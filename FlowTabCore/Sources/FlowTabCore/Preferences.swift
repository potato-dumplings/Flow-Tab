import Foundation

public struct KeyModifier: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let command = KeyModifier(rawValue: 1 << 0)
    public static let shift = KeyModifier(rawValue: 1 << 1)
    public static let option = KeyModifier(rawValue: 1 << 2)
    public static let control = KeyModifier(rawValue: 1 << 3)
}

public struct Hotkey: Equatable, Hashable, Sendable {
    public let key: String
    public let modifiers: KeyModifier

    public init(key: String, modifiers: KeyModifier) {
        self.key = key
        self.modifiers = modifiers
    }

    public static let commandTab = Hotkey(key: "tab", modifiers: [.command])
    public static let optionTab = Hotkey(key: "tab", modifiers: [.option])
}

public enum ThemeMode: String, Equatable, Sendable, CaseIterable {
    case light
    case dark
    case followSystem
}

public enum WindowSwitchingStrategy: String, Equatable, Sendable, CaseIterable {
    case recentActiveWindow
    case rememberLastSelectedWindow
}

public struct SwitcherPreferences: Equatable, Sendable {
    public var autoRestoreMinimizedWindowOnSwitch: Bool
    public var mainSwitcherHotkey: Hotkey
    public var allowOverrideCommandTab: Bool
    public var windowSwitchingStrategy: WindowSwitchingStrategy
    public var groupNavigationWraps: Bool
    public var themeMode: ThemeMode

    public init(
        autoRestoreMinimizedWindowOnSwitch: Bool,
        mainSwitcherHotkey: Hotkey,
        allowOverrideCommandTab: Bool,
        windowSwitchingStrategy: WindowSwitchingStrategy,
        groupNavigationWraps: Bool,
        themeMode: ThemeMode
    ) {
        self.autoRestoreMinimizedWindowOnSwitch = autoRestoreMinimizedWindowOnSwitch
        self.mainSwitcherHotkey = mainSwitcherHotkey
        self.allowOverrideCommandTab = allowOverrideCommandTab
        self.windowSwitchingStrategy = windowSwitchingStrategy
        self.groupNavigationWraps = groupNavigationWraps
        self.themeMode = themeMode
    }

    public static let `default` = SwitcherPreferences(
        autoRestoreMinimizedWindowOnSwitch: true,
        mainSwitcherHotkey: .optionTab,
        allowOverrideCommandTab: true,
        windowSwitchingStrategy: .recentActiveWindow,
        groupNavigationWraps: true,
        themeMode: .followSystem
    )
}
