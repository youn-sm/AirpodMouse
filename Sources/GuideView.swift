import AppKit
import SwiftUI

/// 실행하면 뜨는 메인 창: 시작하기 / 조작법 / 설정
struct MainView: View {
    let controller: AppController
    @ObservedObject var state = AppState.shared
    @ObservedObject var settings = Settings.shared

    var body: some View {
        TabView(selection: $state.guideTab) {
            StartView(controller: controller)
                .tabItem { Label(L("시작하기", "Get Started"), systemImage: "play.circle") }
                .tag(0)
            ControlsView(controller: controller)
                .tabItem { Label(L("조작법", "Controls"), systemImage: "hand.point.up.left") }
                .tag(1)
            SettingsView(controller: controller)
                .tabItem { Label(L("설정", "Settings"), systemImage: "slider.horizontal.3") }
                .tag(2)
        }
        .padding(.top, 8)
        .frame(minWidth: 680, minHeight: 720)
    }
}

// MARK: - 시작하기

private struct StartView: View {
    let controller: AppController
    @ObservedObject var state = AppState.shared
    @ObservedObject var settings = Settings.shared
    @ObservedObject var t = Telemetry.shared

    private struct Step: Identifiable {
        let id: Int
        let title: String
        let how: String
        let done: Bool
        var button: (String, () -> Void)? = nil
    }

