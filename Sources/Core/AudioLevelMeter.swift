import AVFoundation
import Foundation

public struct AudioLevelMeter {
    private var currentLevel: CGFloat = 0
    private let attack: CGFloat
    private let release: CGFloat
    private let floorLevel: CGFloat
    private let gain: CGFloat

    public init(
        attack: CGFloat = 0.4,
        release: CGFloat = 0.15,
        floorLevel: CGFloat = 0.02,
        gain: CGFloat = 6.0
    ) {
        self.attack = attack
        self.release = release
        self.floorLevel = floorLevel
        self.gain = gain
    }

    public mutating func smoothedLevel(nextRawLevel: CGFloat) -> CGFloat {
        let clampedLevel = nextRawLevel.clamped(to: 0 ... 1)
        let coefficient = clampedLevel > currentLevel ? attack : release
        currentLevel += (clampedLevel - currentLevel) * coefficient
        return currentLevel
    }

    public mutating func process(buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let channelData = buffer.floatChannelData else {
            return currentLevel
        }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else {
            return currentLevel
        }

        var squaredSum: Float = 0

        for channelIndex in 0 ..< channelCount {
            let samples = channelData[channelIndex]
            for frameIndex in 0 ..< frameCount {
                let sample = samples[frameIndex]
                squaredSum += sample * sample
            }
        }

        let sampleCount = Float(frameCount * channelCount)
        let rms = sqrt(squaredSum / sampleCount)
        let normalized = CGFloat(rms) * gain
        return smoothedLevel(nextRawLevel: max(floorLevel, normalized))
    }
}

public enum WaveformHeightMapper {
    private static let minimumHeight: CGFloat = 6
    private static let maximumHeight: CGFloat = 30
    private static let weights: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.55]
    private static let jitterScale: CGFloat = 0.08

    public static func makeHeights(for level: CGFloat, jitterSeed: UInt64) -> [CGFloat] {
        let clampedLevel = level.clamped(to: 0 ... 1)

        return weights.enumerated().map { index, weight in
            let jitter = pseudoRandom(seed: jitterSeed &+ UInt64(index)) * jitterScale - (jitterScale / 2)
            let adjusted = (clampedLevel * weight * (1 + jitter)).clamped(to: 0 ... 1)
            return minimumHeight + ((maximumHeight - minimumHeight) * adjusted)
        }
    }

    private static func pseudoRandom(seed: UInt64) -> CGFloat {
        let value = (1_103_515_245 &* seed &+ 12_345) % 10_000
        return CGFloat(value) / 10_000
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
