import AppKit
import CoreMotion
import Combine

/// 설정창에 보여줄 실시간 센서 값 (10Hz로 갱신)
final class Telemetry: ObservableObject {
    static let shared = Telemetry()
    @Published var connected = false
    @Published var receiving = false
    // 각도는 도, 속도는 도/초, rollDev는 기준 대비 기울기(도)
    @Published var yaw = 0.0
    @Published var pitch = 0.0
    @Published var roll = 0.0
    @Published var yawRate = 0.0
    @Published var pitchRate = 0.0
    @Published var rollDev = 0.0
    @Published var gravity = (x: 0.0, y: 0.0, z: 0.0)
    @Published var lastGesture = "-"
    @Published var cursorMovedByHead = false
    @Published var updateHz = 0.0
}

/// 에어팟 헤드 트래킹 → 커서 이동 + 제스처 인식
final class MotionEngine: NSObject, CMHeadphoneMotionManagerDelegate {
    private let manager = CMHeadphoneMotionManager()
    private let settings = Settings.shared
    private let telemetry = Telemetry.shared

    /// 제스처가 인식되면 호출
    var onGesture: ((PodTrigger) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?

    /// 커서 이동 / 스크롤 모드 (외부에서 켜고 끔)
    var mouseEnabled = true
    var scrollMode = false

    // 이전 프레임 값
    private var last: (yaw: Double, pitch: Double, roll: Double, t: TimeInterval)?
    private var rollBaseline: Double?

    // 커서 부드럽게: 센서는 ~25Hz라서 120Hz 타이머로 보간
    private var pending = CGPoint.zero
    private var subpixel = CGPoint.zero
    private var renderTimer: Timer?

    // 절대 모드: 기준 자세(정면)와 그때의 화면
    private var anchor: (yaw: Double, pitch: Double, screen: CGRect)?
    private var needsAnchor = true
    private var absTarget: CGPoint?
    private var lastSetPos: CGPoint?
    private var mouseMonitors: [Any] = []

    // 조이스틱 모드: 기준 자세, 최신 자세, 키 누름 상태
    private var joyNeutral: (yaw: Double, pitch: Double)?
    private var needsJoyNeutral = true
    private var pose: (yaw: Double, pitch: Double)?
    private var joyLastTick: TimeInterval = 0
    private(set) var joyKeyHeld = false
    // 진단용
    private var joyDebugMag = 0.0
    private var joyDebugBlock = "-"
    private var lastStatusLog: TimeInterval = 0
    private var joyMoveCount = 0

    // 제스처 중 커서가 흔들린 것을 되돌리기 위한 위치 기록
    private var cursorHistory: [(t: TimeInterval, p: CGPoint)] = []

    // 끄덕임 상태
    private var nodSpike: (sign: Double, t: TimeInterval)?
    // 도리도리 상태
    private var shakeSpikes: [(sign: Double, t: TimeInterval)] = []
    private var yawSpikeArmed = true
    // 갸웃 상태
    private var tiltStart: (sign: Double, t: TimeInterval)?
    private var cooldownUntil: TimeInterval = 0

    // 통계
    private var frameCount = 0
    private var frameWindowStart: TimeInterval = 0
    private var lastTelemetryPush: TimeInterval = 0

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    static var authorizationStatus: CMAuthorizationStatus { CMHeadphoneMotionManager.authorizationStatus() }

    func start() {
        manager.delegate = self
        guard manager.isDeviceMotionAvailable else {
            NSLog("PodMouse: headphone motion not available")
            return
        }
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            if let error { NSLog("PodMouse motion error: \(error.localizedDescription)") }
            guard let self, let motion else { return }
            self.handle(motion)
        }
        renderTimer?.invalidate()
        renderTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.renderTick()
        }
        RunLoop.main.add(renderTimer!, forMode: .common)

