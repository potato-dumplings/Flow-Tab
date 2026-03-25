import AppKit
import Carbon
import Foundation

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

final class OptionTabHotkeyMonitor {
    var onHotkeyPressed: ((Bool) -> Void)?

    private var eventHandlerRef: EventHandlerRef?
    private var hotkeyRefs: [UInt32: EventHotKeyRef] = [:]

    private let signature: OSType = 0x46544142 // "FTAB"
    private let forwardHotkeyID: UInt32 = 1
    private let backwardHotkeyID: UInt32 = 2
    private let hotkeyConfiguration: SwitcherHotkeyConfiguration

    init(configuration: SwitcherHotkeyConfiguration = SwitcherHotkeyPreferencesStore.load()) {
        self.hotkeyConfiguration = configuration
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
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                let monitor = Unmanaged<OptionTabHotkeyMonitor>.fromOpaque(userData).takeUnretainedValue()
                return monitor.handleHotkeyEvent(event)
            },
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )

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
        }
    }

    private func handleHotkeyEvent(_ event: EventRef) -> OSStatus {
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
            return noErr
        }

        switch hotkeyID.id {
        case forwardHotkeyID:
            onHotkeyPressed?(false)
        case backwardHotkeyID:
            onHotkeyPressed?(true)
        default:
            break
        }
        return noErr
    }
}
