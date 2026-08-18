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

        let flowTabBundleIdentifier =
            FlowTabUITestAppIdentity.configured().bundleIdentifier
        let flowTabRowIdentifier =
            "flowtab.home.app."
            + flowTabBundleIdentifier
                .flowTabUITestAccessibilityIdentifierComponent
        let hiddenAppsIdentifier = Identifier.homeStatsHiddenApps
        let flowTabRow = element(
            in: app,
            identifier: flowTabRowIdentifier
        )
        let hiddenApps = element(
            in: app,
            identifier: hiddenAppsIdentifier
        )
        let projectionExpectation =
            FlowTabUITestHomePermissionBoundaryProjectionExpectation(
                applicationRowIdentifier: flowTabRowIdentifier,
                applicationRowValue: "0w hidden",
                hiddenAppsIdentifier: hiddenAppsIdentifier,
                hiddenAppsValue: "1"
            )
        let projectionObservation =
            FlowTabUITestHomePermissionBoundaryProjectionObservationOwner(
                expectation: projectionExpectation,
                readback: {
                    let applicationRowExists = flowTabRow.exists
                    let hiddenAppsExists = hiddenApps.exists
                    return FlowTabUITestHomePermissionBoundaryProjectionSnapshot(
                        applicationRowIdentifier:
                            flowTabRowIdentifier,
                        applicationRowExists:
                            applicationRowExists,
                        applicationRowValue:
                            applicationRowExists
                            ? self.elementStringValue(flowTabRow)
                            : nil,
                        hiddenAppsIdentifier:
                            hiddenAppsIdentifier,
                        hiddenAppsExists: hiddenAppsExists,
                        hiddenAppsValue:
                            hiddenAppsExists
                            ? self.elementStringValue(hiddenApps)
                            : nil
                    )
                }
            )
        projectionObservation.start()
        defer { projectionObservation.cancel() }

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

        XCTAssertNotNil(
            projectionObservation.waitForResolution(
                timeout:
                    FlowTabUITestHomePermissionBoundaryProjectionPolicy
                        .watchdog
            ),
            "Home permission-boundary projection watchdog expired. "
                + projectionObservation.diagnosticSummary
        )
    }
}
