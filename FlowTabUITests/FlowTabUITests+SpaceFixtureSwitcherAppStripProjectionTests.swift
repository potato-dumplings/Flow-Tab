import Foundation
import XCTest

private enum FlowTabUITestSpaceFixtureSwitcherAppStripProjectionTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 200
}

private enum FlowTabUITestSpaceFixtureSwitcherAppStripProjectionFixture {
    typealias Expectation =
        FlowTabUITestSpaceFixtureSwitcherAppStripProjectionExpectation
    typealias Snapshot =
        FlowTabUITestSpaceFixtureSwitcherAppStripProjectionSnapshot

    static let finder = Expectation.App(
        bundleIdentifier: "com.example.fixture.finder",
        windowCount: 2,
        rowIdentifier: "flowtab.switcher.app.finder"
    )
    static let chrome = Expectation.App(
        bundleIdentifier: "com.example.fixture.chrome",
        windowCount: 2,
        rowIdentifier: "flowtab.switcher.app.chrome"
    )
    static let notes = Expectation.App(
        bundleIdentifier: "com.example.fixture.notes",
        windowCount: 2,
        rowIdentifier: "flowtab.switcher.app.notes"
    )
    static let expectation = Expectation(
        apps: [finder, chrome, notes]
    )

    static let defaultSelectedApp = notes

    static func exactEntries(
        selectedBundleIdentifier: String =
            defaultSelectedApp.bundleIdentifier
    ) -> [String] {
        expectation.apps.map { app in
            app.exactEntry(
                windowCount:
                    app.bundleIdentifier == selectedBundleIdentifier
                        ? app.windowCount
                        : 0
            )
        }
    }

    static func exactEntry(
        for app: Expectation.App,
        selectedBundleIdentifier: String =
            defaultSelectedApp.bundleIdentifier
    ) -> String {
        app.exactEntry(
            windowCount:
                app.bundleIdentifier == selectedBundleIdentifier
                    ? app.windowCount
                    : 0
        )
    }

    static var targetRows: [String] {
        expectation.apps.map(\.rowIdentifier)
    }

    static func readback(
        _ entries: [String],
        selectedBundleIdentifier: String? =
            defaultSelectedApp.bundleIdentifier,
        exists: Bool = true
    ) -> FlowTabUITestSpaceFixtureSwitcherAppStripProjectionReadback {
        let rawValue = exists ? entries.joined(separator: "|") : nil
        return FlowTabUITestSpaceFixtureSwitcherAppStripProjectionReadback(
            appProjection: FlowTabUITestSwitcherAppProjectionReadback(
                snapshot: FlowTabUITestSwitcherAppProjectionSnapshot(
                    applicationState: .runningForeground,
                    identifier: "flowtab.switcher.summary",
                    exists: exists,
                    rawValue: rawValue,
                    entries: exists
                        ? entries.map {
                            FlowTabUITestSwitcherAppProjectionEntry(
                                rawValue: $0
                            )
                        }
                        : []
                )
            ),
            selectedBundleIdentifier: selectedBundleIdentifier
        )
    }

    static func snapshot(
        applicationState: XCUIApplication.State = .runningForeground,
        beforeEntries: [String]? = nil,
        selectedBundleIdentifier: String =
            defaultSelectedApp.bundleIdentifier,
        visibleRows: [String]? = nil,
        afterEntries: [String]? = nil,
        afterSelectedBundleIdentifier: String? = nil,
        exists: Bool = true
    ) -> Snapshot {
        let before =
            beforeEntries
                ?? exactEntries(
                    selectedBundleIdentifier: selectedBundleIdentifier
                ) + ["com.example.other:9"]
        let after = afterEntries ?? before
        return Snapshot(
            applicationState: applicationState,
            projectionBeforeRows: readback(
                before,
                selectedBundleIdentifier: selectedBundleIdentifier,
                exists: exists
            ),
            visibleTargetRowIdentifiers: visibleRows ?? targetRows,
            projectionAfterRows: readback(
                after,
                selectedBundleIdentifier:
                    afterSelectedBundleIdentifier
                        ?? selectedBundleIdentifier,
                exists: exists
            )
        )
    }

    static var partialSnapshot: Snapshot {
        snapshot(
            beforeEntries: [exactEntry(for: finder)],
            visibleRows: [finder.rowIdentifier]
        )
    }
}

