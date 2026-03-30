import Testing
@testable import VoiceInputCore

private final class HotkeyTestProbe: @unchecked Sendable {
    var queuedWork: [() -> Void] = []
    var receivedTransitions: [FnTransition] = []
}

struct HotkeyMonitorStateTests {
    @Test func fnTransitionProducesPressAndRelease() {
        var tracker = FnStateTracker()

        #expect(tracker.handle(flagsContainFn: true) == .pressed)
        #expect(tracker.handle(flagsContainFn: true) == .none)
        #expect(tracker.handle(flagsContainFn: false) == .released)
    }

    @Test func fnTrackerIgnoresRepeatedReleasedState() {
        var tracker = FnStateTracker()

        #expect(tracker.handle(flagsContainFn: false) == .none)
        #expect(tracker.handle(flagsContainFn: false) == .none)
    }

    @Test func hotkeyStateMachineOnlySuppressesWhenHandlingStartedOnPress() {
        var stateMachine = FnHotkeyStateMachine()

        #expect(
            stateMachine.handle(flagsContainFn: true, isHandlingEnabled: false) ==
                .init(transition: .pressed, shouldSuppress: false)
        )
        #expect(
            stateMachine.handle(flagsContainFn: false, isHandlingEnabled: true) ==
                .init(transition: .released, shouldSuppress: false)
        )
    }

    @Test func monitorPassesFnThroughWhenCallbacksAreNotFullyWired() {
        let monitor = HotkeyMonitor(dispatchHandler: { work in
            work()
        })
        monitor.onPress = {}

        #expect(!monitor.processFlagsChanged(flagsContainFn: true))
        #expect(!monitor.processFlagsChanged(flagsContainFn: false))
    }

    @Test func monitorQueuesHotkeyCallbacksOffTheTapPath() {
        let probe = HotkeyTestProbe()
        let monitor = HotkeyMonitor(dispatchHandler: { work in
            probe.queuedWork.append(work)
        })
        monitor.onPress = {
            probe.receivedTransitions.append(.pressed)
        }
        monitor.onRelease = {
            probe.receivedTransitions.append(.released)
        }

        #expect(monitor.processFlagsChanged(flagsContainFn: true))
        #expect(probe.receivedTransitions.isEmpty)
        #expect(probe.queuedWork.count == 1)

        probe.queuedWork.removeFirst()()

        #expect(probe.receivedTransitions == [.pressed])
    }

    @Test func permissionStatePreservesDetailedStatuses() {
        let state = PermissionState(
            accessibility: .denied,
            microphone: .notDetermined,
            speechRecognition: .restricted
        )

        #expect(state.hotkeyMonitoringAvailable == false)
        #expect(state.canRecordAudio == false)
        #expect(state.missingPermissions == [.accessibility, .microphone, .speechRecognition])
    }
}
