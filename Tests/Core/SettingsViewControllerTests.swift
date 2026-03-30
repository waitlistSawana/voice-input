import AppKit
import Foundation
import Testing
@testable import VoiceInputCore
@testable import VoiceInputUI

struct SettingsViewControllerTests {
    private final class ConnectionProbe: @unchecked Sendable {
        var receivedConfiguration: LLMConfiguration?
    }

    @Test @MainActor func viewLoadsStoredApiSettingsAndAllowsClearingApiKey() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = SettingsStore(defaults: defaults)
        store.llmConfiguration = LLMConfiguration(
            baseURL: "https://example.com/v1",
            apiKey: "secret",
            model: "gpt-4.1-mini"
        )

        let controller = SettingsViewController(
            dependencies: .init(settingsStore: store)
        )
        controller.loadViewIfNeeded()

        #expect(controller.apiBaseURLField.stringValue == "https://example.com/v1")
        #expect(controller.apiKeyField.stringValue == "secret")
        #expect(controller.modelField.stringValue == "gpt-4.1-mini")

        controller.apiKeyField.stringValue = ""
        controller.saveButton.performClick(nil as Any?)

        #expect(store.llmConfiguration.apiKey == "")
    }

    @Test @MainActor func testButtonUsesInjectedConnectionActionWithCurrentFieldValues() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = SettingsStore(defaults: defaults)

        let probe = ConnectionProbe()
        let controller = SettingsViewController(
            dependencies: .init(
                settingsStore: store,
                onTestConnection: { configuration in
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    probe.receivedConfiguration = configuration
                    return .success(())
                }
            )
        )
        controller.loadViewIfNeeded()

        controller.apiBaseURLField.stringValue = "https://api.example.com"
        controller.apiKeyField.stringValue = "abc123"
        controller.modelField.stringValue = "gpt-4.1-mini"

        controller.testConnectionAction()
        #expect(!controller.testButton.isEnabled)

        for _ in 0 ..< 100 {
            if probe.receivedConfiguration != nil, controller.testButton.isEnabled {
                break
            }

            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(probe.receivedConfiguration == LLMConfiguration(
            baseURL: "https://api.example.com",
            apiKey: "abc123",
            model: "gpt-4.1-mini"
        ))
        #expect(controller.testButton.isEnabled)
    }
}