extension FlowTabUITests {
    func testSpaceFixtureSwitcherAppStripProjectionPolicy() {
        let watchdog =
            FlowTabUITestSpaceFixtureSwitcherAppStripProjectionPolicy.watchdog
        XCTAssertEqual(watchdog, 8)
        XCTAssertTrue(watchdog.isFinite)
        XCTAssertGreaterThan(watchdog, 0)
    }

    func testSpaceFixtureSwitcherAppStripProjectionRequiresWellFormedExpectation() {
        typealias Expectation =
            FlowTabUITestSpaceFixtureSwitcherAppStripProjectionExpectation
        let fixture =
            FlowTabUITestSpaceFixtureSwitcherAppStripProjectionFixture.self
        XCTAssertTrue(fixture.expectation.isWellFormed)
        XCTAssertFalse(Expectation(apps: []).isWellFormed)
        XCTAssertFalse(
            Expectation(
                apps: [
                    fixture.finder,
                    .init(
                        bundleIdentifier: fixture.finder.bundleIdentifier,
                        windowCount: 3,
                        rowIdentifier: "flowtab.switcher.app.other"
                    )
                ]
            ).isWellFormed
        )
        XCTAssertFalse(
            Expectation(
                apps: [
                    .init(
                        bundleIdentifier: "com.example.invalid",
                        windowCount: 0,
                        rowIdentifier: "flowtab.switcher.app.invalid"
                    )
                ]
            ).isWellFormed
        )
    }

