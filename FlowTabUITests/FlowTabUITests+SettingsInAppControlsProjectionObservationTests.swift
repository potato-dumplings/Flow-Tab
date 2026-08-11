import Foundation
import XCTest

private enum FlowTabUITestSettingsInAppControlsProjectionTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 200
}

extension FlowTabUITests {
    func testSettingsInAppControlsProjectionPolicyUsesNamedWatchdog() {
        let watchdog =
            FlowTabUITestSettingsInAppControlsProjectionPolicy
                .projectionWatchdog
        XCTAssertEqual(watchdog, 10)
        XCTAssertTrue(watchdog.isFinite)
        XCTAssertGreaterThan(watchdog, 0)
    }

    func testSettingsInAppControlsProjectionRequiresCompleteDisabledState() {
        XCTAssertTrue(settingsInAppControlsProjectionSnapshot().isDisabledProjection)
        XCTAssertFalse(
            settingsInAppControlsProjectionSnapshot(
                appState: .runningBackground
            ).isDisabledProjection
        )
        XCTAssertFalse(
            settingsInAppControlsProjectionSnapshot(
                settingsContentExists: false
            ).isDisabledProjection
        )
        XCTAssertFalse(
            settingsInAppControlsProjectionSnapshot(
                modifierExists: false,
                modifierEnabled: nil
            ).isDisabledProjection
        )
        XCTAssertFalse(
            settingsInAppControlsProjectionSnapshot(
                modifierEnabled: true
            ).isDisabledProjection
        )
        XCTAssertFalse(
            settingsInAppControlsProjectionSnapshot(
                keyExists: false,
                keyEnabled: nil
            ).isDisabledProjection
        )
        XCTAssertFalse(
            settingsInAppControlsProjectionSnapshot(
                keyEnabled: true
            ).isDisabledProjection
        )
    }

    func testSettingsInAppControlsProjectionRequiresPostTriggerEvidence() {
        var acceptsEvidence = false
        var cancellationCount = 0
        let owner =
            FlowTabUITestSettingsInAppControlsProjectionObservationOwner(
                acceptsEvidence: { acceptsEvidence },
                observationRegistration: { _ in
                    FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    self.settingsInAppControlsProjectionSnapshot()
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(owner.latestEvidence?.source, .initialReadback)
        XCTAssertNil(owner.resolvedEvidence)

        acceptsEvidence = true
        owner.requestReadback(source: .triggerReadback)

        XCTAssertEqual(owner.resolvedEvidence?.source, .triggerReadback)
        XCTAssertTrue(
            owner.resolvedEvidence?.value.isDisabledProjection == true
        )
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSettingsInAppControlsProjectionUsesLaterEvidenceAndCancels() {
        var snapshot = settingsInAppControlsProjectionSnapshot(
            keyExists: false,
            keyEnabled: nil
        )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestSettingsInAppControlsProjectionObservationOwner(
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: { snapshot }
            )
        owner.start()
        defer { owner.cancel() }

        for _ in 0..<20 {
            snapshot = settingsInAppControlsProjectionSnapshot(
                modifierEnabled: true,
                keyEnabled: false
            )
            scheduledReadback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }

        snapshot = settingsInAppControlsProjectionSnapshot()
        scheduledReadback?(.scheduledReadback)
        scheduledReadback?(.triggerReadback)

        XCTAssertEqual(owner.resolvedEvidence?.source, .scheduledReadback)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSettingsInAppControlsProjectionCancellationRejectsLateReadback() {
        var snapshot = settingsInAppControlsProjectionSnapshot(
            settingsContentExists: false
        )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestSettingsInAppControlsProjectionObservationOwner(
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: { snapshot }
            )
        owner.start()
        owner.cancel()

        snapshot = settingsInAppControlsProjectionSnapshot()
        scheduledReadback?(.scheduledReadback)

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSettingsInAppControlsProjectionWatchdogReportsFinalEvidence() {
        var acceptsEvidence = false
        var readbackCount = 0
        let owner =
            FlowTabUITestSettingsInAppControlsProjectionObservationOwner(
                acceptsEvidence: { acceptsEvidence },
                observationRegistration: { _ in
                    FlowTabUITestObservationCancellation {}
                },
                readback: {
                    defer { readbackCount += 1 }
                    if readbackCount >= 2 {
                        return self.settingsInAppControlsProjectionSnapshot()
                    }
                    return self.settingsInAppControlsProjectionSnapshot(
                        keyExists: false,
                        keyEnabled: nil
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }
        acceptsEvidence = true
        owner.requestReadback(source: .triggerReadback)

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSettingsInAppControlsProjectionTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("source=watchdogReadback")
        )
        XCTAssertTrue(owner.diagnosticSummary.contains("modifierExists=true"))
        XCTAssertTrue(
            owner.diagnosticSummary.contains("modifierEnabled=Optional(false)")
        )
        XCTAssertTrue(owner.diagnosticSummary.contains("keyExists=true"))
        XCTAssertTrue(
            owner.diagnosticSummary.contains("keyEnabled=Optional(false)")
        )
        XCTAssertTrue(owner.diagnosticSummary.contains("waitResult="))
    }

    func testSettingsInAppControlsProjectionRejectsStaleReadbacksUnderPressure() {
        for _ in
            0..<FlowTabUITestSettingsInAppControlsProjectionTestPolicy
                .pressureIterations
        {
            var acceptsEvidence = false
            var snapshot = settingsInAppControlsProjectionSnapshot(
                settingsContentExists: false
            )
            var scheduledReadbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            let owner =
                FlowTabUITestSettingsInAppControlsProjectionObservationOwner(
                    acceptsEvidence: { acceptsEvidence },
                    observationRegistration: { callback in
                        scheduledReadbacks.append(callback)
                        return FlowTabUITestObservationCancellation {}
                    },
                    readback: { snapshot }
                )

            owner.start()
            acceptsEvidence = true
            owner.requestReadback(source: .triggerReadback)
            owner.requestReadback(source: .triggerReadback)
            XCTAssertNil(owner.resolvedEvidence)
            let staleReadback = scheduledReadbacks[0]

            owner.cancel()
            acceptsEvidence = false
            owner.start()
            acceptsEvidence = true
            snapshot = settingsInAppControlsProjectionSnapshot()

            staleReadback(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
            scheduledReadbacks[1](.scheduledReadback)
            scheduledReadbacks[1](.triggerReadback)

            XCTAssertEqual(owner.resolvedEvidence?.generation, 2)
            XCTAssertEqual(
                owner.resolvedEvidence?.source,
                .scheduledReadback
            )
            owner.cancel()
        }
    }

    private func settingsInAppControlsProjectionSnapshot(
        appState: XCUIApplication.State = .runningForeground,
        settingsContentExists: Bool = true,
        modifierExists: Bool = true,
        modifierEnabled: Bool? = false,
        keyExists: Bool = true,
        keyEnabled: Bool? = false
    ) -> FlowTabUITestSettingsInAppControlsProjectionSnapshot {
        FlowTabUITestSettingsInAppControlsProjectionSnapshot(
            appState: appState,
            settingsContentExists: settingsContentExists,
            modifierExists: modifierExists,
            modifierEnabled: modifierEnabled,
            keyExists: keyExists,
            keyEnabled: keyEnabled
        )
    }
}
