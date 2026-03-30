public enum AppDefaults {
    public static let defaultLocaleIdentifier = "zh-CN"

    public static let defaultLocale = AppLocale(rawValue: defaultLocaleIdentifier) ?? .simplifiedChinese

    public enum Key {
        public static let selectedLocale = "selectedLocale"
        public static let llmEnabled = "llmEnabled"
        public static let llmBaseURL = "llmBaseURL"
        public static let llmAPIKey = "llmAPIKey"
        public static let llmModel = "llmModel"
    }
}

public enum AppLocale: String, CaseIterable, Sendable {
    case english = "en-US"
    case simplifiedChinese = "zh-CN"
    case traditionalChinese = "zh-TW"
    case japanese = "ja-JP"
    case korean = "ko-KR"

    public var menuTitle: String {
        switch self {
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        case .traditionalChinese:
            return "繁体中文"
        case .japanese:
            return "日本語"
        case .korean:
            return "한국어"
        }
    }
}
