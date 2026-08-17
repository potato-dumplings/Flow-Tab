enum HotkeySettingsConflict: String, Equatable, Sendable {
    case mainAndQuit = "main_and_quit"
    case mainAndInApp = "main_and_in_app"
    case quitAndInApp = "quit_and_in_app"
}

enum HotkeySettingsField: String, CaseIterable, Equatable, Hashable, Sendable {
    case mainModifier = "main_modifier"
    case mainKey = "main_key"
    case quitKey = "quit_key"
    case inAppModifier = "in_app_modifier"
    case inAppKey = "in_app_key"
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
            primaryModifierRaw: values.hotkeyPrimaryModifierRaw,
            mainKeyRaw: values.hotkeyMainKeyRaw,
            quitKeyRaw: values.hotkeyQuitKeyRaw
        )
        let resolvedInAppConfiguration = InAppWindowHotkeyPreferencesStore.resolve(
            primaryModifierRaw: values.inAppWindowHotkeyPrimaryModifierRaw,
            mainKeyRaw: values.inAppWindowHotkeyMainKeyRaw
        )
        let inAppConfiguration = SwitcherHotkeyConfiguration(
            primaryModifier: resolvedInAppConfiguration.primaryModifier,
            mainKey: resolvedInAppConfiguration.mainKey,
            quitKey: .q
        )

        if mainConfiguration.mainKey == mainConfiguration.quitKey {
            return .conflict(.mainAndQuit)
        }
        if mainConfiguration.primaryModifier == inAppConfiguration.primaryModifier {
            if mainConfiguration.mainKey == inAppConfiguration.mainKey {
                return .conflict(.mainAndInApp)
            }
            if mainConfiguration.quitKey == inAppConfiguration.mainKey {
                return .conflict(.quitAndInApp)
            }
        }

        let request = HotkeyRegistrationRequest(
            mainConfiguration: mainConfiguration,
            inAppWindowConfiguration: inAppConfiguration
        )
        commit(request)
        return .applied(request)
    }
}
