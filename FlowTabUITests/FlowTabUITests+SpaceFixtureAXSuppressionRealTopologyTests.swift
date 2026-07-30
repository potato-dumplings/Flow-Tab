import XCTest

extension FlowTabUITests {
    func testAXSuppressionUsesAuthorizedFlowTabReadbackForRealFixtureTopology() throws {
        let workflow =
            try configuredSwitcherRuntimeTruthWorkflow(
                sourceWorkflowURL:
                    SpaceFixtureMultiAppWorkflowDefaults
                    .controlTabNoisyRuntimeTruthWorkflowSourceURL
            )
        let workflowApp = try XCTUnwrap(workflow.apps.first)
        let route =
            try XCTUnwrap(
                makeSpaceFixtureAXSuppressionRoutes(
                    for: workflow
                ).first
            )
        let observationOwner =
            SpaceFixtureAXSuppressionObservationOwner(
                routes: [route]
            )
        observationOwner.start()
        defer { observationOwner.cancel() }

        let flowTabApp =
            makeRealRuntimeFlowTabApp(
                additionalArguments:
                    route.flowTabLaunchArguments
            )
        launchFlowTabUITestApplication(
            flowTabApp,
            traceLabel:
                "ax-suppression.authorized-readback"
        )
        defer { terminateIfRunning(flowTabApp) }
        XCTAssertTrue(
            waitForFlowTabUITestApplicationToBecomeReady(
                flowTabApp,
                timeout: 12,
                traceLabel:
                    "ax-suppression.authorized-readback"
            )
        )
        guard
            assertSpaceFixtureWorkflowPermissionsAvailable(
                in: flowTabApp
            )
        else {
            return
        }

        let fixtureApp =
            makeAXSuppressionFixtureApplication(
                workflowApp
            )
        terminateIfRunning(fixtureApp)
        fixtureApp.launchArguments += [
            "--workflow-config",
            workflow.workflowURL.path,
            "--workflow-app-id",
            workflowApp.appID,
            "--staggered-layout",
            "--enter-fullscreen-delay-ms",
            String(
                SpaceFixtureMultiAppWorkflowDefaults
                    .enterFullscreenDelayMilliseconds
            ),
            "--suppress-app-accessibility-children",
        ]
        fixtureApp.launchArguments +=
            route.fixtureLaunchArguments
        launchSpaceFixtureApplicationAndWaitForForeground(
            fixtureApp
        )
        defer { terminateIfRunning(fixtureApp) }

        XCTAssertTrue(
            observationOwner.waitForSuppression(
                route: route,
                timeout: 20
            )
        )
        XCTAssertTrue(
            flowTabApp.state == .runningForeground
                || flowTabApp.state == .runningBackground
        )
    }

    private func makeAXSuppressionFixtureApplication(
        _ workflowApp: SpaceFixtureResolvedWorkflow.App
    ) -> XCUIApplication {
        if let appURL = workflowApp.identity.appURL {
            return XCUIApplication(url: appURL)
        }
        return XCUIApplication(
            bundleIdentifier:
                workflowApp.identity.bundleIdentifier
        )
    }

    private func terminateIfRunning(
        _ app: XCUIApplication
    ) {
        guard app.state == .runningForeground
            || app.state == .runningBackground
        else {
            return
        }
        app.terminate()
        XCTAssertTrue(
            app.wait(for: .notRunning, timeout: 5)
        )
    }
}
