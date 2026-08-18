import Foundation
import XCTest

private enum StatusItemWindowReopenObservationTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let delayedReadbacks = 20
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testStatusItemWindowReopenPolicyUsesNamedProjectionWatchdog() {
        XCTAssertEqual(
            StatusItemWindowReopenUITestPolicy.projectionWatchdog,
            8
        )
    }

    func testStatusItemWindowReopenObserverAcceptsInitiallyOpenProjection() {
        let owner = StatusItemWindowReopenObservationOwner(
            observationRegistration: nil,
            readback: {
                self.statusItemWindowReopenSnapshot(
                    homeWindowExists: true,
                    logsContentExists: true
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

    func testStatusItemWindowReopenObserverGatesDelayedEvidenceAndCancels() {
        var acceptsEvidence = false
        var snapshot = statusItemWindowReopenSnapshot(
            homeWindowExists: false,
            logsContentExists: false
        )
        var readback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner = StatusItemWindowReopenObservationOwner(
            acceptsEvidence: {
                acceptsEvidence
            },
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
            owner.latestEvidence?.value.isClosedProjection
                == true
        )
        XCTAssertNil(owner.resolvedEvidence)

        for index in
            0..<StatusItemWindowReopenObservationTestPolicy
                .delayedReadbacks
        {
            snapshot = statusItemWindowReopenSnapshot(
                homeWindowExists: index.isMultiple(of: 2),
                logsContentExists: index.isMultiple(of: 2) == false
            )
            readback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }

        snapshot = statusItemWindowReopenSnapshot(
            homeWindowExists: true,
            logsContentExists: true
        )
        readback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "acceptanceEnabled=false"
            )
        )

        acceptsEvidence = true
        readback?(.triggerReadback)
        readback?(.scheduledReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .triggerReadback
        )
        XCTAssertEqual(cancellationCount, 1)
    }

    func testStatusItemWindowReopenObserverRejectsStaleGenerationsUnderPressure() {
        for _ in
            0..<StatusItemWindowReopenObservationTestPolicy
                .pressureIterations
        {
            var snapshot = statusItemWindowReopenSnapshot(
                homeWindowExists: false,
                logsContentExists: false
            )
            var callbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            let owner = StatusItemWindowReopenObservationOwner(
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

            snapshot = statusItemWindowReopenSnapshot(
                homeWindowExists: true,
                logsContentExists: true
            )
            staleReadback(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
            callbacks[1](.scheduledReadback)
            callbacks[1](.triggerReadback)
            XCTAssertEqual(owner.resolvedEvidence?.generation, 2)
            owner.cancel()
        }
    }

    func testStatusItemWindowReopenWatchdogReportsFinalEvidence() {
        let owner = StatusItemWindowReopenObservationOwner(
            observationRegistration: nil,
            readback: {
                self.statusItemWindowReopenSnapshot(
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
                    StatusItemWindowReopenObservationTestPolicy
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
                "expected=openLogs"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "acceptanceEnabled=true"
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

    private func statusItemWindowReopenSnapshot(
        applicationState: String = "runningForeground",
        applicationIsRunning: Bool = true,
        homeWindowExists: Bool,
        logsContentExists: Bool
    ) -> StatusItemWindowProjectionSnapshot {
        StatusItemWindowProjectionSnapshot(
            applicationState: applicationState,
            applicationIsRunning: applicationIsRunning,
            homeWindowExists: homeWindowExists,
            logsContentExists: logsContentExists
        )
    }
}
