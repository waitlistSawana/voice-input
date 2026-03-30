import AppKit
import Carbon.HIToolbox
import ApplicationServices
import CoreGraphics
import Foundation

struct ClipboardBackend {
    let snapshot: () -> ClipboardSnapshot
    let restore: (ClipboardSnapshot) -> Void
    let writeText: (String) -> Void
}

struct InputSourceBackend {
    let current: () -> InputSourceMetadata?
    let switchToASCII: () -> Bool
    let restoreOriginal: () -> Bool
}

public final class TextInjector {
    private let clipboard: ClipboardBackend
    private let inputSourceManager: InputSourceBackend
    private let eventPoster: () -> Void
    private let sleeper: (TimeInterval) -> Void
    private let stabilizationDelay: TimeInterval

    init(
        clipboard: ClipboardBackend? = nil,
        inputSourceManager: InputSourceBackend? = nil,
        eventPoster: (() -> Void)? = nil,
        sleeper: ((TimeInterval) -> Void)? = nil,
        stabilizationDelay: TimeInterval = 0.05
    ) {
        self.clipboard = clipboard ?? Self.makeSystemClipboardBackend()
        self.inputSourceManager = inputSourceManager ?? Self.makeSystemInputSourceBackend()
        self.eventPoster = eventPoster ?? Self.makeSystemEventPoster()
        self.sleeper = sleeper ?? Self.makeSystemSleeper()
        self.stabilizationDelay = stabilizationDelay
    }

    public func inject(_ text: String) {
        let snapshot = clipboard.snapshot()
        defer {
            clipboard.restore(snapshot)
        }

        let currentSource = inputSourceManager.current()
        if currentSource?.isCJK == true {
            _ = inputSourceManager.switchToASCII()
        }

        clipboard.writeText(text)
        eventPoster()
        sleeper(stabilizationDelay)

        _ = inputSourceManager.restoreOriginal()
    }

    private static func makeSystemClipboardBackend() -> ClipboardBackend {
        let pasteboard = NSPasteboard.general
        return ClipboardBackend(
            snapshot: {
                ClipboardSnapshot(pasteboard: pasteboard)
            },
            restore: { snapshot in
                snapshot.restore(to: pasteboard)
            },
            writeText: { text in
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            }
        )
    }

    private static func makeSystemInputSourceBackend() -> InputSourceBackend {
        let manager = InputSourceManager()
        final class OriginalSourceBox {
            var source: TISInputSource?
        }

        let originalSource = OriginalSourceBox()

        return InputSourceBackend(
            current: {
                manager.currentInputSourceMetadata()
            },
            switchToASCII: {
                guard let preferred = manager.preferredASCIIInputSourceMetadata() else {
                    return false
                }

                guard let source = Self.findTISInputSource(matching: preferred.sourceID) else {
                    return false
                }

                guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
                    return false
                }

                originalSource.source = current
                TISSelectInputSource(source)

                guard let selected = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
                    originalSource.source = nil
                    return false
                }

                let switched = Self.inputSource(selected, matches: preferred.sourceID)
                if !switched {
                    originalSource.source = nil
                }

                return switched
            },
            restoreOriginal: {
                guard let source = originalSource.source else {
                    return false
                }

                TISSelectInputSource(source)
                originalSource.source = nil

                guard let selected = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
                    return false
                }

                return Self.inputSource(selected, matches: Self.sourceIdentifier(for: source))
            }
        )
    }

    private static func makeSystemEventPoster() -> () -> Void {
        return {
            guard let source = CGEventSource(stateID: .combinedSessionState) else {
                return
            }

            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
            keyDown?.flags = .maskCommand
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
            keyUp?.flags = .maskCommand

            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }

    private static func makeSystemSleeper() -> (TimeInterval) -> Void {
        return { delay in
            Thread.sleep(forTimeInterval: delay)
        }
    }

    private static func findTISInputSource(matching sourceID: String?) -> TISInputSource? {
        guard
            let sourceID,
            let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue()
        else {
            return nil
        }

        let count = CFArrayGetCount(sources)
        return (0 ..< count).lazy.compactMap { index -> TISInputSource? in
            let rawSource = CFArrayGetValueAtIndex(sources, index)
            return unsafeBitCast(rawSource, to: TISInputSource.self)
        }.first { inputSource in
            Self.inputSource(inputSource, matches: sourceID)
        }
    }

    private static func sourceIdentifier(for inputSource: TISInputSource) -> String? {
        guard let rawValue = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) else {
            return nil
        }

        return unsafeBitCast(rawValue, to: CFString.self) as String
    }

    private static func inputSource(_ inputSource: TISInputSource, matches sourceID: String?) -> Bool {
        guard let sourceID, let currentSourceID = sourceIdentifier(for: inputSource) else {
            return false
        }

        return currentSourceID == sourceID
    }
}
