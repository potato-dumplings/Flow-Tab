import Foundation
import XCTest

private enum StatusItemWindowCloseObservationTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testStatusItemWindowClosePolicyUsesNamedProjectionWatchdog() {
        XCTAssertEqual(
            StatusItemWindowCloseUITestPolicy.projectionWatchdog,
            6
        )
        XCTAssertEqual(
            StatusItemWindowCloseUITestPolicy.homeWindowTitle,
            "FlowTab"
        )
    }

    func testStatusItemWindowCloseSnapshotRequiresExactPersistentStates() {
        let open = statusItemWindowCloseSnapshot(
            homeWindowExists: true,
            logsContentExists: true
        )
        XCTAssertTrue(open.isOpenLogsProjection)
        XCTAssertFalse(open.isClosedProjection)

        let closed = statusItemWindowCloseSnapshot(
            homeWindowExists: false,
            logsContentExists: false
        )
        XCTAssertFalse(closed.isOpenLogsProjection)
        XCTAssertTrue(closed.isClosedProjection)

        XCTAssertFalse(
            statusItemWindowCloseSnapshot(
                applicationIsRunning: false,
                homeWindowExists: false,
                logsContentExists: false
            ).isClosedProjection
        )
        XCTAssertFalse(
            statusItemWindowCloseSnapshot(
                homeWindowExists: true,
                logsContentExists: false
            ).isClosedProjection
        )
        XCTAssertFalse(
            statusItemWindowCloseSnapshot(
                homeWindowExists: false,
                logsContentExists: true
            ).isClosedProjection
        )
    }

    func testStatusItemWindowCloseObserverAcceptsInitiallyClosedProjection() {
        let owner = StatusItemWindowCloseObservationOwner(
            observationRegistration: nil,
            readback: {
                self.statusItemWindowCloseSnapshot(
                    homeWindowExists: false,
                    logsContentExists: false
                )
            }
        )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .initialReadback
        )
    }

    func testStatusItemWindowCloseObserverUsesLaterExactEvidenceAndCancels() {
        var snapshot = statusItemWindowCloseSnapshot(
            homeWindowExists: true,
            logsContentExists: true
        )
        var readback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner = StatusItemWindowCloseObservationOwner(
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

        XCTAssertTrue(
            owner.latestEvidence?.value.isOpenLogsProjection
                == true
        )
        XCTAssertNil(owner.resolvedEvidence)

        for _ in 0..<20 {
            snapshot = self.statusItemWindowCloseSnapshot(
                homeWindowExists: true,
                logsContentExists: false
            )
            readback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }

        snapshot = statusItemWindowCloseSnapshot(
            homeWindowExists: false,
            logsContentExists: false
        )
        readback?(.triggerReadback)
        readback?(.scheduledReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .triggerReadback
        )
        XCTAssertEqual(cancellationCount, 1)
    }

    func testStatusItemWindowCloseObserverRejectsStaleGenerationsUnderPressure() {
        for _ in
            0..<StatusItemWindowCloseObservationTestPolicy
                .pressureIterations
        {
            var snapshot = statusItemWindowCloseSnapshot(
                homeWindowExists: true,
                logsContentExists: true
            )
            var callbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            let owner = StatusItemWindowCloseObservationOwner(
                observationRegistration: { callback in
                    callbacks.append(callback)
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )
            owner.start()
            let staleReadback = callbacks[0]
            owner.cancel()
            owner.start()

            snapshot = statusItemWindowCloseSnapshot(
                homeWindowExists: false,
                logsContentExists: false
            )
            staleReadback(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
            callbacks[1](.scheduledReadback)
            callbacks[1](.triggerReadback)
            XCTAssertEqual(owner.resolvedEvidence?.generation, 2)
            owner.cancel()
        }
    }

    func testStatusItemWindowCloseWatchdogReportsFinalEvidence() {
        let owner = StatusItemWindowCloseObservationOwner(
            observationRegistration: nil,
            readback: {
                self.statusItemWindowCloseSnapshot(
                    homeWindowExists: true,
                    logsContentExists: false
                )
            }
        )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    StatusItemWindowCloseObservationTestPolicy
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
                "applicationState=runningForeground"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "homeWindowExists=true"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "logsContentExists=false"
            )
        )
    }

    private func statusItemWindowCloseSnapshot(
        applicationState: String = "runningForeground",
        applicationIsRunning: Bool = true,
        homeWindowExists: Bool,
        logsContentExists: Bool
    ) -> StatusItemWindowCloseSnapshot {
        StatusItemWindowCloseSnapshot(
            applicationState: applicationState,
            applicationIsRunning: applicationIsRunning,
            homeWindowExists: homeWindowExists,
            logsContentExists: logsContentExists
        )
    }
}
