import AppKit
import FlowTabCore

struct AppKitSettingsPageState: Equatable {
    let showInCommandTab: Bool
    let themeModeRaw: String
    let appLanguageRaw: String
    let windowLayerAutoEnterDelayText: String
    let autoRestoreMinimizedWindowOnSwitch: Bool
    let hideMinimizedAppsFromAppLayer: Bool
    let showPermissionReminder: Bool
    let allowLaunchAtLogin: Bool
    let searchEnabled: Bool
    let searchDefaultScopeRaw: String
    let hiddenAppCount: Int
    let hotkeyPrimaryModifierRaw: String
    var hotkeyReverseModifiersRaw =
        SwitcherHotkeyPreferencesStore.defaultReverseKeys.rawValue
    let hotkeyMainKeyRaw: String
    let hotkeyQuitKeyRaw: String
    let inAppWindowHotkeyBaseKeysRaw: String
    var inAppWindowHotkeyReverseKeysRaw =
        InAppWindowHotkeyPreferencesStore.defaultReverseKeys.rawValue
    let inAppWindowHotkeyMainKeysRaw: String
    let commandTabTakeoverRegistrationState: CommandTabTakeoverRegistrationState
    let accessibilityTrusted: Bool
    let screenCaptureTrusted: Bool
    let targetNSAppearanceName: NSAppearance.Name
    var hotkeyConflict: HotkeySettingsConflictPresentation? = nil
    var hotkeyPermissionRequirement:
        HotkeySettingsPermissionPresentation? = nil
}

struct AppKitSettingsHotkeyRawValues: Equatable {
    let hotkeyPrimaryModifierRaw: String
    var hotkeyReverseModifiersRaw =
        SwitcherHotkeyPreferencesStore.defaultReverseKeys.rawValue
    let hotkeyMainKeyRaw: String
    let hotkeyQuitKeyRaw: String
    let inAppWindowHotkeyBaseKeysRaw: String
    var inAppWindowHotkeyReverseKeysRaw =
        InAppWindowHotkeyPreferencesStore.defaultReverseKeys.rawValue
    let inAppWindowHotkeyMainKeysRaw: String
}
