import AppKit
import XCTest

extension FlowTabUITests {
    func testHomePageClickingRealWorkflowWindowActivatesExactFixtureWindow() throws {
        try runRealSpaceFixtureMultiAppWorkflow(
            waitsForFullscreenMarkers: false
        ) { workflow, app in
            let targetApp = try XCTUnwrap(
                workflow.apps.first { $0.expectedHomeWindowTitles.count >= 2 },
                "Home activation workflow must include a fixture app with multiple standard windows."
            )
            let targetWindowTitle = try XCTUnwrap(
                targetApp.expectedHomeWindowTitles.dropFirst().first,
                "Home activation workflow must expose a non-initial target window title."
            )

            XCTAssertTrue(
                tapFirstHittable(in: app.buttons.matching(identifier: Identifier.homeTabButton), timeout: 10)
            )
            XCTAssertNotEqual(
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                targetApp.identity.bundleIdentifier,
                "Home window activation scenario must start outside the target fixture app."
            )

            let homeAppRow = app.buttons
                .matching(identifier: targetApp.identity.homeAppAccessibilityIdentifier)
                .firstMatch
            XCTAssertTrue(
                homeAppRow.waitForExistence(timeout: 20),
                "FlowTab did not surface \(targetApp.appName) on the home page."
            )
            tapElement(homeAppRow)

            let targetWindowRow = try XCTUnwrap(
                waitForHomeWindowRow(in: app, title: targetWindowTitle, timeout: 12),
                "FlowTab did not expose a Home window row for \(targetApp.appName) / \(targetWindowTitle)."
            )
            let targetWindowNumber = try XCTUnwrap(
                cgWindowNumber(fromHomeWindowRowIdentifier: targetWindowRow.identifier),
                "Home window row did not expose a CG window identifier: \(targetWindowRow.identifier)"
            )
            targetWindowRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

            XCTAssertTrue(
                waitForFrontmostWorkflowWindow(
                    windowNumber: targetWindowNumber,
                    title: targetWindowTitle,
                    app: targetApp,
                    timeout: 10
                ),
                "Clicking the Home window row did not activate the exact \(targetWindowTitle) fixture window."
            )
        }
    }

    private func cgWindowNumber(fromHomeWindowRowIdentifier identifier: String) -> CGWindowID? {
        let prefix = "flowtab.home.window.cg-"
        guard identifier.hasPrefix(prefix) else { return nil }

        let readableComponent = identifier
            .dropFirst(prefix.count)
            .split(separator: ".id-", maxSplits: 1)
            .first
        let tokens = readableComponent?.split(separator: "-") ?? []
        guard let windowNumberToken = tokens.last,
              let windowNumber = UInt32(windowNumberToken)
        else {
            return nil
        }

        return CGWindowID(windowNumber)
    }
}
