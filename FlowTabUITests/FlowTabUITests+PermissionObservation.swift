import Foundation
import XCTest

extension FlowTabUITests {
    func testHomePermissionBannerConvergesFromOwnedTCCReadbackEvidence() throws {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "flowtab-ui-home-permission-state-\(UUID().uuidString).json",
                isDirectory: false
            )
        defer {
            try? FileManager.default.removeItem(at: stateURL)
        }
        try writePermissionState(
            accessibilityTrusted: false,
            screenCaptureTrusted: false,
            to: stateURL
        )

        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-runtime-log-level",
                "INFO",
                "--flowtab-ui-enable-verbose-logs",
                "--flowtab-ui-permission-state-path",
                stateURL.path
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
            "Home permission foreground watchdog expired. "
                + "finalState=\(String(describing: app.state))"
        )
        guard foregroundReadinessSatisfied else { return }
        let homeTabButtons = app.buttons.matching(
            identifier: Identifier.homeTabButton
        )
        let homeContent = element(
            in: app,
            identifier: Identifier.homeTabContent
        )
        let navigationSatisfied =
            tapFirstHittableAndWaitForExistence(
                in: homeTabButtons,
                content: homeContent,
                contentDescription: Identifier.homeTabContent,
                timeout:
                    FlowTabUITestSupportWatchdogPolicy
                        .tabNavigation
            )
        XCTAssertTrue(
            navigationSatisfied,
            "Home permission navigation watchdog expired. "
                + "finalCandidateCount=\(homeTabButtons.count) "
                + "finalContentExists=\(homeContent.exists)"
        )
        guard navigationSatisfied else { return }

        let permissionAction = element(
            in: app,
            identifier: Identifier.permissionOpenSettings
        )
        XCTAssertTrue(permissionAction.waitForExistence(timeout: 5))
        let logSnapshot = makeRuntimeLogFileSnapshot()

        try writePermissionState(
            accessibilityTrusted: true,
            screenCaptureTrusted: true,
            to: stateURL
        )

        XCTAssertTrue(
            waitForNonExistence(permissionAction, timeout: 6)
        )
        waitForRuntimeLogFiles(
            containing: [
                "home permission observed target=accessibility source=fallbackReadback granted=true",
                "home permission observed target=screenCapture source=fallbackReadback granted=true"
            ],
            since: logSnapshot
        )
    }

    func testSettingsPermissionRequestsConvergeFromTCCReadbackEvidence() throws {
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "flowtab-ui-permission-state-\(UUID().uuidString).json",
                isDirectory: false
            )
        defer {
            try? FileManager.default.removeItem(at: stateURL)
        }
        try writePermissionState(
            accessibilityTrusted: false,
            screenCaptureTrusted: false,
            to: stateURL
        )

        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-runtime-log-level",
                "INFO",
                "--flowtab-ui-enable-verbose-logs",
                "--flowtab-ui-permission-state-path",
                stateURL.path
            ]
        )
        launchFlowTabUITestApplication(app)
        openSettingsTab(in: app)

        XCTAssertTrue(
            app.staticTexts["辅助功能权限：未授权"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.staticTexts["屏幕录制权限：未授权"].waitForExistence(timeout: 5)
        )
        let accessibilityAction = element(
            in: app,
            identifier: Identifier.settingsPermissionAccessibilityAction
        )
        let screenCaptureAction = element(
            in: app,
            identifier: Identifier.settingsPermissionScreenCaptureAction
        )
        XCTAssertTrue(accessibilityAction.waitForExistence(timeout: 5))
        XCTAssertTrue(screenCaptureAction.waitForExistence(timeout: 5))

        let logSnapshot = makeRuntimeLogFileSnapshot()
        tapElement(accessibilityAction)
        tapElement(screenCaptureAction)
        try writePermissionState(
            accessibilityTrusted: true,
            screenCaptureTrusted: true,
            to: stateURL
        )

        XCTAssertTrue(
            app.staticTexts["辅助功能权限：已授权"].waitForExistence(timeout: 6)
        )
        XCTAssertTrue(
            app.staticTexts["屏幕录制权限：已授权"].waitForExistence(timeout: 6)
        )
        waitForRuntimeLogFiles(
            containing: [
                "permission observed target=accessibility source=fallbackReadback",
                "permission observed target=screenCapture source=fallbackReadback"
            ],
            since: logSnapshot
        )
    }

    private func writePermissionState(
        accessibilityTrusted: Bool,
        screenCaptureTrusted: Bool,
        to stateURL: URL
    ) throws {
        let payload: [String: Bool] = [
            "accessibilityTrusted": accessibilityTrusted,
            "screenCaptureTrusted": screenCaptureTrusted
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        try data.write(to: stateURL, options: .atomic)
    }
}
