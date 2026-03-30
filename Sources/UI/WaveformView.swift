import AppKit
import QuartzCore
import VoiceInputCore

@MainActor
public final class WaveformView: NSView {
    private let barWidth: CGFloat = 4
    private let barSpacing: CGFloat = 4
    private let renderInterval: TimeInterval = 1.0 / 60.0
    private let maxInterpolationStep: CGFloat = 0.2
    private let barLayers: [CALayer]
    private var displayLinkTimer: Timer?
    private var renderedLevel: CGFloat = 0
    private var targetLevel: CGFloat = 0

    public var level: CGFloat {
        get { targetLevel }
        set {
            targetLevel = newValue.clamped(to: 0 ... 1)
            startRendererIfNeeded()
            renderFrame()
        }
    }

    public var jitterSeed: UInt64 = 0 {
        didSet {
            startRendererIfNeeded()
            renderFrame()
        }
    }

    public override var isFlipped: Bool { true }
    public override var intrinsicContentSize: NSSize { NSSize(width: 44, height: 32) }
    public override var isOpaque: Bool { false }

    public init(frame frameRect: NSRect = .zero, jitterSeed: UInt64 = 0) {
        self.jitterSeed = jitterSeed
        self.barLayers = (0 ..< 5).map { _ in CALayer() }
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false
        configureBarLayers()
        renderFrame()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        displayLinkTimer?.invalidate()
    }

    public func update(level: CGFloat, jitterSeed: UInt64? = nil) {
        if let jitterSeed {
            self.jitterSeed = jitterSeed
        }
        self.level = level
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopRenderer()
        } else {
            resumeRendererIfNeeded()
        }
    }

    public override func layout() {
        super.layout()
        renderFrame()
    }

    private func configureBarLayers() {
        guard let backingLayer = layer else {
            return
        }

        for barLayer in barLayers {
            barLayer.backgroundColor = NSColor.labelColor.cgColor
            barLayer.cornerRadius = barWidth / 2
            barLayer.masksToBounds = true
            backingLayer.addSublayer(barLayer)
        }
    }

    func startRendererIfNeeded() {
        guard window == nil || window?.isVisible == true else {
            return
        }
        guard displayLinkTimer == nil else {
            return
        }

        let timer = Timer(timeInterval: renderInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickRenderer()
            }
        }
        displayLinkTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func resumeRendererIfNeeded() {
        guard targetLevel != renderedLevel else {
            return
        }
        startRendererIfNeeded()
    }

    func stopRenderer() {
        displayLinkTimer?.invalidate()
        displayLinkTimer = nil
    }

    var testingIsRendererRunning: Bool {
        displayLinkTimer != nil
    }

    func testingAdvanceRenderer() {
        tickRenderer()
    }

    private func tickRenderer() {
        let delta = targetLevel - renderedLevel
        if abs(delta) < 0.001 {
            renderedLevel = targetLevel
            renderFrame()
            stopRenderer()
            return
        } else {
            renderedLevel += delta * maxInterpolationStep
        }
        renderFrame()
    }

    private func renderFrame() {
        guard let backingLayer = layer else {
            return
        }

        backingLayer.frame = bounds
        let heights = WaveformHeightMapper.makeHeights(for: renderedLevel, jitterSeed: jitterSeed)
        let totalWidth = (barWidth * CGFloat(heights.count)) + (barSpacing * CGFloat(max(0, heights.count - 1)))
        let startingX = max(0, (bounds.width - totalWidth) / 2)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, height) in heights.enumerated() {
            let x = startingX + (CGFloat(index) * (barWidth + barSpacing))
            let y = bounds.height - height
            barLayers[index].frame = CGRect(x: x, y: y, width: barWidth, height: height)
        }
        CATransaction.commit()
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
