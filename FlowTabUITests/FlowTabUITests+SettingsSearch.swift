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

    func testSettingsSearchWindowScopeUnavailableWithoutAccessibilityPermission() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-ax-trusted",
                "NO",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))
        assertSettingsSearchWindowScopeUnavailable(in: app) {
            openSettingsTab(in: app)
        }
    }

    func testSettingsAppVisibilityNavigationConvergesFromVisibleState() throws {
        let app = makeApp(
            additionalArguments: appVisibilityRuntimeArguments(
                resetDefaults: true
            )
        )
        launchFlowTabUITestApplication(app)
        openSettingsTab(in: app)

        let manager = element(
            in: app,
            identifier: Identifier.settingsAppVisibilityManager
        )
        let manageButton = element(
            in: app,
            identifier: Identifier.settingsAppVisibilityManage
        )
        guard assertSettingsAppVisibilityManagerProjectionAfterNavigation(
            in: app,
            targetDescription: "visible-state App Visibility manager"
        ) else {
            return
        }

        let backButton = element(
            in: app,
            identifier: Identifier.settingsAppVisibilityBack
        )
        XCTAssertTrue(backButton.waitForExistence(timeout: 6))
        tapElement(backButton)

        XCTAssertTrue(waitForNonExistence(manager, timeout: 6))
        XCTAssertTrue(manageButton.waitForExistence(timeout: 6))
    }

    func testSettingsAppVisibilityHidesMockAppFromSwitcherAndSearch() throws {
        let settingsApp = makeApp(
            additionalArguments: appVisibilityRuntimeArguments(resetDefaults: true)
        )
        launchFlowTabUITestApplication(settingsApp)
        openSettingsTab(in: settingsApp)

        guard assertSettingsAppVisibilityInventoryReadinessAfterNavigation(
            in: settingsApp,
            targetDescription: "hidden-App configuration inventory"
        ) else {
            return
        }

        guard assertSettingsAppVisibilityQueryProjection(
            "Mail",
            targetRowIdentifier: Identifier.settingsAppVisibilityMockMail,
            in: settingsApp,
            targetDescription: "hidden-App configuration Search projection"
        ) else {
            return
        }

        let mockMailRow = element(in: settingsApp, identifier: Identifier.settingsAppVisibilityMockMail)
        tapElement(mockMailRow)

        let showToggle = appVisibilityShowToggle(in: settingsApp)
        setToggle(showToggle, to: false)
        XCTAssertFalse(toggleIsOn(showToggle))
        let settingsTermination = terminateFlowTabUITestApplication(
            settingsApp,
            targetDescription: "settings app visibility configuration"
        )
        XCTAssertTrue(
            settingsTermination.isSatisfied,
            "Settings app termination failed. "
                + settingsTermination.diagnosticSummary
        )

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
        let switcherTermination = terminateFlowTabUITestApplication(
            switcherApp,
            targetDescription: "app visibility switcher verification"
        )
        XCTAssertTrue(
            switcherTermination.isSatisfied,
            "Switcher app termination failed. "
                + switcherTermination.diagnosticSummary
        )

        let searchApp = makeApp(
            additionalArguments: appVisibilityRuntimeArguments(opensSearch: true)
        )
        let searchReadiness =
            prepareInitialFlowTabSearchInputReadiness()
        launchFlowTabUITestApplication(searchApp)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(searchApp, timeout: 10))
        _ = requireInitialFlowTabSearchInput(
            in: searchApp,
            observedBy: searchReadiness
        )
        let diagnosticsSummary = element(
            in: searchApp,
            identifier: Identifier.switcherSummary
        )
        XCTAssertTrue(
            diagnosticsSummary.waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            performAndWaitForSwitcherDiagnostics(
                [
                    FlowTabUITestSwitcherDiagnosticsExpectation(
                        key: "searchResultsScope",
                        expectedValue: "app"
                    ),
                    FlowTabUITestSwitcherDiagnosticsExpectation(
                        key: "searchResultsQuery",
                        expectedValue: "Mail",
                        decodesPercentEncoding: true
                    ),
                    FlowTabUITestSwitcherDiagnosticsExpectation(
                        key: "searchResults",
                        expectedValue: ""
                    )
                ],
                in: diagnosticsSummary,
                timeout: 5,
                trigger: {
                    searchApp.typeText("Mail")
                }
            ),
            "Search did not commit the exact empty app-result projection for Mail."
        )
        XCTAssertFalse(
            element(
                in: searchApp,
                identifier: Identifier.switcherSearchAppMockMail
            ).exists
        )
    }

    func testSettingsAppVisibilitySearchUsesSharedPinyinMatching() throws {
        let app = makeApp(
            additionalArguments: appVisibilityRuntimeArguments(resetDefaults: true)
        )
        launchFlowTabUITestApplication(app)
        openSettingsTab(in: app)

        guard assertSettingsAppVisibilityInventoryReadinessAfterNavigation(
            in: app,
            targetDescription: "pinyin Search inventory"
        ) else {
            return
        }

        XCTAssertTrue(
            assertSettingsAppVisibilityQueryProjection(
                "ceshi",
                targetRowIdentifier:
                    Identifier.settingsAppVisibilityChineseTest,
                in: app,
                targetDescription: "pinyin Search projection"
            )
        )
    }

    func testSettingsCurrentAppActivationPolicyAppearsAsHiddenApp() throws {
        let app = makeApp(
            additionalArguments: appVisibilityRuntimeArguments(resetDefaults: true)
        )
        launchFlowTabUITestApplication(app)
        openSettingsTab(in: app)

        let showInCommandTabToggle = toggleElement(
            in: app,
            identifier: Identifier.settingsAppearanceShowInCommandTab
        )
        XCTAssertTrue(showInCommandTabToggle.waitForExistence(timeout: 6))
        XCTAssertFalse(toggleIsOn(showInCommandTabToggle))
        XCTAssertTrue(app.staticTexts["已隐藏 1 个应用"].waitForExistence(timeout: 6))

        guard assertSettingsAppVisibilityInventoryReadinessAfterNavigation(
            in: app,
            targetDescription: "current-App inventory"
        ) else {
            return
        }

        tapAppVisibilityHiddenFilter(in: app)

        let currentAppRow = element(in: app, identifier: Identifier.settingsAppVisibilityCurrentApp)
        XCTAssertTrue(currentAppRow.waitForExistence(timeout: 6))
        tapElement(currentAppRow)
        XCTAssertFalse(toggleIsOn(appVisibilityShowToggle(in: app)))
    }

    func testSettingsAppVisibilityHiddenFilterShowsStoredHiddenAppMissingFromInventory() throws {
        let firstLaunchApp = makeApp(
            additionalArguments: appVisibilityRuntimeArguments(resetDefaults: true)
        )
        launchFlowTabUITestApplication(firstLaunchApp)
        openSettingsTab(in: firstLaunchApp)

        guard assertSettingsAppVisibilityInventoryReadinessAfterNavigation(
            in: firstLaunchApp,
            targetDescription: "stored hidden-App source inventory"
        ) else {
            return
        }

        guard assertSettingsAppVisibilityQueryProjection(
            "Mail",
            targetRowIdentifier: Identifier.settingsAppVisibilityMockMail,
            in: firstLaunchApp,
            targetDescription: "stored hidden-App source Search projection"
        ) else {
            return
        }

        let mockMailRow = element(in: firstLaunchApp, identifier: Identifier.settingsAppVisibilityMockMail)
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

        guard assertSettingsAppVisibilityInventoryReadinessAfterNavigation(
            in: staleInventoryApp,
            targetDescription: "stale hidden-App inventory"
        ) else {
            return
        }

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
                "--flowtab-ui-listen-switcher-trigger",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
                + FlowTabUITestSearchInputReadinessPolicy
                    .applicationEvidenceLaunchArguments
        )
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))
        postFlowTabUITestSwitcherTriggerAndWaitForDelivery(
            .global,
            traceLabel: "settings-search-user-path"
        )
        XCTAssertTrue(
            element(
                in: app,
                identifier: Identifier.switcherAppMockMail
            ).waitForExistence(timeout: 8)
        )

        let searchReadiness =
            prepareInitialFlowTabSearchInputReadiness()
        app.typeText("\r")

        _ = requireInitialFlowTabSearchInput(
            in: app,
            observedBy: searchReadiness
        )
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
            arguments +=
                FlowTabUITestSearchInputReadinessPolicy
                    .applicationEvidenceLaunchArguments
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
