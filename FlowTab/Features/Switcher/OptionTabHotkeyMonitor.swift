import AppKit
import Carbon
import FlowTabCore
import Foundation
import Darwin

protocol CommandTabTakeoverControlling: AnyObject {
    func reconcileIfNeeded(shouldTakeOver: Bool) -> Bool
    func restoreSystemShortcutsIfNeeded()
}

protocol HotkeyMonitoring: AnyObject {
    var inputSourceID: HotkeyInputSourceID { get }
    var onHotkeyEvent: ((HotkeyInputEvent) -> Void)? { get set }

    func start()
    func stop()
    func requireChordEventMonitoring()
}

final class CommandTabTakeoverController {
    private enum SymbolicHotKey: Int32, CaseIterable {
        case commandTab = 1
        case commandShiftTab = 2
    }

    static let takeoverMarkerKey = "commandTabTakeoverPendingRestore"

    private typealias SetSymbolicHotKeyEnabledFn = @convention(c) (Int32, Bool) -> Int32

    private let userDefaults: UserDefaults
    private let symbolicHotKeySetterOverride: ((Int32, Bool) -> Int32)?
    private var frameworkHandle: UnsafeMutableRawPointer?
    private var setSymbolicHotKeyEnabled: SetSymbolicHotKeyEnabledFn?
    private var hasRecoveredAtLaunch = false
    private var isTakeoverActive = false

    init(
        userDefaults: UserDefaults = .standard,
        symbolicHotKeySetterOverride: ((Int32, Bool) -> Int32)? = nil
    ) {
        self.userDefaults = userDefaults
        self.symbolicHotKeySetterOverride = symbolicHotKeySetterOverride
    }

    deinit {
        if let frameworkHandle {
            dlclose(frameworkHandle)
        }
    }

    func reconcileIfNeeded(shouldTakeOver: Bool) -> Bool {
        recoverFromAbnormalExitIfNeeded()

        if shouldTakeOver {
            return activateTakeoverIfNeeded()
        }

        restoreSystemShortcutsIfNeeded()
        return true
    }

    func restoreSystemShortcutsIfNeeded() {
        guard isTakeoverActive || userDefaults.bool(forKey: Self.takeoverMarkerKey) else { return }
        let success = setSystemCommandTabEnabled(true)
        if success {
            RuntimeLog.info(.hotKey, "system Command+Tab shortcuts restored")
            isTakeoverActive = false
            userDefaults.set(false, forKey: Self.takeoverMarkerKey)
        } else {
            RuntimeLog.error(.hotKey, "failed to restore system Command+Tab shortcuts")
        }
    }

    private func recoverFromAbnormalExitIfNeeded() {
        guard !hasRecoveredAtLaunch else { return }
        hasRecoveredAtLaunch = true
        guard userDefaults.bool(forKey: Self.takeoverMarkerKey) else { return }

        let success = setSystemCommandTabEnabled(true)
        if success {
            RuntimeLog.info(.hotKey, "recovered system Command+Tab shortcuts from previous abnormal exit")
            userDefaults.set(false, forKey: Self.takeoverMarkerKey)
        } else {
            RuntimeLog.error(.hotKey, "failed to recover system Command+Tab shortcuts after abnormal exit")
        }
    }

    private func activateTakeoverIfNeeded() -> Bool {
        guard !isTakeoverActive else { return true }

        let success = setSystemCommandTabEnabled(false)
        if success {
            RuntimeLog.info(.hotKey, "system Command+Tab shortcuts disabled for FlowTab takeover")
            isTakeoverActive = true
            userDefaults.set(true, forKey: Self.takeoverMarkerKey)
            return true
        }

        // Partial failures can leave system hotkeys in an unknown state.
        // Try to roll back immediately before falling back to non-takeover mode.
        _ = setSystemCommandTabEnabled(true)
        RuntimeLog.error(.hotKey, "failed to disable system Command+Tab shortcuts; takeover unavailable")
        isTakeoverActive = false
        userDefaults.set(false, forKey: Self.takeoverMarkerKey)
        return false
    }

