import Foundation
import FlowTabCore

enum AppPreferenceKeys {
    static let showShortcutHint = "showShortcutHint"
    static let showInCommandTab = "showInCommandTab"
    static let showPermissionReminder = "showPermissionReminder"
    static let allowLaunchAtLogin = "allowLaunchAtLogin"
    static let hasPromptedAccessibilityPermission = "hasPromptedAccessibilityPermission"
    static let hiddenAppIDs = "hiddenAppIDs"
    static let hotkeyPrimaryModifier = "hotkeyPrimaryModifier"
    static let hotkeyMainKey = "hotkeyMainKey"
    static let hotkeyQuitKey = "hotkeyQuitKey"
    static let inAppWindowHotkeyPrimaryModifier = "inAppWindowHotkeyPrimaryModifier"
    static let inAppWindowHotkeyMainKey = "inAppWindowHotkeyMainKey"
    static let windowLayerAutoEnterDelay = "windowLayerAutoEnterDelay"
    static let autoRestoreMinimizedWindowOnSwitch = "autoRestoreMinimizedWindowOnSwitch"
    static let hideMinimizedAppsFromAppLayer = "hideMinimizedAppsFromAppLayer"
    static let searchEnabled = "searchEnabled"
    static let searchDefaultScope = "searchDefaultScope"
    static let enableVerboseDiagnostics = "enableVerboseDiagnostics"
    static let diagnosticSessionExpiration = "diagnosticSessionExpiration"
    static let runtimeLogLevel = "runtimeLogLevel"
    static let themeMode = "themeMode"
    static let appLanguage = "appLanguage"

    static let allKeys: [String] = [
        showShortcutHint,
        showInCommandTab,
        showPermissionReminder,
        allowLaunchAtLogin,
        hasPromptedAccessibilityPermission,
        hiddenAppIDs,
        hotkeyPrimaryModifier,
        hotkeyMainKey,
        hotkeyQuitKey,
        inAppWindowHotkeyPrimaryModifier,
        inAppWindowHotkeyMainKey,
        windowLayerAutoEnterDelay,
        autoRestoreMinimizedWindowOnSwitch,
        hideMinimizedAppsFromAppLayer,
        searchEnabled,
        searchDefaultScope,
        enableVerboseDiagnostics,
        diagnosticSessionExpiration,
        runtimeLogLevel,
        themeMode,
        appLanguage
    ]
}

enum AppLanguage: String, CaseIterable, Equatable, Sendable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .simplifiedChinese:
            return "简体中文"
        case .english:
            return "English"
        }
    }
}

enum AppLanguagePreferencesStore {
    static let defaultLanguage: AppLanguage = .simplifiedChinese

    static func resolve(rawValue: String) -> AppLanguage {
        AppLanguage(rawValue: rawValue) ?? defaultLanguage
    }

    static func load(userDefaults: UserDefaults = .standard) -> AppLanguage {
        let rawValue = userDefaults.string(forKey: AppPreferenceKeys.appLanguage)
            ?? defaultLanguage.rawValue
        let resolved = resolve(rawValue: rawValue)
        if rawValue != resolved.rawValue {
            userDefaults.set(resolved.rawValue, forKey: AppPreferenceKeys.appLanguage)
        }
        return resolved
    }
}

extension Notification.Name {
    static let flowTabReRegisterHotkeys = Notification.Name("FlowTab.ReRegisterHotkeys")
    static let flowTabAppVisibilityPreferenceChanged = Notification.Name(
        "FlowTab.AppVisibilityPreferenceChanged"
    )
    static let flowTabLanguagePreferenceChanged = Notification.Name(
        "FlowTab.LanguagePreferenceChanged"
    )
}

struct HotkeyRegistrationRequest: Sendable {
    private enum NotificationUserInfoKey {
        static let requestID = "requestID"
        static let mainPrimaryModifier = "mainPrimaryModifier"
        static let mainKey = "mainKey"
        static let quitKey = "quitKey"
        static let inAppPrimaryModifier = "inAppPrimaryModifier"
        static let inAppMainKey = "inAppMainKey"
    }

