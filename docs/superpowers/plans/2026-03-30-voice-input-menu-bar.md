# Voice Input Menu Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS 14+ Swift menu-bar app that records while `Fn` is held, streams speech recognition with `zh-CN` as the default locale, optionally refines transcripts through an OpenAI-compatible API, and pastes the final text into the focused input after temporarily switching away from CJK input methods.

**Architecture:** The app is a single-process AppKit `LSUIElement` utility. A central `SpeechSessionController` coordinates hotkey events, audio capture, speech recognition, HUD updates, optional LLM refinement, and final text injection. Supporting services isolate configuration, permissions, input source management, clipboard restoration, and floating HUD rendering so the session flow remains linear and testable.

**Tech Stack:** Swift 5.10+, Swift Package Manager, AppKit, AVFoundation, Speech, Carbon HIToolbox/TextInputSources, Core Graphics event taps, URLSession, XCTest

---

### Task 1: Scaffold the SwiftPM app bundle and build pipeline

**Files:**
- Create: `Package.swift`
- Create: `Makefile`
- Create: `Resources/Info.plist`
- Create: `Resources/App.entitlements`
- Create: `Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `Sources/AppMain/VoiceInputApp.swift`
- Create: `Sources/AppMain/AppDelegate.swift`
- Test: `Tests/Smoke/BundleLayoutSmokeTests.swift`

- [ ] **Step 1: Write the failing smoke test for bundle metadata**

```swift
import XCTest
@testable import VoiceInputCore

final class BundleLayoutSmokeTests: XCTestCase {
    func testDefaultLocaleConstantIsChinese() {
        XCTAssertEqual(AppDefaults.defaultLocaleIdentifier, "zh-CN")
    }

    func testSupportedLocalesIncludeFiveMenuLanguages() {
        XCTAssertEqual(
            AppLocale.allCases.map(\.rawValue),
            ["en-US", "zh-CN", "zh-TW", "ja-JP", "ko-KR"]
        )
    }
}
```

- [ ] **Step 2: Run the smoke test to verify it fails because the package does not exist yet**

Run: `swift test --filter BundleLayoutSmokeTests`

Expected: FAIL with package or module resolution errors because `Package.swift` and the source targets are not created yet.

- [ ] **Step 3: Create the package manifest, minimal app entrypoint, resources, and build script**

```swift
// Package.swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VoiceInput",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "VoiceInputCore", targets: ["VoiceInputCore"]),
        .executable(name: "VoiceInputApp", targets: ["VoiceInputApp"])
    ],
    targets: [
        .target(
            name: "VoiceInputCore",
            path: "Sources/Core"
        ),
        .target(
            name: "VoiceInputUI",
            dependencies: ["VoiceInputCore"],
            path: "Sources/UI"
        ),
        .executableTarget(
            name: "VoiceInputApp",
            dependencies: ["VoiceInputCore", "VoiceInputUI"],
            path: "Sources/AppMain",
            resources: [
                .copy("../../Resources/Info.plist"),
                .copy("../../Resources/App.entitlements"),
                .copy("../../Resources/Assets.xcassets")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics")
            ]
        ),
        .testTarget(
            name: "VoiceInputTests",
            dependencies: ["VoiceInputCore"],
            path: "Tests"
        )
    ]
)
```

```make
# Makefile
APP_NAME := VoiceInput
BUILD_DIR := .build
DIST_DIR := dist
CONFIG ?= debug
APP_DIR := $(DIST_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources

.PHONY: build run install clean

build:
	swift build -c $(CONFIG) --product VoiceInputApp
	rm -rf $(APP_DIR)
	mkdir -p $(MACOS_DIR) $(RESOURCES_DIR)
	cp .build/$(CONFIG)/VoiceInputApp $(MACOS_DIR)/$(APP_NAME)
	cp Resources/Info.plist $(CONTENTS_DIR)/Info.plist
	cp -R Resources/Assets.xcassets $(RESOURCES_DIR)/Assets.xcassets
	codesign --force --sign - --entitlements Resources/App.entitlements $(APP_DIR)

run: build
	open $(APP_DIR)

install: build
	rm -rf /Applications/$(APP_NAME).app
	cp -R $(APP_DIR) /Applications/$(APP_NAME).app

clean:
	rm -rf $(BUILD_DIR) $(DIST_DIR)
```

```xml
<!-- Resources/Info.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>VoiceInput</string>
    <key>CFBundleIdentifier</key>
    <string>local.vibe.voice-input</string>
    <key>CFBundleName</key>
    <string>VoiceInput</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>VoiceInput needs speech recognition access to transcribe your recording.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>VoiceInput needs microphone access to record speech while you hold Fn.</string>
</dict>
</plist>
```

```xml
<!-- Resources/App.entitlements -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
```

```json
// Resources/Assets.xcassets/AppIcon.appiconset/Contents.json
{
  "images": [
    {
      "idiom": "mac",
      "scale": "1x",
      "size": "16x16"
    },
    {
      "idiom": "mac",
      "scale": "2x",
      "size": "16x16"
    },
    {
      "idiom": "mac",
      "scale": "1x",
      "size": "32x32"
    },
    {
      "idiom": "mac",
      "scale": "2x",
      "size": "32x32"
    },
    {
      "idiom": "mac",
      "scale": "1x",
      "size": "128x128"
    },
    {
      "idiom": "mac",
      "scale": "2x",
      "size": "128x128"
    },
    {
      "idiom": "mac",
      "scale": "1x",
      "size": "256x256"
    },
    {
      "idiom": "mac",
      "scale": "2x",
      "size": "256x256"
    },
    {
      "idiom": "mac",
      "scale": "1x",
      "size": "512x512"
    },
    {
      "idiom": "mac",
      "scale": "2x",
      "size": "512x512"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
```

```swift
// Sources/AppMain/VoiceInputApp.swift
import AppKit

@main
struct VoiceInputApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}
```

```swift
// Sources/AppMain/AppDelegate.swift
import AppKit
import VoiceInputCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
    }
}
```

- [ ] **Step 4: Add the core constants needed by the smoke test**

```swift
// Sources/Core/AppDefaults.swift
public enum AppDefaults {
    public static let defaultLocaleIdentifier = "zh-CN"
}

public enum AppLocale: String, CaseIterable {
    case english = "en-US"
    case simplifiedChinese = "zh-CN"
    case traditionalChinese = "zh-TW"
    case japanese = "ja-JP"
    case korean = "ko-KR"
}
```

- [ ] **Step 5: Run the smoke test and verify it passes**

Run: `swift test --filter BundleLayoutSmokeTests`

Expected: PASS with 2 executed tests and no package-resolution failures.

- [ ] **Step 6: Commit the scaffold**

```bash
test -d .git || git init
git add Package.swift Makefile Resources Sources Tests
git commit -m "feat: scaffold voice input menu bar app"
```

### Task 2: Implement persisted settings, locale labels, and LLM configuration validation

**Files:**
- Create: `Sources/Core/SettingsStore.swift`
- Create: `Sources/Core/LLMConfiguration.swift`
- Create: `Tests/Core/SettingsStoreTests.swift`
- Modify: `Sources/Core/AppDefaults.swift`

- [ ] **Step 1: Write the failing tests for default language and LLM config completeness**

```swift
import XCTest
@testable import VoiceInputCore

final class SettingsStoreTests: XCTestCase {
    func testLocaleDefaultsToSimplifiedChineseWhenNothingStored() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.selectedLocale, .simplifiedChinese)
    }

    func testSavingApiKeyAllowsClearingItBackToEmptyString() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = SettingsStore(defaults: defaults)

        store.llmConfiguration = LLMConfiguration(baseURL: "https://example.com", apiKey: "secret", model: "gpt")
        store.llmConfiguration = LLMConfiguration(baseURL: "https://example.com", apiKey: "", model: "gpt")

        XCTAssertEqual(store.llmConfiguration.apiKey, "")
    }

    func testRefinementRequiresEnabledFlagAndAllFields() {
        var config = LLMConfiguration(baseURL: "https://example.com", apiKey: "secret", model: "gpt-4.1-mini")
        XCTAssertTrue(config.isComplete)

        config = LLMConfiguration(baseURL: "", apiKey: "secret", model: "gpt-4.1-mini")
        XCTAssertFalse(config.isComplete)
    }
}
```

- [ ] **Step 2: Run the settings tests to verify they fail because the store is missing**

Run: `swift test --filter SettingsStoreTests`

Expected: FAIL with `cannot find 'SettingsStore' in scope` and `cannot find 'LLMConfiguration' in scope`.

- [ ] **Step 3: Implement locale metadata, the LLM configuration type, and the settings store**

```swift
// Sources/Core/AppDefaults.swift
public enum AppDefaults {
    public static let defaultLocaleIdentifier = "zh-CN"

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
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁体中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        }
    }
}
```

```swift
// Sources/Core/LLMConfiguration.swift
public struct LLMConfiguration: Equatable, Sendable {
    public var baseURL: String
    public var apiKey: String
    public var model: String

