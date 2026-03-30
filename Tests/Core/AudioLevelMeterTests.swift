import AVFoundation
import Testing
@testable import VoiceInputCore

private final class SpeechRecognizerFallbackProbe: @unchecked Sendable {
    var operation: (() -> Void)?
}

private final class CallbackDispatchProbe: @unchecked Sendable {
    var queuedWork: [() -> Void] = []
    var partialTexts: [String] = []
    var finishResults: [Result<String, Swift.Error>] = []
}

private final class AudioCaptureProbe: @unchecked Sendable {
    var queuedWork: [() -> Void] = []
    var receivedFirstSamples: [Float] = []
}

struct AudioLevelMeterTests {
    @Test func attackRisesFasterThanReleaseFalls() {
        var meter = AudioLevelMeter()

        let rise = meter.smoothedLevel(nextRawLevel: 1.0)
        let drop = meter.smoothedLevel(nextRawLevel: 0.0)

        #expect(rise > 0.35)
        #expect(drop > 0.0)
        #expect(drop < rise)
    }

    @Test func waveformHeightsRespectFiveBarWeights() {
        let heights = WaveformHeightMapper.makeHeights(for: 0.8, jitterSeed: 0)

        #expect(heights.count == 5)
        #expect(heights[2] > heights[0])
        #expect(heights[2] > heights[4])
    }