    let requestID: UUID
    let mainConfiguration: SwitcherHotkeyConfiguration
    let inAppWindowConfiguration: SwitcherHotkeyConfiguration

    init(
        requestID: UUID = UUID(),
        mainConfiguration: SwitcherHotkeyConfiguration,
        inAppWindowConfiguration: SwitcherHotkeyConfiguration
    ) {
        let resolvedInAppWindowConfiguration =
            InAppWindowHotkeyPreferencesStore.resolveAvoidingMainHotkeyConflict(
                primaryModifierRaw: inAppWindowConfiguration.primaryModifier.rawValue,
                mainKeyRaw: inAppWindowConfiguration.mainKey.rawValue,
                mainHotkeyConfiguration: mainConfiguration
            )
        self.requestID = requestID
        self.mainConfiguration = mainConfiguration
        self.inAppWindowConfiguration = SwitcherHotkeyConfiguration(
            primaryModifier: resolvedInAppWindowConfiguration.primaryModifier,
            mainKey: resolvedInAppWindowConfiguration.mainKey,
            quitKey: inAppWindowConfiguration.quitKey
        )
    }

    static func load(userDefaults: UserDefaults = .standard) -> HotkeyRegistrationRequest {
        let mainPrimaryModifierRaw = userDefaults.string(forKey: AppPreferenceKeys.hotkeyPrimaryModifier)
            ?? SwitcherHotkeyPreferencesStore.defaultPrimaryModifier.rawValue
        let mainKeyRaw = userDefaults.string(forKey: AppPreferenceKeys.hotkeyMainKey)
            ?? SwitcherHotkeyPreferencesStore.defaultMainKey.rawValue
        let quitKeyRaw = userDefaults.string(forKey: AppPreferenceKeys.hotkeyQuitKey)
            ?? SwitcherHotkeyPreferencesStore.defaultQuitKey.rawValue
        let inAppPrimaryModifierRaw = userDefaults.string(forKey: AppPreferenceKeys.inAppWindowHotkeyPrimaryModifier)
            ?? InAppWindowHotkeyPreferencesStore.defaultPrimaryModifier.rawValue
        let inAppMainKeyRaw = userDefaults.string(forKey: AppPreferenceKeys.inAppWindowHotkeyMainKey)
            ?? InAppWindowHotkeyPreferencesStore.defaultMainKey.rawValue

        let request = HotkeyRegistrationRequest.normalized(
            mainPrimaryModifierRaw: mainPrimaryModifierRaw,
            mainKeyRaw: mainKeyRaw,
            quitKeyRaw: quitKeyRaw,
            inAppPrimaryModifierRaw: inAppPrimaryModifierRaw,
            inAppMainKeyRaw: inAppMainKeyRaw
        )
        persistNormalizedValue(
            request.mainConfiguration.primaryModifier.rawValue,
            rawValue: mainPrimaryModifierRaw,
            forKey: AppPreferenceKeys.hotkeyPrimaryModifier,
            userDefaults: userDefaults
        )
        persistNormalizedValue(
            request.mainConfiguration.mainKey.rawValue,
            rawValue: mainKeyRaw,
            forKey: AppPreferenceKeys.hotkeyMainKey,
            userDefaults: userDefaults
        )
        persistNormalizedValue(
            request.mainConfiguration.quitKey.rawValue,
            rawValue: quitKeyRaw,
            forKey: AppPreferenceKeys.hotkeyQuitKey,
            userDefaults: userDefaults
        )
        persistNormalizedValue(
            request.inAppWindowConfiguration.primaryModifier.rawValue,
            rawValue: inAppPrimaryModifierRaw,
            forKey: AppPreferenceKeys.inAppWindowHotkeyPrimaryModifier,
            userDefaults: userDefaults
        )
        persistNormalizedValue(
            request.inAppWindowConfiguration.mainKey.rawValue,
            rawValue: inAppMainKeyRaw,
            forKey: AppPreferenceKeys.inAppWindowHotkeyMainKey,
            userDefaults: userDefaults
        )
        return request
    }