    public init(baseURL: String = "", apiKey: String = "", model: String = "") {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
    }

    public var isComplete: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.isEmpty &&
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
```

```swift
// Sources/Core/SettingsStore.swift
import Foundation

public final class SettingsStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var selectedLocale: AppLocale {
        get {
            guard
                let raw = defaults.string(forKey: AppDefaults.Key.selectedLocale),
                let locale = AppLocale(rawValue: raw)
            else {
                return .simplifiedChinese
            }
            return locale
        }
        set {
            defaults.set(newValue.rawValue, forKey: AppDefaults.Key.selectedLocale)
        }
    }

    public var isLLMRefinementEnabled: Bool {
        get { defaults.bool(forKey: AppDefaults.Key.llmEnabled) }
        set { defaults.set(newValue, forKey: AppDefaults.Key.llmEnabled) }
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
        }
    }
}
```

- [ ] **Step 4: Run the settings tests and verify they pass**

Run: `swift test --filter SettingsStoreTests`

Expected: PASS with 3 executed tests.

- [ ] **Step 5: Commit the settings layer**

```bash
git add Sources/Core/AppDefaults.swift Sources/Core/SettingsStore.swift Sources/Core/LLMConfiguration.swift Tests/Core/SettingsStoreTests.swift
git commit -m "feat: add persisted locale and llm settings"
```

### Task 3: Add the menu bar controller and the Settings window shell

**Files:**
- Create: `Sources/UI/StatusBarController.swift`
- Create: `Sources/UI/SettingsWindowController.swift`
- Create: `Sources/UI/SettingsViewController.swift`
- Modify: `Sources/AppMain/AppDelegate.swift`
- Test: `Tests/Core/MenuStateTests.swift`

- [ ] **Step 1: Write the failing tests for menu labels and toggle state**

```swift
import XCTest
@testable import VoiceInputCore

final class MenuStateTests: XCTestCase {
    func testLanguageMenuItemsAppearInExpectedOrder() {
        XCTAssertEqual(AppLocale.allCases.map(\.menuTitle), ["English", "简体中文", "繁体中文", "日本語", "한국어"])
    }

    func testLlmAvailabilityDependsOnStoredConfiguration() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = SettingsStore(defaults: defaults)

        XCTAssertFalse(store.llmConfiguration.isComplete)

        store.llmConfiguration = LLMConfiguration(baseURL: "https://example.com", apiKey: "secret", model: "gpt")
        XCTAssertTrue(store.llmConfiguration.isComplete)
    }
}
```

- [ ] **Step 2: Run the menu tests to verify they fail because the UI shell is not wired yet**

Run: `swift test --filter MenuStateTests`

Expected: FAIL if the tests target missing or incomplete menu-related state.

- [ ] **Step 3: Implement the status item and settings window shell**

```swift
// Sources/UI/StatusBarController.swift
import AppKit
import VoiceInputCore

public final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let settingsStore: SettingsStore
    private let openSettings: () -> Void

    public init(settingsStore: SettingsStore, openSettings: @escaping () -> Void) {
        self.settingsStore = settingsStore
        self.openSettings = openSettings
        super.init()
        configureStatusItem()
        rebuildMenu()
    }

    public func rebuildMenu() {
        let menu = NSMenu()

        let languageMenu = NSMenu()
        for locale in AppLocale.allCases {
            let item = NSMenuItem(title: locale.menuTitle, action: #selector(selectLocale(_:)), keyEquivalent: "")
            item.target = self
            item.state = settingsStore.selectedLocale == locale ? .on : .off
            item.representedObject = locale.rawValue
            languageMenu.addItem(item)
        }

        let languageItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        menu.setSubmenu(languageMenu, for: languageItem)
        menu.addItem(languageItem)

        let llmMenu = NSMenu()
        let toggleItem = NSMenuItem(title: "Enable Refinement", action: #selector(toggleRefinement(_:)), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.state = settingsStore.isLLMRefinementEnabled ? .on : .off
        llmMenu.addItem(toggleItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        llmMenu.addItem(settingsItem)

        let llmItem = NSMenuItem(title: "LLM Refinement", action: nil, keyEquivalent: "")
        menu.setSubmenu(llmMenu, for: llmItem)
        menu.addItem(llmItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func configureStatusItem() {
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Voice Input")
    }

    @objc private func selectLocale(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let locale = AppLocale(rawValue: raw) else { return }
        settingsStore.selectedLocale = locale
        rebuildMenu()
    }

    @objc private func toggleRefinement(_ sender: NSMenuItem) {
        settingsStore.isLLMRefinementEnabled.toggle()
        rebuildMenu()
    }

    @objc private func openSettingsAction() {
        openSettings()
    }

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }
}
```

```swift
// Sources/UI/SettingsViewController.swift
import AppKit
import VoiceInputCore

public final class SettingsViewController: NSViewController {
    public init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 220))
    }
}
```

```swift
// Sources/UI/SettingsWindowController.swift
import AppKit

