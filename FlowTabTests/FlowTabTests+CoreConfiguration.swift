import AppKit
import SwiftUI
import XCTest
@testable import FlowTab
import FlowTabCore
import Carbon

extension FlowTabTests {
    func testResolveKeepsCommandWhenMainShortcutIsCommandTab() {
        let configuration = SwitcherHotkeyPreferencesStore.resolve(
            primaryModifierRaw: SwitcherPrimaryModifier.command.rawValue,
            mainKeyRaw: SwitcherHotkeyKey.tab.rawValue,
            quitKeyRaw: SwitcherHotkeyKey.q.rawValue
        )

        XCTAssertEqual(configuration.primaryModifier, .command)
        XCTAssertEqual(configuration.mainKey, .tab)
        XCTAssertEqual(configuration.quitKey, .q)
    }

    func testResolveFallsBackQuitKeyWhenQuitEqualsMainKey() {
        let configuration = SwitcherHotkeyPreferencesStore.resolve(
            primaryModifierRaw: SwitcherPrimaryModifier.option.rawValue,
            mainKeyRaw: SwitcherHotkeyKey.q.rawValue,
            quitKeyRaw: SwitcherHotkeyKey.q.rawValue
        )

        XCTAssertEqual(configuration.mainKey, .q)
        XCTAssertEqual(configuration.quitKey, .w)
    }

