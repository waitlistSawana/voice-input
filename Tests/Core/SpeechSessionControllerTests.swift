import AVFoundation
import Foundation
import Testing
@testable import VoiceInputCore

private enum SessionTestError: Error, Equatable {
    case marker
}

private final class AudioCaptureEngineProbe: @unchecked Sendable, AudioCaptureEngineProtocol {
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    private(set) var startCalls = 0
    private(set) var stopCalls = 0
    var startError: Error?

    func start() throws {
        startCalls += 1
        if let startError {
            throw startError
        }
    }

    func stop() {
        stopCalls += 1
    }

    func emitBuffer(_ buffer: AVAudioPCMBuffer) {
        onBuffer?(buffer)
    }
}

private final class SpeechRecognizerServiceProbe: @unchecked Sendable, SpeechRecognizerServiceProtocol {
    var onPartialText: ((String) -> Void)?
    var onFinish: ((Result<String, Error>) -> Void)?
    private(set) var startedLocales: [String] = []
    private(set) var appendedBufferCount = 0
    private(set) var stopCalls = 0
    var startError: Error?

    func start(localeIdentifier: String) throws {
        startedLocales.append(localeIdentifier)
        if let startError {
            throw startError
        }
    }

    func append(buffer: AVAudioPCMBuffer) {
        appendedBufferCount += 1
    }

    func stop() {
        stopCalls += 1
    }

    func emitPartial(_ text: String) {
        onPartialText?(text)
    }

    func emitFinish(_ result: Result<String, Error>) {
        onFinish?(result)
    }
}

private final class TextInjectorProbe: @unchecked Sendable, TextInjectorProtocol {
    private(set) var injectedTexts: [String] = []

    func inject(_ text: String) {
        injectedTexts.append(text)
    }
}

private final class LLMRefinerProbe: @unchecked Sendable, LLMRefinerProtocol {
    struct Call: Equatable {
        let transcript: String
        let configuration: LLMConfiguration
    }

    private(set) var calls: [Call] = []
    var handler: @Sendable (String, LLMConfiguration) async throws -> String = { transcript, _ in transcript }

    func refine(transcript: String, config: LLMConfiguration) async throws -> String {
        calls.append(Call(transcript: transcript, configuration: config))
        return try await handler(transcript, config)
    }
}

private final class CallbackRecorder: @unchecked Sendable {
    var hudVisibility: [Bool] = []
    var statuses: [String] = []
    var transcripts: [String?] = []
    var levels: [CGFloat] = []
}

private final class DelaySchedulerProbe: @unchecked Sendable {
    var scheduledDelays: [TimeInterval] = []
    var scheduledActions: [() -> Void] = []

    func schedule(delay: TimeInterval, action: @escaping () -> Void) {
        scheduledDelays.append(delay)
        scheduledActions.append(action)
    }

    func fireFirst() {
        guard !scheduledActions.isEmpty else {
            return
        }

        let action = scheduledActions.removeFirst()
        action()
    }
}

private final class LoggerProbe: @unchecked Sendable {
    var messages: [String] = []

    func log(_ message: String) {
        messages.append(message)
    }
}

private final class ContinuationBox: @unchecked Sendable {
    var continuation: CheckedContinuation<String, Error>?
}

struct SpeechSessionControllerTests {
    @Test func stateMachineRoutesRecordingCompletionIntoRefiningWhenEnabled() {
        let state = SpeechSessionState.nextState(
            current: .recording,
            event: .recognitionFinished(hasTranscript: true, shouldRefine: true)
        )

        #expect(state == .refining)
    }

    @Test func stateMachineReturnsToIdleForEmptyTranscript() {
        let state = SpeechSessionState.nextState(
            current: .recording,
            event: .recognitionFinished(hasTranscript: false, shouldRefine: false)
        )

        #expect(state == .idle)
    }

