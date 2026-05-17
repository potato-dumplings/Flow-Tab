import Foundation
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testSwitcherPanelVisibilityRecoveryPolicyOwnsDelayConstants() {
        let controller = SwitcherPanelController()

        XCTAssertEqual(controller.panelVisibilityRecoveryPolicy, .default)
        XCTAssertEqual(controller.initialPresentationVisibilityGraceWindow, 0.35)
        XCTAssertEqual(
            controller.interruptionPresentationRecoveryAttemptDelaysNs,
            [0, 50_000_000, 150_000_000, 300_000_000]
        )
        XCTAssertEqual(controller.panelPresentationRecoveryReorderDelayNs, 10_000_000)
    }

    @MainActor
    func testSwitcherPanelVisibilityRecoveryStateTracksPresentationLifecycle() {
        let controller = SwitcherPanelController()
        controller.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
        }

        XCTAssertEqual(controller.panelVisibilityRecoveryState, .idle)
        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())

        let initialGeneration = controller.beginInitialPresentationVisibilityTracking(
            trigger: "state_initial"
        )
        XCTAssertEqual(
            controller.panelVisibilityRecoveryState,
            .presenting(trigger: "state_initial", generation: initialGeneration)
        )

        XCTAssertTrue(
            controller.completeInitialPresentationVisibilityIfVisible(
                trigger: "state_initial",
                generation: initialGeneration,
                reason: "alreadyVisible",
                cancelRecoveryTask: false
            )
        )
        XCTAssertEqual(
            controller.panelVisibilityRecoveryState,
            .visibleConfirmed(
                trigger: "state_initial",
                generation: initialGeneration,
                reason: "alreadyVisible"
            )
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
    func testSwitcherPanelVisibilityRecoveryDiagnosticRecordsBeforeAndAfterSnapshots() async {
        let controller = SwitcherPanelController()
        controller.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
        }
        controller.panelVisibilityOverride = true
        controller.panelOcclusionStateOverride = []
        controller.appIsActiveOverride = false

        XCTAssertTrue(controller.beginGlobalHotkeySessionForTesting())

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
        let controller = SwitcherPanelController()
        controller.modelForTesting.snapshotProviderOverride = {
            RuntimeSnapshot(apps: self.searchScenarioApps(), contextsByID: [:])
        }
        controller.globalPrimaryModifierPressedOverride = true

        let defaults = UserDefaults.standard
        let previousVerbose = defaults.object(forKey: AppPreferenceKeys.enableVerboseDiagnostics)
        let previousLevel = defaults.object(forKey: AppPreferenceKeys.runtimeLogLevel)
        defaults.set(true, forKey: AppPreferenceKeys.enableVerboseDiagnostics)
        defaults.set(RuntimeLogLevel.debug.rawValue, forKey: AppPreferenceKeys.runtimeLogLevel)

        let iterationCount = 200
        let triggerPrefix = "initial_visibility_pressure_\(UUID().uuidString)"
        let logSnapshot = await RuntimeDiagnostics.shared.makeReadSnapshot()
        let startGeneration = controller.initialPresentationVisibilityGeneration
        let startRecoveryGeneration = controller.panelPresentationRecoveryGeneration

        defer {
            restoreUserDefaultsValue(
                previousVerbose,
                forKey: AppPreferenceKeys.enableVerboseDiagnostics,
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
            controller.panelVisibilityOverride = false

            let trigger = "\(triggerPrefix)_\(index)"
            controller.scheduleInitialPanelVisibilityRecovery(
                trigger: trigger,
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

            controller.cancelSelectionForTesting()

            XCTAssertNil(controller.modelForTesting.session, "iteration \(index)")
            XCTAssertFalse(controller.hasActivePresentationSession, "iteration \(index)")
            XCTAssertNil(controller.panelPresentationRecoveryTask, "iteration \(index)")
            XCTAssertEqual(controller.initialPresentationVisibilityDeadline, 0, accuracy: 0.0001, "iteration \(index)")
            XCTAssertNil(controller.initialPresentationVisibilityTrigger, "iteration \(index)")
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

        let didSettleRecoveryState = await waitUntil(
            "rapid open-close pressure settles stale initial visibility tasks",
            timeoutNanoseconds: 2_000_000_000,
            pollIntervalNanoseconds: 10_000_000
        ) {
            controller.modelForTesting.session == nil
                && !controller.hasActivePresentationSession
                && controller.panelPresentationRecoveryTask == nil
                && abs(controller.initialPresentationVisibilityDeadline) <= 0.0001
                && controller.initialPresentationVisibilityTrigger == nil
        }
        XCTAssertTrue(didSettleRecoveryState)

        XCTAssertNil(controller.modelForTesting.session)
        XCTAssertFalse(controller.hasActivePresentationSession)
        XCTAssertNil(controller.panelPresentationRecoveryTask)
        XCTAssertEqual(controller.initialPresentationVisibilityDeadline, 0, accuracy: 0.0001)
        XCTAssertNil(controller.initialPresentationVisibilityTrigger)
        XCTAssertEqual(controller.initialPresentationVisibilityGeneration, startGeneration + iterationCount * 2)
        XCTAssertEqual(controller.panelPresentationRecoveryGeneration, startRecoveryGeneration + iterationCount * 2)

        controller.panelVisibilityOverride = nil
        XCTAssertFalse(controller.isPanelPresented)

        let deltaLines = await RuntimeDiagnostics.shared.readRecentLines(
            limit: iterationCount * 20,
            minimumLevel: .debug,
            since: logSnapshot
        )
        let pressureLines = deltaLines.filter { $0.contains(triggerPrefix) }
        let trackedLines = pressureLines.filter { $0.contains("action=trackInitialVisibility") }
        let staleExecutionLines = pressureLines.filter { line in
            line.contains("action=softAttempt")
                || line.contains("action=complete")
                || line.contains("action=failed")
                || line.contains("systemInterruption")
        }

        XCTAssertEqual(trackedLines.count, iterationCount)
        XCTAssertTrue(
            staleExecutionLines.isEmpty,
            "stale recovery executions: \(staleExecutionLines.prefix(5).joined(separator: "\n"))"
        )
    }
}
