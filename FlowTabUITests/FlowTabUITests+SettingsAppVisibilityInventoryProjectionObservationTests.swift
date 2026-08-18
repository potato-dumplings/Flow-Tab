import Foundation
import XCTest

private enum
    FlowTabUITestSettingsAppVisibilityInventoryReadinessTestPolicy
{
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
    static let readyMarkerIdentifier =
        "flowtab.settings.app-visibility.inventory.ready"
}

extension FlowTabUITests {
    func testSettingsAppVisibilityInventoryReadinessPolicyPreservesBound() {
        XCTAssertEqual(
            FlowTabUITestSettingsAppVisibilityInventoryReadinessPolicy
                .watchdog,
            30
        )
        XCTAssertTrue(
            FlowTabUITestSettingsAppVisibilityInventoryReadinessPolicy
                .watchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSettingsAppVisibilityInventoryReadinessPolicy
                .watchdog,
            0
        )
    }

    func testSettingsAppVisibilityInventoryReadinessRequiresReadyMarker() {
        let expectation = settingsAppVisibilityInventoryTestExpectation()
        let matching = settingsAppVisibilityInventoryTestSnapshot()

        XCTAssertTrue(expectation.isSatisfied(by: matching))
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityInventoryTestSnapshot(
                    applicationState: .runningBackground
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityInventoryTestSnapshot(
                    managerExists: false
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: settingsAppVisibilityInventoryTestSnapshot(
                    readyMarkerExists: false
                )
            )
        )
    }

    func testSettingsAppVisibilityInventoryReadinessAcceptsInitialTarget() {
        let matching = settingsAppVisibilityInventoryTestSnapshot()
        let owner = settingsAppVisibilityInventoryTestOwner {
            matching
        }
        owner.start()

        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestSettingsAppVisibilityInventoryReadinessTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .initialReadback)
        XCTAssertEqual(evidence?.value, matching)
        owner.cancel()
    }

    func testSettingsAppVisibilityInventoryReadinessGatesNavigation() {
        let matching = settingsAppVisibilityInventoryTestSnapshot()
        var navigationDidComplete = false
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestSettingsAppVisibilityInventoryReadinessObservationOwner(
                expectation: settingsAppVisibilityInventoryTestExpectation(),
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                acceptsResolution: { navigationDidComplete },
                readback: { matching }
            )
        owner.start()

        XCTAssertEqual(owner.latestEvidence?.source, .initialReadback)
        XCTAssertNil(owner.resolvedEvidence)
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        navigationDidComplete = true
        owner.requestReadback(source: .triggerReadback)
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestSettingsAppVisibilityInventoryReadinessTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .triggerReadback)
        XCTAssertEqual(evidence?.value, matching)
        XCTAssertEqual(cancellationCount, 1)
        owner.cancel()
    }

    func testSettingsAppVisibilityInventoryReadinessUsesDelayedEvidence() {
        var snapshot = settingsAppVisibilityInventoryTestSnapshot(
            readyMarkerExists: false
        )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let owner =
            FlowTabUITestSettingsAppVisibilityInventoryReadinessObservationOwner(
                expectation: settingsAppVisibilityInventoryTestExpectation(),
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )
        owner.start()

        XCTAssertNil(owner.resolvedEvidence)
        snapshot = settingsAppVisibilityInventoryTestSnapshot()
        scheduledReadback?(.scheduledReadback)
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestSettingsAppVisibilityInventoryReadinessTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .scheduledReadback)
        XCTAssertEqual(evidence?.value, snapshot)
        owner.cancel()
    }

    func testSettingsAppVisibilityInventoryReadinessLifecycleUnderPressure() {
        let matching = settingsAppVisibilityInventoryTestSnapshot()

        for iteration in
            0..<FlowTabUITestSettingsAppVisibilityInventoryReadinessTestPolicy
                .pressureIterations
        {
            var navigationDidComplete = false
            var snapshot = iteration.isMultiple(of: 2)
                ? matching
                : settingsAppVisibilityInventoryTestSnapshot(
                    readyMarkerExists: false
                )
            var scheduledReadback:
                ((FlowTabUITestConditionObservationSource) -> Void)?
            var readbackCount = 0
            var cancellationCount = 0
            let owner =
                FlowTabUITestSettingsAppVisibilityInventoryReadinessObservationOwner(
                    expectation:
                        settingsAppVisibilityInventoryTestExpectation(),
                    observationRegistration: { callback in
                        scheduledReadback = callback
                        return FlowTabUITestObservationCancellation {
                            cancellationCount += 1
                        }
                    },
                    acceptsResolution: { navigationDidComplete },
                    readback: {
                        readbackCount += 1
                        return snapshot
                    }
                )
            owner.start()

            XCTAssertNil(owner.resolvedEvidence, "iteration=\(iteration)")
            navigationDidComplete = true
            snapshot = matching
            scheduledReadback?(.scheduledReadback)
            let evidence = owner.waitForResolution(
                timeout:
                    FlowTabUITestSettingsAppVisibilityInventoryReadinessTestPolicy
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
            FlowTabUITestSettingsAppVisibilityInventoryReadinessObservationOwner(
                expectation: settingsAppVisibilityInventoryTestExpectation(),
                observationRegistration: { callback in
                    cancelledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    cancelledReadbackCount += 1
                    return self.settingsAppVisibilityInventoryTestSnapshot(
                        readyMarkerExists: false
                    )
                }
            )
        cancelledOwner.start()
        cancelledOwner.cancel()
        cancelledReadback?(.scheduledReadback)
        XCTAssertEqual(cancelledReadbackCount, 1)
    }

    func testSettingsAppVisibilityInventoryReadinessWatchdogReportsState() {
        let owner = settingsAppVisibilityInventoryTestOwner {
            self.settingsAppVisibilityInventoryTestSnapshot(
                readyMarkerExists: false
            )
        }
        owner.start()

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSettingsAppVisibilityInventoryReadinessTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("source=watchdogReadback")
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                FlowTabUITestSettingsAppVisibilityInventoryReadinessTestPolicy
                    .readyMarkerIdentifier
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("readyMarkerExists=false")
        )
        owner.cancel()
    }

    private func settingsAppVisibilityInventoryTestOwner(
        readback: @escaping () ->
            FlowTabUITestSettingsAppVisibilityInventoryReadinessSnapshot
    ) -> FlowTabUITestSettingsAppVisibilityInventoryReadinessObservationOwner {
        .init(
            expectation: settingsAppVisibilityInventoryTestExpectation(),
            observationRegistration: nil,
            readback: readback
        )
    }

    private func settingsAppVisibilityInventoryTestExpectation()
        -> FlowTabUITestSettingsAppVisibilityInventoryReadinessExpectation
    {
        .init(
            readyMarkerIdentifier:
                FlowTabUITestSettingsAppVisibilityInventoryReadinessTestPolicy
                    .readyMarkerIdentifier
        )
    }

    private func settingsAppVisibilityInventoryTestSnapshot(
        applicationState: XCUIApplication.State = .runningForeground,
        managerExists: Bool = true,
        readyMarkerExists: Bool = true
    ) -> FlowTabUITestSettingsAppVisibilityInventoryReadinessSnapshot {
        .init(
            applicationState: applicationState,
            managerExists: managerExists,
            readyMarkerExists: readyMarkerExists
        )
    }
}
