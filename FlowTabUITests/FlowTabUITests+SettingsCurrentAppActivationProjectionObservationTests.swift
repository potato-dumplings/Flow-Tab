import Foundation
import XCTest

private enum
    FlowTabUITestSettingsCurrentAppActivationProjectionObservationTestPolicy
{
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testSettingsCurrentAppActivationProjectionPolicyUsesNamedWatchdog() {
        let watchdog =
            FlowTabUITestSettingsCurrentAppActivationProjectionPolicy
                .projectionWatchdog
        XCTAssertEqual(watchdog, 12)
        XCTAssertTrue(watchdog.isFinite)
        XCTAssertGreaterThan(watchdog, 0)
    }

    func testSettingsCurrentAppActivationProjectionRequiresCompleteSnapshot() {
        XCTAssertTrue(
            settingsCurrentAppActivationProjectionSnapshot()
                .isExactProjection
        )
        XCTAssertFalse(
            settingsCurrentAppActivationProjectionSnapshot(
                appState: .runningBackground
            ).isExactProjection
        )
        XCTAssertFalse(
            settingsCurrentAppActivationProjectionSnapshot(
                settingsContentExists: false
            ).isExactProjection
        )
        XCTAssertFalse(
            settingsCurrentAppActivationProjectionSnapshot(
                toggleExists: false,
                toggleIsOn: nil
            ).isExactProjection
        )
        XCTAssertFalse(
            settingsCurrentAppActivationProjectionSnapshot(
                toggleIsOn: true
            ).isExactProjection
        )
        XCTAssertFalse(
            settingsCurrentAppActivationProjectionSnapshot(
                hiddenCountExists: false
            ).isExactProjection
        )
    }

    func testSettingsCurrentAppActivationProjectionAcceptsInitialExactEvidence() {
        let owner =
            FlowTabUITestSettingsCurrentAppActivationProjectionObservationOwner(
                observationRegistration: nil,
                readback: {
                    self.settingsCurrentAppActivationProjectionSnapshot()
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .initialReadback
        )
    }

    func testSettingsCurrentAppActivationProjectionRequiresPostTriggerEvidence() {
        var acceptsEvidence = false
        var cancellationCount = 0
        let owner =
            FlowTabUITestSettingsCurrentAppActivationProjectionObservationOwner(
                acceptsEvidence: { acceptsEvidence },
                observationRegistration: { _ in
                    FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    self.settingsCurrentAppActivationProjectionSnapshot()
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(
            owner.latestEvidence?.source,
            .initialReadback
        )
        XCTAssertNil(owner.resolvedEvidence)

        acceptsEvidence = true
        owner.requestReadback(source: .triggerReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .triggerReadback
        )
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSettingsCurrentAppActivationProjectionUsesLaterEvidenceAndCancels() {
        var snapshot =
            settingsCurrentAppActivationProjectionSnapshot(
                settingsContentExists: false,
                toggleExists: false,
                toggleIsOn: nil,
                hiddenCountExists: false
            )
        var readback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestSettingsCurrentAppActivationProjectionObservationOwner(
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
                settingsCurrentAppActivationProjectionSnapshot(
                    toggleIsOn: true,
                    hiddenCountExists: false
                )
            readback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }

        snapshot = settingsCurrentAppActivationProjectionSnapshot()
        readback?(.scheduledReadback)
        readback?(.triggerReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .scheduledReadback
        )
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSettingsCurrentAppActivationProjectionRejectsStaleGenerationsUnderPressure() {
        for _ in
            0..<FlowTabUITestSettingsCurrentAppActivationProjectionObservationTestPolicy
                .pressureIterations
        {
            var snapshot =
                settingsCurrentAppActivationProjectionSnapshot(
                    settingsContentExists: false,
                    hiddenCountExists: false
                )
            var readbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            let owner =
                FlowTabUITestSettingsCurrentAppActivationProjectionObservationOwner(
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

            snapshot =
                settingsCurrentAppActivationProjectionSnapshot()
            staleReadback(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
            readbacks[1](.scheduledReadback)
            readbacks[1](.triggerReadback)
            XCTAssertEqual(
                owner.resolvedEvidence?.generation,
                2
            )
            owner.cancel()
        }
    }

    func testSettingsCurrentAppActivationProjectionWatchdogReportsFinalEvidence() {
        let owner =
            FlowTabUITestSettingsCurrentAppActivationProjectionObservationOwner(
                observationRegistration: nil,
                readback: {
                    self.settingsCurrentAppActivationProjectionSnapshot(
                        toggleIsOn: true,
                        hiddenCountExists: false
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSettingsCurrentAppActivationProjectionObservationTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "showInCommandTabToggleIsOn=Optional(true)"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "hiddenCountExists=false"
            )
        )
    }

    private func settingsCurrentAppActivationProjectionSnapshot(
        appState: XCUIApplication.State = .runningForeground,
        settingsContentExists: Bool = true,
        toggleExists: Bool = true,
        toggleHittable: Bool = true,
        toggleIsOn: Bool? = false,
        toggleValue: String? = "0",
        hiddenCountExists: Bool = true,
        hiddenCountValue: String? = "已隐藏 1 个应用"
    ) -> FlowTabUITestSettingsCurrentAppActivationProjectionSnapshot {
        FlowTabUITestSettingsCurrentAppActivationProjectionSnapshot(
            appState: appState,
            settingsContentExists: settingsContentExists,
            showInCommandTabToggleExists: toggleExists,
            showInCommandTabToggleHittable: toggleHittable,
            showInCommandTabToggleIsOn: toggleIsOn,
            showInCommandTabToggleValue: toggleValue,
            hiddenCountExists: hiddenCountExists,
            hiddenCountValue: hiddenCountValue
        )
    }
}
