import Foundation
import Testing
@testable import VoiceInputCore

struct BundleLayoutSmokeTests {
    private static let buildCoordinator = BuildCoordinator()

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func builtBundleURL() throws -> URL {
        try Self.buildCoordinator.buildIfNeeded(packageRoot: packageRoot)
    }

    private func readPlist(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        var format = PropertyListSerialization.PropertyListFormat.xml
        return try PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? [String: Any] ?? [:]
    }

    @Test func defaultLocaleConstantIsChinese() {
        #expect(AppDefaults.defaultLocaleIdentifier == "zh-CN")
    }

    @Test func supportedLocalesIncludeFiveMenuLanguages() {
        #expect(AppLocale.allCases.map(\.rawValue) == ["en-US", "zh-CN", "zh-TW", "ja-JP", "ko-KR"])
    }

    @Test func builtBundleContainsExpectedMetadata() throws {
        let builtAppURL = try builtBundleURL()
        let plist = try readPlist(at: builtAppURL.appendingPathComponent("Contents/Info.plist"))
        #expect(plist["LSUIElement"] as? Bool == true)
        #expect(plist["NSMicrophoneUsageDescription"] as? String == "VoiceInput needs microphone access to record speech while you hold Fn.")
        #expect(plist["NSSpeechRecognitionUsageDescription"] as? String == "VoiceInput needs speech recognition access to transcribe your recording.")
        #expect(plist["CFBundleIconFile"] as? String == "AppIcon")
    }

    @Test func builtBundleContainsIconArtifact() throws {
        let builtAppURL = try builtBundleURL()
        #expect(FileManager.default.fileExists(atPath: builtAppURL.appendingPathComponent("Contents/Resources/AppIcon.icns").path))
    }
}

private final class BuildCoordinator {
    private let lock = NSLock()
    private var didBuild = false
    private var builtAppURL: URL?

    func buildIfNeeded(packageRoot: URL) throws -> URL {
        lock.lock()
        defer { lock.unlock() }

        if let builtAppURL {
            return builtAppURL
        }
        let isolatedRoot = try makeIsolatedPackageCopy(from: packageRoot)
        try runMakeBuild(in: isolatedRoot)
        let builtAppURL = isolatedRoot.appendingPathComponent("dist/VoiceInput.app")
        self.builtAppURL = builtAppURL
        didBuild = true
        return builtAppURL
    }

    private func makeIsolatedPackageCopy(from packageRoot: URL) throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-input-smoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        for item in ["Package.swift", "Package.resolved", "Makefile", "Sources", "Resources", "Tests"] {
            let source = packageRoot.appendingPathComponent(item)
            let target = destination.appendingPathComponent(item)
            if FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.copyItem(at: source, to: target)
            }
        }

        return destination
    }

    private func runMakeBuild(in packageRoot: URL) throws {
        let process = Process()
        process.currentDirectoryURL = packageRoot
        process.executableURL = URL(fileURLWithPath: "/usr/bin/make")
        process.arguments = ["build"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self)
            throw NSError(domain: "BundleLayoutSmokeTests", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "make build failed with status \(process.terminationStatus):\n\(output)"
            ])
        }
    }
}
