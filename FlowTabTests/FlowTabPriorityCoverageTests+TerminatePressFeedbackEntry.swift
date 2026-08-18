import Darwin
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testSwitcherPanelControllerQuitShortcutTriggersTerminateSelectedAppFlow()
    {
        let restoreHotkeyConfiguration =
            installTemporarySwitcherHotkeyConfiguration(
                SwitcherHotkeyConfiguration(
                    baseKeys: [.option],
                    reverseKeys: [.shift],
                    mainKeys: [.tab],
                    quitKeys: [.q]
                )
            )
        defer { restoreHotkeyConfiguration() }
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
                        hotkeyConfiguration.quitKeys.orderedKeys[0].keyCode,
                    modifierFlags:
                        hotkeyConfiguration.baseKeys.modifiers.eventModifierFlags
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
    func testSwitcherPanelControllerTerminateRequestProtectsPanelResignAfterModifierRelease() {
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
        let controller = SwitcherPanelController(
            model: model,
            terminatePressFeedbackScheduler:
                scheduler
        )
        var requestedAppIDs: [String] = []
        var protectionPreparedReadbacks: [Bool] = []
        model.terminateRequestOverride = {
            [weak controller] appID in
            XCTAssertTrue(Thread.isMainThread)
            requestedAppIDs.append(appID)
            protectionPreparedReadbacks.append(
                controller?
                    .terminateInterruptionProtectionObservationOwner
                    .isPrepared ?? false
            )
            return (sent: true, pid: 42_301)
        }
        defer {
            model.terminateRequestOverride = nil
            controller.cancelSelectionForTesting()
        }
        controller.globalHotkeyHoldSetPressedOverride = false
        controller.globalMainKeySetPressedOverride = false
        controller.appIsActiveOverride = false

        XCTAssertFalse(
            controller
                .terminatePressFeedbackCompletionOwner
                .isPending
        )
        XCTAssertEqual(
            controller
                .terminatePressFeedbackCompletionOwner
                .generation,
            0
        )
        XCTAssertTrue(scheduler.scheduledIntervals.isEmpty)
        XCTAssertTrue(requestedAppIDs.isEmpty)
        XCTAssertTrue(protectionPreparedReadbacks.isEmpty)
        XCTAssertFalse(
            controller
                .terminateInterruptionProtectionObservationOwner
                .isPrepared
        )

        XCTAssertTrue(
            controller.beginGlobalHotkeySessionForTesting()
        )
        assertAppSwitcherProjectionSessionRead(
            from: runtimeProjectionService
        )
        guard let selectedAppID = model.selectedApp?.id else {
            return XCTFail("Expected selected app")
        }

        controller.terminateSelectedApp()

        XCTAssertEqual(model.terminatingAppID, selectedAppID)
        XCTAssertNil(model.pendingTerminateRequest)
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
        XCTAssertTrue(requestedAppIDs.isEmpty)
        XCTAssertTrue(protectionPreparedReadbacks.isEmpty)
        XCTAssertFalse(
            controller
                .terminateInterruptionProtectionObservationOwner
                .isPrepared
        )

        XCTAssertTrue(scheduler.fire(at: 0))

        XCTAssertFalse(
            controller
                .terminatePressFeedbackCompletionOwner
                .isPending
        )
        XCTAssertEqual(requestedAppIDs, [selectedAppID])
        XCTAssertEqual(protectionPreparedReadbacks, [true])
        XCTAssertEqual(model.terminatingAppID, selectedAppID)
        XCTAssertEqual(
            model.pendingTerminateRequest?.appID,
            selectedAppID
        )
        XCTAssertEqual(
            model.pendingTerminateRequest?.pid,
            42_301
        )
        XCTAssertEqual(
            model.pendingTerminateRequest?.generation,
            1
        )
        XCTAssertTrue(
            controller.shouldProtectTerminateSystemInterruption()
        )
        XCTAssertEqual(
            runtimeProjectionService
                .appSwitcherMaintenanceRequestsRecorded(),
            [
                .switcherSessionStarted,
                .appLifecycleRefresh
            ]
        )
        XCTAssertTrue(
            runtimeProjectionService
                .appTerminationSignalsRecorded()
                .isEmpty
        )
        XCTAssertFalse(scheduler.fire(at: 0))
        XCTAssertEqual(requestedAppIDs, [selectedAppID])
        XCTAssertEqual(protectionPreparedReadbacks, [true])

        controller.handlePanelDidResignKeyForTesting()

        XCTAssertNotNil(model.session)
        XCTAssertFalse(
            controller
                .suppressHotkeyReplayUntilReleaseForTesting
        )
    }

    @MainActor
    func testSwitcherPanelControllerQuitFrontmostAppInAppLayerKeepsSessionAfterWorkspaceTerminationRefresh()
        async
    {
        await withTemporarySearchPreferences(
            enabled: true,
            defaultScope: .app
        ) {
            let restoreHotkeyConfiguration =
                installTemporarySwitcherHotkeyConfiguration(
                    SwitcherHotkeyConfiguration(
                        baseKeys: [.option],
                        reverseKeys: [.shift],
                        mainKeys: [.tab],
                        quitKeys: [.q]
                    )
                )
            defer { restoreHotkeyConfiguration() }
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
                            .quitKeys.orderedKeys[0].keyCode,
                        modifierFlags:
                            hotkeyConfiguration.baseKeys.modifiers.eventModifierFlags
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
