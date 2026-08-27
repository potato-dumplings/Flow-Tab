import XCTest

extension FlowTabUITests {
    func testSettingsRemainsInteractiveAcrossRepeatedTabNavigation() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(app)
        assertHomeAndLogsApplicationIsForegroundReady(app)

        for _ in 0..<3 {
            for target in [
                FlowTabUITestSidebarTabProjectionTarget.logs,
                .settings,
                .home
            ] {
                guard assertSidebarTabProjectionAfterNavigation(
                    in: app,
                    target: target
                ) else {
                    return
                }
                guard target == .settings else { continue }

                let settingsContent = element(
                    in: app,
                    identifier: Identifier.settingsTabContent
                )
                let subtitle = element(
                    in: app,
                    identifier: Identifier.settingsPageSubtitle
                )
                let themeControl = element(
                    in: app,
                    identifier: Identifier.settingsAppearanceThemeMode
                )
                XCTAssertTrue(settingsContent.exists)
                XCTAssertTrue(
                    subtitle.waitForExistence(
                        timeout: FlowTabUITestSupportWatchdogPolicy
                            .briefElementDiscovery
                    )
                )
                XCTAssertTrue(
                    themeControl.waitForExistence(
                        timeout: FlowTabUITestSupportWatchdogPolicy
                            .briefElementDiscovery
                    )
                )
                XCTAssertTrue(themeControl.isHittable)
            }
        }
    }
}
