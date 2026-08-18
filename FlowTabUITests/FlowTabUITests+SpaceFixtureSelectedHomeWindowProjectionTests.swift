import Foundation
import XCTest

private enum
    FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionTestPolicy
{
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 200
}

private enum FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionFixture {
    static let browserAppID = "com.example.fixture.browser"
    static let finderAppID = "com.example.fixture.finder"

    static let browserExpectation =
        FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionExpectation(
            selectedBundleIdentifier: browserAppID,
            expectedRowCount: 3,
            visibleTitles: ["Docs", "Mail"],
            excludedTitles: ["Finder Main", "Notes Inbox"]
        )
    static let fullscreenExpectation =
        FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionExpectation(
            selectedBundleIdentifier: browserAppID,
            expectedRowCount: 1,
            visibleTitles: [],
            excludedTitles: ["Finder Main"]
        )

    static func browserSnapshot(
        state: XCUIApplication.State = .runningForeground,
        countBefore: String? = "3 windows",
        rows: [
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionSnapshot.Row
        ] = [
            .init(
                identifier: "flowtab.home.window.cg-11.id-docs",
                label: "Docs",
                value: "\(browserAppID) Current Space"
            ),
            .init(
                identifier: "flowtab.home.window.cg-12.id-mail",
                label: "Mail",
                value: "\(browserAppID) Other Space"
            ),
            .init(
                identifier: "flowtab.home.window.cg-13.id-review",
                label: "Review",
                value: "\(browserAppID) Fullscreen Space"
            )
        ],
        countAfter: String? = "3 windows"
    ) -> FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionSnapshot {
        .init(
            applicationState: state,
            windowCountLabelBeforeRows: countBefore,
            rows: rows,
            windowCountLabelAfterRows: countAfter
        )
    }

    static func finderSnapshot() ->
        FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionSnapshot
    {
        .init(
            applicationState: .runningForeground,
            windowCountLabelBeforeRows: "1 window",
            rows: [
                .init(
                    identifier: "flowtab.home.window.cg-21.id-finder",
                    label: "Finder Main",
                    value: "\(finderAppID) Current Space"
                )
            ],
            windowCountLabelAfterRows: "1 window"
        )
    }

    static func fullscreenSnapshot(
        countBefore: String? = "1 window",
        rows: [
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionSnapshot.Row
        ] = [
            .init(
                identifier: "flowtab.home.window.cg-13.id-review",
                label: "Review",
                value: "\(browserAppID) Fullscreen Space"
            )
        ],
        countAfter: String? = "1 window"
    ) -> FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionSnapshot {
        .init(
            applicationState: .runningForeground,
            windowCountLabelBeforeRows: countBefore,
            rows: rows,
            windowCountLabelAfterRows: countAfter
        )
    }
}

extension FlowTabUITests {
    func testSpaceFixtureSelectedHomeWindowProjectionPolicyCompatibility() {
        let policy =
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionPolicy.self
        XCTAssertEqual(policy.appSelectionTriggerWatchdog, 8)
        XCTAssertEqual(policy.perVisibleTitleProjectionWatchdog, 12)
        XCTAssertEqual(policy.excludedTitleProjectionWatchdog, 12)
        XCTAssertEqual(policy.watchdog(visibleTitleCount: 0), 32)
        XCTAssertEqual(policy.watchdog(visibleTitleCount: 1), 32)
        XCTAssertEqual(policy.watchdog(visibleTitleCount: 2), 44)
        XCTAssertTrue(policy.watchdog(visibleTitleCount: 2).isFinite)
        XCTAssertGreaterThan(policy.watchdog(visibleTitleCount: 2), 0)
    }

    func testSpaceFixtureSelectedHomeWindowProjectionParsesCountEvidence() {
        let snapshot =
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionSnapshot.self
        XCTAssertEqual(snapshot.count(from: "2 windows"), 2)
        XCTAssertEqual(snapshot.count(from: "2 个窗口"), 2)
        XCTAssertEqual(snapshot.count(from: "0 windows"), 0)
        XCTAssertNil(snapshot.count(from: nil))
        XCTAssertNil(snapshot.count(from: "windows"))
        XCTAssertNil(snapshot.count(from: "2 of 3 windows"))
    }