    static func normalized(
        mainPrimaryModifierRaw: String,
        mainKeyRaw: String,
        quitKeyRaw: String,
        inAppPrimaryModifierRaw: String,
        inAppMainKeyRaw: String
    ) -> HotkeyRegistrationRequest {
        let mainConfiguration = SwitcherHotkeyPreferencesStore.resolve(
            primaryModifierRaw: mainPrimaryModifierRaw,
            mainKeyRaw: mainKeyRaw,
            quitKeyRaw: quitKeyRaw
        )
        let resolvedInAppWindowConfiguration =
            InAppWindowHotkeyPreferencesStore.resolveAvoidingMainHotkeyConflict(
                primaryModifierRaw: inAppPrimaryModifierRaw,
                mainKeyRaw: inAppMainKeyRaw,
                mainHotkeyConfiguration: mainConfiguration
            )
        let inAppWindowConfiguration = SwitcherHotkeyConfiguration(
            primaryModifier: resolvedInAppWindowConfiguration.primaryModifier,
            mainKey: resolvedInAppWindowConfiguration.mainKey,
            quitKey: .q
        )
        return HotkeyRegistrationRequest(
            mainConfiguration: mainConfiguration,
            inAppWindowConfiguration: inAppWindowConfiguration
        )
    }

    private static func persistNormalizedValue(
        _ value: String,
        rawValue: String,
        forKey key: String,
        userDefaults: UserDefaults
    ) {
        if rawValue != value {
            userDefaults.set(value, forKey: key)
        }
    }

    init?(notificationUserInfo: [AnyHashable: Any]) {
        guard
            let requestIDRaw = notificationUserInfo[NotificationUserInfoKey.requestID] as? String,
            let mainPrimaryModifierRaw =
                notificationUserInfo[NotificationUserInfoKey.mainPrimaryModifier] as? String,
            let mainKeyRaw = notificationUserInfo[NotificationUserInfoKey.mainKey] as? String,
            let quitKeyRaw = notificationUserInfo[NotificationUserInfoKey.quitKey] as? String,
            let inAppPrimaryModifierRaw =
                notificationUserInfo[NotificationUserInfoKey.inAppPrimaryModifier] as? String,
            let inAppMainKeyRaw = notificationUserInfo[NotificationUserInfoKey.inAppMainKey] as? String
        else {
            return nil
        }

        let resolvedInAppWindowConfiguration = InAppWindowHotkeyPreferencesStore.resolve(
            primaryModifierRaw: inAppPrimaryModifierRaw,
            mainKeyRaw: inAppMainKeyRaw
        )
        self.init(
            requestID: UUID(uuidString: requestIDRaw) ?? UUID(),
            mainConfiguration: SwitcherHotkeyPreferencesStore.resolve(
                primaryModifierRaw: mainPrimaryModifierRaw,
                mainKeyRaw: mainKeyRaw,
                quitKeyRaw: quitKeyRaw
            ),
            inAppWindowConfiguration: SwitcherHotkeyConfiguration(
                primaryModifier: resolvedInAppWindowConfiguration.primaryModifier,
                mainKey: resolvedInAppWindowConfiguration.mainKey,
                quitKey: .q
            )
        )
    }

    var notificationUserInfo: [AnyHashable: Any] {
        [
            NotificationUserInfoKey.requestID: requestID.uuidString,
            NotificationUserInfoKey.mainPrimaryModifier: mainConfiguration.primaryModifier.rawValue,
            NotificationUserInfoKey.mainKey: mainConfiguration.mainKey.rawValue,
            NotificationUserInfoKey.quitKey: mainConfiguration.quitKey.rawValue,
            NotificationUserInfoKey.inAppPrimaryModifier:
                inAppWindowConfiguration.primaryModifier.rawValue,
            NotificationUserInfoKey.inAppMainKey: inAppWindowConfiguration.mainKey.rawValue
        ]
    }
}

enum ThemePreferencesStore {
    static let defaultMode: ThemeMode = .followSystem

    static func resolve(rawValue: String) -> ThemeMode {
        ThemeMode(rawValue: rawValue) ?? defaultMode
    }
}

enum AppVisibilityPreferencesStore {
    static let defaultShowInCommandTab = false

