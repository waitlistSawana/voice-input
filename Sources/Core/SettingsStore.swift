import Foundation

public final class SettingsStore {
    public static let didChangeNotification = Notification.Name("SettingsStore.didChange")

    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter

    public init(defaults: UserDefaults = .standard, notificationCenter: NotificationCenter = .default) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
    }

    public var selectedLocale: AppLocale {
        get {
            guard
                let rawValue = defaults.string(forKey: AppDefaults.Key.selectedLocale),
                let locale = AppLocale(rawValue: rawValue)
            else {
                return AppDefaults.defaultLocale
            }
            return locale
        }
        set {
            defaults.set(newValue.rawValue, forKey: AppDefaults.Key.selectedLocale)
            postDidChange()
        }
    }

    public var isLLMRefinementEnabled: Bool {
        get { defaults.bool(forKey: AppDefaults.Key.llmEnabled) }
        set {
            defaults.set(newValue, forKey: AppDefaults.Key.llmEnabled)
            postDidChange()
        }
    }

    public var llmConfiguration: LLMConfiguration {
        get {
            LLMConfiguration(
                baseURL: defaults.string(forKey: AppDefaults.Key.llmBaseURL) ?? "",
                apiKey: defaults.string(forKey: AppDefaults.Key.llmAPIKey) ?? "",
                model: defaults.string(forKey: AppDefaults.Key.llmModel) ?? ""
            )
        }
        set {
            defaults.set(newValue.baseURL, forKey: AppDefaults.Key.llmBaseURL)
            defaults.set(newValue.apiKey, forKey: AppDefaults.Key.llmAPIKey)
            defaults.set(newValue.model, forKey: AppDefaults.Key.llmModel)
            postDidChange()
        }
    }

    private func postDidChange() {
        notificationCenter.post(name: Self.didChangeNotification, object: self)
    }
}