    func testSpaceFixtureSelectedHomeWindowProjectionRequiresWellFormedExpectation() {
        let fixture =
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionFixture.self
        XCTAssertTrue(fixture.browserExpectation.isWellFormed)
        XCTAssertTrue(fixture.fullscreenExpectation.isWellFormed)
        XCTAssertFalse(
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionExpectation(
                selectedBundleIdentifier: "",
                expectedRowCount: 1,
                visibleTitles: ["Docs"],
                excludedTitles: []
            ).isWellFormed
        )
        XCTAssertFalse(
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionExpectation(
                selectedBundleIdentifier: fixture.browserAppID,
                expectedRowCount: 0,
                visibleTitles: [],
                excludedTitles: ["Finder Main"]
            ).isWellFormed
        )
        XCTAssertFalse(
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionExpectation(
                selectedBundleIdentifier: fixture.browserAppID,
                expectedRowCount: 1,
                visibleTitles: [],
                excludedTitles: []
            ).isWellFormed
        )
        XCTAssertFalse(
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionExpectation(
                selectedBundleIdentifier: fixture.browserAppID,
                expectedRowCount: 1,
                visibleTitles: ["Docs"],
                excludedTitles: ["Docs"]
            ).isWellFormed
        )
        XCTAssertFalse(
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionExpectation(
                selectedBundleIdentifier: fixture.browserAppID,
                expectedRowCount: 1,
                visibleTitles: ["Docs", "Mail"],
                excludedTitles: []
            ).isWellFormed
        )
    }

