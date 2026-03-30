import AVFoundation
import Foundation
import Speech

public final class SpeechRecognizerService {
    public enum Error: Swift.Error, Equatable {
        case recognizerUnavailable
        case alreadyRunning
    }

    public final class ScheduledFallback: @unchecked Sendable {
        private let cancelHandler: @Sendable () -> Void

        public init(cancel: @escaping @Sendable () -> Void) {
            cancelHandler = cancel
        }

        public func cancel() {
            cancelHandler()
        }
    }

    struct RecognitionBackend {
        let isAvailable: Bool
        let startTask: @Sendable (
            SFSpeechAudioBufferRecognitionRequest,
            @escaping (SFSpeechRecognitionResult?, Swift.Error?) -> Void
        ) -> SFSpeechRecognitionTask

        init(
            isAvailable: Bool,
            startTask: @escaping @Sendable (
                SFSpeechAudioBufferRecognitionRequest,
                @escaping (SFSpeechRecognitionResult?, Swift.Error?) -> Void
            ) -> SFSpeechRecognitionTask
        ) {
            self.isAvailable = isAvailable
            self.startTask = startTask
        }
    }

    typealias FallbackScheduler = @Sendable (TimeInterval, @escaping @Sendable () -> Void) -> ScheduledFallback
    typealias CallbackDispatcher = @Sendable (@escaping @Sendable () -> Void) -> Void
    typealias RecognizerProvider = @Sendable (String) throws -> RecognitionBackend

    public var onPartialText: ((String) -> Void)?
    public var onFinish: ((Result<String, Swift.Error>) -> Void)?

    private let fallbackDelay: TimeInterval
    private let fallbackScheduler: FallbackScheduler
    private let callbackDispatcher: CallbackDispatcher
    private let recognizerProvider: RecognizerProvider
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latestText = ""
    private var isSessionActive = false
    private var isStopping = false
    private var hasCompleted = false
    private var activeSessionID: UInt64?
    private var latestStartedSessionID: UInt64 = 0
    private var nextSessionID: UInt64 = 0
    private var scheduledFallback: ScheduledFallback?
    private static let defaultFallbackScheduler: FallbackScheduler = { delay, operation in
        let workItem = DispatchWorkItem(block: operation)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        return ScheduledFallback(cancel: {
            workItem.cancel()
        })
    }
    private static let defaultCallbackDispatcher: CallbackDispatcher = { operation in
        DispatchQueue.main.async(execute: operation)
    }
    private static let defaultRecognizerProvider: RecognizerProvider = { localeIdentifier in
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) else {
            throw Error.recognizerUnavailable
        }

