import AppKit
import Carbon
import FlowTabCore
import Foundation

extension KeyModifier {
    init(eventModifierFlags: NSEvent.ModifierFlags) {
        var modifiers: KeyModifier = []
        if eventModifierFlags.contains(.command) {
            modifiers.insert(.command)
        }
        if eventModifierFlags.contains(.control) {
            modifiers.insert(.control)
        }
        if eventModifierFlags.contains(.option) {
            modifiers.insert(.option)
        }
        if eventModifierFlags.contains(.shift) {
            modifiers.insert(.shift)
        }
        self = modifiers
    }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if contains(.command) {
            result |= UInt32(cmdKey)
        }
        if contains(.control) {
            result |= UInt32(controlKey)
        }
        if contains(.option) {
            result |= UInt32(optionKey)
        }
        if contains(.shift) {
            result |= UInt32(shiftKey)
        }
        return result
    }

    var eventModifierFlags: NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if contains(.command) {
            result.insert(.command)
        }
        if contains(.control) {
            result.insert(.control)
        }
        if contains(.option) {
            result.insert(.option)
        }
        if contains(.shift) {
            result.insert(.shift)
        }
        return result
    }
}

struct SwitcherHotkeyKey: RawRepresentable, CaseIterable, Identifiable, Hashable, Sendable {
    static let command = Self(keyCode: UInt16(kVK_Command))
    static let control = Self(keyCode: UInt16(kVK_Control))
    static let option = Self(keyCode: UInt16(kVK_Option))
    static let shift = Self(keyCode: UInt16(kVK_Shift))
    static let tab = Self(keyCode: UInt16(kVK_Tab))
    static let space = Self(keyCode: UInt16(kVK_Space))
    static let escape = Self(keyCode: UInt16(kVK_Escape))
    static let f6 = Self(keyCode: UInt16(kVK_F6))
    static let f8 = Self(keyCode: UInt16(kVK_F8))
    static let grave = Self(keyCode: UInt16(kVK_ANSI_Grave))
    static let a = Self(keyCode: UInt16(kVK_ANSI_A))
    static let b = Self(keyCode: UInt16(kVK_ANSI_B))
    static let c = Self(keyCode: UInt16(kVK_ANSI_C))
    static let d = Self(keyCode: UInt16(kVK_ANSI_D))
    static let e = Self(keyCode: UInt16(kVK_ANSI_E))
    static let f = Self(keyCode: UInt16(kVK_ANSI_F))
    static let g = Self(keyCode: UInt16(kVK_ANSI_G))
    static let h = Self(keyCode: UInt16(kVK_ANSI_H))
    static let i = Self(keyCode: UInt16(kVK_ANSI_I))
    static let j = Self(keyCode: UInt16(kVK_ANSI_J))
    static let k = Self(keyCode: UInt16(kVK_ANSI_K))
    static let l = Self(keyCode: UInt16(kVK_ANSI_L))
    static let m = Self(keyCode: UInt16(kVK_ANSI_M))
    static let n = Self(keyCode: UInt16(kVK_ANSI_N))
    static let o = Self(keyCode: UInt16(kVK_ANSI_O))
    static let p = Self(keyCode: UInt16(kVK_ANSI_P))
    static let q = Self(keyCode: UInt16(kVK_ANSI_Q))
    static let r = Self(keyCode: UInt16(kVK_ANSI_R))
    static let s = Self(keyCode: UInt16(kVK_ANSI_S))
    static let t = Self(keyCode: UInt16(kVK_ANSI_T))
    static let u = Self(keyCode: UInt16(kVK_ANSI_U))
    static let v = Self(keyCode: UInt16(kVK_ANSI_V))
    static let w = Self(keyCode: UInt16(kVK_ANSI_W))
    static let x = Self(keyCode: UInt16(kVK_ANSI_X))
    static let y = Self(keyCode: UInt16(kVK_ANSI_Y))
    static let z = Self(keyCode: UInt16(kVK_ANSI_Z))

    static let allCases: [SwitcherHotkeyKey] = [
        .tab, .space, .grave,
        .a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m,
        .n, .o, .p, .q, .r, .s, .t, .u, .v, .w, .x, .y, .z
    ]

    let keyCode: UInt16

    init(keyCode: UInt16) {
        self.keyCode = Self.canonicalKeyCode(keyCode)
    }

    init?(rawValue: String) {
        if let keyCode = Self.namedKeyCodes[rawValue.lowercased()] {
            self.init(keyCode: keyCode)
            return
        }
        guard
            rawValue.hasPrefix(Self.keyCodePrefix),
            let keyCode = UInt16(rawValue.dropFirst(Self.keyCodePrefix.count))
        else {
            return nil
        }
        self.init(keyCode: keyCode)
    }

