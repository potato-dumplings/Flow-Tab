import XCTest

private enum FlowTabUITestCommittedSearchResultRowsTestPolicy {
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testSwitcherSearchResultPolicyUsesNamedMultiAppAppSearchWatchdog() {
        let watchdog =
            FlowTabUITestSwitcherSearchResultObservationPolicy
            .multiAppAppSearchResultPublicationWatchdog

        XCTAssertEqual(watchdog, 8)
        XCTAssertTrue(watchdog.isFinite && watchdog > 0)
    }

    func testCommittedSearchResultRowsRequireUniqueProjectionIdentities() {
        let first = FlowTabUITestSwitcherSearchExpectedResultRow(
            resultID: "app:com.example.first",
            rowIdentifier: "search.app.first"
        )
        let second = FlowTabUITestSwitcherSearchExpectedResultRow(
            resultID: "app:com.example.second",
            rowIdentifier: "search.app.second"
        )

        XCTAssertFalse(
            FlowTabUITestSwitcherSearchExpectedResultRow
                .formsValidProjection([])
        )
        XCTAssertTrue(
            FlowTabUITestSwitcherSearchExpectedResultRow
                .formsValidProjection([first, second])
        )
        XCTAssertFalse(
            FlowTabUITestSwitcherSearchExpectedResultRow
                .formsValidProjection([
                    first,
                    .init(
                        resultID: first.resultID,
                        rowIdentifier: second.rowIdentifier
                    )
                ])
        )
        XCTAssertFalse(
            FlowTabUITestSwitcherSearchExpectedResultRow
                .formsValidProjection([
                    first,
                    .init(
                        resultID: second.resultID,
                        rowIdentifier: first.rowIdentifier
                    )
                ])
        )
    }

    func testCommittedSearchResultRowsClassifyMatchingBaselineAsStale() {
        let rows = committedSearchResultRowsTestExpectations()
        let expectation =
            FlowTabUITestSwitcherSearchResultExpectation
                .committedResultRows(
                    scope: "app",
                    query: "cs",
                    rows: rows
                )
        func snapshot(
            scope: String = "app",
            query: String = "cs",
            resultIDs: [String]? = nil
        ) -> FlowTabUITestSwitcherSearchResultSnapshot {
            FlowTabUITestSwitcherSearchResultSnapshot(
                results: [],
                resultsScope: scope,
                resultsQuery: query,
                committedResultIDs:
                    resultIDs ?? rows.map(\.resultID)
            )
        }

        XCTAssertTrue(
            expectation.hasCommittedIdentity(
                in: snapshot()
            )
        )
        XCTAssertFalse(
            expectation.hasCommittedIdentity(
                in: snapshot(scope: "window")
            )
        )
        XCTAssertFalse(
            expectation.hasCommittedIdentity(
                in: snapshot(query: "stale")
            )
        )
        XCTAssertFalse(
            expectation.hasCommittedIdentity(
                in: snapshot(
                    resultIDs: [rows[0].resultID]
                )
            )
        )
    }

    func testCommittedSearchResultRowsRequireOneAtomicProjection() {
        let rows = committedSearchResultRowsTestExpectations()
        let expectation =
            FlowTabUITestSwitcherSearchResultExpectation
                .committedResultRows(
                    scope: "app",
                    query: "cs",
                    rows: rows
                )
        let visibleRowsWithoutCompleteResults =
            FlowTabUITestSwitcherSearchResultSnapshot(
                results: [],
                resultsScope: "app",
                resultsQuery: "cs",
                committedResultIDs: [rows[0].resultID],
                observedRowIdentifiers:
                    rows.map(\.rowIdentifier),
                applicationState: .runningForeground
            )
        let completeResultsWithPartialRows =
            FlowTabUITestSwitcherSearchResultSnapshot(
                results: [],
                resultsScope: "app",
                resultsQuery: "cs",
                committedResultIDs: rows.map(\.resultID),
                observedRowIdentifiers: [rows[0].rowIdentifier],
                applicationState: .runningForeground
            )
        let completeProjection =
            FlowTabUITestSwitcherSearchResultSnapshot(
                results: [],
                resultsScope: "app",
                resultsQuery: "cs",
                committedResultIDs:
                    rows.reversed().map(\.resultID),
                observedRowIdentifiers:
                    rows.reversed().map(\.rowIdentifier),
                applicationState: .runningForeground
            )

        XCTAssertFalse(
            expectation.isSatisfied(
                by: visibleRowsWithoutCompleteResults
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: completeResultsWithPartialRows
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: .init(
                    results: [],
                    resultsScope: "app",
                    resultsQuery: "cs",
                    committedResultIDs:
                        rows.map(\.resultID),
                    observedRowIdentifiers: [
                        rows[0].rowIdentifier,
                        rows[0].rowIdentifier
                    ],
                    applicationState: .runningForeground
                )
            )
        )
        XCTAssertTrue(
            expectation.isSatisfied(by: completeProjection)
        )
    }

