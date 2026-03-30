import ApplicationServices
import Foundation

public enum FnTransition: Equatable, Sendable {
    case none
    case pressed
    case released
}

public struct FnStateTracker: Sendable {
    private var isFnPressed = false

    public init() {}

    public mutating func handle(flagsContainFn: Bool) -> FnTransition {
        switch (isFnPressed, flagsContainFn) {
        case (false, true):
            isFnPressed = true
            return .pressed
        case (true, false):
            isFnPressed = false
            return .released
        default:
            return .none
        }
    }
}

struct FnHotkeyEventDecision: Equatable, Sendable {
    let transition: FnTransition
    let shouldSuppress: Bool

    init(transition: FnTransition, shouldSuppress: Bool) {
        self.transition = transition
        self.shouldSuppress = shouldSuppress
    }
}

struct FnHotkeyStateMachine: Sendable {
    private var tracker = FnStateTracker()
    private var isSuppressingCurrentHold = false

    mutating func handle(flagsContainFn: Bool, isHandlingEnabled: Bool) -> FnHotkeyEventDecision {
        let transition = tracker.handle(flagsContainFn: flagsContainFn)

        switch transition {
        case .pressed:
            isSuppressingCurrentHold = isHandlingEnabled
            return FnHotkeyEventDecision(transition: .pressed, shouldSuppress: isHandlingEnabled)
        case .released:
            let shouldSuppress = isSuppressingCurrentHold
            isSuppressingCurrentHold = false
            return FnHotkeyEventDecision(transition: .released, shouldSuppress: shouldSuppress)
        case .none:
            return FnHotkeyEventDecision(transition: .none, shouldSuppress: false)
        }
    }

    mutating func reset() {
        tracker = FnStateTracker()
        isSuppressingCurrentHold = false
    }
}

public final class HotkeyMonitor {
    public var onPress: (@Sendable () -> Void)?
    public var onRelease: (@Sendable () -> Void)?
    public private(set) var isRunning = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let dispatchHandler: @Sendable (@escaping @Sendable () -> Void) -> Void
    private var stateMachine = FnHotkeyStateMachine()

    public init(
        dispatchHandler: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void = { work in
            DispatchQueue.main.async(execute: work)
        }
    ) {
        self.dispatchHandler = dispatchHandler
    }

    deinit {
        stop()
    }

    @discardableResult
    public func start() -> Bool {
        guard eventTap == nil else { return true }

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            return monitor.handleEvent(proxy: proxy, type: type, event: event)
        }

        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: userInfo
        ) else {
            isRunning = false
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        return true
    }

    public func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CFRunLoopSourceInvalidate(runLoopSource)
        }

        runLoopSource = nil
        eventTap = nil
        isRunning = false
        stateMachine.reset()
    }

    var isHandlingEnabled: Bool {
        onPress != nil && onRelease != nil
    }

    @discardableResult
    func processFlagsChanged(flagsContainFn: Bool) -> Bool {
        let decision = stateMachine.handle(flagsContainFn: flagsContainFn, isHandlingEnabled: isHandlingEnabled)
        guard decision.shouldSuppress else {
            return false
        }

        dispatchTransition(decision.transition)
        return true
    }

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        return processFlagsChanged(flagsContainFn: event.flags.contains(.maskSecondaryFn))
            ? nil
            : Unmanaged.passUnretained(event)
    }

    private func dispatchTransition(_ transition: FnTransition) {
        dispatchHandler { [weak self] in
            guard let self else {
                return
            }

            switch transition {
            case .pressed:
                self.onPress?()
            case .released:
                self.onRelease?()
            case .none:
                break
            }
        }
    }
}
