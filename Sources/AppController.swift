import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreMotion
import ServiceManagement
import SwiftUI

final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var mouseEnabled = false
    @Published var scrollMode = false
    @Published var listening = false
    @Published var dragging = false
    @Published var accessibilityOK = false
    // 연습 화면용: 인식된 제스처 기록
    @Published var practiced: Set<String> = []
    @Published var lastTrigger: PodTrigger?
    @Published var triggerSeq = 0
    @Published var voiceUsed = false
    @Published var guideTab = 0
}

final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let settings = Settings.shared
    private let state = AppState.shared
    private let motion = MotionEngine()
    private let voice = VoiceInput()
    private let stem = StemButtons()
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var voiceHotkeyDownAt: TimeInterval = 0
    private var voiceStartedByHotkey = false
    private var observers: [Any] = []
    private var joyKeyDown = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        PLog.write("launch motionAvailable=\(CMHeadphoneMotionManager().isDeviceMotionAvailable) motionAuth=\(CMHeadphoneMotionManager.authorizationStatus().rawValue) ax=\(AXIsProcessTrusted())")
        setupStatusItem()
        if CommandLine.arguments.contains("--selftest") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { InputSynth.selfTest() }
        }
        if CommandLine.arguments.contains("--joytest") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self else { return }
                self.setMouse(true, announce: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.motion.selfTestJoystick { self.setMouse(false, announce: false) }
                }
            }
        }
        checkAccessibility(prompt: true)

        motion.mouseEnabled = false
        motion.onGesture = { [weak self] trigger in self?.handle(trigger) }
        motion.onConnectionChange = { [weak self] connected in
            HUD.shared.flash(connected ? L("에어팟 연결됨", "AirPods connected") : L("에어팟 연결 끊김", "AirPods disconnected"), icon: connected ? "airpods" : "airpods.slash")
            if !connected { self?.setMouse(false, announce: false) }
            self?.refreshIcon()
        }
        motion.start()

        voice.onStateChange = { [weak self] listening in
            self?.state.listening = listening
            if listening { self?.state.voiceUsed = true }
            if listening { HUD.shared.showListening("") } else { HUD.shared.endListening() }
            self?.refreshIcon()
        }
        voice.onPartial = { text in HUD.shared.showListening(text) }
        voice.onMessage = { msg in HUD.shared.flash(msg, icon: "text.bubble", duration: 2.0) }

        stem.onPress = { [weak self] trigger in self?.handle(trigger) }
        // 기둥 누르기는 마우스 모드가 켜져 있을 때만 가로챔 (꺼져 있으면 음악 재생/정지 그대로)

        registerHotKeys()

        // 권한을 허용하고 돌아왔을 때 다시 확인
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                self?.checkAccessibility(prompt: false)
            })

        if settings.showGuideOnLaunch {
            openWindow(tab: 0)
        } else {
            HUD.shared.flash(L("PodMouse 실행됨 · ⌃⌥M 으로 마우스 모드 켜기", "PodMouse is running · press ⌃⌥M to turn on mouse mode"), duration: 2.5)
        }
    }

    /// 이미 실행 중일 때 앱을 다시 열면(Finder/Spotlight) 안내 창 보여주기
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openWindow(tab: 0)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        InputSynth.endDrag()
        stem.stop()
        motion.stop()
    }

    // MARK: - 동작 실행

    private func handle(_ trigger: PodTrigger) {
        let action = settings.action(for: trigger)
        state.practiced.insert(trigger.rawValue)
        state.lastTrigger = trigger
        state.triggerSeq += 1
        // 마우스 모드가 꺼져 있으면 마우스 켜기/음성 입력만 받음 (대화 중 끄덕여도 클릭되지 않게)
        if trigger.isHeadGesture && !state.mouseEnabled && !state.scrollMode {
            guard action == .toggleMouse || action == .toggleVoice else { return }
        }
        perform(action, source: trigger.label)
    }

    func perform(_ action: PodAction, source: String? = nil) {
        switch action {
        case .none: return
        case .leftClick: InputSynth.leftClick(); syncDrag(); flash(L("왼쪽 클릭", "Left click"), "cursorarrow.click")
        case .rightClick: InputSynth.rightClick(); flash(L("오른쪽 클릭", "Right click"), "cursorarrow.click.2")
        case .doubleClick: InputSynth.doubleClick(); flash(L("더블 클릭", "Double click"), "cursorarrow.click.2")
        case .toggleDrag:
            if InputSynth.isDragging { InputSynth.endDrag(); flash(L("드래그 끝", "Drag ended"), "hand.raised") }
            else { InputSynth.beginDrag(); flash(L("드래그 중… (⌃⌥D 또는 ⌃⌥ , 로 놓기)", "Dragging… (⌃⌥D or ⌃⌥ , to drop)"), "hand.draw") }
            syncDrag()
        case .toggleVoice: voice.toggle()
        case .toggleMouse: setMouse(!state.mouseEnabled)
        case .toggleScroll: setScroll(!state.scrollMode)
        case .recenter: recenter()
        case .pressEnter: InputSynth.pressEnter(); flash("Enter", "return")
        case .pressEscape: InputSynth.pressEscape(); flash("Esc", "escape")
        }
    }

    private func flash(_ text: String, _ icon: String) { HUD.shared.flash(text, icon: icon, duration: 0.8) }

    private func syncDrag() { state.dragging = InputSynth.isDragging }

    func setMouse(_ on: Bool, announce: Bool = true, center: Bool = true) {
        guard !on || checkAccessibility(prompt: true) else {
            HUD.shared.flash(L("손쉬운 사용 권한이 필요해요", "Accessibility access is required"), icon: "exclamationmark.triangle", duration: 2.5)
            return
        }
        state.mouseEnabled = on
        motion.mouseEnabled = on
        PLog.write("mouse mode \(on ? "on" : "off") mode=\(settings.cursorMode) requiresKey=\(settings.joyRequiresKey)")
        if on {
            motion.recalibrate()
            // 정면을 보고 켜면 커서가 화면 정중앙에서 시작
            if center { InputSynth.move(to: InputSynth.mainScreenCenter()) }
            if CMHeadphoneMotionManager.authorizationStatus() == .denied {
                HUD.shared.flash(L("동작 및 피트니스 권한이 꺼져 있어요", "Motion & Fitness access is turned off"), icon: "exclamationmark.triangle", duration: 2.5)
            }
        } else {
            InputSynth.endDrag()
            syncDrag()
            if state.scrollMode { setScroll(false, announce: false) }
        }
        updateStemCapture()
        if announce {
            let hint = !settings.joystickMode ? ""
                : settings.joyRequiresKey ? L(" · ⌃⌥ / 누른 채 고개를 살짝 기울이면 이동", " · hold ⌃⌥ / and tilt your head slightly to move")
                : L(" · 고개를 살짝 기울이고 있으면 그쪽으로 이동", " · keep your head slightly tilted to move that way")
            HUD.shared.flash(on ? L("마우스 모드 켜짐\(hint)", "Mouse mode on\(hint)") : L("마우스 모드 꺼짐", "Mouse mode off"), icon: on ? "cursorarrow.motionlines" : "cursorarrow.slash",
                             duration: on ? 3.0 : 1.2)
        }
        refreshIcon()
    }

    func setScroll(_ on: Bool, announce: Bool = true) {
        state.scrollMode = on
        motion.scrollMode = on
        motion.recalibrate()
        if announce { HUD.shared.flash(on ? L("스크롤 모드: 고개로 스크롤", "Scroll mode: scroll with your head") : L("스크롤 모드 꺼짐", "Scroll mode off"), icon: "arrow.up.and.down") }
        refreshIcon()
    }

    func recenter() {
        motion.recalibrate()
        if state.mouseEnabled { InputSynth.move(to: InputSynth.mainScreenCenter()) }
        HUD.shared.flash(L("정면 기준 재설정 · 커서 중앙", "Forward reset · cursor centered"), icon: "scope")
    }

    func setStemCapture(_ on: Bool) {
        settings.captureStem = on
        updateStemCapture()
    }

    private func updateStemCapture() {
        if settings.captureStem && state.mouseEnabled { stem.start() } else { stem.stop() }
    }

    @discardableResult
    func checkAccessibility(prompt: Bool) -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        let ok = AXIsProcessTrustedWithOptions(opts)
        state.accessibilityOK = ok
        return ok
    }

    // MARK: - 단축키

    private func registerHotKeys() {
        let mods = controlKey | optionKey
        let hk = HotKeys.shared
        hk.register(keyCode: kVK_ANSI_M, modifiers: mods, display: "⌃⌥M", title: L("마우스 모드 켜기/끄기", "Toggle mouse mode")) { [weak self] in
            self?.perform(.toggleMouse)
        }
        hk.register(keyCode: kVK_ANSI_R, modifiers: mods, display: "⌃⌥R", title: L("기준 자세 재설정 + 커서 중앙", "Reset reference pose + center cursor")) { [weak self] in
            self?.perform(.recenter)
        }
        // 짧게 누르면 켜기/끄기, 길게 누르고 있으면 누르는 동안만 녹음
        hk.register(keyCode: kVK_ANSI_Slash, modifiers: mods, display: "⌃⌥ /", title: L("지금 고개 위치를 멈춤 기준으로 (키 모드: 누르는 동안 이동)", "Set current head position as rest (key mode: move while held)"),
                    onPress: { [weak self] in
                        guard let self, !self.joyKeyDown else { return }
                        self.joyKeyDown = true
                        PLog.write("hotkey ⌃⌥/ down")
                        if self.settings.joyRequiresKey {
                            HUD.shared.showHold(L("이동 중 · 고개를 살짝 기울이세요", "Moving · tilt your head slightly"), icon: "move.3d")
                        } else {
                            HUD.shared.flash(L("지금 고개 위치 = 멈춤", "Current head position = rest"), icon: "scope")
                        }
                        if !self.state.mouseEnabled { self.setMouse(true, announce: false, center: false) }
                        self.motion.beginJoystickHold()
                    },
                    onRelease: { [weak self] in
                        guard let self else { return }
                        self.joyKeyDown = false
                        PLog.write("hotkey ⌃⌥/ up")
                        HUD.shared.endHold()
                        if InputSynth.heldButton == nil { self.motion.endJoystickHold() }
                    })
        hk.register(keyCode: kVK_ANSI_V, modifiers: mods, display: "⌃⌥V", title: L("음성 입력 (탭: 켜기/끄기, 길게: 누르는 동안)", "Voice input (tap: on/off, hold: while held)"),
                    onPress: { [weak self] in
                        guard let self else { return }
                        self.voiceHotkeyDownAt = ProcessInfo.processInfo.systemUptime
                        self.voiceStartedByHotkey = !self.voice.isListening
                        if self.voiceStartedByHotkey { self.voice.start() } else { self.voice.stop() }
                    },
                    onRelease: { [weak self] in
                        guard let self, self.voiceStartedByHotkey else { return }
                        if ProcessInfo.processInfo.systemUptime - self.voiceHotkeyDownAt > 0.6 { self.voice.stop() }
                    })
        // 누르는 순간 버튼 누름, 떼는 순간 버튼 뗌 → 짧게 = 클릭, 꾹 누르고 고개 움직이기 = 드래그
        hk.register(keyCode: kVK_ANSI_Comma, modifiers: mods, display: "⌃⌥ ,", title: L("왼쪽 클릭 (꾹 누르면 드래그)", "Left click (hold to drag)"),
                    onPress: { [weak self] in self?.hotkeyButton(.left, down: true) },
                    onRelease: { [weak self] in self?.hotkeyButton(.left, down: false) })
        hk.register(keyCode: kVK_ANSI_Period, modifiers: mods, display: "⌃⌥ .", title: L("오른쪽 클릭", "Right click"),
                    onPress: { [weak self] in self?.hotkeyButton(.right, down: true) },
                    onRelease: { [weak self] in self?.hotkeyButton(.right, down: false) })
        hk.register(keyCode: kVK_ANSI_D, modifiers: mods, display: "⌃⌥D", title: L("드래그 시작/끝", "Start/end drag")) { [weak self] in
            self?.perform(.toggleDrag)
        }
        hk.register(keyCode: kVK_ANSI_S, modifiers: mods, display: "⌃⌥S", title: L("스크롤 모드 켜기/끄기", "Toggle scroll mode")) { [weak self] in
            self?.perform(.toggleScroll)
        }
        hk.register(keyCode: kVK_ANSI_G, modifiers: mods, display: "⌃⌥G", title: L("머리 제스처 켜기/끄기", "Toggle head gestures")) { [weak self] in
            guard let self else { return }
            self.settings.gesturesEnabled.toggle()
            HUD.shared.flash(self.settings.gesturesEnabled ? L("제스처 켜짐", "Gestures on") : L("제스처 꺼짐", "Gestures off"), icon: "hand.wave")
        }
        hk.register(keyCode: kVK_ANSI_Equal, modifiers: mods, display: "⌃⌥=", title: L("감도 올리기", "Increase sensitivity")) { [weak self] in
            self?.adjustSensitivity(1.15)
        }
        hk.register(keyCode: kVK_ANSI_Minus, modifiers: mods, display: "⌃⌥-", title: L("감도 내리기", "Decrease sensitivity")) { [weak self] in
            self?.adjustSensitivity(1 / 1.15)
        }
    }

    private func hotkeyButton(_ button: CGMouseButton, down: Bool) {
        guard checkAccessibility(prompt: down) else {
            if down { HUD.shared.flash(L("손쉬운 사용 권한이 필요해요", "Accessibility access is required"), icon: "exclamationmark.triangle", duration: 2.5) }
            return
        }
        if down {
            guard InputSynth.heldButton != button else { return } // 키 자동 반복 무시
            motion.beginJoystickHold() // 꾹 누르고 고개를 기울이면 드래그
            InputSynth.buttonDown(button)
            state.practiced.insert(button == .left ? "hotkeyLeft" : "hotkeyRight")
            flash(button == .left ? L("왼쪽 클릭", "Left click") : L("오른쪽 클릭", "Right click"), button == .left ? "cursorarrow.click" : "cursorarrow.click.2")
        } else {
            InputSynth.buttonUp(button)
            if !joyKeyDown { motion.endJoystickHold() }
        }
        syncDrag()
    }

    private func adjustSensitivity(_ factor: Double) {
        settings.sensitivity = min(80, max(4, settings.sensitivity * factor))
        HUD.shared.flash(String(format: L("감도 %.0f", "Sensitivity %.0f"), settings.sensitivity), icon: "dial.medium")
    }

    // MARK: - 메뉴바

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshIcon()
    }

    private func symbol(_ names: [String]) -> NSImage? {
        for n in names {
            if let img = NSImage(systemSymbolName: n, accessibilityDescription: "PodMouse") {
                img.isTemplate = true
                return img
            }
        }
        return nil
    }

    func refreshIcon() {
        let names: [String]
        if state.listening { names = ["waveform"] }
        else if state.scrollMode { names = ["arrow.up.and.down.circle"] }
        else if state.mouseEnabled { names = ["cursorarrow.motionlines"] }
        else {
            // 시스템 에어팟 아이콘과 헷갈리지 않게 커서를 붙인 아이콘
            statusItem.button?.image = idleIcon ?? symbol(["airpods.gen4", "airpods", "headphones"])
            return
        }
        statusItem.button?.image = symbol(names)
    }

    /// 대기 상태 메뉴바 아이콘: 에어팟 + 오른쪽 아래 커서 (겹치는 부분은 테두리만큼 비워서 구분)
    private lazy var idleIcon: NSImage? = {
        func sym(_ names: [String], _ pt: CGFloat, _ weight: NSFont.Weight) -> NSImage? {
            for n in names {
                if let img = NSImage(systemSymbolName: n, accessibilityDescription: "PodMouse") {
                    return img.withSymbolConfiguration(.init(pointSize: pt, weight: weight))
                }
            }
            return nil
        }
        guard let pods = sym(["airpods.gen4", "airpods", "headphones"], 14, .regular),
              let arrow = sym(["cursorarrow"], 11, .heavy) else { return nil }
        let size = NSSize(width: pods.size.width + arrow.size.width * 0.65, height: 18)
        let img = NSImage(size: size, flipped: false) { r in
            pods.draw(in: NSRect(x: 0, y: (r.height - pods.size.height) / 2, width: pods.size.width, height: pods.size.height))
            let a = NSRect(x: r.width - arrow.size.width, y: 0, width: arrow.size.width, height: arrow.size.height)
            for dx in [-1.5, 0, 1.5] {
                for dy in [-1.5, 0, 1.5] {
                    arrow.draw(in: a.offsetBy(dx: dx, dy: dy), from: .zero, operation: .destinationOut, fraction: 1)
                }
            }
            arrow.draw(in: a, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "PodMouse"
        return img
    }()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let t = Telemetry.shared

        let status: String
        if !motion.isAvailable { status = L("⚠️ 헤드 트래킹을 쓸 수 없음", "⚠️ Head tracking unavailable") }
        else if t.receiving && t.connected { status = String(format: L("에어팟 연결됨 · %.0fHz", "AirPods connected · %.0f Hz"), t.updateHz) }
        else { status = L("에어팟을 귀에 착용하세요", "Put your AirPods in") }
        menu.addItem(disabled(status))
        if !state.accessibilityOK {
            menu.addItem(item(L("⚠️ 손쉬운 사용 권한 허용하기…", "⚠️ Allow Accessibility Access…")) { [weak self] in
                self?.checkAccessibility(prompt: true)
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            })
        }
        menu.addItem(.separator())

        menu.addItem(item(L("마우스 모드", "Mouse Mode"), key: "⌃⌥M", on: state.mouseEnabled) { [weak self] in self?.perform(.toggleMouse) })
        menu.addItem(item(L("스크롤 모드", "Scroll Mode"), key: "⌃⌥S", on: state.scrollMode) { [weak self] in self?.perform(.toggleScroll) })
        menu.addItem(item(state.listening ? L("음성 입력 끝내기", "Stop Voice Input") : L("음성 입력 시작", "Start Voice Input"), key: "⌃⌥V", on: state.listening) { [weak self] in
            self?.perform(.toggleVoice)
        })
        menu.addItem(item(L("기준 자세 재설정", "Reset Reference Pose"), key: "⌃⌥R") { [weak self] in self?.perform(.recenter) })
        menu.addItem(.separator())

        menu.addItem(item(L("머리 제스처 사용", "Head Gestures"), key: "⌃⌥G", on: settings.gesturesEnabled) { [weak self] in
            self?.settings.gesturesEnabled.toggle()
        })
        menu.addItem(item(L("에어팟 기둥 누르기로 클릭 (마우스 모드일 때)", "Click with AirPods Stem (in Mouse Mode)"), on: settings.captureStem) { [weak self] in
            guard let self else { return }
            self.setStemCapture(!self.settings.captureStem)
        })
        menu.addItem(item(L("음성 입력 후 Enter 자동", "Auto Enter After Voice Input"), on: settings.autoEnter) { [weak self] in
            self?.settings.autoEnter.toggle()
        })
        menu.addItem(voiceTargetMenu())
        menu.addItem(languageMenu())
        menu.addItem(.separator())

        menu.addItem(item(L("사용 안내 열기…", "Open Guide…")) { [weak self] in self?.openWindow(tab: 0) })
        menu.addItem(item(L("조작법 보기…", "Controls…")) { [weak self] in self?.openWindow(tab: 1) })
        menu.addItem(item(L("설정 및 보정…", "Settings & Calibration…")) { [weak self] in self?.openWindow(tab: 2) })
        menu.addItem(item(L("로그인 시 자동 실행", "Launch at Login"), on: SMAppService.mainApp.status == .enabled) {
            do {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
                else { try SMAppService.mainApp.register() }
            } catch {
                HUD.shared.flash(L("로그인 항목 설정 실패: \(error.localizedDescription)", "Couldn't change login item: \(error.localizedDescription)"), icon: "exclamationmark.triangle", duration: 2.5)
            }
        })
        menu.addItem(.separator())
        menu.addItem(item(L("PodMouse 종료", "Quit PodMouse")) { NSApp.terminate(nil) })
    }

    private func voiceTargetMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: L("음성 입력 대상", "Voice Input Target"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.addItem(item(L("현재 포커스된 창", "Currently Focused Window"), on: settings.voiceTargetBundleID.isEmpty) { [weak self] in
            self?.settings.voiceTargetBundleID = ""
        })
        sub.addItem(.separator())
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        for app in apps {
            guard let bid = app.bundleIdentifier else { continue }
            let i = item(app.localizedName ?? bid, on: settings.voiceTargetBundleID == bid) { [weak self] in
                self?.settings.voiceTargetBundleID = bid
            }
            if let icon = app.icon { icon.size = NSSize(width: 16, height: 16); i.image = icon }
            sub.addItem(i)
        }
        let current = settings.voiceTargetBundleID
        if !current.isEmpty && !apps.contains(where: { $0.bundleIdentifier == current }) {
            sub.addItem(item(L("\(current) (실행 중 아님)", "\(current) (not running)"), on: true) {})
        }
        parent.submenu = sub
        return parent
    }

    private func languageMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "언어 / Language", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (tag, title) in [("system", L("시스템 설정 따르기", "Same as System")), ("ko", "한국어"), ("en", "English")] {
            sub.addItem(item(title, on: settings.language == tag) { [weak self] in self?.settings.setLanguage(tag) })
        }
        parent.submenu = sub
        return parent
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    private func item(_ title: String, key: String? = nil, on: Bool = false, _ handler: @escaping () -> Void) -> NSMenuItem {
        let i = ClosureMenuItem(title: title, handler: handler)
        i.state = on ? .on : .off
        if let key {
            let attr = NSMutableAttributedString(string: title)
            attr.append(NSAttributedString(string: "   \(key)", attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
            i.attributedTitle = attr
        }
        return i
    }

    // MARK: - 메인 창 (시작하기 / 조작법 / 설정)

    func openWindow(tab: Int) {
        state.guideTab = tab
        checkAccessibility(prompt: false)
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 820),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "PodMouse"
            w.contentView = NSHostingView(rootView: MainView(controller: self))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            settingsWindow = w
        }
        // 창이 떠 있는 동안은 Dock / ⌘Tab 에 보이게
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settingsWindow else { return }
        NSApp.setActivationPolicy(.accessory)
        HUD.shared.flash(L("PodMouse는 메뉴바에서 계속 실행 중이에요", "PodMouse keeps running in the menu bar"), duration: 2.0)
    }

    var hotKeyList: [(String, String)] { HotKeys.shared.all.map { ($0.display, $0.title()) } }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func run() { handler() }
}
