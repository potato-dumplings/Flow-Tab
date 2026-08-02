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
            var layoutPublicationCount = 0
            var lastPublishedAppIDs: [String] = []
            var lastPublishedSelectedAppID: String?
            var lastPublishedTerminationAppIDs: [String] = []
            model.onSessionLayoutChanged = {
                XCTAssertTrue(Thread.isMainThread)
                controllerLayoutObserver?()
                layoutPublicationCount += 1
                lastPublishedAppIDs =
                    model.session?.apps.map(\.id) ?? []
                lastPublishedSelectedAppID =
                    model.selectedApp?.id
                lastPublishedTerminationAppIDs =
                    runtimeProjectionService
                        .appTerminationSignalsRecorded()
                        .map(\.appID)
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
            let layoutPublicationBaseline =
                layoutPublicationCount
            XCTAssertEqual(layoutPublicationBaseline, 0)

            controller
                .handleWorkspaceApplicationTerminatedForTesting(
                    appID: terminatedAppID,
                    pid: expectedPID
                )

            XCTAssertEqual(
                layoutPublicationCount,
                layoutPublicationBaseline + 1,
                "unmetCondition=singleSynchronousTerminationLayoutPublication finalAppIDs=\(lastPublishedAppIDs) finalSelectedAppID=\(lastPublishedSelectedAppID ?? "nil") finalTerminationAppIDs=\(lastPublishedTerminationAppIDs)"
            )
            XCTAssertEqual(
                lastPublishedAppIDs,
                remainingAppIDs
            )
            XCTAssertEqual(
                lastPublishedSelectedAppID,
                expectedSelectedAppID
            )
            XCTAssertEqual(
                lastPublishedTerminationAppIDs,
                [terminatedAppID]
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
            XCTAssertNil(model.pendingTerminateRequest)
            XCTAssertNil(model.terminatingAppID)
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
