import Foundation
import XCTest

extension FlowTabUITests {
    func captureAppPanelVisualCheckpoint(
        application: XCUIApplication,
        flow: AppPanelPressureUITestFlow,
        scenario: AppPanelPressureUITestScenario,
        evidence: AppPanelPressureUITestEvidence
    ) {
        let milestone: String
        switch flow {
        case .application:
            milestone = "appContentDraw"
        case .applicationToWindow:
            milestone = "windowContentDraw"
        case .search:
            milestone = "searchFirstRowDraw"
            assertSearchPressureElementsAreFullyPresented(
                in: application,
                scenario: scenario,
                panelWidth: evidence.panelWidth
            )
        }
        let scenarioName = scenario.variant.map {
            $0.replacingOccurrences(
                of: "app-panel-pressure-",
                with: ""
            )
        } ?? "local"
        let attachment = XCTAttachment(
            screenshot: XCUIScreen.main.screenshot()
        )
        attachment.name = [
            "flowtab-app-panel",
            flow.rawValue,
            scenarioName,
            milestone
        ].joined(separator: "-")
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertSearchPressureElementsAreFullyPresented(
        in application: XCUIApplication,
        scenario: AppPanelPressureUITestScenario,
        panelWidth: Double
    ) {
        let header = element(
            in: application,
            identifier: Identifier.switcherSearchHeader
        )
        let input = element(
            in: application,
            identifier: Identifier.switcherSearchInput
        )
        let highlight = element(
            in: application,
            identifier: Identifier.switcherSearchHighlight
        )
        let firstResult: XCUIElement
        if let expectedAppID = scenario.expectedAppID(index: 1) {
            firstResult = element(
                in: application,
                identifier: "flowtab.switcher.search.app."
                    + expectedAppID
                        .flowTabUITestAccessibilityIdentifierComponent
            )
        } else {
            firstResult = application.descendants(matching: .any)
                .matching(
                    NSPredicate(
                        format: "identifier BEGINSWITH %@",
                        "flowtab.switcher.search.app."
                    )
                )
                .firstMatch
        }
        for candidate in [header, input, highlight, firstResult] {
            XCTAssertTrue(candidate.exists)
            XCTAssertFalse(candidate.frame.isEmpty)
        }
        XCTAssertTrue(input.isHittable)
        XCTAssertTrue(firstResult.isHittable)
        XCTAssertLessThanOrEqual(
            header.frame.width,
            panelWidth + 0.5
        )
        XCTAssertTrue(
            header.frame.insetBy(dx: -2, dy: -2)
                .contains(input.frame)
        )
        XCTAssertTrue(
            header.frame.insetBy(dx: -2, dy: -2)
                .contains(highlight.frame)
        )
        XCTAssertGreaterThanOrEqual(
            firstResult.frame.minX,
            header.frame.minX - 2
        )
        XCTAssertLessThanOrEqual(
            firstResult.frame.maxX,
            header.frame.maxX + 2
        )
    }
}
