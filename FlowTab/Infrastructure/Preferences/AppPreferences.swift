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
    static let hotkeyReverseModifiers = "hotkeyReverseModifiers"
    static let hotkeyMainKey = "hotkeyMainKey"
    static let hotkeyQuitKey = "hotkeyQuitKey"
    static let inAppWindowHotkeyShortcutKeys = "inAppWindowHotkeyShortcutKeys"
    static let inAppWindowHotkeyReverseKeys = "inAppWindowHotkeyReverseKeys"
    static let windowLayerAutoEnterDelay = "windowLayerAutoEnterDelay"
    static let autoRestoreMinimizedWindowOnSwitch = "autoRestoreMinimizedWindowOnSwitch"
    static let hideMinimizedAppsFromAppLayer = "hideMinimizedAppsFromAppLayer"
    static let searchEnabled = "searchEnabled"
    static let searchDefaultScope = "searchDefaultScope"
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
        hotkeyReverseModifiers,
        hotkeyMainKey,
        hotkeyQuitKey,
        inAppWindowHotkeyShortcutKeys,
        inAppWindowHotkeyReverseKeys,
        windowLayerAutoEnterDelay,
        autoRestoreMinimizedWindowOnSwitch,
        hideMinimizedAppsFromAppLayer,
        searchEnabled,
        searchDefaultScope,
        runtimeLogLevel,
        themeMode,
        appLanguage
    ]
}

enum AppPreferenceMaintenance {
    private static let retiredKeys = [
        "enableVerboseDiagnostics",
        "diagnosticSessionExpiration"
    ]

    static func removeRetiredValues(userDefaults: UserDefaults = .standard) {
        retiredKeys.forEach { userDefaults.removeObject(forKey: $0) }
    }
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
    static let invalidValueFallbackLanguage: AppLanguage = .simplifiedChinese

    static func firstLaunchLanguage(
        preferredLanguageIdentifiers: [String] = Locale.preferredLanguages
    ) -> AppLanguage {
        guard let primaryIdentifier = preferredLanguageIdentifiers.first else {
            return .english
        }
        let languageCode = Locale(identifier: primaryIdentifier)
            .language.languageCode?.identifier
        return languageCode?.lowercased() == "zh" ? .simplifiedChinese : .english
    }

    static func resolve(rawValue: String) -> AppLanguage {
        AppLanguage(rawValue: rawValue) ?? invalidValueFallbackLanguage
    }

