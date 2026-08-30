import Foundation
import XCTest

private enum TabSwitchRealPressureEnvironment {
    static let durationSeconds =
        "FLOWTAB_TAB_SWITCH_REAL_DURATION_SECONDS"
    static let intervalMilliseconds =
        "FLOWTAB_TAB_SWITCH_REAL_INTERVAL_MILLISECONDS"
    static let runtimeLogLevel =
        "FLOWTAB_TAB_SWITCH_REAL_RUNTIME_LOG_LEVEL"
    static let runtimeHome =
        "FLOWTAB_TAB_SWITCH_REAL_HOME"
    static let statusPath =
        "FLOWTAB_TAB_SWITCH_REAL_STATUS_PATH"
}

private struct TabSwitchRealPressureStatus: Codable {
    var schemaVersion = 1
    var lane = "real_permissions"
    var state = "preflight_pending"
    var runtimeLogLevel = "ERROR"
    var accessibilityAuthorized = false
    var screenRecordingAuthorized = false
    var homeApplicationCount = 0
    var homeWindowCount = 0
    var fixtureBundleIdentifier = ""
    var fixtureHit = false
    var homeWarmed = false
    var logsWarmed = false
    var settingsWarmed = false
    var requiredSwitches: UInt64 = 0
    var completedSwitches: UInt64 = 0
    var homeSwitches: UInt64 = 0
    var logsSwitches: UInt64 = 0
    var settingsSwitches: UInt64 = 0
    var stressStartedUptimeNanoseconds: UInt64 = 0
    var stressCompletedUptimeNanoseconds: UInt64 = 0
    var elapsedNanoseconds: UInt64 = 0
    var durationSatisfied = false
    var workloadSatisfied = false

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case lane
        case state
        case runtimeLogLevel = "runtime_log_level"
        case accessibilityAuthorized = "accessibility_authorized"
        case screenRecordingAuthorized = "screen_recording_authorized"
        case homeApplicationCount = "home_application_count"
        case homeWindowCount = "home_window_count"
        case fixtureBundleIdentifier = "fixture_bundle_identifier"
        case fixtureHit = "fixture_hit"
        case homeWarmed = "home_warmed"
        case logsWarmed = "logs_warmed"
        case settingsWarmed = "settings_warmed"
        case requiredSwitches = "required_switches"
        case completedSwitches = "completed_switches"
        case homeSwitches = "home_switches"
        case logsSwitches = "logs_switches"
        case settingsSwitches = "settings_switches"
        case stressStartedUptimeNanoseconds =
            "stress_started_uptime_nanoseconds"
        case stressCompletedUptimeNanoseconds =
            "stress_completed_uptime_nanoseconds"
        case elapsedNanoseconds = "elapsed_nanoseconds"
        case durationSatisfied = "duration_satisfied"
        case workloadSatisfied = "workload_satisfied"
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(
            to: url,
            options: .atomic
        )
    }
}

private struct TabSwitchRealPressureRoute {
    let evidence = TabSwitchStressUITestRoute()
    let startNotificationName = Notification.Name(
        "io.github.potato-dumplings.flowtab."
            + "tab-switch-real-start."
            + UUID().uuidString
    )

    var launchArguments: [String] {
        evidence.launchArguments + [
            "--flowtab-tab-stress-start-notification-name",
            startNotificationName.rawValue
        ]
    }
}

