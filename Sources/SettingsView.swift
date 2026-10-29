import SwiftUI
import CoreMotion

struct SettingsView: View {
    let controller: AppController
    @ObservedObject var settings = Settings.shared
    @ObservedObject var state = AppState.shared
    @ObservedObject var t = Telemetry.shared

    var body: some View {
        Form {
            Section(L("일반", "General")) {
                Picker(L("앱 언어", "App language"), selection: Binding(get: { settings.language }, set: { settings.setLanguage($0) })) {
                    Text(L("시스템 설정 따르기", "Same as system")).tag("system")
                    Text("한국어").tag("ko")
                    Text("English").tag("en")
                }
            }

            Section(L("상태", "Status")) {
                row(L("에어팟 헤드 트래킹", "AirPods head tracking"), ok: t.connected && t.receiving,
                    detail: t.receiving ? String(format: L("수신 중 %.0fHz", "Receiving %.0f Hz"), t.updateHz) : L("귀에 착용하면 연결돼요", "Connects when you wear them"))
                row(L("동작 및 피트니스 권한", "Motion & Fitness access"), ok: CMHeadphoneMotionManager.authorizationStatus() == .authorized,
                    detail: authText(CMHeadphoneMotionManager.authorizationStatus()))
                HStack {
                    row(L("손쉬운 사용 권한 (마우스 제어)", "Accessibility access (mouse control)"), ok: state.accessibilityOK, detail: state.accessibilityOK ? L("허용됨", "Allowed") : L("필요", "Required"))
                    if !state.accessibilityOK {
                        Button(L("열기", "Open")) {
                            controller.checkAccessibility(prompt: true)
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
                HStack {
                    Toggle(L("마우스 모드", "Mouse mode"), isOn: Binding(get: { state.mouseEnabled }, set: { controller.setMouse($0) }))
                    Spacer()
                    Button(L("기준 재설정", "Reset")) { controller.recenter() }
                }
            }

            Section(L("실시간 센서 (보정용)", "Live Sensors (for calibration)")) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow { Text(L("좌우 회전 yaw", "Turn (yaw)")); mono(t.yaw, "°"); Text(L("속도", "Rate")); mono(t.yawRate, "°/s") }
                    GridRow { Text(L("위아래 pitch", "Up/down (pitch)")); mono(t.pitch, "°"); Text(L("속도", "Rate")); mono(t.pitchRate, "°/s") }
                    GridRow { Text(L("갸웃 roll", "Tilt (roll)")); mono(t.roll, "°"); Text(""); Text("") }
                    GridRow {
                        Text(L("걸러진 속도", "Filtered speed")); mono(t.speed, "°/s")
                        Text(L("커서", "Cursor"))
                        Text(t.still ? L("고정", "Locked") : L("움직임", "Moving")).foregroundStyle(t.still ? Color.secondary : Color.green)
                    }
                    GridRow {
                        Text(L("중력 벡터", "Gravity vector"))
                        Text(String(format: "%.2f, %.2f, %.2f", t.gravity.x, t.gravity.y, t.gravity.z))
                            .font(.system(.body, design: .monospaced)).gridCellColumns(3)
                    }
                }
                Text(L("고개를 가만히 두었을 때 '걸러진 속도'가 '멈춤 기준'보다 낮아야 커서가 흐르지 않아요. 값이 안 움직이면 에어팟을 다시 끼거나 블루투스를 다시 연결하세요.", "With your head still, 'Filtered speed' should stay under the 'Stillness threshold' so the cursor doesn't drift. If nothing moves, reinsert your AirPods or reconnect Bluetooth."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L("커서", "Cursor")) {
                slider(L("감도 (천천히 움직일 때 px/도)", "Sensitivity (px/° when moving slowly)"), $settings.sensitivity, 3...60, "%.0f")
                slider(L("가속 (빠르게 움직일 때 추가)", "Acceleration (extra when moving fast)"), $settings.acceleration, 0...6, "%.1f")
                slider(L("떨림 거르기 (높을수록 매끄럽지만 살짝 느림)", "Jitter filter (higher = smoother, slightly slower)"), $settings.smoothing, 0...1, "%.2f")
                slider(L("멈춤 기준 (°/s, 이보다 느리면 커서 고정)", "Stillness threshold (°/s, slower = cursor locked)"), $settings.stillness, 0...15, "%.1f")
                slider(L("스크롤 속도", "Scroll speed"), $settings.scrollSpeed, 1...30, "%.0f")
                Toggle(L("좌우 반전", "Invert horizontal"), isOn: $settings.invertX)
                Toggle(L("위아래 반전", "Invert vertical"), isOn: $settings.invertY)
                Text(L("천천히 움직이면 정밀하게, 빠르게 움직이면 멀리 가요. 커서가 서서히 흐르면 멈춤 기준을 올리고, 클릭할 때 흔들리면 떨림 거르기를 올리세요.", "Move slowly for precision, quickly to go far. If the cursor creeps, raise the stillness threshold; if it shakes when you try to click, raise the jitter filter."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L("머무르면 클릭", "Dwell Click")) {
                Toggle(L("머무르면 클릭 사용 (⌃⌥W · 기둥 3번)", "Use dwell click (⌃⌥W · stem ×3)"), isOn: Binding(get: { settings.dwellEnabled }, set: { controller.setDwell($0) }))
                slider(L("머무는 시간", "Dwell time"), $settings.dwellTime, 0.3...2.0, "%.1fs")
                slider(L("허용 반경 (px)", "Radius (px)"), $settings.dwellRadius, 3...40, "%.0f")
                Text(L("커서를 반경 안에 머무는 시간만큼 두면 링이 차오르고 왼쪽 클릭이 돼요. 클릭 후엔 커서를 움직여야 다시 클릭돼요. 드래그 고정(⌃⌥D) 중이면 놓기가 돼요.", "Keep the cursor within the radius for the dwell time: a ring fills up and it left-clicks. After a click, move the cursor before it can click again. While drag lock (⌃⌥D) is on, it drops instead."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L("에어팟 기둥 누르기", "AirPods Stem Presses")) {
                Toggle(L("기둥 누르기 사용 (마우스 모드일 때만 재생/정지 대신 아래 동작 실행)", "Use stem presses (in mouse mode, run the actions below instead of play/pause)"),
                       isOn: Binding(get: { settings.captureStem }, set: { controller.setStemCapture($0) }))
                ForEach(PodTrigger.allCases) { trig in actionPicker(trig) }
            }

            Section(L("단축키", "Shortcuts")) {
                ForEach(controller.hotKeyList, id: \.0) { key, title in
                    LabeledContent(title) { Text(key).font(.system(.body, design: .monospaced)) }
                }
            }

            Section {
                Toggle(L("화면 알림 표시", "Show on-screen notifications"), isOn: $settings.showHUD)
                Button(L("커서/클릭 설정 기본값으로", "Reset Cursor & Click Settings")) { settings.resetToDefaults() }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 560, minHeight: 600)
    }

    private func row(_ title: String, ok: Bool, detail: String) -> some View {
        LabeledContent {
            Text(detail).foregroundStyle(ok ? .green : .orange)
        } label: {
            Label(title, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
        }
    }

    private func authText(_ s: CMAuthorizationStatus) -> String {
        switch s {
        case .authorized: return L("허용됨", "Allowed")
        case .denied: return L("거부됨 → 시스템 설정에서 허용", "Denied → allow it in System Settings")
        case .restricted: return L("제한됨", "Restricted")
        default: return L("에어팟 착용 시 물어봐요", "Asked when you put AirPods in")
        }
    }

    private func mono(_ v: Double, _ unit: String) -> some View {
        Text(String(format: "%7.1f%@", v, unit)).font(.system(.body, design: .monospaced))
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ fmt: String) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range).frame(width: 220)
                Text(String(format: fmt, value.wrappedValue)).monospacedDigit().frame(width: 44, alignment: .trailing)
            }
        }
    }

    private func actionPicker(_ trig: PodTrigger) -> some View {
        Picker(trig.label, selection: Binding(get: { settings.action(for: trig) }, set: { settings.setAction($0, for: trig) })) {
            ForEach(PodAction.allCases) { a in Text(a.label).tag(a) }
        }
    }
}
