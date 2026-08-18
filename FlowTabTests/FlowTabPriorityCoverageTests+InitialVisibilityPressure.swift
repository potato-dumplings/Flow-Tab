import AppKit
import Foundation
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    @MainActor
    private func makeInitialVisibilityProjectionPanelController(
        scheduler:
            (any InitialPanelVisibilityObservationScheduling)? = nil,
        recoveryScheduler:
            (any PanelVisibilityRecoveryObservationScheduling)? = nil,
        modifierReleaseScheduler:
            (any ModifierReleaseObservationScheduling)? = nil,
        modifierReleaseEventSource:
            (any ModifierReleaseEventObserving)? = nil
    ) -> (
        controller: SwitcherPanelController,
        runtimeProjectionService: RecordingRuntimeProjectionService
    ) {
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            appSwitcherApps: searchScenarioApps()
        )
        return (
            SwitcherPanelController(
                model: LiveSwitcherModel(
                    runtimeProjectionService: runtimeProjectionService
                ),
                modifierReleaseObservationScheduler:
                    modifierReleaseScheduler,
                modifierReleaseEventSource: modifierReleaseEventSource,
                initialPanelVisibilityObservationScheduler: scheduler,
                panelVisibilityRecoveryObservationScheduler:
                    recoveryScheduler
            ),
            runtimeProjectionService
        )
    }

    @MainActor
    func testSwitcherPanelVisibilityRecoveryPolicyOwnsEvidenceBounds() {
        let controller = SwitcherPanelController()

        XCTAssertEqual(controller.panelVisibilityRecoveryPolicy, .default)
        XCTAssertEqual(
            controller
                .initialPresentationVisibilityRecoveryEscalationInterval,
            0.35
        )
        XCTAssertEqual(
            controller
                .interruptionPresentationRecoveryMaximumAttemptCount,
            4
        )
        XCTAssertEqual(
            controller
                .interruptionPresentationRecoveryConditionReadbackInterval,
            0.01
        )
        XCTAssertEqual(
            controller.interruptionPresentationRecoveryWatchdogInterval,
            1.0
        )
    }

    @MainActor
    func testSwitcherPanelVisibilityRecoveryStateTracksPresentationLifecycle() {
        let recoveryScheduler =
            ManualPanelVisibilityRecoveryObservationScheduler()
        let (controller, runtimeProjectionService) =
            makeInitialVisibilityProjectionPanelController(
                recoveryScheduler: recoveryScheduler
            )

        XCTAssertEqual(controller.panelVisibilityRecoveryState, .idle)
        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        assertInitialVisibilityProjectionRead(
            from: runtimeProjectionService,
            expectedReadCount: 1
        )
        controller.panelVisibilityOverride = false
        controller.panelOcclusionStateOverride = []

        let initialGeneration = controller.beginInitialPresentationVisibilityTracking(
            trigger: "state_initial"
        )
        XCTAssertEqual(
            controller.panelVisibilityRecoveryState,
                .presenting(trigger: "state_initial", generation: initialGeneration)
        )
        XCTAssertTrue(
            controller.hasPendingInitialPresentationVisibilityObservation
        )
        XCTAssertTrue(
            controller
                .hasPendingInitialPresentationVisibilityRecoveryEscalation
        )

        controller.panelVisibilityOverride = true
        controller.panelOcclusionStateOverride = .visible
        controller.handlePanelDidBecomeKeyForTesting()
        XCTAssertEqual(
            controller.panelVisibilityRecoveryState,
            .visibleConfirmed(
                trigger: "state_initial",
                generation: initialGeneration,
                reason: InitialPanelVisibilityEvidenceSource
                    .panelBecameKey
                    .rawValue
            )
        )
        XCTAssertFalse(
            controller.hasPendingInitialPresentationVisibilityObservation
        )
        XCTAssertFalse(
            controller
                .hasPendingInitialPresentationVisibilityRecoveryEscalation
        )

        controller.panelVisibilityOverride = true
        controller.panelOcclusionStateOverride = []
        controller.schedulePanelVisibilityRecovery(
            trigger: "state_occluded",
            maximumAttemptCount: 1,
            cancelSessionOnFailure: false
        )
        XCTAssertEqual(
            controller.panelVisibilityRecoveryState,
            .recovering(
                trigger: "state_occluded",
                generation:
                    controller.panelPresentationRecoveryGeneration,
                attempt: 1,
                totalAttempts: 1,
                mode: .hardReorder
            )
        )
        XCTAssertTrue(
            controller.hasPendingPanelVisibilityRecoveryObservation
        )

        controller.cancelSelectionForTesting()
        XCTAssertEqual(controller.panelVisibilityRecoveryState, .idle)
        XCTAssertFalse(
            controller.hasPendingPanelVisibilityRecoveryObservation
        )
    }

    @MainActor
    func testSwitcherInitialVisibilityObserverAcceptsWindowNotificationReadback() async {
        let (controller, runtimeProjectionService) =
            makeInitialVisibilityProjectionPanelController()

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        assertInitialVisibilityProjectionRead(
            from: runtimeProjectionService,
            expectedReadCount: 1
        )
        controller.panelVisibilityOverride = false
        controller.panelOcclusionStateOverride = []
        let generation =
            controller.beginInitialPresentationVisibilityTracking(
                trigger: "notification"
            )

        controller.panelVisibilityOverride = true
        controller.panelOcclusionStateOverride = .visible
        NotificationCenter.default.post(
            name: NSWindow.didExposeNotification,
            object: controller.panel
        )
        await Task.yield()

        XCTAssertEqual(
            controller.panelVisibilityRecoveryState,
            .visibleConfirmed(
                trigger: "notification",
                generation: generation,
                reason: InitialPanelVisibilityEvidenceSource
                    .panelExposed
                    .rawValue
            )
        )
        XCTAssertFalse(
            controller.hasPendingInitialPresentationVisibilityObservation
        )
        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testSwitcherInitialVisibilityRecoveryEscalationPreservesReleasedSessionUntilExactVisibility() {
        let visibilityScheduler =
            ManualInitialPanelVisibilityObservationScheduler()
        let recoveryScheduler =
            ManualPanelVisibilityRecoveryObservationScheduler()
        let modifierReleaseScheduler =
            ManualModifierReleaseObservationScheduler()
        let modifierReleaseEventSource = ManualModifierReleaseEventSource()
        let (controller, runtimeProjectionService) =
            makeInitialVisibilityProjectionPanelController(
                scheduler: visibilityScheduler,
                recoveryScheduler: recoveryScheduler,
                modifierReleaseScheduler: modifierReleaseScheduler,
                modifierReleaseEventSource: modifierReleaseEventSource
            )
        defer {
            controller.cancelSelectionForTesting()
            controller.panelVisibilityOverride = nil
            controller.panelOcclusionStateOverride = nil
            controller.panel.orderOut(nil)
        }
        controller.globalHotkeyHoldSetPressedOverride = false
        var activatedTarget: ActivationTarget?
        controller.modelForTesting.activationOverride = { target, _ in
            activatedTarget = target
        }

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        assertInitialVisibilityProjectionRead(
            from: runtimeProjectionService,
            expectedReadCount: 1
        )
        controller.panelVisibilityOverride = false
        controller.panelOcclusionStateOverride = []
        guard var expectedSession = controller.modelForTesting.session,
              let expectedActivationTarget = expectedSession.commitSelection()
        else {
            return XCTFail(
                "Expected an exact activation target before escalation."
            )
        }
        let generation =
            controller.beginInitialPresentationVisibilityTracking(
                trigger: "recovery_escalation_behavior"
            )

        visibilityScheduler.fireNext()

        let escalation = controller
            .lastInitialPresentationVisibilityRecoveryEscalation
        XCTAssertEqual(
            escalation?.trigger,
            "recovery_escalation_behavior"
        )
        XCTAssertEqual(escalation?.observationGeneration, generation)
        XCTAssertEqual(
            escalation?.finalEvidence.source,
            .recoveryEscalationReadback
        )
        XCTAssertFalse(
            escalation?.finalEvidence.snapshot.userVisible ?? true
        )
        XCTAssertNotNil(controller.modelForTesting.session)
        XCTAssertTrue(controller.hasActivePresentationSession)
        XCTAssertTrue(
            controller.hasPendingInitialPresentationVisibilityObservation
        )
        XCTAssertFalse(
            controller
                .hasPendingInitialPresentationVisibilityRecoveryEscalation
        )
        XCTAssertTrue(
            controller.hasPendingPanelVisibilityRecoveryObservation
        )
        let escalatedReadiness =
            FlowTabUITestInitialPresentationInputReadinessSnapshot(
                panelController: controller,
                mode: .global
            )
        XCTAssertTrue(escalatedReadiness.initialVisibilityPending)

        controller.panelVisibilityOverride = true
        controller.panelOcclusionStateOverride = .visible
        controller.handlePanelDidExposeForTesting()

        XCTAssertEqual(
            controller.panelVisibilityRecoveryState,
            .visibleConfirmed(
                trigger: "recovery_escalation_behavior",
                generation: generation,
                reason: InitialPanelVisibilityEvidenceSource
                    .panelExposed
                    .rawValue
            )
        )
        XCTAssertFalse(
            controller.hasPendingInitialPresentationVisibilityObservation
        )
        XCTAssertFalse(
            controller.hasPendingPanelVisibilityRecoveryObservation
        )
        let completedReadiness =
            FlowTabUITestInitialPresentationInputReadinessSnapshot(
                panelController: controller,
                mode: .global
            )
        XCTAssertFalse(completedReadiness.initialVisibilityPending)
        XCTAssertTrue(controller.hasPendingModifierReleaseConfirmation)

        modifierReleaseScheduler.fireNext()

        XCTAssertNil(controller.modelForTesting.session)
        XCTAssertEqual(activatedTarget, expectedActivationTarget)
        XCTAssertEqual(modifierReleaseEventSource.activeObserverCount, 0)
    }

    @MainActor
    func testSwitcherPanelVisibilityRecoveryDiagnosticRecordsEvidenceActions() {
        let recoveryScheduler =
            ManualPanelVisibilityRecoveryObservationScheduler()
        let (controller, runtimeProjectionService) =
            makeInitialVisibilityProjectionPanelController(
                recoveryScheduler: recoveryScheduler
            )
        controller.panelVisibilityOverride = true
        controller.panelOcclusionStateOverride = []
        controller.appIsActiveOverride = false

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        assertInitialVisibilityProjectionRead(
            from: runtimeProjectionService,
            expectedReadCount: 1
        )

        controller.schedulePanelVisibilityRecovery(
            trigger: "diagnostic_recovery",
            activateApplicationIfNeeded: false,
            recoveryMode: .hardReorder
        )

        let orderOutDiagnostic =
            controller.lastPanelVisibilityRecoveryDiagnostic
        XCTAssertEqual(
            orderOutDiagnostic?.trigger,
            "diagnostic_recovery"
        )
        XCTAssertEqual(
            orderOutDiagnostic?.generation,
            controller.panelPresentationRecoveryGeneration
        )
        XCTAssertEqual(orderOutDiagnostic?.mode, .hardReorder)
        XCTAssertEqual(
            orderOutDiagnostic?.before.panelPresented,
            true
        )
        XCTAssertEqual(
            orderOutDiagnostic?.before.userVisible,
            false
        )
        XCTAssertEqual(
            orderOutDiagnostic?.after.panelPresented,
            true
        )

        controller.panelVisibilityOverride = false
        recoveryScheduler.fireConditionReadback()
        let orderFrontDiagnostic =
            controller.lastPanelVisibilityRecoveryDiagnostic
        XCTAssertEqual(
            orderFrontDiagnostic?.before.panelPresented,
            false
        )
        XCTAssertEqual(
            orderFrontDiagnostic?.after.userVisible,
            false
        )
        XCTAssertTrue(
            orderFrontDiagnostic?.logMessage.contains(
                "action=visibilityReadback"
            ) ?? false
        )

        controller.panelVisibilityOverride = true
        controller.panelOcclusionStateOverride = .visible
        controller.handlePanelDidExposeForTesting()
        XCTAssertEqual(
            controller.panelVisibilityRecoveryState,
            .visibleConfirmed(
                trigger: "diagnostic_recovery",
                generation:
                    controller.panelPresentationRecoveryGeneration,
                reason: PanelVisibilityRecoveryEvidenceSource
                    .panelExposed
                    .rawValue
            )
        )

        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testSwitcherPanelVisibilityRecoveryWatchdogCancelsWithFinalEvidence() {
        let recoveryScheduler =
            ManualPanelVisibilityRecoveryObservationScheduler()
        let (controller, runtimeProjectionService) =
            makeInitialVisibilityProjectionPanelController(
                recoveryScheduler: recoveryScheduler
            )
        controller.globalHotkeyHoldSetPressedOverride = true

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        assertInitialVisibilityProjectionRead(
            from: runtimeProjectionService,
            expectedReadCount: 1
        )
        controller.panelVisibilityOverride = true
        controller.panelOcclusionStateOverride = []
        controller.schedulePanelVisibilityRecovery(
            trigger: "recovery_watchdog",
            maximumAttemptCount: 1,
            cancelSessionOnFailure: true,
            activateApplicationIfNeeded: false
        )

        controller.panelVisibilityOverride = false
        recoveryScheduler.fireConditionReadback()
        recoveryScheduler.fireWatchdog()

        let failure =
            controller.lastPanelVisibilityRecoveryWatchdogFailure
        XCTAssertEqual(failure?.trigger, "recovery_watchdog")
        XCTAssertEqual(failure?.completedAttemptCount, 1)
        XCTAssertEqual(
            failure?.finalEvidence.source,
            .watchdogReadback
        )
        XCTAssertFalse(
            failure?.finalEvidence.snapshot.userVisible ?? true
        )
        XCTAssertNil(controller.modelForTesting.session)
        XCTAssertFalse(controller.hasActivePresentationSession)
        XCTAssertFalse(
            controller.hasPendingPanelVisibilityRecoveryObservation
        )
    }

    @MainActor
    func testSwitcherInitialVisibilityRecoveryRapidOpenClosePressureDoesNotReplayCancelledObservers() {
        let visibilityScheduler =
            ManualInitialPanelVisibilityObservationScheduler()
        let recoveryScheduler =
            ManualPanelVisibilityRecoveryObservationScheduler()
        let (controller, runtimeProjectionService) =
            makeInitialVisibilityProjectionPanelController(
                scheduler: visibilityScheduler,
                recoveryScheduler: recoveryScheduler
            )
        controller.globalHotkeyHoldSetPressedOverride = true

        let iterationCount = 200
        let triggerPrefix = "initial_visibility_pressure_\(UUID().uuidString)"
        let startGeneration = controller.initialPresentationVisibilityGeneration
        let startRecoveryGeneration = controller.panelPresentationRecoveryGeneration

        defer {
            controller.panelVisibilityOverride = nil
            controller.panel.orderOut(nil)
        }

        for index in 0..<iterationCount {
            XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting(), "iteration \(index)")
            assertInitialVisibilityProjectionRead(
                from: runtimeProjectionService,
                expectedReadCount: index + 1,
                file: #filePath,
                line: #line
            )
            controller.panelVisibilityOverride = false

            let trigger = "\(triggerPrefix)_\(index)"
            let visibilityGeneration =
                controller.beginInitialPresentationVisibilityTracking(
                    trigger: trigger
                )
            controller.scheduleInitialPanelVisibilityRecovery(
                trigger: trigger,
                initialVisibilityGeneration: visibilityGeneration
            )

            let expectedScheduledGeneration = startGeneration + index * 2 + 1
            let expectedScheduledRecoveryGeneration = startRecoveryGeneration + index * 2 + 1
            XCTAssertEqual(
                controller.initialPresentationVisibilityGeneration,
                expectedScheduledGeneration,
                "iteration \(index)"
            )
            XCTAssertEqual(
                controller.panelPresentationRecoveryGeneration,
                expectedScheduledRecoveryGeneration,
                "iteration \(index)"
            )
            XCTAssertEqual(controller.initialPresentationVisibilityTrigger, trigger, "iteration \(index)")
            XCTAssertTrue(
                controller
                    .hasPendingInitialPresentationVisibilityObservation,
                "iteration \(index)"
            )
            XCTAssertTrue(
                controller
                    .hasPendingInitialPresentationVisibilityRecoveryEscalation,
                "iteration \(index)"
            )
            XCTAssertEqual(
                visibilityScheduler.pendingIntervals,
                [
                    controller
                        .initialPresentationVisibilityRecoveryEscalationInterval
                ],
                "iteration \(index)"
            )
            XCTAssertEqual(
                controller.lastPanelVisibilityRecoveryDiagnostic?.trigger,
                trigger,
                "iteration \(index)"
            )

            controller.cancelSelectionForTesting()

            XCTAssertNil(controller.modelForTesting.session, "iteration \(index)")
            XCTAssertFalse(controller.hasActivePresentationSession, "iteration \(index)")
            XCTAssertNil(controller.initialPresentationVisibilityTrigger, "iteration \(index)")
            XCTAssertFalse(
                controller
                    .hasPendingInitialPresentationVisibilityObservation,
                "iteration \(index)"
            )
            XCTAssertFalse(
                controller
                    .hasPendingInitialPresentationVisibilityRecoveryEscalation,
                "iteration \(index)"
            )
            XCTAssertEqual(
                controller.initialPresentationVisibilityGeneration,
                expectedScheduledGeneration + 1,
                "iteration \(index)"
            )
            XCTAssertEqual(
                controller.panelPresentationRecoveryGeneration,
                expectedScheduledRecoveryGeneration + 1,
                "iteration \(index)"
            )
            XCTAssertTrue(
                visibilityScheduler.pendingIntervals.isEmpty,
                "iteration \(index)"
            )
            XCTAssertEqual(
                recoveryScheduler.pendingConditionReadbackCount,
                0,
                "iteration \(index)"
            )
            XCTAssertEqual(
                recoveryScheduler.pendingWatchdogCount,
                0,
                "iteration \(index)"
            )
        }

        XCTAssertNil(controller.modelForTesting.session)
        assertInitialVisibilityProjectionRead(
            from: runtimeProjectionService,
            expectedReadCount: iterationCount
        )
        XCTAssertFalse(controller.hasActivePresentationSession)
        XCTAssertNil(controller.initialPresentationVisibilityTrigger)
        XCTAssertFalse(
            controller.hasPendingInitialPresentationVisibilityObservation
        )
        XCTAssertFalse(
            controller
                .hasPendingInitialPresentationVisibilityRecoveryEscalation
        )
        XCTAssertEqual(controller.initialPresentationVisibilityGeneration, startGeneration + iterationCount * 2)
        XCTAssertEqual(controller.panelPresentationRecoveryGeneration, startRecoveryGeneration + iterationCount * 2)

        controller.panelVisibilityOverride = nil
        XCTAssertFalse(controller.isPanelPresented)

        let finalDiagnostic =
            controller.lastPanelVisibilityRecoveryDiagnostic
        visibilityScheduler.fireAll()
        recoveryScheduler.fireAll()
        XCTAssertEqual(
            controller.lastPanelVisibilityRecoveryDiagnostic,
            finalDiagnostic
        )
        XCTAssertNil(
            controller.lastInitialPresentationVisibilityRecoveryEscalation
        )
        XCTAssertNil(controller.modelForTesting.session)
        XCTAssertFalse(controller.hasActivePresentationSession)
    }

    private func assertInitialVisibilityProjectionRead(
        from runtimeProjectionService: RecordingRuntimeProjectionService,
        expectedReadCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            runtimeProjectionService.appSwitcherProjectionReadCount(),
            expectedReadCount,
            file: file,
            line: line
        )
        XCTAssertEqual(
            runtimeProjectionService.appSwitcherMaintenanceRequestsRecorded(),
            Array(repeating: .switcherSessionStarted, count: expectedReadCount),
            file: file,
            line: line
        )
    }
}
