import AppKit
import SwiftUI

final class DwellRingModel: ObservableObject {
    @Published var progress = 0.0
}

/// 머무르면 클릭: 커서 주위에 차오르는 링 (클릭은 통과)
final class DwellRing {
    static let shared = DwellRing()
    private static let size: CGFloat = 46
    private let model = DwellRingModel()
    private var panel: NSPanel?
    private var shown = false

    /// nil = 숨기기. 매 화면 프레임마다 불려도 바뀐 게 없으면 아무것도 안 함
    func update(_ progress: Double?, at cgPoint: CGPoint) {
        guard let progress else {
            if shown { panel?.orderOut(nil); shown = false }
            return
        }
        let p = ensurePanel()
        // CG 좌표(주 화면 왼쪽 위 원점) → AppKit 좌표(주 화면 왼쪽 아래 원점)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let origin = NSPoint(x: cgPoint.x - Self.size / 2, y: primaryHeight - cgPoint.y - Self.size / 2)
        if p.frame.origin != origin { p.setFrameOrigin(origin) }
        if abs(model.progress - progress) > 0.01 { model.progress = progress }
        if !shown { p.orderFrontRegardless(); shown = true }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.size, height: Self.size),
                        styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .popUpMenu
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.contentView = NSHostingView(rootView: RingView(model: model))
        panel = p
        return p
    }
}

private struct RingView: View {
    @ObservedObject var model: DwellRingModel

    var body: some View {
        ZStack {
            Circle().stroke(Color.black.opacity(0.25), lineWidth: 5)
            Circle()
                .trim(from: 0, to: model.progress)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(4)
    }
}
