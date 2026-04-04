import Foundation

@MainActor
enum FlowTabUITestBootstrapper {
    static func prepareIfNeeded(userDefaults: UserDefaults = .standard) {
        if FlowTabTestLaunchOptions.resetsUserDefaultsOnLaunch {
            AppPreferenceKeys.allKeys.forEach { userDefaults.removeObject(forKey: $0) }
            userDefaults.removeObject(forKey: CommandTabTakeoverController.takeoverMarkerKey)
            HomeTabState.shared.selectedTab = .home
            RuntimeDiagnostics.shared.clear()
        }

        if let runtimeLogLevelRaw = FlowTabTestLaunchOptions.runtimeLogLevelOverrideRawValue {
            let resolved = RuntimeLogPreferencesStore.resolve(rawValue: runtimeLogLevelRaw)
            userDefaults.set(resolved.rawValue, forKey: AppPreferenceKeys.runtimeLogLevel)
        }

        if let seededLogCount = FlowTabTestLaunchOptions.seededLogCount {
            RuntimeDiagnostics.shared.clear()
            if seededLogCount > 0 {
                let seededLevels: [RuntimeLogLevel] = [.debug, .info, .warning, .error]
                for index in 1...seededLogCount {
                    let level = seededLevels[(index - 1) % seededLevels.count]
                    RuntimeDiagnostics.shared.log(
                        level: level,
                        category: "UITest",
                        message: "seeded-\(level.rawValue.lowercased())-log-\(index)"
                    )
                }
            }
        }
    }

    static func presentInitialUIIfNeeded(panelController: SwitcherPanelController) {
        guard FlowTabTestLaunchOptions.opensSwitcherOnLaunch else { return }
        panelController.setModifierReleaseConfirmationSuppressedForTesting(true)

        Task { @MainActor in
            let retrySleepNanoseconds: UInt64 = 150_000_000
            let maxAttempts = 20

            for attempt in 0..<maxAttempts {
                if panelController.presentGlobalHotkeySessionForTesting() {
                    if FlowTabTestLaunchOptions.entersSearchOnLaunch {
                        _ = panelController.modelForTesting.enterSearchMode()
                    }
                    return
                }

                guard attempt < maxAttempts - 1 else { return }
                try? await Task.sleep(nanoseconds: retrySleepNanoseconds)
            }
        }
    }
}
