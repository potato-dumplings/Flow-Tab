import Foundation
import XCTest

private enum FlowTabUITestSidebarTabProjectionTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testSidebarTabProjectionExpectationRequiresExactTarget() {
        for target in FlowTabUITestSidebarTabProjectionTarget.allCases {
            let expectation =
                FlowTabUITestSidebarTabProjectionExpectation(
                    target: target
                )
            let matching = sidebarTabProjectionTestSnapshot(
                visibleTargets: [target]
            )

            XCTAssertTrue(
                expectation.isSatisfied(by: matching),
                "target=\(target.rawValue)"
            )
            XCTAssertFalse(
                expectation.isSatisfied(
                    by: sidebarTabProjectionTestSnapshot(
                        applicationState: .runningBackground,
                        visibleTargets: [target]
                    )
                ),
                "target=\(target.rawValue)"
            )
            XCTAssertFalse(
                expectation.isSatisfied(
                    by: sidebarTabProjectionTestSnapshot(
                        visibleTargets: []
                    )
                ),
                "target=\(target.rawValue)"
            )
            for otherTarget in
                FlowTabUITestSidebarTabProjectionTarget.allCases
                where otherTarget != target
            {
                XCTAssertFalse(
                    expectation.isSatisfied(
                        by: sidebarTabProjectionTestSnapshot(
                            visibleTargets: [target, otherTarget]
                        )
                    ),
                    "target=\(target.rawValue) "
                        + "otherTarget=\(otherTarget.rawValue)"
                )
            }
        }
    }

    func testSidebarTabProjectionObserverUsesPreNavigationEvidence() {
        let target = FlowTabUITestSidebarTabProjectionTarget.logs
        let matching = sidebarTabProjectionTestSnapshot(
            visibleTargets: [target]
        )
        let preNavigation = sidebarTabProjectionTestSnapshot(
            visibleTargets: [.home]
        )
        var snapshot = preNavigation
        var triggerDidComplete = false
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestSidebarTabProjectionObservationOwner(
                expectation: .init(target: target),
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
                FlowTabUITestSidebarTabProjectionTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .triggerReadback)
        XCTAssertEqual(evidence?.value, matching)
        XCTAssertEqual(cancellationCount, 1)
        owner.cancel()
    }

    func testSidebarTabProjectionObserverSupportsInitiallyMatchingState() {
        let target = FlowTabUITestSidebarTabProjectionTarget.home
        let matching = sidebarTabProjectionTestSnapshot(
            visibleTargets: [target]
        )
        var triggerDidComplete = false
        let owner =
            FlowTabUITestSidebarTabProjectionObservationOwner(
                expectation: .init(target: target),
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
                FlowTabUITestSidebarTabProjectionTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .triggerReadback)
        XCTAssertEqual(evidence?.value, matching)
        owner.cancel()
    }

    func testSidebarTabProjectionObserverUsesDelayedScheduledEvidence() {
        let target = FlowTabUITestSidebarTabProjectionTarget.logs
        let matching = sidebarTabProjectionTestSnapshot(
            visibleTargets: [target]
        )
        var snapshot = sidebarTabProjectionTestSnapshot(
            visibleTargets: [.home]
        )
        var triggerDidComplete = false
        var downstreamReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var downstreamRegistrationCount = 0
        var downstreamCancellationCount = 0
        let deferredReadbacks =
            FlowTabUITestDeferredConditionReadbackRegistration(
                downstreamRegistration: { callback in
                    downstreamRegistrationCount += 1
                    downstreamReadback = callback
                    return FlowTabUITestObservationCancellation {
                        downstreamCancellationCount += 1
                    }
                }
            )
        let owner =
            FlowTabUITestSidebarTabProjectionObservationOwner(
                expectation: .init(target: target),
                observationRegistration: { callback in
                    deferredReadbacks.register(callback)
                },
                acceptsResolution: { triggerDidComplete },
                readback: { snapshot }
            )
        owner.start()

        XCTAssertEqual(downstreamRegistrationCount, 0)
        triggerDidComplete = true
        owner.requestReadback(source: .triggerReadback)
        XCTAssertNil(owner.resolvedEvidence)

        deferredReadbacks.activate()
        deferredReadbacks.activate()
        XCTAssertEqual(downstreamRegistrationCount, 1)
        snapshot = matching
        downstreamReadback?(.scheduledReadback)
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestSidebarTabProjectionTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .scheduledReadback)
        XCTAssertEqual(evidence?.value, matching)
        XCTAssertEqual(downstreamCancellationCount, 1)
        owner.cancel()
        deferredReadbacks.cancel()
        XCTAssertEqual(downstreamCancellationCount, 1)
    }

    func testSidebarTabProjectionObserverLifecycleUnderPressure() {
        let targets = FlowTabUITestSidebarTabProjectionTarget.allCases

        for iteration in
            0..<FlowTabUITestSidebarTabProjectionTestPolicy
                .pressureIterations
        {
            let target = targets[iteration % targets.count]
            let matching = sidebarTabProjectionTestSnapshot(
                visibleTargets: [target]
            )
            let initialTarget = targets[(iteration + 1) % targets.count]
            var snapshot = sidebarTabProjectionTestSnapshot(
                visibleTargets: [initialTarget]
            )
            var triggerDidComplete = false
            var scheduledReadback:
                ((FlowTabUITestConditionObservationSource) -> Void)?
            var cancellationCount = 0
            var readbackCount = 0
            let owner =
                FlowTabUITestSidebarTabProjectionObservationOwner(
                    expectation: .init(target: target),
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
            snapshot = matching
            scheduledReadback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
            triggerDidComplete = true
            owner.requestReadback(source: .triggerReadback)
            let evidence = owner.waitForResolution(
                timeout:
                    FlowTabUITestSidebarTabProjectionTestPolicy
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
            FlowTabUITestSidebarTabProjectionObservationOwner(
                expectation: .init(target: .settings),
                observationRegistration: { callback in
                    cancelledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    cancelledReadbackCount += 1
                    return self.sidebarTabProjectionTestSnapshot(
                        visibleTargets: [.home]
                    )
                }
            )
        cancelledOwner.start()
        cancelledOwner.cancel()
        cancelledReadback?(.scheduledReadback)
        XCTAssertEqual(cancelledReadbackCount, 1)
    }

    func testSidebarTabProjectionObserverWatchdogReportsLastEvidence() {
        let owner =
            FlowTabUITestSidebarTabProjectionObservationOwner(
                expectation: .init(target: .settings),
                observationRegistration: nil,
                readback: {
                    self.sidebarTabProjectionTestSnapshot(
                        visibleTargets: [.home]
                    )
                }
            )
        owner.start()

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSidebarTabProjectionTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("target=settings")
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("visibleTargets=[home]")
        )
        owner.cancel()
    }

    private func sidebarTabProjectionTestSnapshot(
        applicationState: XCUIApplication.State = .runningForeground,
        visibleTargets:
            Set<FlowTabUITestSidebarTabProjectionTarget>
    ) -> FlowTabUITestSidebarTabProjectionSnapshot {
        FlowTabUITestSidebarTabProjectionSnapshot(
            applicationState: applicationState,
            homeContentExists: visibleTargets.contains(.home),
            logsContentExists: visibleTargets.contains(.logs),
            settingsContentExists: visibleTargets.contains(.settings)
        )
    }
}