    func testSpaceFixtureSwitcherAppStripProjectionRequiresOneExactSnapshot() {
        let fixture =
            FlowTabUITestSpaceFixtureSwitcherAppStripProjectionFixture.self
        let expectation = fixture.expectation
        XCTAssertTrue(expectation.isSatisfied(by: fixture.snapshot()))
        XCTAssertTrue(
            expectation.isSatisfied(
                by: fixture.snapshot(
                    selectedBundleIdentifier:
                        fixture.finder.bundleIdentifier
                )
            )
        )
        XCTAssertTrue(
            expectation.isSatisfied(
                by: fixture.snapshot(
                    visibleRows: Array(fixture.targetRows.reversed())
                )
            )
        )
        let duplicateRowRepresentations = fixture.snapshot(
            visibleRows: fixture.targetRows + fixture.targetRows
        )
        XCTAssertEqual(
            duplicateRowRepresentations.visibleTargetRowIdentifiers,
            fixture.targetRows.sorted()
        )
        XCTAssertTrue(
            expectation.isSatisfied(by: duplicateRowRepresentations)
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: fixture.snapshot(applicationState: .runningBackground)
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: fixture.snapshot(
                    beforeEntries: [
                        fixture.exactEntry(for: fixture.finder),
                        fixture.exactEntry(for: fixture.chrome),
                        "com.example.fixture.notes:3"
                    ]
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: fixture.snapshot(
                    beforeEntries: fixture.exactEntries()
                        + [fixture.exactEntry(for: fixture.chrome)]
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: fixture.snapshot(
                    beforeEntries: [
                        fixture.exactEntry(for: fixture.finder),
                        "com.example.fixture.chrome.helper:0",
                        fixture.exactEntry(for: fixture.notes)
                    ]
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: fixture.snapshot(
                    beforeEntries: [
                        "com.example.fixture.finder:2",
                        fixture.exactEntry(for: fixture.chrome),
                        fixture.exactEntry(for: fixture.notes)
                    ]
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: fixture.snapshot(
                    visibleRows: Array(fixture.targetRows.dropLast())
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: fixture.snapshot(
                    afterEntries:
                        Array(fixture.exactEntries().dropLast())
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: fixture.snapshot(
                    afterSelectedBundleIdentifier:
                        fixture.finder.bundleIdentifier
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: fixture.snapshot(
                    selectedBundleIdentifier:
                        "com.example.fixture.unknown"
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: fixture.snapshot(exists: false)
            )
        )
    }

    func testSpaceFixtureSwitcherAppStripProjectionAcceptsMatchingInitialState() {
        let fixture =
            FlowTabUITestSpaceFixtureSwitcherAppStripProjectionFixture.self
        var order: [String] = []
        let owner =
            FlowTabUITestSpaceFixtureSwitcherAppStripProjectionObservationOwner(
                expectation: fixture.expectation,
                observationRegistration: { _ in
                    order.append("register")
                    return FlowTabUITestObservationCancellation {
                        order.append("cancel")
                    }
                },
                readback: {
                    order.append("readback")
                    return fixture.snapshot()
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(owner.resolvedEvidence?.source, .initialReadback)
        XCTAssertEqual(order, ["register", "readback", "cancel"])
    }

    func testSpaceFixtureSwitcherAppStripProjectionGatesMatchingBaselineUntilTriggerReturns() {
        let fixture =
            FlowTabUITestSpaceFixtureSwitcherAppStripProjectionFixture.self
        var triggerCompleted = false
        var cancellationCount = 0
        let owner =
            FlowTabUITestSpaceFixtureSwitcherAppStripProjectionObservationOwner(
                expectation: fixture.expectation,
                observationRegistration: { _ in
                    FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                acceptsResolution: { triggerCompleted },
                readback: { fixture.snapshot() }
            )
        owner.start()
        defer { owner.cancel() }
        XCTAssertNil(owner.resolvedEvidence)

        triggerCompleted = true
        owner.requestReadback(source: .triggerReadback)

        XCTAssertEqual(owner.resolvedEvidence?.source, .triggerReadback)
        XCTAssertEqual(owner.resolvedEvidence?.generation, 1)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSpaceFixtureSwitcherAppStripProjectionUsesSlowScheduledEvidence() {
        let fixture =
            FlowTabUITestSpaceFixtureSwitcherAppStripProjectionFixture.self
        var snapshot = fixture.partialSnapshot
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestSpaceFixtureSwitcherAppStripProjectionObservationOwner(
                expectation: fixture.expectation,
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: { snapshot }
            )
        owner.start()
        defer { owner.cancel() }

        for _ in 0..<5 {
            scheduledReadback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }
        snapshot = fixture.snapshot()
        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(owner.resolvedEvidence?.source, .scheduledReadback)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSpaceFixtureSwitcherAppStripProjectionCancellationRejectsLateEvidence() {
        let fixture =
            FlowTabUITestSpaceFixtureSwitcherAppStripProjectionFixture.self
        var snapshot = fixture.partialSnapshot
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestSpaceFixtureSwitcherAppStripProjectionObservationOwner(
                expectation: fixture.expectation,
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: { snapshot }
            )
        owner.start()
        owner.cancel()
        snapshot = fixture.snapshot()
        scheduledReadback?(.scheduledReadback)

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSpaceFixtureSwitcherAppStripProjectionWatchdogReportsFinalEvidence() {
        let fixture =
            FlowTabUITestSpaceFixtureSwitcherAppStripProjectionFixture.self
        let owner =
            FlowTabUITestSpaceFixtureSwitcherAppStripProjectionObservationOwner(
                expectation: fixture.expectation,
                observationRegistration: nil,
                readback: { fixture.partialSnapshot }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSpaceFixtureSwitcherAppStripProjectionTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("source=watchdogReadback")
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "bundleID=\(fixture.chrome.bundleIdentifier)"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(fixture.finder.rowIdentifier)
        )
        XCTAssertTrue(owner.diagnosticSummary.contains("waitResult="))
    }

    func testSpaceFixtureSwitcherAppStripProjectionRejectsReplacedReadbacksUnderPressure() {
        let fixture =
            FlowTabUITestSpaceFixtureSwitcherAppStripProjectionFixture.self
        var snapshot = fixture.partialSnapshot
        var scheduledReadbacks: [
            (FlowTabUITestConditionObservationSource) -> Void
        ] = []
        var cancellationCount = 0
        var readbackCount = 0
        let owner =
            FlowTabUITestSpaceFixtureSwitcherAppStripProjectionObservationOwner(
                expectation: fixture.expectation,
                observationRegistration: { callback in
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
            FlowTabUITestSpaceFixtureSwitcherAppStripProjectionTestPolicy
                .pressureIterations
        for _ in 0..<iterations {
            owner.start()
        }
        XCTAssertEqual(scheduledReadbacks.count, iterations)

        let beforeStaleCallbacks = readbackCount
        for staleReadback in scheduledReadbacks.dropLast() {
            staleReadback(.scheduledReadback)
        }
        XCTAssertEqual(readbackCount, beforeStaleCallbacks)

        snapshot = fixture.snapshot()
        scheduledReadbacks.last?(.scheduledReadback)

        XCTAssertEqual(owner.resolvedEvidence?.generation, UInt64(iterations))
        XCTAssertEqual(owner.resolvedEvidence?.source, .scheduledReadback)
        XCTAssertEqual(cancellationCount, iterations)
        owner.cancel()
    }
}
