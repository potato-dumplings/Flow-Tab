import AppKit
import XCTest

extension FlowTabUITests {
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                makeApp(
                    additionalArguments: [
                        "--flowtab-ui-reset-defaults",
                        "-showPermissionReminder",
                        "NO"
                    ]
                ).launch()
            }
        }
    }

    func testSidebarTabsSwitchContent() throws {
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

        for target in FlowTabUITestSidebarTabProjectionTarget.allCases {
            guard assertSidebarTabProjectionAfterNavigation(
                in: app,
                target: target
            ) else {
                return
            }
        }
    }

    func testStatusItemReopensLastSelectedTabAfterWindowClose() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES",
                "--flowtab-ui-runtime-log-level",
                "INFO",
                "--flowtab-ui-enable-verbose-logs"
            ]
        )
        launchFlowTabUITestApplication(app)
        assertHomeAndLogsApplicationIsForegroundReady(app)
        openLogsTab(in: app)

        assertStatusItemMainWindowCloses(in: app) {
            app.typeKey("w", modifierFlags: .command)
        }

        let flowTabBundleIdentifier = FlowTabUITestAppIdentity.configured().bundleIdentifier
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        assertTriggerMakesApplicationFrontmost(
            "com.apple.finder",
            timeout:
                FlowTabUITestHomeAndLogsWatchdogPolicy
                    .frontmostApplicationActivation,
            message: "Status item reopen should be exercised from another normal Space app."
        ) {
            finder.activate()
        }
        XCTAssertNotEqual(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, flowTabBundleIdentifier)

        let logSnapshot = makeRuntimeLogFileSnapshot()
        defer { logSnapshot.cancel() }
        assertStatusItemActivationPolicyTransition(
            since: logSnapshot
        ) {
            assertStatusItemMainWindowReopens(in: app) {
                assertTriggerMakesApplicationFrontmost(
                    flowTabBundleIdentifier,
                    timeout:
                        FlowTabUITestHomeAndLogsWatchdogPolicy
                            .frontmostApplicationActivation,
                    message: "FlowTab should stay foreground after restoring its hidden accessory policy."
                ) {
                    flowTabStatusItem(in: app).tap()
                }
            }
        }

        XCTAssertEqual(
            NSWorkspace.shared.frontmostApplication?
                .bundleIdentifier,
            flowTabBundleIdentifier,
            "FlowTab should remain foreground after the reopen evidence is visible."
        )
    }

    func testStatusItemSecondaryClickMenuQuitsApp() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(app)
        assertHomeAndLogsApplicationIsForegroundReady(app)

        let quitItem = flowTabStatusMenuQuitItem(
            in: app,
            openingWith: flowTabStatusItem(in: app)
        )
        let termination =
            observeFlowTabUITestApplicationTermination(
                app,
                targetDescription: "status-item-menu-quit",
                timeout:
                    FlowTabUITestApplicationTerminationPolicy
                        .statusItemMenuQuitWatchdog
            ) {
                quitItem.tap()
            }
        XCTAssertTrue(
            termination.isSatisfied,
            termination.diagnosticSummary
        )
    }

    func testHomePermissionBannerHiddenWhenPermissionsGranted() throws {
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
        assertHomePermissionBannerHiddenProjection(
            in: app,
            targetDescription: "granted-permissions"
        ) {
            assertHomeAndLogsHomeTabTriggerReady(in: app)
        }
    }

    func testHomeColdStartPublishesLiveAppDirectoryWithoutAccessibilityPermission() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "-showPermissionReminder",
                "NO",
                "--flowtab-ui-ax-trusted",
                "NO",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(app)
        assertHomeAndLogsApplicationIsForegroundReady(app)
        assertHomeAndLogsLiveApplicationDirectoryAfterNavigation(in: app)
    }

    func testHomeOverviewChromeShowsCountsStatsAndSidebarPermissionStatus() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "-showPermissionReminder",
                "NO",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(app)
        assertHomeAndLogsApplicationIsForegroundReady(app)
        assertHomeAndLogsOverviewChromeAfterNavigation(in: app)
    }

    func testHomeWindowListUsesSeededWindowRecency() throws {
        let workflow = try configuredHomeWindowRecencyWorkflow()

        try runRealSpaceFixtureWorkflow(
            workflow,
            waitsForFullscreenMarkers: false
        ) { workflow, app in
            let targetApp = try XCTUnwrap(
                workflow.apps.first { $0.appID == "chrome" },
                "Home recency workflow must include the Chrome fixture app."
            )
            let targetWindowTitle = "Draft"
            let fallbackWindowTitle = "Inbox"

            let homeAppRow = try XCTUnwrap(
                waitForHomeWindowRecencyTargetAppRowAfterNavigation(
                    identifier: targetApp.identity.homeAppAccessibilityIdentifier,
                    appName: targetApp.appName,
                    in: app
                ),
                "FlowTab did not publish the exact Home App row for "
                    + "\(targetApp.appName)."
            )
            XCTAssertNotEqual(
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                targetApp.identity.bundleIdentifier,
                "Home recency scenario must start outside the target fixture app."
            )
            let targetWindowRow = try XCTUnwrap(
                waitForHomeWindowRecencyTargetWindowRowAfterSelectingApp(
                    homeAppRow, appName: targetApp.appName,
                    title: targetWindowTitle, in: app
                ),
                "FlowTab did not expose a Home window row for \(targetApp.appName) / \(targetWindowTitle)."
            )
            let targetWindowIdentifier = targetWindowRow.identifier
            let targetWindowNumber = try XCTUnwrap(
                cgWindowNumber(
                    fromHomeWindowRowIdentifier: targetWindowIdentifier
                ),
                "Home window row did not expose a CG window identifier: \(targetWindowIdentifier)"
            )
            XCTAssertTrue(
                activateHomeWindowRecencyTargetWindow(
                    row: targetWindowRow,
                    windowNumber: targetWindowNumber,
                    title: targetWindowTitle,
                    app: targetApp
                ),
                "Clicking the Home window row did not activate the real \(targetWindowTitle) fixture window."
            )

            XCTAssertTrue(
                activateFlowTabAfterHomeWindowRecencyTargetActivation(app)
            )
            XCTAssertTrue(
                navigateHomeAfterHomeWindowRecencyFlowTabActivation(
                    in: app
                )
            )

            XCTAssertTrue(
                waitForHomeWindowRecencyOrderedProjectionAfterSelectingApp(
                    homeAppRow,
                    appName: targetApp.appName,
                    expectedTitles: [
                        targetWindowTitle,
                        fallbackWindowTitle
                    ],
                    targetWindowIdentifier: targetWindowIdentifier,
                    in: app
                ),
                "Home window candidates should use real app-local recency before fallback order."
            )
        }
    }

    func testHomeAppLayerMarksHiddenAppsAndSortsThemLast() throws {
        let app = makeApp(
            additionalArguments: homeAppVisibilityRuntimeArguments(resetDefaults: true)
        )
        launchFlowTabUITestApplication(app)
        assertHomeAndLogsApplicationIsForegroundReady(app)
        openSettingsTab(in: app)

        guard assertSettingsAppVisibilityInventoryReadinessAfterNavigation(
            in: app,
            targetDescription: "Home hidden-App inventory"
        ) else {
            return
        }

        guard assertSettingsAppVisibilityQueryProjection(
            "Mail",
            targetRowIdentifier: Identifier.settingsAppVisibilityMockMail,
            in: app,
            targetDescription: "Home hidden-App Search projection"
        ) else {
            return
        }

        guard let showToggle = settingsAppVisibilityShowToggleAfterSelecting(
            rowIdentifier: Identifier.settingsAppVisibilityMockMail,
            in: app,
            targetDescription: "Home hidden-App detail"
        ) else {
            return
        }
        setToggle(showToggle, to: false)
        XCTAssertFalse(toggleIsOn(showToggle))

        guard let rowProjection =
            assertHomeAndLogsHiddenAppRowsAfterNavigation(in: app)
        else {
            return
        }
        XCTAssertEqual(
            rowProjection.identifiersByAscendingFrame,
            [Identifier.homeAppMockBrowser, Identifier.homeAppMockMail],
            "Home should keep hidden apps visible but place them after visible apps."
        )
        XCTAssertTrue(
            FlowTabUITestHomeHiddenAppRowProjectionPolicy
                .acceptsHiddenMailState(rowProjection),
            "Hidden Home app rows should expose the not-shown state for automation."
        )
    }

    func testHomeAppLayerHidesZeroWindowNestedAppsFromMockWeChatTopology() throws {
        var launchArguments = homeAppVisibilityRuntimeArguments(resetDefaults: true)
        launchArguments += [
            "--flowtab-ui-mock-runtime-variant",
            "nested-zero-window-apps"
        ]

        let app = makeApp(additionalArguments: launchArguments)
        launchFlowTabUITestApplication(app)
        assertHomeAndLogsApplicationIsForegroundReady(app)

        guard let hostWeChatRow =
            assertHomeAndLogsNestedTopologyTopLevelRowsAfterNavigation(
                in: app
            )
        else {
            return
        }

        guard assertHomeAndLogsNestedTopologyFilteredAppsAfterSelectingHost(
            hostWeChatRow,
            in: app
        ) else {
            return
        }

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Home app layer nested zero-window topology"
        screenshot.lifetime = .keepAlways
        add(screenshot)

    }

    func testPermissionReminderTogglePersistsAcrossRelaunch() throws {
        let firstLaunchApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-ax-trusted",
                "NO",
                "--flowtab-ui-screen-trusted",
                "NO"
            ]
        )
        launchFlowTabUITestApplication(firstLaunchApp)

        let reminderToggle = try XCTUnwrap(
            waitForHomePermissionReminderToggleAfterOpeningSettings(
                in: firstLaunchApp
            ),
            "Settings did not publish the exact permission reminder toggle."
        )
        reminderToggle.tap()

        firstLaunchApp.terminate()

        let relaunchApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-ax-trusted",
                "NO",
                "--flowtab-ui-screen-trusted",
                "NO"
            ]
        )
        assertHomePermissionBannerHiddenProjection(
            in: relaunchApp,
            targetDescription: "persisted-reminder-toggle"
        ) {
            launchFlowTabUITestApplication(relaunchApp)
            assertHomeAndLogsHomeTabTriggerReady(in: relaunchApp)
        }
    }

    func testPermissionDismissPersistsAcrossRelaunch() throws {
        let firstLaunchApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-ax-trusted",
                "NO",
                "--flowtab-ui-screen-trusted",
                "NO"
            ]
        )
        launchFlowTabUITestApplication(firstLaunchApp)

        let dismissButtons = firstLaunchApp.buttons.matching(identifier: Identifier.permissionDismiss)
        XCTAssertTrue(dismissButtons.firstMatch.waitForExistence(timeout: 5))
        assertHomePermissionBannerHiddenProjection(
            in: firstLaunchApp,
            targetDescription: "permission-dismiss",
            baselineRequirement: .visiblePermissionControls
        ) {
            XCTAssertTrue(tapFirstHittable(in: dismissButtons, timeout: 5))
        }

        firstLaunchApp.terminate()

        let relaunchApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-ax-trusted",
                "NO",
                "--flowtab-ui-screen-trusted",
                "NO"
            ]
        )
        assertHomePermissionBannerHiddenProjection(
            in: relaunchApp,
            targetDescription: "persisted-permission-dismiss"
        ) {
            launchFlowTabUITestApplication(relaunchApp)
            assertHomeAndLogsHomeTabTriggerReady(in: relaunchApp)
        }
    }

    func testLogsPageShowsSeededLogsAndClearRemovesOutput() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-seed-logs",
                "4",
                "--flowtab-ui-runtime-log-level",
                "debug",
                "--flowtab-ui-redacted-runtime-logs",
                "-showPermissionReminder",
                "NO"
            ]
        )
        launchFlowTabUITestApplication(app)
        let expectedSeededLogs: [(identifier: String, marker: String)] = [
            (Identifier.logsSeededDebugLine, "seeded-debug-log-1"),
            (Identifier.logsSeededInfoLine, "seeded-info-log-2"),
            (Identifier.logsSeededWarnLine, "seeded-warn-log-3"),
            (Identifier.logsSeededErrorLine, "seeded-error-log-4")
        ]
        let persistedFingerprints = try XCTUnwrap(
            assertSeededLogsProjection(
                in: app,
                targetDescription: "initial-redacted-seeded-logs",
                selectedLevel: "DEBUG",
                expectedRows: expectedSeededLogs.map {
                    FlowTabUITestSeededLogProjectionExpectation(
                        identifier: $0.identifier,
                        cleartextMarker: $0.marker
                    )
                }
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
        )
        let diagnosticSessionToggle = element(
            in: app,
            identifier: Identifier.logsDiagnosticSession
        )
        XCTAssertEqual(
            persistedFingerprints.count,
            expectedSeededLogs.count
        )
        for fingerprint in persistedFingerprints {
            XCTAssertFalse(fingerprint.isEmpty)
        }
        let diskContentsBeforeClear = runtimeLogContents()
        XCTAssertTrue(persistedFingerprints.allSatisfy { diskContentsBeforeClear.contains($0) })

        assertLogVisibilityTransition(
            in: app,
            targetDescription: "seeded-log-level-WARN",
            initialSelectedLevel: "DEBUG",
            initialVisibleIdentifiers:
                expectedSeededLogs.map(\.identifier),
            selectedLevel: "WARN",
            visibleIdentifiers: [
                Identifier.logsSeededWarnLine,
                Identifier.logsSeededErrorLine
            ],
            hiddenIdentifiers: [
                Identifier.logsSeededDebugLine,
                Identifier.logsSeededInfoLine
            ]
        ) {
            selectOption(
                in: app,
                controlIdentifier: Identifier.logsLevel,
                optionIdentifier: "WARN"
            )
        }

        assertLogsDiagnosticSessionTransition(
            in: app,
            toggle: diagnosticSessionToggle,
            targetDescription: "diagnostic-session-activation",
            from: false, to: true
        ) {
            setToggle(diagnosticSessionToggle, to: true)
        }
        assertLogsDiagnosticSessionTransition(
            in: app,
            toggle: diagnosticSessionToggle,
            targetDescription: "diagnostic-session-deactivation",
            from: true, to: false
        ) {
            setToggle(diagnosticSessionToggle, to: false)
        }

        assertLogsClearTransition(
            in: app,
            targetDescription: "seeded-logs-clear",
            selectedLevel: "WARN",
            initialVisibleIdentifiers: [
                Identifier.logsSeededWarnLine, Identifier.logsSeededErrorLine
            ]
        )

        let clearedDiskContents = runtimeLogContents()
        XCTAssertTrue(persistedFingerprints.allSatisfy { !clearedDiskContents.contains($0) })

        let sourceTermination = terminateFlowTabUITestApplication(
            app,
            targetDescription: "logs-clear-persistence-source"
        )
        XCTAssertTrue(sourceTermination.isSatisfied, sourceTermination.diagnosticSummary)
        let relaunchedApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-runtime-log-level",
                "debug",
                "-showPermissionReminder",
                "NO"
            ]
        )
        assertLogsClearPersistenceAfterRelaunch(
            in: relaunchedApp,
            targetDescription: "seeded-logs-cleared-after-relaunch",
            selectedLevel: "DEBUG"
        ) {
            launchFlowTabUITestApplication(relaunchedApp)
            openLogsTab(in: relaunchedApp)
        }
        let relaunchedDiskContents = runtimeLogContents()
        XCTAssertTrue(persistedFingerprints.allSatisfy { !relaunchedDiskContents.contains($0) })
    }

    func testLogsPageRespectsRuntimeLogLevelVisibility() throws {
        let scenarios: [(level: String, visible: [String], hidden: [String])] = [
            (
                "DEBUG",
                [
                    Identifier.logsSeededDebugLine,
                    Identifier.logsSeededInfoLine,
                    Identifier.logsSeededWarnLine,
                    Identifier.logsSeededErrorLine
                ],
                []
            ),
            (
                "INFO",
                [
                    Identifier.logsSeededInfoLine,
                    Identifier.logsSeededWarnLine,
                    Identifier.logsSeededErrorLine
                ],
                [Identifier.logsSeededDebugLine]
            ),
            (
                "WARN",
                [Identifier.logsSeededWarnLine, Identifier.logsSeededErrorLine],
                [Identifier.logsSeededDebugLine, Identifier.logsSeededInfoLine]
            ),
            (
                "ERROR",
                [Identifier.logsSeededErrorLine],
                [
                    Identifier.logsSeededDebugLine,
                    Identifier.logsSeededInfoLine,
                    Identifier.logsSeededWarnLine
                ]
            )
        ]

        for scenario in scenarios {
            assertLogVisibility(
                at: scenario.level,
                visibleIdentifiers: scenario.visible,
                hiddenIdentifiers: scenario.hidden
            )
        }
    }

    func testLogsPageUpdatesFromRuntimeLogChangeEventWhileVisible() {
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
                targetDescription: "live-update-initial-logs",
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
        guard didResolveInitialLogs else {
            return
        }
        assertLogsClearTransition(
            in: app,
            targetDescription: "live-update-precondition-clear",
            selectedLevel: "INFO",
            initialVisibleIdentifiers: [
                Identifier.logsSeededInfoLine
            ]
        )

        let command = FlowTabUITestSwitcherCommand.runtimeLogProbe
        let expectedMarker = "runtime log observation probe"
        assertLogsRuntimeDelivery(
            in: app,
            targetDescription: "runtime-log-probe",
            selectedLevel: "INFO",
            marker: expectedMarker
        ) {
            postFlowTabUITestSwitcherCommand(
                command,
                traceLabel: "logs.live-update"
            )
        }
    }

    func testLogsTabShowsActionButtons() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-seed-logs",
                "1",
                "-showPermissionReminder",
                "NO"
            ]
        )
        launchFlowTabUITestApplication(app)
        let didResolveLogsActions =
            assertLogsActionProjectionAfterNavigation(
                in: app,
                targetDescription: "logs-action-buttons"
            )
        guard didResolveLogsActions else {
            return
        }
    }

    private func configuredHomeWindowRecencyWorkflow() throws -> SpaceFixtureResolvedWorkflow {
        do {
            let installedWorkflow = try SpaceFixtureResolvedWorkflow.configured()
            return try resolveSpaceFixtureWorkflowScenario(
                sourceWorkflowURL: SpaceFixtureMultiAppWorkflowDefaults.homeWindowRecencyWorkflowSourceURL,
                using: installedWorkflow
            )
        } catch let error as SpaceFixtureMultiAppWorkflowError {
            switch error {
            case .missingWorkflowPath, .workflowScenarioMissingAppVariant, .workflowScenarioBundleIdentifierMismatch:
                throw XCTSkip(
                    multiAppWorkflowSetupMessage(
                        reason: error.localizedDescription,
                        scenarioSourceURL: SpaceFixtureMultiAppWorkflowDefaults.homeWindowRecencyWorkflowSourceURL
                    )
                )
            default:
                XCTFail(error.localizedDescription)
                throw error
            }
        } catch {
            XCTFail(error.localizedDescription)
            throw error
        }
    }

    private func cgWindowNumber(fromHomeWindowRowIdentifier identifier: String) -> CGWindowID? {
        let prefix = "flowtab.home.window.cg-"
        guard identifier.hasPrefix(prefix) else { return nil }

        let readableComponent = identifier
            .dropFirst(prefix.count)
            .split(separator: ".id-", maxSplits: 1)
            .first
        let tokens = readableComponent?.split(separator: "-") ?? []
        guard let windowNumberToken = tokens.last,
              let windowNumber = UInt32(windowNumberToken)
        else {
            return nil
        }

        return CGWindowID(windowNumber)
    }

    private func homeAppVisibilityRuntimeArguments(resetDefaults: Bool = false) -> [String] {
        var arguments: [String] = []
        if resetDefaults {
            arguments.append("--flowtab-ui-reset-defaults")
        }
        arguments += [
            "--flowtab-ui-mock-runtime",
            "-showPermissionReminder",
            "NO",
            "--flowtab-ui-ax-trusted",
            "YES",
            "--flowtab-ui-screen-trusted",
            "YES"
        ]
        return arguments
    }

}