public final class SettingsWindowController: NSWindowController {
    public init(rootViewController: NSViewController = SettingsViewController()) {
        let window = NSWindow(contentViewController: rootViewController)
        window.title = "LLM Settings"
        window.setContentSize(NSSize(width: 480, height: 220))
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

```swift
// Sources/AppMain/AppDelegate.swift
import AppKit
import VoiceInputCore
import VoiceInputUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private var statusBarController: StatusBarController?
    private lazy var settingsWindowController = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(settingsStore: settingsStore) { [weak self] in
            self?.settingsWindowController.present()
        }
    }
}
```

- [ ] **Step 4: Run the menu tests and verify they pass**

Run: `swift test --filter MenuStateTests`

Expected: PASS with 2 executed tests.

- [ ] **Step 5: Commit the menu shell**

```bash
git add Sources/UI/StatusBarController.swift Sources/UI/SettingsWindowController.swift Sources/UI/SettingsViewController.swift Sources/AppMain/AppDelegate.swift Tests/Core/MenuStateTests.swift
git commit -m "feat: add status bar menu and settings shell"
```

### Task 4: Add permission checks and the Fn hotkey monitor

**Files:**
- Create: `Sources/Core/PermissionsManager.swift`
- Create: `Sources/Core/HotkeyMonitor.swift`
- Modify: `Sources/AppMain/AppDelegate.swift`
- Test: `Tests/Core/HotkeyMonitorStateTests.swift`

- [ ] **Step 1: Write the failing tests for Fn transition tracking**

```swift
import XCTest
@testable import VoiceInputCore

final class HotkeyMonitorStateTests: XCTestCase {
    func testFnTransitionProducesPressAndRelease() {
        var tracker = FnStateTracker()

        XCTAssertEqual(tracker.handle(flagsContainFn: true), .pressed)
        XCTAssertEqual(tracker.handle(flagsContainFn: true), .none)
        XCTAssertEqual(tracker.handle(flagsContainFn: false), .released)
    }
}
```

- [ ] **Step 2: Run the hotkey state tests to verify they fail because the tracker is missing**

Run: `swift test --filter HotkeyMonitorStateTests`

Expected: FAIL with `cannot find 'FnStateTracker' in scope`.

- [ ] **Step 3: Implement permissions and the event-tap-backed hotkey monitor**

```swift
// Sources/Core/PermissionsManager.swift
import AppKit
import AVFoundation
import ApplicationServices
import Speech

public struct PermissionState: Equatable {
    public var accessibilityGranted: Bool
    public var microphoneGranted: Bool
    public var speechGranted: Bool
}

public final class PermissionsManager {
    public init() {}

    public func currentState() -> PermissionState {
        PermissionState(
            accessibilityGranted: AXIsProcessTrusted(),
            microphoneGranted: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            speechGranted: SFSpeechRecognizer.authorizationStatus() == .authorized
        )
    }

    public func requestAccessibilityPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
    }

    public func requestSpeechPermission(completion: @escaping (SFSpeechRecognizerAuthorizationStatus) -> Void) {
        SFSpeechRecognizer.requestAuthorization(completion)
    }
}
```

```swift
// Sources/Core/HotkeyMonitor.swift
import ApplicationServices
import Foundation

public enum FnTransition: Equatable {
    case none
    case pressed
    case released
}

public struct FnStateTracker {
    private var isFnPressed = false

    public init() {}

    public mutating func handle(flagsContainFn: Bool) -> FnTransition {
        switch (isFnPressed, flagsContainFn) {
        case (false, true):
            isFnPressed = true
            return .pressed
        case (true, false):
            isFnPressed = false
            return .released
        default:
            return .none
        }
    }
}

public final class HotkeyMonitor {
    public var onPress: (() -> Void)?
    public var onRelease: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tracker = FnStateTracker()

    public init() {}

    public func start() {
        guard eventTap == nil else { return }
        let mask = (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo!).takeUnretainedValue()
            return monitor.handleEvent(proxy: proxy, event: event)
        }

        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: userInfo
        ) else { return }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    public func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
    }

    private func handleEvent(proxy: CGEventTapProxy, event: CGEvent) -> Unmanaged<CGEvent>? {
        let containsFn = event.flags.contains(.maskSecondaryFn)
        switch tracker.handle(flagsContainFn: containsFn) {
        case .pressed:
            onPress?()
            return nil
        case .released:
            onRelease?()
            return nil
        case .none:
            return Unmanaged.passUnretained(event)
        }
    }
}
```

```swift
// Sources/AppMain/AppDelegate.swift
import AppKit
import VoiceInputCore
import VoiceInputUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let permissionsManager = PermissionsManager()
    private let hotkeyMonitor = HotkeyMonitor()
    private var statusBarController: StatusBarController?
    private lazy var settingsWindowController = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(settingsStore: settingsStore) { [weak self] in
            self?.settingsWindowController.present()
        }
        requestPermissionsIfNeeded()
        hotkeyMonitor.start()
    }

    private func requestPermissionsIfNeeded() {
        let state = permissionsManager.currentState()
        if !state.accessibilityGranted {
            permissionsManager.requestAccessibilityPrompt()
        }
        if !state.microphoneGranted {
            permissionsManager.requestMicrophonePermission { _ in }
        }
        if !state.speechGranted {
            permissionsManager.requestSpeechPermission { _ in }
        }
    }
}
```

- [ ] **Step 4: Run the hotkey state tests and verify they pass**

Run: `swift test --filter HotkeyMonitorStateTests`

Expected: PASS with 1 executed test.

- [ ] **Step 5: Commit the permission and hotkey layer**

```bash
git add Sources/Core/PermissionsManager.swift Sources/Core/HotkeyMonitor.swift Sources/AppMain/AppDelegate.swift Tests/Core/HotkeyMonitorStateTests.swift
git commit -m "feat: add permissions and fn hotkey monitoring"
```

### Task 5: Build the audio capture, RMS metering, and streaming speech recognizer

**Files:**
- Create: `Sources/Core/AudioLevelMeter.swift`
- Create: `Sources/Core/SpeechRecognizerService.swift`
- Create: `Sources/Core/AudioCaptureEngine.swift`
- Create: `Tests/Core/AudioLevelMeterTests.swift`

- [ ] **Step 1: Write the failing tests for RMS smoothing and waveform scaling**

```swift
import XCTest
@testable import VoiceInputCore

final class AudioLevelMeterTests: XCTestCase {
    func testAttackRisesFasterThanReleaseFalls() {
        var meter = AudioLevelMeter()

        let rise = meter.smoothedLevel(nextRawLevel: 1.0)
        let drop = meter.smoothedLevel(nextRawLevel: 0.0)

        XCTAssertGreaterThan(rise, 0.35)
        XCTAssertGreaterThan(drop, 0.0)
        XCTAssertLessThan(drop, rise)
    }

    func testWaveformHeightsRespectFiveBarWeights() {
        let heights = WaveformHeightMapper.makeHeights(for: 0.8, jitterSeed: 0)
        XCTAssertEqual(heights.count, 5)
        XCTAssertGreaterThan(heights[2], heights[0])
        XCTAssertGreaterThan(heights[2], heights[4])
    }
}
```

- [ ] **Step 2: Run the meter tests to verify they fail because the audio types are missing**

Run: `swift test --filter AudioLevelMeterTests`

Expected: FAIL with `cannot find 'AudioLevelMeter' in scope`.

- [ ] **Step 3: Implement the level meter, waveform mapper, audio capture engine, and speech service**

```swift
// Sources/Core/AudioLevelMeter.swift
import AVFoundation
import Foundation

public struct AudioLevelMeter {
    private var currentLevel: CGFloat = 0
    private let attack: CGFloat = 0.4
    private let release: CGFloat = 0.15

    public init() {}

    public mutating func smoothedLevel(nextRawLevel: CGFloat) -> CGFloat {
        let coefficient = nextRawLevel > currentLevel ? attack : release
        currentLevel = currentLevel + ((nextRawLevel - currentLevel) * coefficient)
        return currentLevel
    }

    public mutating func process(buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let data = buffer.floatChannelData?[0] else { return currentLevel }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return currentLevel }

        var sum: Float = 0
        for index in 0 ..< frameCount {
            let sample = data[index]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frameCount))
        let normalized = CGFloat(min(max(rms * 6.0, 0.02), 1.0))
        return smoothedLevel(nextRawLevel: normalized)
    }
}

public enum WaveformHeightMapper {
    private static let weights: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.55]

    public static func makeHeights(for level: CGFloat, jitterSeed: UInt64) -> [CGFloat] {
        let minimum: CGFloat = 6
        let maximum: CGFloat = 30
        return weights.enumerated().map { index, weight in
            let jitter = pseudoRandom(seed: jitterSeed + UInt64(index)) * 0.08 - 0.04
            let adjusted = max(0, min(1, level * weight * (1 + jitter)))
            return minimum + ((maximum - minimum) * adjusted)
        }
    }

    private static func pseudoRandom(seed: UInt64) -> CGFloat {
        let value = (1103515245 &* seed &+ 12345) % 10_000
        return CGFloat(value) / 10_000.0
    }
}
```

```swift
// Sources/Core/AudioCaptureEngine.swift
import AVFoundation

public final class AudioCaptureEngine {
    public var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    private let engine = AVAudioEngine()

    public init() {}

    public func start() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.onBuffer?(buffer)
        }
        try engine.start()
    }

    public func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
```

```swift
// Sources/Core/SpeechRecognizerService.swift
import Foundation
import Speech

public final class SpeechRecognizerService {
    public var onPartialText: ((String) -> Void)?
    public var onFinish: ((Result<String, Error>) -> Void)?

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latestText = ""

    public init() {}

    public func start(localeIdentifier: String) throws {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true
        latestText = ""

        task = recognizer?.recognitionTask(with: request!) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.latestText = result.bestTranscription.formattedString
                self.onPartialText?(self.latestText)
                if result.isFinal {
                    self.onFinish?(.success(self.latestText))
                }
            } else if let error {
                if self.latestText.isEmpty {
                    self.onFinish?(.failure(error))
                } else {
                    self.onFinish?(.success(self.latestText))
                }
            }
        }
    }

    public func append(buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    public func stop() {
        request?.endAudio()
        task?.finish()
    }

    public func cancel() {
        task?.cancel()
    }
}
```

- [ ] **Step 4: Run the meter tests and verify they pass**

Run: `swift test --filter AudioLevelMeterTests`

Expected: PASS with 2 executed tests.

- [ ] **Step 5: Commit the audio and recognition layer**

```bash
git add Sources/Core/AudioLevelMeter.swift Sources/Core/AudioCaptureEngine.swift Sources/Core/SpeechRecognizerService.swift Tests/Core/AudioLevelMeterTests.swift
git commit -m "feat: add audio metering and speech recognition services"
```

### Task 6: Implement the floating HUD panel, waveform rendering, and settings form UI

**Files:**
- Create: `Sources/UI/FloatingPanelController.swift`
- Create: `Sources/UI/WaveformView.swift`
- Modify: `Sources/UI/SettingsViewController.swift`
- Create: `Tests/Core/HUDLayoutTests.swift`

- [ ] **Step 1: Write the failing tests for panel width clamping**

```swift
import XCTest
@testable import VoiceInputCore

final class HUDLayoutTests: XCTestCase {
    func testPanelWidthIsClampedToConfiguredBounds() {
        XCTAssertEqual(HUDLayoutMetrics.clampedWidth(forTextWidth: 20), 160)
        XCTAssertEqual(HUDLayoutMetrics.clampedWidth(forTextWidth: 900), 560)
    }
}
```

- [ ] **Step 2: Run the HUD layout tests to verify they fail because the metrics helper is missing**

Run: `swift test --filter HUDLayoutTests`

Expected: FAIL with `cannot find 'HUDLayoutMetrics' in scope`.

- [ ] **Step 3: Implement layout metrics, the floating panel, the waveform view, and the settings form**

```swift
// Sources/Core/HUDLayoutMetrics.swift
import CoreGraphics

public enum HUDLayoutMetrics {
    public static let minWidth: CGFloat = 160
    public static let maxWidth: CGFloat = 560
    public static let height: CGFloat = 56

    public static func clampedWidth(forTextWidth textWidth: CGFloat) -> CGFloat {
        let width = 44 + 16 + textWidth + 32
        return min(max(width, minWidth), maxWidth)
    }
}
```

```swift
// Sources/UI/WaveformView.swift
import AppKit
import VoiceInputCore

public final class WaveformView: NSView {
    private var bars: [CALayer] = []

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for _ in 0 ..< 5 {
            let layer = CALayer()
            layer.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
            layer.cornerRadius = 2
            self.layer?.addSublayer(layer)
            bars.append(layer)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layout() {
        super.layout()
        update(level: 0.05)
    }

    public func update(level: CGFloat, seed: UInt64 = 0) {
        let heights = WaveformHeightMapper.makeHeights(for: level, jitterSeed: seed)
        let barWidth: CGFloat = 6
        let gap: CGFloat = 3.5
        for (index, layer) in bars.enumerated() {
            let height = heights[index]
            let x = CGFloat(index) * (barWidth + gap)
            let y = (bounds.height - height) / 2
            layer.frame = CGRect(x: x, y: y, width: barWidth, height: height)
        }
    }
}
```

```swift
// Sources/UI/FloatingPanelController.swift
import AppKit
import VoiceInputCore

public final class FloatingPanelController {
    private let panel: NSPanel
    private let effectView = NSVisualEffectView()
    private let waveformView = WaveformView(frame: NSRect(x: 0, y: 0, width: 44, height: 32))
    private let label = NSTextField(labelWithString: "请讲话")
    private var currentText = "请讲话"
    private var currentLevel: CGFloat = 0.05

    public init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: HUDLayoutMetrics.height),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        effectView.material = .hudWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 28
        effectView.layer?.masksToBounds = true
        panel.contentView = effectView

        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail

        effectView.addSubview(waveformView)
        effectView.addSubview(label)
    }

    public func show(text: String) {
        currentText = text
        label.stringValue = currentText
        panel.setFrame(frameForCurrentScreen(width: measuredWidth(for: currentText)), display: true)
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
    }

    public func updateText(_ text: String) {
        currentText = text
        applyUpdate()
    }

    public func updateLevel(_ level: CGFloat) {
        currentLevel = level
        applyUpdate()
    }

    public func hide() {
        panel.orderOut(nil)
    }

    private func applyUpdate() {
        label.stringValue = currentText
        waveformView.update(level: currentLevel, seed: UInt64(Date().timeIntervalSince1970 * 1000))
        panel.animator().setFrame(frameForCurrentScreen(width: measuredWidth(for: currentText)), display: true)
    }

    private func measuredWidth(for text: String) -> CGFloat {
        let width = (text as NSString).size(withAttributes: [.font: label.font ?? NSFont.systemFont(ofSize: 15)]).width
        return HUDLayoutMetrics.clampedWidth(forTextWidth: width)
    }

    private func frameForCurrentScreen(width: CGFloat) -> NSRect {
        let screen = NSScreen.main?.visibleFrame ?? .zero
        return NSRect(
            x: screen.midX - width / 2,
            y: screen.minY + 48,
            width: width,
            height: HUDLayoutMetrics.height
        )
    }
}
```

```swift
// Sources/UI/SettingsViewController.swift
import AppKit
import VoiceInputCore

public final class SettingsViewController: NSViewController {
    private let settingsStore: SettingsStore
    private let onTest: (LLMConfiguration) async -> Result<Void, Error>

    private let baseURLField = NSTextField(string: "")
    private let apiKeyField = NSSecureTextField(string: "")
    private let modelField = NSTextField(string: "")

    public init(
        settingsStore: SettingsStore = SettingsStore(),
        onTest: @escaping (LLMConfiguration) async -> Result<Void, Error> = { _ in .success(()) }
    ) {
        self.settingsStore = settingsStore
        self.onTest = onTest
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 220))
        baseURLField.stringValue = settingsStore.llmConfiguration.baseURL
        apiKeyField.stringValue = settingsStore.llmConfiguration.apiKey
        modelField.stringValue = settingsStore.llmConfiguration.model
    }
}
```

- [ ] **Step 4: Run the HUD layout tests and verify they pass**

Run: `swift test --filter HUDLayoutTests`

Expected: PASS with 1 executed test.

- [ ] **Step 5: Commit the HUD and settings UI**

```bash
git add Sources/Core/HUDLayoutMetrics.swift Sources/UI/WaveformView.swift Sources/UI/FloatingPanelController.swift Sources/UI/SettingsViewController.swift Tests/Core/HUDLayoutTests.swift
git commit -m "feat: add floating hud and settings form"
```

### Task 7: Add clipboard-based text injection and input source switching

**Files:**
- Create: `Sources/Core/InputSourceManager.swift`
- Create: `Sources/Core/ClipboardSnapshot.swift`
- Create: `Sources/Core/TextInjector.swift`
- Create: `Tests/Core/InputSourceClassificationTests.swift`

- [ ] **Step 1: Write the failing tests for CJK input source classification**

```swift
import XCTest
@testable import VoiceInputCore

final class InputSourceClassificationTests: XCTestCase {
    func testRecognizesChineseInputMethodsAsCjk() {
        let source = InputSourceDescriptor(identifier: "com.apple.inputmethod.SCIM.ITABC", languages: ["zh-Hans"])
        XCTAssertTrue(source.isCJK)
    }

    func testRecognizesAsciiLayoutsAsNonCjk() {
        let source = InputSourceDescriptor(identifier: "com.apple.keylayout.ABC", languages: ["en"])
        XCTAssertFalse(source.isCJK)
    }
}
```

- [ ] **Step 2: Run the input source tests to verify they fail because the descriptors do not exist**

Run: `swift test --filter InputSourceClassificationTests`

Expected: FAIL with `cannot find 'InputSourceDescriptor' in scope`.

- [ ] **Step 3: Implement input source descriptors, clipboard snapshots, and text injection**

```swift
// Sources/Core/InputSourceManager.swift
import Carbon
import Foundation

public struct InputSourceDescriptor: Equatable {
    public var identifier: String
    public var languages: [String]

    public var isCJK: Bool {
        let cjkPrefixes = ["zh", "ja", "ko"]
        return languages.contains { language in
            cjkPrefixes.contains { language.lowercased().hasPrefix($0) }
        } || identifier.localizedCaseInsensitiveContains("inputmethod")
    }
}

public final class InputSourceManager {
    public init() {}

    public func currentDescriptor() -> InputSourceDescriptor? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        let identifier = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) as? String ?? ""
        let languages = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) as? [String] ?? []
        return InputSourceDescriptor(identifier: identifier, languages: languages)
    }

    public func switchToASCII() {
        let sourceList = TISCreateInputSourceList([kTISPropertyInputSourceID: "com.apple.keylayout.ABC"] as CFDictionary, false).takeRetainedValue() as NSArray
        if let source = sourceList.firstObject {
            TISSelectInputSource(source as! TISInputSource)
            return
        }

        let fallback = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()
        if let fallback {
            TISSelectInputSource(fallback)
        }
    }
}
```

```swift
// Sources/Core/ClipboardSnapshot.swift
import AppKit

public struct ClipboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    public init(pasteboard: NSPasteboard = .general) {
        items = pasteboard.pasteboardItems?.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        } ?? []
    }

    public func restore(to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        for itemPayload in items {
            let item = NSPasteboardItem()
            for (type, data) in itemPayload {
                item.setData(data, forType: type)
            }
            pasteboard.writeObjects([item])
        }
    }
}
```

```swift
// Sources/Core/TextInjector.swift
import AppKit
import Carbon

public final class TextInjector {
    private let inputSourceManager: InputSourceManager

    public init(inputSourceManager: InputSourceManager = InputSourceManager()) {
        self.inputSourceManager = inputSourceManager
    }

    public func inject(_ text: String) {
        let pasteboard = NSPasteboard.general
        let snapshot = ClipboardSnapshot(pasteboard: pasteboard)
        let original = inputSourceManager.currentDescriptor()

        if original?.isCJK == true {
            inputSourceManager.switchToASCII()
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            snapshot.restore(to: pasteboard)
        }
    }
}
```

- [ ] **Step 4: Run the input source tests and verify they pass**

Run: `swift test --filter InputSourceClassificationTests`

Expected: PASS with 2 executed tests.

- [ ] **Step 5: Commit the injection layer**

```bash
git add Sources/Core/InputSourceManager.swift Sources/Core/ClipboardSnapshot.swift Sources/Core/TextInjector.swift Tests/Core/InputSourceClassificationTests.swift
git commit -m "feat: add input source switching and paste injection"
```

### Task 8: Implement the OpenAI-compatible LLM refiner and Settings test action

**Files:**
- Create: `Sources/Core/LLMRefiner.swift`
- Create: `Tests/Core/LLMRefinerTests.swift`
- Modify: `Sources/UI/SettingsViewController.swift`

- [ ] **Step 1: Write the failing tests for request payload generation and conservative prompt wording**

```swift
import XCTest
@testable import VoiceInputCore

final class LLMRefinerTests: XCTestCase {
    func testSystemPromptContainsConservativeCorrectionRules() throws {
        let payload = try LLMRefiner.makePayload(
            config: LLMConfiguration(baseURL: "https://example.com", apiKey: "secret", model: "gpt"),
            transcript: "配森 杰森"
        )

        XCTAssertTrue(payload.systemPrompt.contains("Correct only obvious speech recognition mistakes"))
        XCTAssertTrue(payload.systemPrompt.contains("Return only the final corrected text"))
    }

    func testUserMessageContainsOriginalTranscriptVerbatim() throws {
        let payload = try LLMRefiner.makePayload(
            config: LLMConfiguration(baseURL: "https://example.com", apiKey: "secret", model: "gpt"),
            transcript: "hello 配森 world"
        )

        XCTAssertEqual(payload.userText, "hello 配森 world")
    }
}
```

- [ ] **Step 2: Run the refiner tests to verify they fail because the refiner does not exist**

Run: `swift test --filter LLMRefinerTests`

Expected: FAIL with `cannot find 'LLMRefiner' in scope`.

- [ ] **Step 3: Implement the refiner and wire the settings test button**

```swift
// Sources/Core/LLMRefiner.swift
import Foundation

public struct LLMRefinerPayload: Equatable {
    public var systemPrompt: String
    public var userText: String
}

public final class LLMRefiner {
    public init() {}

    public static func makePayload(config: LLMConfiguration, transcript: String) throws -> LLMRefinerPayload {
        guard config.isComplete else {
            throw URLError(.userAuthenticationRequired)
        }

        return LLMRefinerPayload(
            systemPrompt: """
            Correct only obvious speech recognition mistakes.
            Preserve all text that already looks correct.
            Never rewrite, summarize, embellish, or delete correct content.
            Preserve technical terms, code terms, and mixed-language content when they are already correct.
            Fix obvious misrecognitions such as 配森 -> Python and 杰森 -> JSON when clearly warranted.
            Return only the final corrected text.
            """,
            userText: transcript
        )
    }

    public func refine(transcript: String, config: LLMConfiguration) async throws -> String {
        let payload = try Self.makePayload(config: config, transcript: transcript)
        var request = URLRequest(url: URL(string: config.baseURL)!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": config.model,
            "messages": [
                ["role": "system", "content": payload.systemPrompt],
                ["role": "user", "content": payload.userText]
            ]
        ])

        let (data, _) = try await URLSession.shared.data(for: request)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = object?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let content = (message?["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return content?.isEmpty == false ? content! : transcript
    }

    public func testConnection(config: LLMConfiguration) async -> Result<Void, Error> {
        do {
            _ = try await refine(transcript: "test", config: config)
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}
```

```swift
// Sources/UI/SettingsViewController.swift
import AppKit
import VoiceInputCore

public final class SettingsViewController: NSViewController {
    private let settingsStore: SettingsStore
    private let onTest: (LLMConfiguration) async -> Result<Void, Error>

    private let baseURLField = NSTextField(string: "")
    private let apiKeyField = NSSecureTextField(string: "")
    private let modelField = NSTextField(string: "")
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)
    private let testButton = NSButton(title: "Test", target: nil, action: nil)

    public init(
        settingsStore: SettingsStore = SettingsStore(),
        onTest: @escaping (LLMConfiguration) async -> Result<Void, Error> = { _ in .success(()) }
    ) {
        self.settingsStore = settingsStore
        self.onTest = onTest
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 220))
        baseURLField.stringValue = settingsStore.llmConfiguration.baseURL
        apiKeyField.stringValue = settingsStore.llmConfiguration.apiKey
        modelField.stringValue = settingsStore.llmConfiguration.model
        saveButton.target = self
        saveButton.action = #selector(saveAction)
        testButton.target = self
        testButton.action = #selector(testAction)
    }

    @objc private func saveAction() {
        settingsStore.llmConfiguration = currentConfiguration()
    }

    @objc private func testAction() {
        let config = currentConfiguration()
        Task {
            _ = await onTest(config)
        }
    }

    private func currentConfiguration() -> LLMConfiguration {
        LLMConfiguration(baseURL: baseURLField.stringValue, apiKey: apiKeyField.stringValue, model: modelField.stringValue)
    }
}
```

- [ ] **Step 4: Run the refiner tests and verify they pass**

Run: `swift test --filter LLMRefinerTests`

Expected: PASS with 2 executed tests.

- [ ] **Step 5: Commit the refiner**

```bash
git add Sources/Core/LLMRefiner.swift Sources/UI/SettingsViewController.swift Tests/Core/LLMRefinerTests.swift
git commit -m "feat: add conservative llm transcript refiner"
```

### Task 9: Wire the full session coordinator across hotkey, speech, HUD, refine, and injection

**Files:**
- Create: `Sources/Core/SpeechSessionController.swift`
- Modify: `Sources/AppMain/AppDelegate.swift`
- Test: `Tests/Core/SpeechSessionControllerTests.swift`

- [ ] **Step 1: Write the failing tests for state transitions**

```swift
import XCTest
@testable import VoiceInputCore

final class SpeechSessionControllerTests: XCTestCase {
    func testEnabledRefinementRoutesRecordingStopIntoRefiningState() {
        let state = SpeechSessionState.nextState(
            current: .recording,
            event: .recordingStopped(hasTranscript: true, shouldRefine: true)
        )

        XCTAssertEqual(state, .refining)
    }

    func testEmptyTranscriptReturnsToIdleWithoutInjection() {
        let state = SpeechSessionState.nextState(
            current: .recording,
            event: .recordingStopped(hasTranscript: false, shouldRefine: false)
        )

        XCTAssertEqual(state, .idle)
    }
}
```

- [ ] **Step 2: Run the session tests to verify they fail because the coordinator types are missing**

Run: `swift test --filter SpeechSessionControllerTests`

Expected: FAIL with `cannot find 'SpeechSessionState' in scope`.

- [ ] **Step 3: Implement the coordinator and connect the app delegate**

```swift
// Sources/Core/SpeechSessionController.swift
import Foundation

public enum SpeechSessionState: Equatable {
    case idle
    case recording
    case refining
    case injecting

    public enum Event {
        case fnPressed
        case recordingStopped(hasTranscript: Bool, shouldRefine: Bool)
        case refinementFinished
        case injectionFinished
        case failed
    }

    public static func nextState(current: SpeechSessionState, event: Event) -> SpeechSessionState {
        switch (current, event) {
        case (.idle, .fnPressed):
            return .recording
        case (.recording, .recordingStopped(let hasTranscript, let shouldRefine)):
            guard hasTranscript else { return .idle }
            return shouldRefine ? .refining : .injecting
        case (.refining, .refinementFinished):
            return .injecting
        case (.injecting, .injectionFinished):
            return .idle
        case (_, .failed):
            return .idle
        default:
            return current
        }
    }
}
```

```swift
// Sources/Core/SpeechSessionController.swift
import Foundation

public final class SpeechSessionController {
    private(set) var state: SpeechSessionState = .idle

    private let settingsStore: SettingsStore
    private let audioCaptureEngine: AudioCaptureEngine
    private let speechRecognizerService: SpeechRecognizerService
    private let textInjector: TextInjector
    private let llmRefiner: LLMRefiner

    public var onTranscriptUpdate: ((String) -> Void)?
    public var onLevelUpdate: ((CGFloat) -> Void)?
    public var onHUDVisibilityChange: ((Bool) -> Void)?

    private var transcript = ""
    private var levelMeter = AudioLevelMeter()

    public init(
        settingsStore: SettingsStore,
        audioCaptureEngine: AudioCaptureEngine = AudioCaptureEngine(),
        speechRecognizerService: SpeechRecognizerService = SpeechRecognizerService(),
        textInjector: TextInjector = TextInjector(),
        llmRefiner: LLMRefiner = LLMRefiner()
    ) {
        self.settingsStore = settingsStore
        self.audioCaptureEngine = audioCaptureEngine
        self.speechRecognizerService = speechRecognizerService
        self.textInjector = textInjector
        self.llmRefiner = llmRefiner
    }

    public func handleFnPressed() {
        guard state == .idle else { return }
        state = SpeechSessionState.nextState(current: state, event: .fnPressed)
        transcript = ""
        onHUDVisibilityChange?(true)
        onTranscriptUpdate?("请讲话")

        speechRecognizerService.onPartialText = { [weak self] text in
            self?.transcript = text
            self?.onTranscriptUpdate?(text)
        }

        audioCaptureEngine.onBuffer = { [weak self] buffer in
            guard let self else { return }
            self.speechRecognizerService.append(buffer: buffer)
            let level = self.levelMeter.process(buffer: buffer)
            self.onLevelUpdate?(level)
        }

        try? speechRecognizerService.start(localeIdentifier: settingsStore.selectedLocale.rawValue)
        try? audioCaptureEngine.start()
    }

    public func handleFnReleased() {
        guard state == .recording else { return }
        audioCaptureEngine.stop()
        speechRecognizerService.stop()

        let shouldRefine = settingsStore.isLLMRefinementEnabled && settingsStore.llmConfiguration.isComplete
        state = SpeechSessionState.nextState(
            current: state,
            event: .recordingStopped(hasTranscript: !transcript.isEmpty, shouldRefine: shouldRefine)
        )

        guard !transcript.isEmpty else {
            onTranscriptUpdate?("未识别到内容")
            onHUDVisibilityChange?(false)
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            var finalText = self.transcript

            if self.state == .refining {
                self.onTranscriptUpdate?("Refining...")
                finalText = (try? await self.llmRefiner.refine(
                    transcript: self.transcript,
                    config: self.settingsStore.llmConfiguration
                )) ?? self.transcript
                self.state = SpeechSessionState.nextState(current: self.state, event: .refinementFinished)
            }

            self.textInjector.inject(finalText)
            self.state = SpeechSessionState.nextState(current: self.state, event: .injectionFinished)
            self.onHUDVisibilityChange?(false)
        }
    }
}
```

```swift
// Sources/AppMain/AppDelegate.swift
import AppKit
import VoiceInputCore
import VoiceInputUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let permissionsManager = PermissionsManager()
    private let hotkeyMonitor = HotkeyMonitor()
    private let panelController = FloatingPanelController()
    private lazy var sessionController = SpeechSessionController(settingsStore: settingsStore)
    private var statusBarController: StatusBarController?
    private lazy var settingsWindowController = SettingsWindowController(
        rootViewController: SettingsViewController(
            settingsStore: settingsStore,
            onTest: { config in await LLMRefiner().testConnection(config: config) }
        )
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(settingsStore: settingsStore) { [weak self] in
            self?.settingsWindowController.present()
        }
        requestPermissionsIfNeeded()
        bindSession()
        hotkeyMonitor.onPress = { [weak self] in self?.sessionController.handleFnPressed() }
        hotkeyMonitor.onRelease = { [weak self] in self?.sessionController.handleFnReleased() }
        hotkeyMonitor.start()
    }

    private func bindSession() {
        sessionController.onHUDVisibilityChange = { [weak self] visible in
            visible ? self?.panelController.show(text: "请讲话") : self?.panelController.hide()
        }
        sessionController.onTranscriptUpdate = { [weak self] text in
            self?.panelController.updateText(text)
        }
        sessionController.onLevelUpdate = { [weak self] level in
            self?.panelController.updateLevel(level)
        }
    }

    private func requestPermissionsIfNeeded() {
        let state = permissionsManager.currentState()
        if !state.accessibilityGranted {
            permissionsManager.requestAccessibilityPrompt()
        }
        if !state.microphoneGranted {
            permissionsManager.requestMicrophonePermission { _ in }
        }
        if !state.speechGranted {
            permissionsManager.requestSpeechPermission { _ in }
        }
    }
}
```

- [ ] **Step 4: Run the session tests and verify they pass**

Run: `swift test --filter SpeechSessionControllerTests`

Expected: PASS with 2 executed tests.

- [ ] **Step 5: Commit the integrated session flow**

```bash
git add Sources/Core/SpeechSessionController.swift Sources/AppMain/AppDelegate.swift Tests/Core/SpeechSessionControllerTests.swift
git commit -m "feat: wire speech session orchestration"
```

### Task 10: Polish animation timing, restore input source after paste, and verify the app bundle manually

**Files:**
- Modify: `Sources/UI/FloatingPanelController.swift`
- Modify: `Sources/Core/InputSourceManager.swift`
- Modify: `Sources/Core/TextInjector.swift`
- Create: `docs/manual-test-checklist.md`

- [ ] **Step 1: Write the failing test for width animation timing metadata**

```swift
import XCTest
@testable import VoiceInputCore

final class HUDAnimationConstantsTests: XCTestCase {
    func testHudAnimationDurationsMatchSpec() {
        XCTAssertEqual(HUDAnimationDurations.enter, 0.35, accuracy: 0.001)
        XCTAssertEqual(HUDAnimationDurations.resize, 0.25, accuracy: 0.001)
        XCTAssertEqual(HUDAnimationDurations.exit, 0.22, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run the animation-constant test to verify it fails because the constants are missing**

Run: `swift test --filter HUDAnimationConstantsTests`

Expected: FAIL with `cannot find 'HUDAnimationDurations' in scope`.

- [ ] **Step 3: Add the animation constants, restore the original input source, and document manual verification**

```swift
// Sources/Core/HUDAnimationDurations.swift
public enum HUDAnimationDurations {
    public static let enter = 0.35
    public static let resize = 0.25
    public static let exit = 0.22
}
```

```swift
// Sources/Core/InputSourceManager.swift
import Carbon
import Foundation

public final class InputSourceManager {
    public init() {}

    public func currentInputSource() -> TISInputSource? {
        TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
    }

    public func currentDescriptor() -> InputSourceDescriptor? {
        guard let source = currentInputSource() else { return nil }
        let identifier = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) as? String ?? ""
        let languages = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) as? [String] ?? []
        return InputSourceDescriptor(identifier: identifier, languages: languages)
    }

