import Foundation
import XCTest

private enum FlowTabUITestPermissionObservationPolicy {
    static let settingsInitialProjectionWatchdog: TimeInterval = 5
}

private struct FlowTabUITestSettingsPermissionInitialProjectionSnapshot:
    Equatable
{
    let accessibilityDeniedStatusExists: Bool
    let screenCaptureDeniedStatusExists: Bool
    let accessibilityActionExists: Bool
    let screenCaptureActionExists: Bool

    var isSatisfied: Bool {
        accessibilityDeniedStatusExists
            && screenCaptureDeniedStatusExists
            && accessibilityActionExists
            && screenCaptureActionExists
    }

    var diagnosticSummary: String {
        "accessibilityDeniedStatusExists="
            + "\(accessibilityDeniedStatusExists) "
            + "screenCaptureDeniedStatusExists="
            + "\(screenCaptureDeniedStatusExists) "
            + "accessibilityActionExists="
            + "\(accessibilityActionExists) "
            + "screenCaptureActionExists="
            + "\(screenCaptureActionExists)"
    }
}

extension FlowTabUITests {
    func testSettingsPermissionInitialProjectionPolicyPreservesWatchdog() {
        XCTAssertEqual(
            FlowTabUITestPermissionObservationPolicy
                .settingsInitialProjectionWatchdog,
            5
        )
    }

    func testSettingsPermissionInitialProjectionRequiresEveryExactElement() {
        for mask in 0..<16 {
            let snapshot =
                FlowTabUITestSettingsPermissionInitialProjectionSnapshot(
                    accessibilityDeniedStatusExists:
                        mask & 1 != 0,
                    screenCaptureDeniedStatusExists:
                        mask & 2 != 0,
                    accessibilityActionExists:
                        mask & 4 != 0,
                    screenCaptureActionExists:
                        mask & 8 != 0
                )

            XCTAssertEqual(
                snapshot.isSatisfied,
                mask == 15,
                "mask=\(mask) \(snapshot.diagnosticSummary)"
            )
        }
    }

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
        let permissionActionIdentifier =
            Identifier.permissionOpenSettings
        let permissionAction = element(
            in: app,
            identifier: permissionActionIdentifier
        )
        let permissionProjectionObservation =
            FlowTabUITestConditionObservationOwner(
                observationRegistration:
                    FlowTabUITestConditionReadbackScheduler
                        .mainRunLoopRegistration(
                            cadence:
                                FlowTabUITestConditionObservationPolicy
                                    .xcuiReadbackCadence
                        ),
                readback: { permissionAction.exists },
                isSatisfied: { $0 },
                describe: {
                    "element=\(permissionActionIdentifier) exists=\($0)"
                }
            )
        permissionProjectionObservation.start()
        defer { permissionProjectionObservation.cancel() }

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

        let permissionProjectionEvidence =
            permissionProjectionObservation.waitForResolution(
                timeout:
                    FlowTabUITestSupportWatchdogPolicy
                        .permissionStateProjection
            )
        XCTAssertNotNil(
            permissionProjectionEvidence,
            "Home permission projection watchdog expired. "
                + permissionProjectionObservation.diagnosticSummary
        )
        guard permissionProjectionEvidence != nil else { return }
        let logSnapshot = makeRuntimeLogFileSnapshot()
        let permissionTransitionObservation =
            FlowTabUITestConditionObservationOwner(
                observationRegistration:
                    FlowTabUITestConditionReadbackScheduler
                        .mainRunLoopRegistration(
                            cadence:
                                FlowTabUITestConditionObservationPolicy
                                    .xcuiReadbackCadence
                        ),
                readback: { permissionAction.exists },
                isSatisfied: { !$0 },
                describe: {
                    "element=\(permissionActionIdentifier) exists=\($0)"
                }
            )
        permissionTransitionObservation.start()
        defer { permissionTransitionObservation.cancel() }

        try writePermissionState(
            accessibilityTrusted: true,
            screenCaptureTrusted: true,
            to: stateURL
        )
        permissionTransitionObservation.requestReadback(
            source: .triggerReadback
        )

        let permissionTransitionEvidence =
            permissionTransitionObservation.waitForResolution(
                timeout:
                    FlowTabUITestSupportWatchdogPolicy
                        .permissionStateProjection
            )
        XCTAssertNotNil(
            permissionTransitionEvidence,
            "Home permission transition watchdog expired. "
                + permissionTransitionObservation.diagnosticSummary
        )
        guard permissionTransitionEvidence != nil else { return }
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
        let accessibilityDeniedStatus =
            app.staticTexts["辅助功能权限：未授权"]
        let screenCaptureDeniedStatus =
            app.staticTexts["屏幕录制权限：未授权"]
        let accessibilityAction = element(
            in: app,
            identifier: Identifier.settingsPermissionAccessibilityAction
        )
        let screenCaptureAction = element(
            in: app,
            identifier: Identifier.settingsPermissionScreenCaptureAction
        )
        let initialProjectionObservation =
            FlowTabUITestConditionObservationOwner(
                observationRegistration:
                    FlowTabUITestConditionReadbackScheduler
                        .mainRunLoopRegistration(
                            cadence:
                                FlowTabUITestConditionObservationPolicy
                                    .xcuiReadbackCadence
                        ),
                readback: {
                    FlowTabUITestSettingsPermissionInitialProjectionSnapshot(
                        accessibilityDeniedStatusExists:
                            accessibilityDeniedStatus.exists,
                        screenCaptureDeniedStatusExists:
                            screenCaptureDeniedStatus.exists,
                        accessibilityActionExists:
                            accessibilityAction.exists,
                        screenCaptureActionExists:
                            screenCaptureAction.exists
                    )
                },
                isSatisfied: \.isSatisfied,
                describe: \.diagnosticSummary
            )
        initialProjectionObservation.start()
        defer { initialProjectionObservation.cancel() }
        openSettingsTab(in: app)
        initialProjectionObservation.requestReadback(
            source: .triggerReadback
        )
        let initialProjectionEvidence =
            initialProjectionObservation.waitForResolution(
                timeout:
                    FlowTabUITestPermissionObservationPolicy
                        .settingsInitialProjectionWatchdog
            )
        XCTAssertNotNil(
            initialProjectionEvidence,
            "Settings permission initial projection watchdog expired. "
                + initialProjectionObservation.diagnosticSummary
        )
        guard initialProjectionEvidence != nil else { return }

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
