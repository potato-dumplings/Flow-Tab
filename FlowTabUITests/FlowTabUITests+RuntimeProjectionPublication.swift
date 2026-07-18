import XCTest

extension FlowTabUITests {
    func testWindowSearchPublishesMockWindowRowsAtLaunch() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-open-switcher-search",
                "--flowtab-ui-runtime-log-level",
                "DEBUG",
                "--flowtab-ui-enable-verbose-logs",
                "-searchDefaultScope",
                "window",
                "-showPermissionReminder",
                "NO",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

        let searchInput = element(in: app, identifier: Identifier.switcherSearchInput)
        XCTAssertTrue(searchInput.waitForExistence(timeout: 5))
        app.typeText("Inbox")

        XCTAssertTrue(
            element(in: app, identifier: Identifier.switcherSearchWindowMockMailInbox)
                .waitForExistence(timeout: 8)
        )
    }

    func testWindowSearchPublishesRealFixtureWindowRowsAtLaunch() throws {
        let workflow = try configuredSwitcherSpaceFixtureWorkflow()
        let targetWindowTitle = "Docs"
        let targetApp = try XCTUnwrap(
            workflow.apps.first { $0.expectedWindowTitles.contains(targetWindowTitle) },
            "Switcher workflow must include a real fixture window titled \(targetWindowTitle)"
        )

        try runRealSpaceFixtureWorkflow(
            workflow,
            flowTabAdditionalArguments: [
                "--flowtab-ui-open-switcher-search",
                "--flowtab-ui-runtime-log-level",
                "DEBUG",
                "--flowtab-ui-enable-verbose-logs",
                "-searchDefaultScope",
                "window"
            ]
        ) { _, app in
            let searchInput = element(in: app, identifier: Identifier.switcherSearchInput)
            XCTAssertTrue(searchInput.waitForExistence(timeout: 8))

            app.typeText(targetWindowTitle)
            XCTAssertNotNil(
                waitForSearchWindowResult(
                    in: app,
                    title: targetWindowTitle,
                    appName: targetApp.appName,
                    timeout: 8
                )
            )
        }
    }
}
