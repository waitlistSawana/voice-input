import Foundation
import Testing
@testable import VoiceInputCore

struct InputSourceClassificationTests {
    @Test func localizedNamesDoNotDriveCjkClassificationByThemselves() {
        let metadata = InputSourceMetadata(
            sourceID: "com.example.non-cjk",
            localizedName: "简体中文 - 拼音",
            languages: [],
            isASCIICapable: true
        )

        #expect(metadata.isCJK == false)
    }

    @Test func languagesDriveCjkClassification() {
        let metadata = InputSourceMetadata(
            sourceID: "com.example.cjk",
            localizedName: "Chinese",
            languages: ["zh-Hans"],
            isASCIICapable: false
        )

        #expect(metadata.isCJK == true)
    }

    @Test func appleCjkInputSourceIdentifiersAreClassifiedWithoutLanguages() {
        let metadata = InputSourceMetadata(
            sourceID: "com.apple.inputmethod.SCIM.ITABC",
            localizedName: "Chinese - Simplified",
            languages: [],
            isASCIICapable: false
        )

        #expect(metadata.isCJK == true)
    }

    @Test func appleCjkInputModeIdentifiersAreClassifiedWithoutLanguages() {
        let metadata = InputSourceMetadata(
            sourceID: "com.example.apple-input-source",
            localizedName: "Chinese - Simplified",
            languages: [],
            isASCIICapable: false,
            inputModeID: "com.apple.inputmethod.SCIM.ITABC"
        )

        #expect(metadata.isCJK == true)
    }

    @Test func preferredAsciiSwitchUsesAbcBeforeUsFallback() {
        let manager = InputSourceManager()

        let sources = [
            InputSourceMetadata(
                sourceID: "com.apple.keylayout.US",
                localizedName: "U.S.",
                languages: ["en"],
                isASCIICapable: true
            ),
            InputSourceMetadata(
                sourceID: "com.apple.keylayout.ABC",
                localizedName: "ABC",
                languages: ["en"],
                isASCIICapable: true
            )
        ]

        #expect(manager.preferredASCIIInputSourceIdentifier(from: sources) == "com.apple.keylayout.ABC")
    }

    @Test func preferredAsciiSwitchFallsBackToUsWhenAbcIsUnavailable() {
        let manager = InputSourceManager()

        let sources = [
            InputSourceMetadata(
                sourceID: "com.apple.keylayout.US",
                localizedName: "U.S.",
                languages: ["en"],
                isASCIICapable: true
            ),
            InputSourceMetadata(
                sourceID: "com.example.dvorak",
                localizedName: "Dvorak",
                languages: ["en"],
                isASCIICapable: true
            )
        ]

        #expect(manager.preferredASCIIInputSourceIdentifier(from: sources) == "com.apple.keylayout.US")
    }
}
