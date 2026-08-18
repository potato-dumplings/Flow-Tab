import Foundation
import XCTest

enum FlowTabUITestLaunchAtLoginSettingsPolicy {
    static let togglePublicationWatchdog: TimeInterval = 5
}

extension FlowTabUITests {
    func testLaunchAtLoginSettingsWatchdogRemainsTerminalBound() {
        XCTAssertEqual(
            FlowTabUITestLaunchAtLoginSettingsPolicy
                .togglePublicationWatchdog,
            5
        )
        XCTAssertTrue(
            FlowTabUITestLaunchAtLoginSettingsPolicy
                .togglePublicationWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestLaunchAtLoginSettingsPolicy
                .togglePublicationWatchdog,
            0
        )
    }

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
        assertLaunchAtLoginToggleExists(
            launchAtLoginToggle,
            phase: "firstLaunch"
        )
        XCTAssertFalse(
            toggleIsOn(launchAtLoginToggle),
            "expectedState=off phase=firstLaunch "
                + "finalValue=\(String(describing: launchAtLoginToggle.value))"
        )

        setToggle(launchAtLoginToggle, to: true)
        XCTAssertTrue(
            toggleIsOn(launchAtLoginToggle),
            "expectedState=on phase=postToggle "
                + "finalValue=\(String(describing: launchAtLoginToggle.value))"
        )

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
        assertLaunchAtLoginToggleExists(
            relaunchToggle,
            phase: "relaunch"
        )
        XCTAssertTrue(
            toggleIsOn(relaunchToggle),
            "expectedState=on phase=relaunch "
                + "finalValue=\(String(describing: relaunchToggle.value))"
        )
    }

    private func assertLaunchAtLoginToggleExists(
        _ toggle: XCUIElement,
        phase: String
    ) {
        let didExist = toggle.waitForExistence(
            timeout:
                FlowTabUITestLaunchAtLoginSettingsPolicy
                    .togglePublicationWatchdog
        )
        let finalExists = toggle.exists
        let finalValue = finalExists
            ? String(describing: toggle.value)
            : "unavailable"
        XCTAssertTrue(
            didExist,
            "unmetCondition=launchAtLoginToggle.exists "
                + "phase=\(phase) finalExists=\(finalExists) "
                + "finalValue=\(finalValue)"
        )
    }
}