    private func setSystemCommandTabEnabled(_ isEnabled: Bool) -> Bool {
        let setSymbolicHotKeyEnabled: (Int32, Bool) -> Int32
        if let symbolicHotKeySetterOverride {
            setSymbolicHotKeyEnabled = symbolicHotKeySetterOverride
        } else if let resolvedSetter = resolveSetSymbolicHotKeyEnabled() {
            setSymbolicHotKeyEnabled = resolvedSetter
        } else {
            return false
        }
        var hasFailure = false

        for hotKey in SymbolicHotKey.allCases {
            let status = setSymbolicHotKeyEnabled(hotKey.rawValue, isEnabled)
            if status != noErr {
                hasFailure = true
                RuntimeLog.error(
                    .hotKey,
                    "set symbolic hotkey failed id=\(hotKey.rawValue) enabled=\(isEnabled) status=\(status)"
                )
            }
        }

        return !hasFailure
    }

    private func resolveSetSymbolicHotKeyEnabled() -> SetSymbolicHotKeyEnabledFn? {
        if let setSymbolicHotKeyEnabled {
            return setSymbolicHotKeyEnabled
        }

        let frameworkCandidates = [
            "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        ]

        for path in frameworkCandidates {
            guard let handle = dlopen(path, RTLD_NOW) else { continue }
            if let symbol = dlsym(handle, "CGSSetSymbolicHotKeyEnabled") {
                frameworkHandle = handle
                let function = unsafeBitCast(symbol, to: SetSymbolicHotKeyEnabledFn.self)
                setSymbolicHotKeyEnabled = function
                return function
            }
            dlclose(handle)
        }

        RuntimeLog.error(.hotKey, "CGSSetSymbolicHotKeyEnabled symbol not found")
        return nil
    }

    func hasSymbolicHotKeySetterForTesting() -> Bool {
        resolveSetSymbolicHotKeyEnabled() != nil
    }
}

extension CommandTabTakeoverController: CommandTabTakeoverControlling {}

final class OptionTabHotkeyMonitor {
    typealias HotkeyEventPhase = HotkeyInputEvent.Phase

    let inputSourceID = HotkeyInputSourceID()
    var onHotkeyEvent: ((HotkeyInputEvent) -> Void)?

    private var eventHandlerRef: EventHandlerRef?
    private var hotkeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var registeredHotkeyIDs: Set<UInt32> = []
    private var chordEventMonitor: HotkeyChordEventMonitor?
    private var requiresChordEventMonitoring = false
    private let inputSequenceLock = NSLock()
    private var inputSequence: UInt64 = 0

    private let signature: OSType
    private let forwardHotkeyID: UInt32
    private let backwardHotkeyID: UInt32
    private let hotkeyConfiguration: SwitcherHotkeyConfiguration
    private let handlerInstallerOverride: (() -> Bool)?
    private let hotkeyRegistrarOverride: ((UInt32, UInt32, UInt32) -> Bool)?
    private let hotkeyUnregisterOverride: ((UInt32) -> Void)?
    private let eventHandlerRemoverOverride: (() -> Void)?
    private let chordEventMonitorStarterOverride:
        ((SwitcherHotkeyConfiguration) -> Bool)?
    private let chordEventMonitorStopperOverride: (() -> Void)?

    private(set) var isEventHandlerInstalledForTesting = false
    private var isChordEventMonitorInstalledForTesting = false
    var isChordEventMonitorActiveForTesting: Bool {
        isChordEventMonitorInstalledForTesting
            || chordEventMonitor?.isActive == true
    }

