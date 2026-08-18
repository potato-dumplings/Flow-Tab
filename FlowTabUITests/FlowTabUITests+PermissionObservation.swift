import Foundation
import XCTest

private enum FlowTabUITestPermissionObservationPolicy {
    static let settingsInitialProjectionWatchdog: TimeInterval = 5
    static let homeVisibleControlsBaselineWatchdog: TimeInterval = 5
    static let homeHiddenProjectionWatchdog: TimeInterval = 2
}

enum FlowTabUITestHomePermissionProjectionBaselineRequirement {
    case unconstrained
    case visiblePermissionControls
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

private struct FlowTabUITestSettingsPermissionGrantedProjectionSnapshot:
    Equatable
{
    let accessibilityGrantedStatusExists: Bool
    let screenCaptureGrantedStatusExists: Bool

    var isSatisfied: Bool {
        accessibilityGrantedStatusExists
            && screenCaptureGrantedStatusExists
    }

    var diagnosticSummary: String {
        "accessibilityGrantedStatusExists="
            + "\(accessibilityGrantedStatusExists) "
            + "screenCaptureGrantedStatusExists="
            + "\(screenCaptureGrantedStatusExists)"
    }
}

private struct FlowTabUITestHomeHiddenPermissionProjectionSnapshot:
    Equatable
{
    let applicationState: XCUIApplication.State
    let homeContentExists: Bool
    let permissionBannerExists: Bool
    let permissionActionExists: Bool
    let permissionDismissExists: Bool

    var isSatisfied: Bool {
        applicationIsRunning
            && homeContentExists
            && !permissionBannerExists
            && !permissionActionExists
            && !permissionDismissExists
    }

    var hasVisiblePermissionControls: Bool {
        applicationIsRunning
            && homeContentExists
            && permissionActionExists
            && permissionDismissExists
    }

    var diagnosticSummary: String {
        "applicationState=\(String(describing: applicationState)) "
            + "homeContentExists=\(homeContentExists) "
            + "permissionBannerExists=\(permissionBannerExists) "
            + "permissionActionExists=\(permissionActionExists) "
            + "permissionDismissExists=\(permissionDismissExists)"
    }

    private var applicationIsRunning: Bool {
        applicationState == .runningForeground
            || applicationState == .runningBackground
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

    func testSettingsPermissionGrantedProjectionRequiresBothExactStatuses() {
        for mask in 0..<4 {
            let snapshot =
                FlowTabUITestSettingsPermissionGrantedProjectionSnapshot(
                    accessibilityGrantedStatusExists:
                        mask & 1 != 0,
                    screenCaptureGrantedStatusExists:
                        mask & 2 != 0
                )

            XCTAssertEqual(
                snapshot.isSatisfied,
                mask == 3,
                "mask=\(mask) \(snapshot.diagnosticSummary)"
            )
        }
    }

    func testHomeHiddenPermissionProjectionPolicyPreservesWatchdog() {
        XCTAssertEqual(
            FlowTabUITestPermissionObservationPolicy
                .homeHiddenProjectionWatchdog,
            2
        )
        XCTAssertTrue(
            FlowTabUITestPermissionObservationPolicy
                .homeHiddenProjectionWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestPermissionObservationPolicy
                .homeHiddenProjectionWatchdog,
            0
        )
    }

    func testHomeVisiblePermissionControlsBaselinePolicyPreservesWatchdog() {
        let watchdog =
            FlowTabUITestPermissionObservationPolicy
                .homeVisibleControlsBaselineWatchdog
        XCTAssertEqual(watchdog, 5)
        XCTAssertTrue(watchdog.isFinite)
        XCTAssertGreaterThan(watchdog, 0)
    }

    func testHomeHiddenPermissionProjectionRequiresLoadedContentAndAbsence() {
        for mask in 0..<16 {
            let snapshot =
                FlowTabUITestHomeHiddenPermissionProjectionSnapshot(
                    applicationState: .runningForeground,
                    homeContentExists: mask & 1 != 0,
                    permissionBannerExists: mask & 2 != 0,
                    permissionActionExists: mask & 4 != 0,
                    permissionDismissExists: mask & 8 != 0
                )

            XCTAssertEqual(
                snapshot.isSatisfied,
                mask == 1,
                "mask=\(mask) \(snapshot.diagnosticSummary)"
            )
            XCTAssertEqual(
                snapshot.hasVisiblePermissionControls,
                mask & 13 == 13,
                "mask=\(mask) \(snapshot.diagnosticSummary)"
            )
        }
        let stoppedSnapshot =
            FlowTabUITestHomeHiddenPermissionProjectionSnapshot(
                applicationState: .notRunning,
                homeContentExists: true,
                permissionBannerExists: true,
                permissionActionExists: true,
                permissionDismissExists: true
            )
        XCTAssertFalse(stoppedSnapshot.isSatisfied)
        XCTAssertFalse(
            stoppedSnapshot.hasVisiblePermissionControls
        )
    }

    func assertHomePermissionBannerHiddenProjection(
        in app: XCUIApplication,
        targetDescription: String,
        baselineRequirement:
            FlowTabUITestHomePermissionProjectionBaselineRequirement =
                .unconstrained,
        trigger: () -> Void
    ) {
        let homeContent = element(
            in: app,
            identifier: Identifier.homeTabContent
        )
        let permissionBanner = element(
            in: app,
            identifier: Identifier.permissionBanner
        )
        let permissionAction = element(
            in: app,
            identifier: Identifier.permissionOpenSettings
        )
        let permissionDismiss = element(
            in: app,
            identifier: Identifier.permissionDismiss
        )
        var triggerCompleted = false
        let deferredReadbacks =
            FlowTabUITestDeferredConditionReadbackRegistration(
                downstreamRegistration:
                    FlowTabUITestConditionReadbackScheduler
                        .mainRunLoopRegistration(
                            cadence:
                                FlowTabUITestConditionObservationPolicy
                                    .xcuiReadbackCadence
                        )
            )
        let readback: () ->
            FlowTabUITestHomeHiddenPermissionProjectionSnapshot = {
                let applicationState = app.state
                guard applicationState == .runningForeground
                        || applicationState == .runningBackground
                else {
                    return FlowTabUITestHomeHiddenPermissionProjectionSnapshot(
                        applicationState: applicationState,
                        homeContentExists: false,
                        permissionBannerExists: false,
                        permissionActionExists: false,
                        permissionDismissExists: false
                    )
                }
                return FlowTabUITestHomeHiddenPermissionProjectionSnapshot(
                    applicationState: applicationState,
                    homeContentExists: homeContent.exists,
                    permissionBannerExists: permissionBanner.exists,
                    permissionActionExists: permissionAction.exists,
                    permissionDismissExists: permissionDismiss.exists
                )
            }
        let observation =
            FlowTabUITestConditionObservationOwner(
                observationRegistration: {
                    readback in
                    deferredReadbacks.register(readback)
                },
                readback: readback,
                isSatisfied: {
                    triggerCompleted && $0.isSatisfied
                },
                describe: {
                    "target=\(targetDescription) "
                        + "acceptanceEnabled=\(triggerCompleted) "
                        + $0.diagnosticSummary
                }
            )
        observation.start()
        defer {
            observation.cancel()
            deferredReadbacks.cancel()
        }

        XCTAssertEqual(
            observation.latestEvidence?.source,
            .initialReadback
        )
        XCTAssertNil(observation.resolvedEvidence)
        if baselineRequirement == .visiblePermissionControls {
            guard waitForHomePermissionVisibleControlsBaseline(
                initialSnapshot: observation.latestEvidence?.value,
                readback: readback,
                targetDescription: targetDescription
            ) else {
                return
            }
        }

        trigger()
        triggerCompleted = true
        observation.requestReadback(source: .triggerReadback)
        if observation.resolvedEvidence == nil {
            deferredReadbacks.activate()
        }

        XCTAssertNotNil(
            observation.waitForResolution(
                timeout:
                    FlowTabUITestPermissionObservationPolicy
                        .homeHiddenProjectionWatchdog
            ),
            "Home hidden-permission projection watchdog expired. "
                + observation.diagnosticSummary
        )
    }

    private func waitForHomePermissionVisibleControlsBaseline(
        initialSnapshot:
            FlowTabUITestHomeHiddenPermissionProjectionSnapshot?,
        readback: @escaping () ->
            FlowTabUITestHomeHiddenPermissionProjectionSnapshot,
        targetDescription: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        if initialSnapshot?.hasVisiblePermissionControls == true {
            return true
        }

        let observation = FlowTabUITestConditionObservationOwner(
            readback: readback,
            isSatisfied: \.hasVisiblePermissionControls,
            describe: \.diagnosticSummary
        )
        observation.start()
        defer { observation.cancel() }

        guard observation.waitForResolution(
            timeout:
                FlowTabUITestPermissionObservationPolicy
                    .homeVisibleControlsBaselineWatchdog
        ) != nil else {
            XCTFail(
                "Home visible-permission-controls baseline watchdog "
                    + "expired. target=\(targetDescription) "
                    + observation.diagnosticSummary,
                file: file,
                line: line
            )
            return false
        }
        return true
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

    @discardableResult
    func assertInitialDeniedSettingsPermissionProjection(
        in app: XCUIApplication,
        trigger: () -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
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
        let observation = FlowTabUITestConditionObservationOwner(
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
                    accessibilityActionExists: accessibilityAction.exists,
                    screenCaptureActionExists: screenCaptureAction.exists
                )
            },
            isSatisfied: \.isSatisfied,
            describe: \.diagnosticSummary
        )
        observation.start()
        defer { observation.cancel() }

        trigger()
        observation.requestReadback(source: .triggerReadback)
        let evidence = observation.waitForResolution(
            timeout:
                FlowTabUITestPermissionObservationPolicy
                    .settingsInitialProjectionWatchdog
        )
        XCTAssertNotNil(
            evidence,
            "Settings permission initial projection watchdog expired. "
                + observation.diagnosticSummary,
            file: file,
            line: line
        )
        return evidence != nil
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
        let initialProjectionSatisfied =
            assertInitialDeniedSettingsPermissionProjection(in: app) {
                openSettingsTab(in: app)
            }
        guard initialProjectionSatisfied else { return }

        let accessibilityAction = element(
            in: app,
            identifier: Identifier.settingsPermissionAccessibilityAction
        )
        let screenCaptureAction = element(
            in: app,
            identifier: Identifier.settingsPermissionScreenCaptureAction
        )

        let accessibilityGrantedStatus =
            app.staticTexts["辅助功能权限：已授权"]
        let screenCaptureGrantedStatus =
            app.staticTexts["屏幕录制权限：已授权"]
        let grantedProjectionObservation =
            FlowTabUITestConditionObservationOwner(
                observationRegistration:
                    FlowTabUITestConditionReadbackScheduler
                        .mainRunLoopRegistration(
                            cadence:
                                FlowTabUITestConditionObservationPolicy
                                    .xcuiReadbackCadence
                        ),
                readback: {
                    FlowTabUITestSettingsPermissionGrantedProjectionSnapshot(
                        accessibilityGrantedStatusExists:
                            accessibilityGrantedStatus.exists,
                        screenCaptureGrantedStatusExists:
                            screenCaptureGrantedStatus.exists
                    )
                },
                isSatisfied: \.isSatisfied,
                describe: \.diagnosticSummary
            )
        grantedProjectionObservation.start()
        defer { grantedProjectionObservation.cancel() }
        guard let grantedProjectionBaseline =
            grantedProjectionObservation.latestEvidence
        else {
            XCTFail(
                "Settings permission granted projection has no baseline. "
                    + grantedProjectionObservation.diagnosticSummary
            )
            return
        }
        guard !grantedProjectionBaseline.value.isSatisfied else {
            XCTFail(
                "Settings permission granted projection baseline was "
                    + "already satisfied. "
                    + grantedProjectionObservation.diagnosticSummary
            )
            return
        }

        let logSnapshot = makeRuntimeLogFileSnapshot()
        tapElement(accessibilityAction)
        tapElement(screenCaptureAction)
        try writePermissionState(
            accessibilityTrusted: true,
            screenCaptureTrusted: true,
            to: stateURL
        )
        grantedProjectionObservation.requestReadback(
            source: .triggerReadback
        )
        let grantedProjectionEvidence =
            grantedProjectionObservation.waitForResolution(
                timeout:
                    FlowTabUITestSupportWatchdogPolicy
                        .permissionStateProjection
            )
        XCTAssertNotNil(
            grantedProjectionEvidence,
            "Settings permission granted projection watchdog expired. "
                + grantedProjectionObservation.diagnosticSummary
        )
        guard grantedProjectionEvidence != nil else { return }
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
