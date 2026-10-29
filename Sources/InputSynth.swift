import AppKit
import CoreGraphics

/// 마우스/키보드 이벤트 합성 (손쉬운 사용 권한 필요)
enum InputSynth {
    private static var lastClickTime: TimeInterval = 0
    private static var lastClickPos: CGPoint = .zero
    private static var clickCount: Int64 = 1
    /// 지금 누르고 있는 버튼 (단축키를 꾹 누르거나 드래그 모드일 때)
    static private(set) var heldButton: CGMouseButton?
    private static var heldClickCount: Int64 = 1
    static var isDragging: Bool { heldButton == .left }

    /// 실제 키보드 상태와 분리된 이벤트 소스. nil 소스를 쓰면 그 순간 눌려 있는 ⌃⌥ 가
    /// 클릭에 섞여 들어가서 Control+클릭(=오른쪽 클릭 취급)이 되어 버튼이 반응하지 않음.
    private static let source = CGEventSource(stateID: .privateState)
    /// 우리가 만든 이벤트 표시 (트랙패드로 직접 움직인 것과 구분용)
    static let eventTag: Int64 = 0x504D_5345

    private static func postMouse(_ type: CGEventType, at p: CGPoint, button: CGMouseButton, clickState: Int64? = nil) {
        guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: button) else { return }
        e.flags = []
        e.setIntegerValueField(.eventSourceUserData, value: eventTag)
        if let clickState { e.setIntegerValueField(.mouseEventClickState, value: clickState) }
        e.post(tap: .cghidEventTap)
    }

    /// 현재 커서 위치 (CG 좌표계: 주 화면 왼쪽 위가 원점)
    static var cursor: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    static func move(to p: CGPoint) {
        let type: CGEventType
        switch heldButton {
        case .left: type = .leftMouseDragged
        case .right: type = .rightMouseDragged
        default: type = .mouseMoved
        }
        postMouse(type, at: p, button: heldButton ?? .left)
    }

    /// 진단: 이동 방식별로 실제 커서가 움직이는지 기록 (--selftest 로 실행했을 때만)
    static func selfTest() {
        func probe(_ name: String, _ post: (CGPoint) -> Void) {
            let start = cursor
            let target = CGPoint(x: start.x + 40, y: start.y)
            post(target)
            usleep(150_000)
            let after = cursor
            PLog.write(String(format: "selftest %@: start=(%.0f,%.0f) target=(%.0f,%.0f) after=(%.0f,%.0f) moved=%@",
                              name, start.x, start.y, target.x, target.y, after.x, after.y,
                              abs(after.x - target.x) < 2 ? "YES" : "NO"))
            CGWarpMouseCursorPosition(start)
            usleep(150_000)
        }
        probe("privateSource") { p in
            CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        probe("privateSource+flags+tag") { p in postMouse(.mouseMoved, at: p, button: .left) }
        probe("nilSource") { p in
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        probe("hidSource") { p in
            CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        probe("warp") { p in CGWarpMouseCursorPosition(p) }

        // ⌃⌥ 를 누르고 있는 상태에서 다시
        let hid = CGEventSource(stateID: .hidSystemState)
        for (code, flag) in [(CGKeyCode(59), CGEventFlags.maskControl), (CGKeyCode(58), CGEventFlags.maskAlternate)] {
            let e = CGEvent(keyboardEventSource: hid, virtualKey: code, keyDown: true)
            e?.type = .flagsChanged
            e?.flags = flag.union(code == 58 ? .maskControl : [])
            e?.post(tap: .cghidEventTap)
        }
        usleep(100_000)
        PLog.write("selftest modifiers now=\(CGEventSource.flagsState(.combinedSessionState).rawValue)")
        probe("withMods privateSource+flags+tag") { p in postMouse(.mouseMoved, at: p, button: .left) }
        probe("withMods nilSource") { p in
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        probe("withMods warp") { p in CGWarpMouseCursorPosition(p) }
        for code in [CGKeyCode(58), CGKeyCode(59)] {
            let e = CGEvent(keyboardEventSource: hid, virtualKey: code, keyDown: false)
            e?.type = .flagsChanged
            e?.flags = []
            e?.post(tap: .cghidEventTap)
        }
    }

    /// 화면 밖으로 나가지 않게 가장 가까운 디스플레이 안으로 고정
    static func clampToScreens(_ p: CGPoint) -> CGPoint {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        let rects = ids.map { CGDisplayBounds($0) }
        if rects.contains(where: { $0.contains(p) }) { return p }
        var best = p
        var bestDist = CGFloat.greatestFiniteMagnitude
        for r in rects {
            let c = CGPoint(x: min(max(p.x, r.minX), r.maxX - 1), y: min(max(p.y, r.minY), r.maxY - 1))
            let dist = hypot(c.x - p.x, c.y - p.y)
            if dist < bestDist { bestDist = dist; best = c }
        }
        return best
    }

    static func mainScreenCenter() -> CGPoint {
        let b = CGDisplayBounds(CGMainDisplayID())
        return CGPoint(x: b.midX, y: b.midY)
    }

    /// 빠르게 연속으로 누르면 더블/트리플 클릭으로 처리되도록 클릭 횟수 계산
    private static func nextClickCount(at p: CGPoint) -> Int64 {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastClickTime < NSEvent.doubleClickInterval && hypot(p.x - lastClickPos.x, p.y - lastClickPos.y) < 8 {
            clickCount += 1
        } else {
            clickCount = 1
        }
        lastClickTime = now
        lastClickPos = p
        return clickCount
    }

    static func leftClick() {
        if isDragging { endDrag(); return }
        let p = cursor
        click(button: .left, down: .leftMouseDown, up: .leftMouseUp, at: p, count: nextClickCount(at: p))
    }

    /// 버튼 누르기 (떼기 전까지 커서를 움직이면 드래그)
    static func buttonDown(_ button: CGMouseButton) {
        if let held = heldButton { buttonUp(held) }
        let p = cursor
        heldClickCount = nextClickCount(at: p)
        heldButton = button
        postMouse(button == .right ? .rightMouseDown : .leftMouseDown, at: p, button: button, clickState: heldClickCount)
    }

    static func buttonUp(_ button: CGMouseButton) {
        guard heldButton == button else { return }
        heldButton = nil
        postMouse(button == .right ? .rightMouseUp : .leftMouseUp, at: cursor, button: button, clickState: heldClickCount)
    }

    static func doubleClick() {
        let p = cursor
        click(button: .left, down: .leftMouseDown, up: .leftMouseUp, at: p, count: 1)
        click(button: .left, down: .leftMouseDown, up: .leftMouseUp, at: p, count: 2)
        lastClickTime = 0
    }

    static func rightClick() {
        click(button: .right, down: .rightMouseDown, up: .rightMouseUp, at: cursor, count: 1)
    }

    private static func click(button: CGMouseButton, down: CGEventType, up: CGEventType, at p: CGPoint, count: Int64) {
        postMouse(down, at: p, button: button, clickState: count)
        postMouse(up, at: p, button: button, clickState: count)
    }

    static func beginDrag() {
        guard !isDragging else { return }
        buttonDown(.left)
    }

    static func endDrag() {
        guard isDragging else { return }
        buttonUp(.left)
    }

    static func scroll(dx: Int32, dy: Int32) {
        guard let e = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) else { return }
        e.flags = []
        e.post(tap: .cghidEventTap)
    }

    static func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
            e.flags = flags
            e.post(tap: .cghidEventTap)
        }
    }

    static func pressEnter() { key(36) }
    static func pressEscape() { key(53) }

    /// 클립보드를 잠깐 빌려서 붙여넣기 (한글도 안정적으로 들어감). 원래 클립보드는 복구.
    static func paste(_ text: String, completion: (() -> Void)? = nil) {
        let pb = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]] = (pb.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let data = item.data(forType: t) { dict[t] = data } }
            return dict
        }
        pb.clearContents()
        pb.setString(text, forType: .string)
        key(9, flags: .maskCommand) // ⌘V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pb.clearContents()
            let items = saved.map { dict -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (t, data) in dict { item.setData(data, forType: t) }
                return item
            }
            if !items.isEmpty { pb.writeObjects(items) }
            completion?()
        }
    }
}
