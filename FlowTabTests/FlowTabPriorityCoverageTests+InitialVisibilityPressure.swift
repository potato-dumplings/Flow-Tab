import Foundation
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
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
            XCTAssertEqual(
                controller.initialPresentationVisibilityGeneration,
                expectedScheduledGeneration,
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

            if index.isMultiple(of: 25) {
                await Task.yield()
            }
        }

        let settleNanoseconds = UInt64((controller.initialPresentationVisibilityGraceWindow + 0.15) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: settleNanoseconds)

        XCTAssertNil(controller.modelForTesting.session)
        XCTAssertFalse(controller.hasActivePresentationSession)
        XCTAssertNil(controller.panelPresentationRecoveryTask)
        XCTAssertEqual(controller.initialPresentationVisibilityDeadline, 0, accuracy: 0.0001)
        XCTAssertNil(controller.initialPresentationVisibilityTrigger)
        XCTAssertEqual(controller.initialPresentationVisibilityGeneration, startGeneration + iterationCount * 2)

        controller.panelVisibilityOverride = nil
        XCTAssertFalse(controller.isPanelPresented)

        let deltaLines = await RuntimeDiagnostics.shared.readRecentLines(
            limit: iterationCount * 8,
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
