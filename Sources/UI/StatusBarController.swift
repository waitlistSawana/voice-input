import AppKit
import VoiceInputCore

public struct StatusBarMenuSnapshot: Equatable, Sendable {
    public let topLevelTitles: [String]
    public let languageTitles: [String]
    public let llmToggleTitle: String
    public let llmSettingsTitle: String
    public let quitTitle: String
    public let isLLMToggleEnabled: Bool
    public let isLLMToggleOn: Bool

    public init(
        topLevelTitles: [String],
        languageTitles: [String],
        llmToggleTitle: String,
        llmSettingsTitle: String,
        quitTitle: String,
        isLLMToggleEnabled: Bool,
        isLLMToggleOn: Bool
    ) {
        self.topLevelTitles = topLevelTitles
        self.languageTitles = languageTitles
        self.llmToggleTitle = llmToggleTitle
        self.llmSettingsTitle = llmSettingsTitle
        self.quitTitle = quitTitle
        self.isLLMToggleEnabled = isLLMToggleEnabled
        self.isLLMToggleOn = isLLMToggleOn
    }
}

public final class StatusBarController: NSObject {
    public typealias MenuRebuiltHandler = @Sendable () -> Void

    private let statusItem: NSStatusItem
    private let settingsStore: SettingsStore
    private let notificationCenter: NotificationCenter
    private let onMenuRebuilt: MenuRebuiltHandler?
    private let openSettings: () -> Void
    private var settingsObserver: NSObjectProtocol?

    var menu: NSMenu? {
        statusItem.menu
    }

    public init(
        statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength),
        settingsStore: SettingsStore,
        notificationCenter: NotificationCenter = .default,
        onMenuRebuilt: MenuRebuiltHandler? = nil,
        openSettings: @escaping () -> Void
    ) {
        self.statusItem = statusItem
        self.settingsStore = settingsStore
        self.notificationCenter = notificationCenter
        self.onMenuRebuilt = onMenuRebuilt
        self.openSettings = openSettings
        super.init()
        observeSettingsChanges()
        configureStatusItem()
        rebuildMenu()
    }

    deinit {
        if let settingsObserver {
            notificationCenter.removeObserver(settingsObserver)
        }
    }

    public static func menuSnapshot(settingsStore: SettingsStore) -> StatusBarMenuSnapshot {
        let isAvailable = settingsStore.llmConfiguration.isComplete
        return StatusBarMenuSnapshot(
            topLevelTitles: ["Language", "LLM Refinement", "Quit"],
            languageTitles: AppLocale.allCases.map(\.menuTitle),
            llmToggleTitle: "Enable Refinement",
            llmSettingsTitle: "Settings...",
            quitTitle: "Quit",
            isLLMToggleEnabled: isAvailable,
            isLLMToggleOn: isAvailable && settingsStore.isLLMRefinementEnabled
        )
    }

    public func rebuildMenu() {
        if Thread.isMainThread {
            rebuildMenuOnMainThread()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.rebuildMenuOnMainThread()
            }
        }
    }

    private func rebuildMenuOnMainThread() {
        let snapshot = Self.menuSnapshot(settingsStore: settingsStore)
        let menu = NSMenu()

        let languageMenu = NSMenu()
        for locale in AppLocale.allCases {
            let item = NSMenuItem(title: locale.menuTitle, action: #selector(selectLocale(_:)), keyEquivalent: "")
            item.target = self
            item.state = settingsStore.selectedLocale == locale ? .on : .off
            item.representedObject = locale.rawValue
            languageMenu.addItem(item)
        }

        let languageItem = NSMenuItem(title: snapshot.topLevelTitles[0], action: nil, keyEquivalent: "")
        menu.setSubmenu(languageMenu, for: languageItem)
        menu.addItem(languageItem)

        let llmMenu = NSMenu()
        let toggleItem = NSMenuItem(title: snapshot.llmToggleTitle, action: #selector(toggleRefinement(_:)), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.isEnabled = snapshot.isLLMToggleEnabled
        toggleItem.state = snapshot.isLLMToggleOn ? .on : .off
        llmMenu.addItem(toggleItem)

        let settingsItem = NSMenuItem(title: snapshot.llmSettingsTitle, action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        llmMenu.addItem(settingsItem)

        let llmItem = NSMenuItem(title: snapshot.topLevelTitles[1], action: nil, keyEquivalent: "")
        menu.setSubmenu(llmMenu, for: llmItem)
        menu.addItem(llmItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: snapshot.quitTitle, action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        onMenuRebuilt?()
    }

    private func observeSettingsChanges() {
        settingsObserver = notificationCenter.addObserver(
            forName: SettingsStore.didChangeNotification,
            object: settingsStore,
            queue: nil
        ) { [weak self] _ in
            self?.rebuildMenu()
        }
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Voice Input")
            button.imagePosition = .imageLeading
        }
    }

    @objc private func selectLocale(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String, let locale = AppLocale(rawValue: rawValue) else {
            return
        }

        settingsStore.selectedLocale = locale
    }

    @objc private func toggleRefinement(_ sender: NSMenuItem) {
        guard settingsStore.llmConfiguration.isComplete else {
            return
        }

        settingsStore.isLLMRefinementEnabled.toggle()
    }

    @objc private func openSettingsAction() {
        openSettings()
    }

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }
}
