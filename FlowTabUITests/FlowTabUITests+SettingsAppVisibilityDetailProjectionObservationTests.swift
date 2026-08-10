import Foundation
import XCTest

private enum FlowTabUITestSettingsAppVisibilityDetailProjectionTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
    static let rowIdentifier =
        "flowtab.settings.app-visibility.app.com-flowtab-mock-mail.id-a4181b7a"
    static let identifierPrefix =
        "flowtab.settings.app-visibility.detail.com-flowtab-mock-mail.id-a4181b7a.generation."
    static let baselineIdentifier =
        "flowtab.settings.app-visibility.detail.com-flowtab-mock-browser.id-9ee00827.generation.3"
    static let projectedIdentifier = "\(identifierPrefix)4"
}

extension FlowTabUITests {
    func testSettingsAppVisibilityDetailProjectionPolicyPreservesBound() {
        XCTAssertEqual(
            FlowTabUITestSettingsAppVisibilityDetailProjectionPolicy.watchdog,
            6
        )
        XCTAssertTrue(
            FlowTabUITestSettingsAppVisibilityDetailProjectionPolicy
                .watchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSettingsAppVisibilityDetailProjectionPolicy.watchdog,
            0
        )
        XCTAssertEqual(
            settingsAppVisibilityDetailProjectionIdentifierPrefix(
                forRowIdentifier:
                    FlowTabUITestSettingsAppVisibilityDetailProjectionTestPolicy
                        .rowIdentifier
            ),
            FlowTabUITestSettingsAppVisibilityDetailProjectionTestPolicy
                .identifierPrefix
        )
        XCTAssertNil(
            settingsAppVisibilityDetailProjectionIdentifierPrefix(
                forRowIdentifier: "flowtab.settings.invalid-row"
            )
        )
    }

