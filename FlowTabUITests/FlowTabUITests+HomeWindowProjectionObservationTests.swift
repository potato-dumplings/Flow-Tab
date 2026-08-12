import Foundation
import XCTest

private enum FlowTabUITestHomeWindowProjectionTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testHomeWindowAllTitlesExpectationRequiresCompleteSnapshot() {
        let titles = ["Main", "Child", "Mini Program"]
        let expectation =
            FlowTabUITestHomeWindowProjectionExpectation
                .titlesVisible(titles)

        XCTAssertTrue(
            expectation.isSatisfied(
                by: homeWindowProjectionTestSnapshot(
                    rowTitles: ["Main", "Mini Program"],
                    staticTitles: ["Child"]
                )
            )
        )
        XCTAssertFalse(
            FlowTabUITestHomeWindowProjectionExpectation
                .titlesVisible([])
                .isSatisfied(
                    by: homeWindowProjectionTestSnapshot(
                        rowTitles: [],
                        staticTitles: []
                    )
                )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: homeWindowProjectionTestSnapshot(
                    rowTitles: ["Main", "Child"],
                    staticTitles: []
                )
            )
        )
        XCTAssertEqual(expectation.titles, titles)
        XCTAssertEqual(
            expectation.diagnosticSummary,
            "titlesVisible=\(titles)"
        )
    }

    func testHomeWindowAllTitlesObserverRequiresPostTriggerEvidence() {
        let titles = ["Main", "Child", "Mini Program"]
        var triggerCompleted = false
        var snapshot = homeWindowProjectionTestSnapshot(
            rowTitles: titles,
            staticTitles: []
        )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestHomeWindowProjectionObservationOwner(
                expectation: .titlesVisible(titles),
                acceptsEvidence: { triggerCompleted },
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

        XCTAssertNil(owner.resolvedEvidence)
        triggerCompleted = true
        snapshot = homeWindowProjectionTestSnapshot(
            rowTitles: ["Main", "Child"],
            staticTitles: []
        )
        owner.requestReadback(source: .triggerReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = homeWindowProjectionTestSnapshot(
            rowTitles: ["Main", "Mini Program"],
            staticTitles: ["Child"]
        )
        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .scheduledReadback
        )
        XCTAssertEqual(cancellationCount, 1)
    }

    func testHomeWindowAllTitlesWatchdogReportsFinalProjection() {
        let titles = ["Main", "Child", "Mini Program"]
        var triggerCompleted = false
        let owner =
            FlowTabUITestHomeWindowProjectionObservationOwner(
                expectation: .titlesVisible(titles),
                acceptsEvidence: { triggerCompleted },
                observationRegistration: nil,
                readback: {
                    self.homeWindowProjectionTestSnapshot(
                        rowTitles: ["Main", "Child"],
                        staticTitles: []
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }
        triggerCompleted = true
        owner.requestReadback(source: .triggerReadback)

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestHomeWindowProjectionTestPolicy
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
                "titlesVisible=\(titles)"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("label=Main")
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("waitResult=")
        )
    }

    func testHomeWindowProjectionObserverUsesInitialAndScheduledEvidence() {
        var snapshot = homeWindowProjectionTestSnapshot(
            rowTitle: "Primary Document",
            staticTitles: []
        )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let rowOwner =
            FlowTabUITestHomeWindowProjectionObservationOwner(
                expectation: .rowContaining("primary"),
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: { snapshot }
            )
        rowOwner.start()
        let initialEvidence = rowOwner.waitForResolution(
            timeout:
                FlowTabUITestHomeWindowProjectionTestPolicy
                    .watchdog
        )

        XCTAssertEqual(initialEvidence?.source, .initialReadback)
        XCTAssertEqual(
            initialEvidence?.value.row(
                containing: "primary"
            )?.element,
            "row-element-0"
        )
        XCTAssertEqual(cancellationCount, 1)

        snapshot = homeWindowProjectionTestSnapshot(
            rowTitle: nil,
            staticTitles: []
        )
        let titleOwner =
            FlowTabUITestHomeWindowProjectionObservationOwner(
                expectation: .titleVisible("Settings"),
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: { snapshot }
            )
        titleOwner.start()
        XCTAssertNil(titleOwner.resolvedEvidence)

        snapshot = homeWindowProjectionTestSnapshot(
            rowTitle: nil,
            staticTitles: ["Settings"]
        )
        scheduledReadback?(.scheduledReadback)
        let scheduledEvidence = titleOwner.waitForResolution(
            timeout:
                FlowTabUITestHomeWindowProjectionTestPolicy
                    .watchdog
        )

        XCTAssertEqual(
            scheduledEvidence?.source,
            .scheduledReadback
        )
        XCTAssertEqual(cancellationCount, 2)
        rowOwner.cancel()
        titleOwner.cancel()
    }

    func testHomeWindowProjectionObserverRequiresExactRowLabelPrefixAfterTrigger() {
        var triggerCompleted = false
        var snapshot = homeWindowProjectionTestSnapshot(
            rowTitles: ["Inbox", "Draft", "Archive"],
            staticTitles: []
        )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestHomeWindowProjectionObservationOwner(
                expectation:
                    .rowLabelPrefix(["Draft", "Inbox"]),
                acceptsEvidence: {
                    triggerCompleted
                },
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: { snapshot }
            )
        owner.start()
        XCTAssertNil(owner.resolvedEvidence)

        triggerCompleted = true
        owner.requestReadback(source: .triggerReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = homeWindowProjectionTestSnapshot(
            rowTitles: ["Draft", "Inbox", "Archive"],
            staticTitles: []
        )
        scheduledReadback?(.scheduledReadback)
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestHomeWindowProjectionTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .scheduledReadback)
        XCTAssertEqual(
            evidence?.value.rows.map(\.label),
            ["Draft", "Inbox", "Archive"]
        )
        XCTAssertEqual(cancellationCount, 1)
        owner.cancel()

        XCTAssertFalse(
            FlowTabUITestHomeWindowProjectionExpectation
                .rowLabelPrefix([])
                .isSatisfied(by: snapshot)
        )
    }

    func testHomeWindowProjectionObserverRequiresPostTriggerExactRowEvidence() {
        var triggerCompleted = false
        let snapshot = homeWindowProjectionTestSnapshot(
            rowTitle: "Mail",
            staticTitles: []
        )
        var cancellationCount = 0
        let owner =
            FlowTabUITestHomeWindowProjectionObservationOwner(
                expectation: .rowContaining("Mail"),
                acceptsEvidence: {
                    triggerCompleted
                },
                observationRegistration: { _ in
                    FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: { snapshot }
            )
        owner.start()

        XCTAssertNil(owner.resolvedEvidence)
        triggerCompleted = true
        owner.requestReadback(source: .triggerReadback)
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestHomeWindowProjectionTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .triggerReadback)
        XCTAssertEqual(
            evidence?.value.row(containing: "Mail")?.element,
            "row-element-0"
        )
        XCTAssertEqual(cancellationCount, 1)
        owner.cancel()
    }

    func testHomeWindowProjectionSlowSchedulingOnlyDelaysResolution() {
        var triggerCompleted = false
        var snapshot = homeWindowProjectionTestSnapshot(
            rowTitle: nil,
            staticTitles: []
        )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let owner =
            FlowTabUITestHomeWindowProjectionObservationOwner(
                expectation: .rowContaining("Draft"),
                acceptsEvidence: { triggerCompleted },
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )
        owner.start()
        defer { owner.cancel() }

        triggerCompleted = true
        owner.requestReadback(source: .triggerReadback)
        for _ in 0..<5 {
            scheduledReadback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }

        snapshot = homeWindowProjectionTestSnapshot(
            rowTitle: "Draft",
            staticTitles: []
        )
        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(owner.resolvedEvidence?.source, .scheduledReadback)
        XCTAssertEqual(
            owner.resolvedEvidence?.value.row(
                containing: "Draft"
            )?.element,
            "row-element-0"
        )
    }

    func testHomeWindowProjectionObserverLifecycleUnderPressure() {
        for iteration in 0..<FlowTabUITestHomeWindowProjectionTestPolicy
            .pressureIterations
        {
            var snapshot = homeWindowProjectionTestSnapshot(
                rowTitle: iteration.isMultiple(of: 2)
                    ? nil
                    : "Other App",
                staticTitles: []
            )
            var scheduledReadback:
                ((FlowTabUITestConditionObservationSource) -> Void)?
            var cancellationCount = 0
            var readbackCount = 0
            let owner =
                FlowTabUITestHomeWindowProjectionObservationOwner(
                    expectation: .titlesAbsent(["Other App"]),
                    observationRegistration: { callback in
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

            if !iteration.isMultiple(of: 2) {
                XCTAssertNil(owner.resolvedEvidence)
                snapshot = homeWindowProjectionTestSnapshot(
                    rowTitle: nil,
                    staticTitles: []
                )
                scheduledReadback?(.scheduledReadback)
            }
            let evidence = owner.waitForResolution(
                timeout:
                    FlowTabUITestHomeWindowProjectionTestPolicy
                        .watchdog
            )
            let resolvedReadbackCount = readbackCount
            scheduledReadback?(.scheduledReadback)

            XCTAssertNotNil(evidence, "iteration=\(iteration)")
            XCTAssertEqual(readbackCount, resolvedReadbackCount)
            XCTAssertEqual(cancellationCount, 1)
            owner.cancel()
        }

        var cancelledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancelledReadbackCount = 0
        let cancelledOwner =
            FlowTabUITestHomeWindowProjectionObservationOwner(
                expectation: .titleVisible("Never Visible"),
                observationRegistration: { callback in
                    cancelledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    cancelledReadbackCount += 1
                    return self.homeWindowProjectionTestSnapshot(
                        rowTitle: nil,
                        staticTitles: []
                    )
                }
            )
        cancelledOwner.start()
        cancelledOwner.cancel()
        cancelledReadback?(.scheduledReadback)
        XCTAssertEqual(cancelledReadbackCount, 1)
    }

    private func homeWindowProjectionTestSnapshot(
        rowTitle: String?,
        staticTitles: [String]
    ) -> FlowTabUITestHomeWindowProjectionSnapshot<String> {
        homeWindowProjectionTestSnapshot(
            rowTitles: rowTitle.map { [$0] } ?? [],
            staticTitles: staticTitles
        )
    }

    private func homeWindowProjectionTestSnapshot(
        rowTitles: [String],
        staticTitles: [String]
    ) -> FlowTabUITestHomeWindowProjectionSnapshot<String> {
        let rows = rowTitles.enumerated().map { index, title in
            FlowTabUITestHomeWindowRowSnapshot(
                identifier: "flowtab.home.window.test.\(index)",
                label: title,
                value: title,
                element: "row-element-\(index)"
            )
        }
        return FlowTabUITestHomeWindowProjectionSnapshot(
            rows: rows,
            visibleStaticTextTitles: staticTitles
        )
    }
}
