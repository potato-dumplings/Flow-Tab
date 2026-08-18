import Foundation
import XCTest

private enum FlowTabUITestSpaceFixtureHomeAppInventoryTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 200
}

private enum FlowTabUITestSpaceFixtureHomeAppInventoryTestFixture {
    static let browserIdentifier = "flowtab.home.app.browser"
    static let mailIdentifier = "flowtab.home.app.mail"
    static let fullscreenIdentifier = "flowtab.home.app.fullscreen"

    static let standardExpectation =
        FlowTabUITestSpaceFixtureHomeAppInventoryExpectation(
            visibleRows: [
                .init(identifier: browserIdentifier, value: "1w"),
                .init(identifier: mailIdentifier, value: "3w")
            ]
        )
    static let fullscreenExpectation =
        FlowTabUITestSpaceFixtureHomeAppInventoryExpectation(
            visibleRows: [
                .init(identifier: browserIdentifier, value: "1w"),
                .init(identifier: fullscreenIdentifier, value: "1w")
            ]
        )

    static func standardSnapshot(
        state: XCUIApplication.State = .runningForeground,
        countBefore: String? = "2 apps",
        totalVisibleRowCount: Int = 2,
        visibleRows: [
            FlowTabUITestSpaceFixtureHomeAppInventorySnapshot.Row
        ] = [
            .init(identifier: browserIdentifier, value: "1w"),
            .init(identifier: mailIdentifier, value: "3w")
        ],
        countAfter: String? = "2 apps"
    ) -> FlowTabUITestSpaceFixtureHomeAppInventorySnapshot {
        .init(
            applicationState: state,
            appCountLabelBeforeRows: countBefore,
            totalVisibleRowCount: totalVisibleRowCount,
            visibleRows: visibleRows,
            appCountLabelAfterRows: countAfter
        )
    }

    static func fullscreenSnapshot(
        countBefore: String? = "2 apps",
        totalVisibleRowCount: Int = 2,
        visibleRows: [
            FlowTabUITestSpaceFixtureHomeAppInventorySnapshot.Row
        ] = [
            .init(identifier: browserIdentifier, value: "1w"),
            .init(identifier: fullscreenIdentifier, value: "1w")
        ],
        countAfter: String? = "2 apps"
    ) -> FlowTabUITestSpaceFixtureHomeAppInventorySnapshot {
        .init(
            applicationState: .runningForeground,
            appCountLabelBeforeRows: countBefore,
            totalVisibleRowCount: totalVisibleRowCount,
            visibleRows: visibleRows,
            appCountLabelAfterRows: countAfter
        )
    }
}

extension FlowTabUITests {
    func testSpaceFixtureHomeAppInventoryPolicyCompatibility() {
        let policy = FlowTabUITestSpaceFixtureHomeAppInventoryPolicy.self
        XCTAssertEqual(policy.perAppCompatibilityWatchdog, 20)
        XCTAssertEqual(policy.watchdog(appCount: 3), 60)
        XCTAssertEqual(policy.watchdog(appCount: 2), 40)
        XCTAssertEqual(policy.watchdog(appCount: 0), 20)
        XCTAssertTrue(policy.watchdog(appCount: 3).isFinite)
        XCTAssertGreaterThan(policy.watchdog(appCount: 3), 0)
    }

    func testSpaceFixtureHomeAppInventoryParsesLocalizedCountEvidence() {
        let snapshot = FlowTabUITestSpaceFixtureHomeAppInventorySnapshot.self
        XCTAssertEqual(snapshot.appCount(from: "2 apps"), 2)
        XCTAssertEqual(snapshot.appCount(from: "2 个应用"), 2)
        XCTAssertEqual(snapshot.appCount(from: "12 apps"), 12)
        XCTAssertNil(snapshot.appCount(from: nil))
        XCTAssertNil(snapshot.appCount(from: "apps"))
        XCTAssertNil(snapshot.appCount(from: "2 of 3 apps"))
    }

    func testSpaceFixtureHomeAppInventoryRequiresWellFormedEvidence() {
        let fixture =
            FlowTabUITestSpaceFixtureHomeAppInventoryTestFixture.self
        XCTAssertTrue(fixture.standardExpectation.isWellFormed)
        XCTAssertTrue(fixture.fullscreenExpectation.isWellFormed)
        XCTAssertFalse(
            FlowTabUITestSpaceFixtureHomeAppInventoryExpectation(
                visibleRows: []
            ).isWellFormed
        )
        XCTAssertFalse(
            FlowTabUITestSpaceFixtureHomeAppInventoryExpectation(
                visibleRows: [
                    .init(identifier: fixture.browserIdentifier, value: "1w"),
                    .init(identifier: fixture.browserIdentifier, value: "2w")
                ]
            ).isWellFormed
        )
        XCTAssertFalse(
            FlowTabUITestSpaceFixtureHomeAppInventoryExpectation(
                visibleRows: [
                    .init(identifier: "", value: "1w")
                ]
            ).isWellFormed
        )
    }

