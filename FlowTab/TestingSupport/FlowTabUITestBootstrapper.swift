import Foundation

@MainActor
enum FlowTabUITestBootstrapper {
    private static var hotkeyReloadDiagnosticsObserver: NSObjectProtocol?

    static func prepareIfNeeded(userDefaults: UserDefaults = .standard) {
        if FlowTabTestLaunchOptions.resetsUserDefaultsOnLaunch {
            AppPreferenceKeys.allKeys.forEach { userDefaults.removeObject(forKey: $0) }
            userDefaults.removeObject(forKey: CommandTabTakeoverController.takeoverMarkerKey)
            HomeTabState.shared.selectedTab = .home
            RuntimeDiagnostics.shared.clear()
        }

        if FlowTabTestLaunchOptions.enablesMockHotkeyEffects {
            FlowTabUITestMockRuntimeEffects.reset()
        }

        if let runtimeLogLevelRaw = FlowTabTestLaunchOptions.runtimeLogLevelOverrideRawValue {
            let resolved = RuntimeLogPreferencesStore.resolve(rawValue: runtimeLogLevelRaw)
            userDefaults.set(resolved.rawValue, forKey: AppPreferenceKeys.runtimeLogLevel)
        }

        if FlowTabTestLaunchOptions.enablesVerboseRuntimeLogs {
            userDefaults.set(true, forKey: AppPreferenceKeys.enableVerboseDiagnostics)
        }

        installHotkeyReloadDiagnosticsIfNeeded()

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

    static func configurePanelControllerIfNeeded(panelController: SwitcherPanelController) {
        guard FlowTabTestLaunchOptions.enablesMockHotkeyEffects else { return }

        panelController.modelForTesting.terminateRequestOverride = { appID in
            let pid = FlowTabUITestMockRuntimeEffects.recordTerminateRequest(appID: appID)
            RuntimeLog.info("UITest", "mock terminate request appID=\(appID) pid=\(pid)")
            return (sent: true, pid: pid)
        }
        panelController.modelForTesting.isProcessRunningOverride = { pid in
            FlowTabUITestMockRuntimeEffects.isProcessRunning(pid: pid)
        }
    }

    private static func installHotkeyReloadDiagnosticsIfNeeded() {
        guard FlowTabTestLaunchOptions.recordsHotkeyReloadDiagnostics else { return }
        if let hotkeyReloadDiagnosticsObserver {
            NotificationCenter.default.removeObserver(hotkeyReloadDiagnosticsObserver)
        }
        hotkeyReloadDiagnosticsObserver = NotificationCenter.default.addObserver(
            forName: .flowTabReRegisterHotkeys,
            object: nil,
            queue: .main
        ) { notification in
            guard let request = notification.userInfo.flatMap(HotkeyRegistrationRequest.init) else {
                RuntimeDiagnostics.shared.log(
                    level: .info,
                    category: "UITest",
                    message: "hotkeyReloadNotification sender=unknown payload=missing"
                )
                return
            }
            let sender = notification.object is AppDelegate ? "AppDelegate" : "notification-only"
            RuntimeDiagnostics.shared.log(
                level: .info,
                category: "UITest",
                message: "hotkeyReloadNotification sender=\(sender) main=\(request.mainConfiguration.mainShortcutText) inApp=\(request.inAppWindowConfiguration.mainShortcutText)"
            )
        }
    }

    static func presentInitialUIIfNeeded(panelController: SwitcherPanelController) {
        guard FlowTabTestLaunchOptions.opensSwitcherOnLaunch else { return }
        panelController.setModifierReleaseConfirmationSuppressedForTesting(true)

        Task { @MainActor in
            let retrySleepNanoseconds: UInt64 = 150_000_000
            let maxAttempts = 20
            let requiredStableSnapshotCount = 2
            var lastObservedAppIDs: [String] = []
            var stableSnapshotCount = 0

            for attempt in 0..<maxAttempts {
                if panelController.presentGlobalHotkeySessionForTesting() {
                    let appIDs = panelController.modelForTesting.session?.apps.map(\.id) ?? []
                    if appIDs == lastObservedAppIDs {
                        stableSnapshotCount += 1
                    } else {
                        lastObservedAppIDs = appIDs
                        stableSnapshotCount = 1
                    }

                    if stableSnapshotCount >= requiredStableSnapshotCount {
                        if FlowTabTestLaunchOptions.entersSearchOnLaunch {
                            _ = panelController.modelForTesting.enterSearchMode()
                        }
                        return
                    }

                    panelController.cancelSelectionForTesting()
                } else {
                    lastObservedAppIDs = []
                    stableSnapshotCount = 0
                }

                guard attempt < maxAttempts - 1 else { return }
                try? await Task.sleep(nanoseconds: retrySleepNanoseconds)
            }
        }
    }
}
