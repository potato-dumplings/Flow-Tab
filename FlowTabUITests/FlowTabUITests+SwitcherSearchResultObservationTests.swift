import Foundation
import XCTest

private enum FlowTabUITestSwitcherSearchResultTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
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
        _ results: [SwitcherSearchWindowResultObservation]
    ) -> FlowTabUITestSwitcherSearchResultSnapshot {
        FlowTabUITestSwitcherSearchResultSnapshot(
            results: results
        )
    }
}