    init(
        configuration: SwitcherHotkeyConfiguration = SwitcherHotkeyPreferencesStore.load(),
        signature: OSType = 0x46544142, // "FTAB"
        forwardHotkeyID: UInt32 = 1,
        backwardHotkeyID: UInt32 = 2,
        startsMonitoring: Bool = true,
        handlerInstallerOverride: (() -> Bool)? = nil,
        hotkeyRegistrarOverride: ((UInt32, UInt32, UInt32) -> Bool)? = nil,
        hotkeyUnregisterOverride: ((UInt32) -> Void)? = nil,
        eventHandlerRemoverOverride: (() -> Void)? = nil,
        chordEventMonitorStarterOverride:
            ((SwitcherHotkeyConfiguration) -> Bool)? = nil,
        chordEventMonitorStopperOverride: (() -> Void)? = nil
    ) {
        self.hotkeyConfiguration = configuration
        self.signature = signature
        self.forwardHotkeyID = forwardHotkeyID
        self.backwardHotkeyID = backwardHotkeyID
        self.handlerInstallerOverride = handlerInstallerOverride
        self.hotkeyRegistrarOverride = hotkeyRegistrarOverride
        self.hotkeyUnregisterOverride = hotkeyUnregisterOverride
        self.eventHandlerRemoverOverride = eventHandlerRemoverOverride
        self.chordEventMonitorStarterOverride =
            chordEventMonitorStarterOverride
        self.chordEventMonitorStopperOverride =
            chordEventMonitorStopperOverride
        guard startsMonitoring else { return }
        start()
    }

    func start() {
        if requiresChordEventMonitoring
            || !hotkeyConfiguration.supportsCarbonRegistration
        {
            startChordEventMonitor()
            return
        }
        guard eventHandlerRef == nil else { return }
        guard !isEventHandlerInstalledForTesting else { return }
        guard installHandler() else { return }
        registerHotkeys()
    }

    func requireChordEventMonitoring() {
        requiresChordEventMonitoring = true
    }

    deinit {
        stop()
    }

    func stop() {
        chordEventMonitor?.stop()
        chordEventMonitor = nil
        if isChordEventMonitorInstalledForTesting {
            chordEventMonitorStopperOverride?()
            isChordEventMonitorInstalledForTesting = false
        }

        if let hotkeyUnregisterOverride {
            for id in registeredHotkeyIDs.sorted() {
                hotkeyUnregisterOverride(id)
            }
        } else {
            for hotkeyRef in hotkeyRefs.values {
                UnregisterEventHotKey(hotkeyRef)
            }
        }
        hotkeyRefs.removeAll()
        registeredHotkeyIDs.removeAll()

        if let eventHandlerRef {
            if let eventHandlerRemoverOverride {
                eventHandlerRemoverOverride()
            } else {
                RemoveEventHandler(eventHandlerRef)
            }
            self.eventHandlerRef = nil
        } else if isEventHandlerInstalledForTesting, let eventHandlerRemoverOverride {
            eventHandlerRemoverOverride()
        }
        isEventHandlerInstalledForTesting = false
    }

    private func startChordEventMonitor() {
        guard chordEventMonitor == nil else { return }
        guard !isChordEventMonitorInstalledForTesting else { return }
        if let chordEventMonitorStarterOverride {
            isChordEventMonitorInstalledForTesting =
                chordEventMonitorStarterOverride(hotkeyConfiguration)
            return
        }
        let monitor = HotkeyChordEventMonitor(
            configuration: hotkeyConfiguration
        )
        monitor.onTransition = { [weak self] transition in
            self?.dispatchChordTransition(transition)
        }
        guard monitor.start() else {
            RuntimeLog.error(
                .hotKey,
                "chord event monitor unavailable "
                    + "forward=\(hotkeyConfiguration.mainShortcutText) "
                    + "backward=\(hotkeyConfiguration.backwardShortcutText)"
            )
            return
        }
        chordEventMonitor = monitor
        let tapMode = monitor.activeTapMode?.rawValue ?? "unknown"
        RuntimeLog.info(
            .hotKey,
            "chord event monitor active "
                + "mode=\(tapMode) "
                + "forward=\(hotkeyConfiguration.mainShortcutText) "
                + "backward=\(hotkeyConfiguration.backwardShortcutText)"
        )
    }

    @discardableResult
    private func installHandler() -> Bool {
        if let handlerInstallerOverride {
            let installed = handlerInstallerOverride()
            isEventHandlerInstalledForTesting = installed
            return installed
        }

        var eventTypes: [EventTypeSpec] = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]

