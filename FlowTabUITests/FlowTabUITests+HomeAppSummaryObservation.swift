import XCTest

extension FlowTabUITests {
    func testHomeObservesFixtureAppsLaunchedAfterFlowTab() throws {
        try runRealSpaceFixtureMultiAppWorkflow(
            validatesPermissionsBeforeFixtureLaunch: true,
            prelaunchesFlowTabBeforeFixture: true
        ) { workflow, app in
            XCTAssertTrue(
                tapFirstHittable(
                    in: app.buttons.matching(
                        identifier: Identifier.homeTabButton
                    ),
                    timeout: 10
                )
            )

            for workflowApp in workflow.apps {
                let homeRow = app.buttons
                    .matching(
                        identifier:
                            workflowApp.identity
                                .homeAppAccessibilityIdentifier
                    )
                    .firstMatch
                XCTAssertTrue(
                    homeRow.waitForExistence(timeout: 20),
                    "FlowTab did not observe \(workflowApp.appName) after launch"
                )
                assertValue(
                    of: homeRow,
                    equals: "\(workflowApp.windowCount)w",
                    timeout: 20
                )
            }
        }
    }
}
