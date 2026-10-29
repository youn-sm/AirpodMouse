import Foundation
import Combine

/// 제스처/버튼에 연결할 수 있는 동작
enum PodAction: String, CaseIterable, Identifiable, Codable {
    case none
    case leftClick
    case rightClick
    case doubleClick
    case toggleDrag
    case toggleVoice
    case toggleMouse
    case toggleScroll
    case recenter
    case pressEnter
    case pressEscape

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return L("없음", "None")
        case .leftClick: return L("왼쪽 클릭", "Left click")
        case .rightClick: return L("오른쪽 클릭", "Right click")
        case .doubleClick: return L("더블 클릭", "Double click")
        case .toggleDrag: return L("드래그 시작/끝", "Start/end drag")
        case .toggleVoice: return L("음성 입력 시작/끝", "Start/stop voice input")
        case .toggleMouse: return L("마우스 모드 켜기/끄기", "Toggle mouse mode")
        case .toggleScroll: return L("스크롤 모드 켜기/끄기", "Toggle scroll mode")
        case .recenter: return L("커서 화면 중앙으로", "Center cursor")
        case .pressEnter: return L("Enter 키", "Enter key")
        case .pressEscape: return L("Esc 키", "Esc key")
        }
    }
}

/// 머리 동작 / 기둥 버튼 종류
enum PodTrigger: String, CaseIterable, Identifiable {
    case nod          // 고개 까딱
    case tiltRight    // 오른쪽으로 갸웃
    case tiltLeft     // 왼쪽으로 갸웃
    case shake        // 도리도리
    case stemSingle   // 기둥 1번 누르기
    case stemDouble   // 기둥 2번 누르기
    case stemTriple   // 기둥 3번 누르기

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nod: return L("고개 까딱 (끄덕)", "Nod")
        case .tiltRight: return L("오른쪽으로 갸웃", "Tilt right")
        case .tiltLeft: return L("왼쪽으로 갸웃", "Tilt left")
        case .shake: return L("도리도리", "Head shake")
        case .stemSingle: return L("기둥 1번 누르기", "Stem press ×1")
        case .stemDouble: return L("기둥 2번 누르기", "Stem press ×2")
        case .stemTriple: return L("기둥 3번 누르기", "Stem press ×3")
        }
    }

    var defaultAction: PodAction {
        switch self {
        case .nod: return .none
        case .tiltRight: return .none
        case .tiltLeft: return .toggleVoice
        case .shake: return .toggleMouse
        case .stemSingle: return .leftClick
        case .stemDouble: return .rightClick
        case .stemTriple: return .toggleVoice
        }
    }

    var isHeadGesture: Bool {
        switch self {
        case .nod, .tiltLeft, .tiltRight, .shake: return true
        default: return false
        }
    }
}

