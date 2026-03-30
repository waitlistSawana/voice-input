import AVFoundation
import ApplicationServices
import Speech

public enum AccessibilityPermissionStatus: Equatable, Sendable {
    case granted
    case denied
}

public enum AuthorizationPermissionStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case authorized
}

public enum AppPermission: Equatable, Sendable {
    case accessibility
    case microphone
    case speechRecognition
}

public struct PermissionState: Equatable, Sendable {
    public let accessibility: AccessibilityPermissionStatus
    public let microphone: AuthorizationPermissionStatus
    public let speechRecognition: AuthorizationPermissionStatus

    public init(
        accessibility: AccessibilityPermissionStatus,
        microphone: AuthorizationPermissionStatus,
        speechRecognition: AuthorizationPermissionStatus
    ) {
        self.accessibility = accessibility
        self.microphone = microphone
        self.speechRecognition = speechRecognition
    }

    public var hotkeyMonitoringAvailable: Bool {
        accessibility == .granted
    }

    public var canRecordAudio: Bool {
        microphone == .authorized && speechRecognition == .authorized
    }

    public var missingPermissions: [AppPermission] {
        var permissions: [AppPermission] = []

        if accessibility != .granted {
            permissions.append(.accessibility)
        }

        if microphone != .authorized {
            permissions.append(.microphone)
        }

        if speechRecognition != .authorized {
            permissions.append(.speechRecognition)
        }

        return permissions
    }
}

public final class PermissionsManager {
    public init() {}

    public func currentState() -> PermissionState {
        PermissionState(
            accessibility: AXIsProcessTrusted() ? .granted : .denied,
            microphone: AuthorizationPermissionStatus(AVCaptureDevice.authorizationStatus(for: .audio)),
            speechRecognition: AuthorizationPermissionStatus(SFSpeechRecognizer.authorizationStatus())
        )
    }

    public func requestAccessibilityPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public func requestMicrophonePermission(completion: @escaping @Sendable (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
    }

    public func requestSpeechPermission(
        completion: @escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void
    ) {
        SFSpeechRecognizer.requestAuthorization(completion)
    }
}

extension AuthorizationPermissionStatus {
    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .restricted:
            self = .restricted
        case .denied:
            self = .denied
        case .authorized:
            self = .authorized
        @unknown default:
            self = .denied
        }
    }

    init(_ status: SFSpeechRecognizerAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        case .authorized:
            self = .authorized
        @unknown default:
            self = .denied
        }
    }
}