        // 트랙패드/마우스로 직접 옮기면 그 위치를 새 기준으로 (절대 모드)
        if mouseMonitors.isEmpty {
            let types: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
            let check: (NSEvent) -> Void = { [weak self] e in
                guard let self, e.cgEvent?.getIntegerValueField(.eventSourceUserData) != InputSynth.eventTag else { return }
                if let last = self.lastSetPos, let loc = e.cgEvent?.location, hypot(loc.x - last.x, loc.y - last.y) < 3 { return }
                self.needsAnchor = true
            }
            if let g = NSEvent.addGlobalMonitorForEvents(matching: types, handler: check) { mouseMonitors.append(g) }
            if let l = NSEvent.addLocalMonitorForEvents(matching: types, handler: { check($0); return $0 }) { mouseMonitors.append(l) }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        renderTimer?.invalidate()
        renderTimer = nil
    }

    /// 현재 머리 자세를 기준으로 다시 잡기
    func recalibrate() {
        last = nil
        rollBaseline = nil
        pending = .zero
        subpixel = .zero
        nodSpike = nil
        shakeSpikes.removeAll()
        tiltStart = nil
        needsAnchor = true
        absTarget = nil
        needsJoyNeutral = true
    }

    /// ⌃⌥/ (또는 ⌃⌥ , 꾹 누르기) 를 누르는 순간: 지금 고개 위치를 '멈춤' 기준으로
    func beginJoystickHold() {
        PLog.write("joystick hold begin (pose=\(pose != nil))")
        guard !joyKeyHeld else { return }
        joyKeyHeld = true
        if let pose { joyNeutral = pose; needsJoyNeutral = false } else { needsJoyNeutral = true }
        subpixel = .zero
        joyLastTick = ProcessInfo.processInfo.systemUptime
    }

    /// 진단: 기준을 일부러 10° 옆으로 밀어서 조이스틱이 실제로 커서를 옮기는지 1초간 측정
    func selfTestJoystick(done: @escaping () -> Void) {
        beginJoystickHold()
        if let n = joyNeutral { joyNeutral = (n.yaw + 10, n.pitch) }
        let start = InputSynth.cursor
        joyMoveCount = 0
        PLog.write("joytest begin cursor=(\(Int(start.x)),\(Int(start.y))) neutral=\(String(describing: joyNeutral)) pose=\(String(describing: pose))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let end = InputSynth.cursor
            PLog.write("joytest end cursor=(\(Int(end.x)),\(Int(end.y))) moves=\(self.joyMoveCount) block=\(self.joyDebugBlock) mag=\(self.joyDebugMag)")
            self.endJoystickHold()
            done()
        }
    }

    func endJoystickHold() {
        PLog.write("joystick hold end")
        joyKeyHeld = false
        subpixel = .zero
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

        guard let prev = last else {
            last = (yaw, pitch, roll, now)
            rollBaseline = roll
            return
        }
        let dt = max(now - prev.t, 1.0 / 200.0)
        last = (yaw, pitch, roll, now)
        // 연결이 잠깐 끊겼다 돌아오면 큰 점프가 생기므로 무시
        if dt > 0.5 { return }

        let dYaw = Self.wrap(yaw - prev.yaw)
        let dPitch = pitch - prev.pitch
        let yawRate = dYaw / dt
        let pitchRate = dPitch / dt

        // 기울기 기준점은 천천히 따라감 (갸웃 중에는 고정)
        if rollBaseline == nil { rollBaseline = roll }
        var rollDev = Self.wrap(roll - rollBaseline!)
        if settings.invertTilt { rollDev = -rollDev }
        if tiltStart == nil && abs(rollDev) < settings.tiltAngle * 0.5 {
            rollBaseline = Self.wrap(rollBaseline! + Self.wrap(roll - rollBaseline!) * min(1, dt / 3.0))
        }

        if settings.gesturesEnabled {
            detectGestures(now: now, yawRate: yawRate, pitchRate: pitchRate, rollDev: rollDev)
        }
        accumulateMovement(dYaw: dYaw, dPitch: dPitch, dt: dt)
        if settings.absoluteMode { updateAbsolute(yaw: yaw, pitch: pitch) }
        pose = (yaw, pitch)
        if needsJoyNeutral { joyNeutral = (yaw, pitch); needsJoyNeutral = false }

        if now - lastStatusLog > 1 {
            lastStatusLog = now
            PLog.write(String(format: "status hz=%.0f mouse=%@ mode=%@ key=%@ held=%@ joy=%@ mag=%.1f yaw=%.1f pitch=%.1f roll=%.1f tilt=%@ moves=%d cursor=(%.0f,%.0f)",
                              telemetry.updateHz, mouseEnabled ? "on" : "off", settings.cursorMode,
                              joyKeyHeld ? "down" : "up", InputSynth.heldButton == nil ? "none" : "btn",
                              joyDebugBlock, joyDebugMag, yaw, pitch, roll, tiltStart == nil ? "no" : "yes",
                              joyMoveCount, InputSynth.cursor.x, InputSynth.cursor.y))
            joyMoveCount = 0
        }
        if now - lastTelemetryPush > 0.1 {
            lastTelemetryPush = now
            telemetry.yaw = yaw
            telemetry.pitch = pitch
            telemetry.roll = roll
            telemetry.yawRate = yawRate
            telemetry.pitchRate = pitchRate
            telemetry.rollDev = rollDev
            telemetry.gravity = (m.gravity.x, m.gravity.y, m.gravity.z)
        }
    }

