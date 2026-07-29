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
        let previousLaunchArguments = FlowTabTestLaunchOptions.argumentsOverrideForTesting
        let previousLaunchEnvironment = FlowTabTestLaunchOptions.environmentOverrideForTesting
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
            FlowTabTestLaunchOptions.argumentsOverrideForTesting = previousLaunchArguments
            FlowTabTestLaunchOptions.environmentOverrideForTesting = previousLaunchEnvironment
            clearIsolatedUserDefaults(userDefaults)
        }

        FlowTabTestLaunchOptions.argumentsOverrideForTesting = ["FlowTab"]
        FlowTabTestLaunchOptions.environmentOverrideForTesting = [:]

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

        delegate?.applicationWillTerminate(
            Notification(
                name:
                    NSApplication
                        .willTerminateNotification
            )
        )
        delegate = nil
        XCTAssertEqual(
            stressRunner.stopCallCount,
            1
        )
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
        XCTAssertEqual(hotkeyFactory.records[0].monitor.startCallCount, 1)
        XCTAssertEqual(hotkeyFactory.records[1].monitor.startCallCount, 1)
        XCTAssertEqual(hotkeyFactory.records[0].monitor.stopCallCount, 1)
        XCTAssertEqual(hotkeyFactory.records[1].monitor.stopCallCount, 1)
        XCTAssertEqual(takeoverController.restoreCallCount, 1)
    }

    @MainActor
    func testAppDelegateDirectHotkeyReloadPublishesExactRegistrationEvidence() {
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
        let initialEvidence = appDelegate.latestHotkeyRegistrationEvidence
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
        let evidence = appDelegate.requestHotkeyReload(
            using: request,
            source: "test_direct"
        )

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
        XCTAssertEqual(evidence.generation, (initialEvidence?.generation ?? 0) + 1)
        XCTAssertEqual(evidence.requestID, request.requestID)
        XCTAssertEqual(evidence.mainConfiguration, request.mainConfiguration)
        XCTAssertEqual(
            evidence.inAppWindowConfiguration,
            request.inAppWindowConfiguration
        )
        XCTAssertTrue(evidence.commandTabTakeoverActive)
        XCTAssertEqual(appDelegate.latestHotkeyRegistrationEvidence, evidence)
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
        let currentApp = NSRunningApplication.current
        let currentAppID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let currentAppWindows = [
            WindowCandidate(id: "current-1", title: "Inbox", isMinimized: false, lastActiveAt: 400),
            WindowCandidate(id: "current-2", title: "Draft", isMinimized: false, lastActiveAt: 390)
        ]
        let currentAppCandidate = AppSwitchCandidate(
            id: currentAppID,
            displayName: currentApp.localizedName ?? "Current App",
            groupID: "current",
            lastActiveAt: 400,
            windows: currentAppWindows
        )
        let currentAppContext = makeRuntimeAppContext(
            appID: currentAppID,
            runningApp: currentApp,
            windows: currentAppWindows
        )
        let currentAppWindowPayload = RuntimeCurrentAppWindowPayload(
            summary: RuntimeHomeAppSummary(
                appID: currentAppID,
                displayName: currentAppCandidate.displayName,
                groupID: currentAppCandidate.groupID,
                lastActiveAt: currentAppCandidate.lastActiveAt,
                windowCount: currentAppWindows.count,
                pid: currentApp.processIdentifier
            ),
            candidate: currentAppCandidate,
            context: currentAppContext,
            appDirectoryEntries: [RuntimeAppDirectoryEntry(app: currentApp)]
        )
        let projectionFreshness = RuntimeProjectionFreshness(
            generatedAt: 400,
            sourceGeneration: RuntimeReadModelGeneration(projection: 1),
            dirtyAppIDs: [],
            dirtyPIDs: [],
            dirtyCGWindowIDs: [],
            pendingRepairScopes: [],
            isCompleteForScope: true
        )
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            appSwitcherProjection: RuntimeAppSwitcherProjection(
                apps: [currentAppCandidate] + searchScenarioApps(),
                contextsByID: [currentAppID: currentAppContext],
                freshness: projectionFreshness
            ),
            currentAppWindowProjectionsByAppID: [
                currentAppID: RuntimeCurrentAppWindowProjection(
                    appID: currentAppID,
                    currentAppWindowPayload: currentAppWindowPayload,
                    freshness: projectionFreshness
                )
            ]
        )
        let panelController = SwitcherPanelController(
            model: LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)
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
        XCTAssertEqual(mainRecord.monitor.startCallCount, 1)
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

        mainRecord.monitor.emit(phase: .pressed, isBackward: false)
        panelController.panelVisibilityOverride = true
        XCTAssertEqual(runtimeProjectionService.appSwitcherProjectionReadCount(), 1)
        XCTAssertEqual(runtimeProjectionService.appSwitcherMaintenanceRequestsRecorded(), [.switcherSessionStarted])
        XCTAssertEqual(runtimeProjectionService.currentAppWindowProjectionReadCount(appID: currentAppID), 0)
        XCTAssertNotNil(panelController.modelForTesting.session)
        let initialSelectedAppID = panelController.modelForTesting.selectedApp?.id

        panelController.globalPrimaryModifierPressedOverride = true
        mainRecord.monitor.emit(phase: .pressed, isBackward: false)
        XCTAssertNotEqual(panelController.modelForTesting.selectedApp?.id, initialSelectedAppID)

        panelController.globalPrimaryModifierPressedOverride = false
        panelController.cancelPendingModifierReleaseConfirmation()
        mainRecord.monitor.emit(phase: .released, isBackward: false)
        XCTAssertTrue(panelController.hasPendingModifierReleaseConfirmation)
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
        XCTAssertEqual(inAppRecord.monitor.startCallCount, 1)
        XCTAssertEqual(inAppRecord.configuration.forwardKeyCode, UInt32(SwitcherHotkeyKey.a.keyCode))
        XCTAssertEqual(inAppRecord.configuration.forwardModifiers, SwitcherPrimaryModifier.command.carbonModifier)
        XCTAssertEqual(
            inAppRecord.configuration.backwardModifiers,
            SwitcherPrimaryModifier.command.carbonModifier | UInt32(shiftKey)
        )

        panelController.suppressHotkeyReplayUntilRelease = false
        inAppRecord.monitor.emit(phase: .pressed, isBackward: false)
        panelController.panelVisibilityOverride = true
        XCTAssertEqual(runtimeProjectionService.currentAppWindowProjectionReadCount(appID: currentAppID), 1)
        XCTAssertTrue(runtimeProjectionService.selectedCurrentAppWindowChangeSignalsRecorded().isEmpty)
        XCTAssertEqual(panelController.activeHotkeySessionKind, .inAppWindowSwitcher)
        XCTAssertEqual(panelController.modelForTesting.session?.mode, .windowCycle(appID: currentAppID))
        let initialSelectedWindowID = panelController.modelForTesting.session?.selectedWindow?.id

        panelController.inAppPrimaryModifierPressedOverride = true
        panelController.suppressHotkeyReplayUntilRelease = false
        inAppRecord.monitor.emit(phase: .pressed, isBackward: false)
        XCTAssertNotEqual(panelController.modelForTesting.session?.selectedWindow?.id, initialSelectedWindowID)

        panelController.inAppPrimaryModifierPressedOverride = false
        panelController.cancelPendingModifierReleaseConfirmation()
        inAppRecord.monitor.emit(phase: .released, isBackward: false)
        XCTAssertTrue(panelController.hasPendingModifierReleaseConfirmation)
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
    func testAppDelegateLaunchOpenSwitcherPresentsFromCompleteProjectionEvidence() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        let previousSharedDelegate = AppDelegate.shared
        let previousActivationOverride = AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest = AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let previousLaunchArguments = FlowTabTestLaunchOptions.argumentsOverrideForTesting
        let previousLaunchEnvironment = FlowTabTestLaunchOptions.environmentOverrideForTesting
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        let multiAppSnapshot = Array(searchScenarioApps().prefix(2))
        let initialProjection =
            incompleteInitialPresentationProjection(
                app: multiAppSnapshot[0]
            )
        let runtimeProjectionService =
            RecordingRuntimeProjectionService(
                appSwitcherProjection: initialProjection
            )
        let panelController = SwitcherPanelController(
            model: LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)
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
            clearIsolatedUserDefaults(userDefaults)
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
        XCTAssertTrue(FlowTabUITestBootstrapper.isObservingInitialPresentationForTesting)
        XCTAssertNil(panelController.modelForTesting.session)

        runtimeProjectionService.installAppSwitcherProjection(
            apps: multiAppSnapshot,
            projectionGeneration: 2
        )
        NotificationCenter.default.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: runtimeProjectionService
        )

        XCTAssertFalse(FlowTabUITestBootstrapper.isObservingInitialPresentationForTesting)
        XCTAssertGreaterThanOrEqual(
            runtimeProjectionService
                .appSwitcherProjectionReadCount(),
            5
        )
        XCTAssertFalse(runtimeProjectionService.appSwitcherMaintenanceRequestsRecorded().isEmpty)
        XCTAssertTrue(
            runtimeProjectionService.appSwitcherMaintenanceRequestsRecorded()
                .allSatisfy { $0 == .switcherSessionStarted }
        )
        XCTAssertEqual(runtimeProjectionService.committedSearchIndexReadCount(), 0)
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
        let runtimeProjectionService = RecordingRuntimeProjectionService(appSwitcherApps: [])
        let panelController = SwitcherPanelController(
            model: LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)
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
            RuntimeDiagnostics.shared.clear()
            clearIsolatedUserDefaults(userDefaults)
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
        XCTAssertFalse(FlowTabUITestBootstrapper.isObservingInitialPresentationForTesting)
        XCTAssertNil(panelController.modelForTesting.session)
        XCTAssertFalse(panelController.modelForTesting.isSearchActive)
        XCTAssertEqual(
            runtimeProjectionService
                .appSwitcherProjectionReadCount(),
            1
        )
        XCTAssertTrue(
            runtimeProjectionService
                .appSwitcherMaintenanceRequestsRecorded()
                .isEmpty
        )
        XCTAssertEqual(runtimeProjectionService.committedSearchIndexReadCount(), 0)
        XCTAssertEqual(hotkeyFactory.records.count, 2)

        let lines = await RuntimeDiagnostics.shared.readRecentLines(limit: 40, minimumLevel: .debug)
        XCTAssertFalse(lines.contains(where: { $0.contains("[UnitTest]") }))
        XCTAssertFalse(
            lines.contains {
                $0.contains("[UITest]") && $0.contains("message.fieldCount=0")
            }
        )
    }

}
