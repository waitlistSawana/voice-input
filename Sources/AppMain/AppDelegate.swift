import AppKit
import VoiceInputCore
import VoiceInputUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let permissionsManager = PermissionsManager()
    private let hotkeyMonitor = HotkeyMonitor()
    private let panelController = FloatingPanelController()
    private var statusBarController: StatusBarController?
    private var hotkeyRetryTimer: Timer?
    private lazy var sessionController = SpeechSessionController(settingsStore: settingsStore)
    private lazy var settingsWindowController = SettingsWindowController(
        dependencies: SettingsViewController.Dependencies(settingsStore: settingsStore)
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(settingsStore: settingsStore) { [weak self] in
            self?.settingsWindowController.present()
        }
        bindSession()
        requestPermissionsIfNeeded()
        startHotkeyMonitorIfPossible()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        startHotkeyMonitorIfPossible()
    }

    func applicationWillTerminate(_ notification: Notification) {
        invalidateHotkeyRetryTimer()
        hotkeyMonitor.stop()
    }

    private func requestPermissionsIfNeeded() {
        let state = permissionsManager.currentState()

        if state.accessibility != .granted {
            permissionsManager.requestAccessibilityPrompt()
            scheduleHotkeyRetryIfNeeded()
        }

        if state.microphone == .notDetermined {
            permissionsManager.requestMicrophonePermission { _ in }
        }

        if state.speechRecognition == .notDetermined {
            permissionsManager.requestSpeechPermission { _ in }
        }
    }

    private func bindSession() {
        hotkeyMonitor.onPress = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                let permissionState = self.permissionsManager.currentState()
                guard permissionState.canRecordAudio else {
                    self.requestPermissionsIfNeeded()
                    return
                }

                self.sessionController.handleFnPressed()
            }
        }

        hotkeyMonitor.onRelease = { [weak self] in
            Task { @MainActor [weak self] in
                self?.sessionController.handleFnReleased()
            }
        }

        sessionController.onHUDVisibilityChange = { [weak self] isVisible in
            guard let self else {
                return
            }

            if isVisible {
                self.panelController.show()
            } else {
                self.panelController.hide()
            }
        }

        sessionController.onStatusTextChange = { [weak self] text in
            self?.panelController.updateStatus(text)
        }

        sessionController.onTranscriptChange = { [weak self] text in
            self?.panelController.updateTranscript(text)
        }

        sessionController.onLevelChange = { [weak self] level in
            self?.panelController.updateLevel(level)
        }
    }

    private func startHotkeyMonitorIfPossible() {
        if hotkeyMonitor.isRunning {
            invalidateHotkeyRetryTimer()
            return
        }

        let permissionState = permissionsManager.currentState()
        guard permissionState.hotkeyMonitoringAvailable else {
            scheduleHotkeyRetryIfNeeded()
            return
        }

        if hotkeyMonitor.start() {
            invalidateHotkeyRetryTimer()
        } else {
            scheduleHotkeyRetryIfNeeded()
        }
    }

    private func scheduleHotkeyRetryIfNeeded() {
        guard hotkeyRetryTimer == nil else {
            return
        }

        hotkeyRetryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.startHotkeyMonitorIfPossible()
            }
        }
    }

    private func invalidateHotkeyRetryTimer() {
        hotkeyRetryTimer?.invalidate()
        hotkeyRetryTimer = nil
    }
}