/// UserDefaults에 자동 저장되는 설정
final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    // 커서
    @Published var sensitivity: Double { didSet { d.set(sensitivity, forKey: "sensitivity") } }
    @Published var acceleration: Double { didSet { d.set(acceleration, forKey: "acceleration") } }
    @Published var deadzone: Double { didSet { d.set(deadzone, forKey: "deadzone") } }
    @Published var smoothing: Double { didSet { d.set(smoothing, forKey: "smoothing") } }
    @Published var invertX: Bool { didSet { d.set(invertX, forKey: "invertX") } }
    @Published var invertY: Bool { didSet { d.set(invertY, forKey: "invertY") } }
    @Published var scrollSpeed: Double { didSet { d.set(scrollSpeed, forKey: "scrollSpeed") } }
    /// 절대 모드: 고개 방향 = 화면 위치 (정면 = 중앙). 상대 모드: 움직인 만큼 이동 (트랙패드처럼)
    /// joystick: 기준에서 살짝 기울이면 그쪽으로 계속 이동 / absolute: 고개 방향 = 화면 위치 / relative: 움직인 만큼
    @Published var cursorMode: String { didSet { d.set(cursorMode, forKey: "cursorMode") } }
    var absoluteMode: Bool { cursorMode == "absolute" }
    var joystickMode: Bool { cursorMode == "joystick" }
    /// 조이스틱: ⌃⌥/ 를 누르고 있을 때만 이동 (떼면 커서 고정)
    @Published var joyRequiresKey: Bool { didSet { d.set(joyRequiresKey, forKey: "joyRequiresKey") } }
    @Published var joyMaxSpeed: Double { didSet { d.set(joyMaxSpeed, forKey: "joyMaxSpeed") } }
    @Published var joyDeadzone: Double { didSet { d.set(joyDeadzone, forKey: "joyDeadzone") } }
    @Published var joyRange: Double { didSet { d.set(joyRange, forKey: "joyRange") } }
    @Published var verticalBoost: Double { didSet { d.set(verticalBoost, forKey: "verticalBoost") } }
    @Published var yawRange: Double { didSet { d.set(yawRange, forKey: "yawRange") } }
    @Published var pitchRange: Double { didSet { d.set(pitchRange, forKey: "pitchRange") } }

    // 제스처
    @Published var gesturesEnabled: Bool { didSet { d.set(gesturesEnabled, forKey: "gesturesEnabled") } }
    @Published var nodThreshold: Double { didSet { d.set(nodThreshold, forKey: "nodThreshold") } }
    @Published var tiltAngle: Double { didSet { d.set(tiltAngle, forKey: "tiltAngle") } }
    @Published var shakeThreshold: Double { didSet { d.set(shakeThreshold, forKey: "shakeThreshold") } }
    @Published var invertTilt: Bool { didSet { d.set(invertTilt, forKey: "invertTilt") } }
    @Published var actions: [String: String] { didSet { d.set(actions, forKey: "actions") } }

    // 음성
    @Published var voiceLocale: String { didSet { d.set(voiceLocale, forKey: "voiceLocale") } }
    @Published var autoEnter: Bool { didSet { d.set(autoEnter, forKey: "autoEnter") } }
    @Published var voiceTargetBundleID: String { didSet { d.set(voiceTargetBundleID, forKey: "voiceTargetBundleID") } }

    // 기둥 버튼
    @Published var captureStem: Bool { didSet { d.set(captureStem, forKey: "captureStem") } }

    // 기타
    /// 앱 언어: "system"(시스템 따르기) / "ko" / "en"
    @Published var language: String { didSet { d.set(language, forKey: "language") } }
    var isKorean: Bool { language == "ko" || (language == "system" && Settings.systemIsKorean) }
    static var systemIsKorean: Bool { Locale.preferredLanguages.first?.hasPrefix("ko") ?? false }
    @Published var showHUD: Bool { didSet { d.set(showHUD, forKey: "showHUD") } }
    @Published var showGuideOnLaunch: Bool { didSet { d.set(showGuideOnLaunch, forKey: "showGuideOnLaunch") } }

    private init() {
        d.register(defaults: [
            "sensitivity": 22.0,
            "acceleration": 1.2,
            "deadzone": 3.0,
            "smoothing": 0.35,
            "invertX": false,
            "invertY": false,
            "scrollSpeed": 6.0,
            "cursorMode": "joystick",
            "joyRequiresKey": false,
            "joyMaxSpeed": 1400.0,
            "joyDeadzone": 4.0,
            "joyRange": 12.0,
            "verticalBoost": 1.6,
            "yawRange": 22.0,
            "pitchRange": 12.0,
            "gesturesEnabled": false,
            "nodThreshold": 110.0,
            "tiltAngle": 18.0,
            "shakeThreshold": 140.0,
            "invertTilt": false,
            "voiceLocale": Settings.systemIsKorean ? "ko-KR" : "en-US",
            "autoEnter": false,
            "voiceTargetBundleID": "",
            "captureStem": true,
            "showHUD": true,
            "showGuideOnLaunch": true,
            "language": "system",
        ])
        sensitivity = d.double(forKey: "sensitivity")
        acceleration = d.double(forKey: "acceleration")
        deadzone = d.double(forKey: "deadzone")
        smoothing = d.double(forKey: "smoothing")
        invertX = d.bool(forKey: "invertX")
        invertY = d.bool(forKey: "invertY")
        scrollSpeed = d.double(forKey: "scrollSpeed")
        cursorMode = d.string(forKey: "cursorMode") ?? "joystick"
        joyRequiresKey = d.bool(forKey: "joyRequiresKey")
        joyMaxSpeed = d.double(forKey: "joyMaxSpeed")
        joyDeadzone = d.double(forKey: "joyDeadzone")
        joyRange = d.double(forKey: "joyRange")
        verticalBoost = d.double(forKey: "verticalBoost")
        yawRange = d.double(forKey: "yawRange")
        pitchRange = d.double(forKey: "pitchRange")
        gesturesEnabled = d.bool(forKey: "gesturesEnabled")
        nodThreshold = d.double(forKey: "nodThreshold")
        tiltAngle = d.double(forKey: "tiltAngle")
        shakeThreshold = d.double(forKey: "shakeThreshold")
        invertTilt = d.bool(forKey: "invertTilt")
        actions = (d.dictionary(forKey: "actions") as? [String: String]) ?? [:]
        voiceLocale = d.string(forKey: "voiceLocale") ?? (Settings.systemIsKorean ? "ko-KR" : "en-US")
        autoEnter = d.bool(forKey: "autoEnter")
        voiceTargetBundleID = d.string(forKey: "voiceTargetBundleID") ?? ""
        captureStem = d.bool(forKey: "captureStem")
        showHUD = d.bool(forKey: "showHUD")
        showGuideOnLaunch = d.bool(forKey: "showGuideOnLaunch")
        language = d.string(forKey: "language") ?? "system"
    }

    /// 앱 언어를 바꾸면 음성 인식 언어도 한국어/영어에 맞춰 같이 바꿈 (다른 언어를 골라 둔 경우는 그대로)
    func setLanguage(_ lang: String) {
        language = lang
        if voiceLocale == "ko-KR" || voiceLocale == "en-US" { voiceLocale = isKorean ? "ko-KR" : "en-US" }
    }

    func action(for trigger: PodTrigger) -> PodAction {
        if let raw = actions[trigger.rawValue], let a = PodAction(rawValue: raw) { return a }
        return trigger.defaultAction
    }

    func setAction(_ action: PodAction, for trigger: PodTrigger) {
        actions[trigger.rawValue] = action.rawValue
    }

    func resetToDefaults() {
        for key in ["sensitivity", "acceleration", "deadzone", "smoothing", "invertX", "invertY",
                    "scrollSpeed", "cursorMode", "joyRequiresKey", "joyMaxSpeed", "joyDeadzone", "joyRange", "verticalBoost", "yawRange", "pitchRange", "gesturesEnabled", "nodThreshold", "tiltAngle", "shakeThreshold",
                    "invertTilt", "actions"] {
            d.removeObject(forKey: key)
        }
        sensitivity = d.double(forKey: "sensitivity")
        acceleration = d.double(forKey: "acceleration")
        deadzone = d.double(forKey: "deadzone")
        smoothing = d.double(forKey: "smoothing")
        invertX = d.bool(forKey: "invertX")
        invertY = d.bool(forKey: "invertY")
        scrollSpeed = d.double(forKey: "scrollSpeed")
        cursorMode = d.string(forKey: "cursorMode") ?? "joystick"
        joyRequiresKey = d.bool(forKey: "joyRequiresKey")
        joyMaxSpeed = d.double(forKey: "joyMaxSpeed")
        joyDeadzone = d.double(forKey: "joyDeadzone")
        joyRange = d.double(forKey: "joyRange")
        verticalBoost = d.double(forKey: "verticalBoost")
        yawRange = d.double(forKey: "yawRange")
        pitchRange = d.double(forKey: "pitchRange")
        gesturesEnabled = d.bool(forKey: "gesturesEnabled")
        nodThreshold = d.double(forKey: "nodThreshold")
        tiltAngle = d.double(forKey: "tiltAngle")
        shakeThreshold = d.double(forKey: "shakeThreshold")
        invertTilt = d.bool(forKey: "invertTilt")
        actions = [:]
    }
}
