//
//  FlowTabUITests.swift
//  FlowTabUITests
//
//  Created by lk on 3/24/26.
//

import XCTest

final class FlowTabUITests: XCTestCase {
    private enum Identifier {
        static let homeTabButton = "flowtab.sidebar.tab.home"
        static let logsTabButton = "flowtab.sidebar.tab.logs"
        static let settingsTabButton = "flowtab.sidebar.tab.settings"
        static let homeTabContent = "flowtab.tab.home.content"
        static let logsTabContent = "flowtab.tab.logs.content"
        static let settingsTabContent = "flowtab.tab.settings.content"
        static let permissionBanner = "flowtab.home.permission.banner"
        static let permissionOpenSettings = "flowtab.home.permission.open-settings"
        static let permissionDismiss = "flowtab.home.permission.dismiss"
        static let permissionReminderSwitch = "flowtab.settings.permission.reminder"
        static let logsClearButton = "flowtab.logs.clear"
        static let logsLines = "flowtab.logs.lines"
        static let logsEmptyHint = "flowtab.logs.empty-hint"
        static let logsSeededDebugLine = "flowtab.logs.line.seeded.debug"
        static let logsSeededInfoLine = "flowtab.logs.line.seeded.info"
        static let logsSeededWarnLine = "flowtab.logs.line.seeded.warn"
        static let logsSeededErrorLine = "flowtab.logs.line.seeded.error"
        static let switcherPanel = "flowtab.switcher.panel"
        static let switcherSearchInput = "flowtab.switcher.search.input"
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        terminateAppIfRunning()
    }

    override func tearDownWithError() throws {
        terminateAppIfRunning()
    }

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

