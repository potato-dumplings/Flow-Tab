import FlowTabCore
import Foundation

private enum HotkeyKeySetPreferences {
    static func candidate(
        rawValue: String?,
        defaultKeys: SwitcherHotkeyKeySet
    ) -> SwitcherHotkeyKeySet {
        guard
            let rawValue,
            let keys = SwitcherHotkeyKeySet(rawValue: rawValue),
            !keys.isEmpty
        else {
            return defaultKeys
        }
        return keys
    }

    static func normalizedField(
        _ candidate: SwitcherHotkeyKeySet,
        defaultKeys: SwitcherHotkeyKeySet,
        excluding usedKeys: SwitcherHotkeyKeySet,
        preferredFallbacks: [SwitcherHotkeyKeySet]
    ) -> SwitcherHotkeyKeySet {
        if !candidate.isEmpty, candidate.isDisjoint(with: usedKeys) {
            return candidate
        }
        for fallback in [defaultKeys] + preferredFallbacks
        where !fallback.isEmpty && fallback.isDisjoint(with: usedKeys) {
            return fallback
        }
        return firstAvailableSingleKey(excluding: usedKeys)
            ?? defaultKeys
    }

    private static func firstAvailableSingleKey(
        excluding usedKeys: SwitcherHotkeyKeySet
    ) -> SwitcherHotkeyKeySet? {
        let preferredKeys: [SwitcherHotkeyKey] = [
            .shift,
            .option,
            .control,
            .command,
            .tab,
            .q,
            .w,
            .space
        ]
        let keys = preferredKeys + SwitcherHotkeyKey.allCases
        return keys.lazy
            .map { SwitcherHotkeyKeySet([$0]) }
            .first { $0.isDisjoint(with: usedKeys) }
    }
}

enum SwitcherHotkeyPreferencesStore {
    static let defaultBaseKeys: SwitcherHotkeyKeySet = [.option]
    static let defaultReverseKeys: SwitcherHotkeyKeySet = [.shift]
    static let defaultMainKeys: SwitcherHotkeyKeySet = [.tab]
    static let defaultQuitKeys: SwitcherHotkeyKeySet = [.q]

    static func load(
        userDefaults: UserDefaults = .standard
    ) -> SwitcherHotkeyConfiguration {
        let baseKeysRaw = userDefaults.string(
            forKey: AppPreferenceKeys.hotkeyPrimaryModifier
        ) ?? defaultBaseKeys.rawValue
        let reverseKeysRaw = userDefaults.string(
            forKey: AppPreferenceKeys.hotkeyReverseModifiers
        ) ?? defaultReverseKeys.rawValue
        let mainKeysRaw = userDefaults.string(
            forKey: AppPreferenceKeys.hotkeyMainKey
        ) ?? defaultMainKeys.rawValue
        let quitKeysRaw = userDefaults.string(
            forKey: AppPreferenceKeys.hotkeyQuitKey
        ) ?? defaultQuitKeys.rawValue

        let configuration = resolve(
            baseKeysRaw: baseKeysRaw,
            reverseKeysRaw: reverseKeysRaw,
            mainKeysRaw: mainKeysRaw,
            quitKeysRaw: quitKeysRaw
        )

        persistNormalizedValue(
            configuration.baseKeys.rawValue,
            rawValue: baseKeysRaw,
            forKey: AppPreferenceKeys.hotkeyPrimaryModifier,
            userDefaults: userDefaults
        )
        persistNormalizedValue(
            configuration.reverseKeys.rawValue,
            rawValue: reverseKeysRaw,
            forKey: AppPreferenceKeys.hotkeyReverseModifiers,
            userDefaults: userDefaults
        )
        persistNormalizedValue(
            configuration.mainKeys.rawValue,
            rawValue: mainKeysRaw,
            forKey: AppPreferenceKeys.hotkeyMainKey,
            userDefaults: userDefaults
        )
        persistNormalizedValue(
            configuration.quitKeys.rawValue,
            rawValue: quitKeysRaw,
            forKey: AppPreferenceKeys.hotkeyQuitKey,
            userDefaults: userDefaults
        )
        return configuration
    }

