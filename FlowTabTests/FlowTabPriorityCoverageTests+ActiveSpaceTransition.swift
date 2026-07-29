import AppKit
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testSwitcherPanelControllerActiveSpaceChangeKeepsSessionVisibleWithoutReactivatingApp() {
        let recoveryScheduler =
            ManualPanelVisibilityRecoveryObservationScheduler()
        let transitionScheduler =
            ManualActiveSpaceTransitionObservationScheduler()
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            appSwitcherApps: searchScenarioApps(),
            spaceTopologyProjection:
                makeCompleteCurrentSpaceFullscreenProjectionForTesting(
                    currentSpaceID: 7,
                    spaceGeneration: 1
                )
        )
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService: runtimeProjectionService
            ),
            panelVisibilityRecoveryObservationScheduler:
                recoveryScheduler,
            activeSpaceTransitionObservationScheduler:
                transitionScheduler
        )
        controller.globalPrimaryModifierPressedOverride = true
        controller.appIsActiveOverride = false
        var activateCallCount = 0
        controller.activateApplicationIgnoringOtherAppsOverride = {
            activateCallCount += 1
        }

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        controller.panelOcclusionStateOverride = []
        controller.handleActiveSpaceDidChangeForTesting()

        XCTAssertTrue(
            controller.hasPendingActiveSpaceTransitionObservation
        )
        XCTAssertTrue(
            controller
                .isApplicationActivationSuppressedForActiveSpaceTransition
        )
        XCTAssertEqual(
            recoveryScheduler.pendingConditionReadbackCount,
            0
        )

        runtimeProjectionService.setSpaceTopologyProjection(
            makeCompleteCurrentSpaceFullscreenProjectionForTesting(
                currentSpaceID: 8,
                spaceGeneration: 2
            )
        )
        _ = controller.handleAppSwitcherProjectionDidUpdateForTesting()
        controller.panelVisibilityOverride = false
        recoveryScheduler.fireConditionReadback()
        controller.panelVisibilityOverride = true
        controller.panelOcclusionStateOverride = .visible
        controller.handlePanelDidExposeForTesting()

        guard case .visibleConfirmed =
            controller.panelVisibilityRecoveryState
        else {
            return XCTFail(
                "Active-Space recovery must complete from window evidence."
            )
        }
        XCTAssertNotNil(controller.modelForTesting.session)
        XCTAssertEqual(activateCallCount, 0)
        XCTAssertFalse(
            controller
                .isApplicationActivationSuppressedForActiveSpaceTransition
        )
        XCTAssertFalse(
            controller.suppressHotkeyReplayUntilReleaseForTesting
        )
    }

    @MainActor
    func testSwitcherPanelControllerStableActiveSpaceEvidenceKeepsVisibleSessionWithoutRecovery() {
        let recoveryScheduler =
            ManualPanelVisibilityRecoveryObservationScheduler()
        let transitionScheduler =
            ManualActiveSpaceTransitionObservationScheduler()
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            appSwitcherApps: searchScenarioApps(),
            spaceTopologyProjection:
                makeCompleteCurrentSpaceFullscreenProjectionForTesting(
                    currentSpaceID: 7,
                    spaceGeneration: 1
                )
        )
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService: runtimeProjectionService
            ),
            panelVisibilityRecoveryObservationScheduler:
                recoveryScheduler,
            activeSpaceTransitionObservationScheduler:
                transitionScheduler
        )
        controller.globalPrimaryModifierPressedOverride = true
        controller.panelVisibilityOverride = true
        controller.panelOcclusionStateOverride = .visible

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        controller.handleActiveSpaceDidChangeForTesting()
        runtimeProjectionService.setSpaceTopologyProjection(
            makeCompleteCurrentSpaceFullscreenProjectionForTesting(
                currentSpaceID: 7,
                spaceGeneration: 2
            )
        )
        _ = controller.handleAppSwitcherProjectionDidUpdateForTesting()

        XCTAssertNotNil(controller.modelForTesting.session)
        XCTAssertFalse(
            controller.hasPendingActiveSpaceTransitionObservation
        )
        XCTAssertFalse(
            controller
                .isApplicationActivationSuppressedForActiveSpaceTransition
        )
        XCTAssertEqual(
            recoveryScheduler.pendingConditionReadbackCount,
            0
        )
        XCTAssertEqual(recoveryScheduler.pendingWatchdogCount, 0)
        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testSwitcherPanelControllerActiveSpaceWatchdogUsesFinalVisibleReadback() {
        let transitionScheduler =
            ManualActiveSpaceTransitionObservationScheduler()
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            appSwitcherApps: searchScenarioApps(),
            spaceTopologyProjection:
                makeCompleteCurrentSpaceFullscreenProjectionForTesting(
                    currentSpaceID: 7,
                    spaceGeneration: 1
                )
        )
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService: runtimeProjectionService
            ),
            activeSpaceTransitionObservationScheduler:
                transitionScheduler
        )
        controller.globalPrimaryModifierPressedOverride = true
        controller.panelVisibilityOverride = true
        controller.panelOcclusionStateOverride = .visible

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        controller.handleActiveSpaceDidChangeForTesting()
        transitionScheduler.fireNext()

        XCTAssertNotNil(controller.modelForTesting.session)
        XCTAssertFalse(
            controller.hasPendingActiveSpaceTransitionObservation
        )
        XCTAssertFalse(
            controller
                .isApplicationActivationSuppressedForActiveSpaceTransition
        )
        XCTAssertEqual(
            controller.lastActiveSpaceTransitionWatchdogFailure?
                .baseline.spaceGeneration,
            1
        )
        XCTAssertEqual(
            controller.lastActiveSpaceTransitionWatchdogFailure?
                .finalEvidence.snapshot.spaceGeneration,
            1
        )
        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testSwitcherPanelControllerActiveSpaceNotificationSignalsRuntimeTopologyChange() {
        let runtimeProjectionService = RecordingRuntimeProjectionService()
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService: runtimeProjectionService
            )
        )

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        XCTAssertEqual(
            runtimeProjectionService.spaceTopologyChangeSignalCount(),
            1
        )
        XCTAssertNil(controller.modelForTesting.session)
    }

    @MainActor
    func testSwitcherPanelControllerActiveSpaceChangeCancelsSessionAfterModifierRelease() {
        let transitionScheduler =
            ManualActiveSpaceTransitionObservationScheduler()
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            appSwitcherApps: searchScenarioApps(),
            spaceTopologyProjection:
                makeCompleteCurrentSpaceFullscreenProjectionForTesting(
                    currentSpaceID: 7,
                    spaceGeneration: 1
                )
        )
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService: runtimeProjectionService
            ),
            activeSpaceTransitionObservationScheduler:
                transitionScheduler
        )
        controller.globalPrimaryModifierPressedOverride = false
        controller.globalMainKeyPressedOverride = false

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        controller.handleActiveSpaceDidChangeForTesting()
        XCTAssertNotNil(controller.modelForTesting.session)
        runtimeProjectionService.setSpaceTopologyProjection(
            makeCompleteCurrentSpaceFullscreenProjectionForTesting(
                currentSpaceID: 8,
                spaceGeneration: 2
            )
        )
        _ = controller.handleAppSwitcherProjectionDidUpdateForTesting()

        XCTAssertNil(controller.modelForTesting.session)
        XCTAssertFalse(
            controller.suppressHotkeyReplayUntilReleaseForTesting
        )
    }

    @MainActor
    func testSwitcherPanelControllerTerminateRefreshProtectsObservedActiveSpaceTransition() {
        let initialApps = terminateScenarioApps()
        let transitionScheduler =
            ManualActiveSpaceTransitionObservationScheduler()
        let recordingService = RecordingRuntimeProjectionService(
            appSwitcherApps: initialApps,
            spaceTopologyProjection:
                makeCompleteCurrentSpaceFullscreenProjectionForTesting(
                    currentSpaceID: 7,
                    spaceGeneration: 1
                )
        )
        let runtimeProjectionService =
            RetainingTerminatedAppRuntimeProjectionService(
                recording: recordingService
            )
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService: runtimeProjectionService
            ),
            activeSpaceTransitionObservationScheduler:
                transitionScheduler
        )
        controller.globalPrimaryModifierPressedOverride = false
        controller.globalMainKeyPressedOverride = false

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        let terminatedAppID = controller.modelForTesting.selectedApp?.id
        guard let terminatedAppID else {
            return XCTFail("Expected selected app before terminate refresh.")
        }
        XCTAssertEqual(
            recordingService
                .appSwitcherMaintenanceRequestsRecorded(),
            [.switcherSessionStarted]
        )

        controller.handleWorkspaceApplicationTerminatedForTesting(
            appID: terminatedAppID,
            pid: 42_300
        )

        XCTAssertEqual(
            runtimeProjectionService.appTerminationSignalsRecorded()
                .map(\.appID),
            [terminatedAppID]
        )
        XCTAssertGreaterThanOrEqual(
            recordingService.appSwitcherProjectionReadCount(),
            4
        )
        XCTAssertNotNil(controller.modelForTesting.session)
        XCTAssertFalse(
            controller.modelForTesting.session?.apps.contains {
                $0.id == terminatedAppID
            } ?? true
        )
        XCTAssertTrue(
            controller.shouldProtectTerminateSystemInterruption()
        )

        controller.handleActiveSpaceDidChangeForTesting()
        recordingService.setSpaceTopologyProjection(
            makeCompleteCurrentSpaceFullscreenProjectionForTesting(
                currentSpaceID: 8,
                spaceGeneration: 2
            )
        )
        _ = controller.handleAppSwitcherProjectionDidUpdateForTesting()

        XCTAssertNotNil(controller.modelForTesting.session)
        XCTAssertFalse(
            controller.suppressHotkeyReplayUntilReleaseForTesting
        )
        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testSwitcherPanelControllerSystemInterruptionsCloseReplayGateFromObservedRelease() {
        let releaseScheduler =
            ManualModifierReleaseObservationScheduler()
        let releaseEventSource = ManualModifierReleaseEventSource()
        let transitionScheduler =
            ManualActiveSpaceTransitionObservationScheduler()
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            appSwitcherApps: searchScenarioApps(),
            spaceTopologyProjection:
                makeCompleteCurrentSpaceFullscreenProjectionForTesting(
                    currentSpaceID: 7,
                    spaceGeneration: 1
                )
        )
        let controller = SwitcherPanelController(
            model: LiveSwitcherModel(
                runtimeProjectionService: runtimeProjectionService
            ),
            modifierReleaseObservationScheduler: releaseScheduler,
            modifierReleaseEventSource: releaseEventSource,
            activeSpaceTransitionObservationScheduler:
                transitionScheduler
        )
        controller.globalPrimaryModifierPressedOverride = false
        controller.globalMainKeyPressedOverride = false

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        controller.handleActiveSpaceDidChangeForTesting()
        runtimeProjectionService.setSpaceTopologyProjection(
            makeCompleteCurrentSpaceFullscreenProjectionForTesting(
                currentSpaceID: 8,
                spaceGeneration: 2
            )
        )
        _ = controller.handleAppSwitcherProjectionDidUpdateForTesting()

        XCTAssertNil(controller.modelForTesting.session)
        XCTAssertFalse(
            controller.suppressHotkeyReplayUntilReleaseForTesting
        )

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        controller.panelOcclusionStateOverride = []
        controller.handlePanelOcclusionStateDidChangeForTesting()

        XCTAssertNil(controller.modelForTesting.session)
        XCTAssertFalse(
            controller.suppressHotkeyReplayUntilReleaseForTesting
        )

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        controller.appIsActiveOverride = false
        controller.handlePanelDidResignKeyForTesting()

        XCTAssertNil(controller.modelForTesting.session)
        XCTAssertFalse(
            controller.suppressHotkeyReplayUntilReleaseForTesting
        )
        XCTAssertEqual(releaseEventSource.activeObserverCount, 0)
        XCTAssertEqual(releaseScheduler.pendingCount, 0)
    }
}