        let status: OSStatus = eventTypes.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return OSStatus(paramErr) }
            return InstallEventHandler(
                GetApplicationEventTarget(),
                { _, event, userData in
                    guard let event, let userData else { return noErr }
                    let monitor = Unmanaged<OptionTabHotkeyMonitor>.fromOpaque(userData).takeUnretainedValue()
                    return monitor.handleHotkeyEvent(event)
                },
                buffer.count,
                baseAddress,
                UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                &eventHandlerRef
            )
        }

        if status != noErr {
            eventHandlerRef = nil
            isEventHandlerInstalledForTesting = false
            return false
        }
        isEventHandlerInstalledForTesting = true
        return true
    }

    private func registerHotkeys() {
        guard
            let forward = hotkeyConfiguration.mainShortcut.carbonRegistration,
            let backward = hotkeyConfiguration.backwardShortcut.carbonRegistration
        else {
            RuntimeLog.error(
                .hotKey,
                "Carbon registration requested for a key-set chord"
            )
            return
        }
        registerHotkey(
            id: forwardHotkeyID,
            keyCode: forward.keyCode,
            modifiers: forward.modifiers
        )
        registerHotkey(
            id: backwardHotkeyID,
            keyCode: backward.keyCode,
            modifiers: backward.modifiers
        )
    }

    private func registerHotkey(id: UInt32, keyCode: UInt32, modifiers: UInt32) {
        if let hotkeyRegistrarOverride {
            if hotkeyRegistrarOverride(id, keyCode, modifiers) {
                registeredHotkeyIDs.insert(id)
                RuntimeLog.info(
                    .hotKey,
                    "register ok signature=\(self.signature) id=\(id) keyCode=\(keyCode) modifiers=\(modifiers)"
                )
            } else {
                RuntimeLog.error(
                    .hotKey,
                    "register failed signature=\(self.signature) id=\(id) keyCode=\(keyCode) modifiers=\(modifiers) status=test_override"
                )
            }
            return
        }

        let hotkeyID = EventHotKeyID(signature: signature, id: id)
        var hotkeyRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        if status == noErr, let hotkeyRef {
            hotkeyRefs[id] = hotkeyRef
            registeredHotkeyIDs.insert(id)
            RuntimeLog.info(
                .hotKey,
                "register ok signature=\(self.signature) id=\(id) keyCode=\(keyCode) modifiers=\(modifiers)"
            )
        } else {
            RuntimeLog.error(
                .hotKey,
                "register failed signature=\(self.signature) id=\(id) keyCode=\(keyCode) modifiers=\(modifiers) status=\(status)"
            )
        }
    }

    private func handleHotkeyEvent(_ event: EventRef) -> OSStatus {
        let passThroughStatus = OSStatus(eventNotHandledErr)
        let eventKind = GetEventKind(event)
        let isPressedEvent = eventKind == UInt32(kEventHotKeyPressed)
        let isReleasedEvent = eventKind == UInt32(kEventHotKeyReleased)
        guard isPressedEvent || isReleasedEvent else {
            return passThroughStatus
        }
        let eventReceivedMs = RuntimePerformanceClock.monotonicMilliseconds()

        var hotkeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotkeyID
        )

        guard status == noErr else {
            return passThroughStatus
        }
        return dispatchResolvedHotkeyEvent(
            signature: hotkeyID.signature,
            id: hotkeyID.id,
            isPressedEvent: isPressedEvent,
            isReleasedEvent: isReleasedEvent,
            eventReceivedMs: eventReceivedMs
        )
    }

    @discardableResult
    func dispatchHotkeyEventForTesting(
        signature: OSType? = nil,
        id: UInt32,
        phase: HotkeyEventPhase
    ) -> OSStatus {
        dispatchResolvedHotkeyEvent(
            signature: signature ?? self.signature,
            id: id,
            isPressedEvent: phase == .pressed,
            isReleasedEvent: phase == .released,
            eventReceivedMs: RuntimePerformanceClock.monotonicMilliseconds()
        )
    }

    @discardableResult
    func handleHotkeyEventForTesting(_ event: EventRef) -> OSStatus {
        handleHotkeyEvent(event)
    }

    private func dispatchResolvedHotkeyEvent(
        signature: OSType,
        id: UInt32,
        isPressedEvent: Bool,
        isReleasedEvent: Bool,
        eventReceivedMs: Double
    ) -> OSStatus {
        let passThroughStatus = OSStatus(eventNotHandledErr)
        guard signature == self.signature else {
            // Multiple hotkey monitors may be installed in the same process.
            // Pass through unrelated events so the owning monitor can handle them.
            return passThroughStatus
        }

        let phase: HotkeyInputEvent.Phase
        let direction: String
        let isBackward: Bool
        switch id {
        case forwardHotkeyID:
            if isPressedEvent {
                phase = .pressed
            } else if isReleasedEvent {
                phase = .released
            } else {
                return passThroughStatus
            }
            direction = "forward"
            isBackward = false
        case backwardHotkeyID:
            if isPressedEvent {
                phase = .pressed
            } else if isReleasedEvent {
                phase = .released
            } else {
                return passThroughStatus
            }
            direction = "backward"
            isBackward = true
        default:
            return passThroughStatus
        }
        let inputEvent = HotkeyInputEvent(
            identity: nextInputEventIdentity(),
            phase: phase,
            isBackward: isBackward,
            // Carbon only reports that the registered chord ended; the base
            // keys may still be held when the main key is released.
            holdSetPressedEvidence: phase == .pressed ? true : nil
        )
        let phaseText = phase == .pressed ? "pressed" : "released"
        RuntimeLog.debug(
            .hotKey,
            "dispatch phase=\(phaseText) dir=\(direction) id=\(id) source=\(inputSourceID.rawValue.uuidString) sequence=\(inputEvent.identity.sequence) nowMs=\(RuntimePerformanceClock.formatMilliseconds(eventReceivedMs))"
        )
        let callbackStartMs = RuntimePerformanceClock.monotonicMilliseconds()
        onHotkeyEvent?(inputEvent)
        let callbackEndMs = RuntimePerformanceClock.monotonicMilliseconds()
        RuntimeLog.debug(
            .hotKey,
            "dispatched phase=\(phaseText) dir=\(direction) id=\(id) source=\(inputSourceID.rawValue.uuidString) sequence=\(inputEvent.identity.sequence) callbackMs=\(RuntimePerformanceClock.formatMilliseconds(callbackEndMs - callbackStartMs)) totalMs=\(RuntimePerformanceClock.formatMilliseconds(callbackEndMs - eventReceivedMs))"
        )
        return noErr
    }

    private func nextInputEventIdentity() -> HotkeyInputEventIdentity {
        inputSequenceLock.lock()
        inputSequence &+= 1
        let sequence = inputSequence
        inputSequenceLock.unlock()
        return HotkeyInputEventIdentity(
            sourceID: inputSourceID,
            sequence: sequence
        )
    }

    private func dispatchChordTransition(
        _ transition: HotkeyChordTransition
    ) {
        let inputEvent = HotkeyInputEvent(
            identity: nextInputEventIdentity(),
            phase: transition.phase,
            isBackward: transition.isBackward,
            holdSetPressedEvidence:
                transition.isHoldSetPressed
        )
        let phase = transition.phase == .pressed
            ? "pressed" : "released"
        let direction = transition.isBackward
            ? "backward" : "forward"
        RuntimeLog.debug(
            .hotKey,
            "dispatch chord phase=\(phase) dir=\(direction) "
                + "holdSetPressed="
                + "\(transition.isHoldSetPressed ? 1 : 0) "
                + "source=\(inputSourceID.rawValue.uuidString) "
                + "sequence=\(inputEvent.identity.sequence)"
        )
        onHotkeyEvent?(inputEvent)
    }
}

extension OptionTabHotkeyMonitor: HotkeyMonitoring {}
