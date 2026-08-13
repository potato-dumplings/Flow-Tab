import AppKit
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testAppDelegateSignalsRuntimeWhenWorkspaceAppsLaunchAndTerminate() async {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        let previousSharedDelegate = AppDelegate.shared
        let previousActivationOverride =
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        let previousAXTrusted =
            AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let runtimeProjectionService = RecordingRuntimeProjectionService()
        let appLaunchWindowEvidenceCoordinator =
            SpyAppLaunchWindowEvidenceCoordinator()
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        let stressRunner = SpyStressRunner()
        let workspaceNotificationCenter = NotificationCenter()
        var observationPrecededLaunchSignal = false
        appLaunchWindowEvidenceCoordinator.onPrepareObservation = { _, _ in
            observationPrecededLaunchSignal =
                runtimeProjectionService.appLaunchSignalsRecorded().isEmpty
        }
        var delegate: AppDelegate?
        defer {
            runtimeProjectionService.setAppLaunchSignalHandler(nil)
            runtimeProjectionService.setAppTerminationSignalHandler(nil)
            delegate?.applicationWillTerminate(
                Notification(name: NSApplication.willTerminateNotification)
            )
            AppDelegate.testHooks = previousHooks
            AppDelegate.shared = previousSharedDelegate
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride =
                previousActivationOverride
            AccessibilityPermissionChecker.isTrustedOverrideForTesting =
                previousAXTrusted
            clearIsolatedUserDefaults(userDefaults)
        }

        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { true }
        AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = {}
        AppDelegate.testHooks = AppDelegate.TestHooks(
            userDefaults: userDefaults,
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
            stressRunner: stressRunner,
            runtimeProjectionService: runtimeProjectionService,
            workspaceNotificationCenter: workspaceNotificationCenter,
            appLaunchWindowEvidenceCoordinator:
                appLaunchWindowEvidenceCoordinator
        )

        delegate = AppDelegate()
        delegate?.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        let workspaceApp = NSRunningApplication.current
        let expectedAppID = RuntimeAppIdentity.appID(for: workspaceApp)
        let expectedPID = workspaceApp.processIdentifier
        let launchSignalRecorded = expectation(
            description: "unmetCondition=workspaceLaunchRecordedForExactAppInstance"
        )
        launchSignalRecorded.assertForOverFulfill = true
        let terminationSignalRecorded = expectation(
            description: "unmetCondition=workspaceTerminationRecordedForExactAppInstance"
        )
        terminationSignalRecorded.assertForOverFulfill = true
        runtimeProjectionService.setAppLaunchSignalHandler {
            appID,
            pid,
            appDirectoryEntry in
            guard appID == expectedAppID, pid == expectedPID else { return }
            guard appDirectoryEntry?.appID == expectedAppID else { return }
            guard appDirectoryEntry?.pid == expectedPID else { return }
            launchSignalRecorded.fulfill()
        }
        runtimeProjectionService.setAppTerminationSignalHandler { appID, pid in
            guard appID == expectedAppID, pid == expectedPID else { return }
            terminationSignalRecorded.fulfill()
        }

        workspaceNotificationCenter.post(
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: workspaceApp]
        )
        await fulfillment(
            of: [launchSignalRecorded],
            timeout:
                FlowTabPriorityCoverageWatchdogPolicy
                    .appDelegateWorkspaceLifecycleSignal
        )

        workspaceNotificationCenter.post(
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: workspaceApp]
        )
        await fulfillment(
            of: [terminationSignalRecorded],
            timeout:
                FlowTabPriorityCoverageWatchdogPolicy
                    .appDelegateWorkspaceLifecycleSignal
        )

        let launchSignals = runtimeProjectionService.appLaunchSignalsRecorded()
        XCTAssertEqual(launchSignals.count, 1)
        XCTAssertEqual(launchSignals.first?.appID, expectedAppID)
        XCTAssertEqual(launchSignals.first?.pid, expectedPID)
        XCTAssertEqual(
            launchSignals.first?.appDirectoryEntry?.appID,
            expectedAppID
        )
        XCTAssertEqual(
            launchSignals.first?.appDirectoryEntry?.pid,
            expectedPID
        )
        let terminationSignals =
            runtimeProjectionService.appTerminationSignalsRecorded()
        XCTAssertEqual(terminationSignals.count, 1)
        XCTAssertEqual(terminationSignals.first?.appID, expectedAppID)
        XCTAssertEqual(terminationSignals.first?.pid, expectedPID)
        let workspaceTerminationSchedules =
            runtimeProjectionService
                .workspaceAppTerminationSchedulesRecorded()
        XCTAssertEqual(workspaceTerminationSchedules.count, 1)
        XCTAssertEqual(
            workspaceTerminationSchedules.first?.appID,
            expectedAppID
        )
        XCTAssertEqual(
            workspaceTerminationSchedules.first?.pid,
            expectedPID
        )
        XCTAssertTrue(observationPrecededLaunchSignal)
        XCTAssertEqual(
            appLaunchWindowEvidenceCoordinator.preparedObservations.map(\.appID),
            [expectedAppID]
        )
        XCTAssertEqual(
            appLaunchWindowEvidenceCoordinator.preparedObservations.map(\.pid),
            [expectedPID]
        )
        XCTAssertEqual(
            appLaunchWindowEvidenceCoordinator.cancelledObservations.map(\.appID),
            [expectedAppID]
        )
        XCTAssertEqual(
            appLaunchWindowEvidenceCoordinator.cancelledObservations.map(\.pid),
            [expectedPID]
        )

        runtimeProjectionService.setAppLaunchSignalHandler(nil)
        runtimeProjectionService.setAppTerminationSignalHandler(nil)
        delegate?.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )
        delegate = nil
        workspaceNotificationCenter.post(
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: workspaceApp]
        )
        workspaceNotificationCenter.post(
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: workspaceApp]
        )
        XCTAssertEqual(
            runtimeProjectionService.appLaunchSignalsRecorded().count,
            1
        )
        XCTAssertEqual(
            runtimeProjectionService.appTerminationSignalsRecorded().count,
            1
        )
        XCTAssertEqual(
            runtimeProjectionService
                .workspaceAppTerminationSchedulesRecorded().count,
            1
        )
    }
}
