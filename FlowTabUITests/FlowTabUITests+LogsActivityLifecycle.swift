import XCTest

extension FlowTabUITests {
    func testLogsPageReadsCurrentSnapshotAfterReturningFromHome() {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-seed-logs",
                "2",
                "--flowtab-ui-listen-switcher-trigger",
                "--flowtab-ui-runtime-log-level",
                "info",
                "-showPermissionReminder",
                "NO"
            ]
        )
        launchFlowTabUITestApplication(app)
        let didResolveInitialLogs =
            assertLogsPopulatedProjectionAfterNavigation(
                in: app,
                targetDescription: "activity-lifecycle-initial-logs",
                selectedLevel: "INFO",
                visibleIdentifiers: [
                    Identifier.logsSeededInfoLine
                ]
            ) {
                tapFirstHittable(
                    in: app.buttons.matching(
                        identifier: Identifier.logsTabButton
                    ),
                    timeout:
                        FlowTabUITestLogsProjectionPolicy
                            .tabNavigationWatchdog
                )
            }
        guard didResolveInitialLogs else { return }

        assertLogsClearTransition(
            in: app,
            targetDescription: "activity-lifecycle-precondition-clear",
            selectedLevel: "INFO",
            initialVisibleIdentifiers: [
                Identifier.logsSeededInfoLine
            ]
        )
        guard assertSidebarTabProjectionAfterNavigation(
            in: app,
            target: .home
        ) else { return }

        let marker = "runtime log observation probe"
        let logSnapshot = makeRuntimeLogFileSnapshot()
        defer { logSnapshot.cancel() }
        postFlowTabUITestSwitcherCommand(
            .runtimeLogProbe,
            traceLabel: "logs.hidden-current-snapshot"
        )
        waitForRuntimeLogFiles(
            containing: [marker],
            since: logSnapshot
        )

        assertLogsRuntimeSnapshotAfterNavigation(
            in: app,
            targetDescription: "activity-lifecycle-current-snapshot",
            selectedLevel: "INFO",
            marker: marker
        ) {
            tapFirstHittable(
                in: app.buttons.matching(
                    identifier: Identifier.logsTabButton
                ),
                timeout:
                    FlowTabUITestLogsProjectionPolicy
                        .tabNavigationWatchdog
            )
        }
    }
}