    static func currentAppID() -> String {
        Bundle.main.bundleIdentifier ?? "pid:\(ProcessInfo.processInfo.processIdentifier)"
    }

    static func loadShowInCommandTab(userDefaults: UserDefaults = .standard) -> Bool {
        guard userDefaults.object(forKey: AppPreferenceKeys.showInCommandTab) != nil else {
            return defaultShowInCommandTab
        }
        return userDefaults.bool(forKey: AppPreferenceKeys.showInCommandTab)
    }

    static func loadHiddenAppIDs(userDefaults: UserDefaults = .standard) -> Set<String> {
        let hiddenAppIDs = loadStoredHiddenAppIDs(userDefaults: userDefaults)
        let effectiveHiddenAppIDs = hiddenAppIDsWithCurrentAppPolicy(
            hiddenAppIDs,
            userDefaults: userDefaults
        )
        if effectiveHiddenAppIDs != hiddenAppIDs {
            saveStoredHiddenAppIDs(effectiveHiddenAppIDs, userDefaults: userDefaults)
        }
        return effectiveHiddenAppIDs
    }

    private static func loadStoredHiddenAppIDs(userDefaults: UserDefaults) -> Set<String> {
        let rawIDs = userDefaults.stringArray(forKey: AppPreferenceKeys.hiddenAppIDs) ?? []
        let normalizedIDs = AppVisibilityFilter.normalizedHiddenAppIDs(rawIDs)
        if rawIDs != normalizedIDs {
            userDefaults.set(normalizedIDs, forKey: AppPreferenceKeys.hiddenAppIDs)
        }
        return Set(normalizedIDs)
    }

    static func saveHiddenAppIDs(
        _ hiddenAppIDs: Set<String>,
        userDefaults: UserDefaults = .standard
    ) {
        saveStoredHiddenAppIDs(
            hiddenAppIDsWithCurrentAppPolicy(hiddenAppIDs, userDefaults: userDefaults),
            userDefaults: userDefaults
        )
    }

    private static func saveStoredHiddenAppIDs(
        _ hiddenAppIDs: Set<String>,
        userDefaults: UserDefaults
    ) {
        userDefaults.set(
            AppVisibilityFilter.normalizedHiddenAppIDs(Array(hiddenAppIDs)),
            forKey: AppPreferenceKeys.hiddenAppIDs
        )
    }

    static func setAppHidden(
        _ isHidden: Bool,
        appID: String,
        userDefaults: UserDefaults = .standard
    ) {
        guard let normalizedAppID = AppVisibilityFilter.normalizedAppID(appID) else { return }
        var hiddenAppIDs = loadStoredHiddenAppIDs(userDefaults: userDefaults)
        if isCurrentAppID(normalizedAppID) {
            userDefaults.set(!isHidden, forKey: AppPreferenceKeys.showInCommandTab)
        }
        if isHidden {
            hiddenAppIDs.insert(normalizedAppID)
        } else {
            hiddenAppIDs.remove(normalizedAppID)
        }
        saveHiddenAppIDs(hiddenAppIDs, userDefaults: userDefaults)
    }

    static func visibilityFilter(userDefaults: UserDefaults = .standard) -> AppVisibilityFilter {
        AppVisibilityFilter(hiddenAppIDs: loadHiddenAppIDs(userDefaults: userDefaults))
    }

    private static func hiddenAppIDsWithCurrentAppPolicy(
        _ hiddenAppIDs: Set<String>,
        userDefaults: UserDefaults
    ) -> Set<String> {
        var effectiveHiddenAppIDs = hiddenAppIDs
        let normalizedCurrentAppID = AppVisibilityFilter.normalizedAppID(currentAppID())
        guard let normalizedCurrentAppID else { return effectiveHiddenAppIDs }

        if loadShowInCommandTab(userDefaults: userDefaults) {
            effectiveHiddenAppIDs.remove(normalizedCurrentAppID)
        } else {
            effectiveHiddenAppIDs.insert(normalizedCurrentAppID)
        }
        return effectiveHiddenAppIDs
    }