    func testSpaceFixtureSelectedHomeWindowProjectionRequiresOneExactSnapshot() {
        let fixture =
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionFixture.self
        let expectation = fixture.browserExpectation
        XCTAssertTrue(
            expectation.isSatisfied(by: fixture.browserSnapshot())
        )
        XCTAssertTrue(
            expectation.isSatisfied(
                by: fixture.browserSnapshot(
                    rows: Array(
                        fixture.browserSnapshot().rows.reversed()
                    )
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: fixture.browserSnapshot(state: .runningBackground)
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: fixture.browserSnapshot(countBefore: "1 window")
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: fixture.browserSnapshot(countAfter: "4 windows")
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: fixture.browserSnapshot(
                    rows: Array(fixture.browserSnapshot().rows.prefix(1))
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: fixture.browserSnapshot(
                    rows: [
                        fixture.browserSnapshot().rows[0],
                        .init(
                            identifier: "flowtab.home.window.cg-12.id-calendar",
                            label: "Calendar",
                            value: "\(fixture.browserAppID) Other Space"
                        ),
                        fixture.browserSnapshot().rows[2]
                    ]
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: fixture.browserSnapshot(
                    rows: [
                        fixture.browserSnapshot().rows[0],
                        fixture.browserSnapshot().rows[1],
                        .init(
                            identifier: "flowtab.home.window.cg-22.id-finder",
                            label: "Finder Main",
                            value: "\(fixture.browserAppID) Other Space"
                        )
                    ]
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: fixture.browserSnapshot(
                    rows: [
                        fixture.browserSnapshot().rows[0],
                        .init(
                            identifier:
                                fixture.browserSnapshot().rows[0].identifier,
                            label: "Mail",
                            value: "\(fixture.browserAppID) Current Space"
                        ),
                        fixture.browserSnapshot().rows[2]
                    ]
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: fixture.browserSnapshot(
                    rows: [
                        fixture.browserSnapshot().rows[0],
                        .init(
                            identifier: "flowtab.home.window.cg-12.id-mail",
                            label: "Mail",
                            value: "\(fixture.finderAppID) Other Space"
                        ),
                        fixture.browserSnapshot().rows[2]
                    ]
                )
            )
        )
    }

    func testSpaceFixtureSelectedHomeWindowProjectionRequiresExactFullscreenState() {
        let fixture =
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionFixture.self
        let expectation = fixture.fullscreenExpectation
        XCTAssertTrue(
            expectation.isSatisfied(by: fixture.fullscreenSnapshot())
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: fixture.fullscreenSnapshot(countAfter: "2 windows")
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: fixture.fullscreenSnapshot(
                    rows: fixture.finderSnapshot().rows
                )
            )
        )
    }

    func testSpaceFixtureSelectedHomeWindowProjectionUsesMatchingInitialReadback() {
        let fixture =
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionFixture.self
        var registrationCount = 0
        let owner =
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionObservationOwner(
                expectation: fixture.browserExpectation,
                scheduledRegistration: { _ in
                    registrationCount += 1
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { fixture.browserSnapshot() }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(owner.resolvedEvidence?.source, .initialReadback)
        owner.markSelectionTriggerCompleted()
        XCTAssertEqual(registrationCount, 0)
    }

    func testSpaceFixtureSelectedHomeWindowProjectionReadsBackAfterTrigger() {
        let fixture =
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionFixture.self
        var snapshot = fixture.finderSnapshot()
        var registrationCount = 0
        let owner =
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionObservationOwner(
                expectation: fixture.browserExpectation,
                scheduledRegistration: { _ in
                    registrationCount += 1
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )
        owner.start()
        defer { owner.cancel() }

        snapshot = fixture.browserSnapshot()
        owner.markSelectionTriggerCompleted()
        owner.markSelectionTriggerCompleted()

        XCTAssertEqual(owner.resolvedEvidence?.source, .triggerReadback)
        XCTAssertEqual(owner.resolvedEvidence?.generation, 1)
        XCTAssertEqual(registrationCount, 0)
    }

    func testSpaceFixtureSelectedHomeWindowProjectionUsesDelayedScheduledEvidence() {
        let fixture =
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionFixture.self
        var snapshot = fixture.finderSnapshot()
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionObservationOwner(
                expectation: fixture.browserExpectation,
                scheduledRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: { snapshot }
            )
        owner.start()
        defer { owner.cancel() }
        owner.markSelectionTriggerCompleted()

        for _ in 0..<5 {
            scheduledReadback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }
        snapshot = fixture.browserSnapshot()
        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(owner.resolvedEvidence?.source, .scheduledReadback)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSpaceFixtureSelectedHomeWindowProjectionCancellationRejectsLateEvidence() {
        let fixture =
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionFixture.self
        var snapshot = fixture.finderSnapshot()
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionObservationOwner(
                expectation: fixture.browserExpectation,
                scheduledRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: { snapshot }
            )
        owner.start()
        owner.markSelectionTriggerCompleted()
        owner.cancel()

        snapshot = fixture.browserSnapshot()
        scheduledReadback?(.scheduledReadback)

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSpaceFixtureSelectedHomeWindowProjectionWatchdogReportsFinalEvidence() {
        let fixture =
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionFixture.self
        let owner =
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionObservationOwner(
                expectation: fixture.browserExpectation,
                scheduledRegistration: { _ in
                    FlowTabUITestObservationCancellation {}
                },
                readback: { fixture.finderSnapshot() }
            )
        owner.start()
        defer { owner.cancel() }
        owner.markSelectionTriggerCompleted()

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("source=watchdogReadback")
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("phase=selectionTriggerCompleted")
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "selectedBundleIdentifier=\(fixture.browserAppID)"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("label=Finder Main")
        )
        XCTAssertTrue(owner.diagnosticSummary.contains("waitResult="))
    }

    func testSpaceFixtureSelectedHomeWindowProjectionRejectsReplacedReadbacksUnderPressure() {
        let fixture =
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionFixture.self
        var snapshot = fixture.finderSnapshot()
        var scheduledReadbacks: [
            (FlowTabUITestConditionObservationSource) -> Void
        ] = []
        var cancellationCount = 0
        var readbackCount = 0
        let owner =
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionObservationOwner(
                expectation: fixture.browserExpectation,
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

        let iterations =
            FlowTabUITestSpaceFixtureSelectedHomeWindowProjectionTestPolicy
                .pressureIterations
        for _ in 0..<iterations {
            owner.start()
            owner.markSelectionTriggerCompleted()
        }
        XCTAssertEqual(scheduledReadbacks.count, iterations)

        let readbackCountBeforeStaleEvidence = readbackCount
        for staleReadback in scheduledReadbacks.dropLast() {
            staleReadback(.scheduledReadback)
        }
        XCTAssertEqual(readbackCount, readbackCountBeforeStaleEvidence)

        snapshot = fixture.browserSnapshot()
        scheduledReadbacks.last?(.scheduledReadback)

        XCTAssertEqual(owner.resolvedEvidence?.generation, UInt64(iterations))
        XCTAssertEqual(owner.resolvedEvidence?.source, .scheduledReadback)
        XCTAssertEqual(cancellationCount, iterations)
        owner.cancel()
    }
}
