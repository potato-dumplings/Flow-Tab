import Foundation
import XCTest

private enum
    FlowTabUITestSettingsWindowBehaviorControlsProjectionTestPolicy
{
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testSettingsWindowBehaviorControlsProjectionPolicyUsesNamedWatchdog() {
        let watchdog =
            FlowTabUITestSettingsWindowBehaviorControlsProjectionPolicy
                .projectionWatchdog
        XCTAssertEqual(watchdog, 15)
        XCTAssertTrue(watchdog.isFinite)
        XCTAssertGreaterThan(watchdog, 0)
    }

    func testSettingsWindowBehaviorControlsProjectionRequiresCompleteSnapshot() {
        XCTAssertTrue(
            settingsWindowBehaviorControlsProjectionSnapshot()
                .isExactProjection
        )
        XCTAssertFalse(
            settingsWindowBehaviorControlsProjectionSnapshot(
                appState: .runningBackground
            ).isExactProjection
        )
        XCTAssertFalse(
            settingsWindowBehaviorControlsProjectionSnapshot(
                settingsContentExists: false
            ).isExactProjection
        )
        XCTAssertFalse(
            settingsWindowBehaviorControlsProjectionSnapshot(
                delayInputExists: false,
                delayInputValue: nil
            ).isExactProjection
        )
        XCTAssertFalse(
            settingsWindowBehaviorControlsProjectionSnapshot(
                delayInputValue: ""
            ).isExactProjection
        )
        XCTAssertFalse(
            settingsWindowBehaviorControlsProjectionSnapshot(
                autoRestoreExists: false,
                autoRestoreIsOn: nil
            ).isExactProjection
        )
        XCTAssertFalse(
            settingsWindowBehaviorControlsProjectionSnapshot(
                autoRestoreIsOn: nil
            ).isExactProjection
        )
        XCTAssertFalse(
            settingsWindowBehaviorControlsProjectionSnapshot(
                hideMinimizedExists: false,
                hideMinimizedIsOn: nil
            ).isExactProjection
        )
        XCTAssertFalse(
            settingsWindowBehaviorControlsProjectionSnapshot(
                hideMinimizedIsOn: nil
            ).isExactProjection
        )
    }

    func testSettingsWindowBehaviorControlsProjectionAcceptsInitialExactEvidence() {
        let owner =
            FlowTabUITestSettingsWindowBehaviorControlsProjectionObservationOwner(
                observationRegistration: nil,
                readback: {
                    self.settingsWindowBehaviorControlsProjectionSnapshot()
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(owner.resolvedEvidence?.source, .initialReadback)
    }

    func testSettingsWindowBehaviorControlsProjectionRequiresPostTriggerEvidence() {
        var acceptsEvidence = false
        var cancellationCount = 0
        let owner =
            FlowTabUITestSettingsWindowBehaviorControlsProjectionObservationOwner(
                acceptsEvidence: { acceptsEvidence },
                observationRegistration: { _ in
                    FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    self.settingsWindowBehaviorControlsProjectionSnapshot()
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(owner.latestEvidence?.source, .initialReadback)
        XCTAssertNil(owner.resolvedEvidence)

        acceptsEvidence = true
        owner.requestReadback(source: .triggerReadback)

        XCTAssertEqual(owner.resolvedEvidence?.source, .triggerReadback)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSettingsWindowBehaviorControlsProjectionUsesLaterEvidenceAndCancels() {
        var snapshot =
            settingsWindowBehaviorControlsProjectionSnapshot(
                settingsContentExists: false,
                delayInputExists: false,
                delayInputValue: nil,
                autoRestoreExists: false,
                autoRestoreIsOn: nil,
                hideMinimizedExists: false,
                hideMinimizedIsOn: nil
            )
        var readback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestSettingsWindowBehaviorControlsProjectionObservationOwner(
                observationRegistration: { callback in
                    readback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: { snapshot }
            )
        owner.start()
        defer { owner.cancel() }

        for _ in 0..<20 {
            snapshot =
                settingsWindowBehaviorControlsProjectionSnapshot(
                    hideMinimizedIsOn: nil
                )
            readback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }

        snapshot = settingsWindowBehaviorControlsProjectionSnapshot()
        readback?(.scheduledReadback)
        readback?(.triggerReadback)

        XCTAssertEqual(owner.resolvedEvidence?.source, .scheduledReadback)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSettingsWindowBehaviorControlsProjectionRejectsStaleGenerationsUnderPressure() {
        for _ in
            0..<FlowTabUITestSettingsWindowBehaviorControlsProjectionTestPolicy
                .pressureIterations
        {
            var snapshot =
                settingsWindowBehaviorControlsProjectionSnapshot(
                    settingsContentExists: false,
                    delayInputExists: false,
                    delayInputValue: nil
                )
            var readbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            let owner =
                FlowTabUITestSettingsWindowBehaviorControlsProjectionObservationOwner(
                    observationRegistration: { callback in
                        readbacks.append(callback)
                        return FlowTabUITestObservationCancellation {}
                    },
                    readback: { snapshot }
                )
            owner.start()
            let staleReadback = readbacks[0]
            owner.cancel()
            owner.start()

            snapshot = settingsWindowBehaviorControlsProjectionSnapshot()
            staleReadback(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
            readbacks[1](.scheduledReadback)
            readbacks[1](.triggerReadback)
            XCTAssertEqual(owner.resolvedEvidence?.generation, 2)
            owner.cancel()
        }
    }

    func testSettingsWindowBehaviorControlsProjectionWatchdogReportsFinalEvidence() {
        let owner =
            FlowTabUITestSettingsWindowBehaviorControlsProjectionObservationOwner(
                observationRegistration: nil,
                readback: {
                    self.settingsWindowBehaviorControlsProjectionSnapshot(
                        delayInputValue: "",
                        autoRestoreIsOn: nil
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSettingsWindowBehaviorControlsProjectionTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("source=watchdogReadback")
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("delayInputValue=Optional(\"\")")
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "autoRestoreToggleIsOn=nil"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "hideMinimizedToggleIsOn=Optional(false)"
            )
        )
    }

    private func settingsWindowBehaviorControlsProjectionSnapshot(
        appState: XCUIApplication.State = .runningForeground,
        settingsContentExists: Bool = true,
        delayInputExists: Bool = true,
        delayInputHittable: Bool = true,
        delayInputValue: String? = "0.80",
        autoRestoreExists: Bool = true,
        autoRestoreHittable: Bool = true,
        autoRestoreIsOn: Bool? = true,
        autoRestoreValue: String? = "1",
        hideMinimizedExists: Bool = true,
        hideMinimizedHittable: Bool = true,
        hideMinimizedIsOn: Bool? = false,
        hideMinimizedValue: String? = "0"
    ) -> FlowTabUITestSettingsWindowBehaviorControlsProjectionSnapshot {
        FlowTabUITestSettingsWindowBehaviorControlsProjectionSnapshot(
            appState: appState,
            settingsContentExists: settingsContentExists,
            delayInputExists: delayInputExists,
            delayInputHittable: delayInputHittable,
            delayInputValue: delayInputValue,
            autoRestoreToggleExists: autoRestoreExists,
            autoRestoreToggleHittable: autoRestoreHittable,
            autoRestoreToggleIsOn: autoRestoreIsOn,
            autoRestoreToggleValue: autoRestoreValue,
            hideMinimizedToggleExists: hideMinimizedExists,
            hideMinimizedToggleHittable: hideMinimizedHittable,
            hideMinimizedToggleIsOn: hideMinimizedIsOn,
            hideMinimizedToggleValue: hideMinimizedValue
        )
    }
}