    static func resolve(
        baseKeysRaw: String,
        reverseKeysRaw: String? = nil,
        mainKeysRaw: String,
        quitKeysRaw: String
    ) -> SwitcherHotkeyConfiguration {
        let candidate = resolveCandidate(
            baseKeysRaw: baseKeysRaw,
            reverseKeysRaw: reverseKeysRaw,
            mainKeysRaw: mainKeysRaw,
            quitKeysRaw: quitKeysRaw
        )
        let baseKeys = candidate.baseKeys
        let reverseKeys = HotkeyKeySetPreferences.normalizedField(
            candidate.reverseKeys,
            defaultKeys: defaultReverseKeys,
            excluding: baseKeys,
            preferredFallbacks: [
                [.control],
                [.command],
                [.option]
            ]
        )
        let baseAndReverse = baseKeys.union(reverseKeys)
        let mainKeys = HotkeyKeySetPreferences.normalizedField(
            candidate.mainKeys,
            defaultKeys: defaultMainKeys,
            excluding: baseAndReverse,
            preferredFallbacks: [
                [.space],
                [.grave],
                [.a]
            ]
        )
        let quitKeys = HotkeyKeySetPreferences.normalizedField(
            candidate.quitKeys,
            defaultKeys: defaultQuitKeys,
            excluding: baseAndReverse.union(mainKeys),
            preferredFallbacks: [
                [.w],
                [.z],
                [.escape]
            ]
        )
        return SwitcherHotkeyConfiguration(
            baseKeys: baseKeys,
            reverseKeys: reverseKeys,
            mainKeys: mainKeys,
            quitKeys: quitKeys
        )
    }

    static func resolveCandidate(
        baseKeysRaw: String,
        reverseKeysRaw: String? = nil,
        mainKeysRaw: String,
        quitKeysRaw: String
    ) -> SwitcherHotkeyConfiguration {
        SwitcherHotkeyConfiguration(
            baseKeys: HotkeyKeySetPreferences.candidate(
                rawValue: baseKeysRaw,
                defaultKeys: defaultBaseKeys
            ),
            reverseKeys: HotkeyKeySetPreferences.candidate(
                rawValue: reverseKeysRaw,
                defaultKeys: defaultReverseKeys
            ),
            mainKeys: HotkeyKeySetPreferences.candidate(
                rawValue: mainKeysRaw,
                defaultKeys: defaultMainKeys
            ),
            quitKeys: HotkeyKeySetPreferences.candidate(
                rawValue: quitKeysRaw,
                defaultKeys: defaultQuitKeys
            )
        )
    }

