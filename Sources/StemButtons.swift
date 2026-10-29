import AVFoundation
import MediaPlayer

/// 에어팟 기둥 누르기(재생/다음/이전 신호)를 가로채기.
/// macOS는 '지금 재생 중'인 앱에게만 이 신호를 보내므로, 무음 오디오를 틀어 그 자리를 차지함.
/// 켜두면 음악 앱의 재생 버튼 대신 PodMouse 동작이 실행됨.
final class StemButtons {
    var onPress: ((PodTrigger) -> Void)?
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var targets: [Any] = []
    private(set) var isActive = false

    func start() {
        guard !isActive else { return }
        isActive = true
        startSilentAudio()

        let center = MPRemoteCommandCenter.shared()
        let map: [(MPRemoteCommand, PodTrigger)] = [
            (center.togglePlayPauseCommand, .stemSingle),
            (center.playCommand, .stemSingle),
            (center.pauseCommand, .stemSingle),
            (center.nextTrackCommand, .stemDouble),
            (center.previousTrackCommand, .stemTriple),
        ]
        for (cmd, trigger) in map {
            cmd.isEnabled = true
            let t = cmd.addTarget { [weak self] _ in
                DispatchQueue.main.async {
                    self?.onPress?(trigger)
                    MPNowPlayingInfoCenter.default().playbackState = .playing
                }
                return .success
            }
            targets.append((cmd, t))
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "PodMouse",
            MPMediaItemPropertyArtist: L("에어팟 마우스 모드", "AirPods Mouse Mode"),
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
        MPNowPlayingInfoCenter.default().playbackState = .playing
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        for case let (cmd, t) as (MPRemoteCommand, Any) in targets { cmd.removeTarget(t) }
        targets.removeAll()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        player.stop()
        engine.stop()
    }

    private func startSilentAudio() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100) else { return }
        buffer.frameLength = 44100 // 0으로 채워진 1초짜리 무음
        if player.engine == nil { engine.attach(player) }
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            player.play()
        } catch {
            NSLog("PodMouse: silent audio failed \(error)")
        }
    }
}
