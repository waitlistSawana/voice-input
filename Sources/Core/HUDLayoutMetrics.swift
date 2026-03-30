import CoreGraphics

public struct HUDLayoutMetrics {
    public struct Layout: Equatable, Sendable {
        public let size: CGSize
        public let waveformFrame: CGRect
        public let labelFrame: CGRect

        public init(size: CGSize, waveformFrame: CGRect, labelFrame: CGRect) {
            self.size = size
            self.waveformFrame = waveformFrame
            self.labelFrame = labelFrame
        }
    }

    public let fixedHeight: CGFloat = 56
    public let minimumWidth: CGFloat = 160
    public let maximumWidth: CGFloat = 560
    public let waveformSize = CGSize(width: 44, height: 32)
    public let horizontalPadding: CGFloat = 12
    public let interItemSpacing: CGFloat = 10
    public let bottomInset: CGFloat = 24

    public init() {}

    public func clampedWidth(for desiredWidth: CGFloat) -> CGFloat {
        min(max(desiredWidth, minimumWidth), maximumWidth)
    }

    public func layout(for desiredWidth: CGFloat) -> Layout {
        let width = clampedWidth(for: desiredWidth)
        let waveformOriginY = (fixedHeight - waveformSize.height) / 2
        let waveformFrame = CGRect(
            x: horizontalPadding,
            y: waveformOriginY,
            width: waveformSize.width,
            height: waveformSize.height
        )

        let labelOriginX = waveformFrame.maxX + interItemSpacing
        let labelFrame = CGRect(
            x: labelOriginX,
            y: 0,
            width: max(0, width - labelOriginX - horizontalPadding),
            height: fixedHeight
        )

        return Layout(
            size: CGSize(width: width, height: fixedHeight),
            waveformFrame: waveformFrame,
            labelFrame: labelFrame
        )
    }

    public func frame(for desiredWidth: CGFloat, in visibleFrame: CGRect) -> CGRect {
        let width = clampedWidth(for: desiredWidth)
        return CGRect(
            x: visibleFrame.midX - (width / 2),
            y: visibleFrame.minY + bottomInset,
            width: width,
            height: fixedHeight
        )
    }

    public func resizedFrame(for desiredWidth: CGFloat, anchoredTo currentFrame: CGRect) -> CGRect {
        let width = clampedWidth(for: desiredWidth)
        return CGRect(
            x: currentFrame.midX - (width / 2),
            y: currentFrame.minY,
            width: width,
            height: fixedHeight
        )
    }
}
