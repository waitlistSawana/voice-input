import Foundation
import Testing
@testable import VoiceInputCore

struct SettingsStoreTests {
    @Test func localeDefaultsToSimplifiedChineseWhenNothingStored() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let store = SettingsStore(defaults: defaults)

        #expect(store.selectedLocale == .simplifiedChinese)
    }

    @Test func apiKeyCanBeClearedBackToEmptyString() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let store = SettingsStore(defaults: defaults)
        store.llmConfiguration = LLMConfiguration(baseURL: "https://example.com", apiKey: "secret", model: "gpt")
        store.llmConfiguration = LLMConfiguration(baseURL: "https://example.com", apiKey: "", model: "gpt")

        #expect(store.llmConfiguration.apiKey == "")
    }

    @Test func llmConfigurationRejectsWhitespaceOnlyApiKey() {
        let configuration = LLMConfiguration(baseURL: "https://example.com", apiKey: "   ", model: "gpt-4.1-mini")
        #expect(!configuration.isComplete)
    }

    @Test func llmConfigurationAcceptsWhitespacePaddedBaseURLAfterNormalization() {
        let configuration = LLMConfiguration(baseURL: "  https://example.com  ", apiKey: "secret", model: "gpt-4.1-mini")
        #expect(configuration.isComplete)
        #expect(configuration.normalizedURL == URL(string: "https://example.com"))
        #expect(configuration.normalizedBaseURLString == "https://example.com")
    }

    @Test func llmConfigurationRejectsMalformedBaseURL() {
        let configuration = LLMConfiguration(baseURL: "not a url", apiKey: "secret", model: "gpt-4.1-mini")
        #expect(!configuration.isComplete)
    }

    @Test func llmConfigurationIsCompleteOnlyWhenAllFieldsArePresent() {
        let configuration = LLMConfiguration(baseURL: "https://example.com", apiKey: "secret", model: "gpt-4.1-mini")
        #expect(configuration.isComplete)
    }

    @Test func invalidStoredLocaleFallsBackToDefaultLocale() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set("xx-XX", forKey: AppDefaults.Key.selectedLocale)

        let store = SettingsStore(defaults: defaults)

        #expect(store.selectedLocale == AppDefaults.defaultLocale)
    }

    @Test func localeMenuTitlesAreLocalizedForSupportedLocales() {
        #expect(AppLocale.allCases.map(\.menuTitle) == ["English", "简体中文", "繁体中文", "日本語", "한국어"])
    }
}
