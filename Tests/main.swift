import Foundation

// PointerMath.swift 테스트 (./test.sh 로 실행)

var failures = 0
func check(_ ok: Bool, _ name: String, line: Int = #line) {
    if ok { print("  ok   \(name)") } else { print("  FAIL \(name) (line \(line))"); failures += 1 }
}

print("OneEuroFilter")
do {
    var f = OneEuroFilter(minCutoff: 1.0, beta: 0.05)
    check(f.filter(10, dt: 0.04) == 10, "first sample passes through")
    // 멈춘 상태의 떨림(±0.3°)은 크게 줄어듦
    var outs: [Double] = []
    for i in 0..<100 { outs.append(f.filter(10 + (i % 2 == 0 ? 0.3 : -0.3), dt: 0.04)) }
    let swing = outs.suffix(20).max()! - outs.suffix(20).min()!
    check(swing < 0.3, "jitter amplitude reduced (swing \(String(format: "%.3f", swing)) < 0.3)")
    // 빠르게 움직이면 거의 따라감 (1초 동안 100°/s → 100°)
    f.reset()
    var v = 0.0
    for i in 0...25 { v = f.filter(Double(i) * 4, dt: 0.04) }
    check(100 - v < 12, "fast motion lag small (lag \(String(format: "%.1f", 100 - v))° < 12°)")
    // beta=0이면 같은 속도에서 지연이 더 큼
    var slow = OneEuroFilter(minCutoff: 1.0, beta: 0)
    var w = 0.0
    for i in 0...25 { w = slow.filter(Double(i) * 4, dt: 0.04) }
    check(w < v, "beta reduces lag")
}

print("PointerCurve")
do {
    let c = PointerCurve(sensitivity: 10, acceleration: 3)
    check(c.gain(speed: 0) == 10, "slow speed = base sensitivity")
    check(c.gain(speed: 500) == 40, "fast speed = sensitivity × (1 + acceleration)")
    check(c.gain(speed: 30) < c.gain(speed: 60) && c.gain(speed: 60) < c.gain(speed: 100), "gain increases with speed")
    check(PointerCurve(sensitivity: 10, acceleration: 0).gain(speed: 100) == 10, "acceleration 0 is linear")
}

print("StillnessGate")
do {
    var g = StillnessGate(threshold: 4)
    check(!g.update(speed: 1), "slow drift stays locked")
    check(!g.update(speed: 3.9), "just under threshold stays locked")
    check(g.update(speed: 5), "over threshold unlocks")
    check(g.update(speed: 3), "hysteresis: stays unlocked above half threshold")
    check(!g.update(speed: 1.5), "locks again under half threshold")
}

print("MotionSpreader")
do {
    var s = MotionSpreader()
    s.push(dx: 40, dy: -20, sampleInterval: 0.04)
    var total = (x: 0.0, y: 0.0)
    var steps: [Double] = []
    for _ in 0..<10 {
        let o = s.step(dt: 1.0 / 120)
        total.x += o.x; total.y += o.y
        if o.x != 0 { steps.append(o.x) }
    }
    check(abs(total.x - 40) < 1e-9 && abs(total.y + 20) < 1e-9, "delivers exactly what was pushed")
    check(steps.count >= 4, "spread over several frames (\(steps.count))")
    check(steps.dropLast().allSatisfy { abs($0 - steps[0]) < 1e-6 }, "even steps")
    // 다음 샘플이 늦게 와도 남은 양 없이 끝남, 새 샘플은 이어서 더해짐
    s.push(dx: 10, dy: 0, sampleInterval: 0.04)
    _ = s.step(dt: 0.01)
    s.push(dx: 10, dy: 0, sampleInterval: 0.04)
    var rest = 0.0
    for _ in 0..<20 { rest += s.step(dt: 0.01).x }
    check(abs(rest + 2.5 - 20) < 0.3, "overlapping pushes keep the total")
}

print("DwellDetector")
do {
    var d = DwellDetector(radius: 10, duration: 0.7)
    check(d.update(x: 100, y: 100, t: 0) == .idle, "first position idle")
    check(d.update(x: 100, y: 100, t: 1) == .idle, "doesn't click before moving (not armed)")
    _ = d.update(x: 200, y: 100, t: 1.1) // 움직임 → 준비
    if case .progress(let p) = d.update(x: 203, y: 102, t: 1.45) { check(abs(p - 0.5) < 0.01, "progress halfway") }
    else { check(false, "progress halfway") }
    check(d.update(x: 201, y: 101, t: 1.81) == .fire, "fires after duration within radius")
    check(d.update(x: 201, y: 101, t: 3) == .idle, "doesn't repeat-click in place")
    _ = d.update(x: 260, y: 100, t: 3.1)
    check(d.update(x: 262, y: 100, t: 3.85) == .fire, "re-arms after leaving radius")
    _ = d.update(x: 300, y: 100, t: 4)
    d.disarm()
    check(d.update(x: 300, y: 100, t: 5) == .idle, "disarm prevents click until moved")
}

print(failures == 0 ? "\nAll tests passed" : "\n\(failures) test(s) failed")
exit(failures == 0 ? 0 : 1)
