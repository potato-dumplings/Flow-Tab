import AppKit
import XCTest

extension FlowTabUITests {
    func testSettingsSearchDisabledPreventsAutoSearchLaunchEntry() throws {
        let firstLaunchApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-runtime-log-level",
                "DEBUG",
                "--flowtab-ui-enable-verbose-logs",
                "--flowtab-ui-record-hotkey-reload-diagnostics",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(firstLaunchApp)
        openSettingsTab(in: firstLaunchApp)

        let searchEnabledToggle = toggleElement(in: firstLaunchApp, identifier: Identifier.settingsSearchEnabled)
        XCTAssertTrue(searchEnabledToggle.waitForExistence(timeout: 5))
        setToggle(searchEnabledToggle, to: false)
        XCTAssertFalse(toggleIsOn(searchEnabledToggle))
        firstLaunchApp.terminate()

        let relaunchApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-open-switcher-search",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(relaunchApp)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(relaunchApp, timeout: 10))

        XCTAssertTrue(element(in: relaunchApp, identifier: Identifier.switcherAppMockMail).waitForExistence(timeout: 8))
        XCTAssertFalse(element(in: relaunchApp, identifier: Identifier.switcherSearchInput).exists)
    }

    func testSettingsSearchDefaultScopePersistsAndShowsWindowThenAppResults() throws {
        let firstLaunchApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(firstLaunchApp)
        openSettingsTab(in: firstLaunchApp)

        let searchEnabledToggle = toggleElement(in: firstLaunchApp, identifier: Identifier.settingsSearchEnabled)
        XCTAssertTrue(searchEnabledToggle.waitForExistence(timeout: 5))
        setToggle(searchEnabledToggle, to: true)

        selectOption(in: firstLaunchApp, controlIdentifier: Identifier.settingsSearchDefaultScope, optionIdentifier: "window")
        assertValue(of: element(in: firstLaunchApp, identifier: Identifier.settingsSearchDefaultScope), equals: "window")
        firstLaunchApp.terminate()

        let windowSearchApp = launchMockSwitcherSearchFromUserPath()
        windowSearchApp.typeText("Inbox")
        XCTAssertTrue(
            element(in: windowSearchApp, identifier: Identifier.switcherSearchWindowMockMailInbox)
                .waitForExistence(timeout: 8)
        )
        windowSearchApp.terminate()

        let settingsRelaunchApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(settingsRelaunchApp)
        openSettingsTab(in: settingsRelaunchApp)
        assertValue(of: element(in: settingsRelaunchApp, identifier: Identifier.settingsSearchDefaultScope), equals: "window")

        selectOption(in: settingsRelaunchApp, controlIdentifier: Identifier.settingsSearchDefaultScope, optionIdentifier: "app")
        assertValue(of: element(in: settingsRelaunchApp, identifier: Identifier.settingsSearchDefaultScope), equals: "app")
        settingsRelaunchApp.terminate()

        let appSearchApp = launchMockSwitcherSearchFromUserPath()
        appSearchApp.typeText("Mail")
        XCTAssertTrue(
            element(in: appSearchApp, identifier: Identifier.switcherSearchAppMockMail)
                .waitForExistence(timeout: 8)
        )
    }

    func testSettingsSearchDefaultScopeCanSwitchBetweenAppAndWindow() throws {
        let firstLaunchApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(firstLaunchApp)
        openSettingsTab(in: firstLaunchApp)

        let searchEnabledToggle = toggleElement(in: firstLaunchApp, identifier: Identifier.settingsSearchEnabled)
        XCTAssertTrue(searchEnabledToggle.waitForExistence(timeout: 5))
        setToggle(searchEnabledToggle, to: true)

        selectOption(in: firstLaunchApp, controlIdentifier: Identifier.settingsSearchDefaultScope, optionIdentifier: "app")
        assertValue(of: element(in: firstLaunchApp, identifier: Identifier.settingsSearchDefaultScope), equals: "app")

        selectOption(in: firstLaunchApp, controlIdentifier: Identifier.settingsSearchDefaultScope, optionIdentifier: "window")
        assertValue(of: element(in: firstLaunchApp, identifier: Identifier.settingsSearchDefaultScope), equals: "window")
    }