extension FlowTabUITests {
    func testRealPermissionTabSwitchPressureGate() throws {
        let environment = ProcessInfo.processInfo.environment
        let duration = max(
            1,
            Double(
                environment[
                    TabSwitchRealPressureEnvironment.durationSeconds
                ] ?? ""
            ) ?? 30
        )
        let interval = max(
            1,
            Double(
                environment[
                    TabSwitchRealPressureEnvironment
                        .intervalMilliseconds
                ] ?? ""
            ) ?? 20
        )
        let logLevel = environment[
            TabSwitchRealPressureEnvironment.runtimeLogLevel
        ] ?? "ERROR"
        let statusURL = URL(
            fileURLWithPath: environment[
                TabSwitchRealPressureEnvironment.statusPath
            ] ?? FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "flowtab-tab-switch-real-"
                        + UUID().uuidString
                        + ".json"
                ).path
        )
        let runtimeHomeURL = URL(
            fileURLWithPath: environment[
                TabSwitchRealPressureEnvironment.runtimeHome
            ] ?? FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "flowtab-tab-switch-real-home-"
                        + UUID().uuidString,
                    isDirectory: true
                ).path,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: runtimeHomeURL,
            withIntermediateDirectories: true
        )

        var status = TabSwitchRealPressureStatus()
        status.runtimeLogLevel = logLevel.uppercased()
        defer {
            do {
                try status.write(to: statusURL)
            } catch {
                XCTFail(
                    "Could not preserve real Tab pressure status: "
                        + error.localizedDescription
                )
            }
        }

        let workflow: SpaceFixtureResolvedWorkflow
        do {
            workflow = try SpaceFixtureResolvedWorkflow.configured()
        } catch {
            status.state = "fixture_projection_blocked"
            XCTFail(
                "Resolved fixture workflow is unavailable: "
                    + error.localizedDescription
            )
            return
        }
        let route = TabSwitchRealPressureRoute()
        let observation = TabSwitchStressUITestObservationOwner(
            route: route.evidence
        )
        observation.start()
        defer { observation.cancel() }

        let app = makeRealRuntimeFlowTabApp(
            showsPermissionReminder: true,
            additionalArguments: [
                "--flowtab-tab-stress",
                "--flowtab-tab-stress-duration",
                String(duration),
                "--flowtab-tab-stress-interval-ms",
                String(interval),
                "--flowtab-tab-stress-runtime-log-level",
                logLevel
            ] + route.launchArguments
        )
        app.launchEnvironment["HOME"] = runtimeHomeURL.path
        app.launchEnvironment["CFFIXED_USER_HOME"] =
            runtimeHomeURL.path
        launchFlowTabUITestApplication(app)
        defer {
            if app.state == .runningForeground
                || app.state == .runningBackground
            {
                app.terminate()
            }
        }

        let permissionsAvailable =
            assertSpaceFixtureWorkflowPermissionsAvailable(in: app)
        let accessibilityStatus = element(
            in: app,
            identifier:
                Identifier.sidebarPermissionAccessibilityStatus
        )
        let screenRecordingStatus = element(
            in: app,
            identifier:
                Identifier.sidebarPermissionScreenCaptureStatus
        )
        status.accessibilityAuthorized =
            SpaceFixtureWorkflowPermissionSnapshot
                .grantedStatusLabels
                .contains(elementStringValue(accessibilityStatus))
        status.screenRecordingAuthorized =
            SpaceFixtureWorkflowPermissionSnapshot
                .grantedStatusLabels
                .contains(elementStringValue(screenRecordingStatus))
        guard permissionsAvailable,
              status.accessibilityAuthorized,
              status.screenRecordingAuthorized
        else {
            status.state = "permission_blocked"
            return
        }

        let fixtureApps = launchResolvedSpaceFixtureWorkflow(
            workflow,
            waitsForFullscreenMarkers: true,
            suppressesAppAccessibilityChildren: false,
            preservesDesktopAfterFullscreen: true,
            applicationAXSuppressionRoutes: []
        )
        defer {
            for fixtureApp in fixtureApps.reversed()
            where fixtureApp.state == .runningForeground
                || fixtureApp.state == .runningBackground
            {
                terminateSpaceFixtureApplicationAndWait(
                    fixtureApp
                )
            }
        }

        app.activate()
        guard waitForFlowTabUITestApplicationToBecomeReady(
            app,
            timeout:
                FlowTabUITestSupportWatchdogPolicy
                    .foregroundActivation
        ) else {
            status.state = "fixture_projection_blocked"
            return
        }

        status.homeWarmed = assertSidebarTabProjectionAfterNavigation(
            in: app,
            target: .home
        )
        guard status.homeWarmed else {
            status.state = "page_warmup_blocked"
            return
        }
        guard let homeApplicationCount =
                waitForRealTabFixtureHomeProjection(
                    workflow,
                    in: app
                )
        else {
            status.state = "fixture_projection_blocked"
            return
        }
        status.homeApplicationCount = homeApplicationCount
        status.fixtureHit = true
        guard status.fixtureHit,
              let targetFixture = workflow.apps.first(where: {
                  !$0.expectedHomeWindowTitles.isEmpty
              }),
              let windowProjection =
                selectSpaceFixtureHomeAppAndWaitForExactWindowProjection(
                    targetFixture,
                    in: workflow,
                    app: app
                )
        else {
            status.state = "fixture_projection_blocked"
            return
        }
        status.fixtureBundleIdentifier =
            targetFixture.identity.bundleIdentifier
        status.homeWindowCount = windowProjection.rows.count

        status.logsWarmed = assertSidebarTabProjectionAfterNavigation(
            in: app,
            target: .logs
        )
        status.settingsWarmed =
            assertSidebarTabProjectionAfterNavigation(
                in: app,
                target: .settings
            )
        guard status.homeWarmed,
              status.logsWarmed,
              status.settingsWarmed
        else {
            status.state = "page_warmup_blocked"
            return
        }
        status.state = "preflight_complete"
        try status.write(to: statusURL)

        DistributedNotificationCenter.default()
            .postNotificationName(
                route.startNotificationName,
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
        guard let completed = observation.waitForCompletion(
            timeout: duration + 90
        ) else {
            status.state = "completion_evidence_blocked"
            XCTFail(observation.diagnosticSummary)
            return
        }
        status.requiredSwitches = completed.requiredSwitches
        status.completedSwitches = completed.switches
        status.homeSwitches = completed.homeSwitches
        status.logsSwitches = completed.logsSwitches
        status.settingsSwitches = completed.settingsSwitches
        status.runtimeLogLevel = completed.runtimeLogLevel
        status.stressStartedUptimeNanoseconds =
            completed.startedAtUptimeNanoseconds
        status.stressCompletedUptimeNanoseconds =
            completed.observedAtUptimeNanoseconds
        status.elapsedNanoseconds = completed.elapsedNanoseconds
        status.durationSatisfied = completed.durationSatisfied
        status.workloadSatisfied = completed.workloadSatisfied

        XCTAssertEqual(
            status.completedSwitches,
            status.requiredSwitches
        )
        XCTAssertGreaterThan(status.homeSwitches, 0)
        XCTAssertGreaterThan(status.logsSwitches, 0)
        XCTAssertGreaterThan(status.settingsSwitches, 0)
        XCTAssertEqual(
            status.runtimeLogLevel,
            logLevel.uppercased()
        )
        XCTAssertEqual(
            status.homeSwitches
                + status.logsSwitches
                + status.settingsSwitches,
            status.completedSwitches
        )
        XCTAssertTrue(status.durationSatisfied)
        XCTAssertTrue(status.workloadSatisfied)
        status.state = "completed"
        try status.write(to: statusURL)
        XCTAssertTrue(
            app.wait(for: .notRunning, timeout: 30),
            observation.diagnosticSummary
        )
    }

    private func waitForRealTabFixtureHomeProjection(
        _ workflow: SpaceFixtureResolvedWorkflow,
        in app: XCUIApplication
    ) -> Int? {
        let rows = workflow.apps.map { expected in
            (
                identifier:
                    expected.identity.homeAppAccessibilityIdentifier,
                expectedValue: "\(expected.windowCount)w",
                element: element(
                    in: app,
                    identifier:
                        expected.identity
                            .homeAppAccessibilityIdentifier
                )
            )
        }
        let expectations = rows.map { row in
            XCTNSPredicateExpectation(
                predicate: NSPredicate(
                    format: "exists == true AND value == %@",
                    row.expectedValue
                ),
                object: row.element
            )
        }
        let result = XCTWaiter.wait(
            for: expectations,
            timeout:
                FlowTabUITestSpaceFixtureHomeAppInventoryPolicy
                    .watchdog(appCount: workflow.apps.count)
        )
        guard result == .completed else {
            let observed = rows.map { row in
                row.identifier
                    + "{exists=\(row.element.exists ? 1 : 0),value="
                    + String(
                        reflecting: row.element.exists
                            ? elementStringValue(row.element)
                            : nil
                    )
                    + "}"
            }.joined(separator: ",")
            XCTFail(
                "Real Tab Fixture Home projection watchdog expired. "
                    + "observed=[\(observed)]"
            )
            return nil
        }

        let appCount = element(
            in: app,
            identifier: Identifier.homeAppCount
        )
        guard appCount.exists,
              let count =
                FlowTabUITestSpaceFixtureHomeAppInventorySnapshot
                    .appCount(from: appCount.label),
              count >= rows.count
        else {
            XCTFail(
                "Real Tab Home application count is unavailable. "
                    + "label=\(String(reflecting: appCount.label))"
            )
            return nil
        }
        return count
    }
}
