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
    static let defaultShortcutKeys: SwitcherHotkeyKeySet = [
        .control,
        .tab
    ]
    static let defaultReverseKeys: SwitcherHotkeyKeySet = [.shift]

    static func load(
        userDefaults: UserDefaults = .standard
    ) -> SwitcherHotkeyConfiguration {
        let shortcutKeysRaw = userDefaults.string(
            forKey: AppPreferenceKeys.inAppWindowHotkeyShortcutKeys
        ) ?? defaultShortcutKeys.rawValue
        let reverseKeysRaw = userDefaults.string(
            forKey: AppPreferenceKeys.inAppWindowHotkeyReverseKeys
        ) ?? defaultReverseKeys.rawValue

        let resolved = resolve(
            shortcutKeysRaw: shortcutKeysRaw,
            reverseKeysRaw: reverseKeysRaw
        )
        persistNormalizedValue(
            resolved.shortcutKeys.rawValue,
            rawValue: shortcutKeysRaw,
            forKey: AppPreferenceKeys.inAppWindowHotkeyShortcutKeys,
            userDefaults: userDefaults
        )
        persistNormalizedValue(
            resolved.reverseKeys.rawValue,
            rawValue: reverseKeysRaw,
            forKey: AppPreferenceKeys.inAppWindowHotkeyReverseKeys,
            userDefaults: userDefaults
        )
        return resolved.configuration
    }

    static func resolve(
        shortcutKeysRaw: String,
        reverseKeysRaw: String? = nil
    ) -> InAppWindowHotkeyResolution {
        let candidate = resolveCandidate(
            shortcutKeysRaw: shortcutKeysRaw,
            reverseKeysRaw: reverseKeysRaw
        )
        let reverseKeys = HotkeyKeySetPreferences.normalizedField(
            candidate.reverseKeys,
            defaultKeys: defaultReverseKeys,
            excluding: candidate.shortcutKeys,
            preferredFallbacks: [
                [.option],
                [.command],
                [.control]
            ]
        )
        return InAppWindowHotkeyResolution(
            shortcutKeys: candidate.shortcutKeys,
            reverseKeys: reverseKeys
        )
    }

    static func resolveCandidate(
        shortcutKeysRaw: String,
        reverseKeysRaw: String? = nil
    ) -> InAppWindowHotkeyResolution {
        return InAppWindowHotkeyResolution(
            shortcutKeys: HotkeyKeySetPreferences.candidate(
                rawValue: shortcutKeysRaw,
                defaultKeys: defaultShortcutKeys
            ),
            reverseKeys: HotkeyKeySetPreferences.candidate(
                rawValue: reverseKeysRaw,
                defaultKeys: defaultReverseKeys
            )
        )
    }

    static func resolveAvoidingSwitcherHotkeyConflicts(
        shortcutKeysRaw: String,
        reverseKeysRaw: String? = nil,
        switcherConfiguration: SwitcherHotkeyConfiguration
    ) -> InAppWindowHotkeyResolution {
        let resolved = resolve(
            shortcutKeysRaw: shortcutKeysRaw,
            reverseKeysRaw: reverseKeysRaw
        )
        guard conflictsWithSwitcherShortcuts(
            shortcutKeys: resolved.shortcutKeys,
            reverseKeys: resolved.reverseKeys,
            switcherConfiguration: switcherConfiguration
        ) else {
            return resolved
        }

        for candidate in fallbackShortcutCandidates(
            preservingActionsFrom: resolved.shortcutKeys
        )
        where candidate.isDisjoint(with: resolved.reverseKeys)
            && !conflictsWithSwitcherShortcuts(
                shortcutKeys: candidate,
                reverseKeys: resolved.reverseKeys,
                switcherConfiguration: switcherConfiguration
            ) {
            return InAppWindowHotkeyResolution(
                shortcutKeys: candidate,
                reverseKeys: resolved.reverseKeys
            )
        }
        return resolved
    }

    private static func conflictsWithSwitcherShortcuts(
        shortcutKeys: SwitcherHotkeyKeySet,
        reverseKeys: SwitcherHotkeyKeySet,
        switcherConfiguration: SwitcherHotkeyConfiguration
    ) -> Bool {
        let configuration = SwitcherHotkeyConfiguration.inApp(
            shortcutKeys: shortcutKeys,
            reverseKeys: reverseKeys
        )
        return !configuration.switchingShortcuts.isDisjoint(
            with: switcherConfiguration.reservedShortcuts
        )
    }

    private static func fallbackShortcutCandidates(
        preservingActionsFrom shortcutKeys: SwitcherHotkeyKeySet
    ) -> [SwitcherHotkeyKeySet] {
        let modifiers: [SwitcherHotkeyKey] = [
            .control,
            .option,
            .command,
            .shift
        ]
        let actionKeys = shortcutKeys.subtracting(
            shortcutKeys.modifiers.hotkeyKeys
        )
        let sameActionCandidates = modifiers.map {
            actionKeys.union(SwitcherHotkeyKeySet([$0]))
        }
        return sameActionCandidates
            + [defaultShortcutKeys]
            + modifiers.flatMap { modifier in
                SwitcherHotkeyKey.allCases.map { key in
                    SwitcherHotkeyKeySet([modifier, key])
                }
            }
            + SwitcherHotkeyKey.allCases.map {
                SwitcherHotkeyKeySet([$0])
            }
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

struct InAppWindowHotkeyResolution: Equatable, Sendable {
    let shortcutKeys: SwitcherHotkeyKeySet
    let reverseKeys: SwitcherHotkeyKeySet

    var configuration: SwitcherHotkeyConfiguration {
        .inApp(
            shortcutKeys: shortcutKeys,
            reverseKeys: reverseKeys
        )
    }
}
