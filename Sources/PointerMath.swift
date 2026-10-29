import Foundation

// 커서 계산에 쓰는 순수 로직 (AppKit 없이 테스트 가능: ./test.sh)

/// One Euro 필터 (Casiez 2012): 천천히 움직일 땐 떨림을 강하게 거르고, 빠르게 움직일 땐 지연을 줄임
struct OneEuroFilter {
    /// 멈춰 있을 때의 차단 주파수(Hz). 낮을수록 떨림을 더 거르지만 반응이 느려짐
    var minCutoff: Double
    /// 속도에 따라 차단 주파수를 올리는 정도. 높을수록 빠른 움직임에서 지연이 줄어듦
    var beta: Double
    var dCutoff = 1.0
    private var x: Double?
    private var dx = 0.0

    init(minCutoff: Double, beta: Double) {
        self.minCutoff = minCutoff
        self.beta = beta
    }

    mutating func reset() {
        x = nil
        dx = 0
    }

    mutating func filter(_ value: Double, dt: Double) -> Double {
        guard let prev = x, dt > 0 else { x = value; return value }
        dx += Self.alpha(dCutoff, dt) * ((value - prev) / dt - dx)
        let cutoff = minCutoff + beta * abs(dx)
        let out = prev + Self.alpha(cutoff, dt) * (value - prev)
        x = out
        return out
    }

    private static func alpha(_ cutoff: Double, _ dt: Double) -> Double {
        let tau = 1 / (2 * .pi * cutoff)
        return 1 / (1 + tau / dt)
    }
}

/// 고개 회전 속도(°/s) → 커서 이득(px/°). 느리면 정밀하게, 빠르면 멀리 (부드러운 S자 가속)
struct PointerCurve {
    var sensitivity: Double  // 느릴 때 px/°
    var acceleration: Double // 빠를 때 이득 = sensitivity × (1 + acceleration)
    var slowSpeed = 8.0      // 이 속도 이하는 가속 없음
    var fastSpeed = 120.0    // 이 속도 이상은 최대 가속

    func gain(speed: Double) -> Double {
        let t = min(max((speed - slowSpeed) / (fastSpeed - slowSpeed), 0), 1)
        let s = t * t * (3 - 2 * t)
        return sensitivity * (1 + acceleration * s)
    }
}

/// 고개가 거의 멈추면 커서를 완전히 고정 (느린 드리프트·미세 떨림 흡수).
/// 풀릴 때와 잠길 때 기준이 달라서 경계에서 깜빡이지 않음
struct StillnessGate {
    var threshold: Double // 이 속도(°/s)를 넘으면 움직이기 시작
    private(set) var locked = true

    init(threshold: Double) { self.threshold = threshold }

    /// 움직여도 되면 true
    mutating func update(speed: Double) -> Bool {
        if locked {
            if speed > threshold { locked = false }
        } else if speed < threshold * 0.5 {
            locked = true
        }
        return !locked
    }

    mutating func reset() { locked = true }
}

/// 센서는 ~25Hz라서, 한 프레임 분량의 이동을 다음 프레임이 올 때까지 화면 갱신마다 고르게 나눠 보냄
struct MotionSpreader {
    /// 센서 프레임 간격 추정치 (초). 실제 간격으로 계속 갱신
    private(set) var interval = 0.04
    private var remaining = (x: 0.0, y: 0.0)
    private var timeLeft = 0.0

    mutating func push(dx: Double, dy: Double, sampleInterval: Double) {
        interval += (min(max(sampleInterval, 0.01), 0.1) - interval) * 0.1
        remaining.x += dx
        remaining.y += dy
        timeLeft = interval
    }

    /// 화면 한 프레임(dt초) 동안 보낼 이동량
    mutating func step(dt: Double) -> (x: Double, y: Double) {
        let f = timeLeft > dt ? dt / timeLeft : 1
        let out = (x: remaining.x * f, y: remaining.y * f)
        remaining.x -= out.x
        remaining.y -= out.y
        timeLeft = max(0, timeLeft - dt)
        return out
    }

    mutating func reset() {
        remaining = (0, 0)
        timeLeft = 0
    }
}

/// 커서가 반경 안에 일정 시간 머물면 클릭. 한 번 클릭하면 반경 밖으로 나갔다 와야 다시 준비됨
struct DwellDetector {
    enum Output: Equatable {
        case idle
        case progress(Double) // 0~1
        case fire
    }

    var radius: Double
    var duration: Double
    private var anchor: (x: Double, y: Double)?
    private var since = 0.0
    private var armed = false

    init(radius: Double, duration: Double) {
        self.radius = radius
        self.duration = duration
    }

    mutating func update(x: Double, y: Double, t: Double) -> Output {
        guard let a = anchor, hypot(x - a.x, y - a.y) <= radius else {
            // 처음이거나 반경을 벗어남 → 여기서 새로 시작
            if anchor != nil { armed = true }
            anchor = (x, y)
            since = t
            return .idle
        }
        guard armed else { return .idle }
        let p = (t - since) / duration
        if p >= 1 {
            armed = false
            return .fire
        }
        return .progress(p)
    }

    /// 다른 방법으로 클릭했거나 켜는 순간: 움직이기 전까지 클릭하지 않음
    mutating func disarm() {
        armed = false
        anchor = nil
    }
}