    @Test func processUsesAllChannelsForRMSMetering() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4)!
        buffer.frameLength = 4

        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]

        for index in 0 ..< Int(buffer.frameLength) {
            left[index] = 0
            right[index] = 1
        }

        var meter = AudioLevelMeter()
        let level = meter.process(buffer: buffer)

        #expect(level > 0.3)
    }

    @Test func speechRecognizerStopFallsBackToLatestPartialWhenNoFinalCallbackArrives() throws {
        let probe = SpeechRecognizerFallbackProbe()
        let service = SpeechRecognizerService(
            fallbackDelay: 0.1,
            fallbackScheduler: { _, operation in
                probe.operation = operation
                return SpeechRecognizerService.ScheduledFallback(cancel: {})
            },
            callbackDispatcher: { $0() }
        )
        var finishedResult: Result<String, Swift.Error>?

        service.onFinish = { result in
            finishedResult = result
        }

        service.testingActivateSession(latestText: "你好，世界")
        service.stop()

        #expect(finishedResult == nil)
        #expect(probe.operation != nil)

        probe.operation?()

        switch finishedResult {
        case let .success(text)?:
            #expect(text == "你好，世界")
        default:
            Issue.record("expected fallback stop result to succeed with the latest partial transcript")
        }
    }

    @Test func speechRecognizerIgnoresLateCallbacksFromOldSession() throws {
        let service = SpeechRecognizerService(callbackDispatcher: { $0() })
        var partialTexts: [String] = []
        var finishedResults: [Result<String, Swift.Error>] = []

        service.onPartialText = { partialTexts.append($0) }
        service.onFinish = { finishedResults.append($0) }

        let oldSession = service.testingBeginSession()
        let newSession = service.testingBeginSession()

        service.testingReceiveRecognitionResult(text: "old", isFinal: false, sessionID: oldSession)
        service.testingReceiveRecognitionResult(text: "new", isFinal: false, sessionID: newSession)
        service.testingReceiveRecognitionError(TestError.marker, sessionID: oldSession)
        service.testingReceiveRecognitionResult(text: "final", isFinal: true, sessionID: newSession)

        #expect(partialTexts == ["new", "final"])
        #expect(finishedResults.count == 1)

        switch finishedResults.first {
        case let .success(text)?:
            #expect(text == "final")
        default:
            Issue.record("expected only the active session to complete")
        }
    }

    @Test func speechRecognizerDispatchesCallbacksThroughInjectedDispatcher() throws {
        let probe = CallbackDispatchProbe()
        let service = SpeechRecognizerService(
            callbackDispatcher: { work in
                probe.queuedWork.append(work)
            }
        )

        service.onPartialText = { probe.partialTexts.append($0) }
        service.onFinish = { probe.finishResults.append($0) }

        let sessionID = service.testingBeginSession()
        service.testingReceiveRecognitionResult(text: "queued", isFinal: true, sessionID: sessionID)

        #expect(probe.partialTexts.isEmpty)
        #expect(probe.finishResults.isEmpty)
        #expect(probe.queuedWork.count == 2)

        let work = probe.queuedWork
        probe.queuedWork.removeAll()
        work.forEach { $0() }

        #expect(probe.partialTexts == ["queued"])
        #expect(probe.finishResults.count == 1)
    }

    @Test func speechRecognizerDropsQueuedCallbacksAfterSessionChanges() throws {
        let probe = CallbackDispatchProbe()
        let service = SpeechRecognizerService(
            callbackDispatcher: { work in
                probe.queuedWork.append(work)
            }
        )

        service.onPartialText = { probe.partialTexts.append($0) }
        service.onFinish = { probe.finishResults.append($0) }

        let oldSession = service.testingBeginSession()
        service.testingReceiveRecognitionResult(text: "old-final", isFinal: true, sessionID: oldSession)

        #expect(probe.queuedWork.count == 2)

        let newSession = service.testingBeginSession()
        service.testingReceiveRecognitionResult(text: "new", isFinal: false, sessionID: newSession)

        let work = probe.queuedWork
        probe.queuedWork.removeAll()
        work.forEach { $0() }

        #expect(probe.partialTexts == ["new"])
        #expect(probe.finishResults.isEmpty)
    }

    @Test func audioCaptureEngineDispatchesCopiedBuffersOffTapPath() throws {
        let probe = AudioCaptureProbe()
        let engine = AudioCaptureEngine(
            bufferDispatcher: { work in
                probe.queuedWork.append(work)
            }
        )
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2)!
        buffer.frameLength = 2
        buffer.floatChannelData![0][0] = 0.25
        buffer.floatChannelData![0][1] = 0.75

        engine.onBuffer = { deliveredBuffer in
            probe.receivedFirstSamples.append(deliveredBuffer.floatChannelData![0][0])
        }

        engine.testingActivateRunningState()
        engine.testingHandleTap(buffer)

        #expect(probe.receivedFirstSamples.isEmpty)
        #expect(probe.queuedWork.count == 1)

        buffer.floatChannelData![0][0] = 1.0
        let work = probe.queuedWork
        probe.queuedWork.removeAll()
        work.forEach { $0() }

        #expect(probe.receivedFirstSamples == [0.25])
    }

    @Test func audioCaptureEngineDropsQueuedBuffersAfterStop() throws {
        let probe = AudioCaptureProbe()
        let engine = AudioCaptureEngine(
            bufferDispatcher: { work in
                probe.queuedWork.append(work)
            }
        )
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
        buffer.frameLength = 1
        buffer.floatChannelData![0][0] = 0.5

        engine.onBuffer = { deliveredBuffer in
            probe.receivedFirstSamples.append(deliveredBuffer.floatChannelData![0][0])
        }

        engine.testingActivateRunningState()
        engine.testingHandleTap(buffer)
        engine.stop()

        let work = probe.queuedWork
        probe.queuedWork.removeAll()
        work.forEach { $0() }

        #expect(probe.receivedFirstSamples.isEmpty)
    }

    @Test func speechRecognizerStartFailsWhenRecognizerIsUnavailable() {
        let service = SpeechRecognizerService(
            callbackDispatcher: { $0() },
            recognizerProvider: { _ in
                throw SpeechRecognizerService.Error.recognizerUnavailable
            }
        )

        #expect(throws: SpeechRecognizerService.Error.recognizerUnavailable) {
            try service.start(localeIdentifier: "zh-CN")
        }
    }

    @Test func speechRecognizerCancelDropsQueuedCallbacksForCurrentSession() {
        let probe = CallbackDispatchProbe()
        let service = SpeechRecognizerService(
            callbackDispatcher: { work in
                probe.queuedWork.append(work)
            }
        )

        service.onPartialText = { probe.partialTexts.append($0) }
        service.onFinish = { probe.finishResults.append($0) }

        let sessionID = service.testingBeginSession()
        service.testingReceiveRecognitionResult(text: "queued", isFinal: true, sessionID: sessionID)
        service.cancel()

        let work = probe.queuedWork
        probe.queuedWork.removeAll()
        work.forEach { $0() }

        #expect(probe.partialTexts.isEmpty)
        #expect(probe.finishResults.isEmpty)
    }
}

private enum TestError: Swift.Error, Equatable {
    case marker
}
