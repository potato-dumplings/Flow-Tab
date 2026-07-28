import AppKit
import Foundation
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    @MainActor
    private func makeInitialVisibilityProjectionPanelController(
        scheduler:
            (any InitialPanelVisibilityObservationScheduling)? = nil
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
                initialPanelVisibilityObservationScheduler: scheduler
            ),
            runtimeProjectionService
        )
    }

    @MainActor
    func testSwitcherPanelVisibilityRecoveryPolicyOwnsDelayConstants() {
        let controller = SwitcherPanelController()

        XCTAssertEqual(controller.panelVisibilityRecoveryPolicy, .default)
        XCTAssertEqual(
            controller.initialPresentationVisibilityWatchdogInterval,
            0.35
        )
        XCTAssertEqual(
            controller.interruptionPresentationRecoveryAttemptDelaysNs,
            [0, 50_000_000, 150_000_000, 300_000_000]
        )
        XCTAssertEqual(controller.panelPresentationRecoveryReorderDelayNs, 10_000_000)
    }

    @MainActor
    func testSwitcherPanelVisibilityRecoveryStateTracksPresentationLifecycle() {
        let (controller, runtimeProjectionService) = makeInitialVisibilityProjectionPanelController()

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
            controller.hasPendingInitialPresentationVisibilityWatchdog
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
            controller.hasPendingInitialPresentationVisibilityWatchdog
        )

        controller.schedulePanelVisibilityRecovery(
            trigger: "state_occluded",
            attemptDelaysNanoseconds: [1_000_000_000],
            cancelSessionOnFailure: false
        )
        XCTAssertEqual(
            controller.panelVisibilityRecoveryState,
            .suspectedHidden(
                trigger: "state_occluded",
                generation: controller.panelPresentationRecoveryGeneration
            )
        )

        controller.cancelSelectionForTesting()
        XCTAssertEqual(controller.panelVisibilityRecoveryState, .idle)
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
            controller.hasPendingInitialPresentationVisibilityWatchdog
        )
        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testSwitcherInitialVisibilityWatchdogCancelsReleasedSessionWithDiagnostic() {
        let scheduler =
            ManualInitialPanelVisibilityObservationScheduler()
        let (controller, runtimeProjectionService) =
            makeInitialVisibilityProjectionPanelController(
                scheduler: scheduler
            )
        controller.globalPrimaryModifierPressedOverride = false

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        assertInitialVisibilityProjectionRead(
            from: runtimeProjectionService,
            expectedReadCount: 1
        )
        controller.panelVisibilityOverride = false
        controller.panelOcclusionStateOverride = []
        let generation =
            controller.beginInitialPresentationVisibilityTracking(
                trigger: "watchdog_behavior"
            )

        scheduler.fireNext()

        let failure =
            controller.lastInitialPresentationVisibilityWatchdogFailure
        XCTAssertEqual(failure?.trigger, "watchdog_behavior")
        XCTAssertEqual(failure?.observationGeneration, generation)
        XCTAssertEqual(
            failure?.finalEvidence.source,
            .watchdogReadback
        )
        XCTAssertFalse(failure?.finalEvidence.snapshot.userVisible ?? true)
        XCTAssertNil(controller.modelForTesting.session)
        XCTAssertFalse(controller.hasActivePresentationSession)
        XCTAssertFalse(
            controller.hasPendingInitialPresentationVisibilityWatchdog
        )
    }

    @MainActor
    func testSwitcherPanelVisibilityRecoveryDiagnosticRecordsBeforeAndAfterSnapshots() async {
        let (controller, runtimeProjectionService) = makeInitialVisibilityProjectionPanelController()
        controller.panelVisibilityOverride = true
        controller.panelOcclusionStateOverride = []
        controller.appIsActiveOverride = false

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())
        assertInitialVisibilityProjectionRead(
            from: runtimeProjectionService,
            expectedReadCount: 1
        )

        await controller.performPanelVisibilityRecoveryAttempt(
            trigger: "diagnostic_recovery",
            activateApplicationIfNeeded: false,
            recoveryMode: .hardReorder,
            generation: 7,
            attempt: 2,
            totalAttempts: 4
        )

        let diagnostic = controller.lastPanelVisibilityRecoveryDiagnostic
        XCTAssertEqual(diagnostic?.trigger, "diagnostic_recovery")
        XCTAssertEqual(diagnostic?.generation, 7)
        XCTAssertEqual(diagnostic?.attempt, 2)
        XCTAssertEqual(diagnostic?.totalAttempts, 4)
        XCTAssertEqual(diagnostic?.mode, .hardReorder)
        XCTAssertEqual(diagnostic?.before.panelPresented, true)
        XCTAssertEqual(diagnostic?.before.userVisible, false)
        XCTAssertEqual(diagnostic?.before.occlusionVisible, false)
        XCTAssertEqual(diagnostic?.before.appActive, false)
        XCTAssertEqual(diagnostic?.after.panelPresented, true)
        XCTAssertEqual(diagnostic?.after.userVisible, false)
        XCTAssertEqual(diagnostic?.after.occlusionVisible, false)
        XCTAssertTrue(diagnostic?.logMessage.contains("action=visibilityReadback") ?? false)
        XCTAssertTrue(diagnostic?.logMessage.contains("before{panelVisible=1") ?? false)
        XCTAssertTrue(diagnostic?.logMessage.contains("after{panelVisible=1") ?? false)

        controller.cancelSelectionForTesting()
    }

    @MainActor
    func testSwitcherInitialVisibilityRecoveryRapidOpenClosePressureDoesNotReplayStaleTasks() async {
        let (controller, runtimeProjectionService) = makeInitialVisibilityProjectionPanelController()
        controller.globalPrimaryModifierPressedOverride = true

        let defaults = UserDefaults.standard
        let previousExpiration = defaults.object(forKey: AppPreferenceKeys.diagnosticSessionExpiration)
        let previousLevel = defaults.object(forKey: AppPreferenceKeys.runtimeLogLevel)
        RuntimeDiagnosticSessionStore.start(userDefaults: defaults)
        defaults.set(RuntimeLogLevel.debug.rawValue, forKey: AppPreferenceKeys.runtimeLogLevel)

        let iterationCount = 200
        let triggerPrefix = "initial_visibility_pressure_\(UUID().uuidString)"
        let privacyFormatter = RuntimeLogPrivacyFormatter(
            keyData: RuntimeLogFileStore.shared.loadOrCreatePrivacyFingerprintKey()
        )
        let triggerFingerprintTokens = Set((0..<iterationCount).map { index in
            "field0.value.fingerprint=\(privacyFormatter.stableFingerprint(for: "\(triggerPrefix)_\(index)"))"
        })
        let logSnapshot = await RuntimeDiagnostics.shared.makeReadSnapshot()
        let startGeneration = controller.initialPresentationVisibilityGeneration
        let startRecoveryGeneration = controller.panelPresentationRecoveryGeneration

        defer {
            restoreUserDefaultsValue(
                previousExpiration,
                forKey: AppPreferenceKeys.diagnosticSessionExpiration,
                userDefaults: defaults
            )
            restoreUserDefaultsValue(
                previousLevel,
                forKey: AppPreferenceKeys.runtimeLogLevel,
                userDefaults: defaults
            )
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
                initialVisibilityGeneration: visibilityGeneration,
                activateApplicationIfNeeded: false
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
            XCTAssertNotNil(controller.panelPresentationRecoveryTask, "iteration \(index)")
            XCTAssertTrue(
                controller.hasPendingInitialPresentationVisibilityWatchdog,
                "iteration \(index)"
            )

            controller.cancelSelectionForTesting()

            XCTAssertNil(controller.modelForTesting.session, "iteration \(index)")
            XCTAssertFalse(controller.hasActivePresentationSession, "iteration \(index)")
            XCTAssertNil(controller.panelPresentationRecoveryTask, "iteration \(index)")
            XCTAssertNil(controller.initialPresentationVisibilityTrigger, "iteration \(index)")
            XCTAssertFalse(
                controller.hasPendingInitialPresentationVisibilityWatchdog,
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

            if index.isMultiple(of: 25) {
                await Task.yield()
            }
        }

        XCTAssertNil(controller.modelForTesting.session)
        assertInitialVisibilityProjectionRead(
            from: runtimeProjectionService,
            expectedReadCount: iterationCount
        )
        XCTAssertFalse(controller.hasActivePresentationSession)
        XCTAssertNil(controller.panelPresentationRecoveryTask)
        XCTAssertNil(controller.initialPresentationVisibilityTrigger)
        XCTAssertFalse(
            controller.hasPendingInitialPresentationVisibilityWatchdog
        )
        XCTAssertEqual(controller.initialPresentationVisibilityGeneration, startGeneration + iterationCount * 2)
        XCTAssertEqual(controller.panelPresentationRecoveryGeneration, startRecoveryGeneration + iterationCount * 2)

        controller.panelVisibilityOverride = nil
        XCTAssertFalse(controller.isPanelPresented)

        let deltaLines = await RuntimeDiagnostics.shared.readRecentLines(
            limit: iterationCount * 20,
            minimumLevel: .debug,
            since: logSnapshot
        )
        let pressureLines = deltaLines.filter { line in
            line.contains("[SearchTrace]")
                && triggerFingerprintTokens.contains { line.contains($0) }
        }
        let trackedLines = pressureLines.filter {
            $0.contains("event.length=\("presentationRecovery".count)")
                && $0.contains("field1.value.length=\("trackInitialVisibility".count)")
        }
        let staleExecutionLines = pressureLines.filter { line in
            line.contains("field1.value.length=\("softAttempt".count)")
                || line.contains("field1.value.length=\("complete".count)")
                || line.contains("field1.value.length=\("failed".count)")
        }

        XCTAssertEqual(trackedLines.count, iterationCount)
        XCTAssertTrue(
            staleExecutionLines.isEmpty,
            "stale recovery executions: \(staleExecutionLines.prefix(5).joined(separator: "\n"))"
        )
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
