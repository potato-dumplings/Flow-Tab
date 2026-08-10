import Foundation
import XCTest

private enum
    FlowTabUITestSettingsPermissionActionProjectionTestPolicy
{
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testSettingsPermissionActionProjectionPolicyPreservesContracts() {
        XCTAssertEqual(
            FlowTabUITestSettingsPermissionActionProjectionPolicy
                .watchdog,
            5
        )
        XCTAssertTrue(
            FlowTabUITestSettingsPermissionActionProjectionPolicy
                .watchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSettingsPermissionActionProjectionPolicy
                .watchdog,
            0
        )
        XCTAssertEqual(
            FlowTabUITestSettingsPermissionActionProjectionPolicy
                .maximumCompactActionHeight,
            36
        )
    }

    func testSettingsPermissionActionProjectionRequiresAtomicControls() {
        let anyLabelExpectation =
            FlowTabUITestSettingsPermissionActionProjectionExpectation()
        let matching = settingsPermissionActionProjectionTestSnapshot()

        XCTAssertTrue(
            anyLabelExpectation.isSatisfied(by: matching)
        )
        XCTAssertFalse(
            anyLabelExpectation.isSatisfied(
                by: settingsPermissionActionProjectionTestSnapshot(
                    applicationState: .runningBackground
                )
            )
        )
        XCTAssertFalse(
            anyLabelExpectation.isSatisfied(
                by: settingsPermissionActionProjectionTestSnapshot(
                    settingsContentExists: false
                )
            )
        )
        XCTAssertFalse(
            anyLabelExpectation.isSatisfied(
                by: settingsPermissionActionProjectionTestSnapshot(
                    accessibilityActionExists: false
                )
            )
        )
        XCTAssertFalse(
            anyLabelExpectation.isSatisfied(
                by: settingsPermissionActionProjectionTestSnapshot(
                    accessibilityActionIsHittable: false
                )
            )
        )
        XCTAssertFalse(
            anyLabelExpectation.isSatisfied(
                by: settingsPermissionActionProjectionTestSnapshot(
                    accessibilityActionHeight: 37
                )
            )
        )
        XCTAssertFalse(
            anyLabelExpectation.isSatisfied(
                by: settingsPermissionActionProjectionTestSnapshot(
                    screenCaptureActionExists: false
                )
            )
        )
        XCTAssertFalse(
            anyLabelExpectation.isSatisfied(
                by: settingsPermissionActionProjectionTestSnapshot(
                    screenCaptureActionIsHittable: false
                )
            )
        )
        XCTAssertFalse(
            anyLabelExpectation.isSatisfied(
                by: settingsPermissionActionProjectionTestSnapshot(
                    screenCaptureActionHeight: 37
                )
            )
        )

        let exactLabelExpectation =
            FlowTabUITestSettingsPermissionActionProjectionExpectation(
                expectedAccessibilityLabel:
                    "Manage Accessibility permission",
                expectedScreenCaptureLabel:
                    "Manage Screen Recording permission"
            )
        XCTAssertTrue(
            exactLabelExpectation.isSatisfied(by: matching)
        )
        XCTAssertFalse(
            exactLabelExpectation.isSatisfied(
                by: settingsPermissionActionProjectionTestSnapshot(
                    accessibilityActionLabel:
                        "Grant Accessibility permission"
                )
            )
        )
        XCTAssertFalse(
            exactLabelExpectation.isSatisfied(
                by: settingsPermissionActionProjectionTestSnapshot(
                    screenCaptureActionLabel:
                        "Grant Screen Recording permission"
                )
            )
        )
    }

    func testSettingsPermissionActionProjectionUsesPreTriggerEvidence() {
        let matching = settingsPermissionActionProjectionTestSnapshot()
        var triggerDidComplete = false
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestSettingsPermissionActionProjectionObservationOwner(
                expectation: .init(),
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

        XCTAssertEqual(owner.latestEvidence?.source, .initialReadback)
        XCTAssertEqual(owner.latestEvidence?.value, matching)
        XCTAssertNil(owner.resolvedEvidence)

        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)
        triggerDidComplete = true
        owner.requestReadback(source: .triggerReadback)
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestSettingsPermissionActionProjectionTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .triggerReadback)
        XCTAssertEqual(evidence?.value, matching)
        XCTAssertEqual(cancellationCount, 1)
        owner.cancel()
    }

    func testSettingsPermissionActionProjectionUsesDelayedEvidence() {
        var snapshot = settingsPermissionActionProjectionTestSnapshot(
            screenCaptureActionIsHittable: false
        )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let owner =
            FlowTabUITestSettingsPermissionActionProjectionObservationOwner(
                expectation: .init(),
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )
        owner.start()

        XCTAssertNil(owner.resolvedEvidence)
        snapshot = settingsPermissionActionProjectionTestSnapshot()
        scheduledReadback?(.scheduledReadback)
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestSettingsPermissionActionProjectionTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .scheduledReadback)
        XCTAssertEqual(evidence?.value, snapshot)
        owner.cancel()
    }

    func testSettingsPermissionActionProjectionLifecycleUnderPressure() {
        let matching = settingsPermissionActionProjectionTestSnapshot()

        for iteration in
            0..<FlowTabUITestSettingsPermissionActionProjectionTestPolicy
                .pressureIterations
        {
            var triggerDidComplete = false
            var snapshot = iteration.isMultiple(of: 2)
                ? matching
                : settingsPermissionActionProjectionTestSnapshot(
                    accessibilityActionIsHittable: false
                )
            var scheduledReadback:
                ((FlowTabUITestConditionObservationSource) -> Void)?
            var readbackCount = 0
            var cancellationCount = 0
            let owner =
                FlowTabUITestSettingsPermissionActionProjectionObservationOwner(
                    expectation: .init(),
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
                    FlowTabUITestSettingsPermissionActionProjectionTestPolicy
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
            FlowTabUITestSettingsPermissionActionProjectionObservationOwner(
                expectation: .init(),
                observationRegistration: { callback in
                    cancelledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    cancelledReadbackCount += 1
                    return self
                        .settingsPermissionActionProjectionTestSnapshot(
                            accessibilityActionIsHittable: false
                        )
                }
            )
        cancelledOwner.start()
        cancelledOwner.cancel()
        cancelledReadback?(.scheduledReadback)
        XCTAssertEqual(cancelledReadbackCount, 1)
    }

    func testSettingsPermissionActionProjectionWatchdogReportsLastState() {
        let owner =
            FlowTabUITestSettingsPermissionActionProjectionObservationOwner(
                expectation: .init(
                    expectedAccessibilityLabel:
                        "Manage Accessibility permission",
                    expectedScreenCaptureLabel:
                        "Manage Screen Recording permission"
                ),
                observationRegistration: nil,
                readback: {
                    self.settingsPermissionActionProjectionTestSnapshot(
                        accessibilityActionLabel:
                            "Grant Accessibility permission"
                    )
                }
            )
        owner.start()

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSettingsPermissionActionProjectionTestPolicy
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
                "Grant Accessibility permission"
            )
        )
        owner.cancel()
    }

    private func settingsPermissionActionProjectionTestSnapshot(
        applicationState: XCUIApplication.State = .runningForeground,
        settingsContentExists: Bool = true,
        accessibilityActionExists: Bool = true,
        accessibilityActionIsHittable: Bool = true,
        accessibilityActionLabel: String =
            "Manage Accessibility permission",
        accessibilityActionHeight: CGFloat = 28,
        screenCaptureActionExists: Bool = true,
        screenCaptureActionIsHittable: Bool = true,
        screenCaptureActionLabel: String =
            "Manage Screen Recording permission",
        screenCaptureActionHeight: CGFloat = 28
    ) -> FlowTabUITestSettingsPermissionActionProjectionSnapshot {
        FlowTabUITestSettingsPermissionActionProjectionSnapshot(
            applicationState: applicationState,
            settingsContentExists: settingsContentExists,
            accessibilityActionExists: accessibilityActionExists,
            accessibilityActionIsHittable:
                accessibilityActionIsHittable,
            accessibilityActionLabel: accessibilityActionLabel,
            accessibilityActionHeight: accessibilityActionHeight,
            screenCaptureActionExists: screenCaptureActionExists,
            screenCaptureActionIsHittable:
                screenCaptureActionIsHittable,
            screenCaptureActionLabel: screenCaptureActionLabel,
            screenCaptureActionHeight: screenCaptureActionHeight
        )
    }
}
