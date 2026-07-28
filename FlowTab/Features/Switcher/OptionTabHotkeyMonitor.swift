import AppKit
import Carbon
import Foundation
import Darwin

enum SwitcherPrimaryModifier: String, CaseIterable, Identifiable, Sendable {
    case option
    case control
    case command

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .option:
            return "Option"
        case .control:
            return "Control"
        case .command:
            return "Command"
        }
    }

    var carbonModifier: UInt32 {
        switch self {
        case .option:
            return UInt32(optionKey)
        case .control:
            return UInt32(controlKey)
        case .command:
            return UInt32(cmdKey)
        }
    }

    var eventModifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .option:
            return .option
        case .control:
            return .control
        case .command:
            return .command
        }
    }
}

enum SwitcherHotkeyKey: String, CaseIterable, Identifiable, Sendable {
    case tab
    case space
    case grave
    case a
    case b
    case c
    case d
    case e
    case f
    case g
    case h
    case i
    case j
    case k
    case l
    case m
    case n
    case o
    case p
    case q
    case r
    case s
    case t
    case u
    case v
    case w
    case x
    case y
    case z

    var id: String { rawValue }

    var keyCode: UInt16 {
        switch self {
        case .tab:
            return UInt16(kVK_Tab)
        case .space:
            return UInt16(kVK_Space)
        case .grave:
            return UInt16(kVK_ANSI_Grave)
        case .a:
            return UInt16(kVK_ANSI_A)
        case .b:
            return UInt16(kVK_ANSI_B)
        case .c:
            return UInt16(kVK_ANSI_C)
        case .d:
            return UInt16(kVK_ANSI_D)
        case .e:
            return UInt16(kVK_ANSI_E)
        case .f:
            return UInt16(kVK_ANSI_F)
        case .g:
            return UInt16(kVK_ANSI_G)
        case .h:
            return UInt16(kVK_ANSI_H)
        case .i:
            return UInt16(kVK_ANSI_I)
        case .j:
            return UInt16(kVK_ANSI_J)
        case .k:
            return UInt16(kVK_ANSI_K)
        case .l:
            return UInt16(kVK_ANSI_L)
        case .m:
            return UInt16(kVK_ANSI_M)
        case .n:
            return UInt16(kVK_ANSI_N)
        case .o:
            return UInt16(kVK_ANSI_O)
        case .p:
            return UInt16(kVK_ANSI_P)
        case .q:
            return UInt16(kVK_ANSI_Q)
        case .r:
            return UInt16(kVK_ANSI_R)
        case .s:
            return UInt16(kVK_ANSI_S)
        case .t:
            return UInt16(kVK_ANSI_T)
        case .u:
            return UInt16(kVK_ANSI_U)
        case .v:
            return UInt16(kVK_ANSI_V)
        case .w:
            return UInt16(kVK_ANSI_W)
        case .x:
            return UInt16(kVK_ANSI_X)
        case .y:
            return UInt16(kVK_ANSI_Y)
        case .z:
            return UInt16(kVK_ANSI_Z)
        }
    }

    var displayName: String {
        switch self {
        case .tab:
            return "Tab"
        case .space:
            return "Space"
        case .grave:
            return "`"
        default:
            return rawValue.uppercased()
        }
    }
}

struct SwitcherHotkeyConfiguration: Equatable, Sendable {
    let primaryModifier: SwitcherPrimaryModifier
    let mainKey: SwitcherHotkeyKey
    let quitKey: SwitcherHotkeyKey

    var forwardKeyCode: UInt32 {
        UInt32(mainKey.keyCode)
    }

    var forwardModifiers: UInt32 {
        primaryModifier.carbonModifier
    }

    var backwardModifiers: UInt32 {
        primaryModifier.carbonModifier | UInt32(shiftKey)
    }

    var quitKeyCode: UInt16 {
        quitKey.keyCode
    }

    var mainShortcutText: String {
        "\(primaryModifier.displayName) + \(mainKey.displayName)"
    }

    var backwardShortcutText: String {
        "\(primaryModifier.displayName) + Shift + \(mainKey.displayName)"
    }

    var quitShortcutText: String {
        "\(primaryModifier.displayName) + \(quitKey.displayName)"
    }
}

protocol CommandTabTakeoverControlling: AnyObject {
    func reconcileIfNeeded(shouldTakeOver: Bool) -> Bool
    func restoreSystemShortcutsIfNeeded()
}

protocol HotkeyMonitoring: AnyObject {
    var onHotkeyPressed: ((Bool) -> Void)? { get set }
    var onHotkeyReleased: ((Bool) -> Void)? { get set }

    func stop()
}

enum SwitcherHotkeyPreferencesStore {
    static let defaultPrimaryModifier: SwitcherPrimaryModifier = .option
    static let defaultMainKey: SwitcherHotkeyKey = .tab
    static let defaultQuitKey: SwitcherHotkeyKey = .q

    static func load(userDefaults: UserDefaults = .standard) -> SwitcherHotkeyConfiguration {
        let primaryModifierRaw = userDefaults.string(forKey: AppPreferenceKeys.hotkeyPrimaryModifier)
            ?? defaultPrimaryModifier.rawValue
        let mainKeyRaw = userDefaults.string(forKey: AppPreferenceKeys.hotkeyMainKey)
            ?? defaultMainKey.rawValue
        let quitKeyRaw = userDefaults.string(forKey: AppPreferenceKeys.hotkeyQuitKey)
            ?? defaultQuitKey.rawValue

        let configuration = resolve(
            primaryModifierRaw: primaryModifierRaw,
            mainKeyRaw: mainKeyRaw,
            quitKeyRaw: quitKeyRaw
        )

        if primaryModifierRaw != configuration.primaryModifier.rawValue {
            userDefaults.set(configuration.primaryModifier.rawValue, forKey: AppPreferenceKeys.hotkeyPrimaryModifier)
        }
        if mainKeyRaw != configuration.mainKey.rawValue {
            userDefaults.set(configuration.mainKey.rawValue, forKey: AppPreferenceKeys.hotkeyMainKey)
        }
        if quitKeyRaw != configuration.quitKey.rawValue {
            userDefaults.set(configuration.quitKey.rawValue, forKey: AppPreferenceKeys.hotkeyQuitKey)
        }

        return configuration
    }