    func testSpaceFixtureHomeAppInventoryRequiresOneCompleteStandardSnapshot() {
        let fixture =
            FlowTabUITestSpaceFixtureHomeAppInventoryTestFixture.self
        let expectation = fixture.standardExpectation
        XCTAssertTrue(
            expectation.isSatisfied(by: fixture.standardSnapshot())
        )
        XCTAssertTrue(
            expectation.isSatisfied(
                by: fixture.standardSnapshot(
                    visibleRows: [
                        .init(identifier: fixture.mailIdentifier, value: "3w"),
                        .init(identifier: fixture.browserIdentifier, value: "1w")
                    ]
                )
            )
        )
        XCTAssertTrue(
            expectation.isSatisfied(
                by: fixture.standardSnapshot(
                    countBefore: "16 个应用",
                    totalVisibleRowCount: 16,
                    countAfter: "16 个应用"
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: fixture.standardSnapshot(state: .runningBackground)
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: fixture.standardSnapshot(countBefore: "1 app")
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: fixture.standardSnapshot(countAfter: "3 apps")
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: fixture.standardSnapshot(
                    visibleRows: [
                        .init(identifier: fixture.browserIdentifier, value: "1w")
                    ]
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: fixture.standardSnapshot(
                    visibleRows: [
                        .init(
                            identifier: fixture.browserIdentifier,
                            exists: false,
                            value: nil
                        ),
                        .init(identifier: fixture.mailIdentifier, value: "3w")
                    ]
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: fixture.standardSnapshot(
                    visibleRows: [
                        .init(identifier: fixture.browserIdentifier, value: "1w"),
                        .init(identifier: fixture.browserIdentifier, value: "1w")
                    ]
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: fixture.standardSnapshot(
                    visibleRows: [
                        .init(identifier: fixture.browserIdentifier, value: "1w"),
                        .init(identifier: fixture.mailIdentifier, value: "2w")
                    ]
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: fixture.standardSnapshot(
                    visibleRows: [
                        .init(identifier: fixture.browserIdentifier, value: "1w"),
                        .init(identifier: fixture.mailIdentifier, value: "3w"),
                        .init(identifier: fixture.fullscreenIdentifier, value: "1w")
                    ]
                )
            )
        )
    }

    func testSpaceFixtureHomeAppInventoryRequiresFullscreenVisibility() {
        let fixture =
            FlowTabUITestSpaceFixtureHomeAppInventoryTestFixture.self
        let expectation = fixture.fullscreenExpectation
        XCTAssertTrue(
            expectation.isSatisfied(by: fixture.fullscreenSnapshot())
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: fixture.fullscreenSnapshot(
                    visibleRows: [
                        .init(identifier: fixture.browserIdentifier, value: "1w"),
                        .init(
                            identifier: fixture.fullscreenIdentifier,
                            exists: false,
                            value: nil
                        )
                    ]
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: fixture.fullscreenSnapshot(
                    visibleRows: [
                        .init(identifier: fixture.browserIdentifier, value: "1w"),
                        .init(identifier: "flowtab.home.app.other", value: "1w")
                    ]
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: fixture.fullscreenSnapshot(countAfter: "1 app")
            )
        )
    }

    func testSpaceFixtureHomeAppInventoryGatesInitiallyMatchingEvidence() {
        let fixture =
            FlowTabUITestSpaceFixtureHomeAppInventoryTestFixture.self
        var registrationCount = 0
        let owner =
            FlowTabUITestSpaceFixtureHomeAppInventoryObservationOwner(
                expectation: fixture.standardExpectation,
                scheduledRegistration: { _ in
                    registrationCount += 1
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { fixture.standardSnapshot() }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(owner.latestEvidence?.source, .initialReadback)
        XCTAssertNil(owner.resolvedEvidence)
        owner.markHomeNavigationCompleted()
        owner.markHomeNavigationCompleted()

        XCTAssertEqual(owner.resolvedEvidence?.source, .triggerReadback)
        XCTAssertEqual(owner.resolvedEvidence?.generation, 1)
        XCTAssertEqual(registrationCount, 0)
    }

    func testSpaceFixtureHomeAppInventoryUsesDelayedScheduledEvidence() {
        let fixture =
            FlowTabUITestSpaceFixtureHomeAppInventoryTestFixture.self
        var snapshot = fixture.standardSnapshot(countAfter: "1 app")
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestSpaceFixtureHomeAppInventoryObservationOwner(
                expectation: fixture.standardExpectation,
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
        owner.markHomeNavigationCompleted()

        XCTAssertNil(owner.resolvedEvidence)
        snapshot = fixture.standardSnapshot()
        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(owner.resolvedEvidence?.source, .scheduledReadback)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSpaceFixtureHomeAppInventorySlowSchedulingOnlyDelaysResult() {
        let fixture =
            FlowTabUITestSpaceFixtureHomeAppInventoryTestFixture.self
        var snapshot = fixture.standardSnapshot(countBefore: "1 app")
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let owner =
            FlowTabUITestSpaceFixtureHomeAppInventoryObservationOwner(
                expectation: fixture.standardExpectation,
                scheduledRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )
        owner.start()
        defer { owner.cancel() }
        owner.markHomeNavigationCompleted()

        for _ in 0..<5 {
            scheduledReadback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }
        snapshot = fixture.standardSnapshot()
        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(owner.resolvedEvidence?.source, .scheduledReadback)
        XCTAssertEqual(owner.resolvedEvidence?.value, snapshot)
    }

    func testSpaceFixtureHomeAppInventoryCancellationRejectsLateEvidence() {
        let fixture =
            FlowTabUITestSpaceFixtureHomeAppInventoryTestFixture.self
        var snapshot = fixture.fullscreenSnapshot(
            visibleRows: [
                .init(identifier: fixture.browserIdentifier, value: "1w"),
                .init(
                    identifier: fixture.fullscreenIdentifier,
                    exists: false,
                    value: nil
                )
            ]
        )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestSpaceFixtureHomeAppInventoryObservationOwner(
                expectation: fixture.fullscreenExpectation,
                scheduledRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: { snapshot }
            )
        owner.start()
        owner.markHomeNavigationCompleted()
        owner.cancel()

        snapshot = fixture.fullscreenSnapshot()
        scheduledReadback?(.scheduledReadback)

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSpaceFixtureHomeAppInventoryWatchdogReportsFinalEvidence() {
        let fixture =
            FlowTabUITestSpaceFixtureHomeAppInventoryTestFixture.self
        let owner =
            FlowTabUITestSpaceFixtureHomeAppInventoryObservationOwner(
                expectation: fixture.fullscreenExpectation,
                scheduledRegistration: { _ in
                    FlowTabUITestObservationCancellation {}
                },
                readback: {
                    fixture.fullscreenSnapshot(
                        visibleRows: [
                            .init(
                                identifier: fixture.browserIdentifier,
                                value: "1w"
                            ),
                            .init(
                                identifier: fixture.fullscreenIdentifier,
                                exists: false,
                                value: nil
                            )
                        ],
                        countAfter: "3 apps"
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }
        owner.markHomeNavigationCompleted()

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSpaceFixtureHomeAppInventoryTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("source=watchdogReadback")
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("phase=homeNavigationCompleted")
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("countAfter=Optional(\"3 apps\")")
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                fixture.fullscreenIdentifier + "{exists=0"
            )
        )
        XCTAssertTrue(owner.diagnosticSummary.contains("waitResult="))
    }

    func testSpaceFixtureHomeAppInventoryRejectsReplacedReadbacksUnderPressure() {
        let fixture =
            FlowTabUITestSpaceFixtureHomeAppInventoryTestFixture.self
        var snapshot = fixture.standardSnapshot(countAfter: "1 app")
        var scheduledReadbacks: [
            (FlowTabUITestConditionObservationSource) -> Void
        ] = []
        var cancellationCount = 0
        var readbackCount = 0
        let owner =
            FlowTabUITestSpaceFixtureHomeAppInventoryObservationOwner(
                expectation: fixture.standardExpectation,
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
            0..<FlowTabUITestSpaceFixtureHomeAppInventoryTestPolicy
                .pressureIterations
        {
            owner.start()
            owner.markHomeNavigationCompleted()
        }
        let iterations =
            FlowTabUITestSpaceFixtureHomeAppInventoryTestPolicy
                .pressureIterations
        XCTAssertEqual(scheduledReadbacks.count, iterations)

        let readbackCountBeforeStaleEvidence = readbackCount
        for staleReadback in scheduledReadbacks.dropLast() {
            staleReadback(.scheduledReadback)
        }
        XCTAssertEqual(readbackCount, readbackCountBeforeStaleEvidence)

        snapshot = fixture.standardSnapshot()
        scheduledReadbacks.last?(.scheduledReadback)

        XCTAssertEqual(owner.resolvedEvidence?.generation, UInt64(iterations))
        XCTAssertEqual(owner.resolvedEvidence?.source, .scheduledReadback)
        XCTAssertEqual(cancellationCount, iterations)
        owner.cancel()
    }
}
