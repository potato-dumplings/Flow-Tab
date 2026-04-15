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
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))

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
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        XCTAssertTrue(tapFirstHittable(in: app.buttons.matching(identifier: Identifier.homeTabButton), timeout: 5))

        XCTAssertFalse(
            hasHittableElement(in: app.buttons.matching(identifier: Identifier.permissionOpenSettings), timeout: 2)
        )
        XCTAssertFalse(element(in: app, identifier: Identifier.permissionBanner).exists)
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
        firstLaunchApp.launch()

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
        relaunchApp.launch()
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
        firstLaunchApp.launch()

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
        relaunchApp.launch()
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
        app.launch()

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
        app.launch()
        openLogsTab(in: app)

        let openDirectoryButton = app.buttons[Identifier.logsOpenDirectoryButton]
        XCTAssertTrue(openDirectoryButton.waitForExistence(timeout: 5))
    }

}
