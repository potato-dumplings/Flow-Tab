import AppKit
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testAppDelegateLaunchWithUITestBootstrapArgumentsSeedsLogsAndOpensSearch() async throws {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        let previousSharedDelegate = AppDelegate.shared
        let previousActivationOverride =
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        let previousAXTrusted =
            AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest =
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let previousLaunchArguments =
            FlowTabTestLaunchOptions.argumentsOverrideForTesting
        let previousLaunchEnvironment =
            FlowTabTestLaunchOptions.environmentOverrideForTesting
        let standardDefaults = UserDefaults.standard
        let previousSearchEnabled =
            standardDefaults.object(
                forKey: AppPreferenceKeys.searchEnabled
            )
        let previousSearchDefaultScope =
            standardDefaults.object(
                forKey: AppPreferenceKeys.searchDefaultScope
            )
        let expectedSeededLogCount = 3
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        let takeoverController = SpyCommandTabTakeoverController()
        let stressRunner = SpyStressRunner()
        let panelController = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService:
                    RecordingRuntimeProjectionService(
                        appSwitcherApps: searchScenarioApps()
                    )
            )
        )
        var delegate: AppDelegate?
        var presentationObserver: NSObjectProtocol?
        var hotkeyObserver: NSObjectProtocol?
        var logObservation: RuntimeLogChangeObservation?
        var logWriteRecorder: LaunchBootstrapLogWriteRecorder?
        defer {
            logWriteRecorder?.cancel()
            logObservation?.cancel()
            if let presentationObserver {
                NotificationCenter.default.removeObserver(
                    presentationObserver
                )
            }
            if let hotkeyObserver {
                NotificationCenter.default.removeObserver(
                    hotkeyObserver
                )
            }
            delegate?.applicationWillTerminate(
                Notification(
                    name: NSApplication.willTerminateNotification
                )
            )
            AppDelegate.testHooks = previousHooks
            AppDelegate.shared = previousSharedDelegate
            AppWindowCoordinator
                .activateMainWindowOrOpenHomeSceneOverride =
                    previousActivationOverride
            AccessibilityPermissionChecker
                .isTrustedOverrideForTesting =
                    previousAXTrusted
            AccessibilityPermissionChecker
                .requestPermissionOverrideForTesting =
                    previousAXRequest
            FlowTabTestLaunchOptions
                .argumentsOverrideForTesting =
                    previousLaunchArguments
            FlowTabTestLaunchOptions
                .environmentOverrideForTesting =
                    previousLaunchEnvironment
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

        userDefaults.set(
            false,
            forKey: AppPreferenceKeys.showShortcutHint
        )
        userDefaults.set(
            RuntimeLogLevel.error.rawValue,
            forKey: AppPreferenceKeys.runtimeLogLevel
        )
        userDefaults.set(
            true,
            forKey:
                CommandTabTakeoverController
                    .takeoverMarkerKey
        )
        HomeTabState.shared.selectedTab = .logs

        try await RuntimeDiagnostics.shared.clearAndWait()
        RuntimeDiagnostics.shared.log(
            level: .info,
            category: "UnitTest",
            message: "before-seed-cleanup"
        )
        let prelaunchLines =
            await RuntimeDiagnostics.shared
                .readRecentLines(
                    limit: 200,
                    minimumLevel: .debug
                )
        XCTAssertTrue(
            prelaunchLines.contains {
                $0.contains("[UnitTest]")
            }
        )

        FlowTabTestLaunchOptions.argumentsOverrideForTesting = [
            "FlowTab",
            "--flowtab-ui-reset-defaults",
            "--flowtab-ui-runtime-log-level", "warn",
            "--flowtab-ui-seed-logs",
            String(expectedSeededLogCount),
            "--flowtab-ui-redacted-runtime-logs",
            "--flowtab-ui-open-switcher-search"
        ]
        FlowTabTestLaunchOptions
            .environmentOverrideForTesting = [
                FlowTabTestLaunchOptions
                    .uiTestingEnvironmentKey:
                        FlowTabTestLaunchOptions
                            .uiTestingEnvironmentValue
            ]
        standardDefaults.set(
            true,
            forKey: AppPreferenceKeys.searchEnabled
        )
        standardDefaults.set(
            SwitcherSearchScope.app.rawValue,
            forKey:
                AppPreferenceKeys.searchDefaultScope
        )
        AccessibilityPermissionChecker
            .isTrustedOverrideForTesting = { true }
        AccessibilityPermissionChecker
            .requestPermissionOverrideForTesting = {
                true
            }
        AppWindowCoordinator
            .activateMainWindowOrOpenHomeSceneOverride = {}
        AppDelegate.testHooks = AppDelegate.TestHooks(
            userDefaults: userDefaults,
            makePanelController: { panelController },
            makeHotkeyMonitor: {
                configuration,
                signature,
                forwardHotkeyID,
                backwardHotkeyID in
                hotkeyFactory.make(
                    configuration: configuration,
                    signature: signature,
                    forwardHotkeyID: forwardHotkeyID,
                    backwardHotkeyID: backwardHotkeyID
                )
            },
            commandTabTakeoverController:
                takeoverController,
            stressRunner: stressRunner
        )

        let appDelegate = AppDelegate()
        delegate = appDelegate
        let presentationResolved = expectation(
            description:
                "initial Search presentation publishes exact resolution"
        )
        presentationResolved.assertForOverFulfill = true
        var presentationEvidence:
            FlowTabUITestInitialPresentationEvidence?
        presentationObserver =
            NotificationCenter.default.addObserver(
                forName:
                    .flowTabUITestInitialPresentationDidResolve,
                object: panelController,
                queue: .main
            ) { notification in
                MainActor.assumeIsolated {
                    guard
                        presentationEvidence == nil,
                        let evidence =
                            FlowTabUITestInitialPresentationEvidence(
                                notification: notification
                            ),
                        evidence.resolution == .presented,
                        evidence.attempt?
                            .searchIsActiveOrPending == true
                    else {
                        return
                    }
                    presentationEvidence = evidence
                    presentationResolved.fulfill()
                }
            }

        let launchRegistrationPublished = expectation(
            description:
                "application launch publishes registration generation one"
        )
        launchRegistrationPublished
            .assertForOverFulfill = true
        var launchRegistrationEvidence:
            HotkeyRegistrationEvidence?
        var launchRegistrationRecordSignatures:
            [OSType] = []
        hotkeyObserver =
            NotificationCenter.default.addObserver(
                forName:
                    .flowTabHotkeyRegistrationEvidenceDidChange,
                object: appDelegate,
                queue: .main
            ) { notification in
                MainActor.assumeIsolated {
                    guard
                        launchRegistrationEvidence == nil,
                        let evidence =
                            HotkeyRegistrationEvidence(
                                notification: notification
                        ),
                        evidence.generation == 1,
                        evidence.source
                            == HotkeyRegistrationEvidence
                                .applicationLaunchSource
                    else {
                        return
                    }
                    launchRegistrationEvidence = evidence
                    launchRegistrationRecordSignatures =
                        hotkeyFactory.records
                            .map(\.signature)
                    launchRegistrationPublished
                        .fulfill()
                }
            }

        let seededLogWritesObserved = expectation(
            description:
                "launch log reset is followed by seeded append evidence"
        )
        seededLogWritesObserved.assertForOverFulfill =
            true
        let recorder = LaunchBootstrapLogWriteRecorder(
            expectedAppendCount:
                expectedSeededLogCount
        ) {
            seededLogWritesObserved.fulfill()
        }
        logWriteRecorder = recorder
        logObservation =
            RuntimeDiagnostics.shared
                .observeChanges {
                    [weak recorder] change in
                    recorder?.observe(change)
                }

        appDelegate.applicationDidFinishLaunching(
            Notification(
                name:
                    NSApplication
                        .didFinishLaunchingNotification
            )
        )

        await fulfillment(
            of: [
                presentationResolved,
                launchRegistrationPublished,
                seededLogWritesObserved
            ],
            timeout: 4
        )
        let lines =
            await RuntimeDiagnostics.shared
                .readRecentLines(
                    limit: 200,
                    minimumLevel: .debug
                )

        XCTAssertNil(
            userDefaults.object(
                forKey:
                    AppPreferenceKeys.showShortcutHint
            )
        )
        XCTAssertFalse(
            userDefaults.bool(
                forKey:
                    CommandTabTakeoverController
                        .takeoverMarkerKey
            )
        )
        XCTAssertEqual(
            userDefaults.string(
                forKey:
                    AppPreferenceKeys.runtimeLogLevel
            ),
            RuntimeLogLevel.warning.rawValue
        )
        XCTAssertEqual(
            HomeTabState.shared.selectedTab,
            .home
        )
        XCTAssertEqual(stressRunner.startCallCount, 1)

        let registeredRequest =
            HotkeyRegistrationRequest.load(
                userDefaults: userDefaults
            )
        XCTAssertEqual(
            launchRegistrationEvidence?.generation,
            1
        )
        XCTAssertEqual(
            launchRegistrationEvidence?.source,
            HotkeyRegistrationEvidence
                .applicationLaunchSource
        )
        XCTAssertTrue(
            launchRegistrationEvidence?
                .matchesConfiguration(
                    of: registeredRequest
                ) == true
        )
        XCTAssertEqual(
            launchRegistrationRecordSignatures,
            [0x46544142, 0x4654574E]
        )
        XCTAssertEqual(
            appDelegate
                .latestHotkeyRegistrationEvidence?
                .generation,
            1
        )
        XCTAssertEqual(
            hotkeyFactory.records.map(\.signature),
            [0x46544142, 0x4654574E]
        )

        XCTAssertEqual(
            presentationEvidence?.resolution,
            .presented
        )
        XCTAssertTrue(
            panelController.modelForTesting
                .isSearchActive
        )
        XCTAssertNotNil(
            panelController.modelForTesting.session
        )
        XCTAssertTrue(
            recorder.snapshot.didObserveClear,
            recorder.snapshot.description
        )
        XCTAssertGreaterThanOrEqual(
            recorder.snapshot.appendCount,
            expectedSeededLogCount,
            recorder.snapshot.description
        )

        XCTAssertFalse(
            lines.contains {
                $0.contains("[UnitTest]")
            }
        )
        let seededLines = lines.filter {
            $0.contains("[UITest]")
                && $0.contains(
                    "message.fieldCount=0"
                )
        }
        XCTAssertEqual(
            seededLines.count,
            expectedSeededLogCount
        )
    }
}
