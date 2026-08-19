import AppKit
import ApplicationServices
import CoreGraphics
import FlowTabCore

struct HotkeyChordTransition: Equatable, Sendable {
    let phase: HotkeyInputEvent.Phase
    let isBackward: Bool
    let isHoldSetPressed: Bool

    init(
        phase: HotkeyInputEvent.Phase,
        isBackward: Bool,
        isHoldSetPressed: Bool = true
    ) {
        self.phase = phase
        self.isBackward = isBackward
        self.isHoldSetPressed = isHoldSetPressed
    }
}

enum HotkeyChordEventTapMode: String, Equatable, Sendable {
    case accessibility
    case inputMonitoring

    var options: CGEventTapOptions {
        switch self {
        case .accessibility:
            return .defaultTap
        case .inputMonitoring:
            return .listenOnly
        }
    }
}

struct HotkeyChordEventAccessSnapshot: Equatable, Sendable {
    let accessibilityTrusted: Bool
    let inputMonitoringTrusted: Bool

    static func current() -> HotkeyChordEventAccessSnapshot {
        HotkeyChordEventAccessSnapshot(
            accessibilityTrusted: AccessibilityPermissionChecker.isTrusted(),
            inputMonitoringTrusted: CGPreflightListenEventAccess()
        )
    }

    var availableTapModes: [HotkeyChordEventTapMode] {
        guard accessibilityTrusted else { return [] }
        var modes: [HotkeyChordEventTapMode] = [.accessibility]
        if inputMonitoringTrusted {
            modes.append(.inputMonitoring)
        }
        return modes
    }

    var hasAvailableTapMode: Bool {
        !availableTapModes.isEmpty
    }
}

struct HotkeyChordStateMachine: Sendable {
    private enum InteractionState: Sendable {
        case idle
        case active(isBackward: Bool)
        case holdingBaseKeys(lastDirectionIsBackward: Bool)
    }

    let forwardKeys: SwitcherHotkeyKeySet
    let backwardKeys: SwitcherHotkeyKeySet
    let holdKeys: SwitcherHotkeyKeySet

    private var interactionState: InteractionState = .idle
    private var isArmed = true

    init(
        forwardKeys: SwitcherHotkeyKeySet,
        backwardKeys: SwitcherHotkeyKeySet,
        holdKeys: SwitcherHotkeyKeySet
    ) {
        precondition(!holdKeys.isEmpty, "Hold keys must not be empty")
        precondition(holdKeys.isSubset(of: forwardKeys))
        precondition(holdKeys.isSubset(of: backwardKeys))
        self.forwardKeys = forwardKeys
        self.backwardKeys = backwardKeys
        self.holdKeys = holdKeys
    }

    mutating func update(
        pressedKeys: SwitcherHotkeyKeySet
    ) -> [HotkeyChordTransition] {
        let selectedDirection = matchingDirection(
            pressedKeys: pressedKeys
        )

        switch interactionState {
        case .active(let isBackward):
            let activeKeys = isBackward ? backwardKeys : forwardKeys
            guard !activeKeys.isSubset(of: pressedKeys) else { return [] }

            let isHoldSetPressed = holdKeys.isSubset(
                of: pressedKeys
            )
            interactionState = isHoldSetPressed
                ? .holdingBaseKeys(
                    lastDirectionIsBackward: isBackward
                )
                : .idle
            isArmed = selectedDirection == nil
            return [
                HotkeyChordTransition(
                    phase: .released,
                    isBackward: isBackward,
                    isHoldSetPressed: isHoldSetPressed
                )
            ]
        case .holdingBaseKeys(let lastDirectionIsBackward):
            guard holdKeys.isSubset(of: pressedKeys) else {
                interactionState = .idle
                isArmed = selectedDirection == nil
                return [
                    HotkeyChordTransition(
                        phase: .released,
                        isBackward: lastDirectionIsBackward,
                        isHoldSetPressed: false
                    )
                ]
            }
        case .idle:
            break
        }

        guard let selectedDirection else {
            isArmed = true
            return []
        }
        guard isArmed else { return [] }

        interactionState = .active(isBackward: selectedDirection)
        isArmed = false
        return [
            HotkeyChordTransition(
                phase: .pressed,
                isBackward: selectedDirection
            )
        ]
    }

    mutating func reset() {
        interactionState = .idle
        isArmed = true
    }

    private func matchingDirection(
        pressedKeys: SwitcherHotkeyKeySet
    ) -> Bool? {
        if pressedKeys == backwardKeys {
            return true
        }
        if pressedKeys == forwardKeys {
            return false
        }
        return nil
    }
}

private struct HotkeyPressedKeyState {
    private(set) var keys = SwitcherHotkeyKeySet()

    mutating func apply(
        type: CGEventType,
        event: CGEvent
    ) -> SwitcherHotkeyKeySet {
        keys.replaceModifiers(
            with: KeyModifier(cgEventFlags: event.flags)
        )

        guard type == .keyDown || type == .keyUp else {
            return keys
        }
        let keyCode = UInt16(
            event.getIntegerValueField(.keyboardEventKeycode)
        )
        let key = SwitcherHotkeyKey(keyCode: keyCode)
        guard key.modifier == nil else { return keys }

        if type == .keyDown {
            keys.insert(key)
        } else {
            keys.remove(key)
        }
        return keys
    }

