import ApplicationServices
import Carbon.HIToolbox
import Foundation

public struct InputSourceMetadata: Equatable, Sendable {
    public var sourceID: String?
    public var localizedName: String?
    public var languages: [String]
    public var isASCIICapable: Bool
    public var inputModeID: String?

    public init(
        sourceID: String?,
        localizedName: String?,
        languages: [String],
        isASCIICapable: Bool,
        inputModeID: String? = nil
    ) {
        self.sourceID = sourceID
        self.localizedName = localizedName
        self.languages = languages
        self.isASCIICapable = isASCIICapable
        self.inputModeID = inputModeID
    }

    public var isCJK: Bool {
        let cjkLanguagePrefixes = ["zh", "ja", "ko"]
        if languages.contains(where: { language in
            let lowercased = language.lowercased()
            return cjkLanguagePrefixes.contains(where: { lowercased.hasPrefix($0) })
        }) {
            return true
        }

        let metadataFields = [sourceID, inputModeID]
            .compactMap { $0?.lowercased() }

        if metadataFields.contains(where: Self.appleCJKIdentifiers.contains) {
            return true
        }

        let combinedMetadata = metadataFields.joined(separator: " ")
        return Self.appleCJKMarkers.contains(where: { combinedMetadata.contains($0) })
    }

    private static let appleCJKIdentifiers: Set<String> = [
        "com.apple.inputmethod.scim.itabc",
        "com.apple.inputmethod.scim.pinyin",
        "com.apple.inputmethod.scim.zhuyin",
        "com.apple.inputmethod.scim.cangjie",
        "com.apple.inputmethod.scim.wubi",
        "com.apple.inputmethod.scim.shuangpin",
        "com.apple.inputmethod.scim.bopomofo",
        "com.apple.inputmethod.scim.chewing",
        "com.apple.inputmethod.kotoeri.japanese",
        "com.apple.inputmethod.kotoeri.romajityping.japanese",
        "com.apple.inputmethod.kotoeri.hiragana",
        "com.apple.inputmethod.kotoeri.katakana",
        "com.apple.inputmethod.kotoeri.romaji",
        "com.apple.inputmethod.korean.2setkorean",
        "com.apple.inputmethod.korean.3setkorean",
        "com.apple.inputmethod.korean.hangul"
    ]

    private static let appleCJKMarkers = [
        "chinese",
        "pinyin",
        "zhuyin",
        "cangjie",
        "wubi",
        "shuangpin",
        "bopomofo",
        "chewing",
        "japanese",
        "hiragana",
        "katakana",
        "romaji",
        "korean",
        "hangul",
        "kana",
        "itabc"
    ]
}

public final class InputSourceManager {
    public init() {}

    public func currentInputSourceMetadata() -> InputSourceMetadata? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }

        return Self.metadata(from: source)
    }

    public func preferredASCIIInputSourceIdentifier(from sources: [InputSourceMetadata]) -> String? {
        let preferredIdentifiers = [
            "com.apple.keylayout.ABC",
            "com.apple.keylayout.US"
        ]

        for preferredIdentifier in preferredIdentifiers {
            if sources.contains(where: { $0.sourceID == preferredIdentifier && $0.isASCIICapable }) {
                return preferredIdentifier
            }
        }

        return sources.first(where: { $0.isASCIICapable })?.sourceID
    }

    public func availableInputSourceMetadata() -> [InputSourceMetadata] {
        guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() else {
            return []
        }

        let count = CFArrayGetCount(sources)
        return (0 ..< count).compactMap { index in
            let rawSource = CFArrayGetValueAtIndex(sources, index)
            return Self.metadata(from: unsafeBitCast(rawSource, to: TISInputSource.self))
        }
    }

    public func preferredASCIIInputSourceMetadata() -> InputSourceMetadata? {
        let sources = availableInputSourceMetadata()
        guard let preferredIdentifier = preferredASCIIInputSourceIdentifier(from: sources) else {
            return nil
        }

        return sources.first { $0.sourceID == preferredIdentifier }
    }

    private static func metadata(from inputSource: TISInputSource) -> InputSourceMetadata? {
        func stringValue(for property: CFString) -> String? {
            guard let rawValue = TISGetInputSourceProperty(inputSource, property) else {
                return nil
            }
            return unsafeBitCast(rawValue, to: CFString.self) as String
        }

        func boolValue(for property: CFString) -> Bool {
            guard let rawValue = TISGetInputSourceProperty(inputSource, property) else {
                return false
            }
            return CFBooleanGetValue(unsafeBitCast(rawValue, to: CFBoolean.self))
        }

        func stringArrayValue(for property: CFString) -> [String] {
            guard let rawValue = TISGetInputSourceProperty(inputSource, property) else {
                return []
            }

            let array = unsafeBitCast(rawValue, to: CFArray.self)
            return (array as NSArray).compactMap { $0 as? String }
        }

        return InputSourceMetadata(
            sourceID: stringValue(for: kTISPropertyInputSourceID),
            localizedName: stringValue(for: kTISPropertyLocalizedName),
            languages: stringArrayValue(for: kTISPropertyInputSourceLanguages),
            isASCIICapable: boolValue(for: kTISPropertyInputSourceIsASCIICapable),
            inputModeID: stringValue(for: kTISPropertyInputModeID)
        )
    }
}