    static func commandTabFallback(
        for configuration: SwitcherHotkeyConfiguration
    ) -> SwitcherHotkeyConfiguration {
        var fallbackBaseKeys = configuration.baseKeys
        fallbackBaseKeys.remove(.command)
        fallbackBaseKeys.insert(.option)
        return resolve(
            baseKeysRaw: fallbackBaseKeys.rawValue,
            reverseKeysRaw: configuration.reverseKeys.rawValue,
            mainKeysRaw: configuration.mainKeys.rawValue,
            quitKeysRaw: configuration.quitKeys.rawValue
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
}

enum InAppWindowHotkeyPreferencesStore {
    static let defaultBaseKeys: SwitcherHotkeyKeySet = [.control]
    static let defaultReverseKeys: SwitcherHotkeyKeySet = [.shift]
    static let defaultMainKeys: SwitcherHotkeyKeySet = [.tab]
    static let defaultLegacyShortcutKeys = defaultBaseKeys.union(
        defaultMainKeys
    )

    static func load(
        userDefaults: UserDefaults = .standard
    ) -> SwitcherHotkeyConfiguration {
        let storedBaseKeysRaw = userDefaults.string(
            forKey: AppPreferenceKeys.inAppWindowHotkeyBaseKeys
        )
        let storedMainKeysRaw = userDefaults.string(
            forKey: AppPreferenceKeys.inAppWindowHotkeyMainKeys
        )
        let migratedLegacy = migratedLegacyShortcut(
            rawValue: userDefaults.string(
                forKey: AppPreferenceKeys.inAppWindowHotkeyShortcutKeys
            )
        )
        let baseKeysRaw = storedBaseKeysRaw
            ?? migratedLegacy?.baseKeys.rawValue
            ?? defaultBaseKeys.rawValue
        let mainKeysRaw = storedMainKeysRaw
            ?? migratedLegacy?.mainKeys.rawValue
            ?? defaultMainKeys.rawValue
        let reverseKeysRaw = userDefaults.string(
            forKey: AppPreferenceKeys.inAppWindowHotkeyReverseKeys
        ) ?? defaultReverseKeys.rawValue

        let resolved = resolve(
            baseKeysRaw: baseKeysRaw,
            reverseKeysRaw: reverseKeysRaw,
            mainKeysRaw: mainKeysRaw
        )
        let shouldPersistSplitFields = storedBaseKeysRaw != nil
            || storedMainKeysRaw != nil
            || migratedLegacy != nil
        if shouldPersistSplitFields {
            persistNormalizedValue(
                resolved.baseKeys.rawValue,
                rawValue: storedBaseKeysRaw,
                forKey: AppPreferenceKeys.inAppWindowHotkeyBaseKeys,
                userDefaults: userDefaults
            )
        }
        persistNormalizedValue(
            resolved.reverseKeys.rawValue,
            rawValue: reverseKeysRaw,
            forKey: AppPreferenceKeys.inAppWindowHotkeyReverseKeys,
            userDefaults: userDefaults
        )
        if shouldPersistSplitFields {
            persistNormalizedValue(
                resolved.mainKeys.rawValue,
                rawValue: storedMainKeysRaw,
                forKey: AppPreferenceKeys.inAppWindowHotkeyMainKeys,
                userDefaults: userDefaults
            )
        }
        return resolved.configuration
    }

    static func resolve(
        baseKeysRaw: String,
        reverseKeysRaw: String? = nil,
        mainKeysRaw: String
    ) -> InAppWindowHotkeyResolution {
        let candidate = resolveCandidate(
            baseKeysRaw: baseKeysRaw,
            reverseKeysRaw: reverseKeysRaw,
            mainKeysRaw: mainKeysRaw
        )
        let baseKeys = candidate.baseKeys
        let reverseKeys = HotkeyKeySetPreferences.normalizedField(
            candidate.reverseKeys,
            defaultKeys: defaultReverseKeys,
            excluding: baseKeys,
            preferredFallbacks: [
                [.shift],
                [.option],
                [.command]
            ]
        )
        let mainKeys = HotkeyKeySetPreferences.normalizedField(
            candidate.mainKeys,
            defaultKeys: defaultMainKeys,
            excluding: baseKeys.union(reverseKeys),
            preferredFallbacks: [
                [.space],
                [.grave],
                [.a]
            ]
        )
        return InAppWindowHotkeyResolution(
            baseKeys: baseKeys,
            reverseKeys: reverseKeys,
            mainKeys: mainKeys
        )
    }

    static func resolveCandidate(
        baseKeysRaw: String,
        reverseKeysRaw: String? = nil,
        mainKeysRaw: String
    ) -> InAppWindowHotkeyResolution {
        return InAppWindowHotkeyResolution(
            baseKeys: HotkeyKeySetPreferences.candidate(
                rawValue: baseKeysRaw,
                defaultKeys: defaultBaseKeys
            ),
            reverseKeys: HotkeyKeySetPreferences.candidate(
                rawValue: reverseKeysRaw,
                defaultKeys: defaultReverseKeys
            ),
            mainKeys: HotkeyKeySetPreferences.candidate(
                rawValue: mainKeysRaw,
                defaultKeys: defaultMainKeys
            )
        )
    }

    static func resolveAvoidingSwitcherHotkeyConflicts(
        baseKeysRaw: String,
        reverseKeysRaw: String? = nil,
        mainKeysRaw: String,
        switcherConfiguration: SwitcherHotkeyConfiguration
    ) -> InAppWindowHotkeyResolution {
        let resolved = resolve(
            baseKeysRaw: baseKeysRaw,
            reverseKeysRaw: reverseKeysRaw,
            mainKeysRaw: mainKeysRaw
        )
        guard conflictsWithSwitcherShortcuts(
            baseKeys: resolved.baseKeys,
            reverseKeys: resolved.reverseKeys,
            mainKeys: resolved.mainKeys,
            switcherConfiguration: switcherConfiguration
        ) else {
            return resolved
        }

        for candidate in fallbackBaseKeyCandidates
        where candidate.isDisjoint(
            with: resolved.reverseKeys.union(resolved.mainKeys)
        )
            && !conflictsWithSwitcherShortcuts(
                baseKeys: candidate,
                reverseKeys: resolved.reverseKeys,
                mainKeys: resolved.mainKeys,
                switcherConfiguration: switcherConfiguration
            ) {
            return InAppWindowHotkeyResolution(
                baseKeys: candidate,
                reverseKeys: resolved.reverseKeys,
                mainKeys: resolved.mainKeys
            )
        }
        return resolved
    }

    private static func conflictsWithSwitcherShortcuts(
        baseKeys: SwitcherHotkeyKeySet,
        reverseKeys: SwitcherHotkeyKeySet,
        mainKeys: SwitcherHotkeyKeySet,
        switcherConfiguration: SwitcherHotkeyConfiguration
    ) -> Bool {
        let configuration = SwitcherHotkeyConfiguration.inApp(
            baseKeys: baseKeys,
            reverseKeys: reverseKeys,
            mainKeys: mainKeys
        )
        return !configuration.switchingShortcuts.isDisjoint(
            with: switcherConfiguration.reservedShortcuts
        )
    }

    static func migratedLegacyShortcut(
        rawValue: String?
    ) -> InAppWindowHotkeyLegacyMigration? {
        guard rawValue != nil else { return nil }
        let shortcutKeys = HotkeyKeySetPreferences.candidate(
            rawValue: rawValue,
            defaultKeys: defaultLegacyShortcutKeys
        )
        let modifierKeys = shortcutKeys.modifiers.hotkeyKeys
        let mainKeys = shortcutKeys.subtracting(modifierKeys)
        return InAppWindowHotkeyLegacyMigration(
            baseKeys: modifierKeys.isEmpty
                ? defaultBaseKeys : modifierKeys,
            mainKeys: mainKeys.isEmpty
                ? defaultMainKeys : mainKeys
        )
    }

    private static var fallbackBaseKeyCandidates: [SwitcherHotkeyKeySet] {
        [
            defaultBaseKeys,
            [.option],
            [.command],
            [.shift]
        ] + SwitcherHotkeyKey.allCases.map {
            SwitcherHotkeyKeySet([$0])
        }
    }

    private static func persistNormalizedValue(
        _ value: String,
        rawValue: String?,
        forKey key: String,
        userDefaults: UserDefaults
    ) {
        if rawValue != value {
            userDefaults.set(value, forKey: key)
        }
    }
}

struct InAppWindowHotkeyLegacyMigration: Equatable, Sendable {
    let baseKeys: SwitcherHotkeyKeySet
    let mainKeys: SwitcherHotkeyKeySet
}

struct InAppWindowHotkeyResolution: Equatable, Sendable {
    let baseKeys: SwitcherHotkeyKeySet
    let reverseKeys: SwitcherHotkeyKeySet
    let mainKeys: SwitcherHotkeyKeySet

    var configuration: SwitcherHotkeyConfiguration {
        .inApp(
            baseKeys: baseKeys,
            reverseKeys: reverseKeys,
            mainKeys: mainKeys
        )
    }
}
