import AppKit
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testAppDelegateHotkeyObserverUsesPostedConfigurationsImmediately() async {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }

        let previousHooks = AppDelegate.testHooks
        let previousSharedDelegate = AppDelegate.shared
        let previousActivationOverride =
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        let previousAXTrusted =
            AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest =
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let hotkeyFactory = SpyHotkeyMonitorFactory()
        let takeoverController = SpyCommandTabTakeoverController()
        var delegate: AppDelegate?
        defer {
            delegate?.applicationWillTerminate(
                Notification(name: NSApplication.willTerminateNotification)
            )
            AppDelegate.testHooks = previousHooks
            AppDelegate.shared = previousSharedDelegate
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride =
                previousActivationOverride
            AccessibilityPermissionChecker.isTrustedOverrideForTesting =
                previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting =
                previousAXRequest
            clearIsolatedUserDefaults(userDefaults)
        }

        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { true }
        AccessibilityPermissionChecker.requestPermissionOverrideForTesting = {
            true
        }
        AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = {}
        AppDelegate.testHooks = AppDelegate.TestHooks(
            userDefaults: userDefaults,
            makePanelController: nil,
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
            commandTabTakeoverController: takeoverController,
            stressRunner: SpyStressRunner()
        )

        let appDelegate = AppDelegate()
        delegate = appDelegate
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        let baselineRecordCount = hotkeyFactory.records.count
        XCTAssertEqual(baselineRecordCount, 2)
        let previousMainMonitor =
            hotkeyFactory.records[baselineRecordCount - 2].monitor
        let previousInAppMonitor =
            hotkeyFactory.records[baselineRecordCount - 1].monitor
        let baselineGeneration =
            appDelegate.latestHotkeyRegistrationEvidence?.generation ?? 0

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
        let expectedGeneration = baselineGeneration + 1
        let registrationPublished = expectation(
            forNotification: .flowTabHotkeyRegistrationEvidenceDidChange,
            object: appDelegate,
            notificationCenter: .default
        ) { notification in
            guard
                let evidence =
                    HotkeyRegistrationEvidence(notification: notification)
            else {
                return false
            }
            return evidence.generation == expectedGeneration
                && evidence.requestID == request.requestID
                && evidence.matchesConfiguration(of: request)
                && evidence.commandTabTakeoverActive
                && evidence.source == "notification_payload"
        }
        registrationPublished.assertForOverFulfill = true

        NotificationCenter.default.post(
            name: .flowTabReRegisterHotkeys,
            object: nil,
            userInfo: request.notificationUserInfo
        )
        await fulfillment(
            of: [registrationPublished],
            timeout:
                FlowTabPriorityCoverageWatchdogPolicy
                    .appDelegateHotkeyRegistrationPublication
        )

        let evidence = appDelegate.latestHotkeyRegistrationEvidence
        XCTAssertEqual(evidence?.generation, expectedGeneration)
        XCTAssertEqual(evidence?.requestID, request.requestID)
        XCTAssertEqual(
            evidence?.mainConfiguration,
            request.mainConfiguration
        )
        XCTAssertEqual(
            evidence?.inAppWindowConfiguration,
            request.inAppWindowConfiguration
        )
        XCTAssertEqual(evidence?.commandTabTakeoverActive, true)
        XCTAssertEqual(evidence?.source, "notification_payload")
        let newRecords =
            Array(hotkeyFactory.records.dropFirst(baselineRecordCount))
        XCTAssertEqual(newRecords.count, 2)
        XCTAssertEqual(
            newRecords.map(\.signature),
            [0x46544142, 0x4654574E]
        )
        XCTAssertEqual(
            newRecords.map(\.configuration),
            [request.mainConfiguration, request.inAppWindowConfiguration]
        )
        XCTAssertEqual(newRecords.map(\.forwardHotkeyID), [1, 101])
        XCTAssertEqual(newRecords.map(\.backwardHotkeyID), [2, 102])
        XCTAssertEqual(newRecords.map(\.monitor.startCallCount), [1, 1])
        XCTAssertGreaterThanOrEqual(previousMainMonitor.stopCallCount, 1)
        XCTAssertGreaterThanOrEqual(previousInAppMonitor.stopCallCount, 1)
        XCTAssertEqual(takeoverController.reconcileCalls.last, true)
    }

    @MainActor
    func testAppDelegateHotkeyObserverPressureBindsDeliveryToActiveDelegateAtReceipt() async {
        guard
            let firstUserDefaults = makeIsolatedUserDefaults(),
            let activeUserDefaults = makeIsolatedUserDefaults()
        else {
            return
        }

        let previousHooks = AppDelegate.testHooks
        let previousSharedDelegate = AppDelegate.shared
        let previousActivationOverride =
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride
        let previousAXTrusted =
            AccessibilityPermissionChecker.isTrustedOverrideForTesting
        let previousAXRequest =
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting
        let firstFactory = SpyHotkeyMonitorFactory()
        let activeFactory = SpyHotkeyMonitorFactory()
        var firstDelegate: AppDelegate?
        var activeDelegate: AppDelegate?
        defer {
            activeDelegate?.applicationWillTerminate(
                Notification(name: NSApplication.willTerminateNotification)
            )
            firstDelegate?.applicationWillTerminate(
                Notification(name: NSApplication.willTerminateNotification)
            )
            AppDelegate.testHooks = previousHooks
            AppDelegate.shared = previousSharedDelegate
            AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride =
                previousActivationOverride
            AccessibilityPermissionChecker.isTrustedOverrideForTesting =
                previousAXTrusted
            AccessibilityPermissionChecker.requestPermissionOverrideForTesting =
                previousAXRequest
            clearIsolatedUserDefaults(firstUserDefaults)
            clearIsolatedUserDefaults(activeUserDefaults)
        }

        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { true }
        AccessibilityPermissionChecker.requestPermissionOverrideForTesting = {
            true
        }
        AppWindowCoordinator.activateMainWindowOrOpenHomeSceneOverride = {}
        AppDelegate.testHooks = hotkeyObserverHooks(
            userDefaults: firstUserDefaults,
            factory: firstFactory
        )
        let firstAppDelegate = AppDelegate()
        firstDelegate = firstAppDelegate
        firstAppDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )

        AppDelegate.testHooks = hotkeyObserverHooks(
            userDefaults: activeUserDefaults,
            factory: activeFactory
        )
        let activeAppDelegate = AppDelegate()
        activeDelegate = activeAppDelegate
        activeAppDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        let firstBaselineGeneration =
            firstAppDelegate.latestHotkeyRegistrationEvidence?.generation ?? 0
        let activeBaselineGeneration =
            activeAppDelegate.latestHotkeyRegistrationEvidence?.generation ?? 0
        XCTAssertEqual(firstFactory.records.count, 2)
        XCTAssertEqual(activeFactory.records.count, 2)

        let request = HotkeyRegistrationRequest(
            mainConfiguration: SwitcherHotkeyConfiguration(
                primaryModifier: .control,
                mainKey: .space,
                quitKey: .w
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

        XCTAssertEqual(
            activeAppDelegate.latestHotkeyRegistrationEvidence?.generation,
            activeBaselineGeneration + 1
        )
        XCTAssertEqual(
            activeAppDelegate.latestHotkeyRegistrationEvidence?.requestID,
            request.requestID
        )
        XCTAssertEqual(
            firstAppDelegate.latestHotkeyRegistrationEvidence?.generation,
            firstBaselineGeneration
        )
        XCTAssertEqual(firstFactory.records.count, 2)
        XCTAssertEqual(activeFactory.records.count, 4)
        XCTAssertEqual(
            Array(activeFactory.records.suffix(2)).map(\.configuration),
            [request.mainConfiguration, request.inAppWindowConfiguration]
        )

        var expectedFirstGeneration = firstBaselineGeneration
        var expectedActiveGeneration = activeBaselineGeneration + 1
        let pressureDeliveryCount = 500
        for index in 0..<pressureDeliveryCount {
            let usesFirstDelegate = index.isMultiple(of: 2)
            let owner =
                usesFirstDelegate ? firstAppDelegate : activeAppDelegate
            let ownerUserDefaults =
                usesFirstDelegate ? firstUserDefaults : activeUserDefaults
            let ownerFactory =
                usesFirstDelegate ? firstFactory : activeFactory
            AppDelegate.testHooks = hotkeyObserverHooks(
                userDefaults: ownerUserDefaults,
                factory: ownerFactory
            )
            AppDelegate.shared = owner
            let pressureRequest = HotkeyRegistrationRequest(
                mainConfiguration: request.mainConfiguration,
                inAppWindowConfiguration: request.inAppWindowConfiguration
            )

            NotificationCenter.default.post(
                name: .flowTabReRegisterHotkeys,
                object: nil,
                userInfo: pressureRequest.notificationUserInfo
            )

            if usesFirstDelegate {
                expectedFirstGeneration += 1
                XCTAssertEqual(
                    firstAppDelegate.latestHotkeyRegistrationEvidence?.generation,
                    expectedFirstGeneration
                )
            } else {
                expectedActiveGeneration += 1
                XCTAssertEqual(
                    activeAppDelegate.latestHotkeyRegistrationEvidence?.generation,
                    expectedActiveGeneration
                )
            }
            XCTAssertEqual(
                owner.latestHotkeyRegistrationEvidence?.requestID,
                pressureRequest.requestID
            )
        }

        let firstRecordCount = firstFactory.records.count
        let activeRecordCount = activeFactory.records.count
        XCTAssertEqual(firstRecordCount, 502)
        XCTAssertEqual(activeRecordCount, 504)

        AppDelegate.shared = firstAppDelegate
        await Task.yield()

        XCTAssertEqual(
            firstAppDelegate.latestHotkeyRegistrationEvidence?.generation,
            expectedFirstGeneration
        )
        XCTAssertEqual(
            activeAppDelegate.latestHotkeyRegistrationEvidence?.generation,
            expectedActiveGeneration
        )
        XCTAssertEqual(firstFactory.records.count, firstRecordCount)
        XCTAssertEqual(activeFactory.records.count, activeRecordCount)

        activeAppDelegate.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )
        activeDelegate = nil
        firstAppDelegate.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )
        firstDelegate = nil
        AppDelegate.testHooks = hotkeyObserverHooks(
            userDefaults: firstUserDefaults,
            factory: firstFactory
        )
        AppDelegate.shared = firstAppDelegate
        let postTerminationRequest = HotkeyRegistrationRequest(
            mainConfiguration: request.mainConfiguration,
            inAppWindowConfiguration: request.inAppWindowConfiguration
        )

        NotificationCenter.default.post(
            name: .flowTabReRegisterHotkeys,
            object: nil,
            userInfo: postTerminationRequest.notificationUserInfo
        )
        await Task.yield()

        XCTAssertEqual(
            firstAppDelegate.latestHotkeyRegistrationEvidence?.generation,
            expectedFirstGeneration
        )
        XCTAssertEqual(
            activeAppDelegate.latestHotkeyRegistrationEvidence?.generation,
            expectedActiveGeneration
        )
        XCTAssertEqual(firstFactory.records.count, firstRecordCount)
        XCTAssertEqual(activeFactory.records.count, activeRecordCount)
    }

    @MainActor
    private func hotkeyObserverHooks(
        userDefaults: UserDefaults,
        factory: SpyHotkeyMonitorFactory
    ) -> AppDelegate.TestHooks {
        AppDelegate.TestHooks(
            userDefaults: userDefaults,
            makePanelController: nil,
            makeHotkeyMonitor: {
                configuration,
                signature,
                forwardHotkeyID,
                backwardHotkeyID in
                factory.make(
                    configuration: configuration,
                    signature: signature,
                    forwardHotkeyID: forwardHotkeyID,
                    backwardHotkeyID: backwardHotkeyID
                )
            },
            commandTabTakeoverController: SpyCommandTabTakeoverController(),
            stressRunner: SpyStressRunner()
        )
    }
}
