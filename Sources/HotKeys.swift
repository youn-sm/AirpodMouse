import Carbon.HIToolbox
import Foundation

/// 전역 단축키 (Carbon RegisterEventHotKey: 손쉬운 사용 권한 없이 동작)
final class HotKeys {
    struct Binding {
        let keyCode: UInt32
        let modifiers: UInt32
        let display: String
        let title: () -> String  // 언어를 바꾸면 바로 반영되게 매번 계산
        let onPress: () -> Void
        let onRelease: (() -> Void)?
    }

    static let shared = HotKeys()
    private var bindings: [UInt32: Binding] = [:]
    private var refs: [EventHotKeyRef] = []
    private var nextID: UInt32 = 1
    private var handlerInstalled = false
    private(set) var all: [Binding] = []

    func register(keyCode: Int, modifiers: Int, display: String, title: @autoclosure @escaping () -> String,
                  onPress: @escaping () -> Void, onRelease: (() -> Void)? = nil) {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x504D5345), id: id) // 'PMSE'
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hkID, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("PodMouse: hotkey \(display) 등록 실패 (\(status)) - 다른 앱이 쓰는 중일 수 있음")
            return
        }
        let b = Binding(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers), display: display, title: title,
                        onPress: onPress, onRelease: onRelease)
        bindings[id] = b
        all.append(b)
        refs.append(ref)
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let kind = GetEventKind(event)
            DispatchQueue.main.async {
                guard let b = HotKeys.shared.bindings[hkID.id] else { return }
                if kind == UInt32(kEventHotKeyPressed) { b.onPress() } else { b.onRelease?() }
            }
            return noErr
        }, specs.count, &specs, nil, nil)
    }
}
