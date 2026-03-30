//
//  FlowTabAppUITests.swift
//  FlowTabAppUITests
//
//  Created by lk on 3/24/26.
//

import XCTest

final class FlowTabAppUITests: XCTestCase {
    private enum Identifier {
        static let homeTabButton = "flowtab.sidebar.tab.home"
        static let logsTabButton = "flowtab.sidebar.tab.logs"
        static let settingsTabButton = "flowtab.sidebar.tab.settings"
        static let homeTabContent = "flowtab.tab.home.content"
        static let logsTabContent = "flowtab.tab.logs.content"
        static let settingsTabContent = "flowtab.tab.settings.content"
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
    }

    func testExample() throws {
        let app = XCUIApplication()
        app.launch()
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }

    func testTabSwitchStressCPUAndMemory() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-showPermissionReminder",
            "NO"
        ]
        app.launch()

        let homeButton = sidebarButton(
            app: app,
            identifier: Identifier.homeTabButton,
            fallbackLabelContains: "首页"
        )
        let logsButton = sidebarButton(
            app: app,
            identifier: Identifier.logsTabButton,
            fallbackLabelContains: "日志"
        )
        let settingsButton = sidebarButton(
            app: app,
            identifier: Identifier.settingsTabButton,
            fallbackLabelContains: "设置"
        )
        let homeContent = app.staticTexts["应用层"]
        let logsContent = app.staticTexts["运行日志查看与清理"]
        let settingsContent = app.staticTexts["基础显示设置、快捷键与权限"]

        XCTAssertTrue(homeContent.waitForExistence(timeout: 5))

        for _ in 0..<20 {
            switchToTab(button: logsButton, content: logsContent)
            switchToTab(button: settingsButton, content: settingsContent)
            switchToTab(button: homeButton, content: homeContent)
        }

        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            for _ in 0..<60 {
                switchToTab(button: logsButton, content: logsContent)
                switchToTab(button: settingsButton, content: settingsContent)
                switchToTab(button: homeButton, content: homeContent)
            }
        }
    }

    private func switchToTab(button: XCUIElement, content: XCUIElement) {
        button.tap()
        XCTAssertTrue(content.waitForExistence(timeout: 1.5))
    }

    private func sidebarButton(
        app: XCUIApplication,
        identifier: String,
        fallbackLabelContains labelPart: String
    ) -> XCUIElement {
        let byIdentifier = app.buttons[identifier]
        if byIdentifier.waitForExistence(timeout: 5) {
            return byIdentifier
        }

        let byLabel = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", labelPart)).firstMatch
        XCTAssertTrue(
            byLabel.waitForExistence(timeout: 5),
            "Unable to locate sidebar tab button for \(labelPart)"
        )
        return byLabel
    }
}
