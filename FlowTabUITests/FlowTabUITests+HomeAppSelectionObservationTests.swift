import Foundation
import XCTest

private enum FlowTabUITestHomeAppSelectionTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let budgetWatchdog: TimeInterval = 8
    static let monotonicOrigin: TimeInterval = 100
    static let beforeDeadlineElapsed: TimeInterval = 7.5
    static let afterDeadlineElapsed: TimeInterval = 9
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testHomeAppSelectionUsesMatchingInitialProjection() {
        var scheduledRegistrationCount = 0
        let owner =
            FlowTabUITestHomeAppSelectionObservationOwner(
                expectedTitle: "Atlas",
                scheduledRegistration: { _ in
                    scheduledRegistrationCount += 1
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    self.homeAppSelectionTestSnapshot(
                        title: "Atlas"
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .initialReadback
        )
        XCTAssertEqual(scheduledRegistrationCount, 0)
        owner.markTriggerCompleted()
        XCTAssertEqual(scheduledRegistrationCount, 0)
    }

    func testHomeAppSelectionReadsBackSynchronousProjectionAfterTrigger() {
        var snapshot =
            homeAppSelectionTestSnapshot(title: "Other")
        var scheduledRegistrationCount = 0
        let owner =
            FlowTabUITestHomeAppSelectionObservationOwner(
                expectedTitle: "Atlas",
                scheduledRegistration: { _ in
                    scheduledRegistrationCount += 1
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )
        owner.start()
        defer { owner.cancel() }
        XCTAssertNil(owner.resolvedEvidence)

        snapshot =
            homeAppSelectionTestSnapshot(title: "Atlas")
        XCTAssertNil(owner.resolvedEvidence)
        owner.markTriggerCompleted()

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .triggerReadback
        )
        XCTAssertEqual(scheduledRegistrationCount, 0)
    }

    func testHomeAppSelectionScheduledEvidenceOnlyDelaysResolution() {
        var snapshot =
            homeAppSelectionTestSnapshot(title: "Other")
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        var readbackCount = 0
        let owner =
            FlowTabUITestHomeAppSelectionObservationOwner(
                expectedTitle: "Atlas",
                scheduledRegistration: { callback in
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
        owner.markTriggerCompleted()
        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertNotNil(scheduledReadback)

        snapshot =
            homeAppSelectionTestSnapshot(title: "Atlas")
        scheduledReadback?(.scheduledReadback)
        let resolvedReadbackCount = readbackCount
        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .scheduledReadback
        )
        XCTAssertEqual(readbackCount, resolvedReadbackCount)
        XCTAssertEqual(cancellationCount, 1)
        owner.cancel()
    }

    func testHomeAppSelectionRejectsCancelledGenerationsUnderPressure() {
        for _ in 0..<FlowTabUITestHomeAppSelectionTestPolicy
            .pressureIterations
        {
            var snapshot =
                homeAppSelectionTestSnapshot(title: "Other")
            var scheduledReadbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            let owner =
                FlowTabUITestHomeAppSelectionObservationOwner(
                    expectedTitle: "Atlas",
                    scheduledRegistration: { callback in
                        scheduledReadbacks.append(callback)
                        return FlowTabUITestObservationCancellation {}
                    },
                    readback: { snapshot }
                )

            owner.start()
            owner.markTriggerCompleted()
            let staleReadback = scheduledReadbacks[0]
            owner.cancel()
            owner.start()
            owner.markTriggerCompleted()
            snapshot =
                homeAppSelectionTestSnapshot(title: "Atlas")

            staleReadback(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
            scheduledReadbacks[1](.scheduledReadback)
            scheduledReadbacks[1](.scheduledReadback)
            XCTAssertEqual(
                owner.resolvedEvidence?.generation,
                2
            )
            owner.cancel()
        }
    }

    func testHomeAppSelectionWatchdogReportsLastProjection() {
        let owner =
            FlowTabUITestHomeAppSelectionObservationOwner(
                expectedTitle: "Atlas",
                scheduledRegistration: { _ in
                    FlowTabUITestObservationCancellation {}
                },
                readback: {
                    self.homeAppSelectionTestSnapshot(
                        title: "Other"
                    )
                }
            )
        owner.start()
        owner.markTriggerCompleted()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestHomeAppSelectionTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "phase=triggerCompleted"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "expected{titleVisible=Atlas}"
            )
        )
    }

    func testHomeAppSelectionWatchdogBudgetUsesMonotonicTime() {
        XCTAssertEqual(
            FlowTabUITestHomeAppSelectionTestPolicy
                .budgetWatchdog,
            8
        )
        XCTAssertLessThan(
            FlowTabUITestHomeAppSelectionTestPolicy
                .beforeDeadlineElapsed,
            FlowTabUITestHomeAppSelectionTestPolicy
                .budgetWatchdog
        )
        XCTAssertGreaterThan(
            FlowTabUITestHomeAppSelectionTestPolicy
                .afterDeadlineElapsed,
            FlowTabUITestHomeAppSelectionTestPolicy
                .budgetWatchdog
        )

        var monotonicTime =
            FlowTabUITestHomeAppSelectionTestPolicy
                .monotonicOrigin
        let budget =
            FlowTabUITestHomeAppSelectionWatchdogBudget(
                timeout:
                    FlowTabUITestHomeAppSelectionTestPolicy
                        .budgetWatchdog,
                monotonicTime: { monotonicTime }
            )

        XCTAssertEqual(
            budget.remaining,
            FlowTabUITestHomeAppSelectionTestPolicy
                .budgetWatchdog
        )
        monotonicTime =
            FlowTabUITestHomeAppSelectionTestPolicy
                .monotonicOrigin
            + FlowTabUITestHomeAppSelectionTestPolicy
                .beforeDeadlineElapsed
        XCTAssertEqual(
            budget.remaining,
            FlowTabUITestHomeAppSelectionTestPolicy
                .budgetWatchdog
                - FlowTabUITestHomeAppSelectionTestPolicy
                    .beforeDeadlineElapsed
        )
        monotonicTime =
            FlowTabUITestHomeAppSelectionTestPolicy
                .monotonicOrigin
            + FlowTabUITestHomeAppSelectionTestPolicy
                .afterDeadlineElapsed
        XCTAssertEqual(budget.remaining, 0)
    }

    private func homeAppSelectionTestSnapshot(
        title: String
    ) -> FlowTabUITestHomeWindowProjectionSnapshot<String> {
        FlowTabUITestHomeWindowProjectionSnapshot(
            rows: [
                FlowTabUITestHomeWindowRowSnapshot(
                    identifier:
                        "flowtab.home.window.test",
                    label: title,
                    value: title,
                    element: "row"
                )
            ],
            visibleStaticTextTitles: []
        )
    }
}
