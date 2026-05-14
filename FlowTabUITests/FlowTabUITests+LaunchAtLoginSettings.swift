import XCTest

extension FlowTabUITests {
    func testSettingsLaunchAtLoginToggleDefaultsOffAndPersistsAcrossRelaunch() throws {
        let firstLaunchApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-launch-at-login-service",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(firstLaunchApp)
        openSettingsTab(in: firstLaunchApp)

        let launchAtLoginToggle = toggleElement(
            in: firstLaunchApp,
            identifier: Identifier.settingsPermissionLaunchAtLogin
        )
        XCTAssertTrue(launchAtLoginToggle.waitForExistence(timeout: 5))
        XCTAssertFalse(toggleIsOn(launchAtLoginToggle))

        setToggle(launchAtLoginToggle, to: true)
        XCTAssertTrue(toggleIsOn(launchAtLoginToggle))

        firstLaunchApp.terminate()

        let relaunchApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-mock-launch-at-login-service",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(relaunchApp)
        openSettingsTab(in: relaunchApp)

        let relaunchToggle = toggleElement(
            in: relaunchApp,
            identifier: Identifier.settingsPermissionLaunchAtLogin
        )
        XCTAssertTrue(relaunchToggle.waitForExistence(timeout: 5))
        XCTAssertTrue(toggleIsOn(relaunchToggle))
    }
}