    // MARK: - 커서 이동

    private func accumulateMovement(dYaw: Double, dPitch: Double, dt: Double) {
        guard mouseEnabled || scrollMode else { return }
        // 제스처 판별 중에는 커서를 움직이지 않음 (갸웃 중)
        if tiltStart != nil { return }

        let speed = hypot(dYaw, dPitch) / dt // 도/초
        if speed < settings.deadzone { return }

        // 속도가 빠를수록 더 멀리 (가속 곡선)
        let accel = 1 + settings.acceleration * min(speed / 60.0, 3.0)
        let gain = settings.sensitivity * accel
        var dx = -dYaw * gain   // 고개를 왼쪽으로 돌리면 yaw 증가 → 커서 왼쪽
        var dy = -dPitch * gain // 고개를 들면 pitch 증가 → 커서 위 (CG 좌표는 아래가 +)
        if settings.invertX { dx = -dx }
        if settings.invertY { dy = -dy }

        if scrollMode {
            let s = settings.scrollSpeed / settings.sensitivity
            InputSynth.scroll(dx: Int32((dx * s).rounded()), dy: Int32((-dy * s).rounded()))
            return
        }
        if settings.cursorMode != "relative" { return }
        pending.x += dx
        pending.y += dy
    }

    // MARK: - 절대 모드

    private var signX: Double { settings.invertX ? -1 : 1 }
    private var signY: Double { settings.invertY ? -1 : 1 }

    /// 현재 커서 위치가 지금 머리 자세에 대응하도록 기준점 잡기 (튀지 않게)
    private func setAnchor(cursor cur: CGPoint, yaw: Double, pitch: Double) {
        let screen = Self.displayBounds(containing: cur)
        let dYaw = -Double((cur.x - screen.midX) / (screen.width / 2)) * settings.yawRange * signX
        let dPitch = -Double((cur.y - screen.midY) / (screen.height / 2)) * settings.pitchRange * signY
        anchor = (Self.wrap(yaw - dYaw), pitch - dPitch, screen)
        absTarget = cur
        lastSetPos = cur
    }

    private static func displayBounds(containing p: CGPoint) -> CGRect {
        var id: CGDirectDisplayID = 0
        var count: UInt32 = 0
        CGGetDisplaysWithPoint(p, 1, &id, &count)
        return CGDisplayBounds(count > 0 ? id : CGMainDisplayID())
    }

    private func updateAbsolute(yaw: Double, pitch: Double) {
        guard mouseEnabled, !scrollMode else { return }
        // 갸웃 중에는 멈추고, 끝나면 그 자리에서 다시 기준을 잡음
        if tiltStart != nil { needsAnchor = true; absTarget = nil; return }
        if needsAnchor || anchor == nil {
            needsAnchor = false
            setAnchor(cursor: InputSynth.cursor, yaw: yaw, pitch: pitch)
            return
        }
        guard var a = anchor else { return }
        let ry = settings.yawRange, rp = settings.pitchRange
        var dYaw = Self.wrap(yaw - a.yaw)
        var dPitch = pitch - a.pitch
        // 화면 끝을 넘어 더 돌리면 기준이 따라옴 → 돌아올 때 바로 반응 (드리프트도 이걸로 보정)
        if dYaw > ry { a.yaw = Self.wrap(a.yaw + dYaw - ry); dYaw = ry }
        if dYaw < -ry { a.yaw = Self.wrap(a.yaw + dYaw + ry); dYaw = -ry }
        if dPitch > rp { a.pitch += dPitch - rp; dPitch = rp }
        if dPitch < -rp { a.pitch += dPitch + rp; dPitch = -rp }
        anchor = a

        let s = a.screen
        let x = s.midX + CGFloat(signX * -dYaw / ry) * (s.width / 2)
        let y = s.midY + CGFloat(signY * -dPitch / rp) * (s.height / 2)
        let target = CGPoint(x: min(max(x, s.minX), s.maxX - 1), y: min(max(y, s.minY), s.maxY - 1))
        // 아주 작은 떨림은 무시
        if let prev = absTarget, hypot(target.x - prev.x, target.y - prev.y) < 1.5 { return }
        absTarget = target
    }

