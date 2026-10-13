import Foundation

/// 한국어·영어 UI. 시스템 첫 번째 선호 언어가 한국어면 한국어, 아니면 영어.
public enum L10n {
    public enum Language: Sendable { case ko, en }

    public static let language: Language = detect()

    public static func detect(_ preferred: [String] = Locale.preferredLanguages) -> Language {
        preferred.first?.hasPrefix("ko") == true ? .ko : .en
    }

    public static func t(_ ko: String, _ en: String, _ lang: Language = language) -> String {
        lang == .ko ? ko : en
    }
}
