import AVFoundation
import Foundation

protocol AudioCaptureEngineProtocol: AnyObject {
    var onBuffer: ((AVAudioPCMBuffer) -> Void)? { get set }
    func start() throws
    func stop()
}

protocol SpeechRecognizerServiceProtocol: AnyObject {
    var onPartialText: ((String) -> Void)? { get set }
    var onFinish: ((Result<String, Error>) -> Void)? { get set }
    func start(localeIdentifier: String) throws
    func append(buffer: AVAudioPCMBuffer)
    func stop()
}

protocol TextInjectorProtocol: AnyObject {
    func inject(_ text: String)
}

protocol LLMRefinerProtocol: AnyObject {
    func refine(transcript: String, config: LLMConfiguration) async throws -> String
}

extension AudioCaptureEngine: AudioCaptureEngineProtocol {}
extension SpeechRecognizerService: SpeechRecognizerServiceProtocol {}
extension TextInjector: TextInjectorProtocol {}
extension LLMRefiner: LLMRefinerProtocol {}

public enum SpeechSessionState: Equatable {
    case idle
    case recording
    case refining
    case injecting

    public enum Event {
        case fnPressed
        case recognitionFinished(hasTranscript: Bool, shouldRefine: Bool)
        case refinementFinished
        case injectionFinished
        case failed
    }

