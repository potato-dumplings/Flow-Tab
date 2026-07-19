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
            XCTAssertFalse(FlowTabTestLaunchOptions.opensInAppWindowSwitcherOnLaunch)
            XCTAssertTrue(FlowTabTestLaunchOptions.entersSearchOnLaunch)
        }

        withLaunchArgumentsForTesting(["FlowTab", "--flowtab-ui-open-in-app-window-switcher"]) {
            XCTAssertTrue(FlowTabTestLaunchOptions.opensSwitcherOnLaunch)
            XCTAssertTrue(FlowTabTestLaunchOptions.opensInAppWindowSwitcherOnLaunch)
            XCTAssertFalse(FlowTabTestLaunchOptions.entersSearchOnLaunch)
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
                "--flowtab-ui-runtime-log-level", "debug",
                "--flowtab-ui-suppress-home-on-launch",
                "--flowtab-ui-enable-verbose-logs",
                "--flowtab-ui-record-hotkey-reload-diagnostics"
            ]
        ) {
            XCTAssertTrue(FlowTabTestLaunchOptions.usesMockRuntimeProjection)
            XCTAssertTrue(FlowTabTestLaunchOptions.resetsUserDefaultsOnLaunch)
            XCTAssertEqual(FlowTabTestLaunchOptions.accessibilityTrustedOverride, true)
            XCTAssertEqual(FlowTabTestLaunchOptions.screenCaptureTrustedOverride, false)
            XCTAssertEqual(FlowTabTestLaunchOptions.seededLogCount, 12)
            XCTAssertEqual(FlowTabTestLaunchOptions.runtimeLogLevelOverrideRawValue, "debug")
            XCTAssertTrue(FlowTabTestLaunchOptions.suppressesHomeWindowOnLaunch)
            XCTAssertTrue(FlowTabTestLaunchOptions.enablesVerboseRuntimeLogs)
            XCTAssertTrue(FlowTabTestLaunchOptions.recordsHotkeyReloadDiagnostics)
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
            XCTAssertFalse(FlowTabTestLaunchOptions.enablesVerboseRuntimeLogs)
            XCTAssertFalse(FlowTabTestLaunchOptions.recordsHotkeyReloadDiagnostics)
        }
    }

    func testFlowTabTestLaunchOptionsIgnoreUITestArgumentsWithoutEnvironmentSentinel() {
        withLaunchArgumentsForTesting(
            [
                "FlowTab",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-open-switcher-search",
                "--flowtab-ui-ax-trusted", "true",
                "--flowtab-ui-screen-trusted", "false",
                "--flowtab-ui-seed-logs", "7"
            ],
            environment: [:]
        ) {
            XCTAssertFalse(FlowTabTestLaunchOptions.isRunningUITests)
            XCTAssertFalse(FlowTabTestLaunchOptions.usesMockRuntimeProjection)
            XCTAssertFalse(FlowTabTestLaunchOptions.resetsUserDefaultsOnLaunch)
            XCTAssertFalse(FlowTabTestLaunchOptions.opensSwitcherOnLaunch)
            XCTAssertFalse(FlowTabTestLaunchOptions.entersSearchOnLaunch)
            XCTAssertNil(FlowTabTestLaunchOptions.accessibilityTrustedOverride)
            XCTAssertNil(FlowTabTestLaunchOptions.screenCaptureTrustedOverride)
            XCTAssertNil(FlowTabTestLaunchOptions.seededLogCount)
        }

        withLaunchArgumentsForTesting(
            ["FlowTab", "--flowtab-ui-unknown"],
            environment: [
                FlowTabTestLaunchOptions.uiTestingEnvironmentKey:
                    FlowTabTestLaunchOptions.uiTestingEnvironmentValue
            ]
        ) {
            XCTAssertFalse(FlowTabTestLaunchOptions.isRunningUITests)
        }
    }

    func testFlowTabTestLaunchOptionsSuppressesHomeWindowForUnitTestHost() {
        withLaunchArgumentsForTesting(
            ["FlowTab"],
            environment: [
                FlowTabTestLaunchOptions.unitTestingBundlePathEnvironmentKey:
                    "/tmp/FlowTabTests.xctest"
            ]
        ) {
            XCTAssertTrue(FlowTabTestLaunchOptions.isRunningUnitTests)
            XCTAssertTrue(FlowTabTestLaunchOptions.suppressesHomeWindowOnLaunch)
        }

        withLaunchArgumentsForTesting(
            ["FlowTab"],
            environment: [
                FlowTabTestLaunchOptions.unitTestingBundlePathEnvironmentKey:
                    "/tmp/FlowTabUITests.xctest"
            ]
        ) {
            XCTAssertFalse(FlowTabTestLaunchOptions.isRunningUnitTests)
            XCTAssertFalse(FlowTabTestLaunchOptions.suppressesHomeWindowOnLaunch)
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

    private func uiTestFullRepairProjectionPayload(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> RuntimeFullRepairProjectionPayload? {
        guard let dataset = FlowTabUITestRuntimeProjectionDataset.current() else {
            XCTFail("Expected UI test runtime projection dataset", file: file, line: line)
            return nil
        }
        return RuntimeFullRepairProjectionPayload(
            apps: dataset.appSwitcherApps,
            contextsByID: dataset.appSwitcherContextsByID,
            appDirectoryEntries: dataset.appDirectoryEntries
        )
    }

    func testUITestMockDatasetBuildsExplicitFullRepairProjectionPayloadWhenLaunchFlagEnabled() {
        withLaunchArgumentsForTesting(["FlowTab", "--flowtab-ui-mock-runtime"]) {
            let uiTestDataset = FlowTabUITestRuntimeProjectionDataset.current()
            let fullRepairPayload = uiTestFullRepairProjectionPayload()

            XCTAssertEqual(fullRepairPayload?.apps.count, 6)
            XCTAssertEqual(fullRepairPayload?.contextsByID.count, 0)
            XCTAssertEqual(fullRepairPayload?.apps.first?.id, "com.flowtab.mock.mail")
            XCTAssertEqual(fullRepairPayload?.apps.first?.windows.count, 2)
            XCTAssertEqual(fullRepairPayload?.appDirectoryEntries.count, 6)
            XCTAssertEqual(fullRepairPayload?.appDirectoryEntries.first?.appID, "com.flowtab.mock.mail")

            let currentAppWindowPayload = uiTestDataset?.currentAppWindowPayloadsByAppID["com.flowtab.mock.mail"]
            XCTAssertNotNil(currentAppWindowPayload)
            XCTAssertEqual(currentAppWindowPayload?.candidate.id, "com.flowtab.mock.mail")
            XCTAssertEqual(
                currentAppWindowPayload?.candidate.windows.map(\.id),
                ["mock-mail-inbox", "mock-mail-draft"]
            )
            XCTAssertEqual(currentAppWindowPayload?.summary.windowCount, 2)
            XCTAssertEqual(currentAppWindowPayload?.context.appID, "com.flowtab.mock.mail")
            XCTAssertEqual(currentAppWindowPayload?.context.windowsByID.count, 2)
            XCTAssertEqual(
                currentAppWindowPayload?.appDirectoryEntries.map(\.appID),
                ["com.flowtab.mock.mail"]
            )

            let browserPayload = uiTestDataset?.currentAppWindowPayloadsByAppID["com.flowtab.mock.browser"]
            XCTAssertEqual(browserPayload?.summary.displayName, "Mock Browser")
            XCTAssertEqual(browserPayload?.summary.windowCount, 1)
            XCTAssertEqual(fullRepairPayload?.apps.last?.id, "com.flowtab.mock.file-transfer-assistant")
            XCTAssertNil(uiTestDataset?.currentAppWindowPayloadsByAppID["com.flowtab.mock.missing"])
        }
    }

    func testAppInventoryServiceReadsUITestRuntimeProjectionDataset() {
        withLaunchArgumentsForTesting(["FlowTab", "--flowtab-ui-mock-runtime"]) {
            let recordsByID = Dictionary(
                uniqueKeysWithValues: AppInventoryService().installedApps().map { ($0.id, $0) }
            )

            XCTAssertEqual(recordsByID["com.flowtab.mock.mail"]?.displayName, "Mock Mail")
            XCTAssertEqual(recordsByID["com.flowtab.mock.mail"]?.bundleIdentifier, "com.flowtab.mock.mail")
            XCTAssertNil(recordsByID["com.flowtab.mock.mail"]?.path)
            XCTAssertTrue(recordsByID["com.flowtab.mock.mail"]?.isRunning == true)
            XCTAssertEqual(recordsByID["com.flowtab.mock.browser"]?.displayName, "Mock Browser")
            XCTAssertEqual(recordsByID["com.flowtab.mock.file-transfer-assistant"]?.displayName, "文件传输助手")
        }
    }

    func testRuntimeProjectionServiceDefaultFullRepairCommitsEvidenceThroughMainTableProjection() throws {
        withLaunchArgumentsForTesting(["FlowTab", "--flowtab-ui-mock-runtime"]) {
            let store = RuntimeReadModelStore()
            let service = RuntimeProjectionService(
                label: "FlowTabTests.RuntimeProjectionService.DefaultFullRepair",
                readModelStore: store
            )

            service.requestAppSwitcherProjectionMaintenance(reason: .switcherSessionStarted)
            service.waitForMaintenanceQueueForTesting()

            guard let projection = store.readAppSwitcherProjection() else {
                XCTFail("Expected default full repair executor to commit evidence through main-table projection")
                return
            }
            XCTAssertEqual(projection.apps.count, 6)
            let appsByID = Dictionary(uniqueKeysWithValues: projection.apps.map { ($0.id, $0) })
            XCTAssertEqual(appsByID["com.flowtab.mock.mail"]?.displayName, "Mock Mail")
            XCTAssertEqual(appsByID["com.flowtab.mock.mail"]?.windows.map(\.id), [])
            let appDirectoryEntries = store.readAppDirectoryProjection()?.entries
            XCTAssertEqual(appDirectoryEntries?.count, 6)
            XCTAssertTrue(appDirectoryEntries?.contains { $0.appID == "com.flowtab.mock.mail" } == true)
            XCTAssertFalse(projection.freshness.isCompleteForScope)
            XCTAssertEqual(store.diagnostics().dirtyAppIDs, [])
        }
    }

    func testRuntimeProjectionRepairProviderMockRuntimeKeepsCurrentAppPayloadsScopedPerApp() {
        withLaunchArgumentsForTesting(["FlowTab", "--flowtab-ui-mock-runtime"]) {
            let uiTestDataset = FlowTabUITestRuntimeProjectionDataset.current()

            let mailPayload = uiTestDataset?.currentAppWindowPayloadsByAppID["com.flowtab.mock.mail"]
            XCTAssertEqual(mailPayload?.candidate.windows.map(\.title), ["Inbox", "Draft"])
            XCTAssertFalse(mailPayload?.candidate.windows.contains(where: { $0.title == "Docs" }) ?? true)

            let browserPayload = uiTestDataset?.currentAppWindowPayloadsByAppID["com.flowtab.mock.browser"]
            XCTAssertEqual(browserPayload?.candidate.windows.map(\.title), ["Docs"])
            XCTAssertFalse(browserPayload?.candidate.windows.contains(where: { $0.title == "Inbox" }) ?? true)
        }
    }

    func testRuntimeProjectionRepairProviderMockSingleAppFiveWindowsProjectionPayloadKeepsAllWindowsInHomeLayer() {
        let expectedWindowIDs = [
            "mock-browser-normal-1",
            "mock-browser-normal-2",
            "mock-browser-fullscreen-1",
            "mock-browser-fullscreen-2",
            "mock-browser-fullscreen-3"
        ]

        withLaunchArgumentsForTesting(
            [
                "FlowTab",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-mock-runtime-variant",
                "single-app-five-windows"
            ]
        ) {
            let uiTestDataset = FlowTabUITestRuntimeProjectionDataset.current()
            let fullRepairPayload = uiTestFullRepairProjectionPayload()

            XCTAssertEqual(fullRepairPayload?.apps.count, 1)
            XCTAssertEqual(fullRepairPayload?.apps.first?.id, "com.flowtab.mock.browser")
            XCTAssertEqual(fullRepairPayload?.apps.first?.windows.count, 5)
            XCTAssertEqual(fullRepairPayload?.apps.first?.windows.map(\.id), expectedWindowIDs)

            let currentAppWindowPayload = uiTestDataset?.currentAppWindowPayloadsByAppID["com.flowtab.mock.browser"]
            XCTAssertNotNil(currentAppWindowPayload)
            XCTAssertEqual(currentAppWindowPayload?.summary.windowCount, 5)
            XCTAssertEqual(currentAppWindowPayload?.summary.appID, "com.flowtab.mock.browser")
            XCTAssertEqual(currentAppWindowPayload?.candidate.windows.map(\.id), expectedWindowIDs)
            XCTAssertEqual(currentAppWindowPayload?.context.windowsByID.count, 5)
        }
    }

    func testRuntimeProjectionRepairProviderMockSingleAppFiveWindowsCGOffSpaceProjectionPayloadKeepsAllWindowsInHomeLayer() {
        let expectedWindowIDs = [
            "cg:100:240001",
            "cg:100:240002",
            "cg:100:243747",
            "cg:100:243679",
            "cg:100:240029"
        ]

        withLaunchArgumentsForTesting(
            [
                "FlowTab",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-mock-runtime-variant",
                "single-app-five-windows-cg-offspace"
            ]
        ) {
            let uiTestDataset = FlowTabUITestRuntimeProjectionDataset.current()
            let fullRepairPayload = uiTestFullRepairProjectionPayload()

            XCTAssertEqual(fullRepairPayload?.apps.count, 1)
            XCTAssertEqual(fullRepairPayload?.apps.first?.id, "com.flowtab.mock.browser")
            XCTAssertEqual(fullRepairPayload?.apps.first?.windows.count, 5)
            XCTAssertEqual(fullRepairPayload?.apps.first?.windows.map(\.id), expectedWindowIDs)

            let currentAppWindowPayload = uiTestDataset?.currentAppWindowPayloadsByAppID["com.flowtab.mock.browser"]
            XCTAssertNotNil(currentAppWindowPayload)
            XCTAssertEqual(currentAppWindowPayload?.summary.windowCount, 5)
            XCTAssertEqual(currentAppWindowPayload?.summary.appID, "com.flowtab.mock.browser")
            XCTAssertEqual(currentAppWindowPayload?.candidate.windows.map(\.id), expectedWindowIDs)
            XCTAssertEqual(currentAppWindowPayload?.context.windowsByID.count, 5)
        }
    }

    func testRuntimeProjectionRepairProviderMockSingleAppFiveWindowsCGOffSpaceProjectionPayloadUsesExplicitTitles() {
        withLaunchArgumentsForTesting(
            [
                "FlowTab",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-mock-runtime-variant",
                "single-app-five-windows-cg-offspace-titled"
            ]
        ) {
            let uiTestDataset = FlowTabUITestRuntimeProjectionDataset.current()
            let fullRepairPayload = uiTestFullRepairProjectionPayload()
            XCTAssertEqual(fullRepairPayload?.apps.count, 1)
            XCTAssertEqual(
                fullRepairPayload?.apps.first?.windows.map(\.title),
                ["Normal 1", "Normal 2", "Fullscreen 3", "Fullscreen 4", "Fullscreen 5"]
            )

            let currentAppWindowPayload = uiTestDataset?.currentAppWindowPayloadsByAppID["com.flowtab.mock.browser"]
            XCTAssertEqual(
                currentAppWindowPayload?.candidate.windows.map(\.title),
                ["Normal 1", "Normal 2", "Fullscreen 3", "Fullscreen 4", "Fullscreen 5"]
            )
        }
    }

    func testRuntimeProjectionRepairProviderRealPathWithoutAccessibilityBuildsMainTableProjectionPayload() {
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
            let windowRecordStore = RuntimeWindowRecordStore()
            let repairProvider = RuntimeProjectionRepairProvider(windowRecordStore: windowRecordStore)
            let projectionBuilder = RuntimeMainTableProjectionBuilder(
                windowRecordStore: windowRecordStore
            )
            let repairEvidence = repairProvider.fullRepairEvidence()
            let projectionPayload = projectionBuilder.appSwitcherProjectionPayloadFromMainTables(
                appDirectoryEntries: repairEvidence.appDirectoryEntries,
                generatedAt: Date.timeIntervalSinceReferenceDate
            )

            XCTAssertFalse(repairEvidence.appDirectoryEntries.isEmpty)
            guard let windowRecordRefresh = repairEvidence.windowRecordRefresh else {
                XCTFail("expected full repair to report WindowRecord refresh evidence separately")
                return
            }
            XCTAssertEqual(windowRecordRefresh.runningAppCount, repairEvidence.appDirectoryEntries.count)
            XCTAssertEqual(windowRecordRefresh.projectedWindowPIDCount, 0)
            XCTAssertEqual(windowRecordRefresh.projectedWindowCount, 0)
            XCTAssertFalse(projectionPayload?.apps.isEmpty ?? true)
            XCTAssertEqual(projectionPayload?.contextsByID.count, projectionPayload?.apps.count)
            XCTAssertTrue(projectionPayload?.apps.allSatisfy { $0.windows.isEmpty } == true)
            XCTAssertTrue(projectionPayload?.contextsByID.values.allSatisfy { $0.windowsByID.isEmpty } == true)
            XCTAssertFalse(projectionPayload?.hasCompleteWindowCoverage ?? true)
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
                    axWindow: liveHandle,
                    lastConfirmationSource: .publicExactMatch
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
        XCTAssertEqual(
            SwitcherPanelWindowConfiguration.resolvedSharingType(isRunningUITests: false),
            .none
        )
        XCTAssertEqual(
            SwitcherPanelWindowConfiguration.resolvedSharingType(isRunningUITests: true),
            .readOnly
        )
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

    func testRuntimeSpaceTopologySignatureDetectsCurrentSpaceFullscreenByDisplay() {
        let signature = RuntimeSpaceTopologySignature(displays: [
            RuntimeDisplaySpaceSignature(
                displayID: 1,
                currentSpaceID: 7,
                spaceIDs: [7, 8],
                windowIDsBySpaceID: [
                    7: [240_001],
                    8: [240_002]
                ],
                fullscreenWindowIDBySpaceID: [
                    8: 240_002
                ]
            ),
            RuntimeDisplaySpaceSignature(
                displayID: 2,
                currentSpaceID: 11,
                spaceIDs: [11],
                windowIDsBySpaceID: [
                    11: [250_001]
                ],
                fullscreenWindowIDBySpaceID: [
                    11: 250_001
                ]
            )
        ])

        XCTAssertFalse(signature.hasFullscreenWindowOnCurrentSpace(displayID: 1))
        XCTAssertTrue(signature.hasFullscreenWindowOnCurrentSpace(displayID: 2))
        XCTAssertTrue(signature.hasFullscreenWindowOnCurrentSpace(displayID: nil))
        XCTAssertFalse(signature.hasFullscreenWindowOnCurrentSpace(displayID: 3))
    }

    func testSwitcherPanelWindowConfigurationDoesNotElevateWithoutFullscreenProjectionProof() {
        let normalLevel = SwitcherPanelWindowConfiguration.presentationLevel(
            frontmostWindowIsFullScreen: false
        )

        XCTAssertEqual(normalLevel, .statusBar)
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
