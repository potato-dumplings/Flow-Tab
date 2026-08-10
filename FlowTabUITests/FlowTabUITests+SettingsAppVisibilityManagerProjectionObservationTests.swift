import Foundation
import XCTest

private enum
    FlowTabUITestSettingsAppVisibilityManagerProjectionTestPolicy
{
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testSettingsAppVisibilityManagerProjectionPolicyPreservesBound() {
        XCTAssertEqual(
            FlowTabUITestSettingsAppVisibilityManagerProjectionPolicy
                .watchdog,
            6
        )
        XCTAssertTrue(
            FlowTabUITestSettingsAppVisibilityManagerProjectionPolicy
                .watchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSettingsAppVisibilityManagerProjectionPolicy
                .watchdog,
            0
        )
    }

    func testSettingsAppVisibilityManagerProjectionRequiresExactPage() {
        let expectation =
            FlowTabUITestSettingsAppVisibilityManagerProjectionExpectation(
                expectedManagerTitle: "App Visibility"
            )
        let matching = settingsAppVisibilityManagerProjectionTestSnapshot()

        XCTAssertTrue(expectation.isSatisfied(by: matching))
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityManagerProjectionTestSnapshot(
                    applicationState: .runningBackground
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityManagerProjectionTestSnapshot(
                    settingsContentExists: false
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityManagerProjectionTestSnapshot(
                    manageActionExists: true,
                    manageActionIsHittable: true
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityManagerProjectionTestSnapshot(
                    managerExists: false
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityManagerProjectionTestSnapshot(
                    backActionExists: false
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityManagerProjectionTestSnapshot(
                    backActionIsHittable: false
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityManagerProjectionTestSnapshot(
                    expectedManagerTitleExists: false
                )
            )
        )
        XCTAssertTrue(
            FlowTabUITestSettingsAppVisibilityManagerProjectionExpectation()
                .isSatisfied(
                    by: settingsAppVisibilityManagerProjectionTestSnapshot(
                        expectedManagerTitleExists: false
                    )
                )
        )
    }

    func testSettingsAppVisibilityManagerProjectionAcceptsInitialTarget() {
        let matching = settingsAppVisibilityManagerProjectionTestSnapshot()
        let owner =
            FlowTabUITestSettingsAppVisibilityManagerProjectionObservationOwner(
                expectation: .init(
                    expectedManagerTitle: "App Visibility"
                ),
                observationRegistration: nil,
                readback: { matching }
            )
        owner.start()

        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestSettingsAppVisibilityManagerProjectionTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .initialReadback)
        XCTAssertEqual(evidence?.value, matching)
        owner.cancel()
    }

    func testSettingsAppVisibilityManagerProjectionGatesPreTriggerEvidence() {
        let matching = settingsAppVisibilityManagerProjectionTestSnapshot()
        var navigationAttemptDidComplete = false
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestSettingsAppVisibilityManagerProjectionObservationOwner(
                expectation: .init(),
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                acceptsResolution: {
                    navigationAttemptDidComplete
                },
                readback: { matching }
            )
        owner.start()

        XCTAssertEqual(owner.latestEvidence?.source, .initialReadback)
        XCTAssertNil(owner.resolvedEvidence)
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        navigationAttemptDidComplete = true
        owner.requestReadback(source: .triggerReadback)
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestSettingsAppVisibilityManagerProjectionTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .triggerReadback)
        XCTAssertEqual(evidence?.value, matching)
        XCTAssertEqual(cancellationCount, 1)
        owner.cancel()
    }

    func testSettingsAppVisibilityManagerProjectionUsesDelayedEvidence() {
        var snapshot = settingsAppVisibilityManagerProjectionTestSnapshot(
            manageActionExists: true,
            manageActionIsHittable: true,
            managerExists: false,
            backActionExists: false,
            backActionIsHittable: false,
            expectedManagerTitleExists: false
        )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let owner =
            FlowTabUITestSettingsAppVisibilityManagerProjectionObservationOwner(
                expectation: .init(
                    expectedManagerTitle: "App Visibility"
                ),
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )
        owner.start()

        XCTAssertNil(owner.resolvedEvidence)
        snapshot = settingsAppVisibilityManagerProjectionTestSnapshot()
        scheduledReadback?(.scheduledReadback)
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestSettingsAppVisibilityManagerProjectionTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .scheduledReadback)
        XCTAssertEqual(evidence?.value, snapshot)
        owner.cancel()
    }

    func testSettingsAppVisibilityManagerProjectionLifecycleUnderPressure() {
        let matching = settingsAppVisibilityManagerProjectionTestSnapshot()

        for iteration in
            0..<FlowTabUITestSettingsAppVisibilityManagerProjectionTestPolicy
                .pressureIterations
        {
            var navigationAttemptDidComplete = false
            var snapshot = iteration.isMultiple(of: 2)
                ? matching
                : settingsAppVisibilityManagerProjectionTestSnapshot(
                    manageActionExists: true,
                    manageActionIsHittable: true,
                    managerExists: false,
                    backActionExists: false,
                    backActionIsHittable: false
                )
            var scheduledReadback:
                ((FlowTabUITestConditionObservationSource) -> Void)?
            var readbackCount = 0
            var cancellationCount = 0
            let owner =
                FlowTabUITestSettingsAppVisibilityManagerProjectionObservationOwner(
                    expectation: .init(),
                    observationRegistration: { callback in
                        scheduledReadback = callback
                        return FlowTabUITestObservationCancellation {
                            cancellationCount += 1
                        }
                    },
                    acceptsResolution: {
                        navigationAttemptDidComplete
                    },
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
            navigationAttemptDidComplete = true
            snapshot = matching
            scheduledReadback?(.scheduledReadback)
            let evidence = owner.waitForResolution(
                timeout:
                    FlowTabUITestSettingsAppVisibilityManagerProjectionTestPolicy
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
            FlowTabUITestSettingsAppVisibilityManagerProjectionObservationOwner(
                expectation: .init(),
                observationRegistration: { callback in
                    cancelledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    cancelledReadbackCount += 1
                    return self
                        .settingsAppVisibilityManagerProjectionTestSnapshot(
                            managerExists: false
                        )
                }
            )
        cancelledOwner.start()
        cancelledOwner.cancel()
        cancelledReadback?(.scheduledReadback)
        XCTAssertEqual(cancelledReadbackCount, 1)
    }

    func testSettingsAppVisibilityManagerProjectionWatchdogReportsState() {
        let owner =
            FlowTabUITestSettingsAppVisibilityManagerProjectionObservationOwner(
                expectation: .init(
                    expectedManagerTitle: "App Visibility"
                ),
                observationRegistration: nil,
                readback: {
                    self.settingsAppVisibilityManagerProjectionTestSnapshot(
                        manageActionExists: true,
                        manageActionIsHittable: true,
                        managerExists: false,
                        backActionExists: false,
                        backActionIsHittable: false,
                        expectedManagerTitleExists: false
                    )
                }
            )
        owner.start()

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSettingsAppVisibilityManagerProjectionTestPolicy
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
                "expectedManagerTitle=Optional(\"App Visibility\")"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "manageActionExists=true"
            )
        )
        owner.cancel()
    }

    private func settingsAppVisibilityManagerProjectionTestSnapshot(
        applicationState: XCUIApplication.State = .runningForeground,
        settingsContentExists: Bool = true,
        manageActionExists: Bool = false,
        manageActionIsHittable: Bool = false,
        managerExists: Bool = true,
        backActionExists: Bool = true,
        backActionIsHittable: Bool = true,
        expectedManagerTitleExists: Bool = true
    ) -> FlowTabUITestSettingsAppVisibilityManagerProjectionSnapshot {
        FlowTabUITestSettingsAppVisibilityManagerProjectionSnapshot(
            applicationState: applicationState,
            settingsContentExists: settingsContentExists,
            manageActionExists: manageActionExists,
            manageActionIsHittable: manageActionIsHittable,
            managerExists: managerExists,
            backActionExists: backActionExists,
            backActionIsHittable: backActionIsHittable,
            expectedManagerTitleExists: expectedManagerTitleExists
        )
    }
}