    private static func isCurrentAppID(_ appID: String) -> Bool {
        guard let normalizedCurrentAppID = AppVisibilityFilter.normalizedAppID(currentAppID()) else {
            return false
        }
        return appID == normalizedCurrentAppID
    }
}

enum LaunchAtLoginPreferencesStore {
    static let defaultAllowLaunchAtLogin = false

    static func loadAllowLaunchAtLogin(userDefaults: UserDefaults = .standard) -> Bool {
        guard userDefaults.object(forKey: AppPreferenceKeys.allowLaunchAtLogin) != nil else {
            return defaultAllowLaunchAtLogin
        }
        return userDefaults.bool(forKey: AppPreferenceKeys.allowLaunchAtLogin)
    }
}

enum WindowLayerPreferencesStore {
    static let defaultAutoEnterDelay: Double = 0.75
    static let minAutoEnterDelay: Double = 0.0
    static let maxAutoEnterDelay: Double = 999.99

    static func loadAutoEnterDelay(userDefaults: UserDefaults = .standard) -> TimeInterval {
        guard userDefaults.object(forKey: AppPreferenceKeys.windowLayerAutoEnterDelay) != nil else {
            return defaultAutoEnterDelay
        }
        return normalizedAutoEnterDelay(
            userDefaults.double(forKey: AppPreferenceKeys.windowLayerAutoEnterDelay)
        )
    }

    static func normalizedAutoEnterDelay(_ rawValue: Double) -> Double {
        guard rawValue.isFinite else { return defaultAutoEnterDelay }
        let clamped = min(max(rawValue, minAutoEnterDelay), maxAutoEnterDelay)
        return (clamped * 100).rounded() / 100
    }

    static func sanitizeAutoEnterDelayText(_ rawText: String) -> String {
        var sanitized = ""
        var hasDecimalSeparator = false
        var fractionalDigitCount = 0

        for character in rawText {
            if character.isNumber {
                if hasDecimalSeparator {
                    guard fractionalDigitCount < 2 else { continue }
                    fractionalDigitCount += 1
                }
                sanitized.append(character)
                continue
            }
            if character == ".", !hasDecimalSeparator {
                hasDecimalSeparator = true
                if sanitized.isEmpty {
                    sanitized = "0"
                }
                sanitized.append(".")
            }
        }

        if let parsedValue = Double(sanitized), parsedValue > maxAutoEnterDelay {
            return String(format: "%.2f", maxAutoEnterDelay)
        }

        return sanitized
    }
}

enum SwitcherBehaviorPreferencesStore {
    static let defaultAutoRestoreMinimizedWindowOnSwitch = false
    static let defaultHideMinimizedAppsFromAppLayer = false

    static func loadAutoRestoreMinimizedWindowOnSwitch(
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        guard userDefaults.object(forKey: AppPreferenceKeys.autoRestoreMinimizedWindowOnSwitch) != nil else {
            return defaultAutoRestoreMinimizedWindowOnSwitch
        }
        return userDefaults.bool(forKey: AppPreferenceKeys.autoRestoreMinimizedWindowOnSwitch)
    }

    static func loadHideMinimizedAppsFromAppLayer(
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        guard userDefaults.object(forKey: AppPreferenceKeys.hideMinimizedAppsFromAppLayer) != nil else {
            return defaultHideMinimizedAppsFromAppLayer
        }
        return userDefaults.bool(forKey: AppPreferenceKeys.hideMinimizedAppsFromAppLayer)
    }

    static func loadSwitcherPreferences(userDefaults: UserDefaults = .standard) -> SwitcherPreferences {
        var preferences = SwitcherPreferences.default
        preferences.autoRestoreMinimizedWindowOnSwitch = loadAutoRestoreMinimizedWindowOnSwitch(
            userDefaults: userDefaults
        )
        return preferences
    }
}

enum SearchInteractionPreferencesStore {
    static let defaultIsEnabled = true
    static let defaultScope: SwitcherSearchScope = .app

    static func loadIsEnabled(userDefaults: UserDefaults = .standard) -> Bool {
        guard userDefaults.object(forKey: AppPreferenceKeys.searchEnabled) != nil else {
            return defaultIsEnabled
        }
        return userDefaults.bool(forKey: AppPreferenceKeys.searchEnabled)
    }

