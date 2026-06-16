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
    func testAppDelegateLaunchInstallsObserversPromptsAccessibilityAndStartsStressRunner() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        let previousActivationOverride = AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest = AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        let takeoverController = SpyCommandTabTakeoverController()
        let stressRunner = SpyStressRunner()
        var delegate: AppDelegate?
        defer {
            delegate?.applicationWillTerminate(
                Notification(name: NSApplication.willTerminateNotification)
            )
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

        var openHomeCallCount = 0
        HomeTabState.shared.selectedTab = .settings
        AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = {
            openHomeCallCount += 1
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

        delegate = AppDelegate()
        delegate?.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )

        XCTAssertEqual(openHomeCallCount, 1)
        XCTAssertEqual(HomeTabState.shared.selectedTab, .home)
        XCTAssertTrue(delegate?.hasPanelControllerForTesting == true)
        XCTAssertTrue(delegate?.hasMainHotkeyMonitorForTesting == true)
        XCTAssertTrue(delegate?.hasInAppHotkeyMonitorForTesting == true)
        XCTAssertTrue(delegate?.hasHotkeyObserverForTesting == true)
        XCTAssertTrue(delegate?.hasAppVisibilityObserverForTesting == true)
        XCTAssertTrue(delegate?.hasLanguageObserverForTesting == true)
        XCTAssertTrue(delegate?.hasWorkspaceLifecycleObserverForTesting == true)
        XCTAssertTrue(delegate?.hasStatusItemForTesting == true)
        XCTAssertEqual(accessibilityPromptCount, 1)
        XCTAssertTrue(userDefaults.bool(forKey: AppPreferenceKeys.hasPromptedAccessibilityPermission))
        XCTAssertEqual(stressRunner.startCallCount, 1)
        XCTAssertEqual(takeoverController.reconcileCalls, [false])
        XCTAssertEqual(hotkeyFactory.records.map(\.signature), [0x46544142, 0x4654574E])
        XCTAssertEqual(hotkeyFactory.records.map(\.forwardHotkeyID), [1, 101])
        XCTAssertEqual(hotkeyFactory.records.map(\.backwardHotkeyID), [2, 102])
    }

    @MainActor
    func testAppDelegateSignalsRuntimeWhenWorkspaceAppsLaunchAndTerminate() async {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        let previousSharedDelegate = AppDelegate.shared
        let previousActivationOverride = AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let snapshotService = RecordingRuntimeSnapshotService()
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        let stressRunner = SpyStressRunner()
        let workspaceNotificationCenter = NotificationCenter()
        var delegate: AppDelegate?
        defer {
            delegate?.applicationWillTerminate(
                Notification(name: NSApplication.willTerminateNotification)
            )
            AppDelegate.testHooks = previousHooks
            AppDelegate.shared = previousSharedDelegate
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = previousActivationOverride
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousAXTrusted
            clearIsolatedUserDefaults(userDefaults)
        }

        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { true }
        AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = {}
        AppDelegate.testHooks = AppDelegate.TestHooks(
            userDefaults: userDefaults,
            makeHotkeyMonitor: { configuration, signature, forwardHotkeyID, backwardHotkeyID in
                hotkeyFactory.make(
                    configuration: configuration,
                    signature: signature,
                    forwardHotkeyID: forwardHotkeyID,
                    backwardHotkeyID: backwardHotkeyID
                )
            },
            stressRunner: stressRunner,
            runtimeSnapshotService: snapshotService,
            workspaceNotificationCenter: workspaceNotificationCenter
        )

        delegate = AppDelegate()
        delegate?.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        let workspaceApp = NSRunningApplication.current

        workspaceNotificationCenter.post(
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: workspaceApp]
        )

        let didSignalLaunch = await waitUntil(
            "workspace launch reaches runtime snapshot service",
            timeoutNanoseconds: 1_000_000_000,
            pollIntervalNanoseconds: 10_000_000
        ) {
            let signals = snapshotService.appLaunchSignalsRecorded()
            return signals.count == 1
                && signals.first?.appID == RuntimeSnapshotProvider.baseAppID(for: workspaceApp)
                && signals.first?.pid == workspaceApp.processIdentifier
        }

        workspaceNotificationCenter.post(
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: workspaceApp]
        )

        let didSignalTermination = await waitUntil(
            "workspace termination reaches runtime snapshot service",
            timeoutNanoseconds: 1_000_000_000,
            pollIntervalNanoseconds: 10_000_000
        ) {
            let signals = snapshotService.appTerminationSignalsRecorded()
            return signals.count == 1
                && signals.first?.appID == RuntimeSnapshotProvider.baseAppID(for: workspaceApp)
                && signals.first?.pid == workspaceApp.processIdentifier
        }

        XCTAssertTrue(didSignalLaunch)
        XCTAssertTrue(didSignalTermination)
    }

    @MainActor
    func testAppDelegateLaunchNormalizesStoredInAppHotkeyConflictBeforeRegistration() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        let previousSharedDelegate = AppDelegate.shared
        let previousActivationOverride = AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest = AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let hotkeyFactory = SpyHotkeyMonitorFactory()
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

        userDefaults.set(
            SwitcherPrimaryModifier.control.rawValue,
            forKey: AppPreferenceKeys.hotkeyPrimaryModifier
        )
        userDefaults.set(SwitcherHotkeyKey.tab.rawValue, forKey: AppPreferenceKeys.hotkeyMainKey)
        userDefaults.set(SwitcherHotkeyKey.q.rawValue, forKey: AppPreferenceKeys.hotkeyQuitKey)
        userDefaults.set(
            SwitcherPrimaryModifier.control.rawValue,
            forKey: AppPreferenceKeys.inAppWindowHotkeyPrimaryModifier
        )
        userDefaults.set(SwitcherHotkeyKey.tab.rawValue, forKey: AppPreferenceKeys.inAppWindowHotkeyMainKey)

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

        let appDelegate = AppDelegate()
        delegate = appDelegate
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )

        XCTAssertEqual(hotkeyFactory.records.count, 2)
        guard hotkeyFactory.records.count == 2 else { return }
        XCTAssertEqual(hotkeyFactory.records.map(\.signature), [0x46544142, 0x4654574E])
        XCTAssertEqual(hotkeyFactory.records[0].configuration.primaryModifier, .control)
        XCTAssertEqual(hotkeyFactory.records[0].configuration.mainKey, .tab)
        XCTAssertEqual(hotkeyFactory.records[1].configuration.primaryModifier, .option)
        XCTAssertEqual(hotkeyFactory.records[1].configuration.mainKey, .tab)
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.inAppWindowHotkeyPrimaryModifier),
            SwitcherPrimaryModifier.option.rawValue
        )
    }

    @MainActor
    func testAppDelegateLaunchCanSuppressHomeWindowForUITestTriggerListener() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        let previousActivationOverride = AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest = AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let previousLaunchArguments = FlowTabTestLaunchOptions.argumentsOverrideForTesting
        let previousLaunchEnvironment = FlowTabTestLaunchOptions.environmentOverrideForTesting
        let previousSelectedTab = HomeTabState.shared.selectedTab
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        let takeoverController = SpyCommandTabTakeoverController()
        let stressRunner = SpyStressRunner()
        defer {
            AppDelegate.testHooks = previousHooks
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = previousActivationOverride
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting = previousAXRequest
            FlowTabTestLaunchOptions.argumentsOverrideForTesting = previousLaunchArguments
            FlowTabTestLaunchOptions.environmentOverrideForTesting = previousLaunchEnvironment
            HomeTabState.shared.selectedTab = previousSelectedTab
            clearIsolatedUserDefaults(userDefaults)
        }

        var openHomeCallCount = 0
        HomeTabState.shared.selectedTab = .settings
        FlowTabTestLaunchOptions.argumentsOverrideForTesting = [
            "FlowTab",
            "--flowtab-ui-listen-switcher-trigger",
            "--flowtab-ui-suppress-home-on-launch"
        ]
        FlowTabTestLaunchOptions.environmentOverrideForTesting = [
            FlowTabTestLaunchOptions.uiTestingEnvironmentKey:
                FlowTabTestLaunchOptions.uiTestingEnvironmentValue
        ]
        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { true }
        AccessibilityPermissionChecker.requestPermissionOverrideForTesting = {
            XCTFail("Launch with trusted accessibility should not prompt")
            return true
        }
        AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = {
            openHomeCallCount += 1
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

        XCTAssertEqual(openHomeCallCount, 0)
        XCTAssertEqual(HomeTabState.shared.selectedTab, .settings)
        XCTAssertTrue(delegate.hasPanelControllerForTesting)
        XCTAssertTrue(delegate.hasMainHotkeyMonitorForTesting)
        XCTAssertTrue(delegate.hasInAppHotkeyMonitorForTesting)
        XCTAssertTrue(delegate.hasHotkeyObserverForTesting)
        XCTAssertTrue(delegate.hasAppVisibilityObserverForTesting)
        XCTAssertTrue(delegate.hasLanguageObserverForTesting)
        XCTAssertTrue(delegate.hasStatusItemForTesting)
        XCTAssertEqual(stressRunner.startCallCount, 1)
        XCTAssertEqual(takeoverController.reconcileCalls, [false])
        XCTAssertEqual(hotkeyFactory.records.map(\.signature), [0x46544142, 0x4654574E])
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

        let didRegisterNewHotkeys = await waitUntil(
            "notification hotkey reload registers replacement monitors",
            timeoutNanoseconds: 1_000_000_000,
            pollIntervalNanoseconds: 10_000_000
        ) {
            hotkeyFactory.records.count >= baselineRecordCount + 2
        }
        XCTAssertTrue(didRegisterNewHotkeys)

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

        let didRegisterNewHotkeys = await waitUntil(
            "direct hotkey reload registers replacement monitors",
            timeoutNanoseconds: 1_000_000_000,
            pollIntervalNanoseconds: 10_000_000
        ) {
            hotkeyFactory.records.count >= baselineRecordCount + 2
        }
        XCTAssertTrue(didRegisterNewHotkeys)

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
            AppPreferenceKeys.hotkeyQuitKey,
            AppPreferenceKeys.inAppWindowHotkeyPrimaryModifier,
            AppPreferenceKeys.inAppWindowHotkeyMainKey
        ]
        let previousPreferenceValues = Dictionary(
            uniqueKeysWithValues: preferenceKeys.map { key in
                (key, standardDefaults.object(forKey: key))
            }
        )
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        let panelController = SwitcherPanelController(
            model: LiveSwitcherModel(
                snapshotService: RecordingRuntimeSnapshotService(
                    appSwitcherApps: self.searchScenarioApps()
                )
            )
        )
        let currentApp = NSRunningApplication.current
        let currentAppID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let currentAppWindows = [
            WindowCandidate(id: "current-1", title: "Inbox", isMinimized: false, lastActiveAt: 400),
            WindowCandidate(id: "current-2", title: "Draft", isMinimized: false, lastActiveAt: 390)
        ]
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

        panelController.modelForTesting.testingSnapshotProviderOverride = {
            RuntimeSnapshot(
                apps: [
                    AppSwitchCandidate(
                        id: currentAppID,
                        displayName: currentApp.localizedName ?? "Current App",
                        groupID: "current",
                        lastActiveAt: 400,
                        windows: currentAppWindows
                    )
                ] + self.searchScenarioApps(),
                contextsByID: [
                    currentAppID: self.makeRuntimeAppContext(
                        appID: currentAppID,
                        runningApp: currentApp,
                        windows: currentAppWindows
                    )
                ]
            )
        }
        panelController.modelForTesting.frontmostApplicationOverride = { currentApp }
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
        standardDefaults.set(
            request.inAppWindowConfiguration.primaryModifier.rawValue,
            forKey: AppPreferenceKeys.inAppWindowHotkeyPrimaryModifier
        )
        standardDefaults.set(
            request.inAppWindowConfiguration.mainKey.rawValue,
            forKey: AppPreferenceKeys.inAppWindowHotkeyMainKey
        )

        appDelegate.requestHotkeyReload(using: request, source: "test_settings_reload")

        let newRecords = Array(hotkeyFactory.records.dropFirst(baselineRecordCount))
        XCTAssertGreaterThanOrEqual(newRecords.count, 2)
        guard let mainRecord = newRecords.last(where: { $0.signature == 0x46544142 }) else {
            XCTFail("Expected reloaded main hotkey monitor")
            return
        }
        XCTAssertEqual(mainRecord.configuration.primaryModifier, .option)
        XCTAssertEqual(mainRecord.configuration.mainKey, .space)
        XCTAssertEqual(mainRecord.configuration.quitKey, .z)
        XCTAssertEqual(mainRecord.configuration.forwardKeyCode, UInt32(SwitcherHotkeyKey.space.keyCode))
        XCTAssertEqual(mainRecord.configuration.forwardModifiers, SwitcherPrimaryModifier.option.carbonModifier)
        XCTAssertEqual(
            mainRecord.configuration.backwardModifiers,
            SwitcherPrimaryModifier.option.carbonModifier | UInt32(shiftKey)
        )
        XCTAssertTrue(
            panelController.isTerminateSelectedAppShortcut(
                Self.makeKeyDownEvent(
                    keyCode: SwitcherHotkeyKey.z.keyCode,
                    modifierFlags: .option
                )
            )
        )
        XCTAssertFalse(
            panelController.isTerminateSelectedAppShortcut(
                Self.makeKeyDownEvent(
                    keyCode: SwitcherHotkeyKey.z.keyCode,
                    modifierFlags: [.option, .shift]
                )
            )
        )

        mainRecord.monitor.onHotkeyPressed?(false)
        panelController.panelVisibilityOverride = true
        XCTAssertNotNil(panelController.modelForTesting.session)
        let initialSelectedAppID = panelController.modelForTesting.selectedApp?.id

        panelController.globalPrimaryModifierPressedOverride = true
        mainRecord.monitor.onHotkeyPressed?(false)
        XCTAssertNotEqual(panelController.modelForTesting.selectedApp?.id, initialSelectedAppID)

        panelController.globalPrimaryModifierPressedOverride = false
        panelController.cancelPendingModifierReleaseConfirmation()
        mainRecord.monitor.onHotkeyReleased?(false)
        XCTAssertNotNil(panelController.pendingModifierReleaseConfirmationTask)
        panelController.cancelPendingModifierReleaseConfirmation()
        panelController.cancelSelectionForTesting()
        XCTAssertNil(panelController.modelForTesting.session)

        guard let inAppRecord = newRecords.last(where: { $0.signature == 0x4654574E }) else {
            XCTFail("Expected reloaded in-app window hotkey monitor")
            return
        }
        XCTAssertEqual(inAppRecord.configuration.primaryModifier, .command)
        XCTAssertEqual(inAppRecord.configuration.mainKey, .a)
        XCTAssertEqual(inAppRecord.configuration.quitKey, .q)
        XCTAssertEqual(inAppRecord.configuration.forwardKeyCode, UInt32(SwitcherHotkeyKey.a.keyCode))
        XCTAssertEqual(inAppRecord.configuration.forwardModifiers, SwitcherPrimaryModifier.command.carbonModifier)
        XCTAssertEqual(
            inAppRecord.configuration.backwardModifiers,
            SwitcherPrimaryModifier.command.carbonModifier | UInt32(shiftKey)
        )

        panelController.suppressHotkeyReplayUntilRelease = false
        panelController.ignoreHotkeyPressesUntil = 0
        inAppRecord.monitor.onHotkeyPressed?(false)
        panelController.panelVisibilityOverride = true
        XCTAssertEqual(panelController.activeHotkeySessionKind, .inAppWindowSwitcher)
        XCTAssertEqual(panelController.modelForTesting.session?.mode, .windowCycle(appID: currentAppID))
        let initialSelectedWindowID = panelController.modelForTesting.session?.selectedWindow?.id

        panelController.inAppPrimaryModifierPressedOverride = true
        inAppRecord.monitor.onHotkeyPressed?(false)
        XCTAssertNotEqual(panelController.modelForTesting.session?.selectedWindow?.id, initialSelectedWindowID)

        panelController.inAppPrimaryModifierPressedOverride = false
        panelController.cancelPendingModifierReleaseConfirmation()
        inAppRecord.monitor.onHotkeyReleased?(false)
        XCTAssertNotNil(panelController.pendingModifierReleaseConfirmationTask)
        panelController.cancelPendingModifierReleaseConfirmation()
        panelController.cancelSelectionForTesting()
        XCTAssertNil(panelController.modelForTesting.session)
    }

    @MainActor
    func testAppDelegateNormalizesInAppHotkeyConflictToControlTabBeforeRegistration() {
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
        XCTAssertTrue(delegate.hasInAppHotkeyMonitorForTesting)
        XCTAssertEqual(hotkeyFactory.records.count, 2)
        XCTAssertEqual(hotkeyFactory.records.first?.signature, 0x46544142)
        XCTAssertEqual(hotkeyFactory.records.first?.configuration.primaryModifier, .option)
        XCTAssertEqual(hotkeyFactory.records.first?.configuration.mainKey, .tab)
        XCTAssertEqual(hotkeyFactory.records.last?.signature, 0x4654574E)
        XCTAssertEqual(hotkeyFactory.records.last?.configuration.primaryModifier, .control)
        XCTAssertEqual(hotkeyFactory.records.last?.configuration.mainKey, .tab)
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.inAppWindowHotkeyPrimaryModifier),
            SwitcherPrimaryModifier.control.rawValue
        )
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
        let previousLaunchEnvironment = FlowTabTestLaunchOptions.environmentOverrideForTesting
        let standardDefaults = UserDefaults.standard
        let previousSearchEnabled = standardDefaults.object(forKey: AppPreferenceKeys.searchEnabled)
        let previousSearchDefaultScope = standardDefaults.object(forKey: AppPreferenceKeys.searchDefaultScope)
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        let takeoverController = SpyCommandTabTakeoverController()
        let stressRunner = SpyStressRunner()
        let panelController = SwitcherPanelController(
            model: LiveSwitcherModel(
                snapshotService: RecordingRuntimeSnapshotService(
                    appSwitcherApps: searchScenarioApps()
                )
            )
        )
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
            FlowTabTestLaunchOptions.environmentOverrideForTesting = previousLaunchEnvironment
            restoreUserDefaultsValue(
                previousSearchEnabled,
                forKey: AppPreferenceKeys.searchEnabled,
                userDefaults: standardDefaults
            )
            restoreUserDefaultsValue(
                previousSearchDefaultScope,
                forKey: AppPreferenceKeys.searchDefaultScope,
                userDefaults: standardDefaults
            )
            RuntimeDiagnostics.shared.clear()
            clearIsolatedUserDefaults(userDefaults)
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
        FlowTabTestLaunchOptions.environmentOverrideForTesting = [
            FlowTabTestLaunchOptions.uiTestingEnvironmentKey:
                FlowTabTestLaunchOptions.uiTestingEnvironmentValue
        ]
        standardDefaults.set(true, forKey: AppPreferenceKeys.searchEnabled)
        standardDefaults.set(
            SwitcherSearchScope.app.rawValue,
            forKey: AppPreferenceKeys.searchDefaultScope
        )
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
        let lines = await waitForLaunchBootstrapSearchAndSeededLogs(
            panelController: panelController,
            seededLogCount: 3
        )

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
        let previousLaunchEnvironment = FlowTabTestLaunchOptions.environmentOverrideForTesting
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
            FlowTabTestLaunchOptions.environmentOverrideForTesting = previousLaunchEnvironment
            clearIsolatedUserDefaults(userDefaults)
        }

        panelController.modelForTesting.testingSnapshotProviderOverride = {
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
        FlowTabTestLaunchOptions.environmentOverrideForTesting = [
            FlowTabTestLaunchOptions.uiTestingEnvironmentKey:
                FlowTabTestLaunchOptions.uiTestingEnvironmentValue
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
        let didOpenSeededSwitcher = await waitUntil(
            "launch open switcher loads seeded multi-app snapshot",
            timeoutNanoseconds: 2_000_000_000,
            pollIntervalNanoseconds: 25_000_000
        ) {
            snapshotCallCount >= 3
                && panelController.modelForTesting.appCount == multiAppSnapshot.count
                && panelController.modelForTesting.session?.apps.map(\.id) == multiAppSnapshot.map(\.id)
        }
        XCTAssertTrue(didOpenSeededSwitcher)

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
        let previousLaunchEnvironment = FlowTabTestLaunchOptions.environmentOverrideForTesting
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
            FlowTabTestLaunchOptions.environmentOverrideForTesting = previousLaunchEnvironment
            RuntimeDiagnostics.shared.clear()
            clearIsolatedUserDefaults(userDefaults)
        }

        panelController.modelForTesting.testingSnapshotProviderOverride = {
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
        FlowTabTestLaunchOptions.environmentOverrideForTesting = [
            FlowTabTestLaunchOptions.uiTestingEnvironmentKey:
                FlowTabTestLaunchOptions.uiTestingEnvironmentValue
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
        let didFinishLaunchBootstrap = await waitUntil(
            "launch open switcher without results finishes bootstrap",
            timeoutNanoseconds: 2_000_000_000,
            pollIntervalNanoseconds: 25_000_000
        ) {
            hotkeyFactory.records.count == 2
        }
        XCTAssertTrue(didFinishLaunchBootstrap)

        XCTAssertNil(panelController.modelForTesting.session)
        XCTAssertFalse(panelController.modelForTesting.isSearchActive)
        XCTAssertEqual(hotkeyFactory.records.count, 2)

        let lines = await RuntimeDiagnostics.shared.readRecentLines(limit: 40, minimumLevel: .debug)
        XCTAssertFalse(lines.contains(where: { $0.contains("seed-zero-cleanup") }))
        XCTAssertFalse(lines.contains(where: { $0.contains("[UITest] seeded-") }))
    }

}
