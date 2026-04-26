import AppKit
import Carbon
import CoreGraphics
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testFlowTabAppInitStartsMRUTracking() {
        let previousTracker = FlowTabApp.mruTracker
        let tracker = SpyMRUTracker()
        defer {
            FlowTabApp.mruTracker = previousTracker
        }

        FlowTabApp.mruTracker = tracker

        _ = FlowTabApp()

        XCTAssertEqual(tracker.startCallCount, 1)
    }

    @MainActor
    func testAppDelegateLaunchInstallsObserversPromptsAccessibilityAndStartsStressRunner() async {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        let previousActivationOverride = AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest = AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        let takeoverController = SpyCommandTabTakeoverController()
        let stressRunner = SpyStressRunner()
        defer {
            AppDelegate.testHooks = previousHooks
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = previousActivationOverride
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting = previousAXRequest
            clearIsolatedUserDefaults(userDefaults)
        }

        var accessibilityPromptCount = 0
        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { false }
        AccessibilityPermissionChecker.requestPermissionOverrideForTesting = {
            accessibilityPromptCount += 1
            return false
        }

        let openHome = expectation(description: "open home after launch")
        HomeTabState.shared.selectedTab = .settings
        AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = {
            openHome.fulfill()
        }
        AppDelegate.testHooks = AppDelegate.TestHooks(
            userDefaults: userDefaults,
            makePanelController: nil,
            makeHotkeyMonitor: { configuration, signature, forwardHotkeyID, backwardHotkeyID in
                hotkeyFactory.make(
                    configuration: configuration,
                    signature: signature,
                    forwardHotkeyID: forwardHotkeyID,
                    backwardHotkeyID: backwardHotkeyID
                )
            },
            commandTabTakeoverController: takeoverController,
            stressRunner: stressRunner
        )

        let delegate = AppDelegate()
        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )

        await fulfillment(of: [openHome], timeout: 1.0)
        XCTAssertEqual(HomeTabState.shared.selectedTab, .home)
        XCTAssertTrue(delegate.hasPanelControllerForTesting)
        XCTAssertTrue(delegate.hasMainHotkeyMonitorForTesting)
        XCTAssertTrue(delegate.hasInAppHotkeyMonitorForTesting)
        XCTAssertTrue(delegate.hasHotkeyObserverForTesting)
        XCTAssertTrue(delegate.hasAppVisibilityObserverForTesting)
        XCTAssertTrue(delegate.hasLanguageObserverForTesting)
        XCTAssertTrue(delegate.hasStatusItemForTesting)
        XCTAssertEqual(accessibilityPromptCount, 1)
        XCTAssertTrue(userDefaults.bool(forKey: AppPreferenceKeys.hasPromptedAccessibilityPermission))
        XCTAssertEqual(stressRunner.startCallCount, 1)
        XCTAssertEqual(takeoverController.reconcileCalls, [false])
        XCTAssertEqual(hotkeyFactory.records.map(\.signature), [0x46544142, 0x4654574E])
        XCTAssertEqual(hotkeyFactory.records.map(\.forwardHotkeyID), [1, 101])
        XCTAssertEqual(hotkeyFactory.records.map(\.backwardHotkeyID), [2, 102])
    }

    @MainActor
    func testAppDelegateLaunchSkipsAccessibilityPromptWhenAlreadyPromptedOrReminderDisabled() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        let previousActivationOverride = AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest = AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        defer {
            AppDelegate.testHooks = previousHooks
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = previousActivationOverride
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting = previousAXRequest
            clearIsolatedUserDefaults(userDefaults)
        }

        let cases: [(name: String, configure: (UserDefaults) -> Void)] = [
            ("alreadyPrompted", { defaults in
                defaults.set(true, forKey: AppPreferenceKeys.hasPromptedAccessibilityPermission)
            }),
            ("reminderDisabled", { defaults in
                defaults.set(false, forKey: AppPreferenceKeys.showPermissionReminder)
            })
        ]

        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { false }
        AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = {}

        for item in cases {
            userDefaults.removePersistentDomain(
                forName: userDefaults.string(forKey: "FlowTabPriorityCoverageTestsSuiteName") ?? ""
            )
            item.configure(userDefaults)

            let hotkeyFactory = SpyHotkeyMonitorFactory()
            var promptCount = 0
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting = {
                promptCount += 1
                return false
            }
            AppDelegate.testHooks = AppDelegate.TestHooks(
                userDefaults: userDefaults,
                makePanelController: nil,
                makeHotkeyMonitor: { configuration, signature, forwardHotkeyID, backwardHotkeyID in
                    hotkeyFactory.make(
                        configuration: configuration,
                        signature: signature,
                        forwardHotkeyID: forwardHotkeyID,
                        backwardHotkeyID: backwardHotkeyID
                    )
                },
                commandTabTakeoverController: SpyCommandTabTakeoverController(),
                stressRunner: SpyStressRunner()
            )

            let delegate = AppDelegate()
            delegate.applicationDidFinishLaunching(
                Notification(name: NSApplication.didFinishLaunchingNotification)
            )

            XCTAssertEqual(promptCount, 0, "Unexpected accessibility prompt for \(item.name)")
        }
    }

    @MainActor
    func testAppDelegateTerminationRemovesObserversStopsHotkeyMonitorsAndRestoresTakeover() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        let previousActivationOverride = AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest = AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        let takeoverController = SpyCommandTabTakeoverController()
        defer {
            AppDelegate.testHooks = previousHooks
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = previousActivationOverride
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting = previousAXRequest
            clearIsolatedUserDefaults(userDefaults)
        }

        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { true }
        AccessibilityPermissionChecker.requestPermissionOverrideForTesting = { true }
        AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = {}
        AppDelegate.testHooks = AppDelegate.TestHooks(
            userDefaults: userDefaults,
            makePanelController: nil,
            makeHotkeyMonitor: { configuration, signature, forwardHotkeyID, backwardHotkeyID in
                hotkeyFactory.make(
                    configuration: configuration,
                    signature: signature,
                    forwardHotkeyID: forwardHotkeyID,
                    backwardHotkeyID: backwardHotkeyID
                )
            },
            commandTabTakeoverController: takeoverController,
            stressRunner: SpyStressRunner()
        )

        let delegate = AppDelegate()
        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        delegate.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )

        XCTAssertFalse(delegate.hasHotkeyObserverForTesting)
        XCTAssertFalse(delegate.hasAppVisibilityObserverForTesting)
        XCTAssertFalse(delegate.hasLanguageObserverForTesting)
        XCTAssertEqual(hotkeyFactory.records.count, 2)
        XCTAssertEqual(hotkeyFactory.records[0].monitor.stopCallCount, 1)
        XCTAssertEqual(hotkeyFactory.records[1].monitor.stopCallCount, 1)
        XCTAssertEqual(takeoverController.restoreCallCount, 1)
    }

    @MainActor
    func testAppDelegateHotkeyObserverUsesPostedConfigurationsImmediately() async {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        let previousSharedDelegate = AppDelegate.shared
        let previousActivationOverride = AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest = AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        let takeoverController = SpyCommandTabTakeoverController()
        var delegate: AppDelegate?
        defer {
            delegate?.applicationWillTerminate(
                Notification(name: NSApplication.willTerminateNotification)
            )
            AppDelegate.testHooks = previousHooks
            AppDelegate.shared = previousSharedDelegate
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = previousActivationOverride
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting = previousAXRequest
            clearIsolatedUserDefaults(userDefaults)
        }

        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { true }
        AccessibilityPermissionChecker.requestPermissionOverrideForTesting = { true }
        AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = {}
        AppDelegate.testHooks = AppDelegate.TestHooks(
            userDefaults: userDefaults,
            makePanelController: nil,
            makeHotkeyMonitor: { configuration, signature, forwardHotkeyID, backwardHotkeyID in
                hotkeyFactory.make(
                    configuration: configuration,
                    signature: signature,
                    forwardHotkeyID: forwardHotkeyID,
                    backwardHotkeyID: backwardHotkeyID
                )
            },
            commandTabTakeoverController: takeoverController,
            stressRunner: SpyStressRunner()
        )

        let appDelegate = AppDelegate()
        delegate = appDelegate
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        let baselineRecordCount = hotkeyFactory.records.count
        XCTAssertGreaterThanOrEqual(baselineRecordCount, 2)
        let previousMainMonitor = hotkeyFactory.records[baselineRecordCount - 2].monitor
        let previousInAppMonitor = hotkeyFactory.records[baselineRecordCount - 1].monitor

        let request = HotkeyRegistrationRequest(
            mainConfiguration: SwitcherHotkeyConfiguration(
                primaryModifier: .command,
                mainKey: .tab,
                quitKey: .q
            ),
            inAppWindowConfiguration: SwitcherHotkeyConfiguration(
                primaryModifier: .option,
                mainKey: .grave,
                quitKey: .q
            )
        )
        NotificationCenter.default.post(
            name: .flowTabReRegisterHotkeys,
            object: nil,
            userInfo: request.notificationUserInfo
        )

        try? await Task.sleep(nanoseconds: 120_000_000)

        let newRecords = Array(hotkeyFactory.records.dropFirst(baselineRecordCount))
        XCTAssertEqual(newRecords.count, 2)
        XCTAssertGreaterThanOrEqual(previousMainMonitor.stopCallCount, 1)
        XCTAssertGreaterThanOrEqual(previousInAppMonitor.stopCallCount, 1)
        XCTAssertTrue(
            newRecords.contains {
                $0.signature == 0x46544142
                    && $0.configuration.primaryModifier == .command
                    && $0.configuration.mainKey == .tab
                    && $0.configuration.quitKey == .q
            }
        )
        XCTAssertTrue(
            newRecords.contains {
                $0.signature == 0x4654574E
                    && $0.configuration.primaryModifier == .option
                    && $0.configuration.mainKey == .grave
                    && $0.configuration.quitKey == .q
            }
        )
        XCTAssertEqual(takeoverController.reconcileCalls.last, true)
    }

    @MainActor
    func testAppDelegateDirectHotkeyReloadRegistersImmediatelyWithoutNotificationEcho() async {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        let previousSharedDelegate = AppDelegate.shared
        let previousActivationOverride = AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest = AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        let takeoverController = SpyCommandTabTakeoverController()
        var delegate: AppDelegate?
        defer {
            delegate?.applicationWillTerminate(
                Notification(name: NSApplication.willTerminateNotification)
            )
            AppDelegate.testHooks = previousHooks
            AppDelegate.shared = previousSharedDelegate
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = previousActivationOverride
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting = previousAXRequest
            clearIsolatedUserDefaults(userDefaults)
        }

        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { true }
        AccessibilityPermissionChecker.requestPermissionOverrideForTesting = { true }
        AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = {}
        AppDelegate.testHooks = AppDelegate.TestHooks(
            userDefaults: userDefaults,
            makePanelController: nil,
            makeHotkeyMonitor: { configuration, signature, forwardHotkeyID, backwardHotkeyID in
                hotkeyFactory.make(
                    configuration: configuration,
                    signature: signature,
                    forwardHotkeyID: forwardHotkeyID,
                    backwardHotkeyID: backwardHotkeyID
                )
            },
            commandTabTakeoverController: takeoverController,
            stressRunner: SpyStressRunner()
        )

        let appDelegate = AppDelegate()
        delegate = appDelegate
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        let baselineRecordCount = hotkeyFactory.records.count
        XCTAssertGreaterThanOrEqual(baselineRecordCount, 2)
        let previousMainMonitor = hotkeyFactory.records[baselineRecordCount - 2].monitor
        let previousInAppMonitor = hotkeyFactory.records[baselineRecordCount - 1].monitor

        let request = HotkeyRegistrationRequest(
            mainConfiguration: SwitcherHotkeyConfiguration(
                primaryModifier: .command,
                mainKey: .tab,
                quitKey: .q
            ),
            inAppWindowConfiguration: SwitcherHotkeyConfiguration(
                primaryModifier: .option,
                mainKey: .grave,
                quitKey: .q
            )
        )
        appDelegate.requestHotkeyReload(using: request, source: "test_direct")

        try? await Task.sleep(nanoseconds: 120_000_000)

        let newRecords = Array(hotkeyFactory.records.dropFirst(baselineRecordCount))
        XCTAssertEqual(newRecords.count, 2)
        XCTAssertGreaterThanOrEqual(previousMainMonitor.stopCallCount, 1)
        XCTAssertGreaterThanOrEqual(previousInAppMonitor.stopCallCount, 1)
        XCTAssertTrue(
            newRecords.contains {
                $0.signature == 0x46544142
                    && $0.configuration.primaryModifier == .command
                    && $0.configuration.mainKey == .tab
                    && $0.configuration.quitKey == .q
            }
        )
        XCTAssertTrue(
            newRecords.contains {
                $0.signature == 0x4654574E
                    && $0.configuration.primaryModifier == .option
                    && $0.configuration.mainKey == .grave
                    && $0.configuration.quitKey == .q
            }
        )
        XCTAssertEqual(takeoverController.reconcileCalls.last, true)
    }

    @MainActor
    func testAppDelegateReloadedHotkeyMonitorRoutesCallbacksToSwitcherSession() async {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        let previousSharedDelegate = AppDelegate.shared
        let previousActivationOverride = AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest = AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let standardDefaults = UserDefaults.standard
        let preferenceKeys = [
            AppPreferenceKeys.hotkeyPrimaryModifier,
            AppPreferenceKeys.hotkeyMainKey,
            AppPreferenceKeys.hotkeyQuitKey
        ]
        let previousPreferenceValues = Dictionary(
            uniqueKeysWithValues: preferenceKeys.map { key in
                (key, standardDefaults.object(forKey: key))
            }
        )
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        let panelController = SwitcherPanelController()
        var delegate: AppDelegate?
        defer {
            delegate?.applicationWillTerminate(
                Notification(name: NSApplication.willTerminateNotification)
            )
            AppDelegate.testHooks = previousHooks
            AppDelegate.shared = previousSharedDelegate
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = previousActivationOverride
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting = previousAXRequest
            preferenceKeys.forEach { key in
                restoreUserDefaultsValue(
                    previousPreferenceValues[key] ?? nil,
                    forKey: key,
                    userDefaults: standardDefaults
                )
            }
            panelController.cancelSelectionForTesting()
            clearIsolatedUserDefaults(userDefaults)
        }

        panelController.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
        }
        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { true }
        AccessibilityPermissionChecker.requestPermissionOverrideForTesting = { true }
        AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = {}
        AppDelegate.testHooks = AppDelegate.TestHooks(
            userDefaults: userDefaults,
            makePanelController: { panelController },
            makeHotkeyMonitor: { configuration, signature, forwardHotkeyID, backwardHotkeyID in
                hotkeyFactory.make(
                    configuration: configuration,
                    signature: signature,
                    forwardHotkeyID: forwardHotkeyID,
                    backwardHotkeyID: backwardHotkeyID
                )
            },
            commandTabTakeoverController: SpyCommandTabTakeoverController(),
            stressRunner: SpyStressRunner()
        )

        let appDelegate = AppDelegate()
        delegate = appDelegate
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        let baselineRecordCount = hotkeyFactory.records.count

        let request = HotkeyRegistrationRequest(
            mainConfiguration: SwitcherHotkeyConfiguration(
                primaryModifier: .option,
                mainKey: .space,
                quitKey: .z
            ),
            inAppWindowConfiguration: SwitcherHotkeyConfiguration(
                primaryModifier: .command,
                mainKey: .a,
                quitKey: .q
            )
        )
        standardDefaults.set(request.mainConfiguration.primaryModifier.rawValue, forKey: AppPreferenceKeys.hotkeyPrimaryModifier)
        standardDefaults.set(request.mainConfiguration.mainKey.rawValue, forKey: AppPreferenceKeys.hotkeyMainKey)
        standardDefaults.set(request.mainConfiguration.quitKey.rawValue, forKey: AppPreferenceKeys.hotkeyQuitKey)

        appDelegate.requestHotkeyReload(using: request, source: "test_settings_reload")

        let newRecords = Array(hotkeyFactory.records.dropFirst(baselineRecordCount))
        XCTAssertEqual(newRecords.count, 2)
        guard let mainRecord = newRecords.first(where: { $0.signature == 0x46544142 }) else {
            XCTFail("Expected reloaded main hotkey monitor")
            return
        }
        XCTAssertEqual(mainRecord.configuration.primaryModifier, .option)
        XCTAssertEqual(mainRecord.configuration.mainKey, .space)
        XCTAssertEqual(mainRecord.configuration.quitKey, .z)
        XCTAssertEqual(mainRecord.configuration.forwardKeyCode, UInt32(SwitcherHotkeyKey.space.keyCode))
        XCTAssertEqual(mainRecord.configuration.forwardModifiers, SwitcherPrimaryModifier.option.carbonModifier)

        mainRecord.monitor.onHotkeyPressed?(false)
        XCTAssertNotNil(panelController.modelForTesting.session)
        let initialSelectedAppID = panelController.modelForTesting.selectedApp?.id

        panelController.globalPrimaryModifierPressedOverride = true
        mainRecord.monitor.onHotkeyPressed?(false)
        XCTAssertNotEqual(panelController.modelForTesting.selectedApp?.id, initialSelectedAppID)

        panelController.globalPrimaryModifierPressedOverride = false
        mainRecord.monitor.onHotkeyReleased?(false)
        try? await Task.sleep(nanoseconds: 180_000_000)
        XCTAssertNil(panelController.modelForTesting.session)
    }

    @MainActor
    func testAppDelegateSkipsInAppHotkeyMonitorWhenShortcutConflictsWithMainHotkey() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        let previousActivationOverride = AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest = AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        defer {
            AppDelegate.testHooks = previousHooks
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = previousActivationOverride
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting = previousAXRequest
            clearIsolatedUserDefaults(userDefaults)
        }

        userDefaults.set(
            SwitcherPrimaryModifier.option.rawValue,
            forKey: AppPreferenceKeys.inAppWindowHotkeyPrimaryModifier
        )
        userDefaults.set(
            SwitcherHotkeyKey.tab.rawValue,
            forKey: AppPreferenceKeys.inAppWindowHotkeyMainKey
        )
        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { true }
        AccessibilityPermissionChecker.requestPermissionOverrideForTesting = { true }
        AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = {}
        AppDelegate.testHooks = AppDelegate.TestHooks(
            userDefaults: userDefaults,
            makePanelController: nil,
            makeHotkeyMonitor: { configuration, signature, forwardHotkeyID, backwardHotkeyID in
                hotkeyFactory.make(
                    configuration: configuration,
                    signature: signature,
                    forwardHotkeyID: forwardHotkeyID,
                    backwardHotkeyID: backwardHotkeyID
                )
            },
            commandTabTakeoverController: SpyCommandTabTakeoverController(),
            stressRunner: SpyStressRunner()
        )

        let delegate = AppDelegate()
        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )

        XCTAssertTrue(delegate.hasMainHotkeyMonitorForTesting)
        XCTAssertFalse(delegate.hasInAppHotkeyMonitorForTesting)
        XCTAssertEqual(hotkeyFactory.records.count, 1)
        XCTAssertEqual(hotkeyFactory.records.first?.signature, 0x46544142)
    }

    @MainActor
    func testAppDelegateLaunchWithUITestBootstrapArgumentsSeedsLogsAndOpensSearch() async {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        let previousSharedDelegate = AppDelegate.shared
        let previousActivationOverride = AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest = AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let previousLaunchArguments = FlowTabTestLaunchOptions.argumentsOverrideForTesting
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        let takeoverController = SpyCommandTabTakeoverController()
        let stressRunner = SpyStressRunner()
        let panelController = SwitcherPanelController()
        var delegate: AppDelegate?
        defer {
            delegate?.applicationWillTerminate(
                Notification(name: NSApplication.willTerminateNotification)
            )
            AppDelegate.testHooks = previousHooks
            AppDelegate.shared = previousSharedDelegate
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = previousActivationOverride
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting = previousAXRequest
            FlowTabTestLaunchOptions.argumentsOverrideForTesting = previousLaunchArguments
            RuntimeDiagnostics.shared.clear()
            clearIsolatedUserDefaults(userDefaults)
        }

        panelController.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
        }

        userDefaults.set(false, forKey: AppPreferenceKeys.showShortcutHint)
        userDefaults.set(
            RuntimeLogLevel.error.rawValue,
            forKey: AppPreferenceKeys.runtimeLogLevel
        )
        userDefaults.set(true, forKey: CommandTabTakeoverController.takeoverMarkerKey)
        HomeTabState.shared.selectedTab = .logs

        RuntimeDiagnostics.shared.clear()
        RuntimeDiagnostics.shared.log(
            level: .info,
            category: "UnitTest",
            message: "before-seed-cleanup"
        )

        FlowTabTestLaunchOptions.argumentsOverrideForTesting = [
            "FlowTab",
            "--flowtab-ui-reset-defaults",
            "--flowtab-ui-runtime-log-level", "warn",
            "--flowtab-ui-seed-logs", "3",
            "--flowtab-ui-open-switcher-search"
        ]
        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { true }
        AccessibilityPermissionChecker.requestPermissionOverrideForTesting = { true }
        AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = {}
        AppDelegate.testHooks = AppDelegate.TestHooks(
            userDefaults: userDefaults,
            makePanelController: { panelController },
            makeHotkeyMonitor: { configuration, signature, forwardHotkeyID, backwardHotkeyID in
                hotkeyFactory.make(
                    configuration: configuration,
                    signature: signature,
                    forwardHotkeyID: forwardHotkeyID,
                    backwardHotkeyID: backwardHotkeyID
                )
            },
            commandTabTakeoverController: takeoverController,
            stressRunner: stressRunner
        )

        let appDelegate = AppDelegate()
        delegate = appDelegate
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        try? await Task.sleep(nanoseconds: 420_000_000)

        XCTAssertNil(userDefaults.object(forKey: AppPreferenceKeys.showShortcutHint))
        XCTAssertFalse(userDefaults.bool(forKey: CommandTabTakeoverController.takeoverMarkerKey))
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.runtimeLogLevel),
            RuntimeLogLevel.warning.rawValue
        )
        XCTAssertEqual(HomeTabState.shared.selectedTab, .home)
        XCTAssertEqual(stressRunner.startCallCount, 1)
        XCTAssertEqual(hotkeyFactory.records.map(\.signature), [0x46544142, 0x4654574E])
        XCTAssertTrue(panelController.modelForTesting.isSearchActive)
        XCTAssertNotNil(panelController.modelForTesting.session)

        let lines = await RuntimeDiagnostics.shared.readRecentLines(limit: 40, minimumLevel: .debug)
        XCTAssertFalse(lines.contains(where: { $0.contains("before-seed-cleanup") }))
        let seededLines = lines.filter { $0.contains("[UITest] seeded-") }
        XCTAssertEqual(seededLines.count, 3)
    }

    @MainActor
    func testAppDelegateLaunchOpenSwitcherWaitsForStableSnapshotBeforeKeepingPanelOpen() async {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        let previousSharedDelegate = AppDelegate.shared
        let previousActivationOverride = AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest = AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let previousLaunchArguments = FlowTabTestLaunchOptions.argumentsOverrideForTesting
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        let panelController = SwitcherPanelController()
        var delegate: AppDelegate?
        let multiAppSnapshot = Array(searchScenarioApps().prefix(2))
        var snapshotCallCount = 0
        defer {
            delegate?.applicationWillTerminate(
                Notification(name: NSApplication.willTerminateNotification)
            )
            AppDelegate.testHooks = previousHooks
            AppDelegate.shared = previousSharedDelegate
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = previousActivationOverride
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting = previousAXRequest
            FlowTabTestLaunchOptions.argumentsOverrideForTesting = previousLaunchArguments
            clearIsolatedUserDefaults(userDefaults)
        }

        panelController.modelForTesting.snapshotProviderOverride = {
            snapshotCallCount += 1
            let apps: [AppSwitchCandidate]
            switch snapshotCallCount {
            case 1:
                apps = [multiAppSnapshot[0]]
            default:
                apps = multiAppSnapshot
            }
            return RuntimeSnapshot(apps: apps, contextsByID: [:])
        }

        FlowTabTestLaunchOptions.argumentsOverrideForTesting = [
            "FlowTab",
            "--flowtab-ui-open-switcher"
        ]
        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { true }
        AccessibilityPermissionChecker.requestPermissionOverrideForTesting = { true }
        AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = {}
        AppDelegate.testHooks = AppDelegate.TestHooks(
            userDefaults: userDefaults,
            makePanelController: { panelController },
            makeHotkeyMonitor: { configuration, signature, forwardHotkeyID, backwardHotkeyID in
                hotkeyFactory.make(
                    configuration: configuration,
                    signature: signature,
                    forwardHotkeyID: forwardHotkeyID,
                    backwardHotkeyID: backwardHotkeyID
                )
            },
            commandTabTakeoverController: SpyCommandTabTakeoverController(),
            stressRunner: SpyStressRunner()
        )

        let appDelegate = AppDelegate()
        delegate = appDelegate
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        try? await Task.sleep(nanoseconds: 650_000_000)

        XCTAssertGreaterThanOrEqual(snapshotCallCount, 3)
        XCTAssertEqual(panelController.modelForTesting.appCount, multiAppSnapshot.count)
        XCTAssertEqual(
            panelController.modelForTesting.session?.apps.map(\.id),
            multiAppSnapshot.map(\.id)
        )
        XCTAssertFalse(panelController.modelForTesting.isSearchActive)
        XCTAssertEqual(hotkeyFactory.records.count, 2)
    }

    @MainActor
    func testAppDelegateLaunchOpenSwitcherWithoutResultsDoesNotEnterSearchAndSeedZeroSkipsSeededLogs() async {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        let previousSharedDelegate = AppDelegate.shared
        let previousActivationOverride = AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest = AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let previousLaunchArguments = FlowTabTestLaunchOptions.argumentsOverrideForTesting
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        let panelController = SwitcherPanelController()
        var delegate: AppDelegate?
        defer {
            delegate?.applicationWillTerminate(
                Notification(name: NSApplication.willTerminateNotification)
            )
            AppDelegate.testHooks = previousHooks
            AppDelegate.shared = previousSharedDelegate
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = previousActivationOverride
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting = previousAXRequest
            FlowTabTestLaunchOptions.argumentsOverrideForTesting = previousLaunchArguments
            RuntimeDiagnostics.shared.clear()
            clearIsolatedUserDefaults(userDefaults)
        }

        panelController.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(apps: [], contextsByID: [:])
        }

        RuntimeDiagnostics.shared.clear()
        RuntimeDiagnostics.shared.log(
            level: .info,
            category: "UnitTest",
            message: "seed-zero-cleanup"
        )

        FlowTabTestLaunchOptions.argumentsOverrideForTesting = [
            "FlowTab",
            "--flowtab-ui-open-switcher",
            "--flowtab-ui-seed-logs", "0"
        ]
        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { true }
        AccessibilityPermissionChecker.requestPermissionOverrideForTesting = { true }
        AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = {}
        AppDelegate.testHooks = AppDelegate.TestHooks(
            userDefaults: userDefaults,
            makePanelController: { panelController },
            makeHotkeyMonitor: { configuration, signature, forwardHotkeyID, backwardHotkeyID in
                hotkeyFactory.make(
                    configuration: configuration,
                    signature: signature,
                    forwardHotkeyID: forwardHotkeyID,
                    backwardHotkeyID: backwardHotkeyID
                )
            },
            commandTabTakeoverController: SpyCommandTabTakeoverController(),
            stressRunner: SpyStressRunner()
        )

        let appDelegate = AppDelegate()
        delegate = appDelegate
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        try? await Task.sleep(nanoseconds: 420_000_000)

        XCTAssertNil(panelController.modelForTesting.session)
        XCTAssertFalse(panelController.modelForTesting.isSearchActive)
        XCTAssertEqual(hotkeyFactory.records.count, 2)

        let lines = await RuntimeDiagnostics.shared.readRecentLines(limit: 40, minimumLevel: .debug)
        XCTAssertFalse(lines.contains(where: { $0.contains("seed-zero-cleanup") }))
        XCTAssertFalse(lines.contains(where: { $0.contains("[UITest] seeded-") }))
    }

}
