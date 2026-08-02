import XCTest

private enum FlowTabUITestRuntimeProjectionPublicationPolicy {
    static let windowResultPublicationWatchdog: TimeInterval = 8
}

extension FlowTabUITests {
    func testRuntimeProjectionPublicationWatchdogPolicyCompatibility() {
        XCTAssertEqual(
            FlowTabUITestRuntimeProjectionPublicationPolicy
                .windowResultPublicationWatchdog,
            8
        )
        XCTAssertTrue(
            FlowTabUITestRuntimeProjectionPublicationPolicy
                .windowResultPublicationWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestRuntimeProjectionPublicationPolicy
                .windowResultPublicationWatchdog,
            0
        )
    }

    func testWindowSearchPublishesMockWindowRowsAtLaunch() throws {
        let readiness =
            prepareInitialFlowTabSearchInputReadiness()
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
        let foregroundReadinessSatisfied =
            waitForFlowTabUITestApplicationToBecomeReady(
                app,
                timeout:
                    FlowTabUITestSupportWatchdogPolicy
                        .foregroundActivation
            )
        XCTAssertTrue(
            foregroundReadinessSatisfied,
            "Runtime-projection FlowTab foreground watchdog expired. "
                + "finalState=\(String(describing: app.state))"
        )

        _ = requireInitialFlowTabSearchInput(
            in: app,
            observedBy: readiness
        )
        let result = performAndWaitForCommittedSearchWindowResult(
            in: app,
            scope: "window",
            query: "Inbox",
            title: "Inbox",
            appName: "Mock Mail",
            timeout:
                FlowTabUITestRuntimeProjectionPublicationPolicy
                    .windowResultPublicationWatchdog,
            trigger: {
                app.typeText("Inbox")
            }
        )
        XCTAssertEqual(
            result?.identifier,
            Identifier.switcherSearchWindowMockMailInbox
        )
    }

    func testWindowSearchPublishesRealFixtureWindowRowsAtLaunch() throws {
        let workflow = try configuredSwitcherSpaceFixtureWorkflow()
        let targetWindowTitle = "Docs"
        let targetApp = try XCTUnwrap(
            workflow.apps.first { $0.expectedWindowTitles.contains(targetWindowTitle) },
            "Switcher workflow must include a real fixture window titled \(targetWindowTitle)"
        )
        let readiness =
            prepareInitialFlowTabSearchInputReadiness()

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
            _ = requireInitialFlowTabSearchInput(
                in: app,
                observedBy: readiness
            )

            XCTAssertNotNil(
                performAndWaitForCommittedSearchWindowResult(
                    in: app,
                    scope: "window",
                    query: targetWindowTitle,
                    title: targetWindowTitle,
                    appName: targetApp.appName,
                    timeout:
                        FlowTabUITestRuntimeProjectionPublicationPolicy
                            .windowResultPublicationWatchdog,
                    trigger: {
                        app.typeText(targetWindowTitle)
                    }
                )
            )
        }
    }
}
