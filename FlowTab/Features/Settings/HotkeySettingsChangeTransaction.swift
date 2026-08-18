enum HotkeySettingsConflict: String, Equatable, Sendable {
    case mainAndReverseModifier = "main_and_reverse_modifier"
    case mainFamilyDuplicateKey = "main_family_duplicate_key"
    case mainAndQuit = "main_and_quit"
    case mainAndInApp = "main_and_in_app"
    case quitAndInApp = "quit_and_in_app"
    case inAppAndReverseModifier = "in_app_and_reverse_modifier"
}

enum HotkeySettingsField: String, CaseIterable, Equatable, Hashable, Sendable {
    case mainModifiers = "main_modifiers"
    case mainReverseModifiers = "main_reverse_modifiers"
    case mainKey = "main_key"
    case quitKey = "quit_key"
    case inAppShortcut = "in_app_shortcut"
    case inAppReverseModifiers = "in_app_reverse_modifiers"
}

struct HotkeySettingsChangeCandidate: Equatable {
    let field: HotkeySettingsField
    let values: AppKitSettingsHotkeyRawValues
}

struct HotkeySettingsConflictPresentation: Equatable, Sendable {
    let field: HotkeySettingsField
    let conflict: HotkeySettingsConflict
}

enum HotkeySettingsChangeResult: Equatable {
    case applied(HotkeyRegistrationRequest)
    case conflict(HotkeySettingsConflict)
}

enum HotkeySettingsChangeTransaction {
    static func apply(
        _ values: AppKitSettingsHotkeyRawValues,
        commit: (HotkeyRegistrationRequest) -> Void
    ) -> HotkeySettingsChangeResult {
        let mainConfiguration = SwitcherHotkeyPreferencesStore.resolveCandidate(
            baseKeysRaw: values.hotkeyPrimaryModifierRaw,
            reverseKeysRaw: values.hotkeyReverseModifiersRaw,
            mainKeysRaw: values.hotkeyMainKeyRaw,
            quitKeysRaw: values.hotkeyQuitKeyRaw
        )
        let resolvedInAppConfiguration = InAppWindowHotkeyPreferencesStore.resolveCandidate(
            shortcutKeysRaw: values.inAppWindowHotkeyShortcutKeysRaw,
            reverseKeysRaw: values.inAppWindowHotkeyReverseKeysRaw
        )
        let inAppConfiguration = resolvedInAppConfiguration.configuration

        if !mainConfiguration.baseKeys.isDisjoint(
            with: mainConfiguration.reverseKeys
        )
        {
            return .conflict(.mainAndReverseModifier)
        }
        if !mainConfiguration.mainKeys.isDisjoint(
            with: mainConfiguration.quitKeys
        )
        {
            return .conflict(.mainAndQuit)
        }
        if mainConfiguration.mainFamilyHasDuplicateKeys {
            return .conflict(.mainFamilyDuplicateKey)
        }
        if !inAppConfiguration.baseKeys.isDisjoint(
            with: inAppConfiguration.reverseKeys
        )
        {
            return .conflict(.inAppAndReverseModifier)
        }

        let mainSwitchingShortcuts = mainConfiguration.switchingShortcuts
        let inAppSwitchingShortcuts = inAppConfiguration.switchingShortcuts

        if !mainSwitchingShortcuts.isDisjoint(with: inAppSwitchingShortcuts) {
            return .conflict(.mainAndInApp)
        }
        if inAppSwitchingShortcuts.contains(mainConfiguration.quitShortcut) {
            return .conflict(.quitAndInApp)
        }

        let request = HotkeyRegistrationRequest(
            mainConfiguration: mainConfiguration,
            inAppWindowConfiguration: inAppConfiguration
        )
        commit(request)
        return .applied(request)
    }
}