    func testSettingsAppVisibilityHidesMockAppFromSwitcherAndSearch() throws {
        let settingsApp = makeApp(
            additionalArguments: appVisibilityRuntimeArguments(resetDefaults: true)
        )
        launchFlowTabUITestApplication(settingsApp)
        openSettingsTab(in: settingsApp)

        let manageButton = element(in: settingsApp, identifier: Identifier.settingsAppVisibilityManage)
        XCTAssertTrue(manageButton.waitForExistence(timeout: 6))
        tapElement(manageButton)
        XCTAssertTrue(element(in: settingsApp, identifier: Identifier.settingsAppVisibilityManager).waitForExistence(timeout: 6))

        let managerSearch = settingsApp.textFields.firstMatch
        XCTAssertTrue(managerSearch.waitForExistence(timeout: 6))
        tapElement(managerSearch)
        settingsApp.typeText("Mail")

        let mockMailRow = element(in: settingsApp, identifier: Identifier.settingsAppVisibilityMockMail)
        XCTAssertTrue(mockMailRow.waitForExistence(timeout: 6))
        tapElement(mockMailRow)

        let showToggle = appVisibilityShowToggle(in: settingsApp)
        setToggle(showToggle, to: false)
        XCTAssertFalse(toggleIsOn(showToggle))
        settingsApp.terminate()

        let switcherApp = makeApp(
            additionalArguments: appVisibilityRuntimeArguments(opensSwitcher: true)
        )
        launchFlowTabUITestApplication(switcherApp)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(switcherApp, timeout: 10))
        XCTAssertTrue(element(in: switcherApp, identifier: Identifier.switcherAppMockBrowser).waitForExistence(timeout: 8))
        XCTAssertTrue(
            waitForNonExistence(
                element(in: switcherApp, identifier: Identifier.switcherAppMockMail),
                timeout: 2
            )
        )
        switcherApp.terminate()