    func testSettingsAppVisibilityDetailProjectionRequiresExactEvidence() {
        let expectation = settingsAppVisibilityDetailProjectionTestExpectation()
        let matching = settingsAppVisibilityDetailProjectionTestSnapshot()

        XCTAssertTrue(expectation.isSatisfied(by: matching))
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityDetailProjectionTestSnapshot(
                    applicationState: .runningBackground
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityDetailProjectionTestSnapshot(
                    managerExists: false
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityDetailProjectionTestSnapshot(
                    targetRowExists: false
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityDetailProjectionTestSnapshot(
                    targetRowHittable: false
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityDetailProjectionTestSnapshot(
                    projectionIdentifier:
                        FlowTabUITestSettingsAppVisibilityDetailProjectionTestPolicy
                            .baselineIdentifier
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityDetailProjectionTestSnapshot(
                    projectionIdentifier: nil
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityDetailProjectionTestSnapshot(
                    showToggleExists: false
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityDetailProjectionTestSnapshot(
                    showToggleHittable: false
                )
            )
        )
    }

    func testSettingsAppVisibilityDetailProjectionAcceptsInitialTarget() {
        let matching = settingsAppVisibilityDetailProjectionTestSnapshot()
        let owner = settingsAppVisibilityDetailProjectionTestOwner {
            matching
        }
        owner.start()

        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestSettingsAppVisibilityDetailProjectionTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .initialReadback)
        XCTAssertEqual(evidence?.value, matching)
        owner.cancel()
    }

    func testSettingsAppVisibilityDetailProjectionGatesTrigger() {
        let matching = settingsAppVisibilityDetailProjectionTestSnapshot()
        var triggerDidComplete = false
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestSettingsAppVisibilityDetailProjectionObservationOwner(
                expectation:
                    settingsAppVisibilityDetailProjectionTestExpectation(),
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
                FlowTabUITestSettingsAppVisibilityDetailProjectionTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .triggerReadback)
        XCTAssertEqual(evidence?.value, matching)
        XCTAssertEqual(cancellationCount, 1)
        owner.cancel()
    }

    func testSettingsAppVisibilityDetailProjectionUsesDelayedEvidence() {
        var snapshot = settingsAppVisibilityDetailProjectionTestSnapshot(
            projectionIdentifier:
                FlowTabUITestSettingsAppVisibilityDetailProjectionTestPolicy
                    .baselineIdentifier,
            showToggleExists: false,
            showToggleHittable: false
        )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let owner =
            FlowTabUITestSettingsAppVisibilityDetailProjectionObservationOwner(
                expectation:
                    settingsAppVisibilityDetailProjectionTestExpectation(),
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )
        owner.start()

        snapshot = settingsAppVisibilityDetailProjectionTestSnapshot(
            showToggleExists: false,
            showToggleHittable: false
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = settingsAppVisibilityDetailProjectionTestSnapshot()
        scheduledReadback?(.scheduledReadback)
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestSettingsAppVisibilityDetailProjectionTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .scheduledReadback)
        XCTAssertEqual(evidence?.value, snapshot)
        owner.cancel()
    }

    func testSettingsAppVisibilityDetailProjectionLifecycleUnderPressure() {
        let matching = settingsAppVisibilityDetailProjectionTestSnapshot()

        for iteration in
            0..<FlowTabUITestSettingsAppVisibilityDetailProjectionTestPolicy
                .pressureIterations
        {
            var triggerDidComplete = false
            var snapshot = iteration.isMultiple(of: 2)
                ? matching
                : settingsAppVisibilityDetailProjectionTestSnapshot(
                    showToggleExists: false,
                    showToggleHittable: false
                )
            var scheduledReadback:
                ((FlowTabUITestConditionObservationSource) -> Void)?
            var readbackCount = 0
            var cancellationCount = 0
            let owner =
                FlowTabUITestSettingsAppVisibilityDetailProjectionObservationOwner(
                    expectation:
                        settingsAppVisibilityDetailProjectionTestExpectation(),
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
                    FlowTabUITestSettingsAppVisibilityDetailProjectionTestPolicy
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
            FlowTabUITestSettingsAppVisibilityDetailProjectionObservationOwner(
                expectation:
                    settingsAppVisibilityDetailProjectionTestExpectation(),
                observationRegistration: { callback in
                    cancelledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    cancelledReadbackCount += 1
                    return self.settingsAppVisibilityDetailProjectionTestSnapshot(
                        showToggleExists: false,
                        showToggleHittable: false
                    )
                }
            )
        cancelledOwner.start()
        cancelledOwner.cancel()
        cancelledReadback?(.scheduledReadback)
        XCTAssertEqual(cancelledReadbackCount, 1)
    }

    func testSettingsAppVisibilityDetailProjectionWatchdogReportsState() {
        let owner = settingsAppVisibilityDetailProjectionTestOwner {
            self.settingsAppVisibilityDetailProjectionTestSnapshot(
                projectionIdentifier:
                    FlowTabUITestSettingsAppVisibilityDetailProjectionTestPolicy
                        .baselineIdentifier,
                showToggleExists: false,
                showToggleHittable: false
            )
        }
        owner.start()

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSettingsAppVisibilityDetailProjectionTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("source=watchdogReadback")
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                FlowTabUITestSettingsAppVisibilityDetailProjectionTestPolicy
                    .identifierPrefix
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                FlowTabUITestSettingsAppVisibilityDetailProjectionTestPolicy
                    .baselineIdentifier
            )
        )
        XCTAssertTrue(owner.diagnosticSummary.contains("showToggleExists=false"))
        owner.cancel()
    }

    private func settingsAppVisibilityDetailProjectionTestOwner(
        readback: @escaping () ->
            FlowTabUITestSettingsAppVisibilityDetailProjectionSnapshot
    ) -> FlowTabUITestSettingsAppVisibilityDetailProjectionObservationOwner {
        .init(
            expectation:
                settingsAppVisibilityDetailProjectionTestExpectation(),
            observationRegistration: nil,
            readback: readback
        )
    }

    private func settingsAppVisibilityDetailProjectionTestExpectation()
        -> FlowTabUITestSettingsAppVisibilityDetailProjectionExpectation
    {
        .init(
            expectedProjectionIdentifierPrefix:
                FlowTabUITestSettingsAppVisibilityDetailProjectionTestPolicy
                    .identifierPrefix,
            baselineProjectionIdentifier:
                FlowTabUITestSettingsAppVisibilityDetailProjectionTestPolicy
                    .baselineIdentifier,
            targetRowIdentifier:
                FlowTabUITestSettingsAppVisibilityDetailProjectionTestPolicy
                    .rowIdentifier
        )
    }

    private func settingsAppVisibilityDetailProjectionTestSnapshot(
        applicationState: XCUIApplication.State = .runningForeground,
        managerExists: Bool = true,
        targetRowExists: Bool = true,
        targetRowHittable: Bool = true,
        projectionIdentifier: String? =
            FlowTabUITestSettingsAppVisibilityDetailProjectionTestPolicy
                .projectedIdentifier,
        showToggleExists: Bool = true,
        showToggleHittable: Bool = true
    ) -> FlowTabUITestSettingsAppVisibilityDetailProjectionSnapshot {
        .init(
            applicationState: applicationState,
            managerExists: managerExists,
            targetRowExists: targetRowExists,
            targetRowHittable: targetRowHittable,
            projectionIdentifier: projectionIdentifier,
            showToggleExists: showToggleExists,
            showToggleHittable: showToggleHittable
        )
    }
}