        return RecognitionBackend(
            isAvailable: recognizer.isAvailable,
            startTask: { request, handler in
                recognizer.recognitionTask(with: request, resultHandler: handler)
            }
        )
    }

    public convenience init() {
        self.init(
            fallbackDelay: 0.2,
            fallbackScheduler: Self.defaultFallbackScheduler,
            callbackDispatcher: Self.defaultCallbackDispatcher,
            recognizerProvider: Self.defaultRecognizerProvider
        )
    }

    convenience init(
        fallbackDelay: TimeInterval,
        fallbackScheduler: @escaping FallbackScheduler,
        callbackDispatcher: @escaping CallbackDispatcher
    ) {
        self.init(
            fallbackDelay: fallbackDelay,
            fallbackScheduler: fallbackScheduler,
            callbackDispatcher: callbackDispatcher,
            recognizerProvider: Self.defaultRecognizerProvider
        )
    }

    convenience init(callbackDispatcher: @escaping CallbackDispatcher) {
        self.init(
            fallbackDelay: 0.2,
            fallbackScheduler: Self.defaultFallbackScheduler,
            callbackDispatcher: callbackDispatcher,
            recognizerProvider: Self.defaultRecognizerProvider
        )
    }

    convenience init(
        fallbackDelay: TimeInterval = 0.2,
        callbackDispatcher: @escaping CallbackDispatcher,
        recognizerProvider: @escaping RecognizerProvider
    ) {
        self.init(
            fallbackDelay: fallbackDelay,
            fallbackScheduler: Self.defaultFallbackScheduler,
            callbackDispatcher: callbackDispatcher,
            recognizerProvider: recognizerProvider
        )
    }

    convenience init(
        callbackDispatcher: @escaping CallbackDispatcher,
        recognizerProvider: @escaping RecognizerProvider
    ) {
        self.init(
            fallbackDelay: 0.2,
            fallbackScheduler: Self.defaultFallbackScheduler,
            callbackDispatcher: callbackDispatcher,
            recognizerProvider: recognizerProvider
        )
    }

    init(
        fallbackDelay: TimeInterval,
        fallbackScheduler: @escaping FallbackScheduler,
        callbackDispatcher: @escaping CallbackDispatcher,
        recognizerProvider: @escaping RecognizerProvider
    ) {
        self.fallbackDelay = fallbackDelay
        self.fallbackScheduler = fallbackScheduler
        self.callbackDispatcher = callbackDispatcher
        self.recognizerProvider = recognizerProvider
    }

    public func start(localeIdentifier: String) throws {
        guard task == nil, request == nil else {
            throw Error.alreadyRunning
        }

        let backend = try recognizerProvider(localeIdentifier)
        guard backend.isAvailable else {
            throw Error.recognizerUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        let sessionID = beginSession()

        self.request = request

        task = backend.startTask(request) { [weak self] result, error in
            self?.handleRecognition(result: result, error: error, sessionID: sessionID)
        }
    }

    public func append(buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    public func stop() {
        guard let sessionID = activeSessionID, isSessionActive else {
            return
        }

        isStopping = true
        request?.endAudio()
        task?.finish()
        scheduleFallbackCompletionIfNeeded(sessionID: sessionID)
    }

    public func cancel() {
        task?.cancel()
        latestStartedSessionID &+= 1
        reset()
    }

    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Swift.Error?, sessionID: UInt64) {
        guard activeSessionID == sessionID, isSessionActive else {
            return
        }

        if let result {
            latestText = result.bestTranscription.formattedString
            dispatchCallback(for: sessionID) { [weak self] in
                self?.onPartialText?(result.bestTranscription.formattedString)
            }

            if result.isFinal {
                complete(with: .success(latestText), sessionID: sessionID)
            }
        }

        if let error {
            if latestText.isEmpty {
                complete(with: .failure(error), sessionID: sessionID)
            } else {
                complete(with: .success(latestText), sessionID: sessionID)
            }
        }
    }

    private func complete(with result: Result<String, Swift.Error>, sessionID: UInt64) {
        guard activeSessionID == sessionID, !hasCompleted else {
            return
        }

        hasCompleted = true
        scheduledFallback?.cancel()
        scheduledFallback = nil
        dispatchCallback(for: sessionID) { [weak self] in
            self?.onFinish?(result)
        }
        reset()
    }

    private func reset() {
        scheduledFallback?.cancel()
        scheduledFallback = nil
        task = nil
        request = nil
        isSessionActive = false
        isStopping = false
        activeSessionID = nil
    }

    private func scheduleFallbackCompletionIfNeeded(sessionID: UInt64) {
        scheduledFallback?.cancel()
        scheduledFallback = fallbackScheduler(fallbackDelay) { [weak self] in
            guard
                let self,
                self.activeSessionID == sessionID,
                self.isStopping,
                !self.hasCompleted
            else {
                return
            }

            self.complete(with: .success(self.latestText), sessionID: sessionID)
        }
    }

    private func beginSession() -> UInt64 {
        nextSessionID &+= 1
        latestText = ""
        isSessionActive = true
        isStopping = false
        hasCompleted = false
        activeSessionID = nextSessionID
        latestStartedSessionID = nextSessionID
        scheduledFallback?.cancel()
        scheduledFallback = nil
        return nextSessionID
    }

    private func dispatchCallback(for sessionID: UInt64, _ operation: @escaping @Sendable () -> Void) {
        callbackDispatcher { [weak self] in
            guard let self, self.latestStartedSessionID == sessionID else {
                return
            }

            operation()
        }
    }

    @discardableResult
    func testingBeginSession() -> UInt64 {
        beginSession()
    }

    func testingReceiveRecognitionResult(text: String, isFinal: Bool, sessionID: UInt64) {
        guard activeSessionID == sessionID, isSessionActive else {
            return
        }

        latestText = text
        dispatchCallback(for: sessionID) { [weak self] in
            self?.onPartialText?(text)
        }

        if isFinal {
            complete(with: .success(text), sessionID: sessionID)
        }
    }

    func testingReceiveRecognitionError(_ error: Swift.Error, sessionID: UInt64) {
        guard activeSessionID == sessionID, isSessionActive else {
            return
        }

        if latestText.isEmpty {
            complete(with: .failure(error), sessionID: sessionID)
        } else {
            complete(with: .success(latestText), sessionID: sessionID)
        }
    }

    func testingActivateSession(latestText: String) {
        _ = beginSession()
        self.latestText = latestText
    }
}
