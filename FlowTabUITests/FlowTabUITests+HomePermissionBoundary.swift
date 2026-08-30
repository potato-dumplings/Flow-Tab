import XCTest

private enum FlowTabUITestHomePermissionLayoutOracle {
    static let compactTrailingInset: CGFloat = 8
    static let frameAccuracy: CGFloat = 2
}

extension FlowTabUITests {
    func testHomePermissionStatusesUseCompactTrailingInset() {
        let app = makeApp(
            additionalArguments: [
                "-AppleLanguages",
                "(zh-Hans)",
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "NO"
            ]
        )
        launchFlowTabUITestApplication(app)

        let card = element(
            in: app,
            identifier: Identifier.sidebarPermissionStatus
        )
        XCTAssertTrue(
            card.waitForExistence(
                timeout:
                    FlowTabUITestSupportWatchdogPolicy
                        .permissionStateProjection
            )
        )

        let statuses = [
            (
                element(
                    in: app,
                    identifier:
                        Identifier
                            .sidebarPermissionAccessibilityStatus
                ),
                "已授予"
            ),
            (
                element(
                    in: app,
                    identifier:
                        Identifier
                            .sidebarPermissionScreenCaptureStatus
                ),
                "未授权"
            )
        ]

        for (status, expectedText) in statuses {
            XCTAssertTrue(status.exists)
            XCTAssertEqual(elementStringValue(status), expectedText)
            XCTAssertEqual(
                card.frame.maxX - status.frame.maxX,
                FlowTabUITestHomePermissionLayoutOracle
                    .compactTrailingInset,
                accuracy:
                    FlowTabUITestHomePermissionLayoutOracle
                        .frameAccuracy
            )
        }
    }

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
                minimumHiddenApps: 1
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

    func testHomePermissionBoundaryRemainsResolvedAcrossRepeatedTabSwitches() {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "-showPermissionReminder",
                "YES",
                "--flowtab-ui-ax-trusted",
                "NO",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(app)
        assertHomeAndLogsApplicationIsForegroundReady(app)

        for cycle in 0..<4 {
            for target in [
                FlowTabUITestSidebarTabProjectionTarget.logs,
                .settings,
                .home
            ] {
                guard assertSidebarTabProjectionAfterNavigation(
                    in: app,
                    target: target
                ) else {
                    XCTFail(
                        "Permission-boundary navigation failed. "
                            + "cycle=\(cycle) target=\(target.rawValue)"
                    )
                    return
                }
            }
        }

        let flowTabBundleIdentifier =
            FlowTabUITestAppIdentity.configured().bundleIdentifier
        let flowTabRow = element(
            in: app,
            identifier:
                "flowtab.home.app."
                + flowTabBundleIdentifier
                    .flowTabUITestAccessibilityIdentifierComponent
        )
        XCTAssertTrue(flowTabRow.waitForExistence(timeout: 5))
        XCTAssertEqual(elementStringValue(flowTabRow), "0w hidden")
        XCTAssertTrue(
            element(in: app, identifier: Identifier.permissionOpenSettings)
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            element(in: app, identifier: Identifier.permissionDismiss)
                .waitForExistence(timeout: 5)
        )
        assertValue(
            of: element(
                in: app,
                identifier: Identifier.homeStatsTotalWindows
            ),
            equals: "0"
        )
    }
}
