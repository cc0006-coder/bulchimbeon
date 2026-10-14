import Foundation

/// 한국어·영어 UI. 시스템 첫 번째 선호 언어가 한국어면 한국어, 아니면 영어.
public enum L10n {
    public enum Language: Sendable { case ko, en }

    public static let language: Language = detect()

    public static func detect(_ preferred: [String] = Locale.preferredLanguages) -> Language {
        preferred.first?.hasPrefix("ko") == true ? .ko : .en
    }

    /// 메뉴의 언어 선택. 앱 전용 설정(`AppleLanguages`, 앱 도메인)으로 저장한다.
    public enum Preference: String, CaseIterable, Sendable {
        case system, ko, en

        /// 앱 도메인에 저장할 값. nil 이면 설정을 지워 시스템 언어를 따른다.
        public var appleLanguages: [String]? {
            switch self {
            case .system: nil
            case .ko: ["ko"]
            case .en: ["en"]
            }
        }

        /// 앱 도메인에 저장된 값 → 선택 (전역 설정이 섞인 값이 아니라 앱 도메인 값만 넣어야 한다)
        public init(appDomainLanguages: [String]?) {
            switch appDomainLanguages?.first {
            case let first? where first.hasPrefix("ko"): self = .ko
            case let first? where first.hasPrefix("en"): self = .en
            default: self = .system
            }
        }

        public var title: String {
            switch self {
            case .system: "시스템 설정 따름 (System)"
            case .ko: "한국어"
            case .en: "English"
            }
        }
    }

    public static func t(_ ko: String, _ en: String, _ lang: Language = language) -> String {
        lang == .ko ? ko : en
    }
}