    static func load(
        userDefaults: UserDefaults = .standard,
        preferredLanguageIdentifiers: [String] = Locale.preferredLanguages
    ) -> AppLanguage {
        guard let rawValue = userDefaults.string(forKey: AppPreferenceKeys.appLanguage) else {
            let language = firstLaunchLanguage(
                preferredLanguageIdentifiers: preferredLanguageIdentifiers
            )
            userDefaults.set(language.rawValue, forKey: AppPreferenceKeys.appLanguage)
            return language
        }
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

struct HotkeyRegistrationRequest: Equatable, Sendable {
    private enum NotificationUserInfoKey {
        static let requestID = "requestID"
        static let mainBaseKeys = "mainBaseKeys"
        static let mainReverseKeys = "mainReverseKeys"
        static let mainKeys = "mainKeys"
        static let quitKeys = "quitKeys"
        static let inAppShortcutKeys = "inAppShortcutKeys"
        static let inAppReverseKeys = "inAppReverseKeys"
    }

    let requestID: UUID
    let mainConfiguration: SwitcherHotkeyConfiguration
    let inAppWindowConfiguration: SwitcherHotkeyConfiguration

    var configurationSignature: String {
        [
            mainConfiguration.baseKeys.rawValue,
            mainConfiguration.reverseKeys.rawValue,
            mainConfiguration.mainKeys.rawValue,
            mainConfiguration.quitKeys.rawValue,
            inAppWindowConfiguration.baseKeys.rawValue,
            inAppWindowConfiguration.reverseKeys.rawValue
        ].joined(separator: "|")
    }

    init(
        requestID: UUID = UUID(),
        mainConfiguration: SwitcherHotkeyConfiguration,
        inAppWindowConfiguration: SwitcherHotkeyConfiguration
    ) {
        let resolvedInAppWindowConfiguration =
            InAppWindowHotkeyPreferencesStore.resolveAvoidingSwitcherHotkeyConflicts(
                shortcutKeysRaw: inAppWindowConfiguration.baseKeys.rawValue,
                reverseKeysRaw: inAppWindowConfiguration.reverseKeys.rawValue,
                switcherConfiguration: mainConfiguration
            )
        self.requestID = requestID
        self.mainConfiguration = mainConfiguration
        self.inAppWindowConfiguration =
            resolvedInAppWindowConfiguration.configuration
    }

    static func load(userDefaults: UserDefaults = .standard) -> HotkeyRegistrationRequest {
        let mainBaseKeysRaw = userDefaults.string(
            forKey: AppPreferenceKeys.hotkeyPrimaryModifier
        ) ?? SwitcherHotkeyPreferencesStore.defaultBaseKeys.rawValue
        let mainReverseKeysRaw = userDefaults.string(
            forKey: AppPreferenceKeys.hotkeyReverseModifiers
        ) ?? SwitcherHotkeyPreferencesStore.defaultReverseKeys.rawValue
        let mainKeysRaw = userDefaults.string(
            forKey: AppPreferenceKeys.hotkeyMainKey
        ) ?? SwitcherHotkeyPreferencesStore.defaultMainKeys.rawValue
        let quitKeysRaw = userDefaults.string(
            forKey: AppPreferenceKeys.hotkeyQuitKey
        ) ?? SwitcherHotkeyPreferencesStore.defaultQuitKeys.rawValue
        let inAppShortcutKeysRaw = userDefaults.string(
            forKey: AppPreferenceKeys.inAppWindowHotkeyShortcutKeys
        ) ?? InAppWindowHotkeyPreferencesStore.defaultShortcutKeys.rawValue
        let inAppReverseKeysRaw = userDefaults.string(
            forKey: AppPreferenceKeys.inAppWindowHotkeyReverseKeys
        ) ?? InAppWindowHotkeyPreferencesStore.defaultReverseKeys.rawValue

        let request = HotkeyRegistrationRequest.normalized(
            mainBaseKeysRaw: mainBaseKeysRaw,
            mainReverseKeysRaw: mainReverseKeysRaw,
            mainKeysRaw: mainKeysRaw,
            quitKeysRaw: quitKeysRaw,
            inAppShortcutKeysRaw: inAppShortcutKeysRaw,
            inAppReverseKeysRaw: inAppReverseKeysRaw
        )
        persistNormalizedValue(
            request.mainConfiguration.baseKeys.rawValue,
            rawValue: mainBaseKeysRaw,
            forKey: AppPreferenceKeys.hotkeyPrimaryModifier,
            userDefaults: userDefaults
        )
        persistNormalizedValue(
            request.mainConfiguration.reverseKeys.rawValue,
            rawValue: mainReverseKeysRaw,
            forKey: AppPreferenceKeys.hotkeyReverseModifiers,
            userDefaults: userDefaults
        )
        persistNormalizedValue(
            request.mainConfiguration.mainKeys.rawValue,
            rawValue: mainKeysRaw,
            forKey: AppPreferenceKeys.hotkeyMainKey,
            userDefaults: userDefaults
        )
        persistNormalizedValue(
            request.mainConfiguration.quitKeys.rawValue,
            rawValue: quitKeysRaw,
            forKey: AppPreferenceKeys.hotkeyQuitKey,
            userDefaults: userDefaults
        )
        persistNormalizedValue(
            request.inAppWindowConfiguration.baseKeys.rawValue,
            rawValue: inAppShortcutKeysRaw,
            forKey: AppPreferenceKeys.inAppWindowHotkeyShortcutKeys,
            userDefaults: userDefaults
        )
        persistNormalizedValue(
            request.inAppWindowConfiguration.reverseKeys.rawValue,
            rawValue: inAppReverseKeysRaw,
            forKey: AppPreferenceKeys.inAppWindowHotkeyReverseKeys,
            userDefaults: userDefaults
        )
        return request
    }

    static func normalized(
        mainBaseKeysRaw: String,
        mainReverseKeysRaw: String? = nil,
        mainKeysRaw: String,
        quitKeysRaw: String,
        inAppShortcutKeysRaw: String,
        inAppReverseKeysRaw: String? = nil
    ) -> HotkeyRegistrationRequest {
        let mainConfiguration = SwitcherHotkeyPreferencesStore.resolve(
            baseKeysRaw: mainBaseKeysRaw,
            reverseKeysRaw: mainReverseKeysRaw,
            mainKeysRaw: mainKeysRaw,
            quitKeysRaw: quitKeysRaw
        )
        let resolvedInAppWindowConfiguration =
            InAppWindowHotkeyPreferencesStore.resolveAvoidingSwitcherHotkeyConflicts(
                shortcutKeysRaw: inAppShortcutKeysRaw,
                reverseKeysRaw: inAppReverseKeysRaw,
                switcherConfiguration: mainConfiguration
            )
        let inAppWindowConfiguration =
            resolvedInAppWindowConfiguration.configuration
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
            let mainBaseKeysRaw =
                notificationUserInfo[NotificationUserInfoKey.mainBaseKeys] as? String,
            let mainReverseKeysRaw =
                notificationUserInfo[NotificationUserInfoKey.mainReverseKeys] as? String,
            let mainKeysRaw =
                notificationUserInfo[NotificationUserInfoKey.mainKeys] as? String,
            let quitKeysRaw =
                notificationUserInfo[NotificationUserInfoKey.quitKeys] as? String,
            let inAppShortcutKeysRaw =
                notificationUserInfo[NotificationUserInfoKey.inAppShortcutKeys] as? String,
            let inAppReverseKeysRaw =
                notificationUserInfo[NotificationUserInfoKey.inAppReverseKeys] as? String
        else {
            return nil
        }

        let resolvedInAppWindowConfiguration = InAppWindowHotkeyPreferencesStore.resolve(
            shortcutKeysRaw: inAppShortcutKeysRaw,
            reverseKeysRaw: inAppReverseKeysRaw
        )
        self.init(
            requestID: UUID(uuidString: requestIDRaw) ?? UUID(),
            mainConfiguration: SwitcherHotkeyPreferencesStore.resolve(
                baseKeysRaw: mainBaseKeysRaw,
                reverseKeysRaw: mainReverseKeysRaw,
                mainKeysRaw: mainKeysRaw,
                quitKeysRaw: quitKeysRaw
            ),
            inAppWindowConfiguration:
                resolvedInAppWindowConfiguration.configuration
        )
    }

    var notificationUserInfo: [AnyHashable: Any] {
        [
            NotificationUserInfoKey.requestID: requestID.uuidString,
            NotificationUserInfoKey.mainBaseKeys:
                mainConfiguration.baseKeys.rawValue,
            NotificationUserInfoKey.mainReverseKeys:
                mainConfiguration.reverseKeys.rawValue,
            NotificationUserInfoKey.mainKeys:
                mainConfiguration.mainKeys.rawValue,
            NotificationUserInfoKey.quitKeys:
                mainConfiguration.quitKeys.rawValue,
            NotificationUserInfoKey.inAppShortcutKeys:
                inAppWindowConfiguration.baseKeys.rawValue,
            NotificationUserInfoKey.inAppReverseKeys:
                inAppWindowConfiguration.reverseKeys.rawValue
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