    func testLoadPersistsNormalizedHotkeyValues() {
        let suiteName = "FlowTabTests.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated user defaults suite")
            return
        }

        userDefaults.set(
            SwitcherPrimaryModifier.command.rawValue,
            forKey: AppPreferenceKeys.hotkeyPrimaryModifier
        )
        userDefaults.set(
            SwitcherHotkeyKey.tab.rawValue,
            forKey: AppPreferenceKeys.hotkeyMainKey
        )
        userDefaults.set(
            SwitcherHotkeyKey.tab.rawValue,
            forKey: AppPreferenceKeys.hotkeyQuitKey
        )

        let configuration = SwitcherHotkeyPreferencesStore.load(userDefaults: userDefaults)

        XCTAssertEqual(configuration.primaryModifier, .command)
        XCTAssertEqual(configuration.mainKey, .tab)
        XCTAssertEqual(configuration.quitKey, .q)
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.hotkeyPrimaryModifier),
            SwitcherPrimaryModifier.command.rawValue
        )
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.hotkeyMainKey),
            SwitcherHotkeyKey.tab.rawValue
        )
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.hotkeyQuitKey),
            SwitcherHotkeyKey.q.rawValue
        )

        userDefaults.removePersistentDomain(forName: suiteName)
    }

    func testResolveFallsBackToDefaultValuesForInvalidHotkeyRawInputs() {
        let configuration = SwitcherHotkeyPreferencesStore.resolve(
            primaryModifierRaw: "invalid-modifier",
            mainKeyRaw: "invalid-main",
            quitKeyRaw: "invalid-quit"
        )

        XCTAssertEqual(configuration.primaryModifier, SwitcherHotkeyPreferencesStore.defaultPrimaryModifier)
        XCTAssertEqual(configuration.mainKey, SwitcherHotkeyPreferencesStore.defaultMainKey)
        XCTAssertEqual(configuration.quitKey, SwitcherHotkeyPreferencesStore.defaultQuitKey)
    }

    func testRuntimeActivatorOpenConfigurationActivatesTargetApp() {
        let configuration = RuntimeActivator.makeOpenConfiguration()

        XCTAssertTrue(configuration.activates)
    }

    func testRuntimeActivatorOpenConfigurationReusesRunningAppInstance() {
        let configuration = RuntimeActivator.makeOpenConfiguration()

        XCTAssertFalse(configuration.createsNewApplicationInstance)
    }

    func testHotkeyConfigurationDerivedFieldsAreConsistent() {
        let configuration = SwitcherHotkeyConfiguration(
            primaryModifier: .command,
            mainKey: .space,
            quitKey: .w
        )

        XCTAssertEqual(configuration.forwardKeyCode, UInt32(SwitcherHotkeyKey.space.keyCode))
        XCTAssertEqual(configuration.forwardModifiers, UInt32(cmdKey))
        XCTAssertEqual(configuration.backwardModifiers, UInt32(cmdKey) | UInt32(shiftKey))
        XCTAssertEqual(configuration.quitKeyCode, SwitcherHotkeyKey.w.keyCode)
        XCTAssertEqual(configuration.mainShortcutText, "Command + Space")
        XCTAssertEqual(configuration.backwardShortcutText, "Command + Shift + Space")
        XCTAssertEqual(configuration.quitShortcutText, "Command + W")
    }

    func testSwitcherEnumsExposeStableIdentifiersAndDistinctKeyCodes() {
        for modifier in SwitcherPrimaryModifier.allCases {
            XCTAssertEqual(modifier.id, modifier.rawValue)
        }

        for key in SwitcherHotkeyKey.allCases {
            XCTAssertEqual(key.id, key.rawValue)
        }

        let keyCodes = SwitcherHotkeyKey.allCases.map(\.keyCode)
        XCTAssertEqual(Set(keyCodes).count, SwitcherHotkeyKey.allCases.count)
        XCTAssertEqual(SwitcherHotkeyKey.tab.keyCode, UInt16(kVK_Tab))
        XCTAssertEqual(SwitcherHotkeyKey.space.keyCode, UInt16(kVK_Space))
        XCTAssertEqual(SwitcherHotkeyKey.grave.keyCode, UInt16(kVK_ANSI_Grave))
    }

    @MainActor
    func testContentViewBodyBuildsWithPersistedPreferences() {
        let userDefaults = UserDefaults.standard
        let keys = [
            AppPreferenceKeys.themeMode,
            AppPreferenceKeys.hotkeyPrimaryModifier,
            AppPreferenceKeys.hotkeyMainKey,
            AppPreferenceKeys.hotkeyQuitKey,
            AppPreferenceKeys.appLanguage
        ]
        let previousValues = Dictionary(
            uniqueKeysWithValues: keys.map { key in
                (key, userDefaults.object(forKey: key))
            }
        )
        defer {
            keys.forEach { key in
                restoreUserDefaultsValue(
                    previousValues[key] ?? nil,
                    forKey: key,
                    userDefaults: userDefaults
                )
            }
        }

        userDefaults.set(ThemeMode.dark.rawValue, forKey: AppPreferenceKeys.themeMode)
        userDefaults.set(
            SwitcherPrimaryModifier.command.rawValue,
            forKey: AppPreferenceKeys.hotkeyPrimaryModifier
        )
        userDefaults.set(SwitcherHotkeyKey.space.rawValue, forKey: AppPreferenceKeys.hotkeyMainKey)
        userDefaults.set(SwitcherHotkeyKey.w.rawValue, forKey: AppPreferenceKeys.hotkeyQuitKey)
        userDefaults.set(AppLanguage.english.rawValue, forKey: AppPreferenceKeys.appLanguage)

        let view = ContentView()
        let hostingView = NSHostingView(rootView: view)

        XCTAssertGreaterThan(hostingView.fittingSize.width, 0)
        XCTAssertGreaterThan(hostingView.fittingSize.height, 0)
        XCTAssertFalse(String(describing: view.body).isEmpty)
    }

    func testFlowTabTestLaunchOptionsParsesSwitcherAndSearchFlags() {
        withLaunchArgumentsForTesting(["FlowTab", "--flowtab-ui-open-switcher"]) {
            XCTAssertTrue(FlowTabTestLaunchOptions.opensSwitcherOnLaunch)
            XCTAssertFalse(FlowTabTestLaunchOptions.entersSearchOnLaunch)
        }

        withLaunchArgumentsForTesting(["FlowTab", "--flowtab-ui-open-switcher-search"]) {
            XCTAssertTrue(FlowTabTestLaunchOptions.opensSwitcherOnLaunch)
            XCTAssertTrue(FlowTabTestLaunchOptions.entersSearchOnLaunch)
        }
    }

    func testFlowTabTestLaunchOptionsParsesBooleanAndValueOverrides() {
        withLaunchArgumentsForTesting(
            [
                "FlowTab",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-ax-trusted", "yes",
                "--flowtab-ui-screen-trusted", "0",
                "--flowtab-ui-seed-logs", "12",
                "--flowtab-ui-runtime-log-level", "debug"
            ]
        ) {
            XCTAssertTrue(FlowTabTestLaunchOptions.usesMockRuntimeSnapshot)
            XCTAssertTrue(FlowTabTestLaunchOptions.resetsUserDefaultsOnLaunch)
            XCTAssertEqual(FlowTabTestLaunchOptions.accessibilityTrustedOverride, true)
            XCTAssertEqual(FlowTabTestLaunchOptions.screenCaptureTrustedOverride, false)
            XCTAssertEqual(FlowTabTestLaunchOptions.seededLogCount, 12)
            XCTAssertEqual(FlowTabTestLaunchOptions.runtimeLogLevelOverrideRawValue, "debug")
        }
    }

    func testFlowTabTestLaunchOptionsReturnsNilForInvalidOrMissingValues() {
        withLaunchArgumentsForTesting(
            [
                "FlowTab",
                "--flowtab-ui-ax-trusted", "maybe",
                "--flowtab-ui-screen-trusted",
                "--flowtab-ui-seed-logs", "not-a-number"
            ]
        ) {
            XCTAssertNil(FlowTabTestLaunchOptions.accessibilityTrustedOverride)
            XCTAssertNil(FlowTabTestLaunchOptions.screenCaptureTrustedOverride)
            XCTAssertNil(FlowTabTestLaunchOptions.seededLogCount)
            XCTAssertNil(FlowTabTestLaunchOptions.runtimeLogLevelOverrideRawValue)
        }
    }

    func testPermissionCheckersRespectLaunchOptionOverrides() {
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest = AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let previousScreenTrusted = ScreenCapturePermissionChecker.hasPermissionOverrideForTesting
        let previousScreenRequest = ScreenCapturePermissionChecker.requestPermissionOverrideForTesting
        defer {
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting = previousAXRequest
            ScreenCapturePermissionChecker.hasPermissionOverrideForTesting = previousScreenTrusted
            ScreenCapturePermissionChecker.requestPermissionOverrideForTesting = previousScreenRequest
        }

        AccessibilityPermissionChecker.isTrustedOverrideForTesting = nil
        AccessibilityPermissionChecker.requestPermissionOverrideForTesting = nil
        ScreenCapturePermissionChecker.hasPermissionOverrideForTesting = nil
        ScreenCapturePermissionChecker.requestPermissionOverrideForTesting = nil

        withLaunchArgumentsForTesting(
            [
                "FlowTab",
                "--flowtab-ui-ax-trusted", "false",
                "--flowtab-ui-screen-trusted", "true"
            ]
        ) {
            XCTAssertFalse(AccessibilityPermissionChecker.isTrusted())
            XCTAssertFalse(AccessibilityPermissionChecker.requestPermission())
            XCTAssertTrue(ScreenCapturePermissionChecker.hasScreenCapturePermission)
            XCTAssertTrue(ScreenCapturePermissionChecker.requestScreenCapturePermission())
        }
    }

    func testRuntimeSnapshotProviderUsesUITestMockDatasetWhenLaunchFlagEnabled() {
        withLaunchArgumentsForTesting(["FlowTab", "--flowtab-ui-mock-runtime"]) {
            let provider = RuntimeSnapshotProvider()

            let snapshot = provider.snapshot()
            XCTAssertEqual(snapshot.apps.count, 6)
            XCTAssertEqual(snapshot.contextsByID.count, 0)
            XCTAssertEqual(snapshot.apps.first?.id, "com.flowtab.mock.mail")
            XCTAssertEqual(snapshot.apps.first?.windows.count, 2)

            let summaries = provider.homeAppSummaries()
            XCTAssertEqual(summaries.count, 6)
            XCTAssertEqual(summaries.first?.appID, "com.flowtab.mock.mail")
            XCTAssertEqual(summaries.first?.windowCount, 2)
            XCTAssertEqual(summaries.last?.appID, "com.flowtab.mock.file-transfer-assistant")

            let summary = provider.homeAppSummary(for: "com.flowtab.mock.browser")
            XCTAssertNotNil(summary)
            XCTAssertEqual(summary?.displayName, "Mock Browser")
            XCTAssertEqual(summary?.windowCount, 1)
            XCTAssertNil(provider.homeAppSummary(for: "com.flowtab.mock.missing"))

            let homeSnapshot = provider.homeAppSnapshot(for: "com.flowtab.mock.mail")
            XCTAssertNotNil(homeSnapshot)
            XCTAssertEqual(homeSnapshot?.candidate.id, "com.flowtab.mock.mail")
            XCTAssertEqual(homeSnapshot?.candidate.windows.map(\.id), ["mock-mail-inbox", "mock-mail-draft"])
            XCTAssertEqual(homeSnapshot?.summary.windowCount, 2)
            XCTAssertEqual(homeSnapshot?.context.appID, "com.flowtab.mock.mail")
            XCTAssertEqual(homeSnapshot?.context.windowsByID.count, 2)
            XCTAssertNil(provider.homeAppSnapshot(for: "com.flowtab.mock.missing"))
        }
    }

    func testRuntimeSnapshotProviderRealPathWithoutAccessibilityBuildsConsistentSnapshot() {
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let userDefaults = UserDefaults.standard
        let previousShowInCommandTab = userDefaults.object(forKey: AppPreferenceKeys.showInCommandTab)
        let previousHideMinimized = userDefaults.object(forKey: AppPreferenceKeys.hideMinimizedAppsFromAppLayer)
        defer {
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousAXTrusted
            restoreUserDefaultsValue(
                previousShowInCommandTab,
                forKey: AppPreferenceKeys.showInCommandTab,
                userDefaults: userDefaults
            )
            restoreUserDefaultsValue(
                previousHideMinimized,
                forKey: AppPreferenceKeys.hideMinimizedAppsFromAppLayer,
                userDefaults: userDefaults
            )
        }

        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { false }
        userDefaults.set(true, forKey: AppPreferenceKeys.showInCommandTab)
        userDefaults.set(true, forKey: AppPreferenceKeys.hideMinimizedAppsFromAppLayer)

        withLaunchArgumentsForTesting(["FlowTab"]) {
            let provider = RuntimeSnapshotProvider()
            let snapshot = provider.snapshot()

            XCTAssertFalse(snapshot.apps.isEmpty)
            XCTAssertEqual(snapshot.contextsByID.count, snapshot.apps.count)
            XCTAssertTrue(snapshot.apps.allSatisfy { $0.windows.isEmpty })
            XCTAssertTrue(snapshot.contextsByID.values.allSatisfy { $0.windowsByID.isEmpty })

            let summaries = provider.homeAppSummaries()
            XCTAssertFalse(summaries.isEmpty)
            XCTAssertTrue(summaries.allSatisfy { $0.windowCount == 0 })

            guard let targetID = snapshot.apps.first?.id else {
                XCTFail("Expected at least one app in runtime snapshot")
                return
            }

            let summary = provider.homeAppSummary(for: targetID)
            XCTAssertNotNil(summary)
            XCTAssertEqual(summary?.appID, targetID)
            XCTAssertEqual(summary?.windowCount, 0)

            let homeSnapshot = provider.homeAppSnapshot(for: targetID)
            XCTAssertNotNil(homeSnapshot)
            XCTAssertEqual(homeSnapshot?.candidate.id, targetID)
            XCTAssertEqual(homeSnapshot?.candidate.windows.count, 0)
            XCTAssertEqual(homeSnapshot?.context.windowsByID.count, 0)
        }
    }

    @MainActor
    func testRuntimeActivatorRequestsActivationForAppTargetWhenNotCurrent() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }

        var requestedPID: pid_t?
        var observedCompletionWasNil = false
        activator.requestActivationOverride = { app, completion in
            requestedPID = app.processIdentifier
            observedCompletionWasNil = completion == nil
        }

        activator.activate(
            target: .app(appID: appID),
            contextsByID: [
                appID: RuntimeAppContext(
                    appID: appID,
                    runningApp: currentApp,
                    windowsByID: [:]
                )
            ]
        )

        XCTAssertEqual(requestedPID, currentApp.processIdentifier)
        XCTAssertTrue(observedCompletionWasNil)
    }

    @MainActor
    func testRuntimeActivatorSkipsMissingContextsForAppAndWindowTargets() {
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in
            XCTFail("activateCurrentAppIfNeeded should not run for missing contexts")
            return false
        }

        var requestCallCount = 0
        activator.requestActivationOverride = { _, _ in
            requestCallCount += 1
        }

        activator.activate(target: .app(appID: "missing-app"), contextsByID: [:])
        activator.activate(
            target: .window(appID: "missing-app", windowID: "missing-window", restoreIfMinimized: false),
            contextsByID: [:]
        )

        XCTAssertEqual(requestCallCount, 0)
    }

    @MainActor
    func testRuntimeActivatorFocusWindowPathReturnsWhenAXWindowsUnavailable() {
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        defer {
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousAXTrusted
        }

        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { false }

        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }

        var requestCallCount = 0
        activator.requestActivationOverride = { app, completion in
            requestCallCount += 1
            completion?(app)
        }
        activator.focusWindowOverride = nil

        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                "mail-1": RuntimeWindowContext(
                    id: "mail-1",
                    title: "Inbox",
                    isMinimized: false,
                    cgWindowID: nil,
                    inferredTitleBarStyle: nil
                )
            ]
        )

        activator.activate(
            target: .window(appID: appID, windowID: "mail-1", restoreIfMinimized: false),
            contextsByID: [appID: context]
        )

        XCTAssertEqual(requestCallCount, 1)
    }

    @MainActor
    func testRuntimeActivatorPrefersLiveAXWindowHandleBeforeIndexOrTitleFallback() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }

        var requestCallCount = 0
        activator.requestActivationOverride = { app, completion in
            requestCallCount += 1
            completion?(app)
        }

        var directFocusCount = 0
        activator.focusAXWindowOverride = { _, _, _ in
            directFocusCount += 1
            return true
        }

        let liveHandle = AXUIElementCreateApplication(currentApp.processIdentifier)
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                "mail-1": RuntimeWindowContext(
                    id: "mail-1",
                    title: "Inbox",
                    isMinimized: false,
                    cgWindowID: nil,
                    inferredTitleBarStyle: nil,
                    axWindow: liveHandle
                )
            ]
        )

        activator.activate(
            target: .window(appID: appID, windowID: "mail-1", restoreIfMinimized: false),
            contextsByID: [appID: context]
        )

        XCTAssertEqual(requestCallCount, 1)
        XCTAssertEqual(directFocusCount, 1)
    }

    func testPermissionCheckersPreferTestingOverridesOverLaunchArgumentOverrides() {
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest = AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let previousScreenTrusted = ScreenCapturePermissionChecker.hasPermissionOverrideForTesting
        let previousScreenRequest = ScreenCapturePermissionChecker.requestPermissionOverrideForTesting
        defer {
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting = previousAXRequest
            ScreenCapturePermissionChecker.hasPermissionOverrideForTesting = previousScreenTrusted
            ScreenCapturePermissionChecker.requestPermissionOverrideForTesting = previousScreenRequest
        }

        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { false }
        AccessibilityPermissionChecker.requestPermissionOverrideForTesting = { true }
        ScreenCapturePermissionChecker.hasPermissionOverrideForTesting = { false }
        ScreenCapturePermissionChecker.requestPermissionOverrideForTesting = { true }

        withLaunchArgumentsForTesting(
            [
                "FlowTab",
                "--flowtab-ui-ax-trusted", "true",
                "--flowtab-ui-screen-trusted", "true"
            ]
        ) {
            XCTAssertFalse(AccessibilityPermissionChecker.isTrusted())
            XCTAssertTrue(AccessibilityPermissionChecker.requestPermission())
            XCTAssertFalse(ScreenCapturePermissionChecker.hasScreenCapturePermission)
            XCTAssertTrue(ScreenCapturePermissionChecker.requestScreenCapturePermission())
        }
    }

    func testScreenCapturePermissionRequestHonorsFalseLaunchOverride() {
        let previousRequestOverride = ScreenCapturePermissionChecker.requestPermissionOverrideForTesting
        defer {
            ScreenCapturePermissionChecker.requestPermissionOverrideForTesting = previousRequestOverride
        }

        ScreenCapturePermissionChecker.requestPermissionOverrideForTesting = nil
        withLaunchArgumentsForTesting(["FlowTab", "--flowtab-ui-screen-trusted", "false"]) {
            XCTAssertFalse(ScreenCapturePermissionChecker.requestScreenCapturePermission())
        }
    }

    func testScreenCapturePermissionRequestTestingOverrideCanForceFalse() {
        let previousRequestOverride = ScreenCapturePermissionChecker.requestPermissionOverrideForTesting
        defer {
            ScreenCapturePermissionChecker.requestPermissionOverrideForTesting = previousRequestOverride
        }

        var requestCallCount = 0
        ScreenCapturePermissionChecker.requestPermissionOverrideForTesting = {
            requestCallCount += 1
            return false
        }

        withLaunchArgumentsForTesting(["FlowTab", "--flowtab-ui-screen-trusted", "true"]) {
            XCTAssertFalse(ScreenCapturePermissionChecker.requestScreenCapturePermission())
        }
        XCTAssertEqual(requestCallCount, 1)
    }

    func testScreenCapturePermissionResolutionHelperCoversOverrideLaunchAndLegacyPaths() {
        var testingOverrideCalls = 0
        var systemCalls = 0

        let testingOverrideResult = ScreenCapturePermissionChecker.resolvePermissionForTesting(
            testingOverride: {
                testingOverrideCalls += 1
                return false
            },
            launchOverride: true,
            supportsPermissionAPI: true,
            systemPermissionProvider: {
                systemCalls += 1
                return true
            }
        )
        XCTAssertFalse(testingOverrideResult)
        XCTAssertEqual(testingOverrideCalls, 1)
        XCTAssertEqual(systemCalls, 0)

        let launchOverrideResult = ScreenCapturePermissionChecker.resolvePermissionForTesting(
            testingOverride: nil,
            launchOverride: false,
            supportsPermissionAPI: true,
            systemPermissionProvider: {
                systemCalls += 1
                return true
            }
        )
        XCTAssertFalse(launchOverrideResult)
        XCTAssertEqual(systemCalls, 0)

        let legacyFallbackResult = ScreenCapturePermissionChecker.resolvePermissionForTesting(
            testingOverride: nil,
            launchOverride: nil,
            supportsPermissionAPI: false,
            systemPermissionProvider: {
                systemCalls += 1
                return false
            }
        )
        XCTAssertTrue(legacyFallbackResult)
        XCTAssertEqual(systemCalls, 0)

        let systemProviderResult = ScreenCapturePermissionChecker.resolvePermissionForTesting(
            testingOverride: nil,
            launchOverride: nil,
            supportsPermissionAPI: true,
            systemPermissionProvider: {
                systemCalls += 1
                return false
            }
        )
        XCTAssertFalse(systemProviderResult)
        XCTAssertEqual(systemCalls, 1)
    }

    func testSwitcherPanelWindowConfigurationSupportsFullscreenSpaces() {
        let behavior = SwitcherPanelWindowConfiguration.collectionBehavior
        let styleMask = SwitcherPanelWindowConfiguration.styleMask

        XCTAssertEqual(SwitcherPanelWindowConfiguration.level, .statusBar)
        XCTAssertTrue(styleMask.contains(.borderless))
        XCTAssertTrue(styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(behavior.contains(.ignoresCycle))
        XCTAssertTrue(behavior.contains(.stationary))
        XCTAssertTrue(behavior.contains(.canJoinAllApplications))
        XCTAssertFalse(behavior.contains(.moveToActiveSpace))
        XCTAssertFalse(behavior.contains(.transient))
    }

    func testSwitcherPanelWindowConfigurationElevatesLevelForFullscreenPresentation() {
        let normalLevel = SwitcherPanelWindowConfiguration.presentationLevel(
            frontmostWindowIsFullScreen: false
        )
        let fullScreenLevel = SwitcherPanelWindowConfiguration.presentationLevel(
            frontmostWindowIsFullScreen: true
        )

        XCTAssertEqual(normalLevel, .statusBar)
        XCTAssertGreaterThan(fullScreenLevel.rawValue, normalLevel.rawValue)
    }

    func testSwitcherPanelWindowConfigurationElevatesLevelWhenFullscreenDetectionFallsBack() {
        let fallbackLevel = SwitcherPanelWindowConfiguration.presentationLevel(
            frontmostWindowIsFullScreen: false,
            requiresFallbackElevation: true
        )

        XCTAssertEqual(SwitcherPanelWindowConfiguration.level, .statusBar)
        XCTAssertGreaterThan(
            fallbackLevel.rawValue,
            SwitcherPanelWindowConfiguration.level.rawValue
        )
    }

    func testSwitcherPanelWindowConfigurationAddsMoveToActiveSpaceOnlyForRecovery() {
        let defaultBehavior = SwitcherPanelWindowConfiguration.presentationCollectionBehavior()
        let recoveryBehavior = SwitcherPanelWindowConfiguration.presentationCollectionBehavior(
            mode: .activeSpaceMove
        )

        XCTAssertFalse(defaultBehavior.contains(.moveToActiveSpace))
        XCTAssertTrue(recoveryBehavior.contains(.moveToActiveSpace))
        XCTAssertFalse(recoveryBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(recoveryBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(recoveryBehavior.contains(.stationary))
        XCTAssertTrue(recoveryBehavior.contains(.canJoinAllApplications))
        XCTAssertFalse(recoveryBehavior.contains(.transient))
    }

    func testSwitcherPanelWindowConfigurationUsesNonActivatingBorderlessPanelStyle() {
        let styleMask = SwitcherPanelWindowConfiguration.styleMask

        XCTAssertTrue(styleMask.contains(.borderless))
        XCTAssertTrue(styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(styleMask.contains(.titled))
        XCTAssertFalse(styleMask.contains(.resizable))
    }

}