    @Test func fnPressStartsRecordingShowsHUDAndStreamsBuffers() throws {
        let defaults = UserDefaults(suiteName: "SpeechSessionControllerTests.press")!
        defaults.removePersistentDomain(forName: "SpeechSessionControllerTests.press")
        let settings = SettingsStore(defaults: defaults, notificationCenter: .init())
        settings.selectedLocale = .japanese

        let audioCapture = AudioCaptureEngineProbe()
        let speechRecognizer = SpeechRecognizerServiceProbe()
        let textInjector = TextInjectorProbe()
        let refiner = LLMRefinerProbe()
        let callbacks = CallbackRecorder()
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2))
        buffer.frameLength = 2
        buffer.floatChannelData?[0][0] = 0.25
        buffer.floatChannelData?[0][1] = 0.5

        let controller = SpeechSessionController(
            settingsStore: settings,
            audioCaptureEngine: audioCapture,
            speechRecognizerService: speechRecognizer,
            textInjector: textInjector,
            llmRefiner: refiner,
            makeLevelProcessor: {
                { (_: AVAudioPCMBuffer) in 0.42 }
            }
        )
        controller.onHUDVisibilityChange = { callbacks.hudVisibility.append($0) }
        controller.onStatusTextChange = { callbacks.statuses.append($0) }
        controller.onTranscriptChange = { callbacks.transcripts.append($0) }
        controller.onLevelChange = { callbacks.levels.append($0) }

        controller.handleFnPressed()
        audioCapture.emitBuffer(buffer)

        #expect(controller.state == .recording)
        #expect(callbacks.hudVisibility == [true])
        #expect(callbacks.statuses == ["请讲话"])
        #expect(callbacks.transcripts == [nil])
        #expect(speechRecognizer.startedLocales == ["ja-JP"])
        #expect(audioCapture.startCalls == 1)
        #expect(speechRecognizer.appendedBufferCount == 1)
        #expect(callbacks.levels == [0, 0.42])
        #expect(textInjector.injectedTexts.isEmpty)
        #expect(refiner.calls.isEmpty)
    }

    @Test func ignoresFnPressWhileAlreadyRecording() {
        let controller = Self.makeController()

        controller.controller.handleFnPressed()
        controller.controller.handleFnPressed()

        #expect(controller.audioCapture.startCalls == 1)
        #expect(controller.speechRecognizer.startedLocales == ["zh-CN"])
        #expect(controller.callbacks.hudVisibility == [true])
    }

    @Test func directInjectionWaitsForFinalRecognitionResultAfterRelease() async {
        let controller = Self.makeController()

        controller.controller.handleFnPressed()
        controller.controller.handleFnReleased()

        #expect(controller.audioCapture.stopCalls == 1)
        #expect(controller.speechRecognizer.stopCalls == 1)
        #expect(controller.textInjector.injectedTexts.isEmpty)

        controller.speechRecognizer.emitFinish(Result<String, Error>.success("final transcript"))
        await Self.waitUntil { !controller.textInjector.injectedTexts.isEmpty }

        #expect(controller.controller.state == .idle)
        #expect(controller.textInjector.injectedTexts == ["final transcript"])
        #expect(controller.refiner.calls.isEmpty)
        #expect(controller.callbacks.hudVisibility == [true, false])
        #expect(controller.callbacks.statuses == ["请讲话"])
    }

    @Test func recognitionResultThatFinishesBeforeReleaseStillInjectsOnRelease() async {
        let controller = Self.makeController()

        controller.controller.handleFnPressed()
        controller.speechRecognizer.emitFinish(Result<String, Error>.success("final transcript"))
        #expect(controller.controller.state == .recording)
        #expect(controller.textInjector.injectedTexts.isEmpty)

        controller.controller.handleFnReleased()
        await Self.waitUntil { !controller.textInjector.injectedTexts.isEmpty }

        #expect(controller.textInjector.injectedTexts == ["final transcript"])
        #expect(controller.controller.state == .idle)
        #expect(controller.callbacks.hudVisibility == [true, false])
    }

    @Test func emptyTranscriptShowsNoContentStateBeforeDelayedHide() async {
        let controller = Self.makeController()

        controller.controller.handleFnPressed()
        controller.controller.handleFnReleased()
        controller.speechRecognizer.emitFinish(Result<String, Error>.success("   "))
        await Self.waitUntil { controller.controller.state == .idle }

        #expect(controller.textInjector.injectedTexts.isEmpty)
        #expect(controller.refiner.calls.isEmpty)
        #expect(controller.callbacks.statuses == ["请讲话", "未识别到内容"])
        #expect(controller.callbacks.hudVisibility == [true])
        #expect(controller.scheduler.scheduledDelays == [0.25])
        controller.scheduler.fireFirst()
        #expect(controller.callbacks.hudVisibility == [true, false])
        #expect(controller.controller.state == .idle)
    }

    @Test func recognitionErrorWithoutTranscriptShowsErrorStateBeforeDelayedHide() async {
        let controller = Self.makeController()

        controller.controller.handleFnPressed()
        controller.controller.handleFnReleased()
        controller.speechRecognizer.emitFinish(Result<String, Error>.failure(SessionTestError.marker))
        await Self.waitUntil { controller.controller.state == .idle }

        #expect(controller.textInjector.injectedTexts.isEmpty)
        #expect(controller.callbacks.statuses == ["请讲话", "语音识别不可用"])
        #expect(controller.callbacks.hudVisibility == [true])
        #expect(controller.scheduler.scheduledDelays == [0.25])
        controller.scheduler.fireFirst()
        #expect(controller.callbacks.hudVisibility == [true, false])
    }

    @Test func enabledRefinementTransitionsThroughRefiningAndInjectsRefinedText() async throws {
        let defaults = UserDefaults(suiteName: "SpeechSessionControllerTests.refining")!
        defaults.removePersistentDomain(forName: "SpeechSessionControllerTests.refining")
        let settings = SettingsStore(defaults: defaults, notificationCenter: .init())
        settings.isLLMRefinementEnabled = true
        settings.llmConfiguration = LLMConfiguration(
            baseURL: "https://example.com/v1",
            apiKey: "secret",
            model: "gpt-4.1-mini"
        )

        let audioCapture = AudioCaptureEngineProbe()
        let speechRecognizer = SpeechRecognizerServiceProbe()
        let textInjector = TextInjectorProbe()
        let refiner = LLMRefinerProbe()
        let callbacks = CallbackRecorder()
        let continuationBox = ContinuationBox()
        refiner.handler = { _, _ in
            try await withCheckedThrowingContinuation { checkedContinuation in
                continuationBox.continuation = checkedContinuation
            }
        }

        let controller = SpeechSessionController(
            settingsStore: settings,
            audioCaptureEngine: audioCapture,
            speechRecognizerService: speechRecognizer,
            textInjector: textInjector,
            llmRefiner: refiner
        )
        controller.onHUDVisibilityChange = { callbacks.hudVisibility.append($0) }
        controller.onStatusTextChange = { callbacks.statuses.append($0) }
        controller.onTranscriptChange = { callbacks.transcripts.append($0) }
        controller.onLevelChange = { callbacks.levels.append($0) }

        controller.handleFnPressed()
        speechRecognizer.emitPartial("rough transcript")
        controller.handleFnReleased()
        speechRecognizer.emitFinish(Result<String, Error>.success("rough transcript"))
        await Self.waitUntil { controller.state == .refining }
        await Self.waitUntil { !refiner.calls.isEmpty }
        await Self.waitUntil { continuationBox.continuation != nil }

        #expect(refiner.calls == [
            .init(
                transcript: "rough transcript",
                configuration: settings.llmConfiguration
            )
        ])
        #expect(callbacks.statuses == ["请讲话", "Refining..."])
        #expect(textInjector.injectedTexts.isEmpty)

        continuationBox.continuation?.resume(returning: "refined transcript")
        await Self.waitUntil { !textInjector.injectedTexts.isEmpty }

        #expect(textInjector.injectedTexts == ["refined transcript"])
        #expect(controller.state == .idle)
        #expect(callbacks.hudVisibility == [true, false])
    }

    @Test func refinementFailureFallsBackToOriginalTranscript() async {
        let controller = Self.makeController(
            llmEnabled: true,
            configuration: LLMConfiguration(
                baseURL: "https://example.com/v1",
                apiKey: "secret",
                model: "gpt-4.1-mini"
            )
        )
        controller.refiner.handler = { (_: String, _: LLMConfiguration) in
            throw SessionTestError.marker
        }

        controller.controller.handleFnPressed()
        controller.controller.handleFnReleased()
        controller.speechRecognizer.emitFinish(Result<String, Error>.success("original transcript"))
        await Self.waitUntil { !controller.refiner.calls.isEmpty }
        await Self.waitUntil { !controller.textInjector.injectedTexts.isEmpty }

        #expect(controller.textInjector.injectedTexts == ["original transcript"])
        #expect(controller.controller.state == .idle)
        #expect(controller.callbacks.statuses == ["请讲话", "Refining..."])
        #expect(controller.logger.messages.count == 1)
        #expect(controller.logger.messages[0].contains("Refinement failed"))
    }

    private static func makeController(
        llmEnabled: Bool = false,
        configuration: LLMConfiguration = .init()
    ) -> ControllerHarness {
        let suiteName = "SpeechSessionControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = SettingsStore(defaults: defaults, notificationCenter: .init())
        settings.isLLMRefinementEnabled = llmEnabled
        settings.llmConfiguration = configuration

        let audioCapture = AudioCaptureEngineProbe()
        let speechRecognizer = SpeechRecognizerServiceProbe()
        let textInjector = TextInjectorProbe()
        let refiner = LLMRefinerProbe()
        let callbacks = CallbackRecorder()
        let scheduler = DelaySchedulerProbe()
        let logger = LoggerProbe()
        let controller = SpeechSessionController(
            settingsStore: settings,
            audioCaptureEngine: audioCapture,
            speechRecognizerService: speechRecognizer,
            textInjector: textInjector,
            llmRefiner: refiner,
            statusMessageDuration: 0.25,
            delayedScheduler: { delay, action in
                scheduler.schedule(delay: delay, action: action)
            },
            logger: { message in
                logger.log(message)
            }
        )
        controller.onHUDVisibilityChange = { callbacks.hudVisibility.append($0) }
        controller.onStatusTextChange = { callbacks.statuses.append($0) }
        controller.onTranscriptChange = { callbacks.transcripts.append($0) }
        controller.onLevelChange = { callbacks.levels.append($0) }

        return ControllerHarness(
            controller: controller,
            audioCapture: audioCapture,
            speechRecognizer: speechRecognizer,
            textInjector: textInjector,
            refiner: refiner,
            callbacks: callbacks,
            scheduler: scheduler,
            logger: logger
        )
    }

    private static func waitUntil(
        iterations: Int = 200,
        condition: @escaping @Sendable () -> Bool
    ) async {
        for _ in 0 ..< iterations {
            if condition() {
                return
            }

            await Task.yield()
        }

        #expect(Bool(false), "condition was not satisfied before timing out")
    }
}

private struct ControllerHarness {
    let controller: SpeechSessionController
    let audioCapture: AudioCaptureEngineProbe
    let speechRecognizer: SpeechRecognizerServiceProbe
    let textInjector: TextInjectorProbe
    let refiner: LLMRefinerProbe
    let callbacks: CallbackRecorder
    let scheduler: DelaySchedulerProbe
    let logger: LoggerProbe
}
