import XCTest

extension FlowTabUITests {
    func launchAndWaitForPointerSearchResultRows(
        in app: XCUIApplication,
        bundleIdentifiers: [String],
        timeout: TimeInterval
    ) -> [XCUIElement]? {
        let rows = bundleIdentifiers.map { bundleIdentifier in
            FlowTabUITestSwitcherSearchExpectedResultRow(
                resultID: "app:\(bundleIdentifier)",
                rowIdentifier:
                    "flowtab.switcher.search.app."
                    + bundleIdentifier
                        .flowTabUITestAccessibilityIdentifierComponent
            )
        }
        guard
            performAndWaitForCommittedSearchResultRows(
                in: app,
                scope: "app",
                query: "",
                rows: rows,
                timeout: timeout,
                trigger: {
                    launchFlowTabUITestApplication(app)
                    assertSwitcherAndSearchApplicationIsForegroundReady(
                        app
                    )
                }
            )
        else {
            return nil
        }
        return rows.map {
            element(in: app, identifier: $0.rowIdentifier)
        }
    }

    func assertSearchResultUsesRowSizedFrame(
        _ result: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThan(
            result.frame.width,
            200,
            "Search result hover tests must target the full "
                + "result row, not only its label. "
                + "frame=\(result.frame)",
            file: file,
            line: line
        )
    }

    func performAndWaitForCommittedSearchResultRow(
        in app: XCUIApplication,
        scope: String,
        query: String,
        resultID: String,
        rowIdentifier: String,
        timeout: TimeInterval,
        trigger: () -> Void
    ) -> Bool {
        performAndWaitForCommittedSearchResultRows(
            in: app,
            scope: scope,
            query: query,
            rows: [
                FlowTabUITestSwitcherSearchExpectedResultRow(
                    resultID: resultID,
                    rowIdentifier: rowIdentifier
                )
            ],
            timeout: timeout,
            trigger: trigger
        )
    }

    func performAndWaitForCommittedSearchResultRows(
        in app: XCUIApplication,
        scope: String,
        query: String,
        rows: [FlowTabUITestSwitcherSearchExpectedResultRow],
        timeout: TimeInterval,
        trigger: () -> Void
    ) -> Bool {
        guard FlowTabUITestSwitcherSearchExpectedResultRow
            .formsValidProjection(rows)
        else {
            XCTFail(
                "Committed Search result projection requires "
                    + "unique nonempty result and row identities."
            )
            return false
        }
        let expectation =
            FlowTabUITestSwitcherSearchResultExpectation
                .committedResultRows(
                    scope: scope,
                    query: query,
                    rows: rows
                )
        var triggerCompleted = false
        let owner =
            FlowTabUITestSwitcherSearchResultObservationOwner(
                expectation: expectation,
                acceptsEvidence: {
                    triggerCompleted
                },
                readback: {
                    self.committedSwitcherSearchResultSnapshot(
                        in: app,
                        targetRowIdentifiers:
                            rows.map(\.rowIdentifier)
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        guard let baseline = owner.latestSnapshot else {
            XCTFail(
                "Committed Search result observation did not "
                    + "produce an initial readback. "
                    + owner.diagnosticSummary
            )
            return false
        }
        guard !expectation.hasCommittedIdentity(in: baseline)
        else {
            XCTFail(
                "Committed Search result observation baseline "
                    + "already matched the triggered identity. "
                    + owner.diagnosticSummary
            )
            return false
        }

        trigger()
        triggerCompleted = true
        owner.requestReadback(source: .triggerReadback)

        guard owner.waitForResolution(timeout: timeout) != nil
        else {
            XCTFail(
                "Committed Search result-row projection "
                    + "watchdog expired. "
                    + owner.diagnosticSummary
            )
            return false
        }
        return true
    }
}
