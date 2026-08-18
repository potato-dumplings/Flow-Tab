import Foundation
import XCTest

private enum SpaceFixtureWorkflowPermissionObservationTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testSpaceFixturePermissionSnapshotRequiresCompleteTerminalProjection() {
        let grantedEnglish = permissionSnapshot(
            accessibilityStatusLabel: "Granted",
            screenCaptureStatusLabel: "Granted"
        )
        let grantedChinese = permissionSnapshot(
            accessibilityStatusLabel: "已授予",
            screenCaptureStatusLabel: "已授予"
        )
        let missing = permissionSnapshot(
            accessibilityStatusLabel: "Missing",
            screenCaptureStatusLabel: "Granted",
            bannerExists: true,
            openSettingsCandidateCount: 1,
            openSettingsHittable: true,
            dismissActionExists: true
        )

        XCTAssertEqual(grantedEnglish.projection, .granted)
        XCTAssertEqual(grantedChinese.projection, .granted)
        XCTAssertEqual(missing.projection, .missing)

        XCTAssertEqual(
            permissionSnapshot(
                accessibilityStatusLabel: "Granted",
                screenCaptureStatusLabel: ""
            ).projection,
            .projecting
        )
        XCTAssertEqual(
            permissionSnapshot(
                accessibilityStatusLabel: "Granted",
                screenCaptureStatusLabel: "Unknown"
            ).projection,
            .projecting
        )
        XCTAssertEqual(
            permissionSnapshot(
                accessibilityStatusLabel: "Missing",
                screenCaptureStatusLabel: "Granted",
                bannerExists: true,
                openSettingsCandidateCount: 1,
                openSettingsHittable: false,
                dismissActionExists: true
            ).projection,
            .projecting
        )
        XCTAssertEqual(
            permissionSnapshot(
                accessibilityStatusLabel: "Missing",
                screenCaptureStatusLabel: "Granted",
                bannerExists: true,
                openSettingsHittable: true,
                dismissActionExists: true
            ).projection,
            .projecting
        )
    }

    func testSpaceFixturePermissionObservationAcceptsInitialGrantedProjection() {
        let snapshot = permissionSnapshot(
            accessibilityStatusLabel: "Granted",
            screenCaptureStatusLabel: "Granted"
        )
        let owner =
            SpaceFixtureWorkflowPermissionObservationOwner(
                observationRegistration: nil,
                readback: { snapshot }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .initialReadback
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value.projection,
            .granted
        )
    }

    func testSpaceFixturePermissionObservationResolvesExactMissingSurface() {
        var snapshot = permissionSnapshot(
            accessibilityStatusLabel: "",
            screenCaptureStatusLabel: ""
        )
        var readback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            SpaceFixtureWorkflowPermissionObservationOwner(
                observationRegistration: { callback in
                    readback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: { snapshot }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(
            owner.latestEvidence?.value.projection,
            .projecting
        )
        for _ in 0..<20 {
            readback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }
        snapshot = permissionSnapshot(
            accessibilityStatusLabel: "Missing",
            screenCaptureStatusLabel: "Granted",
            bannerExists: true,
            openSettingsCandidateCount: 1,
            openSettingsHittable: true,
            dismissActionExists: true
        )
        readback?(.triggerReadback)
        readback?(.scheduledReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .triggerReadback
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value.projection,
            .missing
        )
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSpaceFixturePermissionObservationRejectsStaleCallbacksUnderPressure() {
        for _ in
            0..<SpaceFixtureWorkflowPermissionObservationTestPolicy
                .pressureIterations
        {
            var snapshot = permissionSnapshot(
                accessibilityStatusLabel: "",
                screenCaptureStatusLabel: ""
            )
            var callbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            let owner =
                SpaceFixtureWorkflowPermissionObservationOwner(
                    observationRegistration: { callback in
                        callbacks.append(callback)
                        return FlowTabUITestObservationCancellation {}
                    },
                    readback: { snapshot }
                )
            owner.start()
            let staleReadback = callbacks[0]
            owner.cancel()
            owner.start()

            snapshot = permissionSnapshot(
                accessibilityStatusLabel: "Granted",
                screenCaptureStatusLabel: "Granted"
            )
            staleReadback(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
            callbacks[1](.scheduledReadback)
            callbacks[1](.triggerReadback)
            XCTAssertEqual(owner.resolvedEvidence?.generation, 2)
            owner.cancel()
        }
    }

    func testSpaceFixturePermissionObservationWatchdogReportsFinalProjection() {
        let owner =
            SpaceFixtureWorkflowPermissionObservationOwner(
                observationRegistration: nil,
                readback: {
                    self.permissionSnapshot(
                        accessibilityStatusLabel: "Missing",
                        screenCaptureStatusLabel: "Granted",
                        bannerExists: true,
                        openSettingsCandidateCount: 1,
                        openSettingsHittable: false,
                        dismissActionExists: true
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    SpaceFixtureWorkflowPermissionObservationTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "projection=projecting"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "openSettingsHittable=false"
            )
        )
    }

    func testSpaceFixturePermissionPreflightResolvesExactGrantedProjection() {
        XCTAssertTrue(
            assertSpaceFixtureWorkflowPermissionsAvailable()
        )
    }

    func testHomePermissionStatusPublishesExactGrantedAccessibilityEvidence() {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "-showPermissionReminder",
                "NO",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES",
            ]
        )
        launchFlowTabUITestApplication(app)
        defer {
            if app.state == .runningForeground
                || app.state == .runningBackground
            {
                app.terminate()
            }
        }
        XCTAssertTrue(
            waitForFlowTabUITestApplicationToBecomeReady(
                app,
                timeout:
                    FlowTabUITestSupportWatchdogPolicy
                        .foregroundActivation
            )
        )
        XCTAssertTrue(
            tapFirstHittable(
                in: app.buttons.matching(
                    identifier: Identifier.homeTabButton
                ),
                timeout:
                    FlowTabUITestSupportWatchdogPolicy
                        .tabNavigation
            )
        )

        let accessibilityStatus = element(
            in: app,
            identifier:
                Identifier.sidebarPermissionAccessibilityStatus
        )
        let screenCaptureStatus = element(
            in: app,
            identifier:
                Identifier.sidebarPermissionScreenCaptureStatus
        )
        XCTAssertTrue(
            accessibilityStatus.waitForExistence(
                timeout:
                    FlowTabUITestSupportWatchdogPolicy
                        .permissionStateProjection
            )
        )
        XCTAssertTrue(
            screenCaptureStatus.waitForExistence(
                timeout:
                    FlowTabUITestSupportWatchdogPolicy
                        .permissionStateProjection
            )
        )
        XCTAssertTrue(
            SpaceFixtureWorkflowPermissionSnapshot
                .grantedStatusLabels
                .contains(accessibilityStatus.label),
            "Unexpected Accessibility status: \(accessibilityStatus.label)"
        )
        XCTAssertTrue(
            SpaceFixtureWorkflowPermissionSnapshot
                .grantedStatusLabels
                .contains(screenCaptureStatus.label),
            "Unexpected Screen Recording status: \(screenCaptureStatus.label)"
        )
    }

    private func permissionSnapshot(
        accessibilityStatusLabel: String,
        screenCaptureStatusLabel: String,
        bannerExists: Bool = false,
        openSettingsCandidateCount: Int = 0,
        openSettingsHittable: Bool = false,
        dismissActionExists: Bool = false
    ) -> SpaceFixtureWorkflowPermissionSnapshot {
        SpaceFixtureWorkflowPermissionSnapshot(
            applicationState: "runningForeground",
            statusCardExists: true,
            accessibilityRowExists: true,
            screenCaptureRowExists: true,
            accessibilityStatusExists: true,
            accessibilityStatusLabel: accessibilityStatusLabel,
            screenCaptureStatusExists: true,
            screenCaptureStatusLabel: screenCaptureStatusLabel,
            bannerExists: bannerExists,
            openSettingsCandidateCount:
                openSettingsCandidateCount,
            openSettingsHittable: openSettingsHittable,
            dismissActionExists: dismissActionExists
        )
    }
}
