import Foundation
import XCTest

private enum FlowTabUITestLogsDiagnosticSessionTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testLogsDiagnosticSessionExpectationRequiresAtomicProjection() {
        XCTAssertEqual(
            FlowTabUITestLogsDiagnosticSessionObservationPolicy
                .projectionWatchdog,
            5
        )
        XCTAssertTrue(
            FlowTabUITestLogsDiagnosticSessionObservationPolicy
                .projectionWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestLogsDiagnosticSessionObservationPolicy
                .projectionWatchdog,
            0
        )

        let activeExpectation =
            FlowTabUITestLogsDiagnosticSessionExpectation(
                isActive: true
            )
        let inactiveExpectation =
            FlowTabUITestLogsDiagnosticSessionExpectation(
                isActive: false
            )
        let active = logsDiagnosticSessionTestSnapshot(
            isActive: true
        )
        let inactive = logsDiagnosticSessionTestSnapshot(
            isActive: false
        )

        XCTAssertTrue(activeExpectation.isSatisfied(by: active))
        XCTAssertTrue(inactiveExpectation.isSatisfied(by: inactive))
        XCTAssertFalse(activeExpectation.isSatisfied(by: inactive))
        XCTAssertFalse(inactiveExpectation.isSatisfied(by: active))
        XCTAssertFalse(
            activeExpectation.isSatisfied(
                by: logsDiagnosticSessionTestSnapshot(
                    isActive: true,
                    applicationState: .runningBackground
                )
            )
        )
        XCTAssertFalse(
            activeExpectation.isSatisfied(
                by: logsDiagnosticSessionTestSnapshot(
                    isActive: true,
                    logsContentExists: false
                )
            )
        )
        XCTAssertFalse(
            activeExpectation.isSatisfied(
                by: logsDiagnosticSessionTestSnapshot(
                    isActive: true,
                    toggleExists: false
                )
            )
        )
        XCTAssertFalse(
            activeExpectation.isSatisfied(
                by: logsDiagnosticSessionTestSnapshot(
                    isActive: true,
                    toggleIsOn: false
                )
            )
        )
        XCTAssertFalse(
            activeExpectation.isSatisfied(
                by: logsDiagnosticSessionTestSnapshot(
                    isActive: true,
                    statusExists: false
                )
            )
        )
        XCTAssertFalse(
            activeExpectation.isSatisfied(
                by: logsDiagnosticSessionTestSnapshot(
                    isActive: true,
                    statusLabel: "  "
                )
            )
        )
    }

    func testLogsDiagnosticSessionObserverRequiresPostTriggerEvidence() {
        let matching = logsDiagnosticSessionTestSnapshot(
            isActive: true
        )
        var snapshot = matching
        var triggerDidComplete = false
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestLogsDiagnosticSessionObservationOwner(
                expectation:
                    FlowTabUITestLogsDiagnosticSessionExpectation(
                        isActive: true
                    ),
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                acceptsResolution: { triggerDidComplete },
                readback: { snapshot }
            )
        owner.start()

        XCTAssertNil(owner.resolvedEvidence)
        triggerDidComplete = true
        snapshot = logsDiagnosticSessionTestSnapshot(
            isActive: true,
            statusExists: false
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = matching
        owner.requestReadback(source: .triggerReadback)
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestLogsDiagnosticSessionTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .triggerReadback)
        XCTAssertEqual(evidence?.value, matching)
        XCTAssertEqual(cancellationCount, 1)
        owner.cancel()
    }

    func testLogsDiagnosticSessionObserverLifecycleUnderPressure() {
        for iteration in
            0..<FlowTabUITestLogsDiagnosticSessionTestPolicy
                .pressureIterations
        {
            let isActive = iteration.isMultiple(of: 2)
            let resolvesInitially = iteration.isMultiple(of: 3)
            let matching = logsDiagnosticSessionTestSnapshot(
                isActive: isActive
            )
            var snapshot = resolvesInitially
                ? matching
                : logsDiagnosticSessionTestSnapshot(
                    isActive: !isActive
                )
            var scheduledReadback:
                ((FlowTabUITestConditionObservationSource) -> Void)?
            var cancellationCount = 0
            var readbackCount = 0
            let owner =
                FlowTabUITestLogsDiagnosticSessionObservationOwner(
                    expectation:
                        FlowTabUITestLogsDiagnosticSessionExpectation(
                            isActive: isActive
                        ),
                    observationRegistration: { callback in
                        scheduledReadback = callback
                        return FlowTabUITestObservationCancellation {
                            cancellationCount += 1
                        }
                    },
                    readback: {
                        readbackCount += 1
                        return snapshot
                    }
                )
            owner.start()

            if !resolvesInitially {
                XCTAssertNil(owner.resolvedEvidence)
                snapshot = matching
                scheduledReadback?(.scheduledReadback)
            }
            let evidence = owner.waitForResolution(
                timeout:
                    FlowTabUITestLogsDiagnosticSessionTestPolicy
                        .watchdog
            )
            let resolvedReadbackCount = readbackCount
            scheduledReadback?(.scheduledReadback)

            XCTAssertEqual(
                evidence?.value,
                matching,
                "iteration=\(iteration)"
            )
            XCTAssertEqual(readbackCount, resolvedReadbackCount)
            XCTAssertEqual(cancellationCount, 1)
            owner.cancel()
        }

        var cancelledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancelledReadbackCount = 0
        let cancelledOwner =
            FlowTabUITestLogsDiagnosticSessionObservationOwner(
                expectation:
                    FlowTabUITestLogsDiagnosticSessionExpectation(
                        isActive: true
                    ),
                observationRegistration: { callback in
                    cancelledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    cancelledReadbackCount += 1
                    return self.logsDiagnosticSessionTestSnapshot(
                        isActive: false
                    )
                }
            )
        cancelledOwner.start()
        cancelledOwner.cancel()
        cancelledReadback?(.scheduledReadback)
        XCTAssertEqual(cancelledReadbackCount, 1)
    }

    func testLogsDiagnosticSessionObserverWatchdogReportsLastEvidence() {
        let owner =
            FlowTabUITestLogsDiagnosticSessionObservationOwner(
                expectation:
                    FlowTabUITestLogsDiagnosticSessionExpectation(
                        isActive: true
                    ),
                observationRegistration: nil,
                readback: {
                    self.logsDiagnosticSessionTestSnapshot(
                        isActive: false
                    )
                }
            )
        owner.start()

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestLogsDiagnosticSessionTestPolicy
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
                "toggleIsOn=false"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "statusExists=false"
            )
        )
        owner.cancel()
    }

    private func logsDiagnosticSessionTestSnapshot(
        isActive: Bool,
        applicationState: XCUIApplication.State = .runningForeground,
        logsContentExists: Bool = true,
        toggleExists: Bool = true,
        toggleIsOn: Bool? = nil,
        statusExists: Bool? = nil,
        statusLabel: String? = nil
    ) -> FlowTabUITestLogsDiagnosticSessionSnapshot {
        FlowTabUITestLogsDiagnosticSessionSnapshot(
            applicationState: applicationState,
            logsContentExists: logsContentExists,
            toggleExists: toggleExists,
            toggleIsOn: toggleIsOn ?? isActive,
            statusExists: statusExists ?? isActive,
            statusLabel: statusLabel
                ?? (isActive ? "Detailed diagnostics active" : "")
        )
    }
}
