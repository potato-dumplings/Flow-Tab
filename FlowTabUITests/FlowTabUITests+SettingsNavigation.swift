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

    func testSettingsInputStopsReceivingKeysAfterTabNavigation() throws {
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

        guard let controls =
            assertSettingsWindowBehaviorControlsProjectionAfterNavigation(
                in: app,
                targetDescription: "hidden Settings input responder",
                trigger: {
                    openSettingsTab(in: app)
                }
            )
        else {
            return
        }

        replaceText(in: controls.delayInput, with: "1.23", app: app)
        assertValuePrefix(
            of: controls.delayInput,
            expectedPrefix: "1.23"
        )

        guard assertSidebarTabProjectionAfterNavigation(
            in: app,
            target: .logs
        ) else {
            return
        }
        app.typeKey("a", modifierFlags: .command)
        app.typeText("4.56")

        guard assertSidebarTabProjectionAfterNavigation(
            in: app,
            target: .settings
        ) else {
            return
        }
        assertValuePrefix(
            of: element(
                in: app,
                identifier: Identifier.settingsWindowAutoEnterDelayInput
            ),
            expectedPrefix: "1.23"
        )
    }
}
