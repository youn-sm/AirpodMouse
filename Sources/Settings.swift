import Foundation
import Combine

/// 기둥 버튼에 연결할 수 있는 동작
enum PodAction: String, CaseIterable, Identifiable, Codable {
    case none
    case leftClick
    case rightClick
    case doubleClick
    case toggleDrag
    case toggleDwell
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
        case .toggleDwell: return L("머무르면 클릭 켜기/끄기", "Toggle dwell click")
        case .toggleMouse: return L("마우스 모드 켜기/끄기", "Toggle mouse mode")
        case .toggleScroll: return L("스크롤 모드 켜기/끄기", "Toggle scroll mode")
        case .recenter: return L("커서 화면 중앙으로", "Center cursor")
        case .pressEnter: return L("Enter 키", "Enter key")
        case .pressEscape: return L("Esc 키", "Esc key")
        }
    }
}

/// 에어팟 기둥 누르기 종류
enum PodTrigger: String, CaseIterable, Identifiable {
    case stemSingle   // 기둥 1번 누르기
    case stemDouble   // 기둥 2번 누르기
    case stemTriple   // 기둥 3번 누르기

    var id: String { rawValue }

    var label: String {
        switch self {
        case .stemSingle: return L("기둥 1번 누르기", "Stem press ×1")
        case .stemDouble: return L("기둥 2번 누르기", "Stem press ×2")
        case .stemTriple: return L("기둥 3번 누르기", "Stem press ×3")
        }
    }

    var defaultAction: PodAction {
        switch self {
        case .stemSingle: return .leftClick
        case .stemDouble: return .rightClick
        case .stemTriple: return .toggleDwell
        }
    }
}

/// UserDefaults에 자동 저장되는 설정
final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    // 커서
    /// 천천히 움직일 때 커서 이득 (px/°)
    @Published var sensitivity: Double { didSet { d.set(sensitivity, forKey: "sensitivity") } }
    /// 빠르게 움직일 때 추가 이득 (0 = 가속 없음)
    @Published var acceleration: Double { didSet { d.set(acceleration, forKey: "acceleration") } }
    /// 떨림 거르기 0~1 (높을수록 강하게, 대신 살짝 느려짐)
    @Published var smoothing: Double { didSet { d.set(smoothing, forKey: "smoothing") } }
    /// 이 속도(°/s)보다 느리면 커서 고정 (드리프트·떨림 흡수)
    @Published var stillness: Double { didSet { d.set(stillness, forKey: "stillness") } }
    @Published var invertX: Bool { didSet { d.set(invertX, forKey: "invertX") } }
    @Published var invertY: Bool { didSet { d.set(invertY, forKey: "invertY") } }
    @Published var scrollSpeed: Double { didSet { d.set(scrollSpeed, forKey: "scrollSpeed") } }

    // 머무르면 클릭
    @Published var dwellEnabled: Bool { didSet { d.set(dwellEnabled, forKey: "dwellEnabled") } }
    @Published var dwellTime: Double { didSet { d.set(dwellTime, forKey: "dwellTime") } }
    @Published var dwellRadius: Double { didSet { d.set(dwellRadius, forKey: "dwellRadius") } }

    // 기둥 버튼
    @Published var actions: [String: String] { didSet { d.set(actions, forKey: "actions") } }
    @Published var captureStem: Bool { didSet { d.set(captureStem, forKey: "captureStem") } }

    // 기타
    /// 앱 언어: "system"(시스템 따르기) / "ko" / "en"
    @Published var language: String { didSet { d.set(language, forKey: "language") } }
    var isKorean: Bool { language == "ko" || (language == "system" && Settings.systemIsKorean) }
    static var systemIsKorean: Bool { Locale.preferredLanguages.first?.hasPrefix("ko") ?? false }
    @Published var showHUD: Bool { didSet { d.set(showHUD, forKey: "showHUD") } }
    @Published var showGuideOnLaunch: Bool { didSet { d.set(showGuideOnLaunch, forKey: "showGuideOnLaunch") } }

    /// '기본값으로' 버튼이 되돌리는 항목
    private static let tunableDefaults: [String: Any] = [
        "sensitivity": 14.0,
        "acceleration": 2.5,
        "smoothing": 0.6,
        "stillness": 4.0,
        "invertX": false,
        "invertY": false,
        "scrollSpeed": 6.0,
        "dwellTime": 0.7,
        "dwellRadius": 10.0,
        "actions": [String: String](),
    ]

    private init() {
        d.register(defaults: Self.tunableDefaults.merging([
            "dwellEnabled": false,
            "captureStem": true,
            "showHUD": true,
            "showGuideOnLaunch": true,
            "language": "system",
        ]) { a, _ in a })
        sensitivity = 0; acceleration = 0; smoothing = 0; stillness = 0
        invertX = false; invertY = false; scrollSpeed = 0
        dwellEnabled = false; dwellTime = 0; dwellRadius = 0
        actions = [:]; captureStem = false
        language = "system"; showHUD = false; showGuideOnLaunch = false
        load()
    }

    private func load() {
        sensitivity = d.double(forKey: "sensitivity")
        acceleration = d.double(forKey: "acceleration")
        smoothing = d.double(forKey: "smoothing")
        stillness = d.double(forKey: "stillness")
        invertX = d.bool(forKey: "invertX")
        invertY = d.bool(forKey: "invertY")
        scrollSpeed = d.double(forKey: "scrollSpeed")
        dwellEnabled = d.bool(forKey: "dwellEnabled")
        dwellTime = d.double(forKey: "dwellTime")
        dwellRadius = d.double(forKey: "dwellRadius")
        actions = (d.dictionary(forKey: "actions") as? [String: String]) ?? [:]
        captureStem = d.bool(forKey: "captureStem")
        language = d.string(forKey: "language") ?? "system"
        showHUD = d.bool(forKey: "showHUD")
        showGuideOnLaunch = d.bool(forKey: "showGuideOnLaunch")
    }

    func setLanguage(_ lang: String) {
        language = lang
    }

    func action(for trigger: PodTrigger) -> PodAction {
        if let raw = actions[trigger.rawValue], let a = PodAction(rawValue: raw) { return a }
        return trigger.defaultAction
    }

    func setAction(_ action: PodAction, for trigger: PodTrigger) {
        actions[trigger.rawValue] = action.rawValue
    }

    func resetToDefaults() {
        for key in Self.tunableDefaults.keys { d.removeObject(forKey: key) }
        load()
    }
}
