import AppKit
import Carbon
import Foundation
import Darwin

enum SwitcherPrimaryModifier: String, CaseIterable, Identifiable {
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

enum SwitcherHotkeyKey: String, CaseIterable, Identifiable {
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

struct SwitcherHotkeyConfiguration {
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
    private var frameworkHandle: UnsafeMutableRawPointer?
    private var setSymbolicHotKeyEnabled: SetSymbolicHotKeyEnabledFn?
    private var hasRecoveredAtLaunch = false
    private var isTakeoverActive = false

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    deinit {
        if let frameworkHandle {
            dlclose(frameworkHandle)
        }
    }

    func reconcileIfNeeded(with configuration: SwitcherHotkeyConfiguration) -> Bool {
        recoverFromAbnormalExitIfNeeded()

        let shouldTakeOver = configuration.primaryModifier == .command
            && configuration.mainKey == .tab

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
            RuntimeLog.info("HotKey", "system Command+Tab shortcuts restored")
            isTakeoverActive = false
            userDefaults.set(false, forKey: Self.takeoverMarkerKey)
        } else {
            RuntimeLog.info("HotKey", "failed to restore system Command+Tab shortcuts")
        }
    }

    private func recoverFromAbnormalExitIfNeeded() {
        guard !hasRecoveredAtLaunch else { return }
        hasRecoveredAtLaunch = true
        guard userDefaults.bool(forKey: Self.takeoverMarkerKey) else { return }

        let success = setSystemCommandTabEnabled(true)
        if success {
            RuntimeLog.info("HotKey", "recovered system Command+Tab shortcuts from previous abnormal exit")
            userDefaults.set(false, forKey: Self.takeoverMarkerKey)
        } else {
            RuntimeLog.info("HotKey", "failed to recover system Command+Tab shortcuts after abnormal exit")
        }
    }

    private func activateTakeoverIfNeeded() -> Bool {
        guard !isTakeoverActive else { return true }

        let success = setSystemCommandTabEnabled(false)
        if success {
            RuntimeLog.info("HotKey", "system Command+Tab shortcuts disabled for FlowTab takeover")
            isTakeoverActive = true
            userDefaults.set(true, forKey: Self.takeoverMarkerKey)
            return true
        }

        // Partial failures can leave system hotkeys in an unknown state.
        // Try to roll back immediately before falling back to non-takeover mode.
        _ = setSystemCommandTabEnabled(true)
        RuntimeLog.info("HotKey", "failed to disable system Command+Tab shortcuts; takeover unavailable")
        isTakeoverActive = false
        userDefaults.set(false, forKey: Self.takeoverMarkerKey)
        return false
    }

    private func setSystemCommandTabEnabled(_ isEnabled: Bool) -> Bool {
        guard let setSymbolicHotKeyEnabled = resolveSetSymbolicHotKeyEnabled() else { return false }
        var hasFailure = false

        for hotKey in SymbolicHotKey.allCases {
            let status = setSymbolicHotKeyEnabled(hotKey.rawValue, isEnabled)
            if status != noErr {
                hasFailure = true
                RuntimeLog.info(
                    "HotKey",
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

        RuntimeLog.info("HotKey", "CGSSetSymbolicHotKeyEnabled symbol not found")
        return nil
    }
}

final class OptionTabHotkeyMonitor {
    var onHotkeyPressed: ((Bool) -> Void)?
    var onHotkeyReleased: ((Bool) -> Void)?

    private var eventHandlerRef: EventHandlerRef?
    private var hotkeyRefs: [UInt32: EventHotKeyRef] = [:]

    private let signature: OSType
    private let forwardHotkeyID: UInt32
    private let backwardHotkeyID: UInt32
    private let hotkeyConfiguration: SwitcherHotkeyConfiguration

    init(
        configuration: SwitcherHotkeyConfiguration = SwitcherHotkeyPreferencesStore.load(),
        signature: OSType = 0x46544142, // "FTAB"
        forwardHotkeyID: UInt32 = 1,
        backwardHotkeyID: UInt32 = 2
    ) {
        self.hotkeyConfiguration = configuration
        self.signature = signature
        self.forwardHotkeyID = forwardHotkeyID
        self.backwardHotkeyID = backwardHotkeyID
        installHandler()
        registerHotkeys()
    }

    deinit {
        stop()
    }

    func stop() {
        for hotkeyRef in hotkeyRefs.values {
            UnregisterEventHotKey(hotkeyRef)
        }
        hotkeyRefs.removeAll()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func installHandler() {
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
        }
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
            RuntimeLog.info(
                "HotKey",
                "register ok signature=\(self.signature) id=\(id) keyCode=\(keyCode) modifiers=\(modifiers)"
            )
        } else {
            RuntimeLog.info(
                "HotKey",
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

        guard status == noErr, hotkeyID.signature == signature else {
            // Multiple hotkey monitors may be installed in the same process.
            // Pass through unrelated events so the owning monitor can handle them.
            return passThroughStatus
        }

        switch hotkeyID.id {
        case forwardHotkeyID:
            if isPressedEvent {
                onHotkeyPressed?(false)
            } else {
                onHotkeyReleased?(false)
            }
        case backwardHotkeyID:
            if isPressedEvent {
                onHotkeyPressed?(true)
            } else {
                onHotkeyReleased?(true)
            }
        default:
            return passThroughStatus
        }
        return noErr
    }
}