    private func renderTick() {
        guard mouseEnabled, !scrollMode else { pending = .zero; return }
        if settings.absoluteMode {
            renderAbsolute()
            return
        }
        if settings.joystickMode {
            renderJoystick()
            return
        }
        guard abs(pending.x) > 0.01 || abs(pending.y) > 0.01 else { return }
        // smoothing 0 → 즉시, 1 → 아주 느리게
        let k = max(0.05, 1 - settings.smoothing)
        let step = CGPoint(x: pending.x * k, y: pending.y * k)
        pending.x -= step.x
        pending.y -= step.y
        subpixel.x += step.x
        subpixel.y += step.y
        let ix = subpixel.x.rounded(.towardZero), iy = subpixel.y.rounded(.towardZero)
        guard ix != 0 || iy != 0 else { return }
        subpixel.x -= ix
        subpixel.y -= iy

        let cur = InputSynth.cursor
        let target = InputSynth.clampToScreens(CGPoint(x: cur.x + ix, y: cur.y + iy))
        InputSynth.move(to: target)
        if !telemetry.cursorMovedByHead { telemetry.cursorMovedByHead = true }

        let now = ProcessInfo.processInfo.systemUptime
        cursorHistory.append((now, target))
        cursorHistory.removeAll { now - $0.t > 1.5 }
    }

    /// 조이스틱: 기준에서 벗어난 각도만큼 속도로 바꿔 계속 이동
    private func renderJoystick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(now - joyLastTick, 0.05)
        joyLastTick = now
        let active = !settings.joyRequiresKey || joyKeyHeld || InputSynth.heldButton != nil
        if !active { joyDebugBlock = "키 안 누름"; return }
        guard let pose, let n = joyNeutral else { joyDebugBlock = "센서 값 없음"; return }
        joyDebugBlock = "동작"