    public func switchToASCII() {
        let sourceList = TISCreateInputSourceList([kTISPropertyInputSourceID: "com.apple.keylayout.ABC"] as CFDictionary, false).takeRetainedValue() as NSArray
        if let source = sourceList.firstObject as? TISInputSource {
            TISSelectInputSource(source)
            return
        }

        if let fallback = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue() {
            TISSelectInputSource(fallback)
        }
    }

    public func restore(_ source: TISInputSource?) {
        guard let source else { return }
        TISSelectInputSource(source)
    }
}
```

```swift
// Sources/Core/TextInjector.swift
import AppKit

public final class TextInjector {
    private let inputSourceManager: InputSourceManager

    public init(inputSourceManager: InputSourceManager = InputSourceManager()) {
        self.inputSourceManager = inputSourceManager
    }

    public func inject(_ text: String) {
        let pasteboard = NSPasteboard.general
        let snapshot = ClipboardSnapshot(pasteboard: pasteboard)
        let originalSource = inputSourceManager.currentInputSource()
        let descriptor = inputSourceManager.currentDescriptor()

        if descriptor?.isCJK == true {
            inputSourceManager.switchToASCII()
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.inputSourceManager.restore(originalSource)
            snapshot.restore(to: pasteboard)
        }
    }
}
```

```swift
// Sources/UI/FloatingPanelController.swift
import AppKit
import VoiceInputCore

