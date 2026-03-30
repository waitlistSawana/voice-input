import AppKit
import Foundation
import Testing
@testable import VoiceInputCore

private final class ClipboardProbe: @unchecked Sendable {
    var snapshotToReturn = ClipboardSnapshot(items: [["existing": .data(Data("clipboard".utf8))]])
    var snapshots: [ClipboardSnapshot] = []
    var restoredSnapshots: [ClipboardSnapshot] = []
    var writtenTexts: [String] = []
}

private final class InputSourceProbe: @unchecked Sendable {
    var currentSource: InputSourceMetadata?
    var asciiSwitchTarget: InputSourceMetadata?
    var storedOriginalSource: InputSourceMetadata?
    var restoredSources: [InputSourceMetadata?] = []
    var switchCalls = 0
    var restoreCalls = 0
    var shouldFailSwitch = false
    var shouldFailRestore = false
}

private final class CallTrace: @unchecked Sendable {
    var entries: [String] = []
}

struct TextInjectorTests {
    @Test func restoresStringOnlyClipboardFlavorsWithoutReencoding() {
        let pasteboard = NSPasteboard.general
        let original = ClipboardSnapshot(pasteboard: pasteboard)
        defer {
            original.restore(to: pasteboard)
        }

        let customType = NSPasteboard.PasteboardType("com.example.string-only")
        let snapshot = ClipboardSnapshot(items: [[customType.rawValue: .string("hello")]])

        snapshot.restore(to: pasteboard)

        #expect(pasteboard.string(forType: customType) == "hello")
    }

    @Test func injectsInTheExpectedTransactionOrder() {
        let clipboard = ClipboardProbe()
        let inputSource = InputSourceProbe()
        let trace = CallTrace()

        let originalSource = InputSourceMetadata(
            sourceID: "com.apple.inputmethod.SCIM.ITABC",
            localizedName: "中文 - 简体拼音",
            languages: [],
            isASCIICapable: false
        )
        let asciiSource = InputSourceMetadata(
            sourceID: "com.apple.keylayout.ABC",
            localizedName: "ABC",
            languages: ["en"],
            isASCIICapable: true
        )

        inputSource.currentSource = originalSource
        inputSource.asciiSwitchTarget = asciiSource

        let injector = Self.makeInjector(
            clipboard: clipboard,
            inputSource: inputSource,
            trace: trace
        )

        injector.inject("hello")

        #expect(trace.entries == [
            "snapshot",
            "current",
            "switch",
            "write",
            "paste",
            "sleep",
            "restore",
            "clipboard-restore"
        ])
        #expect(inputSource.restoredSources == [originalSource])
        #expect(clipboard.writtenTexts == ["hello"])
        #expect(clipboard.restoredSnapshots == [clipboard.snapshotToReturn])
    }

    @Test func continuesWhenAsciiSwitchLookupFailsAndDoesNotStoreRestoreState() {
        let clipboard = ClipboardProbe()
        let inputSource = InputSourceProbe()
        let trace = CallTrace()

        inputSource.currentSource = InputSourceMetadata(
            sourceID: "com.apple.inputmethod.SCIM.ITABC",
            localizedName: "中文 - 简体拼音",
            languages: [],
            isASCIICapable: false
        )
        inputSource.asciiSwitchTarget = nil

        let injector = Self.makeInjector(
            clipboard: clipboard,
            inputSource: inputSource,
            trace: trace
        )

        injector.inject("hello")

        #expect(trace.entries == [
            "snapshot",
            "current",
            "switch",
            "write",
            "paste",
            "sleep",
            "restore",
            "clipboard-restore"
        ])
        #expect(inputSource.switchCalls == 1)
        #expect(inputSource.restoreCalls == 1)
        #expect(inputSource.restoredSources.isEmpty)
        #expect(clipboard.writtenTexts == ["hello"])
        #expect(clipboard.restoredSnapshots == [clipboard.snapshotToReturn])
    }

    @Test func doesNotRestoreAStaleSourceOnLaterInjectionThatDoesNotSwitch() {
        let clipboard = ClipboardProbe()
        let inputSource = InputSourceProbe()
        let trace = CallTrace()

        let cjkSource = InputSourceMetadata(
            sourceID: "com.apple.inputmethod.SCIM.ITABC",
            localizedName: "中文 - 简体拼音",
            languages: [],
            isASCIICapable: false
        )
        let asciiSource = InputSourceMetadata(
            sourceID: "com.apple.keylayout.ABC",
            localizedName: "ABC",
            languages: ["en"],
            isASCIICapable: true
        )

        inputSource.currentSource = cjkSource
        inputSource.asciiSwitchTarget = asciiSource

        let injector = Self.makeInjector(
            clipboard: clipboard,
            inputSource: inputSource,
            trace: trace
        )

        injector.inject("first")
        #expect(inputSource.restoredSources == [cjkSource])

        trace.entries.removeAll(keepingCapacity: true)
        clipboard.writtenTexts.removeAll(keepingCapacity: true)
        clipboard.restoredSnapshots.removeAll(keepingCapacity: true)

        inputSource.currentSource = asciiSource
        inputSource.asciiSwitchTarget = nil

        injector.inject("second")

        #expect(trace.entries == [
            "snapshot",
            "current",
            "write",
            "paste",
            "sleep",
            "restore",
            "clipboard-restore"
        ])
        #expect(inputSource.restoredSources == [cjkSource])
        #expect(inputSource.restoreCalls == 2)
        #expect(clipboard.writtenTexts == ["second"])
        #expect(clipboard.restoredSnapshots == [clipboard.snapshotToReturn])
    }

    private static func makeInjector(
        clipboard: ClipboardProbe,
        inputSource: InputSourceProbe,
        trace: CallTrace
    ) -> TextInjector {
        TextInjector(
            clipboard: ClipboardBackend(
                snapshot: {
                    trace.entries.append("snapshot")
                    clipboard.snapshots.append(clipboard.snapshotToReturn)
                    return clipboard.snapshotToReturn
                },
                restore: { snapshot in
                    trace.entries.append("clipboard-restore")
                    clipboard.restoredSnapshots.append(snapshot)
                },
                writeText: { text in
                    trace.entries.append("write")
                    clipboard.writtenTexts.append(text)
                }
            ),
            inputSourceManager: InputSourceBackend(
                current: {
                    trace.entries.append("current")
                    return inputSource.currentSource
                },
                switchToASCII: {
                    trace.entries.append("switch")
                    inputSource.switchCalls += 1

                    guard
                        !inputSource.shouldFailSwitch,
                        let currentSource = inputSource.currentSource,
                        let target = inputSource.asciiSwitchTarget
                    else {
                        return false
                    }

                    inputSource.storedOriginalSource = currentSource
                    inputSource.currentSource = target
                    return true
                },
                restoreOriginal: {
                    trace.entries.append("restore")
                    inputSource.restoreCalls += 1

                    guard let originalSource = inputSource.storedOriginalSource else {
                        return false
                    }

                    inputSource.storedOriginalSource = nil

                    guard !inputSource.shouldFailRestore else {
                        return false
                    }

                    inputSource.currentSource = originalSource
                    inputSource.restoredSources.append(originalSource)
                    return true
                }
            ),
            eventPoster: {
                trace.entries.append("paste")
            },
            sleeper: { _ in
                trace.entries.append("sleep")
            }
        )
    }
}