        // 고개는 위아래로 덜 움직이니까 세로를 증폭
        let ox = -Self.wrap(pose.yaw - n.yaw) * signX
        let oy = -(pose.pitch - n.pitch) * signY * settings.verticalBoost
        let mag = hypot(ox, oy)
        joyDebugMag = mag
        let dz = settings.joyDeadzone
        guard mag > dz else { joyDebugBlock = "멈춤 범위 안"; return }
        // 데드존을 벗어난 만큼 0→1. 곡선을 줘서 살짝 기울이면 아주 천천히(정밀), 많이 기울이면 빠르게
        let level = min(1, (mag - dz) / max(1, settings.joyRange - dz))
        let speed = settings.joyMaxSpeed * pow(level, 1.8) + 40 * level
        subpixel.x += CGFloat(ox / mag * speed * dt)
        subpixel.y += CGFloat(oy / mag * speed * dt)
        let ix = subpixel.x.rounded(.towardZero), iy = subpixel.y.rounded(.towardZero)
        guard ix != 0 || iy != 0 else { return }
        subpixel.x -= ix
        subpixel.y -= iy
        let cur = InputSynth.cursor
        let target = InputSynth.clampToScreens(CGPoint(x: cur.x + ix, y: cur.y + iy))
        InputSynth.move(to: target)
        lastSetPos = target
        joyMoveCount += 1
        if !telemetry.cursorMovedByHead { telemetry.cursorMovedByHead = true }
    }

    private func renderAbsolute() {
        guard let target = absTarget, !needsAnchor else { return }
        let cur = lastSetPos ?? InputSynth.cursor
        let dx = target.x - cur.x, dy = target.y - cur.y
        guard hypot(dx, dy) >= 0.5 else { return }
        let k = CGFloat(max(0.05, 1 - settings.smoothing))
        let next = CGPoint(x: (cur.x + dx * k).rounded(), y: (cur.y + dy * k).rounded())
        guard next != cur else { return }
        InputSynth.move(to: next)
        lastSetPos = next
        if !telemetry.cursorMovedByHead { telemetry.cursorMovedByHead = true }
        let now = ProcessInfo.processInfo.systemUptime
        cursorHistory.append((now, next))
        cursorHistory.removeAll { now - $0.t > 1.5 }
    }

    /// 제스처를 하느라 커서가 밀린 만큼 되돌리기
    private func restoreCursor(to t: TimeInterval) {
        pending = .zero
        subpixel = .zero
        guard mouseEnabled, !scrollMode else { return }
        if let entry = cursorHistory.last(where: { $0.t <= t }) {
            InputSynth.move(to: entry.p)
        } else if let first = cursorHistory.first, first.t > t {
            // 기록 시작 전부터 움직였다면 가장 오래된 위치로
            InputSynth.move(to: first.p)
        }
        cursorHistory.removeAll { $0.t > t }
        needsAnchor = true
    }

    // MARK: - 제스처 인식

    private func fire(_ trigger: PodTrigger, now: TimeInterval, restoreTo t: TimeInterval) {
        restoreCursor(to: t)
        cooldownUntil = now + 0.35
        nodSpike = nil
        shakeSpikes.removeAll()
        telemetry.lastGesture = trigger.label
        onGesture?(trigger)
    }

    private func detectGestures(now: TimeInterval, yawRate: Double, pitchRate: Double, rollDev: Double) {
        guard now >= cooldownUntil else { return }

        // 1) 갸웃: 귀를 어깨 쪽으로 기울였다가 다시 돌아오기
        let tiltTh = settings.tiltAngle
        if let ts = tiltStart {
            if abs(rollDev) < tiltTh * 0.4 {
                tiltStart = nil
                let held = now - ts.t
                if held < 1.5 {
                    fire(ts.sign > 0 ? .tiltRight : .tiltLeft, now: now, restoreTo: ts.t - 0.1)
                    return
                }
            } else if now - ts.t > 4 {
                // 너무 오래 기울이고 있으면 자세가 바뀐 것으로 보고 기준점 재설정
                tiltStart = nil
                rollBaseline = nil
            }
            return
        } else if abs(rollDev) > tiltTh {
            tiltStart = (rollDev > 0 ? 1 : -1, now)
            nodSpike = nil
            shakeSpikes.removeAll()
            return
        }

        // 2) 도리도리: 좌우로 빠르게 3번 이상 방향 전환
        let shakeTh = settings.shakeThreshold
        if abs(yawRate) > shakeTh {
            let sign: Double = yawRate > 0 ? 1 : -1
            if yawSpikeArmed || shakeSpikes.last?.sign != sign {
                if shakeSpikes.last?.sign != sign { shakeSpikes.append((sign, now)) }
                yawSpikeArmed = false
            }
        } else if abs(yawRate) < shakeTh * 0.5 {
            yawSpikeArmed = true
        }
        shakeSpikes.removeAll { now - $0.t > 1.0 }
        if shakeSpikes.count >= 3, let first = shakeSpikes.first {
            fire(.shake, now: now, restoreTo: first.t - 0.15)
            return
        }

        // 고개를 좌우로 크게 돌리는 중이면 끄덕임으로 보지 않음
        if abs(yawRate) > shakeTh * 0.7 {
            nodSpike = nil
            return
        }

        // 3) 끄덕임: 위/아래로 빠르게 움직였다가 반대 방향으로 돌아오기
        let nodTh = settings.nodThreshold
        if let spike = nodSpike {
            if now - spike.t > 0.45 {
                nodSpike = nil
            } else if pitchRate * spike.sign < 0 && abs(pitchRate) > nodTh * 0.7 {
                fire(.nod, now: now, restoreTo: spike.t - 0.12)
                return
            }
        }
        if nodSpike == nil && abs(pitchRate) > nodTh {
            nodSpike = (pitchRate > 0 ? 1 : -1, now)
        }
    }
}
