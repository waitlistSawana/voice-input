import AVFoundation
import Foundation

public final class AudioCaptureEngine {
    public enum Error: Swift.Error, Equatable {
        case inputNodeUnavailable
        case alreadyRunning
    }

    typealias BufferDispatcher = @Sendable (@escaping @Sendable () -> Void) -> Void

    public var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    private let engine: AVAudioEngine
    private let bus: AVAudioNodeBus
    private let bufferSize: AVAudioFrameCount
    private let bufferDispatcher: BufferDispatcher
    private var isRunning = false
    private var hasInstalledTap = false
    private var runGeneration: UInt64 = 0
    private static let defaultBufferDispatcher: BufferDispatcher = { operation in
        DispatchQueue.main.async(execute: operation)
    }

    public convenience init(
        engine: AVAudioEngine = AVAudioEngine(),
        bus: AVAudioNodeBus = 0,
        bufferSize: AVAudioFrameCount = 1024
    ) {
        self.init(
            engine: engine,
            bus: bus,
            bufferSize: bufferSize,
            bufferDispatcher: Self.defaultBufferDispatcher
        )
    }

    init(
        engine: AVAudioEngine = AVAudioEngine(),
        bus: AVAudioNodeBus = 0,
        bufferSize: AVAudioFrameCount = 1024,
        bufferDispatcher: @escaping BufferDispatcher
    ) {
        self.engine = engine
        self.bus = bus
        self.bufferSize = bufferSize
        self.bufferDispatcher = bufferDispatcher
    }

    public func start() throws {
        guard !isRunning else {
            throw Error.alreadyRunning
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: bus)
        guard format.channelCount > 0 else {
            throw Error.inputNodeUnavailable
        }

        engine.stop()
        inputNode.removeTap(onBus: bus)
        runGeneration &+= 1
        let generation = runGeneration
        inputNode.installTap(onBus: bus, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            self?.handleTapBuffer(buffer, generation: generation)
        }
        hasInstalledTap = true

        try engine.start()
        isRunning = true
    }

    public func stop() {
        if hasInstalledTap {
            engine.inputNode.removeTap(onBus: bus)
            hasInstalledTap = false
        }
        engine.stop()
        isRunning = false
        runGeneration &+= 1
    }

    func testingHandleTap(_ buffer: AVAudioPCMBuffer) {
        handleTapBuffer(buffer, generation: runGeneration)
    }

    func testingActivateRunningState() {
        isRunning = true
        runGeneration &+= 1
    }

    private func handleTapBuffer(_ buffer: AVAudioPCMBuffer, generation: UInt64) {
        guard let copiedBuffer = Self.copy(buffer: buffer) else {
            return
        }

        bufferDispatcher { [weak self] in
            guard let self, self.isRunning, self.runGeneration == generation else {
                return
            }

            self.onBuffer?(copiedBuffer)
        }
    }

    private static func copy(buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copiedBuffer = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity) else {
            return nil
        }

        copiedBuffer.frameLength = buffer.frameLength

        let sourceBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(copiedBuffer.mutableAudioBufferList)
        guard sourceBuffers.count == destinationBuffers.count else {
            return nil
        }

        for index in 0 ..< sourceBuffers.count {
            guard
                let sourceData = sourceBuffers[index].mData,
                let destinationData = destinationBuffers[index].mData
            else {
                continue
            }

            memcpy(destinationData, sourceData, Int(sourceBuffers[index].mDataByteSize))
            destinationBuffers[index].mDataByteSize = sourceBuffers[index].mDataByteSize
        }

        return copiedBuffer
    }
}