    static func loadDefaultScope(userDefaults: UserDefaults = .standard) -> SwitcherSearchScope {
        let rawValue = userDefaults.string(forKey: AppPreferenceKeys.searchDefaultScope) ?? defaultScope.rawValue
        let resolved = SwitcherSearchScope(rawValue: rawValue) ?? defaultScope
        if rawValue != resolved.rawValue {
            userDefaults.set(resolved.rawValue, forKey: AppPreferenceKeys.searchDefaultScope)
        }
        return resolved
    }

    static func availableScopes(accessibilityTrusted: Bool) -> [SwitcherSearchScope] {
        accessibilityTrusted ? SwitcherSearchScope.allCases : [.app]
    }

    static func effectiveDefaultScope(
        rawValue: String,
        accessibilityTrusted: Bool
    ) -> SwitcherSearchScope {
        let resolved = SwitcherSearchScope(rawValue: rawValue) ?? defaultScope
        return availableScopes(accessibilityTrusted: accessibilityTrusted).contains(resolved)
            ? resolved
            : .app
    }
}

enum InAppWindowHotkeyPreferencesStore {
    static let defaultPrimaryModifier: SwitcherPrimaryModifier = .control
    static let defaultMainKey: SwitcherHotkeyKey = .tab

    static func load(userDefaults: UserDefaults = .standard) -> SwitcherHotkeyConfiguration {
        let primaryModifierRaw = userDefaults.string(forKey: AppPreferenceKeys.inAppWindowHotkeyPrimaryModifier)
            ?? defaultPrimaryModifier.rawValue
        let mainKeyRaw = userDefaults.string(forKey: AppPreferenceKeys.inAppWindowHotkeyMainKey)
            ?? defaultMainKey.rawValue

        let resolved = resolve(
            primaryModifierRaw: primaryModifierRaw,
            mainKeyRaw: mainKeyRaw
        )

        if primaryModifierRaw != resolved.primaryModifier.rawValue {
            userDefaults.set(
                resolved.primaryModifier.rawValue,
                forKey: AppPreferenceKeys.inAppWindowHotkeyPrimaryModifier
            )
        }
        if mainKeyRaw != resolved.mainKey.rawValue {
            userDefaults.set(
                resolved.mainKey.rawValue,
                forKey: AppPreferenceKeys.inAppWindowHotkeyMainKey
            )
        }

        return SwitcherHotkeyConfiguration(
            primaryModifier: resolved.primaryModifier,
            mainKey: resolved.mainKey,
            quitKey: .q
        )
    }

    static func resolve(
        primaryModifierRaw: String,
        mainKeyRaw: String
    ) -> (primaryModifier: SwitcherPrimaryModifier, mainKey: SwitcherHotkeyKey) {
        let primaryModifier = SwitcherPrimaryModifier(rawValue: primaryModifierRaw) ?? defaultPrimaryModifier
        let mainKey = SwitcherHotkeyKey(rawValue: mainKeyRaw) ?? defaultMainKey
        return (primaryModifier, mainKey)
    }

    static func resolveAvoidingMainHotkeyConflict(
        primaryModifierRaw: String,
        mainKeyRaw: String,
        mainHotkeyConfiguration: SwitcherHotkeyConfiguration
    ) -> (primaryModifier: SwitcherPrimaryModifier, mainKey: SwitcherHotkeyKey) {
        let resolved = resolve(primaryModifierRaw: primaryModifierRaw, mainKeyRaw: mainKeyRaw)
        guard
            resolved.primaryModifier == mainHotkeyConfiguration.primaryModifier,
            resolved.mainKey == mainHotkeyConfiguration.mainKey
        else {
            return resolved
        }

        let candidateModifiers = [defaultPrimaryModifier] + SwitcherPrimaryModifier.allCases
        let fallbackPrimaryModifier = candidateModifiers.first {
            $0 != mainHotkeyConfiguration.primaryModifier
        } ?? defaultPrimaryModifier

        return (fallbackPrimaryModifier, resolved.mainKey)
    }
}