    func testCommittedSearchResultRowsAcceptEmptyQueryAfterTrigger() {
        let rows = committedSearchResultRowsTestExpectations()
        let expectation =
            FlowTabUITestSwitcherSearchResultExpectation
                .committedResultRows(
                    scope: "app",
                    query: "",
                    rows: rows
                )
        var acceptsEvidence = false
        var snapshot =
            FlowTabUITestSwitcherSearchResultSnapshot(
                results: [],
                applicationState: .notRunning
            )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let owner =
            FlowTabUITestSwitcherSearchResultObservationOwner(
                expectation: expectation,
                acceptsEvidence: {
                    acceptsEvidence
                },
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    snapshot
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(
            owner.latestSnapshot?.applicationState,
            .notRunning
        )
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = FlowTabUITestSwitcherSearchResultSnapshot(
            results: [],
            resultsScope: "app",
            resultsQuery: "",
            committedResultIDs: rows.map(\.resultID),
            observedRowIdentifiers:
                rows.reversed().map(\.rowIdentifier),
            applicationState: .runningForeground
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        acceptsEvidence = true
        owner.requestReadback(source: .triggerReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .triggerReadback
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value.resultsQuery,
            ""
        )
        XCTAssertEqual(
            Set(
                owner.resolvedEvidence?.value
                    .observedRowIdentifiers ?? []
            ),
            Set(rows.map(\.rowIdentifier))
        )
    }

    func testCommittedSearchResultRowsRejectStaleGenerationsUnderPressure() {
        let rows = committedSearchResultRowsTestExpectations()
        let expectation =
            FlowTabUITestSwitcherSearchResultExpectation
                .committedResultRows(
                    scope: "app",
                    query: "cs",
                    rows: rows
                )
        for _ in 0..<FlowTabUITestCommittedSearchResultRowsTestPolicy
            .pressureIterations
        {
            var callbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            var snapshot =
                FlowTabUITestSwitcherSearchResultSnapshot(
                    results: [],
                    resultsScope: "app",
                    resultsQuery: "",
                    committedResultIDs: []
                )
            let owner =
                FlowTabUITestSwitcherSearchResultObservationOwner(
                    expectation: expectation,
                    observationRegistration: { callback in
                        callbacks.append(callback)
                        return FlowTabUITestObservationCancellation {}
                    },
                    readback: {
                        snapshot
                    }
                )
            owner.start()
            let staleReadback = callbacks[0]
            owner.cancel()
            owner.start()

            snapshot =
                FlowTabUITestSwitcherSearchResultSnapshot(
                    results: [],
                    resultsScope: "app",
                    resultsQuery: "cs",
                    committedResultIDs: rows.map(\.resultID),
                    observedRowIdentifiers: [
                        rows[0].rowIdentifier
                    ],
                    applicationState: .runningForeground
                )
            staleReadback(.scheduledReadback)
            callbacks[1](.scheduledReadback)
            callbacks[1](.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)

            snapshot =
                FlowTabUITestSwitcherSearchResultSnapshot(
                    results: [],
                    resultsScope: "app",
                    resultsQuery: "cs",
                    committedResultIDs: rows.map(\.resultID),
                    observedRowIdentifiers:
                        rows.reversed().map(\.rowIdentifier),
                    applicationState: .runningForeground
                )
            callbacks[1](.scheduledReadback)
            XCTAssertEqual(
                owner.resolvedEvidence?.generation,
                2
            )
            owner.cancel()
        }
    }

    private func committedSearchResultRowsTestExpectations()
        -> [FlowTabUITestSwitcherSearchExpectedResultRow]
    {
        [
            FlowTabUITestSwitcherSearchExpectedResultRow(
                resultID: "app:com.xxx.csgo",
                rowIdentifier: "search.app.csgo"
            ),
            FlowTabUITestSwitcherSearchExpectedResultRow(
                resultID: "app:com.xxx.test",
                rowIdentifier: "search.app.test"
            )
        ]
    }
}
