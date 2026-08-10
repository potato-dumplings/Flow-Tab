import Foundation
import XCTest

private enum
    FlowTabUITestSettingsInitialAppearanceProjectionObservationTestPolicy
{
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testSettingsInitialAppearanceProjectionPolicyUsesNamedWatchdog() {
        let watchdog =
            FlowTabUITestSettingsInitialAppearanceProjectionPolicy
                .projectionWatchdog
        XCTAssertEqual(watchdog, 5)
        XCTAssertTrue(watchdog.isFinite)
        XCTAssertGreaterThan(watchdog, 0)
    }

    func testSettingsInitialAppearanceProjectionRequiresCompleteSnapshot() {
        XCTAssertTrue(
            settingsInitialAppearanceProjectionSnapshot().isExactProjection
        )
        XCTAssertFalse(
            settingsInitialAppearanceProjectionSnapshot(
                appState: .runningBackground
            ).isExactProjection
        )
        XCTAssertFalse(
            settingsInitialAppearanceProjectionSnapshot(
                settingsContentExists: false
            ).isExactProjection
        )
        XCTAssertFalse(
            settingsInitialAppearanceProjectionSnapshot(
                appearanceTitleExists: false,
                appearanceTitleValue: nil
            ).isExactProjection
        )
    }

    func testSettingsInitialAppearanceProjectionAcceptsInitialExactEvidence() {
        let owner =
            FlowTabUITestSettingsInitialAppearanceProjectionObservationOwner(
                observationRegistration: nil,
                readback: {
                    self.settingsInitialAppearanceProjectionSnapshot()
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(owner.resolvedEvidence?.source, .initialReadback)
    }

    func testSettingsInitialAppearanceProjectionRequiresPostTriggerEvidence() {
        var acceptsEvidence = false
        var cancellationCount = 0
        let owner =
            FlowTabUITestSettingsInitialAppearanceProjectionObservationOwner(
                acceptsEvidence: { acceptsEvidence },
                observationRegistration: { _ in
                    FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    self.settingsInitialAppearanceProjectionSnapshot()
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

    func testSettingsInitialAppearanceProjectionUsesLaterEvidenceAndCancels() {
        var snapshot = settingsInitialAppearanceProjectionSnapshot(
            settingsContentExists: false,
            appearanceTitleExists: false,
            appearanceTitleValue: nil
        )
        var readback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestSettingsInitialAppearanceProjectionObservationOwner(
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
            snapshot = settingsInitialAppearanceProjectionSnapshot(
                appearanceTitleExists: false,
                appearanceTitleValue: nil
            )
            readback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }

        snapshot = settingsInitialAppearanceProjectionSnapshot()
        readback?(.scheduledReadback)
        readback?(.triggerReadback)

        XCTAssertEqual(owner.resolvedEvidence?.source, .scheduledReadback)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSettingsInitialAppearanceProjectionRejectsStaleGenerationsUnderPressure() {
        for _ in
            0..<FlowTabUITestSettingsInitialAppearanceProjectionObservationTestPolicy
                .pressureIterations
        {
            var snapshot = settingsInitialAppearanceProjectionSnapshot(
                appearanceTitleExists: false,
                appearanceTitleValue: nil
            )
            var readbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            let owner =
                FlowTabUITestSettingsInitialAppearanceProjectionObservationOwner(
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

            snapshot = settingsInitialAppearanceProjectionSnapshot()
            staleReadback(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
            readbacks[1](.scheduledReadback)
            readbacks[1](.triggerReadback)
            XCTAssertEqual(owner.resolvedEvidence?.generation, 2)
            owner.cancel()
        }
    }

    func testSettingsInitialAppearanceProjectionWatchdogReportsFinalEvidence() {
        let owner =
            FlowTabUITestSettingsInitialAppearanceProjectionObservationOwner(
                observationRegistration: nil,
                readback: {
                    self.settingsInitialAppearanceProjectionSnapshot(
                        appearanceTitleExists: false,
                        appearanceTitleValue: nil
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSettingsInitialAppearanceProjectionObservationTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("source=watchdogReadback")
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("appearanceTitleExists=false")
        )
    }

    private func settingsInitialAppearanceProjectionSnapshot(
        appState: XCUIApplication.State = .runningForeground,
        settingsContentExists: Bool = true,
        appearanceTitleExists: Bool = true,
        appearanceTitleValue: String? = "外观"
    ) -> FlowTabUITestSettingsInitialAppearanceProjectionSnapshot {
        FlowTabUITestSettingsInitialAppearanceProjectionSnapshot(
            appState: appState,
            settingsContentExists: settingsContentExists,
            appearanceTitleExists: appearanceTitleExists,
            appearanceTitleValue: appearanceTitleValue
        )
    }
}
