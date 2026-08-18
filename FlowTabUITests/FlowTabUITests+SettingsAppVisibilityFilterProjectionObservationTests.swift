import Foundation
import XCTest

private enum FlowTabUITestSettingsAppVisibilityFilterProjectionTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
    static let identifierPrefix =
        "flowtab.settings.app-visibility.filter-projection."
    static let hiddenIdentifierPrefix = "\(identifierPrefix)hidden.generation."
    static let baselineIdentifier = "\(identifierPrefix)all.generation.0"
    static let projectedIdentifier = "\(hiddenIdentifierPrefix)1"
    static let targetRowIdentifier =
        "flowtab.settings.app-visibility.app.com-flowtab-mock-mail.id-a4181b7a"
}

extension FlowTabUITests {
    func testSettingsAppVisibilityFilterProjectionPolicyPreservesBound() {
        XCTAssertEqual(
            FlowTabUITestSettingsAppVisibilityFilterProjectionPolicy.watchdog,
            6
        )
        XCTAssertTrue(
            FlowTabUITestSettingsAppVisibilityFilterProjectionPolicy
                .watchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSettingsAppVisibilityFilterProjectionPolicy.watchdog,
            0
        )
    }

    func testSettingsAppVisibilityFilterProjectionRequiresExactEvidence() {
        let expectation = settingsAppVisibilityFilterProjectionTestExpectation()
        let matching = settingsAppVisibilityFilterProjectionTestSnapshot()

        XCTAssertTrue(expectation.isSatisfied(by: matching))
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityFilterProjectionTestSnapshot(
                    applicationState: .runningBackground
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityFilterProjectionTestSnapshot(
                    managerExists: false
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityFilterProjectionTestSnapshot(
                    hiddenActionExists: false
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityFilterProjectionTestSnapshot(
                    hiddenActionHittable: false
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityFilterProjectionTestSnapshot(
                    projectionIdentifier:
                        FlowTabUITestSettingsAppVisibilityFilterProjectionTestPolicy
                            .baselineIdentifier
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityFilterProjectionTestSnapshot(
                    projectionIdentifier:
                        "flowtab.settings.app-visibility.filter-projection.all.generation.1"
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityFilterProjectionTestSnapshot(
                    projectionIdentifier: nil
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityFilterProjectionTestSnapshot(
                    targetRowExists: false
                )
            )
        )
    }

    func testSettingsAppVisibilityFilterProjectionAcceptsInitialTarget() {
        let matching = settingsAppVisibilityFilterProjectionTestSnapshot()
        let owner = settingsAppVisibilityFilterProjectionTestOwner {
            matching
        }
        owner.start()

        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestSettingsAppVisibilityFilterProjectionTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .initialReadback)
        XCTAssertEqual(evidence?.value, matching)
        owner.cancel()
    }

    func testSettingsAppVisibilityFilterProjectionGatesTrigger() {
        let matching = settingsAppVisibilityFilterProjectionTestSnapshot()
        var triggerDidComplete = false
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestSettingsAppVisibilityFilterProjectionObservationOwner(
                expectation:
                    settingsAppVisibilityFilterProjectionTestExpectation(),
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                acceptsResolution: { triggerDidComplete },
                readback: { matching }
            )
        owner.start()

        XCTAssertNil(owner.resolvedEvidence)
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        triggerDidComplete = true
        owner.requestReadback(source: .triggerReadback)
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestSettingsAppVisibilityFilterProjectionTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .triggerReadback)
        XCTAssertEqual(evidence?.value, matching)
        XCTAssertEqual(cancellationCount, 1)
        owner.cancel()
    }

    func testSettingsAppVisibilityFilterProjectionUsesDelayedEvidence() {
        var snapshot = settingsAppVisibilityFilterProjectionTestSnapshot(
            projectionIdentifier:
                FlowTabUITestSettingsAppVisibilityFilterProjectionTestPolicy
                    .baselineIdentifier,
            targetRowExists: false
        )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let owner =
            FlowTabUITestSettingsAppVisibilityFilterProjectionObservationOwner(
                expectation:
                    settingsAppVisibilityFilterProjectionTestExpectation(),
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )
        owner.start()

        snapshot = settingsAppVisibilityFilterProjectionTestSnapshot(
            projectionIdentifier:
                FlowTabUITestSettingsAppVisibilityFilterProjectionTestPolicy
                    .projectedIdentifier,
            targetRowExists: false
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = settingsAppVisibilityFilterProjectionTestSnapshot()
        scheduledReadback?(.scheduledReadback)
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestSettingsAppVisibilityFilterProjectionTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .scheduledReadback)
        XCTAssertEqual(evidence?.value, snapshot)
        owner.cancel()
    }

    func testSettingsAppVisibilityFilterProjectionLifecycleUnderPressure() {
        let matching = settingsAppVisibilityFilterProjectionTestSnapshot()

        for iteration in
            0..<FlowTabUITestSettingsAppVisibilityFilterProjectionTestPolicy
                .pressureIterations
        {
            var triggerDidComplete = false
            var snapshot = iteration.isMultiple(of: 2)
                ? matching
                : settingsAppVisibilityFilterProjectionTestSnapshot(
                    targetRowExists: false
                )
            var scheduledReadback:
                ((FlowTabUITestConditionObservationSource) -> Void)?
            var readbackCount = 0
            var cancellationCount = 0
            let owner =
                FlowTabUITestSettingsAppVisibilityFilterProjectionObservationOwner(
                    expectation:
                        settingsAppVisibilityFilterProjectionTestExpectation(),
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

            XCTAssertNil(owner.resolvedEvidence, "iteration=\(iteration)")
            triggerDidComplete = true
            snapshot = matching
            scheduledReadback?(.scheduledReadback)
            let evidence = owner.waitForResolution(
                timeout:
                    FlowTabUITestSettingsAppVisibilityFilterProjectionTestPolicy
                        .watchdog
            )
            let resolvedReadbackCount = readbackCount
            scheduledReadback?(.scheduledReadback)

            XCTAssertEqual(evidence?.value, matching, "iteration=\(iteration)")
            XCTAssertEqual(readbackCount, resolvedReadbackCount)
            XCTAssertEqual(cancellationCount, 1)
            owner.cancel()
        }

        var cancelledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancelledReadbackCount = 0
        let cancelledOwner =
            FlowTabUITestSettingsAppVisibilityFilterProjectionObservationOwner(
                expectation:
                    settingsAppVisibilityFilterProjectionTestExpectation(),
                observationRegistration: { callback in
                    cancelledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    cancelledReadbackCount += 1
                    return self.settingsAppVisibilityFilterProjectionTestSnapshot(
                        targetRowExists: false
                    )
                }
            )
        cancelledOwner.start()
        cancelledOwner.cancel()
        cancelledReadback?(.scheduledReadback)
        XCTAssertEqual(cancelledReadbackCount, 1)
    }

    func testSettingsAppVisibilityFilterProjectionWatchdogReportsState() {
        let owner = settingsAppVisibilityFilterProjectionTestOwner {
            self.settingsAppVisibilityFilterProjectionTestSnapshot(
                projectionIdentifier:
                    FlowTabUITestSettingsAppVisibilityFilterProjectionTestPolicy
                        .baselineIdentifier,
                targetRowExists: false
            )
        }
        owner.start()

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSettingsAppVisibilityFilterProjectionTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("source=watchdogReadback")
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                FlowTabUITestSettingsAppVisibilityFilterProjectionTestPolicy
                    .hiddenIdentifierPrefix
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                FlowTabUITestSettingsAppVisibilityFilterProjectionTestPolicy
                    .baselineIdentifier
            )
        )
        XCTAssertTrue(owner.diagnosticSummary.contains("targetRowExists=false"))
        owner.cancel()
    }

    private func settingsAppVisibilityFilterProjectionTestOwner(
        readback: @escaping () ->
            FlowTabUITestSettingsAppVisibilityFilterProjectionSnapshot
    ) -> FlowTabUITestSettingsAppVisibilityFilterProjectionObservationOwner {
        .init(
            expectation:
                settingsAppVisibilityFilterProjectionTestExpectation(),
            observationRegistration: nil,
            readback: readback
        )
    }

    private func settingsAppVisibilityFilterProjectionTestExpectation()
        -> FlowTabUITestSettingsAppVisibilityFilterProjectionExpectation
    {
        .init(
            expectedProjectionIdentifierPrefix:
                FlowTabUITestSettingsAppVisibilityFilterProjectionTestPolicy
                    .hiddenIdentifierPrefix,
            baselineProjectionIdentifier:
                FlowTabUITestSettingsAppVisibilityFilterProjectionTestPolicy
                    .baselineIdentifier,
            targetRowIdentifier:
                FlowTabUITestSettingsAppVisibilityFilterProjectionTestPolicy
                    .targetRowIdentifier
        )
    }

    private func settingsAppVisibilityFilterProjectionTestSnapshot(
        applicationState: XCUIApplication.State = .runningForeground,
        managerExists: Bool = true,
        hiddenActionExists: Bool = true,
        hiddenActionHittable: Bool = true,
        projectionIdentifier: String? =
            FlowTabUITestSettingsAppVisibilityFilterProjectionTestPolicy
                .projectedIdentifier,
        targetRowExists: Bool = true
    ) -> FlowTabUITestSettingsAppVisibilityFilterProjectionSnapshot {
        .init(
            applicationState: applicationState,
            managerExists: managerExists,
            hiddenActionExists: hiddenActionExists,
            hiddenActionHittable: hiddenActionHittable,
            projectionIdentifier: projectionIdentifier,
            targetRowExists: targetRowExists
        )
    }
}
