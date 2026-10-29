import AppKit
import CoreMotion
import Combine
import QuartzCore

/// 설정창에 보여줄 실시간 센서 값 (10Hz로 갱신)
final class Telemetry: ObservableObject {
    static let shared = Telemetry()
    @Published var connected = false
    @Published var receiving = false
    // 각도는 도, 속도는 도/초
    @Published var yaw = 0.0
    @Published var pitch = 0.0
    @Published var roll = 0.0
    @Published var yawRate = 0.0
    @Published var pitchRate = 0.0
    /// 걸러진 고개 회전 속도와 커서 고정 여부 (멈춤 기준을 맞출 때 참고)
    @Published var speed = 0.0
    @Published var still = true
    @Published var gravity = (x: 0.0, y: 0.0, z: 0.0)
    @Published var cursorMovedByHead = false
    @Published var updateHz = 0.0
}

/// 에어팟 헤드 트래킹 → 커서 이동 (상대 모드) + 머무르면 클릭
///
/// 센서(~25Hz) → One Euro 필터 → 멈춤 고정 → 가속 곡선 → 화면 갱신마다 고르게 나눠 이동
final class MotionEngine: NSObject, CMHeadphoneMotionManagerDelegate {
    private let manager = CMHeadphoneMotionManager()
    private let settings = Settings.shared
    private let telemetry = Telemetry.shared

    var onConnectionChange: ((Bool) -> Void)?
    /// 머무르면 클릭: 진행률(0~1, nil = 숨김)과 클릭 순간
    var onDwellProgress: ((Double?) -> Void)?
    var onDwellFire: (() -> Void)?

    /// 커서 이동 / 스크롤 모드 (외부에서 켜고 끔)
    var mouseEnabled = true
    var scrollMode = false

    // 이전 프레임: 감은 각도를 펼친 값(yaw가 ±180°에서 튀지 않게)과 시각
    private var last: (yaw: Double, pitch: Double, t: TimeInterval)?
    private var unwrappedYaw = 0.0
    private var rawYaw: Double?
    private var filtered: (yaw: Double, pitch: Double)?
    private var yawFilter = OneEuroFilter(minCutoff: 1.5, beta: 0.04)
    private var pitchFilter = OneEuroFilter(minCutoff: 1.5, beta: 0.04)
    private var gate = StillnessGate(threshold: 4)
    private var spreader = MotionSpreader()
    private var dwell = DwellDetector(radius: 10, duration: 0.7)
    private var subpixel = CGPoint.zero

    private var displayLink: CADisplayLink?
    private var lastTick: CFTimeInterval = 0

    // 통계
    private var frameCount = 0
    private var frameWindowStart: TimeInterval = 0
    private var lastTelemetryPush: TimeInterval = 0
    private var lastStatusLog: TimeInterval = 0

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    static var authorizationStatus: CMAuthorizationStatus { CMHeadphoneMotionManager.authorizationStatus() }