    mutating func reset() {
        keys = SwitcherHotkeyKeySet()
    }
}

extension KeyModifier {
    init(cgEventFlags: CGEventFlags) {
        var modifiers: KeyModifier = []
        if cgEventFlags.contains(.maskCommand) {
            modifiers.insert(.command)
        }
        if cgEventFlags.contains(.maskControl) {
            modifiers.insert(.control)
        }
        if cgEventFlags.contains(.maskAlternate) {
            modifiers.insert(.option)
        }
        if cgEventFlags.contains(.maskShift) {
            modifiers.insert(.shift)
        }
        self = modifiers
    }
}

final class HotkeyChordEventMonitor {
    typealias TransitionDispatcher = (@escaping () -> Void) -> Void

    var onTransition: ((HotkeyChordTransition) -> Void)?

    private var stateMachine: HotkeyChordStateMachine
    private var pressedKeyState = HotkeyPressedKeyState()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let accessSnapshotProvider:
        () -> HotkeyChordEventAccessSnapshot
    private let transitionDispatcher: TransitionDispatcher
    private var transitionDeliveryGeneration: UInt64 = 0

    private(set) var isActive = false
    private(set) var activeTapMode: HotkeyChordEventTapMode?

    init(
        configuration: SwitcherHotkeyConfiguration,
        accessSnapshotProvider: @escaping
            () -> HotkeyChordEventAccessSnapshot = {
                HotkeyChordEventAccessSnapshot.current()
            },
        transitionDispatcher: @escaping TransitionDispatcher = { action in
            DispatchQueue.main.async(execute: action)
        }
    ) {
        stateMachine = HotkeyChordStateMachine(
            forwardKeys: configuration.mainShortcut.keys,
            backwardKeys: configuration.backwardShortcut.keys,
            holdKeys: configuration.baseKeys
        )
        self.accessSnapshotProvider = accessSnapshotProvider
        self.transitionDispatcher = transitionDispatcher
    }

    deinit {
        stop()
    }

    @discardableResult
    func start() -> Bool {
        guard !isActive else { return true }

        let accessSnapshot = accessSnapshotProvider()
        guard accessSnapshot.hasAvailableTapMode else {
            RuntimeLog.warning(
                .permission,
                "chord hotkey event access missing "
                    + "accessibility="
                    + "\(accessSnapshot.accessibilityTrusted) "
                    + "inputMonitoring="
                    + "\(accessSnapshot.inputMonitoringTrusted)"
            )
            return false
        }
        let eventMask = eventMask(for: [
            .keyDown,
            .keyUp,
            .flagsChanged
        ])
        for tapMode in accessSnapshot.availableTapModes {
            guard let eventTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: tapMode.options,
                eventsOfInterest: eventMask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else {
                        return Unmanaged.passUnretained(event)
                    }
                    let monitor = Unmanaged<HotkeyChordEventMonitor>
                        .fromOpaque(userInfo)
                        .takeUnretainedValue()
                    monitor.consume(type: type, event: event)
                    return Unmanaged.passUnretained(event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
            else {
                RuntimeLog.warning(
                    .hotKey,
                    "chord event tap creation failed mode=\(tapMode.rawValue)"
                )
                continue
            }

            install(eventTap: eventTap, mode: tapMode)
            return true
        }
        return false
    }

    private func install(
        eventTap: CFMachPort,
        mode: HotkeyChordEventTapMode
    ) {
        let source = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            eventTap,
            0
        )
        self.eventTap = eventTap
        runLoopSource = source
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            source,
            .commonModes
        )
        CGEvent.tapEnable(tap: eventTap, enable: true)
        activeTapMode = mode
        isActive = true
    }

    func stop() {
        transitionDeliveryGeneration &+= 1
        guard eventTap != nil || runLoopSource != nil else { return }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                runLoopSource,
                .commonModes
            )
        }
        self.eventTap = nil
        self.runLoopSource = nil
        pressedKeyState.reset()
        stateMachine.reset()
        activeTapMode = nil
        isActive = false
    }

    func consume(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout
            || type == .tapDisabledByUserInput
        {
            pressedKeyState.reset()
            stateMachine.reset()
            transitionDeliveryGeneration &+= 1
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            RuntimeLog.warning(
                .hotKey,
                "chord event tap interrupted type=\(type.rawValue) "
                    + "action=reset_and_reenable"
            )
            return
        }
        let pressedKeys = pressedKeyState.apply(
            type: type,
            event: event
        )
        let transitions = stateMachine.update(
            pressedKeys: pressedKeys
        )
        let deliveryGeneration = transitionDeliveryGeneration
        for transition in transitions {
            // WindowServer disables slow event taps. Defer panel work so this
            // callback returns after only updating the pressed-key state.
            transitionDispatcher { [weak self] in
                guard let self,
                      self.transitionDeliveryGeneration
                        == deliveryGeneration
                else {
                    return
                }
                self.onTransition?(transition)
            }
        }
    }

    private func eventMask(
        for types: [CGEventType]
    ) -> CGEventMask {
        types.reduce(CGEventMask()) { result, type in
            result | (CGEventMask(1) << type.rawValue)
        }
    }
}
