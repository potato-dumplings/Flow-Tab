import XCTest

extension FlowTabUITests {
    func performAndWaitForCommittedSearchResultRow(
        in app: XCUIApplication,
        scope: String,
        query: String,
        resultID: String,
        rowIdentifier: String,
        timeout: TimeInterval,
        trigger: () -> Void
    ) -> Bool {
        let expectation =
            FlowTabUITestSwitcherSearchResultExpectation
                .committedResultRow(
                    scope: scope,
                    query: query,
                    resultID: resultID,
                    rowIdentifier: rowIdentifier
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
                        targetRowIdentifier: rowIdentifier
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
