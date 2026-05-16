import CoreGraphics
import Foundation
import XCTest

struct EdgeWorkflowWindowCardObservation: Equatable {
    let identifier: String
    let title: String
}

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
        postFlowTabUITestSwitcherCommand(
            .selectApp,
            traceLabel: "edgeInputs.selectApp.\(targetApp.appID)"
        )

        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if switcherPanelDiagnosticsValue(diagnosticsSummary, key: "selected")
                == targetApp.identity.bundleIdentifier {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        let latestCards = edgeSwitcherWindowCardObservations(in: app)
        XCTFail(
            """
            Switcher direct app selection did not settle on \(targetApp.appName).

            target=\(targetApp.identity.bundleIdentifier)
            selected=\(switcherPanelDiagnosticsValue(diagnosticsSummary, key: "selected"))
            mode=\(switcherPanelDiagnosticsValue(diagnosticsSummary, key: "mode"))
            preview=\(switcherPreviewTitles(from: diagnosticsSummary).sorted())
            windowCards=\(latestCards.map { "\($0.title)=\($0.identifier)" }.sorted())

            \(switcherDebugSummary(app, diagnosticsSummary: diagnosticsSummary))
            """
        )
        return false
    }

    func waitForEdgeSwitcherWindowCards(
        in app: XCUIApplication,
        expectedTitles: [String],
        timeout: TimeInterval
    ) -> [EdgeWorkflowWindowCardObservation] {
        let deadline = Date().addingTimeInterval(timeout)
        var latestCards: [EdgeWorkflowWindowCardObservation] = []
        let expectedTitleCounts = edgeTitleCounts(expectedTitles)

        repeat {
            latestCards = edgeSwitcherWindowCardObservations(in: app)
            if latestCards.count == expectedTitles.count,
               Set(latestCards.map(\.identifier)).count == latestCards.count,
               edgeTitleCounts(latestCards.map(\.title)) == expectedTitleCounts {
                return latestCards
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        XCTFail(
            """
            Expected switcher preview cards to preserve titles \(expectedTitles), \
            found \(latestCards.map { "\($0.title)=\($0.identifier)" }.sorted()).
            """
        )
        return latestCards
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

    func edgeWorkflowAccessibilityIdentifierFragment(
        for workflowApp: SpaceFixtureResolvedWorkflow.App
    ) -> String {
        workflowApp.identity.bundleIdentifier.edgeWorkflowAccessibilitySlug
    }

    func edgeWorkflowCGWindowID(
        fromSearchResultIdentifier identifier: String
    ) -> CGWindowID? {
        guard let rawWindowID = identifier.split(separator: "-").last else { return nil }
        guard let windowID = UInt32(rawWindowID) else { return nil }
        return CGWindowID(windowID)
    }

    private func edgeSwitcherWindowCardObservations(in app: XCUIApplication) -> [EdgeWorkflowWindowCardObservation] {
        var seenIdentifiers: Set<String> = []
        return edgeWorkflowElements(in: app, identifierPrefix: "flowtab.switcher.window.").compactMap { element in
            let identifier = element.identifier
            let title = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            guard seenIdentifiers.insert(identifier).inserted else { return nil }
            return EdgeWorkflowWindowCardObservation(
                identifier: identifier,
                title: title
            )
        }
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

private extension String {
    var edgeWorkflowAccessibilitySlug: String {
        let replaced = trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(
                of: #"[^a-z0-9]+"#,
                with: "-",
                options: .regularExpression
            )
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return replaced.isEmpty ? "item" : replaced
    }
}
