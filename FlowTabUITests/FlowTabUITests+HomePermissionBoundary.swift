import XCTest

extension FlowTabUITests {
    func testHomeKeepsCurrentFlowTabInApplicationDirectoryWithoutAccessibilityPermission() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "-showPermissionReminder",
                "NO",
                "--flowtab-ui-ax-trusted",
                "NO",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(app)
        let foregroundReadinessSatisfied =
            waitForFlowTabUITestApplicationToBecomeReady(
                app,
                timeout:
                    FlowTabUITestSupportWatchdogPolicy
                        .foregroundActivation
            )
        XCTAssertTrue(
            foregroundReadinessSatisfied,
            "Home permission-boundary foreground watchdog expired. "
                + "finalState=\(String(describing: app.state))"
        )
        let homeTabButtons = app.buttons.matching(
            identifier: Identifier.homeTabButton
        )
        let homeContent = element(
            in: app,
            identifier: Identifier.homeTabContent
        )
        XCTAssertTrue(
            tapFirstHittableAndWaitForExistence(
                in: homeTabButtons,
                content: homeContent,
                contentDescription: Identifier.homeTabContent,
                timeout:
                    FlowTabUITestSupportWatchdogPolicy
                        .tabNavigation
            ),
            "Home permission-boundary navigation watchdog expired. "
                + "finalCandidateCount=\(homeTabButtons.count) "
                + "finalContentExists=\(homeContent.exists)"
        )

        let flowTabBundleIdentifier = FlowTabUITestAppIdentity.configured().bundleIdentifier
        let flowTabRowIdentifier =
            "flowtab.home.app.\(flowTabBundleIdentifier.flowTabUITestAccessibilityIdentifierComponent)"
        let flowTabRow = element(in: app, identifier: flowTabRowIdentifier)

        XCTAssertTrue(
            flowTabRow.waitForExistence(timeout: 6),
            "Home should keep FlowTab in the application directory while Accessibility is unavailable."
        )
        assertValue(of: flowTabRow, equals: "0w hidden", timeout: 2)
        assertValue(
            of: element(in: app, identifier: Identifier.homeStatsHiddenApps),
            equals: "1",
            timeout: 2
        )
    }
}
