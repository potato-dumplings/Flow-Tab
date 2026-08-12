import Foundation
import XCTest

private enum
    FlowTabUITestHomeWindowRecencyOrderedProjectionTestPolicy
{
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testHomeWindowRecencyOrderedProjectionPolicyCompatibility() {
        let watchdog =
            FlowTabUITestHomeWindowRecencyOrderedProjectionPolicy
                .orderedWindowPublicationWatchdog
        XCTAssertEqual(watchdog, 12)
        XCTAssertTrue(watchdog.isFinite)
        XCTAssertGreaterThan(watchdog, 0)
    }

    func testHomeWindowRecencyOrderedProjectionRequiresExactWindowEvidence() {
        let expectation = homeWindowRecencyOrderedTestExpectation()

        XCTAssertTrue(
            expectation.isSatisfied(
                by: homeWindowRecencyOrderedTestSnapshot(
                    rows: [
                        ("flowtab.home.window.cg-42-202", "Draft"),
                        ("flowtab.home.window.cg-42-101", "Inbox"),
                        ("flowtab.home.window.cg-42-303", "Archive")
                    ]
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: homeWindowRecencyOrderedTestSnapshot(
                    rows: [
                        ("flowtab.home.window.cg-42-101", "Inbox"),
                        ("flowtab.home.window.cg-42-202", "Draft")
                    ]
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: homeWindowRecencyOrderedTestSnapshot(
                    rows: [
                        ("flowtab.home.window.cg-42-999", "Draft"),
                        ("flowtab.home.window.cg-42-101", "Inbox")
                    ]
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: homeWindowRecencyOrderedTestSnapshot(
                    rows: [
                        ("flowtab.home.window.cg-42-202", "Draft"),
                        ("flowtab.home.window.cg-42-202", "Inbox")
                    ]
                )
            )
        )
        XCTAssertFalse(
            FlowTabUITestHomeWindowRecencyOrderedProjectionExpectation(
                expectedTitles: [],
                targetWindowIdentifier:
                    "flowtab.home.window.cg-42-202"
            ).hasValidConfiguration
        )
        XCTAssertFalse(
            FlowTabUITestHomeWindowRecencyOrderedProjectionExpectation(
                expectedTitles: ["Draft", "Inbox"],
                targetWindowIdentifier: "invalid-row"
            ).hasValidConfiguration
        )
        XCTAssertTrue(
            expectation.diagnosticSummary.contains(
                "targetWindowIdentifier="
                    + "flowtab.home.window.cg-42-202"
            )
        )
    }

    func testHomeWindowRecencyOrderedProjectionGatesInitiallyMatchingState() {
        let snapshot = homeWindowRecencyOrderedMatchingTestSnapshot()
        var downstreamRegistrationCount = 0
        let owner =
            FlowTabUITestHomeWindowRecencyOrderedProjectionObservationOwner(
                expectation: homeWindowRecencyOrderedTestExpectation(),
                scheduledRegistration: { _ in
                    downstreamRegistrationCount += 1
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(owner.latestEvidence?.source, .initialReadback)
        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(downstreamRegistrationCount, 0)

        owner.markAppSelectionCompleted()

        XCTAssertEqual(owner.resolvedEvidence?.source, .triggerReadback)
        XCTAssertEqual(
            owner.resolvedEvidence?.value.rows.map(\.identifier),
            [
                "flowtab.home.window.cg-42-202",
                "flowtab.home.window.cg-42-101"
            ]
        )
        XCTAssertEqual(downstreamRegistrationCount, 0)
    }

    func testHomeWindowRecencyOrderedProjectionUsesDelayedScheduledEvidence() {
        var snapshot = homeWindowRecencyOrderedTestSnapshot(
            rows: [
                ("flowtab.home.window.cg-42-101", "Inbox"),
                ("flowtab.home.window.cg-42-202", "Draft")
            ]
        )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var downstreamRegistrationCount = 0
        var downstreamCancellationCount = 0
        let owner =
            FlowTabUITestHomeWindowRecencyOrderedProjectionObservationOwner(
                expectation: homeWindowRecencyOrderedTestExpectation(),
                scheduledRegistration: { callback in
                    downstreamRegistrationCount += 1
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        downstreamCancellationCount += 1
                    }
                },
                readback: { snapshot }
            )
        owner.start()
        defer { owner.cancel() }

        owner.markAppSelectionCompleted()
        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(downstreamRegistrationCount, 1)

        snapshot = homeWindowRecencyOrderedMatchingTestSnapshot()
        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(owner.resolvedEvidence?.source, .scheduledReadback)
        XCTAssertEqual(downstreamCancellationCount, 1)
    }

    func testHomeWindowRecencyOrderedProjectionSlowSchedulingOnlyDelaysResolution() {
        var snapshot = homeWindowRecencyOrderedTestSnapshot(rows: [])
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let owner =
            FlowTabUITestHomeWindowRecencyOrderedProjectionObservationOwner(
                expectation: homeWindowRecencyOrderedTestExpectation(),
                scheduledRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )
        owner.start()
        defer { owner.cancel() }
        owner.markAppSelectionCompleted()

        for _ in 0..<5 {
            scheduledReadback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }
        snapshot = homeWindowRecencyOrderedMatchingTestSnapshot()
        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(owner.resolvedEvidence?.source, .scheduledReadback)
    }

    func testHomeWindowRecencyOrderedProjectionRejectsReplacedReadbacksUnderPressure() {
        var snapshot = homeWindowRecencyOrderedTestSnapshot(rows: [])
        var scheduledReadbacks: [
            (FlowTabUITestConditionObservationSource) -> Void
        ] = []
        var cancellationCount = 0
        var readbackCount = 0
        let owner =
            FlowTabUITestHomeWindowRecencyOrderedProjectionObservationOwner(
                expectation: homeWindowRecencyOrderedTestExpectation(),
                scheduledRegistration: { callback in
                    scheduledReadbacks.append(callback)
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    readbackCount += 1
                    return snapshot
                }
            )

        for _ in
            0..<FlowTabUITestHomeWindowRecencyOrderedProjectionTestPolicy
                .pressureIterations
        {
            owner.start()
            owner.markAppSelectionCompleted()
        }
        XCTAssertEqual(
            scheduledReadbacks.count,
            FlowTabUITestHomeWindowRecencyOrderedProjectionTestPolicy
                .pressureIterations
        )
        let readbackCountBeforeStaleEvidence = readbackCount
        for staleReadback in scheduledReadbacks.dropLast() {
            staleReadback(.scheduledReadback)
        }
        XCTAssertEqual(readbackCount, readbackCountBeforeStaleEvidence)

        snapshot = homeWindowRecencyOrderedMatchingTestSnapshot()
        scheduledReadbacks.last?(.scheduledReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.generation,
            UInt64(
                FlowTabUITestHomeWindowRecencyOrderedProjectionTestPolicy
                    .pressureIterations
            )
        )
        XCTAssertEqual(
            cancellationCount,
            FlowTabUITestHomeWindowRecencyOrderedProjectionTestPolicy
                .pressureIterations
        )
        owner.cancel()
    }

    func testHomeWindowRecencyOrderedProjectionWatchdogReportsFinalEvidence() {
        var scheduledCancellationCount = 0
        let owner =
            FlowTabUITestHomeWindowRecencyOrderedProjectionObservationOwner(
                expectation: homeWindowRecencyOrderedTestExpectation(),
                scheduledRegistration: { _ in
                    FlowTabUITestObservationCancellation {
                        scheduledCancellationCount += 1
                    }
                },
                readback: {
                    self.homeWindowRecencyOrderedTestSnapshot(
                        rows: [
                            (
                                "flowtab.home.window.cg-7-303",
                                "Finder Main"
                            )
                        ]
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }
        owner.markAppSelectionCompleted()

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestHomeWindowRecencyOrderedProjectionTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("source=watchdogReadback")
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "phase=appSelectionCompleted"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "expectedTitles=[\"Draft\", \"Inbox\"]"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("label=Finder Main")
        )
        XCTAssertTrue(owner.diagnosticSummary.contains("waitResult="))
        XCTAssertEqual(scheduledCancellationCount, 1)
    }

    private func homeWindowRecencyOrderedTestExpectation()
        -> FlowTabUITestHomeWindowRecencyOrderedProjectionExpectation
    {
        FlowTabUITestHomeWindowRecencyOrderedProjectionExpectation(
            expectedTitles: ["Draft", "Inbox"],
            targetWindowIdentifier: "flowtab.home.window.cg-42-202"
        )
    }

    private func homeWindowRecencyOrderedMatchingTestSnapshot()
        -> FlowTabUITestHomeWindowProjectionSnapshot<String>
    {
        homeWindowRecencyOrderedTestSnapshot(
            rows: [
                ("flowtab.home.window.cg-42-202", "Draft"),
                ("flowtab.home.window.cg-42-101", "Inbox")
            ]
        )
    }

    private func homeWindowRecencyOrderedTestSnapshot(
        rows: [(identifier: String, label: String)]
    ) -> FlowTabUITestHomeWindowProjectionSnapshot<String> {
        FlowTabUITestHomeWindowProjectionSnapshot(
            rows: rows.enumerated().map { index, row in
                FlowTabUITestHomeWindowRowSnapshot(
                    identifier: row.identifier,
                    label: row.label,
                    value: row.label,
                    element: "row-element-\(index)"
                )
            },
            visibleStaticTextTitles: []
        )
    }
}