    func start() {
        manager.delegate = self
        guard manager.isDeviceMotionAvailable else {
            NSLog("AirpodMouse: headphone motion not available")
            return
        }
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            if let error { NSLog("AirpodMouse motion error: \(error.localizedDescription)") }
            guard let self, let motion else { return }
            self.handle(motion)
        }
        startDisplayLink()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        displayLink?.invalidate()
        displayLink = nil
    }

    /// 화면 주사율에 맞춰 커서를 움직임 (Timer보다 프레임 간격이 고름)
    private func startDisplayLink() {
        displayLink?.invalidate()
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let link = screen.displayLink(target: self, selector: #selector(renderTick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTick = 0
    }

    @objc private func screensChanged() {
        if displayLink != nil { startDisplayLink() }
    }

    /// 현재 머리 자세를 기준으로 다시 잡기
    func recalibrate() {
        last = nil
        rawYaw = nil
        filtered = nil
        yawFilter.reset()
        pitchFilter.reset()
        gate.reset()
        spreader.reset()
        subpixel = .zero
        resetDwell()
    }

    /// 다른 방법으로 클릭했을 때: 그 자리에서 머무르면 클릭이 또 눌리지 않게
    func resetDwell() {
        dwell.disarm()
        onDwellProgress?(nil)
    }

    // MARK: - CMHeadphoneMotionManagerDelegate

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        PLog.write("headphones connected")
        telemetry.connected = true
        recalibrate()
        onConnectionChange?(true)
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        PLog.write("headphones disconnected")
        telemetry.connected = false
        telemetry.receiving = false
        onConnectionChange?(false)
    }

    // MARK: - 센서 처리

    private static func deg(_ r: Double) -> Double { r * 180 / .pi }

    /// -180~180 범위로 감기
    private static func wrap(_ a: Double) -> Double {
        var x = a.truncatingRemainder(dividingBy: 360)
        if x > 180 { x -= 360 }
        if x < -180 { x += 360 }
        return x
    }

    /// 0(가장 약하게)~1(가장 강하게) 떨림 거르기 → One Euro 최소 차단 주파수
    private static func minCutoff(smoothing: Double) -> Double {
        4.0 + (0.4 - 4.0) * min(max(smoothing, 0), 1)
    }

    private func handle(_ m: CMDeviceMotion) {
        let now = ProcessInfo.processInfo.systemUptime
        let yaw = Self.deg(m.attitude.yaw)
        let pitch = Self.deg(m.attitude.pitch)
        let roll = Self.deg(m.attitude.roll)

        frameCount += 1
        if now - frameWindowStart >= 1 {
            telemetry.updateHz = Double(frameCount) / (now - frameWindowStart)
            frameCount = 0
            frameWindowStart = now
        }
        if !telemetry.receiving { telemetry.receiving = true; telemetry.connected = true }

        // yaw는 ±180°에서 감기므로 변화량을 쌓아서 연속된 값으로
        if let r = rawYaw { unwrappedYaw += Self.wrap(yaw - r) } else { unwrappedYaw = yaw }
        rawYaw = yaw

        let dt = last.map { now - $0.t } ?? 0
        // 처음이거나 연결이 잠깐 끊겼다 돌아오면 큰 점프가 생기므로 새로 시작
        if last == nil || dt > 0.5 {
            last = (unwrappedYaw, pitch, now)
            yawFilter.reset()
            pitchFilter.reset()
            filtered = (yawFilter.filter(unwrappedYaw, dt: 0), pitchFilter.filter(pitch, dt: 0))
            return
        }
        let step = max(dt, 1.0 / 200.0)
        let rawRates = ((unwrappedYaw - last!.yaw) / step, (pitch - last!.pitch) / step)
        last = (unwrappedYaw, pitch, now)

        let cutoff = Self.minCutoff(smoothing: settings.smoothing)
        yawFilter.minCutoff = cutoff
        pitchFilter.minCutoff = cutoff
        let fy = yawFilter.filter(unwrappedYaw, dt: step)
        let fp = pitchFilter.filter(pitch, dt: step)
        let prev = filtered ?? (fy, fp)
        filtered = (fy, fp)
        let dYaw = fy - prev.yaw
        let dPitch = fp - prev.pitch
        let speed = hypot(dYaw, dPitch) / step

        gate.threshold = settings.stillness
        let moving = gate.update(speed: speed)
        if moving { move(dYaw: dYaw, dPitch: dPitch, speed: speed, dt: step) }

        if now - lastStatusLog > 5 {
            lastStatusLog = now
            PLog.write(String(format: "status hz=%.0f mouse=%@ scroll=%@ speed=%.1f still=%@ yaw=%.1f pitch=%.1f",
                              telemetry.updateHz, mouseEnabled ? "on" : "off", scrollMode ? "on" : "off",
                              speed, moving ? "no" : "yes", yaw, pitch))
        }
        if now - lastTelemetryPush > 0.1 {
            lastTelemetryPush = now
            telemetry.yaw = yaw
            telemetry.pitch = pitch
            telemetry.roll = roll
            telemetry.yawRate = rawRates.0
            telemetry.pitchRate = rawRates.1
            telemetry.speed = speed
            telemetry.still = !moving
            telemetry.gravity = (m.gravity.x, m.gravity.y, m.gravity.z)
        }
    }

    // MARK: - 커서 이동

    private func move(dYaw: Double, dPitch: Double, speed: Double, dt: Double) {
        guard mouseEnabled || scrollMode else { return }
        let gain = PointerCurve(sensitivity: settings.sensitivity, acceleration: settings.acceleration).gain(speed: speed)
        var dx = -dYaw * gain   // 고개를 왼쪽으로 돌리면 yaw 증가 → 커서 왼쪽
        var dy = -dPitch * gain // 고개를 들면 pitch 증가 → 커서 위 (CG 좌표는 아래가 +)
        if settings.invertX { dx = -dx }
        if settings.invertY { dy = -dy }

        if scrollMode {
            let s = settings.scrollSpeed / settings.sensitivity
            InputSynth.scroll(dx: Int32((dx * s).rounded()), dy: Int32((-dy * s).rounded()))
            return
        }
        spreader.push(dx: dx, dy: dy, sampleInterval: dt)
    }

    @objc private func renderTick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastTick == 0 ? link.duration : min(now - lastTick, 0.05)
        lastTick = now
        guard mouseEnabled, !scrollMode else {
            spreader.reset()
            onDwellProgress?(nil)
            return
        }

        let step = spreader.step(dt: dt)
        subpixel.x += step.x
        subpixel.y += step.y
        let ix = subpixel.x.rounded(.towardZero), iy = subpixel.y.rounded(.towardZero)
        var cur = InputSynth.cursor
        if ix != 0 || iy != 0 {
            subpixel.x -= ix
            subpixel.y -= iy
            cur = InputSynth.clampToScreens(CGPoint(x: cur.x + ix, y: cur.y + iy))
            InputSynth.move(to: cur)
            if !telemetry.cursorMovedByHead { telemetry.cursorMovedByHead = true }
        }
        updateDwell(at: cur)
    }

    // MARK: - 머무르면 클릭

    private func updateDwell(at p: CGPoint) {
        guard settings.dwellEnabled else { onDwellProgress?(nil); return }
        dwell.radius = settings.dwellRadius
        dwell.duration = settings.dwellTime
        switch dwell.update(x: p.x, y: p.y, t: ProcessInfo.processInfo.systemUptime) {
        case .idle:
            onDwellProgress?(nil)
        case .progress(let f):
            // 아주 잠깐 멈춘 것까지 링을 띄우면 정신없으니 조금 지나서부터 보여줌
            onDwellProgress?(f < 0.15 ? nil : f)
        case .fire:
            onDwellProgress?(nil)
            onDwellFire?()
        }
    }
}
