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
                    Button(L("기준 자세 재설정", "Reset Reference Pose")) { controller.recenter() }
                }
            }

            Section(L("실시간 센서 (보정용)", "Live Sensors (for calibration)")) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow { Text(L("좌우 회전 yaw", "Turn (yaw)")); mono(t.yaw, "°"); Text(L("속도", "Rate")); mono(t.yawRate, "°/s") }
                    GridRow { Text(L("위아래 pitch", "Up/down (pitch)")); mono(t.pitch, "°"); Text(L("속도", "Rate")); mono(t.pitchRate, "°/s") }
                    GridRow { Text(L("갸웃 roll", "Tilt (roll)")); mono(t.roll, "°"); Text(L("기준 대비", "vs. reference")); mono(t.rollDev, "°") }
                    GridRow {
                        Text(L("중력 벡터", "Gravity vector"))
                        Text(String(format: "%.2f, %.2f, %.2f", t.gravity.x, t.gravity.y, t.gravity.z))
                            .font(.system(.body, design: .monospaced)).gridCellColumns(3)
                    }
                }
                LabeledContent(L("마지막 인식 제스처", "Last recognized gesture")) { Text(t.lastGesture).bold() }
                Text(L("까딱/갸웃을 해보면서 위 값과 '마지막 인식 제스처'를 보고 아래 기준값을 맞추세요. 끄덕일 때 pitch 속도가 기준값을 넘어야 인식돼요.", "Nod and tilt while watching these values and 'Last recognized gesture', then tune the thresholds below. A nod is recognized when the pitch rate goes over the threshold."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L("커서", "Cursor")) {
                Picker(L("이동 방식", "Movement"), selection: $settings.cursorMode) {
                    Text(L("조이스틱 (살짝 기울이고 있으면 계속 이동) · 추천", "Joystick (keeps moving while you're tilted) · Recommended")).tag("joystick")
                    Text(L("절대 (고개 방향 = 화면 위치)", "Absolute (head direction = screen position)")).tag("absolute")
                    Text(L("상대 (움직인 만큼, 트랙패드처럼)", "Relative (moves as much as you move, like a trackpad)")).tag("relative")
                }
                .pickerStyle(.radioGroup)
                if settings.joystickMode {
                    Toggle(L("⌃⌥ / 를 누르고 있을 때만 이동 (끄면 항상 이동)", "Move only while holding ⌃⌥ / (off = always move)"), isOn: $settings.joyRequiresKey)
                    slider(L("최고 속도 (px/초)", "Max speed (px/s)"), $settings.joyMaxSpeed, 300...4000, "%.0f")
                    slider(L("멈춤 범위 (이만큼은 기울여도 안 움직임)", "Rest zone (no movement within this tilt)"), $settings.joyDeadzone, 0.5...10, "%.1f°")
                    slider(L("최고 속도가 되는 기울기", "Tilt for max speed"), $settings.joyRange, 4...30, "%.0f°")
                    slider(L("위아래 증폭", "Vertical boost"), $settings.verticalBoost, 1...3, "%.1f×")
                    Text(settings.joyRequiresKey
                         ? L("⌃⌥ / 를 누르는 순간의 고개 위치가 '멈춤'이에요. 누른 채로 고개를 살짝 기울이면 그쪽으로 계속 가고, 많이 기울일수록 빨라져요. 떼면 그 자리에 멈춰요.", "Your head position when you press ⌃⌥ / is the rest point. Hold it and tilt slightly to keep moving that way — the more you tilt, the faster. Release to stop in place.")
                         : L("정면(⌃⌥R 로 맞춘 방향)이 '멈춤'이에요. 거기서 살짝 벗어나 있으면 그쪽으로 계속 가고, 많이 벗어날수록 빨라요. 클릭할 땐 정면으로 돌아오세요. 멈춤 위치가 어긋나면 편한 자세에서 ⌃⌥ / 를 한 번 누르세요.", "Forward (set with ⌃⌥R) is the rest point. Turn slightly away to keep moving that way — the further, the faster. Face forward again to click. If the rest point drifts, press ⌃⌥ / once in a comfortable pose."))
                        .font(.caption).foregroundStyle(.secondary)
                } else if settings.absoluteMode {
                    slider(L("좌우 범위 (화면 끝까지 몇 도)", "Horizontal range (degrees to screen edge)"), $settings.yawRange, 8...45, "%.0f°")
                    slider(L("위아래 범위 (화면 끝까지 몇 도)", "Vertical range (degrees to screen edge)"), $settings.pitchRange, 5...30, "%.0f°")
                    Text(L("정면을 보면 화면 중앙이에요. 범위를 줄이면 고개를 조금만 움직여도 화면 끝에 닿아요. 화면 끝을 넘어 더 돌리면 기준이 따라와서, 돌아올 때 바로 반응해요. 트랙패드로 옮기면 그 위치가 새 기준이 돼요.", "Looking forward puts the cursor at screen center. A smaller range reaches the edge with less head movement. Turning past the edge drags the reference along, so it responds right away on the way back. Moving the cursor with the trackpad makes that the new reference."))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    slider(L("감도 (px/도)", "Sensitivity (px/°)"), $settings.sensitivity, 4...80, "%.0f")
                    slider(L("가속", "Acceleration"), $settings.acceleration, 0...4, "%.1f")
                    slider(L("데드존 (도/초, 떨림 무시)", "Dead zone (°/s, ignores jitter)"), $settings.deadzone, 0...20, "%.1f")
                }
                slider(L("부드럽게", "Smoothing"), $settings.smoothing, 0...0.9, "%.2f")
                slider(L("스크롤 속도", "Scroll speed"), $settings.scrollSpeed, 1...30, "%.0f")
                Toggle(L("좌우 반전", "Invert horizontal"), isOn: $settings.invertX)
                Toggle(L("위아래 반전", "Invert vertical"), isOn: $settings.invertY)
            }

            Section(L("머리 제스처", "Head Gestures")) {
                Toggle(L("제스처 사용 (⌃⌥G)", "Use gestures (⌃⌥G)"), isOn: $settings.gesturesEnabled)
                slider(L("까딱 인식 속도 (°/s, 높을수록 둔감)", "Nod threshold (°/s, higher = less sensitive)"), $settings.nodThreshold, 50...300, "%.0f")
                slider(L("갸웃 인식 각도 (°)", "Tilt threshold (°)"), $settings.tiltAngle, 8...40, "%.0f")
                slider(L("도리도리 인식 속도 (°/s)", "Shake threshold (°/s)"), $settings.shakeThreshold, 60...350, "%.0f")
                Toggle(L("갸웃 좌우 반전 (오른쪽/왼쪽이 반대로 인식될 때)", "Invert tilt (if left/right are detected backwards)"), isOn: $settings.invertTilt)
                ForEach(PodTrigger.allCases.filter(\.isHeadGesture)) { trig in actionPicker(trig) }
                Text(L("마우스 모드가 꺼져 있을 땐 '마우스 모드 켜기'와 '음성 입력'에 연결된 제스처만 동작해요.", "While mouse mode is off, only gestures assigned to 'Toggle mouse mode' and voice input work."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L("에어팟 기둥 누르기", "AirPods Stem Presses")) {
                Toggle(L("기둥 누르기 사용 (마우스 모드일 때만 재생/정지 대신 아래 동작 실행)", "Use stem presses (in mouse mode, run the actions below instead of play/pause)"),
                       isOn: Binding(get: { settings.captureStem }, set: { controller.setStemCapture($0) }))
                ForEach(PodTrigger.allCases.filter { !$0.isHeadGesture }) { trig in actionPicker(trig) }
            }

            Section(L("음성 입력 (Claude Code · Codex 등)", "Voice Input (Claude Code, Codex, etc.)")) {
                Picker(L("인식 언어", "Recognition language"), selection: $settings.voiceLocale) {
                    Text("한국어").tag("ko-KR")
                    Text("English (US)").tag("en-US")
                    Text("日本語").tag("ja-JP")
                }
                Toggle(L("입력 후 Enter 자동으로 누르기 (바로 전송)", "Press Enter automatically after input (send right away)"), isOn: $settings.autoEnter)
                LabeledContent(L("입력 대상", "Target")) {
                    Text(settings.voiceTargetBundleID.isEmpty ? L("현재 포커스된 창", "Currently focused window") : settings.voiceTargetBundleID)
                }
                Text(L("메뉴바 → 음성 입력 대상에서 터미널 앱을 고르면, 다른 창을 보고 있어도 그 앱으로 보내요. \"엔터\" / \"전송\" 이라고만 말하면 Enter, \"취소\" 는 Esc 를 눌러요.", "Pick your terminal app in menu bar → Voice Input Target to send text there even while another window is in front. Say just \"enter\" / \"send\" to press Enter, or \"cancel\" for Esc."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L("단축키", "Shortcuts")) {
                ForEach(controller.hotKeyList, id: \.0) { key, title in
                    LabeledContent(title) { Text(key).font(.system(.body, design: .monospaced)) }
                }
            }

            Section {
                Toggle(L("화면 알림 표시", "Show on-screen notifications"), isOn: $settings.showHUD)
                Button(L("커서/제스처 설정 기본값으로", "Reset Cursor & Gesture Settings")) { settings.resetToDefaults() }
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
