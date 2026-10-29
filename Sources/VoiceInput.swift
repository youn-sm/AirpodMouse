import AppKit
import AVFoundation
import Speech

/// 에어팟(기본 입력 장치) 마이크로 받아쓰기 → 포커스된 창 또는 지정한 앱에 입력
final class VoiceInput {
    private let settings = Settings.shared
    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latestText = ""
    private var finishing = false
    private var finishTimer: DispatchWorkItem?

    private(set) var isListening = false
    var onStateChange: ((Bool) -> Void)?
    var onPartial: ((String) -> Void)?
    var onMessage: ((String) -> Void)?

    static func requestPermissions(_ done: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            AVCaptureDevice.requestAccess(for: .audio) { micOK in
                DispatchQueue.main.async { done(status == .authorized && micOK) }
            }
        }
    }

    func toggle() {
        isListening ? stop() : start()
    }

    func start() {
        guard !isListening, !finishing else { return }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            Self.requestPermissions { [weak self] ok in
                if ok { self?.start() } else { self?.onMessage?(L("마이크/음성 인식 권한이 필요해요 (시스템 설정 → 개인정보 보호)", "Microphone and Speech Recognition access are required (System Settings → Privacy & Security)")) }
            }
            return
        }
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: settings.voiceLocale))
        guard let recognizer, recognizer.isAvailable else {
            onMessage?(L("음성 인식을 사용할 수 없어요 (\(settings.voiceLocale))", "Speech recognition isn't available (\(settings.voiceLocale))"))
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req
        latestText = ""

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            onMessage?(L("마이크 입력 장치를 찾을 수 없어요", "No microphone input device found"))
            return
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak req] buffer, _ in
            req?.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            onMessage?(L("마이크를 시작하지 못했어요: \(error.localizedDescription)", "Couldn't start the microphone: \(error.localizedDescription)"))
            return
        }

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    self.latestText = result.bestTranscription.formattedString
                    self.onPartial?(self.latestText)
                    if result.isFinal { self.deliver() }
                }
                if error != nil && self.finishing { self.deliver() }
            }
        }
        isListening = true
        onStateChange?(true)
    }

    func stop() {
        guard isListening else { return }
        isListening = false
        finishing = true
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        onStateChange?(false)
        // 최종 결과가 늦게 오면 지금까지 들은 걸로 입력
        let work = DispatchWorkItem { [weak self] in self?.deliver() }
        finishTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    func cancel() {
        latestText = ""
        if isListening { stop() }
    }

    private func deliver() {
        guard finishing else { return }
        finishing = false
        finishTimer?.cancel()
        task?.cancel()
        task = nil
        request = nil
        let text = latestText.trimmingCharacters(in: .whitespacesAndNewlines)
        latestText = ""
        guard !text.isEmpty else { onMessage?(L("인식된 말이 없어요", "Didn't catch anything")); return }
        insert(text)
    }

    /// 짧은 음성 명령은 키로 바꿔줌
    private func command(for text: String) -> (() -> Void)? {
        let t = text.lowercased().trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
        switch t {
        case "엔터", "전송", "보내", "enter", "send": return { InputSynth.pressEnter() }
        case "취소", "이스케이프", "escape", "cancel": return { InputSynth.pressEscape() }
        default: return nil
        }
    }

    private func insert(_ text: String) {
        if let cmd = command(for: text) {
            onMessage?(L("명령: \(text)", "Command: \(text)"))
            cmd()
            return
        }
        let doPaste = { [settings] in
            InputSynth.paste(text)
            if settings.autoEnter {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { InputSynth.pressEnter() }
            }
        }
        let bid = settings.voiceTargetBundleID
        if !bid.isEmpty, let app = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first {
            app.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: doPaste)
        } else {
            doPaste()
        }
        onMessage?(L("입력: \(text)", "Typed: \(text)"))
    }
}
