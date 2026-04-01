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
        static let permissionReminderSwitch = "flowtab.settings.permission.reminder"
        static let logsClearButton = "flowtab.logs.clear"
        static let logsEmptyHint = "flowtab.logs.empty-hint"
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

        let permissionBanner = firstLaunchApp.otherElements[Identifier.permissionBanner]
        XCTAssertTrue(permissionBanner.waitForExistence(timeout: 5))

        firstLaunchApp.buttons[Identifier.permissionOpenSettings].tap()
        XCTAssertTrue(firstLaunchApp.otherElements[Identifier.settingsTabContent].waitForExistence(timeout: 5))

        let reminderToggle = settingsReminderToggle(in: firstLaunchApp)
        XCTAssertTrue(reminderToggle.waitForExistence(timeout: 5))
        reminderToggle.tap()

        firstLaunchApp.buttons[Identifier.homeTabButton].tap()
        XCTAssertTrue(firstLaunchApp.otherElements[Identifier.homeTabContent].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForNonExistence(permissionBanner, timeout: 2))

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
        XCTAssertTrue(relaunchApp.otherElements[Identifier.homeTabContent].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForNonExistence(relaunchApp.otherElements[Identifier.permissionBanner], timeout: 2))
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

        XCTAssertTrue(app.otherElements[Identifier.homeTabContent].waitForExistence(timeout: 5))

        let browserRow = app.buttons["flowtab.home.app.com-flowtab-mock-browser"]
        XCTAssertTrue(browserRow.waitForExistence(timeout: 5))
        browserRow.tap()

        let browserWindowRow = app.otherElements["flowtab.home.window.mock-browser-docs"]
        XCTAssertTrue(browserWindowRow.waitForExistence(timeout: 5))
    }

    func testLogsPageShowsSeededLogsAndClearRemovesOutput() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-seed-logs",
                "3",
                "-showPermissionReminder",
                "NO"
            ]
        )
        app.launch()

        app.buttons[Identifier.logsTabButton].tap()
        XCTAssertTrue(app.otherElements[Identifier.logsTabContent].waitForExistence(timeout: 5))

        let seededLine = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "seeded-log-3")
        ).firstMatch
        XCTAssertTrue(seededLine.waitForExistence(timeout: 5))

        app.buttons[Identifier.logsClearButton].tap()
        XCTAssertTrue(app.staticTexts[Identifier.logsEmptyHint].waitForExistence(timeout: 5))
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

        let switcherPanel = app.otherElements[Identifier.switcherPanel]
        XCTAssertTrue(switcherPanel.waitForExistence(timeout: 5))

        let searchInput = app.otherElements[Identifier.switcherSearchInput]
        XCTAssertTrue(searchInput.waitForExistence(timeout: 5))
        searchInput.tap()
        app.typeText("browser")

        let browserResult = app.otherElements["flowtab.switcher.search.app.com-flowtab-mock-browser"]
        XCTAssertTrue(browserResult.waitForExistence(timeout: 5))

        app.typeText("\r")
        XCTAssertTrue(waitForNonExistence(switcherPanel, timeout: 3))
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

    private func waitForNonExistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func terminateAppIfRunning() {
        let app = XCUIApplication()
        if app.state == .runningForeground || app.state == .runningBackground {
            app.terminate()
        }
    }
}