    func testHomePageSelectingMockAppUpdatesWindowList() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "-showPermissionReminder",
                "NO"
            ]
        )
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(
            tapFirstHittable(in: app.buttons.matching(identifier: Identifier.homeTabButton), timeout: 10)
        )

        let browserRows = app.buttons.matching(identifier: "flowtab.home.app.com-flowtab-mock-browser")
        XCTAssertTrue(tapFirstHittable(in: browserRows, timeout: 10))

        let browserWindowRows = app.descendants(matching: .any)
            .matching(identifier: "flowtab.home.window.mock-browser-docs")
        XCTAssertTrue(browserWindowRows.firstMatch.waitForExistence(timeout: 12))
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

    func testSearchPanelEntryAndResultActivation() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-open-switcher-search",
                "-showPermissionReminder",
                "NO"
            ]
        )
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        let switcherPanel = app.descendants(matching: .any)
            .matching(identifier: Identifier.switcherPanel)
            .firstMatch
        XCTAssertTrue(switcherPanel.waitForExistence(timeout: 5))

        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        app.typeText("browser")

        let browserResult = app.descendants(matching: .any)
            .matching(identifier: "flowtab.switcher.search.app.com-flowtab-mock-browser")
            .firstMatch
        XCTAssertTrue(browserResult.waitForExistence(timeout: 5))

        app.typeText("\r")
        if !waitForNonExistence(switcherPanel, timeout: 1.2) {
            // XCUI keyboard input may leave the hidden NSTextView in a marked-text
            // composition state, so the first Return only commits composition.
            app.typeText("\r")
        }
        XCTAssertTrue(waitForNonExistence(switcherPanel, timeout: 3))
    }

    func testSearchPanelChineseQueryShowsChineseMockResult() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-open-switcher-search",
                "-showPermissionReminder",
                "NO"
            ]
        )
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        let switcherPanel = app.descendants(matching: .any)
            .matching(identifier: Identifier.switcherPanel)
            .firstMatch
        XCTAssertTrue(switcherPanel.waitForExistence(timeout: 5))

        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        app.typeText("测")

        let chineseResult = app.descendants(matching: .any)
            .matching(identifier: "flowtab.switcher.search.app.com-xxx-test")
            .firstMatch
        XCTAssertTrue(chineseResult.waitForExistence(timeout: 5))
    }

    func testSearchPanelPinyinInitialsShowChineseMockResult() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-open-switcher-search",
                "-showPermissionReminder",
                "NO"
            ]
        )
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        let switcherPanel = app.descendants(matching: .any)
            .matching(identifier: Identifier.switcherPanel)
            .firstMatch
        XCTAssertTrue(switcherPanel.waitForExistence(timeout: 5))

        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        app.typeText("cs")

        let chineseResult = app.descendants(matching: .any)
            .matching(identifier: "flowtab.switcher.search.app.com-xxx-test")
            .firstMatch
        XCTAssertTrue(chineseResult.waitForExistence(timeout: 5))
    }

    func testSearchPanelSharedCsQueryShowsCSGOAndChineseMockResults() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-open-switcher-search",
                "-showPermissionReminder",
                "NO"
            ]
        )
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        let switcherPanel = app.descendants(matching: .any)
            .matching(identifier: Identifier.switcherPanel)
            .firstMatch
        XCTAssertTrue(switcherPanel.waitForExistence(timeout: 5))

        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        app.typeText("cs")

        let csgoResult = app.descendants(matching: .any)
            .matching(identifier: "flowtab.switcher.search.app.com-xxx-csgo")
            .firstMatch
        XCTAssertTrue(csgoResult.waitForExistence(timeout: 5))

        let chineseResult = app.descendants(matching: .any)
            .matching(identifier: "flowtab.switcher.search.app.com-xxx-test")
            .firstMatch
        XCTAssertTrue(chineseResult.waitForExistence(timeout: 5))
    }

    func testSearchPanelSegmentedChineseQueryShowsCompoundMockResult() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-open-switcher-search",
                "-showPermissionReminder",
                "NO"
            ]
        )
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        let switcherPanel = app.descendants(matching: .any)
            .matching(identifier: Identifier.switcherPanel)
            .firstMatch
        XCTAssertTrue(switcherPanel.waitForExistence(timeout: 5))

        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        app.typeText("文件助手")

        let segmentedResult = app.descendants(matching: .any)
            .matching(identifier: "flowtab.switcher.search.app.com-flowtab-mock-file-transfer-assistant")
            .firstMatch
        XCTAssertTrue(segmentedResult.waitForExistence(timeout: 5))
    }

    func testTabSwitchStressCPUAndMemory() throws {
        let options = XCTMeasureOptions()
        options.iterationCount = 3

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            let app = makeApp(
                additionalArguments: [
                    "--flowtab-ui-reset-defaults",
                    "--flowtab-ui-mock-runtime",
                    "--flowtab-tab-stress",
                    "--flowtab-tab-stress-duration",
                    "2",
                    "--flowtab-tab-stress-interval-ms",
                    "16",
                    "-showPermissionReminder",
                    "NO"
                ]
            )
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        }
    }

    private func makeApp(additionalArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += additionalArguments
        return app
    }

    private func settingsReminderToggle(in app: XCUIApplication) -> XCUIElement {
        let switchElement = app.switches[Identifier.permissionReminderSwitch]
        if switchElement.exists || switchElement.waitForExistence(timeout: 1) {
            return switchElement
        }
        let checkboxElement = app.checkBoxes[Identifier.permissionReminderSwitch]
        return checkboxElement
    }

    private func assertLogVisibility(
        at logLevel: String,
        visibleIdentifiers: [String],
        hiddenIdentifiers: [String]
    ) {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-seed-logs",
                "4",
                "--flowtab-ui-runtime-log-level",
                logLevel,
                "-showPermissionReminder",
                "NO"
            ]
        )
        app.launch()
        defer {
            if app.state == .runningForeground || app.state == .runningBackground {
                app.terminate()
            }
        }

        XCTAssertTrue(
            tapFirstHittable(in: app.buttons.matching(identifier: Identifier.logsTabButton), timeout: 5),
            "Failed to open logs tab at level \(logLevel)"
        )

        let logsTabContent = app.descendants(matching: .any)
            .matching(identifier: Identifier.logsTabContent)
            .firstMatch
        XCTAssertTrue(logsTabContent.waitForExistence(timeout: 5), "Missing logs tab content at level \(logLevel)")

        let logsLines = app.descendants(matching: .any)
            .matching(identifier: Identifier.logsLines)
            .firstMatch
        XCTAssertTrue(logsLines.waitForExistence(timeout: 8), "Missing logs container at level \(logLevel)")

        for identifier in visibleIdentifiers {
            let line = app.descendants(matching: .any)
                .matching(identifier: identifier)
                .firstMatch
            XCTAssertTrue(
                line.waitForExistence(timeout: 8),
                "Expected visible log row \(identifier) at level \(logLevel)"
            )
        }

        RunLoop.current.run(until: Date().addingTimeInterval(1.2))

        for identifier in hiddenIdentifiers {
            let line = app.descendants(matching: .any)
                .matching(identifier: identifier)
                .firstMatch
            XCTAssertFalse(
                line.exists,
                "Expected hidden log row \(identifier) at level \(logLevel)"
            )
        }
    }

    private func waitForNonExistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func tapFirstHittable(in query: XCUIElementQuery, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let count = query.count
            for index in 0..<count {
                let element = query.element(boundBy: index)
                if element.exists && element.isHittable {
                    element.tap()
                    return true
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return false
    }

    private func hasHittableElement(in query: XCUIElementQuery, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let count = query.count
            for index in 0..<count {
                let element = query.element(boundBy: index)
                if element.exists && element.isHittable {
                    return true
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return false
    }

    private func terminateAppIfRunning() {
        let app = XCUIApplication()
        if app.state == .runningForeground || app.state == .runningBackground {
            app.terminate()
        }
    }
}
