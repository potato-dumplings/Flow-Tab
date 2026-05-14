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
        XCTAssertTrue(tapFirstHittable(in: app.buttons.matching(identifier: Identifier.homeTabButton), timeout: 5))

        XCTAssertFalse(
            hasHittableElement(in: app.buttons.matching(identifier: Identifier.permissionOpenSettings), timeout: 2)
        )
        XCTAssertFalse(element(in: app, identifier: Identifier.permissionBanner).exists)
    }

    func testHomeWindowListUsesSeededWindowRecency() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-seed-window-recency-app-id",
                "com.flowtab.mock.mail",
                "--flowtab-ui-seed-window-recency-window-id",
                "mock-mail-draft",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES",
                "-showPermissionReminder",
                "NO"
            ]
        )
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 8))
        XCTAssertTrue(tapFirstHittable(in: app.buttons.matching(identifier: Identifier.homeTabButton), timeout: 5))
        XCTAssertTrue(
            tapFirstHittable(
                in: app.buttons.matching(identifier: "flowtab.home.app.com-flowtab-mock-mail"),
                timeout: 5
            )
        )

        let deadline = Date().addingTimeInterval(8)
        var visibleWindowTitles: [String] = []
        repeat {
            visibleWindowTitles = homeWindowRows(in: app).map(\.label)
            if visibleWindowTitles.count >= 2,
               visibleWindowTitles.contains("Draft"),
               visibleWindowTitles.contains("Inbox") {
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        XCTAssertEqual(
            Array(visibleWindowTitles.prefix(2)),
            ["Draft", "Inbox"],
            "Home window candidates should use app-local recency before fallback order."
        )
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
        launchFlowTabUITestApplication(relaunchApp)
        XCTAssertTrue(
            tapFirstHittable(in: relaunchApp.buttons.matching(identifier: Identifier.homeTabButton), timeout: 5)
        )
        XCTAssertFalse(
            hasHittableElement(
                in: relaunchApp.buttons.matching(identifier: Identifier.permissionOpenSettings),
                timeout: 2
            )
        )
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
        XCTAssertTrue(tapFirstHittable(in: dismissButtons, timeout: 5))
        XCTAssertFalse(
            hasHittableElement(
                in: firstLaunchApp.buttons.matching(identifier: Identifier.permissionOpenSettings),
                timeout: 2
            )
        )

        firstLaunchApp.terminate()

        let relaunchApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-ax-trusted",
                "NO",
                "--flowtab-ui-screen-trusted",
                "NO"
            ]
        )
        launchFlowTabUITestApplication(relaunchApp)
        XCTAssertTrue(
            tapFirstHittable(in: relaunchApp.buttons.matching(identifier: Identifier.homeTabButton), timeout: 5)
        )
        XCTAssertFalse(
            hasHittableElement(
                in: relaunchApp.buttons.matching(identifier: Identifier.permissionOpenSettings),
                timeout: 2
            )
        )
    }

    func testLogsPageShowsSeededLogsAndClearRemovesOutput() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-seed-logs",
                "4",
                "--flowtab-ui-runtime-log-level",
                "debug",
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
        for expectedSeededLog in expectedSeededLogs {
            let line = app.descendants(matching: .any)
                .matching(identifier: expectedSeededLog.identifier)
                .firstMatch
            XCTAssertTrue(
                line.waitForExistence(timeout: 8),
                "Missing seeded log row: \(expectedSeededLog.identifier)"
            )
            let lineValue = (line.value as? String) ?? line.label
            XCTAssertTrue(
                lineValue.contains(expectedSeededLog.marker),
                "Unexpected seeded log value for \(expectedSeededLog.identifier): \(lineValue)"
            )
        }
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: Identifier.logsEmptyHint).firstMatch.exists)

        XCTAssertTrue(
            tapFirstHittable(in: app.buttons.matching(identifier: Identifier.logsClearButton), timeout: 5)
        )

        let logsEmptyHint = app.descendants(matching: .any)
            .matching(identifier: Identifier.logsEmptyHint)
            .firstMatch
        XCTAssertTrue(logsEmptyHint.waitForExistence(timeout: 5))
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

    func testLogsOpenDirectoryButtonIsVisible() throws {
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
