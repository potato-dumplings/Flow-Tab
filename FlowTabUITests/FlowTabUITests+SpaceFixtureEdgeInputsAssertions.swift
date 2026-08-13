import CoreGraphics
import Foundation
import XCTest

extension FlowTabUITests {
    func selectEdgeWorkflowAppInSwitcherAppLayer(
        _ targetApp: SpaceFixtureResolvedWorkflow.App,
        app: XCUIApplication,
        diagnosticsSummary: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        do {
            try FlowTabUITestSwitcherCommandPayload.write(targetApp.identity.bundleIdentifier)
        } catch {
            XCTFail("Failed to write edge workflow switcher select-app payload: \(error)")
            return false
        }
        return performAndWaitForSwitcherDiagnostics(
            diagnosticsSummary,
            key: "selected",
            equals: targetApp.identity.bundleIdentifier,
            timeout: timeout
        ) {
            postFlowTabUITestSwitcherCommandAndWaitForDelivery(
                .selectApp,
                traceLabel:
                    "edgeInputs.selectApp.\(targetApp.appID)",
                timeout: timeout
            )
        }
    }

    func confirmEdgeSwitcherSearchSelection(
        in app: XCUIApplication,
        searchInput: XCUIElement,
        expectedQuery: String
    ) {
        confirmSwitcherSearchSelection(
            in: app,
            searchInput: searchInput,
            expectedQuery: expectedQuery
        )
    }

    func edgeTitleCounts(_ titles: [String]) -> [String: Int] {
        titles.reduce(into: [:]) { result, title in
            result[title, default: 0] += 1
        }
    }

    func edgeWorkflowSearchWindowIdentifierAppFragment(
        for workflowApp: SpaceFixtureResolvedWorkflow.App
    ) -> String {
        let resultIDPrefix = "window:\(workflowApp.identity.bundleIdentifier)#"
        return "\(resultIDPrefix.flowTabUITestAccessibilitySlug)-"
    }

    func edgeWorkflowCGWindowID(
        fromSearchResultIdentifier identifier: String
    ) -> CGWindowID? {
        let prefix = "flowtab.switcher.search.window."
        let component = identifier.hasPrefix(prefix)
            ? identifier.dropFirst(prefix.count)
            : Substring(identifier)
        let readableComponent = component.split(separator: ".id-", maxSplits: 1).first ?? component
        guard let rawWindowID = readableComponent.split(separator: "-").last else { return nil }
        guard let windowID = UInt32(rawWindowID) else { return nil }
        return CGWindowID(windowID)
    }

}
