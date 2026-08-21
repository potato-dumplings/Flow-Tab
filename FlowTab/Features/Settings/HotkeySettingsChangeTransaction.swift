enum HotkeySettingsConflict: String, Equatable, Sendable {
    case mainAndReverseModifier = "main_and_reverse_modifier"
    case mainFamilyDuplicateKey = "main_family_duplicate_key"
    case mainAndQuit = "main_and_quit"
    case mainAndInApp = "main_and_in_app"
    case quitAndInApp = "quit_and_in_app"
    case inAppFamilyDuplicateKey = "in_app_family_duplicate_key"
}

enum HotkeySettingsField: String, CaseIterable, Equatable, Hashable, Sendable {
    case mainModifiers = "main_modifiers"
    case mainReverseModifiers = "main_reverse_modifiers"
    case mainKey = "main_key"
    case quitKey = "quit_key"
    case inAppBaseKeys = "in_app_base_keys"
    case inAppReverseModifiers = "in_app_reverse_modifiers"
    case inAppMainKeys = "in_app_main_keys"
}

struct HotkeySettingsChangeCandidate: Equatable {
    let field: HotkeySettingsField
    let values: AppKitSettingsHotkeyRawValues
}

struct HotkeySettingsConflictPresentation: Equatable, Sendable {
    let field: HotkeySettingsField
    let conflict: HotkeySettingsConflict
}

struct HotkeySettingsPermissionPresentation: Equatable, Sendable {
    let field: HotkeySettingsField
}

enum HotkeySettingsChangeResult: Equatable {
    case applied(HotkeyRegistrationRequest)
    case conflict(HotkeySettingsConflict)
    case accessibilityRequired
}

enum HotkeySettingsPermissionlessFieldPolicy {
    static func allows(
        keys: SwitcherHotkeyKeySet,
        for field: HotkeySettingsField
    ) -> Bool {
        switch field {
        case .mainModifiers, .mainReverseModifiers:
            return !keys.isEmpty && keys.nonModifierKeys.isEmpty
        case .mainKey:
            return keys.nonModifierKeys.count == 1
        case .quitKey, .inAppBaseKeys, .inAppReverseModifiers,
             .inAppMainKeys:
            return true
        }
    }

    static func allows(
        configuration: SwitcherHotkeyConfiguration,
        for field: HotkeySettingsField
    ) -> Bool {
        allows(keys: keys(in: configuration, for: field), for: field)
    }

    static func fieldsRequiringAccessibility(
        in configuration: SwitcherHotkeyConfiguration
    ) -> Set<HotkeySettingsField> {
        Set(
            [
                HotkeySettingsField.mainModifiers,
                .mainReverseModifiers,
                .mainKey
            ].filter {
                !allows(configuration: configuration, for: $0)
            }
        )
    }

    private static func keys(
        in configuration: SwitcherHotkeyConfiguration,
        for field: HotkeySettingsField
    ) -> SwitcherHotkeyKeySet {
        switch field {
        case .mainModifiers:
            return configuration.baseKeys
        case .mainReverseModifiers:
            return configuration.reverseKeys
        case .mainKey:
            return configuration.mainKeys
        case .quitKey:
            return configuration.quitKeys
        case .inAppBaseKeys, .inAppReverseModifiers, .inAppMainKeys:
            return SwitcherHotkeyKeySet()
        }
    }
}

enum HotkeySettingsChangeTransaction {
    static func apply(
        _ values: AppKitSettingsHotkeyRawValues,
        commit: (HotkeyRegistrationRequest) -> Void
    ) -> HotkeySettingsChangeResult {
        apply(
            values,
            changedField: nil,
            accessibilityTrusted: true,
            commit: commit
        )
    }

    static func apply(
        _ candidate: HotkeySettingsChangeCandidate,
        accessibilityTrusted: Bool,
        commit: (HotkeyRegistrationRequest) -> Void
    ) -> HotkeySettingsChangeResult {
        apply(
            candidate.values,
            changedField: candidate.field,
            accessibilityTrusted: accessibilityTrusted,
            commit: commit
        )
    }

    private static func apply(
        _ values: AppKitSettingsHotkeyRawValues,
        changedField: HotkeySettingsField?,
        accessibilityTrusted: Bool,
        commit: (HotkeyRegistrationRequest) -> Void
    ) -> HotkeySettingsChangeResult {
        let mainConfiguration = SwitcherHotkeyPreferencesStore.resolveCandidate(
            baseKeysRaw: values.hotkeyPrimaryModifierRaw,
            reverseKeysRaw: values.hotkeyReverseModifiersRaw,
            mainKeysRaw: values.hotkeyMainKeyRaw,
            quitKeysRaw: values.hotkeyQuitKeyRaw
        )
        let resolvedInAppConfiguration = InAppWindowHotkeyPreferencesStore.resolveCandidate(
            baseKeysRaw: values.inAppWindowHotkeyBaseKeysRaw,
            reverseKeysRaw: values.inAppWindowHotkeyReverseKeysRaw,
            mainKeysRaw: values.inAppWindowHotkeyMainKeysRaw
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
        let inAppFields = [
            inAppConfiguration.baseKeys,
            inAppConfiguration.reverseKeys,
            inAppConfiguration.mainKeys
        ]
        for index in inAppFields.indices {
            for otherIndex in inAppFields.indices
            where otherIndex > index
            {
                if !inAppFields[index].isDisjoint(
                    with: inAppFields[otherIndex]
                ) {
                    return .conflict(.inAppFamilyDuplicateKey)
                }
            }
        }

        let mainSwitchingShortcuts = mainConfiguration.switchingShortcuts
        let inAppSwitchingShortcuts = inAppConfiguration.switchingShortcuts

        if !mainSwitchingShortcuts.isDisjoint(with: inAppSwitchingShortcuts) {
            return .conflict(.mainAndInApp)
        }
        if inAppSwitchingShortcuts.contains(mainConfiguration.quitShortcut) {
            return .conflict(.quitAndInApp)
        }

        if let changedField,
           !accessibilityTrusted,
           !HotkeySettingsPermissionlessFieldPolicy.allows(
                configuration: mainConfiguration,
                for: changedField
           )
        {
            return .accessibilityRequired
        }

        let request = HotkeyRegistrationRequest(
            mainConfiguration: mainConfiguration,
            inAppWindowConfiguration: inAppConfiguration
        )
        commit(request)
        return .applied(request)
    }
}
