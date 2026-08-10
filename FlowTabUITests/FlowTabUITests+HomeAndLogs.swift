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
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 8))

        XCTAssertTrue(tapFirstHittable(in: app.buttons.matching(identifier: Identifier.homeTabButton), timeout: 5))
        XCTAssertTrue(element(in: app, identifier: Identifier.homeTabContent).waitForExistence(timeout: 5))

        XCTAssertTrue(tapFirstHittable(in: app.buttons.matching(identifier: Identifier.logsTabButton), timeout: 5))
        XCTAssertTrue(element(in: app, identifier: Identifier.logsTabContent).waitForExistence(timeout: 5))

        XCTAssertTrue(tapFirstHittable(in: app.buttons.matching(identifier: Identifier.settingsTabButton), timeout: 5))
        XCTAssertTrue(element(in: app, identifier: Identifier.settingsTabContent).waitForExistence(timeout: 5))
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
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 8))
        openLogsTab(in: app)

        assertStatusItemMainWindowCloses(in: app) {
            app.typeKey("w", modifierFlags: .command)
        }

        let flowTabBundleIdentifier = FlowTabUITestAppIdentity.configured().bundleIdentifier
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        assertTriggerMakesApplicationFrontmost(
            "com.apple.finder",
            timeout: 5,
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
                    timeout: 5,
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
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 8))

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
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 8))
        assertHomePermissionBannerHiddenProjection(
            in: app,
            targetDescription: "granted-permissions"
        ) {
            XCTAssertTrue(
                tapFirstHittable(
                    in: app.buttons.matching(
                        identifier: Identifier.homeTabButton
                    ),
                    timeout: 5
                )
            )
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
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 8))
        XCTAssertTrue(tapFirstHittable(in: app.buttons.matching(identifier: Identifier.homeTabButton), timeout: 5))
        XCTAssertTrue(element(in: app, identifier: Identifier.homeTabContent).waitForExistence(timeout: 5))
        let firstLiveAppRow = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "flowtab.home.app.")
        ).firstMatch
        XCTAssertTrue(
            firstLiveAppRow.waitForExistence(timeout: 2),
            "Home should publish the running-application directory without waiting for AX window repair."
        )
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
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 8))
        XCTAssertTrue(tapFirstHittable(in: app.buttons.matching(identifier: Identifier.homeTabButton), timeout: 5))
        XCTAssertTrue(element(in: app, identifier: Identifier.homeTabContent).waitForExistence(timeout: 5))

        XCTAssertTrue(element(in: app, identifier: Identifier.homeHeader).waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app, identifier: Identifier.homeAppCount).waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, identifier: Identifier.homeWindowCount).waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, identifier: Identifier.homeStatsTotalApps).waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, identifier: Identifier.homeStatsVisibleApps).waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, identifier: Identifier.homeStatsHiddenApps).waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, identifier: Identifier.homeStatsTotalWindows).waitForExistence(timeout: 8))
        XCTAssertTrue(element(in: app, identifier: Identifier.sidebarPermissionAccessibility).waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app, identifier: Identifier.sidebarPermissionScreenCapture).waitForExistence(timeout: 5))
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

            XCTAssertTrue(tapFirstHittable(in: app.buttons.matching(identifier: Identifier.homeTabButton), timeout: 10))
            XCTAssertNotEqual(
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                targetApp.identity.bundleIdentifier,
                "Home recency scenario must start outside the target fixture app."
            )

            let homeAppRow = app.buttons
                .matching(identifier: targetApp.identity.homeAppAccessibilityIdentifier)
                .firstMatch
            XCTAssertTrue(
                homeAppRow.waitForExistence(timeout: 20),
                "FlowTab did not surface \(targetApp.appName) on the home page."
            )
            tapElement(homeAppRow)

            let targetWindowRow = try XCTUnwrap(
                waitForHomeWindowRow(in: app, title: targetWindowTitle, timeout: 12),
                "FlowTab did not expose a Home window row for \(targetApp.appName) / \(targetWindowTitle)."
            )
            let targetWindowNumber = try XCTUnwrap(
                cgWindowNumber(fromHomeWindowRowIdentifier: targetWindowRow.identifier),
                "Home window row did not expose a CG window identifier: \(targetWindowRow.identifier)"
            )
            XCTAssertTrue(
                triggerAndWaitForFrontmostWorkflowWindow(
                    windowNumber: targetWindowNumber,
                    title: targetWindowTitle,
                    app: targetApp,
                    timeout: 10,
                    trigger: {
                        targetWindowRow.coordinate(
                            withNormalizedOffset:
                                CGVector(dx: 0.5, dy: 0.5)
                        ).tap()
                    }
                ),
                "Clicking the Home window row did not activate the real \(targetWindowTitle) fixture window."
            )

            app.activate()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
            XCTAssertTrue(tapFirstHittable(in: app.buttons.matching(identifier: Identifier.homeTabButton), timeout: 10))

            XCTAssertTrue(
                performAndWaitForHomeWindowTitlePrefix(
                    [targetWindowTitle, fallbackWindowTitle],
                    in: app,
                    timeout: 12,
                    trigger: {
                        tapElement(homeAppRow)
                    }
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
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 8))
        openSettingsTab(in: app)

        let manageButton = element(in: app, identifier: Identifier.settingsAppVisibilityManage)
        XCTAssertTrue(manageButton.waitForExistence(timeout: 6))
        tapElement(manageButton)
        XCTAssertTrue(element(in: app, identifier: Identifier.settingsAppVisibilityManager).waitForExistence(timeout: 6))

        let managerSearch = app.textFields.firstMatch
        XCTAssertTrue(managerSearch.waitForExistence(timeout: 6))
        tapElement(managerSearch)
        app.typeText("Mail")

        let mockMailRow = element(in: app, identifier: Identifier.settingsAppVisibilityMockMail)
        XCTAssertTrue(mockMailRow.waitForExistence(timeout: 6))
        tapElement(mockMailRow)

        let showToggle = homeAppVisibilityShowToggle(in: app)
        setToggle(showToggle, to: false)
        XCTAssertFalse(toggleIsOn(showToggle))

        XCTAssertTrue(tapFirstHittable(in: app.buttons.matching(identifier: Identifier.homeTabButton), timeout: 5))
        XCTAssertTrue(element(in: app, identifier: Identifier.homeTabContent).waitForExistence(timeout: 5))

        let browserRow = element(in: app, identifier: Identifier.homeAppMockBrowser)
        let mailRow = element(in: app, identifier: Identifier.homeAppMockMail)
        XCTAssertTrue(browserRow.waitForExistence(timeout: 8))
        XCTAssertTrue(mailRow.waitForExistence(timeout: 8))
        XCTAssertLessThan(
            browserRow.frame.minY,
            mailRow.frame.minY,
            "Home should keep hidden apps visible but place them after visible apps."
        )
        let mailRowDescription = "\(mailRow.label) \(elementStringValue(mailRow))"
        XCTAssertTrue(
            mailRowDescription.contains("不展示")
                || mailRowDescription.contains("Not shown")
                || mailRowDescription.contains("hidden"),
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
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 8))
        XCTAssertTrue(tapFirstHittable(in: app.buttons.matching(identifier: Identifier.homeTabButton), timeout: 5))
        XCTAssertTrue(element(in: app, identifier: Identifier.homeTabContent).waitForExistence(timeout: 5))

        let hostWeChatRow = element(in: app, identifier: Identifier.homeAppWeChat)
        let nestedAppExRow = element(in: app, identifier: Identifier.homeAppNestedWeChatAppEx)
        let nestedMiniProgramRow = element(in: app, identifier: Identifier.homeAppNestedMiniProgram)
        let topLevelZeroWindowRow = element(in: app, identifier: Identifier.homeAppTopLevelZeroWindow)

        XCTAssertTrue(hostWeChatRow.waitForExistence(timeout: 8))
        XCTAssertTrue(topLevelZeroWindowRow.waitForExistence(timeout: 8))
        tapElement(hostWeChatRow)
        assertHomeWindowTitle("微信", in: app, timeout: 6)
        assertHomeWindowTitle("微信（窗口）", in: app, timeout: 6)
        assertHomeWindowTitle("Mock Mini Program Window", in: app, timeout: 6)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Home app layer nested zero-window topology"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        XCTAssertFalse(
            nestedAppExRow.waitForExistence(timeout: 2),
            "Home should hide zero-window nested app rows when the outer host app is already visible."
        )
        XCTAssertFalse(
            nestedMiniProgramRow.exists,
            "Home should hide deeper zero-window nested app rows while keeping ordinary top-level 0w apps visible."
        )
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

        let openSettingsButtons = firstLaunchApp.buttons.matching(identifier: Identifier.permissionOpenSettings)
        XCTAssertTrue(openSettingsButtons.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(tapFirstHittable(in: openSettingsButtons, timeout: 5))

        let reminderToggle = settingsReminderToggle(in: firstLaunchApp)
        XCTAssertTrue(reminderToggle.waitForExistence(timeout: 5))
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
            XCTAssertTrue(
                tapFirstHittable(
                    in: relaunchApp.buttons.matching(
                        identifier: Identifier.homeTabButton
                    ),
                    timeout: 5
                )
            )
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
            XCTAssertTrue(
                tapFirstHittable(
                    in: relaunchApp.buttons.matching(
                        identifier: Identifier.homeTabButton
                    ),
                    timeout: 5
                )
            )
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

        XCTAssertTrue(
            tapFirstHittable(in: app.buttons.matching(identifier: Identifier.logsTabButton), timeout: 5)
        )

        let logsTabContent = app.descendants(matching: .any)
            .matching(identifier: Identifier.logsTabContent)
            .firstMatch
        XCTAssertTrue(logsTabContent.waitForExistence(timeout: 5))

        XCTAssertTrue(element(in: app, identifier: Identifier.logsPrivacyNotice).waitForExistence(timeout: 5))
        let diagnosticSessionToggle = element(
            in: app, identifier: Identifier.logsDiagnosticSession
        )

        let logsLines = app.descendants(matching: .any)
            .matching(identifier: Identifier.logsLines)
            .firstMatch
        XCTAssertTrue(logsLines.waitForExistence(timeout: 8))
        let expectedSeededLogs: [(identifier: String, marker: String)] = [
            (Identifier.logsSeededDebugLine, "seeded-debug-log-1"),
            (Identifier.logsSeededInfoLine, "seeded-info-log-2"),
            (Identifier.logsSeededWarnLine, "seeded-warn-log-3"),
            (Identifier.logsSeededErrorLine, "seeded-error-log-4")
        ]
        var persistedFingerprints: [String] = []
        for expectedSeededLog in expectedSeededLogs {
            let line = app.descendants(matching: .any)
                .matching(identifier: expectedSeededLog.identifier)
                .firstMatch
            XCTAssertTrue(
                line.waitForExistence(timeout: 8),
                "Missing seeded log row: \(expectedSeededLog.identifier)"
            )
            let lineValue = (line.value as? String) ?? line.label
            XCTAssertFalse(lineValue.contains(expectedSeededLog.marker))
            XCTAssertTrue(lineValue.contains("message.type=structured"))
            XCTAssertTrue(lineValue.contains("message.fingerprint="))
            let fingerprintSuffix = lineValue.components(separatedBy: "message.fingerprint=").dropFirst().first
            let fingerprint = fingerprintSuffix?.split(separator: " ").first.map(String.init)
            persistedFingerprints.append(try XCTUnwrap(fingerprint))
        }
        let diskContentsBeforeClear = runtimeLogContents()
        XCTAssertTrue(persistedFingerprints.allSatisfy { diskContentsBeforeClear.contains($0) })
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: Identifier.logsEmptyHint).firstMatch.exists)

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

        app.terminate()
        let relaunchedApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-runtime-log-level",
                "debug",
                "-showPermissionReminder",
                "NO"
            ]
        )
        launchFlowTabUITestApplication(relaunchedApp)
        openLogsTab(in: relaunchedApp)

        for expectedSeededLog in expectedSeededLogs {
            XCTAssertTrue(
                waitForNonExistence(
                    relaunchedApp.descendants(matching: .any)
                        .matching(identifier: expectedSeededLog.identifier)
                        .firstMatch,
                    timeout: 3
                )
            )
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
        let logsTabButton = app.buttons
            .matching(identifier: Identifier.logsTabButton)
            .firstMatch
        XCTAssertTrue(logsTabButton.waitForExistence(timeout: 6))
        tapElement(logsTabButton)
        XCTAssertTrue(
            element(in: app, identifier: Identifier.logsTabContent)
                .waitForExistence(timeout: 6)
        )

        let seededInfoLine = app.descendants(matching: .any)
            .matching(identifier: Identifier.logsSeededInfoLine)
            .firstMatch
        XCTAssertTrue(seededInfoLine.waitForExistence(timeout: 5))
        let clearButton = app.buttons
            .matching(identifier: Identifier.logsClearButton)
            .firstMatch
        XCTAssertTrue(clearButton.waitForExistence(timeout: 5))
        app.activate()
        tapElement(clearButton)
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: Identifier.logsEmptyHint)
                .firstMatch
                .waitForExistence(timeout: 5)
        )

        let command = FlowTabUITestSwitcherCommand.runtimeLogProbe
        let expectedMarker = "runtime log observation probe"
        let deliveredLogLine = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", expectedMarker))
            .firstMatch

        postFlowTabUITestSwitcherCommand(
            command,
            traceLabel: "logs.live-update"
        )

        XCTAssertTrue(deliveredLogLine.waitForExistence(timeout: 5))
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
        openLogsTab(in: app)

        let openDirectoryButton = app.buttons[Identifier.logsOpenDirectoryButton]
        XCTAssertTrue(openDirectoryButton.waitForExistence(timeout: 5))
        XCTAssertTrue(openDirectoryButton.isHittable)

        let clearLogsButton = app.buttons[Identifier.logsClearButton]
        XCTAssertTrue(clearLogsButton.waitForExistence(timeout: 5))
        XCTAssertTrue(clearLogsButton.isHittable)
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

    private func homeAppVisibilityShowToggle(in app: XCUIApplication) -> XCUIElement {
        let switchElement = app.switches.firstMatch
        if switchElement.waitForExistence(timeout: 3) {
            return switchElement
        }
        let checkBox = app.checkBoxes.firstMatch
        XCTAssertTrue(checkBox.waitForExistence(timeout: 3))
        return checkBox
    }

}
