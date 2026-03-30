import AppKit
import Foundation
import Testing
@testable import VoiceInputCore
@testable import VoiceInputUI

struct MenuStateTests {
    final class RebuildProbe: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var wasLastRebuildOnMainThread = false

        func recordRebuild(onMainThread: Bool) {
            lock.lock()
            wasLastRebuildOnMainThread = onMainThread
            lock.unlock()
        }

        func lastRebuildOnMainThread() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return wasLastRebuildOnMainThread
        }
    }

    @MainActor
    @Test func controllerBuildsRequiredMenuStructure() throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let notificationCenter = NotificationCenter()
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }

        let controller = StatusBarController(
            statusItem: statusItem,
            settingsStore: SettingsStore(defaults: defaults, notificationCenter: notificationCenter),
            notificationCenter: notificationCenter,
            openSettings: {}
        )

        let menu = try #require(controller.menu)
        #expect(menu.items.map { $0.title } == ["Language", "LLM Refinement", "", "Quit"])

        let languageMenu = try #require(menu.items[0].submenu)
        #expect(languageMenu.items.map { $0.title } == ["English", "简体中文", "繁体中文", "日本語", "한국어"])

        let llmMenu = try #require(menu.items[1].submenu)
        #expect(llmMenu.items.map { $0.title } == ["Enable Refinement", "Settings..."])
        #expect(menu.items[3].title == "Quit")
    }

    @MainActor
    @Test func externalSettingsChangesRefreshLlmToggleAvailability() throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let notificationCenter = NotificationCenter()
        let store = SettingsStore(defaults: defaults, notificationCenter: notificationCenter)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }

        store.isLLMRefinementEnabled = true
        let controller = StatusBarController(
            statusItem: statusItem,
            settingsStore: store,
            notificationCenter: notificationCenter,
            onMenuRebuilt: nil,
            openSettings: {}
        )

        let llmToggleBefore = try #require(controller.menu?.items[1].submenu?.items.first)
        #expect(llmToggleBefore.title == "Enable Refinement")
        #expect(!llmToggleBefore.isEnabled)
        #expect(llmToggleBefore.state == NSControl.StateValue.off)

        store.llmConfiguration = LLMConfiguration(baseURL: "https://example.com", apiKey: "secret", model: "gpt")

        let llmToggleAfter = try #require(controller.menu?.items[1].submenu?.items.first)
        #expect(llmToggleAfter.isEnabled)
        #expect(llmToggleAfter.state == NSControl.StateValue.on)
    }

    @MainActor
    @Test func backgroundSettingsChangesRebuildMenuOnMainThread() async throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let notificationCenter = NotificationCenter()
        let store = SettingsStore(defaults: defaults, notificationCenter: notificationCenter)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let probe = RebuildProbe()

        let controller = StatusBarController(
            statusItem: statusItem,
            settingsStore: store,
            notificationCenter: notificationCenter,
            onMenuRebuilt: {
                probe.recordRebuild(onMainThread: Thread.isMainThread)
            },
            openSettings: {}
        )

        _ = controller
        await Task.detached {
            store.llmConfiguration = LLMConfiguration(baseURL: "https://example.com", apiKey: "secret", model: "gpt")
        }.value

        for _ in 0..<20 {
            if let llmToggle = controller.menu?.items[1].submenu?.items.first, llmToggle.isEnabled {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let llmToggle = try #require(controller.menu?.items[1].submenu?.items.first)
        #expect(llmToggle.isEnabled)
        #expect(probe.lastRebuildOnMainThread())
    }
}