    private var steps: [Step] {
        let a = { settings.action(for: $0).label }
        return [
            Step(id: 1, title: L("손쉬운 사용 권한 허용", "Allow Accessibility access"), how: L("커서를 움직이고 클릭하려면 필요해요. 시스템 설정에서 AirpodMouse를 켜주세요.", "Needed to move the cursor and click. Turn on AirpodMouse in System Settings."),
                 done: state.accessibilityOK,
                 button: state.accessibilityOK ? nil : (L("설정 열기", "Open Settings"), {
                     controller.checkAccessibility(prompt: true)
                     NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                 })),
            Step(id: 2, title: L("에어팟 귀에 착용", "Put your AirPods in"), how: L("이 Mac에 연결된 채로 끼면 헤드 트래킹이 시작돼요. 처음엔 '동작 및 피트니스' 권한을 물어봐요.", "Head tracking starts once they're in your ears and connected to this Mac. The first time, macOS asks for Motion & Fitness access."),
                 done: t.receiving),
            Step(id: 3, title: L("마우스 모드 켜기", "Turn on mouse mode"), how: L("⌃⌥M 을 누르세요. 다시 누르면 꺼져요.", "Press ⌃⌥M. Press it again to turn it off."),
                 done: state.mouseEnabled,
                 button: state.mouseEnabled ? nil : (L("지금 켜기", "Turn On"), { controller.setMouse(true) })),
            Step(id: 4, title: L("고개를 돌리기 → 커서 이동", "Turn your head → the cursor moves"),
                 how: L("트랙패드처럼 움직인 만큼 가요. 천천히 = 정밀하게, 빠르게 = 멀리. 고개를 멈추면 커서도 멈춰요. 어긋나면 정면을 보고 ⌃⌥R.", "Like a trackpad, it moves as much as you move. Slow = precise, fast = far. Stop your head and the cursor stops. If it's off, face forward and press ⌃⌥R."),
                 done: t.cursorMovedByHead),
            Step(id: 5, title: L("⌃⌥ , (쉼표) → 왼쪽 클릭", "⌃⌥ , (comma) → left click"), how: L("아래 연습 영역에 커서를 두고 Control+Option+쉼표. 꾹 누른 채 고개를 움직이면 드래그돼요. 빠르게 두 번 = 더블클릭.", "Put the cursor over the practice area below and press Control+Option+Comma. Hold it and move your head to drag. Press twice quickly to double-click."),
                 done: state.practiced.contains("hotkeyLeft")),
            Step(id: 6, title: L("⌃⌥ . (마침표) → 오른쪽 클릭", "⌃⌥ . (period) → right click"), how: L("Control+Option+마침표. 쉼표 바로 오른쪽 키예요.", "Control+Option+Period — the key right next to the comma."),
                 done: state.practiced.contains("hotkeyRight")),
            Step(id: 7, title: L("에어팟 기둥 1번 → \(a(.stemSingle)),  2번 → \(a(.stemDouble))", "AirPods stem ×1 → \(a(.stemSingle)),  ×2 → \(a(.stemDouble))"),
                 how: L("마우스 모드가 켜져 있을 때만 동작해요 (꺼지면 음악 재생/정지로 돌아가요). 양쪽 어느 에어팟을 눌러도 같아요.", "Only works while mouse mode is on (otherwise it's play/pause again). Either AirPod works the same."),
                 done: state.practiced.contains(PodTrigger.stemSingle.rawValue) || state.practiced.contains(PodTrigger.stemDouble.rawValue)),
            Step(id: 8, title: L("⌃⌥W 또는 기둥 3번 → 머무르면 클릭", "⌃⌥W or stem ×3 → dwell click"),
                 how: L("켠 뒤 연습 영역 위에서 커서를 멈추면 링이 차오르고 클릭돼요. 손을 쓰지 않을 때 좋아요. 같은 방법으로 끄세요.", "Turn it on, then hold the cursor still over the practice area: a ring fills up and it clicks. Great when your hands are busy. Turn it off the same way."),
                 done: state.practiced.contains("dwell"),
                 button: settings.dwellEnabled ? nil : (L("켜기", "Turn On"), { controller.setDwell(true) })),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                checklist
                PracticePad()
                footer
            }
            .padding(24)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "airpods.gen4")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text("AirpodMouse").font(.largeTitle.bold())
                Text(L("에어팟을 낀 채로 고개로 커서를 움직이고, 단축키·기둥 누르기·머무르기로 클릭해요.", "Move the cursor with your head and click with shortcuts, stem presses, or by holding still — just by wearing your AirPods."))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                controller.setMouse(!state.mouseEnabled)
            } label: {
                Label(state.mouseEnabled ? L("마우스 모드 켜짐", "Mouse Mode On") : L("마우스 모드 꺼짐", "Mouse Mode Off"),
                      systemImage: state.mouseEnabled ? "cursorarrow.motionlines" : "cursorarrow.slash")
                    .frame(minWidth: 150)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(state.mouseEnabled ? .green : .gray)
            .controlSize(.large)
        }
    }

    private var checklist: some View {
        let s = steps
        let done = s.filter(\.done).count
        return GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(L("따라 해보기", "Try It Step by Step")).font(.headline)
                    Spacer()
                    Text("\(done) / \(s.count)").monospacedDigit().foregroundStyle(.secondary)
                    ProgressView(value: Double(done), total: Double(s.count)).frame(width: 120)
                }
                .padding(.bottom, 8)
                ForEach(s) { step in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: step.done ? "checkmark.circle.fill" : "\(step.id).circle")
                            .font(.title2)
                            .foregroundStyle(step.done ? Color.green : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title).font(.body.weight(.semibold))
                                .strikethrough(step.done, color: .secondary)
                            Text(step.how).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if let (title, action) = step.button {
                            Button(title, action: action)
                        }
                    }
                    .padding(.vertical, 7)
                    if step.id != s.count { Divider() }
                }
            }
            .padding(6)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(L("실행할 때 이 창 보기", "Show this window at launch"), isOn: $settings.showGuideOnLaunch)
            Text(L("창을 닫아도 앱은 메뉴바(화면 오른쪽 위 에어팟 아이콘)에서 계속 실행돼요. 아이콘 → '사용 안내 열기'로 다시 볼 수 있어요.", "Closing this window keeps the app running in the menu bar (the AirPods icon at the top right). Choose 'Open Guide…' from the icon to see it again."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 연습 영역

/// 연습 영역 카운터 (Command Line Tools에는 SwiftUI @State 매크로가 없어서 ObservableObject로 보관)
private final class PracticeModel: ObservableObject {
    static let shared = PracticeModel()
    @Published var left = 0
    @Published var right = 0
    @Published var double = 0
    @Published var flashText = ""
    @Published var flashOn = false
}

private struct PracticePad: View {
    @ObservedObject var state = AppState.shared
    @ObservedObject var settings = Settings.shared
    @ObservedObject var t = Telemetry.shared
    @ObservedObject var m = PracticeModel.shared

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L("연습 영역", "Practice Area")).font(.headline)
                    Spacer()
                    Button(L("기록 지우기", "Reset")) {
                        m.left = 0; m.right = 0; m.double = 0
                        state.practiced.removeAll()
                        t.cursorMovedByHead = false
                    }
                    .controlSize(.small)
                }
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(m.flashOn ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    ClickCatcher { kind in
                        switch kind {
                        case .left(let count):
                            if count >= 2 { m.double += 1; flash(L("더블 클릭!", "Double click!")) } else { m.left += 1; flash(L("왼쪽 클릭!", "Left click!")) }
                        case .right:
                            m.right += 1; flash(L("오른쪽 클릭!", "Right click!"))
                        }
                    }
                    VStack(spacing: 10) {
                        Text(m.flashText.isEmpty ? L("커서를 여기에 두고 ⌃⌥ , 또는 ⌃⌥ . 를 눌러보세요", "Put the cursor here and press ⌃⌥ , or ⌃⌥ .") : m.flashText)
                            .font(.title2.weight(.semibold))
                        HStack(spacing: 24) {
                            counter(L("왼쪽", "Left"), m.left)
                            counter(L("오른쪽", "Right"), m.right)
                            counter(L("더블", "Double"), m.double)
                        }
                        Text(L("마지막 입력: \(state.lastInput ?? "-")", "Last input: \(state.lastInput ?? "-")"))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .allowsHitTesting(false)
                }
                .frame(height: 190)
                Text(L("에어팟 기둥을 1번 / 2번 누르거나, 머무르면 클릭을 켜고 커서를 멈춰서도 해보세요 (마우스 모드가 켜져 있어야 해요).", "Also try pressing an AirPods stem once or twice, or turn on dwell click and hold the cursor still (mouse mode must be on)."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(6)
        }
    }

    private func counter(_ label: String, _ n: Int) -> some View {
        VStack {
            Text("\(n)").font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func flash(_ text: String) {
        m.flashText = text
        withAnimation(.easeOut(duration: 0.1)) { m.flashOn = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeIn(duration: 0.3)) { m.flashOn = false }
        }
    }
}

/// 왼쪽/오른쪽 클릭을 구분해서 받는 뷰
private struct ClickCatcher: NSViewRepresentable {
    enum Kind { case left(Int), right }
    let onClick: (Kind) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let v = CatcherView()
        v.onClick = onClick
        return v
    }

    func updateNSView(_ v: CatcherView, context: Context) { v.onClick = onClick }

    final class CatcherView: NSView {
        var onClick: ((Kind) -> Void)?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { onClick?(.left(event.clickCount)) }
        override func rightMouseDown(with event: NSEvent) { onClick?(.right) }
    }
}

// MARK: - 조작법

private struct ControlsView: View {
    let controller: AppController
    @ObservedObject var settings = Settings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section(L("클릭", "Clicking")) {
                    infoRow("keyboard", L("⌃⌥ ,  (Control + Option + 쉼표)  →  왼쪽 클릭", "⌃⌥ ,  (Control + Option + Comma)  →  Left click"),
                            L("빠르게 두 번 = 더블클릭. 꾹 누른 채로 고개를 살짝 기울이면 드래그, 떼면 놓아져요.", "Press twice quickly to double-click. Hold and tilt your head slightly to drag; release to drop."))
                    infoRow("keyboard", L("⌃⌥ .  (Control + Option + 마침표)  →  오른쪽 클릭", "⌃⌥ .  (Control + Option + Period)  →  Right click"), nil)
                    infoRow("hand.tap", L("에어팟 기둥 1번 누르기  →  \(settings.action(for: .stemSingle).label)", "Press AirPods stem once  →  \(settings.action(for: .stemSingle).label)"), nil)
                    infoRow("hand.tap", L("에어팟 기둥 2번 누르기  →  \(settings.action(for: .stemDouble).label)", "Press AirPods stem twice  →  \(settings.action(for: .stemDouble).label)"), nil)
                    infoRow("hand.tap", L("에어팟 기둥 3번 누르기  →  \(settings.action(for: .stemTriple).label)", "Press AirPods stem three times  →  \(settings.action(for: .stemTriple).label)"), nil)
                    Text(L("macOS는 왼쪽·오른쪽 에어팟 중 어느 쪽을 눌렀는지 알려주지 않아요. 그래서 누른 횟수로 구분해요. 에어팟이 2번 누르기인지 기다렸다가 신호를 보내서, 1번 누르기는 약간(0.3~0.5초) 늦게 클릭돼요.", "macOS doesn't report which AirPod (left or right) was pressed, so presses are told apart by count. AirPods wait to see whether a second press is coming before sending the signal, so a single press clicks slightly late (0.3–0.5 s)."))
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text(settings.captureStem ? L("기둥 누르기 클릭: 켜짐 · 마우스 모드일 때만 동작하고, 꺼지면 음악 재생/정지로 돌아가요.", "Stem clicks: On · only while mouse mode is on; otherwise it's play/pause again.")
                                                  : L("기둥 누르기 클릭: 꺼짐 · 켜면 마우스 모드일 때 재생/정지 대신 클릭이 돼요.", "Stem clicks: Off · turn on to click instead of play/pause while in mouse mode."))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Toggle(L("사용", "Enabled"), isOn: Binding(get: { settings.captureStem }, set: { controller.setStemCapture($0) }))
                            .toggleStyle(.switch)
                    }
                    infoRow("smallcircle.filled.circle", L("머무르면 클릭 (⌃⌥W)", "Dwell click (⌃⌥W)"),
                            String(format: L("커서를 %.0fpx 안에 %.1f초 두면 왼쪽 클릭. 링이 차오르는 동안 움직이면 취소돼요. 손을 전혀 안 쓸 땐 기둥 3번으로 켜고 끄세요.", "Keep the cursor within %.0f px for %.1f s to left-click. Move while the ring fills to cancel. Fully hands-free? Toggle it with stem ×3."), settings.dwellRadius, settings.dwellTime))
                }

                section(L("커서 이동", "Moving the Cursor")) {
                    infoRow("move.3d", L("고개 돌리기 / 들기 · 숙이기", "Turn / raise / lower your head"),
                            L("트랙패드처럼 움직인 만큼 이동해요. 천천히 = 정밀하게, 빠르게 = 멀리. 고개를 멈추면 커서가 그 자리에 고정돼서 떨리지 않아요.", "Like a trackpad, the cursor moves as much as you move. Slow = precise, fast = far. Stop and the cursor locks in place so it doesn't shake."))
                    infoRow("scope", L("⌃⌥R  →  기준 재설정 + 커서 정중앙", "⌃⌥R  →  Reset + center the cursor"),
                            L("커서가 엉뚱한 곳에 있을 때 정면을 보고 누르세요. 마우스 모드를 켤 때도 커서가 정중앙에서 시작해요.", "Face forward and press it when the cursor is somewhere odd. Turning on mouse mode also starts the cursor at the center."))
                    infoRow("dial.medium", L("⌃⌥= / ⌃⌥-  →  감도 올리기 / 내리기", "⌃⌥= / ⌃⌥-  →  More / less sensitive"),
                            L("고개를 너무 많이 움직여야 하면 올리고, 너무 휙휙 가면 내리세요. 나머지는 설정 탭에서.", "Raise it if you have to move your head too much; lower it if the cursor flies around. More in the Settings tab."))
                    infoRow("arrow.up.and.down", L("스크롤 모드 (⌃⌥S)", "Scroll mode (⌃⌥S)"),
                            L("켜면 고개 위아래가 스크롤이 돼요. 긴 코드나 문서 읽을 때 좋아요.", "Moving your head up/down scrolls. Great for reading long code or documents."))
                    infoRow("hand.draw", L("드래그 고정 (⌃⌥D)", "Drag lock (⌃⌥D)"),
                            L("키를 계속 누르고 있기 힘들 때. 한 번 누르면 버튼이 눌린 상태가 되고, 고개로 옮긴 뒤 다시 ⌃⌥D 나 ⌃⌥ , 로 놓아요. 머무르면 클릭이 켜져 있으면 멈추는 것만으로 놓여요.", "For when holding a key is tiring. Press once to hold the button down, move with your head, then press ⌃⌥D or ⌃⌥ , to release. With dwell click on, just holding still drops it."))
                }

                section(L("단축키  (⌃ Control + ⌥ Option)", "Shortcuts  (⌃ Control + ⌥ Option)")) {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                        ForEach(controller.hotKeyList, id: \.0) { key, title in
                            GridRow {
                                Text(key).font(.system(.body, design: .monospaced).weight(.semibold))
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.15)))
                                Text(title)
                            }
                        }
                    }
                }

                section(L("문제가 생기면", "Troubleshooting")) {
                    infoRow("exclamationmark.triangle", L("머무르면 클릭이 멋대로 눌려요", "Dwell click fires by accident"), L("⌃⌥W 나 기둥 3번으로 끄거나, 설정 탭에서 머무는 시간을 늘리세요.", "Turn it off with ⌃⌥W or stem ×3, or make the dwell time longer in the Settings tab."))
                    infoRow("arrow.triangle.2.circlepath", L("커서가 계속 한쪽으로 흘러요", "The cursor keeps drifting"), L("설정 탭에서 멈춤 기준을 올리세요. 실시간 센서의 '걸러진 속도'를 참고하세요.", "Raise the stillness threshold in the Settings tab. Use 'Filtered speed' under Live Sensors as a guide."))
                    infoRow("arrow.left.arrow.right", L("방향이 반대예요", "Directions are reversed"), L("설정 탭 → 좌우/위아래 반전.", "Settings tab → Invert horizontal/vertical."))
                    infoRow("cursorarrow.slash", L("커서가 아예 안 움직여요", "The cursor doesn't move at all"), L("시작하기 탭의 체크리스트 1~3번을 확인하세요.", "Check steps 1–3 in the Get Started tab."))
                }
            }
            .padding(24)
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private func infoRow(_ icon: String, _ title: String, _ detail: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(.tint).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                if let detail {
                    Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
