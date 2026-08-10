import Foundation
import XCTest

private enum FlowTabUITestSettingsAppVisibilityQueryProjectionTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
    static let identifierPrefix =
        "flowtab.settings.app-visibility.list.query-generation."
    static let baselineIdentifier = "\(identifierPrefix)0"
    static let projectedIdentifier = "\(identifierPrefix)1"
    static let targetRowIdentifier =
        "flowtab.settings.app-visibility.app.com-flowtab-mock-mail.id-a4181b7a"
}

extension FlowTabUITests {
    func testSettingsAppVisibilityQueryProjectionPolicyPreservesBound() {
        XCTAssertEqual(
            FlowTabUITestSettingsAppVisibilityQueryProjectionPolicy.watchdog,
            6
        )
        XCTAssertTrue(
            FlowTabUITestSettingsAppVisibilityQueryProjectionPolicy
                .watchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSettingsAppVisibilityQueryProjectionPolicy.watchdog,
            0
        )
    }

    func testSettingsAppVisibilityQueryProjectionRequiresExactEvidence() {
        let expectation = settingsAppVisibilityQueryProjectionTestExpectation()
        let matching = settingsAppVisibilityQueryProjectionTestSnapshot()

        XCTAssertTrue(expectation.isSatisfied(by: matching))
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityQueryProjectionTestSnapshot(
                    applicationState: .runningBackground
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityQueryProjectionTestSnapshot(
                    managerExists: false
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityQueryProjectionTestSnapshot(
                    searchFieldExists: false
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityQueryProjectionTestSnapshot(
                    searchFieldValue: "ceshi"
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityQueryProjectionTestSnapshot(
                    projectionIdentifier:
                        FlowTabUITestSettingsAppVisibilityQueryProjectionTestPolicy
                            .baselineIdentifier
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityQueryProjectionTestSnapshot(
                    projectionIdentifier: "unrelated.1"
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityQueryProjectionTestSnapshot(
                    projectionIdentifier: nil
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityQueryProjectionTestSnapshot(
                    targetRowExists: false
                )
            )
        )
    }

    func testSettingsAppVisibilityQueryProjectionAcceptsInitialTarget() {
        let matching = settingsAppVisibilityQueryProjectionTestSnapshot()
        let owner = settingsAppVisibilityQueryProjectionTestOwner {
            matching
        }
        owner.start()

        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestSettingsAppVisibilityQueryProjectionTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .initialReadback)
        XCTAssertEqual(evidence?.value, matching)
        owner.cancel()
    }

    func testSettingsAppVisibilityQueryProjectionGatesTrigger() {
        let matching = settingsAppVisibilityQueryProjectionTestSnapshot()
        var triggerDidComplete = false
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestSettingsAppVisibilityQueryProjectionObservationOwner(
                expectation:
                    settingsAppVisibilityQueryProjectionTestExpectation(),
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
                FlowTabUITestSettingsAppVisibilityQueryProjectionTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .triggerReadback)
        XCTAssertEqual(evidence?.value, matching)
        XCTAssertEqual(cancellationCount, 1)
        owner.cancel()
    }

    func testSettingsAppVisibilityQueryProjectionUsesDelayedEvidence() {
        var snapshot = settingsAppVisibilityQueryProjectionTestSnapshot(
            searchFieldValue: "Mail",
            projectionIdentifier:
                FlowTabUITestSettingsAppVisibilityQueryProjectionTestPolicy
                    .baselineIdentifier,
            targetRowExists: false
        )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let owner =
            FlowTabUITestSettingsAppVisibilityQueryProjectionObservationOwner(
                expectation:
                    settingsAppVisibilityQueryProjectionTestExpectation(),
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )
        owner.start()

        snapshot = settingsAppVisibilityQueryProjectionTestSnapshot(
            searchFieldValue: "ceshi"
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = settingsAppVisibilityQueryProjectionTestSnapshot()
        scheduledReadback?(.scheduledReadback)
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestSettingsAppVisibilityQueryProjectionTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .scheduledReadback)
        XCTAssertEqual(evidence?.value, snapshot)
        owner.cancel()
    }

    func testSettingsAppVisibilityQueryProjectionLifecycleUnderPressure() {
        let matching = settingsAppVisibilityQueryProjectionTestSnapshot()

        for iteration in
            0..<FlowTabUITestSettingsAppVisibilityQueryProjectionTestPolicy
                .pressureIterations
        {
            var triggerDidComplete = false
            var snapshot = iteration.isMultiple(of: 2)
                ? matching
                : settingsAppVisibilityQueryProjectionTestSnapshot(
                    targetRowExists: false
                )
            var scheduledReadback:
                ((FlowTabUITestConditionObservationSource) -> Void)?
            var readbackCount = 0
            var cancellationCount = 0
            let owner =
                FlowTabUITestSettingsAppVisibilityQueryProjectionObservationOwner(
                    expectation:
                        settingsAppVisibilityQueryProjectionTestExpectation(),
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
                    FlowTabUITestSettingsAppVisibilityQueryProjectionTestPolicy
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
            FlowTabUITestSettingsAppVisibilityQueryProjectionObservationOwner(
                expectation:
                    settingsAppVisibilityQueryProjectionTestExpectation(),
                observationRegistration: { callback in
                    cancelledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    cancelledReadbackCount += 1
                    return self.settingsAppVisibilityQueryProjectionTestSnapshot(
                        targetRowExists: false
                    )
                }
            )
        cancelledOwner.start()
        cancelledOwner.cancel()
        cancelledReadback?(.scheduledReadback)
        XCTAssertEqual(cancelledReadbackCount, 1)
    }

    func testSettingsAppVisibilityQueryProjectionWatchdogReportsState() {
        let owner = settingsAppVisibilityQueryProjectionTestOwner {
            self.settingsAppVisibilityQueryProjectionTestSnapshot(
                projectionIdentifier:
                    FlowTabUITestSettingsAppVisibilityQueryProjectionTestPolicy
                        .baselineIdentifier,
                targetRowExists: false
            )
        }
        owner.start()

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSettingsAppVisibilityQueryProjectionTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("source=watchdogReadback")
        )
        XCTAssertTrue(owner.diagnosticSummary.contains("expectedQuery=\"Mail\""))
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                FlowTabUITestSettingsAppVisibilityQueryProjectionTestPolicy
                    .baselineIdentifier
            )
        )
        XCTAssertTrue(owner.diagnosticSummary.contains("targetRowExists=false"))
        owner.cancel()
    }

    private func settingsAppVisibilityQueryProjectionTestOwner(
        readback: @escaping () ->
            FlowTabUITestSettingsAppVisibilityQueryProjectionSnapshot
    ) -> FlowTabUITestSettingsAppVisibilityQueryProjectionObservationOwner {
        .init(
            expectation: settingsAppVisibilityQueryProjectionTestExpectation(),
            observationRegistration: nil,
            readback: readback
        )
    }

    private func settingsAppVisibilityQueryProjectionTestExpectation()
        -> FlowTabUITestSettingsAppVisibilityQueryProjectionExpectation
    {
        .init(
            expectedQuery: "Mail",
            projectionIdentifierPrefix:
                FlowTabUITestSettingsAppVisibilityQueryProjectionTestPolicy
                    .identifierPrefix,
            baselineProjectionIdentifier:
                FlowTabUITestSettingsAppVisibilityQueryProjectionTestPolicy
                    .baselineIdentifier,
            targetRowIdentifier:
                FlowTabUITestSettingsAppVisibilityQueryProjectionTestPolicy
                    .targetRowIdentifier
        )
    }

    private func settingsAppVisibilityQueryProjectionTestSnapshot(
        applicationState: XCUIApplication.State = .runningForeground,
        managerExists: Bool = true,
        searchFieldExists: Bool = true,
        searchFieldValue: String = "Mail",
        projectionIdentifier: String? =
            FlowTabUITestSettingsAppVisibilityQueryProjectionTestPolicy
                .projectedIdentifier,
        targetRowExists: Bool = true
    ) -> FlowTabUITestSettingsAppVisibilityQueryProjectionSnapshot {
        .init(
            applicationState: applicationState,
            managerExists: managerExists,
            searchFieldExists: searchFieldExists,
            searchFieldValue: searchFieldValue,
            projectionIdentifier: projectionIdentifier,
            targetRowExists: targetRowExists
        )
    }
}
