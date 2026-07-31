import XCTest

extension FlowTabUITests {
    func testSearchPanelWrapFromLastResultScrollsBackToFirstResult() throws {
        let launch =
            launchSearchMockApplication(
                mockRuntimeVariant: "search-wrap"
            )
        let app = launch.app

        _ = requireInitialFlowTabSearchInput(
            in: app,
            observedBy: launch.readiness
        )

        let diagnosticsSummary =
            element(
                in: app,
                identifier: Identifier.switcherSummary
            )
        XCTAssertTrue(
            diagnosticsSummary.waitForExistence(timeout: 5)
        )

        for index in 1...10 {
            let suffix =
                index < 10
                ? "0\(index)"
                : "\(index)"
            let resultID =
                "app:com.flowtab.mock.wrap.\(suffix)"
            XCTAssertTrue(
                performAndWaitForSwitcherDiagnostics(
                    diagnosticsSummary,
                    key: "searchSelectedResult",
                    equals: resultID,
                    decodesPercentEncoding: true,
                    timeout: 3,
                    trigger: {
                        app.typeKey(
                            .downArrow,
                            modifierFlags: []
                        )
                    }
                ),
                "Search selection did not reach \(resultID)."
            )
        }

        let lastResultIdentifier =
            "flowtab.switcher.search.app."
            + "com.flowtab.mock.wrap.10"
                .flowTabUITestAccessibilityIdentifierComponent
        XCTAssertTrue(
            hasHittableElement(
                in: app.descendants(matching: .any)
                    .matching(
                        identifier:
                            lastResultIdentifier
                    ),
                timeout: 2
            )
        )

        let firstResultID =
            "app:com.flowtab.mock.wrap.01"
        XCTAssertTrue(
            performAndWaitForSwitcherDiagnostics(
                diagnosticsSummary,
                key: "searchSelectedResult",
                equals: firstResultID,
                decodesPercentEncoding: true,
                timeout: 3,
                trigger: {
                    app.typeKey(
                        .downArrow,
                        modifierFlags: []
                    )
                }
            ),
            "Search selection did not wrap to \(firstResultID)."
        )

        let firstResultIdentifier =
            "flowtab.switcher.search.app."
            + "com.flowtab.mock.wrap.01"
                .flowTabUITestAccessibilityIdentifierComponent
        XCTAssertTrue(
            hasHittableElement(
                in: app.descendants(matching: .any)
                    .matching(
                        identifier:
                            firstResultIdentifier
                    ),
                timeout: 5
            )
        )
    }
}
