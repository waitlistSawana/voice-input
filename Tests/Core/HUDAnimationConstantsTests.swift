import Testing
@testable import VoiceInputUI
@testable import VoiceInputCore

struct HUDAnimationConstantsTests {
    @Test func animationDurationsMatchSpec() {
        #expect(HUDAnimationDurations.enter == 0.35)
        #expect(HUDAnimationDurations.resize == 0.25)
        #expect(HUDAnimationDurations.exit == 0.22)
    }

    @MainActor
    @Test func floatingPanelAnimationUsesAScaleBelowIdentity() {
        #expect(FloatingPanelController.animationScale < 1)
    }
}
