import Foundation

/// 한국어/영어 중 지금 언어에 맞는 문자열 (설정 → 앱 언어: 시스템 따르기 / 한국어 / English)
func L(_ ko: String, _ en: String) -> String {
    Settings.shared.isKorean ? ko : en
}