public final class FloatingPanelController {
    public func show(text: String) {
        currentText = text
        label.stringValue = currentText
        panel.alphaValue = 0
        panel.contentView?.layer?.transform = CATransform3DMakeScale(0.92, 0.92, 1)
        panel.setFrame(frameForCurrentScreen(width: measuredWidth(for: currentText)), display: true)
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = HUDAnimationDurations.enter
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.contentView?.animator().layer?.transform = CATransform3DIdentity
        }
    }

    public func updateText(_ text: String) {
        currentText = text
        label.stringValue = currentText
        NSAnimationContext.runAnimationGroup { context in
            context.duration = HUDAnimationDurations.resize
            panel.animator().setFrame(frameForCurrentScreen(width: measuredWidth(for: currentText)), display: true)
        }
    }

    public func hide() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = HUDAnimationDurations.exit
            panel.animator().alphaValue = 0
            panel.contentView?.animator().layer?.transform = CATransform3DMakeScale(0.96, 0.96, 1)
        }, completionHandler: {
            self.panel.orderOut(nil)
        })
    }
}
```

```markdown
<!-- docs/manual-test-checklist.md -->
# Manual Test Checklist

- Grant Accessibility, Microphone, and Speech Recognition permissions on first launch.
- Hold `Fn` in a text editor and confirm the emoji picker does not appear.
- Speak softly and loudly to verify the five waveform bars visibly follow RMS changes.
- Confirm the HUD appears centered near the bottom of the screen and resizes with transcript length.
- Switch the app language to `简体中文`, `English`, `繁体中文`, `日本語`, and `한국어`, then verify recognition uses the selected locale.
- Enable LLM refinement with a valid API config and verify the HUD shows `Refining...` before paste.
- Enter a phrase containing obvious mixed-language ASR errors such as `配森 杰森`, then verify the final pasted text becomes `Python JSON`.
- With a CJK input method active, verify the app pastes text correctly and restores the original input source afterward.
- Verify the original clipboard content is restored after injection.
- Run `make build`, `make run`, and `make install`, then launch the installed app from `/Applications`.
```

- [ ] **Step 4: Run the animation-constant test and the full test suite**

Run: `swift test`

Expected: PASS across all unit tests including `HUDAnimationConstantsTests`.

- [ ] **Step 5: Build the app bundle and complete manual verification**

Run: `make build`

Expected: `dist/VoiceInput.app` exists and is ad-hoc signed without `codesign` errors.

- [ ] **Step 6: Commit the polish and verification assets**

```bash
git add Sources/Core/HUDAnimationDurations.swift Sources/Core/InputSourceManager.swift Sources/Core/TextInjector.swift Sources/UI/FloatingPanelController.swift docs/manual-test-checklist.md
git commit -m "feat: polish hud timing and injection restoration"
```
