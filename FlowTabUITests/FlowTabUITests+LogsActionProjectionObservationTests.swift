import Foundation
import XCTest

private enum FlowTabUITestLogsActionProjectionTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testLogsActionProjectionExpectationRequiresAtomicControls() {
        let expectation =
            FlowTabUITestLogsActionProjectionExpectation()
        let matching = logsActionProjectionTestSnapshot()

        XCTAssertTrue(expectation.isSatisfied(by: matching))
        XCTAssertFalse(
            expectation.isSatisfied(
                by: logsActionProjectionTestSnapshot(
                    applicationState: .runningBackground
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: logsActionProjectionTestSnapshot(
                    logsContentExists: false
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: logsActionProjectionTestSnapshot(
                    openDirectoryButtonExists: false
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: logsActionProjectionTestSnapshot(
                    openDirectoryButtonIsHittable: false
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: logsActionProjectionTestSnapshot(
                    clearButtonExists: false
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: logsActionProjectionTestSnapshot(
                    clearButtonIsHittable: false
                )
            )
        )
    }

    func testLogsActionProjectionObserverUsesPreNavigationEvidence() {
        let matching = logsActionProjectionTestSnapshot()
        let preNavigation = logsActionProjectionTestSnapshot(
            logsContentExists: false,
            openDirectoryButtonExists: false,
            openDirectoryButtonIsHittable: false,
            clearButtonExists: false,
            clearButtonIsHittable: false
        )
        var snapshot = preNavigation
        var triggerDidComplete = false
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestLogsActionProjectionObservationOwner(
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

        XCTAssertEqual(owner.latestEvidence?.source, .initialReadback)
        XCTAssertEqual(owner.latestEvidence?.value, preNavigation)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = matching
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        triggerDidComplete = true
        owner.requestReadback(source: .triggerReadback)
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestLogsActionProjectionTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .triggerReadback)
        XCTAssertEqual(evidence?.value, matching)
        XCTAssertEqual(cancellationCount, 1)
        owner.cancel()
    }

    func testLogsActionProjectionObserverSupportsInitiallyMatchingState() {
        let matching = logsActionProjectionTestSnapshot()
        var triggerDidComplete = false
        let owner =
            FlowTabUITestLogsActionProjectionObservationOwner(
                observationRegistration: nil,
                acceptsResolution: { triggerDidComplete },
                readback: { matching }
            )
        owner.start()

        XCTAssertEqual(owner.latestEvidence?.source, .initialReadback)
        XCTAssertEqual(owner.latestEvidence?.value, matching)
        XCTAssertNil(owner.resolvedEvidence)

        triggerDidComplete = true
        owner.requestReadback(source: .triggerReadback)
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestLogsActionProjectionTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .triggerReadback)
        XCTAssertEqual(evidence?.value, matching)
        owner.cancel()
    }

    func testLogsActionProjectionObserverLifecycleUnderPressure() {
        let matching = logsActionProjectionTestSnapshot()

        for iteration in
            0..<FlowTabUITestLogsActionProjectionTestPolicy
                .pressureIterations
        {
            var triggerDidComplete = false
            var snapshot = iteration.isMultiple(of: 2)
                ? matching
                : logsActionProjectionTestSnapshot(
                    clearButtonIsHittable: false
                )
            var scheduledReadback:
                ((FlowTabUITestConditionObservationSource) -> Void)?
            var cancellationCount = 0
            var readbackCount = 0
            let owner =
                FlowTabUITestLogsActionProjectionObservationOwner(
                    observationRegistration: { callback in
                        scheduledReadback = callback
                        return FlowTabUITestObservationCancellation {
                            cancellationCount += 1
                        }
                    },
                    acceptsResolution: { triggerDidComplete },
                    readback: {
                        readbackCount += 1
                        return snapshot
                    }
                )
            owner.start()

            XCTAssertNil(
                owner.resolvedEvidence,
                "iteration=\(iteration)"
            )
            triggerDidComplete = true
            snapshot = matching
            scheduledReadback?(.scheduledReadback)
            let evidence = owner.waitForResolution(
                timeout:
                    FlowTabUITestLogsActionProjectionTestPolicy
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
            FlowTabUITestLogsActionProjectionObservationOwner(
                observationRegistration: { callback in
                    cancelledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    cancelledReadbackCount += 1
                    return self.logsActionProjectionTestSnapshot(
                        clearButtonIsHittable: false
                    )
                }
            )
        cancelledOwner.start()
        cancelledOwner.cancel()
        cancelledReadback?(.scheduledReadback)
        XCTAssertEqual(cancelledReadbackCount, 1)
    }

    func testLogsActionProjectionObserverWatchdogReportsLastEvidence() {
        let owner =
            FlowTabUITestLogsActionProjectionObservationOwner(
                observationRegistration: nil,
                readback: {
                    self.logsActionProjectionTestSnapshot(
                        clearButtonIsHittable: false
                    )
                }
            )
        owner.start()

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestLogsActionProjectionTestPolicy
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
                "clearButtonIsHittable=false"
            )
        )
        owner.cancel()
    }

    private func logsActionProjectionTestSnapshot(
        applicationState: XCUIApplication.State = .runningForeground,
        logsContentExists: Bool = true,
        openDirectoryButtonExists: Bool = true,
        openDirectoryButtonIsHittable: Bool = true,
        clearButtonExists: Bool = true,
        clearButtonIsHittable: Bool = true
    ) -> FlowTabUITestLogsActionProjectionSnapshot {
        FlowTabUITestLogsActionProjectionSnapshot(
            applicationState: applicationState,
            logsContentExists: logsContentExists,
            openDirectoryButtonExists: openDirectoryButtonExists,
            openDirectoryButtonIsHittable:
                openDirectoryButtonIsHittable,
            clearButtonExists: clearButtonExists,
            clearButtonIsHittable: clearButtonIsHittable
        )
    }
}
