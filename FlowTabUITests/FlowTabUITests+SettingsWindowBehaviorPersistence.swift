import XCTest

extension FlowTabUITests {
    func testSettingsWindowBehaviorDelayAndTogglesPersistAcrossRelaunch() throws {
        let firstLaunchApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-runtime-log-level",
                "debug",
                "--flowtab-ui-record-hotkey-reload-diagnostics",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(firstLaunchApp)
        guard let controls =
            assertSettingsWindowBehaviorControlsProjectionAfterNavigation(
                in: firstLaunchApp,
                targetDescription: "delay and toggle persistence",
                trigger: {
                    openSettingsTab(in: firstLaunchApp)
                }
            )
        else {
            return
        }

        let delayInput = controls.delayInput
        replaceText(in: delayInput, with: "1.2345", app: firstLaunchApp)
        assertTriggerMakesValue(
            of: delayInput,
            equals: "1.23"
        ) {
            firstLaunchApp.typeKey(.tab, modifierFlags: [])
        }

        let autoRestoreToggle = controls.autoRestoreToggle
        let hideMinimizedToggle = controls.hideMinimizedToggle

        let expectedAutoRestore = !toggleIsOn(autoRestoreToggle)
        let expectedHideMinimized = !toggleIsOn(hideMinimizedToggle)
        setToggle(autoRestoreToggle, to: expectedAutoRestore)
        setToggle(hideMinimizedToggle, to: expectedHideMinimized)

        firstLaunchApp.terminate()

        let relaunchApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(relaunchApp)
        openSettingsTab(in: relaunchApp)

        let relaunchDelayInput = element(
            in: relaunchApp,
            identifier: Identifier.settingsWindowAutoEnterDelayInput
        )
        assertValuePrefix(
            of: relaunchDelayInput,
            expectedPrefix: "1.23"
        )
        XCTAssertEqual(
            toggleIsOn(
                toggleElement(
                    in: relaunchApp,
                    identifier:
                        Identifier.settingsWindowAutoRestoreMinimized
                )
            ),
            expectedAutoRestore
        )
        XCTAssertEqual(
            toggleIsOn(
                toggleElement(
                    in: relaunchApp,
                    identifier:
                        Identifier.settingsWindowHideMinimizedApps
                )
            ),
            expectedHideMinimized
        )
    }
}
