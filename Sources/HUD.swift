import AppKit
import SwiftUI

final class HUDModel: ObservableObject {
    @Published var text = ""
    @Published var icon = "airpods"
    @Published var listening = false
    @Published var visible = false
}

/// 화면 아래쪽에 뜨는 작은 알림 (포커스를 뺏지 않고 클릭도 통과)
final class HUD {
    static let shared = HUD()
    private let model = HUDModel()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private var holding = false

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 70),
                        styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.contentView = NSHostingView(rootView: HUDView(model: model))
        panel = p
        return p
    }

    private func position(_ p: NSPanel) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let f = screen?.visibleFrame else { return }
        p.setFrameOrigin(NSPoint(x: f.midX - p.frame.width / 2, y: f.minY + 60))
    }

    /// 잠깐 보였다 사라지는 알림
    func flash(_ text: String, icon: String = "airpods", duration: TimeInterval = 1.2) {
        guard Settings.shared.showHUD || model.listening else { return }
        show(text, icon: icon)
        scheduleHide(after: duration)
    }

    /// 음성 입력 중 계속 떠 있는 표시
    func showListening(_ text: String) {
        model.listening = true
        show(text.isEmpty ? L("듣는 중…", "Listening…") : text, icon: "waveform")
        hideWork?.cancel()
    }

    /// 키를 누르고 있는 동안 떠 있는 표시
    func showHold(_ text: String, icon: String) {
        guard !model.listening else { return }
        holding = true
        show(text, icon: icon)
        hideWork?.cancel()
    }

    func endHold() {
        holding = false
        scheduleHide(after: 0.3)
    }

    func endListening() {
        model.listening = false
        scheduleHide(after: 1.0)
    }

    private func show(_ text: String, icon: String) {
        let p = ensurePanel()
        model.text = text
        model.icon = icon
        model.visible = true
        position(p)
        p.orderFrontRegardless()
    }

    private func scheduleHide(after t: TimeInterval) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.model.listening, !self.holding else { return }
            self.model.visible = false
            self.panel?.orderOut(nil)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: work)
    }
}

private struct HUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(model.listening ? Color.red : Color.white)
                .symbolEffect(.pulse, isActive: model.listening)
            Text(model.text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .truncationMode(.head)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Capsule().fill(Color.black.opacity(0.78)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