        let searchApp = makeApp(
            additionalArguments: appVisibilityRuntimeArguments(opensSearch: true)
        )
        launchFlowTabUITestApplication(searchApp)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(searchApp, timeout: 10))
        XCTAssertTrue(element(in: searchApp, identifier: Identifier.switcherSearchInput).waitForExistence(timeout: 6))
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        searchApp.typeText("Mail")
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        XCTAssertFalse(element(in: searchApp, identifier: Identifier.switcherSearchAppMockMail).exists)
    }

    func testSettingsAppVisibilitySearchUsesSharedPinyinMatching() throws {
        let app = makeApp(
            additionalArguments: appVisibilityRuntimeArguments(resetDefaults: true)
        )
        launchFlowTabUITestApplication(app)
        openSettingsTab(in: app)

        let manageButton = element(in: app, identifier: Identifier.settingsAppVisibilityManage)
        XCTAssertTrue(manageButton.waitForExistence(timeout: 6))
        tapElement(manageButton)
        XCTAssertTrue(element(in: app, identifier: Identifier.settingsAppVisibilityManager).waitForExistence(timeout: 6))

        let managerSearch = app.textFields.firstMatch
        XCTAssertTrue(managerSearch.waitForExistence(timeout: 6))
        tapElement(managerSearch)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("ceshi", forType: .string)
        app.typeKey("v", modifierFlags: .command)

        XCTAssertTrue(
            element(in: app, identifier: Identifier.settingsAppVisibilityChineseTest)
                .waitForExistence(timeout: 6)
        )
    }

    func testSettingsAppVisibilityHiddenFilterShowsStoredHiddenAppMissingFromInventory() throws {
        let firstLaunchApp = makeApp(
            additionalArguments: appVisibilityRuntimeArguments(resetDefaults: true)
        )
        launchFlowTabUITestApplication(firstLaunchApp)
        openSettingsTab(in: firstLaunchApp)

        let manageButton = element(in: firstLaunchApp, identifier: Identifier.settingsAppVisibilityManage)
        XCTAssertTrue(manageButton.waitForExistence(timeout: 6))
        tapElement(manageButton)
        XCTAssertTrue(element(in: firstLaunchApp, identifier: Identifier.settingsAppVisibilityManager).waitForExistence(timeout: 6))

        let managerSearch = firstLaunchApp.textFields.firstMatch
        XCTAssertTrue(managerSearch.waitForExistence(timeout: 6))
        tapElement(managerSearch)
        firstLaunchApp.typeText("Mail")

        let mockMailRow = element(in: firstLaunchApp, identifier: Identifier.settingsAppVisibilityMockMail)
        XCTAssertTrue(mockMailRow.waitForExistence(timeout: 6))
        tapElement(mockMailRow)

        let showToggle = appVisibilityShowToggle(in: firstLaunchApp)
        setToggle(showToggle, to: false)
        XCTAssertFalse(toggleIsOn(showToggle))
        firstLaunchApp.terminate()

        let staleInventoryApp = makeApp(
            additionalArguments: appVisibilityRuntimeArguments(
                mockRuntimeVariant: "single-app-five-windows"
            )
        )
        launchFlowTabUITestApplication(staleInventoryApp)
        openSettingsTab(in: staleInventoryApp)

        let staleManageButton = element(in: staleInventoryApp, identifier: Identifier.settingsAppVisibilityManage)
        XCTAssertTrue(staleManageButton.waitForExistence(timeout: 6))
        tapElement(staleManageButton)
        XCTAssertTrue(element(in: staleInventoryApp, identifier: Identifier.settingsAppVisibilityManager).waitForExistence(timeout: 6))

        tapAppVisibilityHiddenFilter(in: staleInventoryApp)

        let staleHiddenRow = element(in: staleInventoryApp, identifier: Identifier.settingsAppVisibilityMockMail)
        XCTAssertTrue(staleHiddenRow.waitForExistence(timeout: 6))
        tapElement(staleHiddenRow)
        XCTAssertFalse(toggleIsOn(appVisibilityShowToggle(in: staleInventoryApp)))
    }

    private func launchMockSwitcherSearchFromUserPath() -> XCUIApplication {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-open-switcher",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))
        XCTAssertTrue(element(in: app, identifier: Identifier.switcherAppMockMail).waitForExistence(timeout: 8))

        app.activate()
        app.typeText("\r")

        XCTAssertTrue(element(in: app, identifier: Identifier.switcherSearchInput).waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        return app
    }

    private func appVisibilityRuntimeArguments(
        resetDefaults: Bool = false,
        opensSwitcher: Bool = false,
        opensSearch: Bool = false,
        mockRuntimeVariant: String? = nil
    ) -> [String] {
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
        if opensSearch {
            arguments.append("--flowtab-ui-open-switcher-search")
        } else if opensSwitcher {
            arguments.append("--flowtab-ui-open-switcher")
        }
        if let mockRuntimeVariant {
            arguments += [
                "--flowtab-ui-mock-runtime-variant",
                mockRuntimeVariant
            ]
        }
        return arguments
    }

    private func appVisibilityShowToggle(in app: XCUIApplication) -> XCUIElement {
        let switchElement = app.switches.firstMatch
        if switchElement.waitForExistence(timeout: 3) {
            return switchElement
        }
        let checkBox = app.checkBoxes.firstMatch
        XCTAssertTrue(checkBox.waitForExistence(timeout: 3))
        return checkBox
    }

    private func tapAppVisibilityHiddenFilter(in app: XCUIApplication) {
        let hiddenSegment = element(in: app, identifier: Identifier.settingsAppVisibilityFilterHidden)
        if hiddenSegment.waitForExistence(timeout: 3) {
            tapElement(hiddenSegment)
            return
        }

        let hiddenChinese = app.buttons["已隐藏"].firstMatch
        if hiddenChinese.waitForExistence(timeout: 2) {
            tapElement(hiddenChinese)
            return
        }

        let hiddenEnglish = app.buttons["Hidden"].firstMatch
        XCTAssertTrue(hiddenEnglish.waitForExistence(timeout: 4))
        tapElement(hiddenEnglish)
    }
}
