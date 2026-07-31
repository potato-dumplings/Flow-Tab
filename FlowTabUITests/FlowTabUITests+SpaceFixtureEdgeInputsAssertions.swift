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
        let appTile = element(in: app, identifier: targetApp.identity.switcherAppAccessibilityIdentifier)
        XCTAssertTrue(
            appTile.waitForExistence(timeout: timeout),
            """
            Edge workflow app \(targetApp.appName) was not exposed in the switcher app layer.

            \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
            """
        )

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

    func waitForEdgeSearchWindowResultIdentifiers(
        in app: XCUIApplication,
        identifierFragment: String? = nil,
        expectedCount: Int,
        timeout: TimeInterval
    ) -> [String] {
        let deadline = Date().addingTimeInterval(timeout)
        var latestMatches: [String] = []
        repeat {
            latestMatches = uniqueEdgeSearchWindowResultIdentifiers(in: app)
                .filter { identifier in
                    guard let identifierFragment else { return true }
                    return identifier.contains(identifierFragment)
                }
            if latestMatches.count == expectedCount {
                return latestMatches
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        XCTFail(
            """
            Expected \(expectedCount) window-scope search result identifiers matching \
            \(identifierFragment ?? "<any>"), found \(latestMatches.sorted()).
            """
        )
        return latestMatches
    }

    func confirmEdgeSwitcherSearchSelection(in app: XCUIApplication, searchInput: XCUIElement) {
        app.typeText("\r")
        if !waitForNonExistence(searchInput, timeout: 1.2) {
            app.typeText("\r")
        }
        XCTAssertTrue(waitForNonExistence(searchInput, timeout: 4))
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

    private func uniqueEdgeSearchWindowResultIdentifiers(in app: XCUIApplication) -> [String] {
        var seenIdentifiers: Set<String> = []
        return edgeWorkflowIdentifiers(
            in: app.debugDescription,
            identifierPrefix: "flowtab.switcher.search.window."
        ).compactMap { identifier in
            guard seenIdentifiers.insert(identifier).inserted else { return nil }
            return identifier
        }
    }

    private func edgeWorkflowIdentifiers(
        in hierarchyDescription: String,
        identifierPrefix: String
    ) -> [String] {
        let escapedPrefix = NSRegularExpression.escapedPattern(for: identifierPrefix)
        let pattern = "identifier: ['\"](" + escapedPrefix + "[^'\"]*)['\"]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(hierarchyDescription.startIndex..<hierarchyDescription.endIndex, in: hierarchyDescription)
        return regex.matches(in: hierarchyDescription, range: range).compactMap { match in
            guard let identifierRange = Range(match.range(at: 1), in: hierarchyDescription) else {
                return nil
            }
            return String(hierarchyDescription[identifierRange])
        }
    }

    private func edgeWorkflowElements(
        in app: XCUIApplication,
        identifierPrefix: String
    ) -> [XCUIElement] {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", identifierPrefix))
            .allElementsBoundByIndex
    }

}
