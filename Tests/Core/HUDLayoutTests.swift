import AppKit
import Foundation
import Testing
@testable import VoiceInputCore
@testable import VoiceInputUI

struct HUDLayoutTests {
    @Test func metricsClampWidthAndFixHeight() {
        let metrics = HUDLayoutMetrics()

        #expect(metrics.fixedHeight == 56)
        #expect(metrics.clampedWidth(for: 120) == 160)
        #expect(metrics.clampedWidth(for: 240) == 240)
        #expect(metrics.clampedWidth(for: 800) == 560)
    }

    @Test func metricsPlaceFiveBarWaveformInACompactHud() {
        let metrics = HUDLayoutMetrics()
        let layout = metrics.layout(for: 240)

        #expect(layout.size.height == 56)
        #expect(layout.waveformFrame.size == CGSize(width: 44, height: 32))
        #expect(layout.labelFrame.width > 0)
        #expect(layout.labelFrame.minX > layout.waveformFrame.maxX)
    }

    @Test func metricsAnchorHudToBottomCenter() {
        let metrics = HUDLayoutMetrics()
        let visibleFrame = CGRect(x: 100, y: 40, width: 800, height: 600)

        let initialFrame = metrics.frame(for: 240, in: visibleFrame)
        #expect(initialFrame.midX == visibleFrame.midX)
        #expect(initialFrame.minY == visibleFrame.minY + metrics.bottomInset)

        let resizedFrame = metrics.resizedFrame(for: 360, anchoredTo: initialFrame)
        #expect(resizedFrame.midX == initialFrame.midX)
        #expect(resizedFrame.minY == initialFrame.minY)
    }

    @MainActor
    @Test func waveformViewUsesFiveRoundedLayers() {
        let waveformView = WaveformView(frame: CGRect(x: 0, y: 0, width: 44, height: 32))

        #expect(waveformView.layer?.sublayers?.count == 5)
        #expect((waveformView.layer?.sublayers ?? []).allSatisfy { $0.cornerRadius > 0 })
    }

    @MainActor
    @Test func floatingPanelUsesFullSizeContentViewAndNonactivatingHudStyle() {
        let controller = FloatingPanelController()
        controller.loadWindow()
        controller.show()

        #expect(FloatingPanelController.defaultStatusText == "请讲话")
        #expect(controller.window?.styleMask.contains(.nonactivatingPanel) == true)
        #expect(controller.window?.styleMask.contains(.fullSizeContentView) == true)
        #expect(controller.window?.isFloatingPanel == true)
        #expect(controller.window?.contentView is NSVisualEffectView)
        #expect(controller.window?.isKeyWindow == false)
    }

    @MainActor
    @Test func floatingPanelReanchorsToTheCurrentVisibleFrameAfterHide() {
        var visibleFrame = CGRect(x: 100, y: 40, width: 800, height: 600)
        let controller = FloatingPanelController(visibleFrameProvider: { visibleFrame })
        controller.show()

        let initialFrame = controller.window!.frame
        #expect(initialFrame.midX == visibleFrame.midX)
        #expect(initialFrame.minY == visibleFrame.minY + controller.testingMetrics.bottomInset)

        controller.hide()
        visibleFrame = CGRect(x: 300, y: 80, width: 1000, height: 700)
        controller.show()

        let restoredFrame = controller.window!.frame
        #expect(restoredFrame.midX == visibleFrame.midX)
        #expect(restoredFrame.minY == visibleFrame.minY + controller.testingMetrics.bottomInset)
    }

    @MainActor
    @Test func floatingPanelDoesNotReplayEnterAnimationWhenAlreadyVisible() {
        var now: TimeInterval = 0
        let controller = FloatingPanelController(
            timeProvider: { now },
            visibleFrameProvider: {
                CGRect(x: 100, y: 40, width: 800, height: 600)
            }
        )

        controller.show()
        let enterCountAfterFirstShow = controller.testingEnterAnimationCount

        now = 0.01
        controller.show()

        #expect(controller.testingEnterAnimationCount == enterCountAfterFirstShow)
    }

    @MainActor
    @Test func floatingPanelThrottlesFrequentResizeAnimationsDuringStreaming() {
        var now: TimeInterval = 0
        let controller = FloatingPanelController(
            timeProvider: { now },
            visibleFrameProvider: {
                CGRect(x: 100, y: 40, width: 800, height: 600)
            }
        )

        controller.show()
        let resizeCountBeforeUpdates = controller.testingAnimatedResizeCount

        now = 0.01
        controller.updateStatus("first partial transcript update")
        now = 0.03
        controller.updateStatus("second partial transcript update")
        now = 0.05
        controller.updateStatus("third partial transcript update")

        #expect(controller.testingAnimatedResizeCount == resizeCountBeforeUpdates + 1)

        now = 0.20
        controller.updateStatus("later transcript update")

        #expect(controller.testingAnimatedResizeCount == resizeCountBeforeUpdates + 2)
    }

    @MainActor
    @Test func waveformRendererStopsWhenSettledAndWhenHudHides() {
        let controller = FloatingPanelController()
        controller.show()
        controller.updateLevel(0)

        #expect(controller.testingIsWaveformRendering)

        controller.testingAdvanceWaveformRenderer()
        #expect(!controller.testingIsWaveformRendering)

        controller.updateLevel(0.75)
        #expect(controller.testingIsWaveformRendering)

        controller.hide()
        #expect(!controller.testingIsWaveformRendering)
    }
}
