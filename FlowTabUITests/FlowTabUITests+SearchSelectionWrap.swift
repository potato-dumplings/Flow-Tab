import Foundation
import XCTest

enum FlowTabUITestSearchSelectionWrapPolicy {
    static let diagnosticsPublicationWatchdog: TimeInterval = 5
    static let diagnosticsTransitionWatchdog: TimeInterval = 3
    static let lastResultHittabilityWatchdog: TimeInterval = 2
    static let wrappedFirstResultHittabilityWatchdog: TimeInterval = 5
}

extension FlowTabUITests {
    func testSearchSelectionWrapWatchdogPolicyCompatibility() {
        XCTAssertEqual(
            FlowTabUITestSearchSelectionWrapPolicy
                .diagnosticsPublicationWatchdog,
            5
        )
        XCTAssertEqual(
            FlowTabUITestSearchSelectionWrapPolicy
                .diagnosticsTransitionWatchdog,
            3
        )
        XCTAssertEqual(
            FlowTabUITestSearchSelectionWrapPolicy
                .lastResultHittabilityWatchdog,
            2
        )
        XCTAssertEqual(
            FlowTabUITestSearchSelectionWrapPolicy
                .wrappedFirstResultHittabilityWatchdog,
            5
        )
    }

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
        let diagnosticsPublished =
            diagnosticsSummary.waitForExistence(
                timeout:
                    FlowTabUITestSearchSelectionWrapPolicy
                        .diagnosticsPublicationWatchdog
            )
        XCTAssertTrue(
            diagnosticsPublished,
            "Search diagnostics summary was not published. "
                + "expectedExists=true "
                + "finalExists=\(diagnosticsSummary.exists) "
                + "identifier=\(diagnosticsSummary.identifier)"
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
                    timeout:
                        FlowTabUITestSearchSelectionWrapPolicy
                            .diagnosticsTransitionWatchdog,
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
        let lastResultQuery =
            app.descendants(matching: .any)
                .matching(identifier: lastResultIdentifier)
        XCTAssertTrue(
            hasHittableElement(
                in: lastResultQuery,
                timeout:
                    FlowTabUITestSearchSelectionWrapPolicy
                        .lastResultHittabilityWatchdog
            ),
            "Last Search result did not become hittable. "
                + "expectedIdentifier=\(lastResultIdentifier) "
                + "finalCandidateCount=\(lastResultQuery.count) "
                + "finalExists=\(lastResultQuery.firstMatch.exists) "
                + "finalHittable=\(lastResultQuery.firstMatch.isHittable)"
        )

        let firstResultID =
            "app:com.flowtab.mock.wrap.01"
        XCTAssertTrue(
            performAndWaitForSwitcherDiagnostics(
                diagnosticsSummary,
                key: "searchSelectedResult",
                equals: firstResultID,
                decodesPercentEncoding: true,
                timeout:
                    FlowTabUITestSearchSelectionWrapPolicy
                        .diagnosticsTransitionWatchdog,
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
        let firstResultQuery =
            app.descendants(matching: .any)
                .matching(identifier: firstResultIdentifier)
        XCTAssertTrue(
            hasHittableElement(
                in: firstResultQuery,
                timeout:
                    FlowTabUITestSearchSelectionWrapPolicy
                        .wrappedFirstResultHittabilityWatchdog
            ),
            "Wrapped first Search result did not become hittable. "
                + "expectedIdentifier=\(firstResultIdentifier) "
                + "finalCandidateCount=\(firstResultQuery.count) "
                + "finalExists=\(firstResultQuery.firstMatch.exists) "
                + "finalHittable=\(firstResultQuery.firstMatch.isHittable)"
        )
    }
}
