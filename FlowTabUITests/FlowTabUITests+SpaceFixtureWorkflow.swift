import Foundation
import XCTest

extension FlowTabUITests {
    func testHomePageShowsRealSpaceFixtureWorkflowWindows() throws {
        runRealSpaceFixtureWorkflow { identity, app in
            let fixtureAppRow = openHomeTabAndSelectSpaceFixtureApp(in: app, identity: identity)
            assertValue(of: fixtureAppRow, equals: "3w", timeout: 20)
            assertSpaceFixtureWindowTitles(
                expectedSpaceFixtureWorkflowWindowTitles(titlePrefix: "Workflow", windowCount: 3),
                in: app
            )
        }
    }

    func testHomePageSelectingRealSpaceFixtureAppShowsWorkflowWindowTitles() throws {
        runRealSpaceFixtureWorkflow { identity, app in
            _ = openHomeTabAndSelectSpaceFixtureApp(in: app, identity: identity)
            assertSpaceFixtureWindowTitles(
                expectedSpaceFixtureWorkflowWindowTitles(titlePrefix: "Workflow", windowCount: 3),
                in: app
            )
        }
    }

    func testSwitcherPanelShowsRealSpaceFixtureAppTileInStandardMode() throws {
        runRealSpaceFixtureWorkflow(
            flowTabAdditionalArguments: ["--flowtab-ui-open-switcher"]
        ) { identity, app in
            let switcherPanel = element(in: app, identifier: Identifier.switcherPanel)
            XCTAssertTrue(switcherPanel.waitForExistence(timeout: 8))

            let fixtureAppTile = switcherPanel.descendants(matching: .any)
                .matching(identifier: identity.switcherAppAccessibilityIdentifier)
                .firstMatch
            XCTAssertTrue(
                fixtureAppTile.waitForExistence(timeout: 8),
                "FlowTab did not surface the Space Fixture app in the switcher app strip"
            )
        }
    }

    func testSwitcherPanelShowsRealSpaceFixtureWorkflowWindowCards() throws {
        runRealSpaceFixtureWorkflow(
            flowTabAdditionalArguments: ["--flowtab-ui-open-switcher"]
        ) { identity, app in
            let switcherPanel = element(in: app, identifier: Identifier.switcherPanel)
            XCTAssertTrue(switcherPanel.waitForExistence(timeout: 8))

            let fixtureAppTile = switcherPanel.descendants(matching: .any)
                .matching(identifier: identity.switcherAppAccessibilityIdentifier)
                .firstMatch
            XCTAssertTrue(fixtureAppTile.waitForExistence(timeout: 8))

            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            app.typeKey(.downArrow, modifierFlags: [])

            assertSpaceFixtureWindowTitles(
                expectedSpaceFixtureWorkflowWindowTitles(titlePrefix: "Workflow", windowCount: 3),
                in: app
            )
        }
    }

    func makeSpaceFixtureWorkflowFile(_ contents: String) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = directoryURL.appendingPathComponent("workflow.json")
        try Data(contents.utf8).write(to: fileURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        return fileURL
    }

    func runRealSpaceFixtureWorkflow(
        flowTabAdditionalArguments: [String] = [],
        perform assertions: (SpaceFixtureAppIdentity, XCUIApplication) -> Void
    ) {
        let identity = spaceFixtureAppIdentity
        let fixtureApp = launchSpaceFixtureWorkflow(
            identity: identity,
            windowCount: 3,
            fullscreenWindowIndex: 3,
            titlePrefix: "Workflow",
            enterFullscreenDelayMilliseconds: 5_000
        )
        defer {
            if fixtureApp.state == .runningForeground || fixtureApp.state == .runningBackground {
                fixtureApp.terminate()
            }
        }

        guard assertSpaceFixtureWorkflowPermissionsAvailable() else { return }

        let app = makeRealRuntimeFlowTabApp(additionalArguments: flowTabAdditionalArguments)
        app.launch()
        defer {
            if app.state == .runningForeground || app.state == .runningBackground {
                app.terminate()
            }
        }

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12))
        assertions(identity, app)
    }

    private func openHomeTabAndSelectSpaceFixtureApp(
        in app: XCUIApplication,
        identity: SpaceFixtureAppIdentity,
        timeout: TimeInterval = 20
    ) -> XCUIElement {
        XCTAssertTrue(
            tapFirstHittable(in: app.buttons.matching(identifier: Identifier.homeTabButton), timeout: 10)
        )

        let fixtureAppRows = app.buttons.matching(identifier: identity.homeAppAccessibilityIdentifier)
        let fixtureAppRow = fixtureAppRows.firstMatch
        XCTAssertTrue(fixtureAppRow.waitForExistence(timeout: timeout))
        XCTAssertTrue(
            tapFirstHittable(in: fixtureAppRows, timeout: timeout),
            "FlowTab did not surface the real Space Fixture app on the home page"
        )
        return fixtureAppRow
    }

    private func assertSpaceFixtureWindowTitles(
        _ expectedTitles: [String],
        in app: XCUIApplication,
        timeout: TimeInterval = 12
    ) {
        for title in expectedTitles {
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: timeout), "Missing window title: \(title)")
        }
    }
}