    var rawValue: String {
        switch Int(keyCode) {
        case kVK_Command:
            return "command"
        case kVK_Control:
            return "control"
        case kVK_Option:
            return "option"
        case kVK_Shift:
            return "shift"
        default:
            return Self.namedKeyCodes.first(where: { $0.value == keyCode })?.key
                ?? "\(Self.keyCodePrefix)\(keyCode)"
        }
    }

    var id: String { rawValue }

    var displayName: String {
        switch Int(keyCode) {
        case kVK_Command:
            return "Command"
        case kVK_Control:
            return "Control"
        case kVK_Option:
            return "Option"
        case kVK_Shift:
            return "Shift"
        default:
            break
        }
        if let rawValue = Self.namedKeyCodes.first(where: { $0.value == keyCode })?.key {
            switch rawValue {
            case "tab":
                return "Tab"
            case "space":
                return "Space"
            case "grave":
                return "`"
            default:
                return rawValue.uppercased()
            }
        }
        return Self.additionalDisplayNames[keyCode] ?? "Key \(keyCode)"
    }

    var modifier: KeyModifier? {
        switch Int(keyCode) {
        case kVK_Command:
            return .command
        case kVK_Control:
            return .control
        case kVK_Option:
            return .option
        case kVK_Shift:
            return .shift
        default:
            return nil
        }
    }

    var physicalKeyCodes: Set<UInt16> {
        switch Int(keyCode) {
        case kVK_Command:
            return [UInt16(kVK_Command), UInt16(kVK_RightCommand)]
        case kVK_Control:
            return [UInt16(kVK_Control), UInt16(kVK_RightControl)]
        case kVK_Option:
            return [UInt16(kVK_Option), UInt16(kVK_RightOption)]
        case kVK_Shift:
            return [UInt16(kVK_Shift), UInt16(kVK_RightShift)]
        default:
            return [keyCode]
        }
    }

    private var sortRank: Int {
        switch Int(keyCode) {
        case kVK_Command:
            return 0
        case kVK_Control:
            return 1
        case kVK_Option:
            return 2
        case kVK_Shift:
            return 3
        default:
            return 1_000 + Int(keyCode)
        }
    }

    private static let keyCodePrefix = "keyCode:"

    private static let namedKeyCodes: [String: UInt16] = [
        "command": UInt16(kVK_Command),
        "control": UInt16(kVK_Control),
        "option": UInt16(kVK_Option),
        "shift": UInt16(kVK_Shift),
        "tab": UInt16(kVK_Tab),
        "space": UInt16(kVK_Space),
        "grave": UInt16(kVK_ANSI_Grave),
        "a": UInt16(kVK_ANSI_A), "b": UInt16(kVK_ANSI_B),
        "c": UInt16(kVK_ANSI_C), "d": UInt16(kVK_ANSI_D),
        "e": UInt16(kVK_ANSI_E), "f": UInt16(kVK_ANSI_F),
        "g": UInt16(kVK_ANSI_G), "h": UInt16(kVK_ANSI_H),
        "i": UInt16(kVK_ANSI_I), "j": UInt16(kVK_ANSI_J),
        "k": UInt16(kVK_ANSI_K), "l": UInt16(kVK_ANSI_L),
        "m": UInt16(kVK_ANSI_M), "n": UInt16(kVK_ANSI_N),
        "o": UInt16(kVK_ANSI_O), "p": UInt16(kVK_ANSI_P),
        "q": UInt16(kVK_ANSI_Q), "r": UInt16(kVK_ANSI_R),
        "s": UInt16(kVK_ANSI_S), "t": UInt16(kVK_ANSI_T),
        "u": UInt16(kVK_ANSI_U), "v": UInt16(kVK_ANSI_V),
        "w": UInt16(kVK_ANSI_W), "x": UInt16(kVK_ANSI_X),
        "y": UInt16(kVK_ANSI_Y), "z": UInt16(kVK_ANSI_Z)
    ]

