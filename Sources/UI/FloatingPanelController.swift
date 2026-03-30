import AppKit
import QuartzCore
import VoiceInputCore

@MainActor
public final class FloatingPanelController: NSWindowController {
    public static let defaultStatusText = "请讲话"
    static let animationScale: CGFloat = 0.96
    private static let resizeAnimationThrottle: TimeInterval = 0.12

    let metrics: HUDLayoutMetrics
    private let waveformView = WaveformView()
    private let messageLabel = NSTextField(labelWithString: "")
    private let rootView = NSVisualEffectView()
    private let visibleFrameProvider: () -> CGRect
    private let timeProvider: () -> TimeInterval
    private var transcriptText: String?
    private var statusText: String
    private var hasShownPanel = false
    private var isExiting = false
    private var transitionGeneration = 0
    private var lastAnimatedResizeAt: TimeInterval?

    var testingEnterAnimationCount = 0
    var testingAnimatedResizeCount = 0

    public init(
        metrics: HUDLayoutMetrics = HUDLayoutMetrics(),
        timeProvider: @escaping () -> TimeInterval = CACurrentMediaTime,
        visibleFrameProvider: @escaping () -> CGRect = {
            NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 560, height: 56)
        }
    ) {
        self.metrics = metrics
        self.timeProvider = timeProvider
        self.visibleFrameProvider = visibleFrameProvider
        self.statusText = Self.defaultStatusText

        let layout = metrics.layout(for: 280)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: layout.size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = rootView

        super.init(window: panel)
        configureContentView(with: layout)
        refreshMessageLabel()
        updateWindowFrameIfNeeded(animate: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func show() {
        transitionGeneration &+= 1
        updateWindowFrameIfNeeded(animate: false)
        isExiting = false

        guard let window else {
            return
        }

        if hasShownPanel, window.isVisible {
            window.orderFrontRegardless()
            waveformView.resumeRendererIfNeeded()
            return
        }

        applyHUDVisibility(alpha: 0, scale: Self.animationScale)
        window.orderFrontRegardless()
        testingEnterAnimationCount &+= 1
        animateHUDVisibility(
            alpha: 1,
            scale: 1,
            duration: HUDAnimationDurations.enter
        )
        hasShownPanel = true
        waveformView.resumeRendererIfNeeded()
    }

    public func updateTranscript(_ text: String?) {
        transcriptText = text?.nilIfEmpty
        refreshMessageLabel()
        updateWindowFrameIfNeeded(animate: true)
    }

    public func updateStatus(_ text: String) {
        statusText = text
        refreshMessageLabel()
        updateWindowFrameIfNeeded(animate: true)
    }

    public func updateLevel(_ level: CGFloat, jitterSeed: UInt64 = 0) {
        waveformView.update(level: level, jitterSeed: jitterSeed)
    }

    public func hide() {
        waveformView.stopRenderer()
        guard let window else {
            return
        }

        guard window.isVisible else {
            window.orderOut(nil)
            return
        }

        isExiting = true
        transitionGeneration &+= 1
        let generation = transitionGeneration

        animateHUDVisibility(
            alpha: 0,
            scale: Self.animationScale,
            duration: HUDAnimationDurations.exit
        ) { [generation, window] in
            DispatchQueue.main.async { [weak self, generation, window] in
                guard let self, self.transitionGeneration == generation else {
                    return
                }

                self.isExiting = false
                window.orderOut(nil)
                self.applyHUDVisibility(alpha: 1, scale: 1)
            }
        }
    }

    var testingIsWaveformRendering: Bool {
        waveformView.testingIsRendererRunning
    }

    var testingMetrics: HUDLayoutMetrics {
        metrics
    }

    func testingAdvanceWaveformRenderer() {
        waveformView.testingAdvanceRenderer()
    }

    private func configureContentView(with layout: HUDLayoutMetrics.Layout) {
        rootView.material = .hudWindow
        rootView.blendingMode = .withinWindow
        rootView.state = .active
        rootView.wantsLayer = true
        rootView.frame = NSRect(origin: .zero, size: layout.size)
        rootView.autoresizingMask = [.width, .height]
        rootView.layer?.cornerRadius = 28
        rootView.layer?.masksToBounds = true

        let horizontalStack = NSStackView()
        horizontalStack.orientation = .horizontal
        horizontalStack.alignment = .centerY
        horizontalStack.distribution = .fill
        horizontalStack.spacing = metrics.interItemSpacing
        horizontalStack.translatesAutoresizingMaskIntoConstraints = false
        horizontalStack.edgeInsets = NSEdgeInsets(
            top: (metrics.fixedHeight - metrics.waveformSize.height) / 2,
            left: metrics.horizontalPadding,
            bottom: (metrics.fixedHeight - metrics.waveformSize.height) / 2,
            right: metrics.horizontalPadding
        )

        waveformView.translatesAutoresizingMaskIntoConstraints = false
        waveformView.widthAnchor.constraint(equalToConstant: metrics.waveformSize.width).isActive = true
        waveformView.heightAnchor.constraint(equalToConstant: metrics.waveformSize.height).isActive = true

        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.font = .systemFont(ofSize: 13, weight: .medium)
        messageLabel.textColor = .labelColor
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        messageLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        horizontalStack.addArrangedSubview(waveformView)
        horizontalStack.addArrangedSubview(messageLabel)
        rootView.addSubview(horizontalStack)

        NSLayoutConstraint.activate([
            horizontalStack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            horizontalStack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            horizontalStack.topAnchor.constraint(equalTo: rootView.topAnchor),
            horizontalStack.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])
    }

    private func refreshMessageLabel() {
        messageLabel.stringValue = transcriptText ?? statusText
    }

    private func applyHUDVisibility(alpha: CGFloat, scale: CGFloat) {
        guard let layer = rootView.layer else {
            return
        }

        layer.opacity = Float(alpha)
        layer.transform = Self.scaledTransform(scale)
    }

    private func animateHUDVisibility(
        alpha: CGFloat,
        scale: CGFloat,
        duration: TimeInterval,
        completion: (@MainActor @Sendable () -> Void)? = nil
    ) {
        guard let layer = rootView.layer else {
            completion?()
            return
        }

        let targetOpacity = Float(alpha)
        let targetTransform = Self.scaledTransform(scale)
        let fromOpacity = layer.presentation()?.opacity ?? layer.opacity
        let fromTransform = layer.presentation()?.transform ?? layer.transform

        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = fromOpacity
        opacityAnimation.toValue = targetOpacity
        opacityAnimation.duration = duration
        opacityAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        let transformAnimation = CABasicAnimation(keyPath: "transform")
        transformAnimation.fromValue = fromTransform
        transformAnimation.toValue = targetTransform
        transformAnimation.duration = duration
        transformAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        CATransaction.setCompletionBlock {
            completion?()
        }
        layer.opacity = targetOpacity
        layer.transform = targetTransform
        layer.add(opacityAnimation, forKey: "hudOpacity")
        layer.add(transformAnimation, forKey: "hudTransform")
        CATransaction.commit()
    }

    private static func scaledTransform(_ scale: CGFloat) -> CATransform3D {
        CATransform3DMakeScale(scale, scale, 1)
    }

    private func updateWindowFrameIfNeeded(animate: Bool) {
        guard let window else {
            return
        }

        let targetWidth = contentWidthForCurrentMessage()
        let frame: CGRect

        if hasShownPanel && window.isVisible && !isExiting {
            frame = metrics.resizedFrame(for: targetWidth, anchoredTo: window.frame)
        } else {
            let visibleFrame = visibleFrameProvider()
            frame = metrics.frame(for: targetWidth, in: visibleFrame)
        }

        if animate && shouldAnimateResize(for: window) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = HUDAnimationDurations.resize
                window.animator().setFrame(frame, display: true)
            }
        } else {
            window.setFrame(frame, display: true, animate: false)
        }
        rootView.frame = NSRect(origin: .zero, size: frame.size)
    }

    private func shouldAnimateResize(for window: NSWindow) -> Bool {
        guard hasShownPanel, window.isVisible, !isExiting else {
            return false
        }

        let now = timeProvider()
        if let lastAnimatedResizeAt, now - lastAnimatedResizeAt < Self.resizeAnimationThrottle {
            return false
        }

        lastAnimatedResizeAt = now
        testingAnimatedResizeCount &+= 1
        return true
    }

    private func contentWidthForCurrentMessage() -> CGFloat {
        let messageWidth = messageLabel.intrinsicContentSize.width
        let total = metrics.horizontalPadding
            + metrics.waveformSize.width
            + metrics.interItemSpacing
            + messageWidth
            + metrics.horizontalPadding
        return total
    }
}

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }
        return value
    }
}
