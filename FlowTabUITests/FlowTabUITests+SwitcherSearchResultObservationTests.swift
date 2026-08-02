import Foundation
import XCTest

private enum FlowTabUITestSwitcherSearchResultTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testSwitcherSearchResultDiagnosticsParserPreservesExactWindowIdentity() {
        let resultID =
            "window:com.example.chrome#123"
        let rawProjection = [
            [
                "window%3Acom.example.chrome%23123",
                "window",
                "com.example.chrome",
                "cg%3A123",
                "Shared%20Docs",
                "Chrome%20Fixture"
            ].joined(separator: ","),
            [
                "window%3Acom.example.chrome%23123",
                "window",
                "com.example.chrome",
                "cg%3A123",
                "Shared%20Docs",
                "Chrome%20Fixture"
            ].joined(separator: ","),
            [
                "app%3Acom.example.chrome",
                "app",
                "com.example.chrome",
                "",
                "Chrome%20Fixture",
                ""
            ].joined(separator: ",")
        ].joined(separator: "|")

        let results = searchWindowResultObservations(
            inDiagnosticsProjection: rawProjection
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.resultID, resultID)
        XCTAssertEqual(results.first?.appID, "com.example.chrome")
        XCTAssertEqual(results.first?.windowID, "cg:123")
        XCTAssertEqual(results.first?.title, "Shared Docs")
        XCTAssertEqual(results.first?.appName, "Chrome Fixture")
        XCTAssertEqual(
            results.first?.identifier,
            "flowtab.switcher.search.window."
                + resultID
                    .flowTabUITestAccessibilityIdentifierComponent
        )
    }

    func testSwitcherSearchResultObserverAcceptsMatchingInitialWindow() {
        let expectation =
            FlowTabUITestSwitcherSearchResultExpectation
                .matchingWindow(
                    title: "Report",
                    appName: "Browser"
                )
        let owner =
            FlowTabUITestSwitcherSearchResultObservationOwner(
                expectation: expectation,
                observationRegistration: nil,
                readback: {
                    self.switcherSearchResultTestSnapshot(
                        [
                            self.switcherSearchResultTestObservation(
                                resultID: "window:42",
                                title: "Report",
                                appName: "Browser",
                                appID: "com.example.browser"
                            )
                        ]
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .initialReadback
        )
        XCTAssertEqual(
            expectation.matchingResult(
                in: owner.resolvedEvidence?.value
                    ?? switcherSearchResultTestSnapshot([])
            )?.resultID,
            "window:42"
        )
    }

    func testSwitcherSearchResultObserverRequiresCommittedQueryAfterTrigger() {
        let expectation =
            FlowTabUITestSwitcherSearchResultExpectation
                .committedMatchingWindow(
                    scope: "window",
                    query: "Docs",
                    title: "Docs",
                    appName: "Browser"
                )
        let matchingResult =
            switcherSearchResultTestObservation(
                resultID: "window:42",
                title: "Docs",
                appName: "Browser",
                appID: "com.example.browser"
            )
        var acceptsEvidence = false
        var snapshot = switcherSearchResultTestSnapshot(
            [matchingResult],
            resultsScope: "window",
            resultsQuery: "Docs"
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

        XCTAssertNil(owner.resolvedEvidence)
        acceptsEvidence = true
        snapshot = switcherSearchResultTestSnapshot(
            [matchingResult],
            resultsScope: "window",
            resultsQuery: "stale"
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = switcherSearchResultTestSnapshot(
            [matchingResult],
            resultsScope: "window",
            resultsQuery: "Docs"
        )
        owner.requestReadback(source: .triggerReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .triggerReadback
        )
        XCTAssertEqual(
            expectation.matchingResult(
                in: owner.resolvedEvidence?.value
                    ?? switcherSearchResultTestSnapshot([])
            )?.resultID,
            "window:42"
        )
    }

    func testSwitcherSearchResultObserverMatchesFallbackAccessibilityText() {
        let owner =
            FlowTabUITestSwitcherSearchResultObservationOwner(
                expectation:
                    .matchingWindow(
                        title: "report",
                        appName: "browser"
                    ),
                observationRegistration: nil,
                readback: {
                    self.switcherSearchResultTestSnapshot(
                        [
                            SwitcherSearchWindowResultObservation(
                                identifier: "search.window.42",
                                searchableText:
                                    "Quarterly Report\nBrowser"
                            )
                        ]
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .initialReadback
        )
    }

    func testSwitcherSearchResultObserverWaitsForCompleteAppProjection() {
        let expectation =
            FlowTabUITestSwitcherSearchResultExpectation
                .appWindowSet(
                    appID: "com.example.browser",
                    expectedTitles: ["Primary", "Secondary"],
                    expectedCount: 2
                )
        var results = [
            switcherSearchResultTestObservation(
                resultID: "window:1",
                title: "Primary",
                appName: "Browser",
                appID: "com.example.browser"
            )
        ]
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let owner =
            FlowTabUITestSwitcherSearchResultObservationOwner(
                expectation: expectation,
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    self.switcherSearchResultTestSnapshot(results)
                }
            )
        owner.start()
        defer { owner.cancel() }
        XCTAssertNil(owner.resolvedEvidence)

        results.append(
            switcherSearchResultTestObservation(
                resultID: "window:2",
                title: "Secondary",
                appName: "Browser",
                appID: "com.example.browser"
            )
        )
        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .scheduledReadback
        )
    }

    func testSwitcherSearchResultObserverAllowsNoisySiblingRows() {
        let expectation =
            FlowTabUITestSwitcherSearchResultExpectation
                .appWindowSet(
                    appID: "com.example.browser",
                    expectedTitles: ["Primary"],
                    expectedCount: nil
                )
        let owner =
            FlowTabUITestSwitcherSearchResultObservationOwner(
                expectation: expectation,
                observationRegistration: nil,
                readback: {
                    self.switcherSearchResultTestSnapshot(
                        [
                            self.switcherSearchResultTestObservation(
                                resultID: "window:1",
                                title: "Primary",
                                appName: "Browser",
                                appID: "com.example.browser"
                            ),
                            self.switcherSearchResultTestObservation(
                                resultID: "window:2",
                                title: "System Panel",
                                appName: "Browser",
                                appID: "com.example.browser"
                            ),
                            self.switcherSearchResultTestObservation(
                                resultID: "window:3",
                                title: "Message",
                                appName: "Mail",
                                appID: "com.example.mail"
                            )
                        ]
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .initialReadback
        )
    }

    func testSwitcherSearchResultObserverRequiresFreshCommittedExactIdentifiers() {
        let expectation =
            FlowTabUITestSwitcherSearchResultExpectation
                .exactWindowIdentifiers(
                    scope: "window",
                    query: "Shared Docs",
                    identifierFragment: "browser",
                    expectedCount: 2
                )
        let matchingResults = [
            switcherSearchResultTestObservation(
                resultID: "window:browser-1",
                title: "Shared Docs",
                appName: "Browser",
                appID: "com.example.browser"
            ),
            switcherSearchResultTestObservation(
                resultID: "window:browser-2",
                title: "Shared Docs",
                appName: "Browser",
                appID: "com.example.browser"
            )
        ]
        var acceptsEvidence = false
        var snapshot = switcherSearchResultTestSnapshot(
            matchingResults,
            resultsScope: "window",
            resultsQuery: "Shared Docs"
        )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestSwitcherSearchResultObservationOwner(
                expectation: expectation,
                acceptsEvidence: {
                    acceptsEvidence
                },
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    snapshot
                }
            )
        owner.start()

        XCTAssertNil(owner.resolvedEvidence)
        acceptsEvidence = true
        snapshot = switcherSearchResultTestSnapshot(
            matchingResults,
            resultsScope: "window",
            resultsQuery: "stale"
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = switcherSearchResultTestSnapshot(
            matchingResults,
            resultsScope: "app",
            resultsQuery: "Shared Docs"
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = switcherSearchResultTestSnapshot(
            [matchingResults[0], matchingResults[0]],
            resultsScope: "window",
            resultsQuery: "Shared Docs"
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = switcherSearchResultTestSnapshot(
            [
                matchingResults[0],
                switcherSearchResultTestObservation(
                    resultID: "window:mail-1",
                    title: "Shared Docs",
                    appName: "Mail",
                    appID: "com.example.mail"
                )
            ],
            resultsScope: "window",
            resultsQuery: "Shared Docs"
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        let matchingSnapshot =
            switcherSearchResultTestSnapshot(
                matchingResults,
                resultsScope: "window",
                resultsQuery: "Shared Docs"
            )
        snapshot = matchingSnapshot
        owner.requestReadback(source: .triggerReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .triggerReadback
        )
        XCTAssertEqual(
            expectation.matchingIdentifiers(
                in: owner.resolvedEvidence?.value
                    ?? switcherSearchResultTestSnapshot([])
            ),
            matchingResults.map(\.identifier)
        )
        XCTAssertEqual(cancellationCount, 1)
        owner.cancel()
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSwitcherSearchResultObserverSchedulerDelayOnlyDefersExactEvidence() {
        let expectation =
            FlowTabUITestSwitcherSearchResultExpectation
                .exactWindowIdentifiers(
                    scope: "window",
                    query: "punctuation",
                    identifierFragment: "chrome",
                    expectedCount: 1
                )
        var snapshot = switcherSearchResultTestSnapshot(
            [],
            resultsScope: "window",
            resultsQuery: ""
        )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let owner =
            FlowTabUITestSwitcherSearchResultObservationOwner(
                expectation: expectation,
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

        snapshot = switcherSearchResultTestSnapshot(
            [
                switcherSearchResultTestObservation(
                    resultID: "window:chrome-42",
                    title: "Punctuation",
                    appName: "Chrome",
                    appID: "com.example.chrome"
                )
            ],
            resultsScope: "window",
            resultsQuery: "punctuation"
        )
        XCTAssertNil(owner.resolvedEvidence)
        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .scheduledReadback
        )
        XCTAssertEqual(
            expectation.matchingIdentifiers(
                in: owner.resolvedEvidence?.value
                    ?? switcherSearchResultTestSnapshot([])
            )?.count,
            1
        )
    }

    func testSwitcherSearchResultObserverRejectsStaleReadbacksUnderPressure() {
        let expectation =
            FlowTabUITestSwitcherSearchResultExpectation
                .matchingWindow(
                    title: "Report",
                    appName: "Browser"
                )
        for _ in 0..<FlowTabUITestSwitcherSearchResultTestPolicy
            .pressureIterations
        {
            var callbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            var results: [
                SwitcherSearchWindowResultObservation
            ] = []
            let owner =
                FlowTabUITestSwitcherSearchResultObservationOwner(
                    expectation: expectation,
                    observationRegistration: { callback in
                        callbacks.append(callback)
                        return FlowTabUITestObservationCancellation {}
                    },
                    readback: {
                        self.switcherSearchResultTestSnapshot(
                            results
                        )
                    }
                )
            owner.start()
            let staleReadback = callbacks[0]
            owner.cancel()
            owner.start()
            results = [
                switcherSearchResultTestObservation(
                    resultID: "window:42",
                    title: "Report",
                    appName: "Browser",
                    appID: "com.example.browser"
                )
            ]

            staleReadback(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
            callbacks[1](.scheduledReadback)
            callbacks[1](.scheduledReadback)
            XCTAssertEqual(
                owner.resolvedEvidence?.generation,
                2
            )
            owner.cancel()
        }
    }

    func testSwitcherSearchResultWatchdogReportsFinalProjection() {
        let owner =
            FlowTabUITestSwitcherSearchResultObservationOwner(
                expectation:
                    .matchingWindow(
                        title: "Report",
                        appName: "Browser"
                    ),
                observationRegistration: nil,
                readback: {
                    self.switcherSearchResultTestSnapshot(
                        [
                            self.switcherSearchResultTestObservation(
                                resultID: "window:7",
                                title: "Draft",
                                appName: "Browser",
                                appID: "com.example.browser"
                            )
                        ]
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSwitcherSearchResultTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("title=Draft")
        )
    }

    private func switcherSearchResultTestObservation(
        resultID: String,
        title: String,
        appName: String,
        appID: String
    ) -> SwitcherSearchWindowResultObservation {
        SwitcherSearchWindowResultObservation(
            identifier: "search.\(resultID)",
            searchableText:
                "\(title)\n\(appName)\n\(appID)",
            resultID: resultID,
            title: title,
            appName: appName,
            appID: appID,
            windowID: resultID
        )
    }

    private func switcherSearchResultTestSnapshot(
        _ results: [SwitcherSearchWindowResultObservation],
        resultsScope: String? = nil,
        resultsQuery: String? = nil
    ) -> FlowTabUITestSwitcherSearchResultSnapshot {
        FlowTabUITestSwitcherSearchResultSnapshot(
            results: results,
            resultsScope: resultsScope,
            resultsQuery: resultsQuery
        )
    }
}