    private static let additionalDisplayNames: [UInt16: String] = [
        UInt16(kVK_ANSI_0): "0", UInt16(kVK_ANSI_1): "1",
        UInt16(kVK_ANSI_2): "2", UInt16(kVK_ANSI_3): "3",
        UInt16(kVK_ANSI_4): "4", UInt16(kVK_ANSI_5): "5",
        UInt16(kVK_ANSI_6): "6", UInt16(kVK_ANSI_7): "7",
        UInt16(kVK_ANSI_8): "8", UInt16(kVK_ANSI_9): "9",
        UInt16(kVK_ANSI_Minus): "-", UInt16(kVK_ANSI_Equal): "=",
        UInt16(kVK_ANSI_LeftBracket): "[", UInt16(kVK_ANSI_RightBracket): "]",
        UInt16(kVK_ANSI_Backslash): "\\", UInt16(kVK_ANSI_Semicolon): ";",
        UInt16(kVK_ANSI_Quote): "'", UInt16(kVK_ANSI_Comma): ",",
        UInt16(kVK_ANSI_Period): ".", UInt16(kVK_ANSI_Slash): "/",
        UInt16(kVK_Return): "Return", UInt16(kVK_Escape): "Escape",
        UInt16(kVK_Delete): "Delete", UInt16(kVK_ForwardDelete): "Forward Delete",
        UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_Home): "Home", UInt16(kVK_End): "End",
        UInt16(kVK_PageUp): "Page Up", UInt16(kVK_PageDown): "Page Down",
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4", UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8", UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
        UInt16(kVK_F13): "F13", UInt16(kVK_F14): "F14", UInt16(kVK_F15): "F15",
        UInt16(kVK_F16): "F16", UInt16(kVK_F17): "F17", UInt16(kVK_F18): "F18",
        UInt16(kVK_F19): "F19", UInt16(kVK_F20): "F20"
    ]

    private static func canonicalKeyCode(_ keyCode: UInt16) -> UInt16 {
        switch Int(keyCode) {
        case kVK_RightCommand:
            return UInt16(kVK_Command)
        case kVK_RightControl:
            return UInt16(kVK_Control)
        case kVK_RightOption:
            return UInt16(kVK_Option)
        case kVK_RightShift:
            return UInt16(kVK_Shift)
        default:
            return keyCode
        }
    }

    static func ordered(_ keys: Set<Self>) -> [Self] {
        keys.sorted {
            if $0.sortRank == $1.sortRank {
                return $0.rawValue < $1.rawValue
            }
            return $0.sortRank < $1.sortRank
        }
    }
}

struct SwitcherHotkeyKeySet:
    RawRepresentable,
    ExpressibleByArrayLiteral,
    Equatable,
    Hashable,
    Sendable
{
    typealias ArrayLiteralElement = SwitcherHotkeyKey

    var keys: Set<SwitcherHotkeyKey>

    init(_ keys: Set<SwitcherHotkeyKey> = []) {
        self.keys = keys
    }

    init(arrayLiteral elements: SwitcherHotkeyKey...) {
        keys = Set(elements)
    }

    init?(rawValue: String) {
        let tokens = rawValue.split(
            separator: "+",
            omittingEmptySubsequences: true
        )
        if tokens.isEmpty {
            self.init()
            return
        }
        var parsed: Set<SwitcherHotkeyKey> = []
        for token in tokens {
            guard
                let key = SwitcherHotkeyKey(
                    rawValue: token.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                )
            else {
                return nil
            }
            parsed.insert(key)
        }
        self.init(parsed)
    }

    var rawValue: String {
        orderedKeys.map(\.rawValue).joined(separator: "+")
    }

    var displayName: String {
        orderedKeys.map(\.displayName).joined(separator: " + ")
    }

    var orderedKeys: [SwitcherHotkeyKey] {
        SwitcherHotkeyKey.ordered(keys)
    }

    var isEmpty: Bool { keys.isEmpty }
    var count: Int { keys.count }

    var modifiers: KeyModifier {
        keys.reduce(into: KeyModifier()) { result, key in
            if let modifier = key.modifier {
                result.insert(modifier)
            }
        }
    }

    var nonModifierKeys: [SwitcherHotkeyKey] {
        orderedKeys.filter { $0.modifier == nil }
    }

    var physicalKeyCodes: Set<UInt16> {
        keys.reduce(into: Set<UInt16>()) { result, key in
            result.formUnion(key.physicalKeyCodes)
        }
    }

    var physicalKeyCodeGroups: [Set<UInt16>] {
        orderedKeys.map(\.physicalKeyCodes)
    }

    func contains(_ key: SwitcherHotkeyKey) -> Bool {
        keys.contains(key)
    }

    func union(_ other: Self) -> Self {
        Self(keys.union(other.keys))
    }

    func intersection(_ other: Self) -> Self {
        Self(keys.intersection(other.keys))
    }

    func subtracting(_ other: Self) -> Self {
        Self(keys.subtracting(other.keys))
    }

    func isDisjoint(with other: Self) -> Bool {
        keys.isDisjoint(with: other.keys)
    }

    func isSubset(of other: Self) -> Bool {
        keys.isSubset(of: other.keys)
    }

    mutating func insert(_ key: SwitcherHotkeyKey) {
        keys.insert(key)
    }

    mutating func remove(_ key: SwitcherHotkeyKey) {
        keys.remove(key)
    }

    mutating func replaceModifiers(with modifiers: KeyModifier) {
        keys.subtract(
            Set(keys.filter { $0.modifier != nil })
        )
        keys.formUnion(modifiers.hotkeyKeys.keys)
    }
}

