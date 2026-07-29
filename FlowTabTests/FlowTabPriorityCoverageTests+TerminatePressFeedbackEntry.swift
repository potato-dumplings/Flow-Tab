import Darwin
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testSwitcherPanelControllerQuitShortcutTriggersTerminateSelectedAppFlow()
    {
        let scheduler =
            ManualTerminatePressFeedbackScheduler()
        let runtimeProjectionService =
            RecordingRuntimeProjectionService(
                appSwitcherApps: terminateScenarioApps()
            )
        let model = LiveSwitcherModel(
            runtimeProjectionService:
                runtimeProjectionService
        )
        let expectedPID = pid_t(42_100)
        model.terminateRequestOverride = { _ in
            (sent: true, pid: expectedPID)
        }
        let controller = SwitcherPanelController(
            model: model,
            terminatePressFeedbackScheduler:
                scheduler
        )
        defer {
            controller.cancelSelectionForTesting()
        }

        XCTAssertTrue(
            model.startSession(triggerDirection: .forward)
        )
        assertAppSwitcherProjectionSessionRead(
            from: runtimeProjectionService
        )
        guard let selectedAppID = model.selectedApp?.id else {
            return XCTFail("Expected selected app")
        }
        let hotkeyConfiguration =
            SwitcherHotkeyPreferencesStore.load()

        XCTAssertTrue(
            controller.handleKeyDownForTesting(
                Self.makeKeyDownEvent(
                    keyCode:
                        hotkeyConfiguration.quitKeyCode,
                    modifierFlags:
                        hotkeyConfiguration
                        .primaryModifier
                        .eventModifierFlag
                )
            )
        )
        XCTAssertTrue(
            controller
                .terminatePressFeedbackCompletionOwner
                .isPending
        )
        XCTAssertEqual(
            controller
                .terminatePressFeedbackCompletionOwner
                .generation,
            1
        )
        XCTAssertEqual(
            scheduler.scheduledIntervals,
            [
                TerminatePressFeedbackPolicy
                    .default
                    .completionInterval
            ]
        )
        XCTAssertNil(model.pendingTerminateRequest)

        XCTAssertTrue(scheduler.fire(at: 0))

        XCTAssertFalse(
            controller
                .terminatePressFeedbackCompletionOwner
                .isPending
        )
        XCTAssertEqual(
            model.terminatingAppID,
            selectedAppID
        )
        XCTAssertEqual(
            model.pendingTerminateRequest?.appID,
            selectedAppID
        )
        XCTAssertEqual(
            model.pendingTerminateRequest?.pid,
            expectedPID
        )
        XCTAssertEqual(
            model.pendingTerminateRequest?.generation,
            1
        )
        XCTAssertTrue(
            runtimeProjectionService
                .appTerminationSignalsRecorded()
                .isEmpty
        )
        assertAppSwitcherProjectionSessionRead(
            from: runtimeProjectionService,
            maintenanceRequests: [
                .switcherSessionStarted,
                .appLifecycleRefresh
            ]
        )
        XCTAssertNotNil(model.session)
    }

    @MainActor
    func testSwitcherPanelControllerQuitFrontmostAppInAppLayerKeepsSessionAfterWorkspaceTerminationRefresh()
        async
    {
        await withTemporarySearchPreferences(
            enabled: true,
            defaultScope: .app
        ) {
            let scheduler =
                ManualTerminatePressFeedbackScheduler()
            let initialApps =
                self.terminateScenarioApps()
            let runtimeProjectionService =
                RecordingRuntimeProjectionService(
                    appSwitcherApps: initialApps
                )
            let model = LiveSwitcherModel(
                runtimeProjectionService:
                    runtimeProjectionService
            )
            let expectedPID = pid_t(42_100)
            model.terminateRequestOverride = { _ in
                (sent: true, pid: expectedPID)
            }
            let controller = SwitcherPanelController(
                model: model,
                terminatePressFeedbackScheduler:
                    scheduler
            )
            let controllerLayoutObserver =
                model.onSessionLayoutChanged
            let layoutRefreshed = expectation(
                description:
                    "workspace termination publishes matching layout"
            )
            layoutRefreshed.assertForOverFulfill =
                true
            model.onSessionLayoutChanged = {
                controllerLayoutObserver?()
                layoutRefreshed.fulfill()
            }
            defer {
                model.onSessionLayoutChanged =
                    controllerLayoutObserver
                controller.cancelSelectionForTesting()
            }

            XCTAssertTrue(
                controller
                    .beginGlobalHotkeySessionForTesting()
            )
            guard
                let sessionBeforeTermination =
                    model.session
            else {
                return XCTFail(
                    "Expected an active session before workspace termination"
                )
            }
            let terminatedAppID =
                sessionBeforeTermination.selectedApp.id
            let remainingAppIDs =
                sessionBeforeTermination.apps
                .map(\.id)
                .filter { $0 != terminatedAppID }
            let expectedSelectedAppID =
                remainingAppIDs[
                    min(
                        sessionBeforeTermination
                            .selectedAppIndex,
                        remainingAppIDs.count - 1
                    )
                ]
            XCTAssertFalse(model.isSearchActive)
            assertAppSwitcherProjectionSessionRead(
                from: runtimeProjectionService
            )

            let hotkeyConfiguration =
                SwitcherHotkeyPreferencesStore.load()
            XCTAssertTrue(
                controller.handleKeyDownForTesting(
                    Self.makeKeyDownEvent(
                        keyCode:
                            hotkeyConfiguration
                            .quitKeyCode,
                        modifierFlags:
                            hotkeyConfiguration
                            .primaryModifier
                            .eventModifierFlag
                    )
                )
            )
            XCTAssertTrue(
                controller
                    .terminatePressFeedbackCompletionOwner
                    .isPending
            )
            XCTAssertNil(model.pendingTerminateRequest)

            XCTAssertTrue(scheduler.fire(at: 0))

            XCTAssertFalse(
                controller
                    .terminatePressFeedbackCompletionOwner
                    .isPending
            )
            XCTAssertEqual(
                model.pendingTerminateRequest?.appID,
                terminatedAppID
            )
            XCTAssertEqual(
                model.pendingTerminateRequest?.pid,
                expectedPID
            )
            XCTAssertEqual(
                model.pendingTerminateRequest?
                    .generation,
                1
            )
            assertAppSwitcherProjectionSessionRead(
                from: runtimeProjectionService,
                maintenanceRequests: [
                    .switcherSessionStarted,
                    .appLifecycleRefresh
                ]
            )
            XCTAssertEqual(model.appCount, initialApps.count)
            XCTAssertTrue(
                model.session?.apps.contains {
                    $0.id == terminatedAppID
                } ?? false
            )
            XCTAssertTrue(
                runtimeProjectionService
                    .appTerminationSignalsRecorded()
                    .isEmpty
            )

            controller
                .handleWorkspaceApplicationTerminatedForTesting(
                    appID: terminatedAppID,
                    pid: expectedPID
                )

            await fulfillment(
                of: [layoutRefreshed],
                timeout: 1
            )

            XCTAssertNotNil(model.session)
            XCTAssertEqual(model.appCount, 2)
            XCTAssertEqual(
                model.selectedApp?.id,
                expectedSelectedAppID
            )
            XCTAssertFalse(
                model.session?.apps.contains {
                    $0.id == terminatedAppID
                } ?? true
            )
            XCTAssertEqual(
                runtimeProjectionService
                    .appTerminationSignalsRecorded()
                    .map(\.appID),
                [terminatedAppID]
            )
            assertAppSwitcherProjectionSessionRead(
                from: runtimeProjectionService,
                minimumReadCount: 2,
                maintenanceRequests: [
                    .switcherSessionStarted,
                    .appLifecycleRefresh
                ]
            )
            XCTAssertFalse(model.isSearchActive)
        }
    }
}