    public static func nextState(current: SpeechSessionState, event: Event) -> SpeechSessionState {
        switch (current, event) {
        case (.idle, .fnPressed):
            return .recording
        case (.recording, .recognitionFinished(let hasTranscript, let shouldRefine)):
            guard hasTranscript else {
                return .idle
            }
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

public final class SpeechSessionController {
    typealias LevelProcessor = (AVAudioPCMBuffer) -> CGFloat
    typealias SessionDispatcher = (@escaping () -> Void) -> Void
    typealias DelayedScheduler = (TimeInterval, @escaping @Sendable () -> Void) -> Void
    typealias Logger = (String) -> Void

    public private(set) var state: SpeechSessionState = .idle

    public var onHUDVisibilityChange: ((Bool) -> Void)?
    public var onStatusTextChange: ((String) -> Void)?
    public var onTranscriptChange: ((String?) -> Void)?
    public var onLevelChange: ((CGFloat) -> Void)?

    private let settingsStore: SettingsStore
    private let audioCaptureEngine: any AudioCaptureEngineProtocol
    private let speechRecognizerService: any SpeechRecognizerServiceProtocol
    private let textInjector: any TextInjectorProtocol
    private let llmRefiner: any LLMRefinerProtocol
    private let makeLevelProcessor: () -> LevelProcessor
    private let sessionDispatcher: SessionDispatcher
    private let statusMessageDuration: TimeInterval
    private let delayedScheduler: DelayedScheduler
    private let logger: Logger

    private var transcript = ""
    private var levelProcessor: LevelProcessor
    private var hasRequestedStop = false
    private var pendingRecognitionResult: Result<String, Error>?
    private var hudDismissGeneration: UInt64 = 0

    public convenience init(settingsStore: SettingsStore) {
        self.init(
            settingsStore: settingsStore,
            audioCaptureEngine: AudioCaptureEngine(),
            speechRecognizerService: SpeechRecognizerService(),
            textInjector: TextInjector(),
            llmRefiner: LLMRefiner(),
            makeLevelProcessor: Self.makeDefaultLevelProcessor,
            statusMessageDuration: 0.4,
            delayedScheduler: Self.makeDefaultDelayedScheduler,
            logger: Self.makeDefaultLogger,
            sessionDispatcher: { operation in
                DispatchQueue.main.async(execute: operation)
            }
        )
    }

    init(
        settingsStore: SettingsStore,
        audioCaptureEngine: any AudioCaptureEngineProtocol,
        speechRecognizerService: any SpeechRecognizerServiceProtocol,
        textInjector: any TextInjectorProtocol,
        llmRefiner: any LLMRefinerProtocol,
        makeLevelProcessor: (() -> LevelProcessor)? = nil,
        statusMessageDuration: TimeInterval = 0.4,
        delayedScheduler: DelayedScheduler? = nil,
        logger: Logger? = nil,
        sessionDispatcher: @escaping SessionDispatcher = { $0() }
    ) {
        self.settingsStore = settingsStore
        self.audioCaptureEngine = audioCaptureEngine
        self.speechRecognizerService = speechRecognizerService
        self.textInjector = textInjector
        self.llmRefiner = llmRefiner
        self.makeLevelProcessor = makeLevelProcessor ?? Self.makeDefaultLevelProcessor
        self.statusMessageDuration = statusMessageDuration
        self.delayedScheduler = delayedScheduler ?? Self.makeDefaultDelayedScheduler
        self.logger = logger ?? Self.makeDefaultLogger
        self.sessionDispatcher = sessionDispatcher
        levelProcessor = self.makeLevelProcessor()

        bindServices()
    }

    public func handleFnPressed() {
        guard state == .idle else {
            return
        }

        cancelPendingHUDHide()
        state = SpeechSessionState.nextState(current: state, event: .fnPressed)
        hasRequestedStop = false
        pendingRecognitionResult = nil
        transcript = ""
        levelProcessor = makeLevelProcessor()

        onTranscriptChange?(nil)
        onLevelChange?(0)
        onStatusTextChange?("请讲话")
        onHUDVisibilityChange?(true)

        do {
            try speechRecognizerService.start(localeIdentifier: settingsStore.selectedLocale.rawValue)
            try audioCaptureEngine.start()
        } catch {
            failSession()
        }
    }

    public func handleFnReleased() {
        guard state == .recording, !hasRequestedStop else {
            return
        }

        hasRequestedStop = true
        audioCaptureEngine.stop()
        speechRecognizerService.stop()

        if let pendingRecognitionResult {
            processRecognitionFinish(pendingRecognitionResult)
        }
    }

    private func bindServices() {
        audioCaptureEngine.onBuffer = { [weak self] buffer in
            self?.handleCapturedBuffer(buffer)
        }

        speechRecognizerService.onPartialText = { [weak self] text in
            self?.handlePartialText(text)
        }

        speechRecognizerService.onFinish = { [weak self] result in
            self?.handleRecognitionFinish(result)
        }
    }

    private func handleCapturedBuffer(_ buffer: AVAudioPCMBuffer) {
        guard state == .recording else {
            return
        }

        speechRecognizerService.append(buffer: buffer)
        onLevelChange?(levelProcessor(buffer))
    }

    private func handlePartialText(_ text: String) {
        guard state == .recording else {
            return
        }

        transcript = text
        onTranscriptChange?(text.trimmedNilIfEmpty)
    }

    private func handleRecognitionFinish(_ result: Result<String, Error>) {
        guard state == .recording else {
            return
        }

        guard hasRequestedStop else {
            pendingRecognitionResult = result

            if let resolvedTranscript = resolvedTranscript(from: result) {
                transcript = resolvedTranscript
                onTranscriptChange?(resolvedTranscript)
            }
            return
        }

        processRecognitionFinish(result)
    }

    private func processRecognitionFinish(_ result: Result<String, Error>) {
        guard state == .recording else {
            return
        }

        pendingRecognitionResult = nil
        let resolvedTranscript = resolvedTranscript(from: result)

        let shouldRefine = settingsStore.isLLMRefinementEnabled && settingsStore.llmConfiguration.isComplete
        state = SpeechSessionState.nextState(
            current: state,
            event: .recognitionFinished(hasTranscript: resolvedTranscript != nil, shouldRefine: shouldRefine)
        )

        guard let resolvedTranscript else {
            transcript = ""
            hasRequestedStop = false
            onTranscriptChange?(nil)
            switch result {
            case .success:
                showTerminalStatus("未识别到内容")
            case .failure:
                showTerminalStatus("语音识别不可用")
            }
            return
        }

        transcript = resolvedTranscript
        if state == .refining {
            beginRefinement(for: resolvedTranscript)
        } else {
            performInjection(with: resolvedTranscript)
        }
    }

    private func beginRefinement(for transcript: String) {
        onTranscriptChange?(nil)
        onStatusTextChange?("Refining...")

        let config = settingsStore.llmConfiguration
        Task { [weak self] in
            guard let self else {
                return
            }

            let refinedText: String
            do {
                refinedText = try await llmRefiner.refine(transcript: transcript, config: config)
            } catch {
                logger("Refinement failed: \(error)")
                refinedText = transcript
            }
            sessionDispatcher { [weak self] in
                self?.completeRefinement(with: refinedText)
            }
        }
    }

    private func completeRefinement(with text: String) {
        guard state == .refining else {
            return
        }

        state = SpeechSessionState.nextState(current: state, event: .refinementFinished)
        performInjection(with: text)
    }

    private func performInjection(with text: String) {
        guard state == .injecting else {
            return
        }

        textInjector.inject(text)
        state = SpeechSessionState.nextState(current: state, event: .injectionFinished)
        finishSession()
    }

    private func resolvedTranscript(from result: Result<String, Error>) -> String? {
        switch result {
        case let .success(text):
            return text.trimmedNilIfEmpty ?? transcript.trimmedNilIfEmpty
        case .failure:
            return transcript.trimmedNilIfEmpty
        }
    }

    private func finishSession() {
        cancelPendingHUDHide()
        hasRequestedStop = false
        pendingRecognitionResult = nil
        onLevelChange?(0)
        onHUDVisibilityChange?(false)
    }

    private func failSession() {
        cancelPendingHUDHide()
        audioCaptureEngine.stop()
        speechRecognizerService.stop()
        transcript = ""
        hasRequestedStop = false
        pendingRecognitionResult = nil
        state = SpeechSessionState.nextState(current: state, event: .failed)
        onTranscriptChange?(nil)
        onLevelChange?(0)
        onHUDVisibilityChange?(false)
    }

    private func showTerminalStatus(_ message: String) {
        onStatusTextChange?(message)
        onLevelChange?(0)
        scheduleHUDHide()
    }

    private func scheduleHUDHide() {
        hudDismissGeneration &+= 1
        let generation = hudDismissGeneration
        delayedScheduler(statusMessageDuration) { [weak self] in
            guard let self, self.hudDismissGeneration == generation else {
                return
            }

            self.onHUDVisibilityChange?(false)
        }
    }

    private func cancelPendingHUDHide() {
        hudDismissGeneration &+= 1
    }

    private static func makeDefaultLevelProcessor() -> LevelProcessor {
        var meter = AudioLevelMeter()
        return { buffer in
            meter.process(buffer: buffer)
        }
    }

    private static func makeDefaultDelayedScheduler(
        delay: TimeInterval,
        operation: @escaping @Sendable () -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: operation)
    }

    private static func makeDefaultLogger(_ message: String) {
        NSLog("%@", message)
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