extension KeyModifier {
    var hotkeyKeys: SwitcherHotkeyKeySet {
        var keys: Set<SwitcherHotkeyKey> = []
        if contains(.command) { keys.insert(.command) }
        if contains(.control) { keys.insert(.control) }
        if contains(.option) { keys.insert(.option) }
        if contains(.shift) { keys.insert(.shift) }
        return SwitcherHotkeyKeySet(keys)
    }
}

struct SwitcherHotkeyShortcut: Equatable, Hashable, Sendable {
    struct CarbonRegistration: Equatable, Sendable {
        let keyCode: UInt32
        let modifiers: UInt32
    }

    let keys: SwitcherHotkeyKeySet

    init(keys: SwitcherHotkeyKeySet) {
        precondition(!keys.isEmpty, "A shortcut requires at least one key")
        self.keys = keys
    }

    var modifiers: KeyModifier {
        keys.modifiers
    }

    var displayName: String {
        keys.displayName
    }

    var carbonRegistration: CarbonRegistration? {
        guard keys.nonModifierKeys.count == 1 else { return nil }
        let key = keys.nonModifierKeys[0]
        return CarbonRegistration(
            keyCode: UInt32(key.keyCode),
            modifiers: modifiers.carbonModifiers
        )
    }
}

struct SwitcherHotkeyConfiguration: Equatable, Sendable {
    let baseKeys: SwitcherHotkeyKeySet
    let reverseKeys: SwitcherHotkeyKeySet
    let mainKeys: SwitcherHotkeyKeySet
    let quitKeys: SwitcherHotkeyKeySet

    init(
        baseKeys: SwitcherHotkeyKeySet,
        reverseKeys: SwitcherHotkeyKeySet,
        mainKeys: SwitcherHotkeyKeySet,
        quitKeys: SwitcherHotkeyKeySet
    ) {
        precondition(!baseKeys.isEmpty, "Base keys must not be empty")
        precondition(!reverseKeys.isEmpty, "Reverse keys must not be empty")
        precondition(!quitKeys.isEmpty, "Quit keys must not be empty")
        self.baseKeys = baseKeys
        self.reverseKeys = reverseKeys
        self.mainKeys = mainKeys
        self.quitKeys = quitKeys
    }

    var mainShortcut: SwitcherHotkeyShortcut {
        SwitcherHotkeyShortcut(keys: baseKeys.union(mainKeys))
    }

    var backwardShortcut: SwitcherHotkeyShortcut {
        SwitcherHotkeyShortcut(
            keys: baseKeys.union(reverseKeys).union(mainKeys)
        )
    }

    var quitShortcut: SwitcherHotkeyShortcut {
        SwitcherHotkeyShortcut(keys: baseKeys.union(quitKeys))
    }

    var switchingShortcuts: Set<SwitcherHotkeyShortcut> {
        [mainShortcut, backwardShortcut]
    }

    var reservedShortcuts: Set<SwitcherHotkeyShortcut> {
        switchingShortcuts.union([quitShortcut])
    }

    var supportsCarbonRegistration: Bool {
        mainShortcut.carbonRegistration != nil
            && backwardShortcut.carbonRegistration != nil
    }

    var mainFamilyHasDuplicateKeys: Bool {
        let fields = [baseKeys, reverseKeys, mainKeys, quitKeys]
        for index in fields.indices {
            for otherIndex in fields.indices where otherIndex > index {
                if !fields[index].isDisjoint(with: fields[otherIndex]) {
                    return true
                }
            }
        }
        return false
    }

    var mainShortcutText: String {
        mainShortcut.displayName
    }

    var backwardShortcutText: String {
        backwardShortcut.displayName
    }

    var quitShortcutText: String {
        quitShortcut.displayName
    }

    var usesCommandTab: Bool {
        switchingShortcuts.contains { shortcut in
            guard shortcut.keys.contains(.tab) else { return false }
            return shortcut.modifiers == [.command]
                || shortcut.modifiers == [.command, .shift]
        }
    }

    static func inApp(
        shortcutKeys: SwitcherHotkeyKeySet,
        reverseKeys: SwitcherHotkeyKeySet
    ) -> Self {
        Self(
            baseKeys: shortcutKeys,
            reverseKeys: reverseKeys,
            mainKeys: [],
            quitKeys: [.q]
        )
    }
}