    static func resolve(
        primaryModifierRaw: String,
        mainKeyRaw: String,
        quitKeyRaw: String
    ) -> SwitcherHotkeyConfiguration {
        let primaryModifier = SwitcherPrimaryModifier(rawValue: primaryModifierRaw) ?? defaultPrimaryModifier
        let mainKey = SwitcherHotkeyKey(rawValue: mainKeyRaw) ?? defaultMainKey
        var quitKey = SwitcherHotkeyKey(rawValue: quitKeyRaw) ?? defaultQuitKey

        if quitKey == mainKey {
            quitKey = defaultQuitFallback(excluding: mainKey)
        }

        return SwitcherHotkeyConfiguration(
            primaryModifier: primaryModifier,
            mainKey: mainKey,
            quitKey: quitKey
        )
    }

    private static func defaultQuitFallback(excluding key: SwitcherHotkeyKey) -> SwitcherHotkeyKey {
        if key != .q {
            return .q
        }
        return .w
    }
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
    enum HotkeyEventPhase {
        case pressed
        case released
    }

    var onHotkeyPressed: ((Bool) -> Void)?
    var onHotkeyReleased: ((Bool) -> Void)?

    private var eventHandlerRef: EventHandlerRef?
    private var hotkeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var registeredHotkeyIDs: Set<UInt32> = []

    private let signature: OSType
    private let forwardHotkeyID: UInt32
    private let backwardHotkeyID: UInt32
    private let hotkeyConfiguration: SwitcherHotkeyConfiguration
    private let handlerInstallerOverride: (() -> Bool)?
    private let hotkeyRegistrarOverride: ((UInt32, UInt32, UInt32) -> Bool)?
    private let hotkeyUnregisterOverride: ((UInt32) -> Void)?
    private let eventHandlerRemoverOverride: (() -> Void)?

    private(set) var isEventHandlerInstalledForTesting = false

    init(
        configuration: SwitcherHotkeyConfiguration = SwitcherHotkeyPreferencesStore.load(),
        signature: OSType = 0x46544142, // "FTAB"
        forwardHotkeyID: UInt32 = 1,
        backwardHotkeyID: UInt32 = 2,
        startsMonitoring: Bool = true,
        handlerInstallerOverride: (() -> Bool)? = nil,
        hotkeyRegistrarOverride: ((UInt32, UInt32, UInt32) -> Bool)? = nil,
        hotkeyUnregisterOverride: ((UInt32) -> Void)? = nil,
        eventHandlerRemoverOverride: (() -> Void)? = nil
    ) {
        self.hotkeyConfiguration = configuration
        self.signature = signature
        self.forwardHotkeyID = forwardHotkeyID
        self.backwardHotkeyID = backwardHotkeyID
        self.handlerInstallerOverride = handlerInstallerOverride
        self.hotkeyRegistrarOverride = hotkeyRegistrarOverride
        self.hotkeyUnregisterOverride = hotkeyUnregisterOverride
        self.eventHandlerRemoverOverride = eventHandlerRemoverOverride
        guard startsMonitoring else { return }
        guard installHandler() else { return }
        registerHotkeys()
    }

    deinit {
        stop()
    }

    func stop() {
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
        registerHotkey(
            id: forwardHotkeyID,
            keyCode: hotkeyConfiguration.forwardKeyCode,
            modifiers: hotkeyConfiguration.forwardModifiers
        )
        registerHotkey(
            id: backwardHotkeyID,
            keyCode: hotkeyConfiguration.forwardKeyCode,
            modifiers: hotkeyConfiguration.backwardModifiers
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

        let phase: String
        let direction: String
        let callback: ((Bool) -> Void)?
        let isBackward: Bool
        switch id {
        case forwardHotkeyID:
            if isPressedEvent {
                phase = "pressed"
                callback = onHotkeyPressed
            } else if isReleasedEvent {
                phase = "released"
                callback = onHotkeyReleased
            } else {
                return passThroughStatus
            }
            direction = "forward"
            isBackward = false
        case backwardHotkeyID:
            if isPressedEvent {
                phase = "pressed"
                callback = onHotkeyPressed
            } else if isReleasedEvent {
                phase = "released"
                callback = onHotkeyReleased
            } else {
                return passThroughStatus
            }
            direction = "backward"
            isBackward = true
        default:
            return passThroughStatus
        }
        RuntimeLog.debug(
            .hotKey,
            "dispatch phase=\(phase) dir=\(direction) id=\(id) nowMs=\(RuntimePerformanceClock.formatMilliseconds(eventReceivedMs))"
        )
        let callbackStartMs = RuntimePerformanceClock.monotonicMilliseconds()
        callback?(isBackward)
        let callbackEndMs = RuntimePerformanceClock.monotonicMilliseconds()
        RuntimeLog.debug(
            .hotKey,
            "dispatched phase=\(phase) dir=\(direction) id=\(id) callbackMs=\(RuntimePerformanceClock.formatMilliseconds(callbackEndMs - callbackStartMs)) totalMs=\(RuntimePerformanceClock.formatMilliseconds(callbackEndMs - eventReceivedMs))"
        )
        return noErr
    }
}

extension OptionTabHotkeyMonitor: HotkeyMonitoring {}
