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
        static let logsOpenDirectoryButton = "flowtab.logs.open-directory"
        static let logsLines = "flowtab.logs.lines"
        static let logsEmptyHint = "flowtab.logs.empty-hint"
        static let logsSeededDebugLine = "flowtab.logs.line.seeded.debug"
        static let logsSeededInfoLine = "flowtab.logs.line.seeded.info"
        static let logsSeededWarnLine = "flowtab.logs.line.seeded.warn"
        static let logsSeededErrorLine = "flowtab.logs.line.seeded.error"
        static let settingsAppearanceShowShortcutHint = "flowtab.settings.appearance.show-shortcut-hint"
        static let settingsAppearanceShowInCommandTab = "flowtab.settings.appearance.show-in-command-tab"
        static let settingsAppearanceThemeMode = "flowtab.settings.appearance.theme-mode"
        static let settingsAppearanceAppLanguage = "flowtab.settings.appearance.app-language"
        static let settingsWindowAutoEnterDelay = "flowtab.settings.window.auto-enter-delay"
        static let settingsWindowAutoEnterDelayInput = "flowtab.settings.window.auto-enter-delay.input"
        static let settingsWindowAutoRestoreMinimized = "flowtab.settings.window.auto-restore-minimized"
        static let settingsWindowHideMinimizedApps = "flowtab.settings.window.hide-minimized-apps"
        static let settingsSearchEnabled = "flowtab.settings.search.enabled"
        static let settingsSearchDefaultScope = "flowtab.settings.search.default-scope"
        static let settingsPermissionAccessibilityAction = "flowtab.settings.permission.accessibility-action"
        static let settingsPermissionScreenCaptureAction = "flowtab.settings.permission.screen-capture-action"
        static let settingsHotkeyMainModifier = "flowtab.settings.hotkey.main-modifier"
        static let settingsHotkeyMainKey = "flowtab.settings.hotkey.main-key"
        static let settingsHotkeyQuitKey = "flowtab.settings.hotkey.quit-key"
        static let settingsHotkeyInAppModifier = "flowtab.settings.hotkey.in-app-modifier"
        static let settingsHotkeyInAppKey = "flowtab.settings.hotkey.in-app-key"
        static let switcherPanel = "flowtab.switcher.panel"
        static let switcherSearchInput = "flowtab.switcher.search.input"
        static let switcherAppMockMail = "flowtab.switcher.app.com-flowtab-mock-mail"
        static let switcherAppMockBrowser = "flowtab.switcher.app.com-flowtab-mock-browser"
        static let switcherSearchWindowMockMailInbox = "flowtab.switcher.search.window.mock-mail-inbox"
        static let switcherWindowMockMailInbox = "flowtab.switcher.window.mock-mail-inbox"
        static let switcherWindowMockMailDraft = "flowtab.switcher.window.mock-mail-draft"
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

    func testSettingsAppearanceTogglesCanBeChanged() throws {
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
        openSettingsTab(in: app)

        let showShortcutHintToggle = toggleElement(in: app, identifier: Identifier.settingsAppearanceShowShortcutHint)
        let showInCommandTabToggle = toggleElement(in: app, identifier: Identifier.settingsAppearanceShowInCommandTab)
        XCTAssertTrue(showShortcutHintToggle.waitForExistence(timeout: 5))
        XCTAssertTrue(showInCommandTabToggle.waitForExistence(timeout: 5))

        let targetShortcutHint = !toggleIsOn(showShortcutHintToggle)
        let targetShowInCommandTab = !toggleIsOn(showInCommandTabToggle)
        setToggle(showShortcutHintToggle, to: targetShortcutHint)
        setToggle(showInCommandTabToggle, to: targetShowInCommandTab)

        XCTAssertEqual(toggleIsOn(showShortcutHintToggle), targetShortcutHint)
        XCTAssertEqual(toggleIsOn(showInCommandTabToggle), targetShowInCommandTab)
    }

    func testSettingsAppearanceThemeAndLanguagePersistAcrossRelaunch() throws {
        let firstLaunchApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        firstLaunchApp.launch()
        openSettingsTab(in: firstLaunchApp)

        selectOption(in: firstLaunchApp, controlIdentifier: Identifier.settingsAppearanceThemeMode, optionIdentifier: "dark")
        assertValue(of: element(in: firstLaunchApp, identifier: Identifier.settingsAppearanceThemeMode), equals: "dark")

        selectOption(in: firstLaunchApp, controlIdentifier: Identifier.settingsAppearanceAppLanguage, optionIdentifier: "en")
        assertValue(of: element(in: firstLaunchApp, identifier: Identifier.settingsAppearanceAppLanguage), equals: "en")

        firstLaunchApp.terminate()

        let relaunchApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        relaunchApp.launch()
        openSettingsTab(in: relaunchApp)

        assertValue(of: element(in: relaunchApp, identifier: Identifier.settingsAppearanceThemeMode), equals: "dark")
        assertValue(of: element(in: relaunchApp, identifier: Identifier.settingsAppearanceAppLanguage), equals: "en")
    }

    func testSettingsWindowBehaviorDelayAndTogglesPersistAcrossRelaunch() throws {
        let firstLaunchApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        firstLaunchApp.launch()
        openSettingsTab(in: firstLaunchApp)

        let delayInput = element(in: firstLaunchApp, identifier: Identifier.settingsWindowAutoEnterDelayInput)
        XCTAssertTrue(delayInput.waitForExistence(timeout: 5))
        replaceText(in: delayInput, with: "1.2345", app: firstLaunchApp)
        commitEditing(in: firstLaunchApp)
        assertValuePrefix(of: delayInput, expectedPrefix: "1.23")

        let autoRestoreToggle = toggleElement(in: firstLaunchApp, identifier: Identifier.settingsWindowAutoRestoreMinimized)
        let hideMinimizedToggle = toggleElement(in: firstLaunchApp, identifier: Identifier.settingsWindowHideMinimizedApps)
        XCTAssertTrue(autoRestoreToggle.waitForExistence(timeout: 5))
        XCTAssertTrue(hideMinimizedToggle.waitForExistence(timeout: 5))

        let expectedAutoRestore = !toggleIsOn(autoRestoreToggle)
        let expectedHideMinimized = !toggleIsOn(hideMinimizedToggle)
        setToggle(autoRestoreToggle, to: expectedAutoRestore)
        setToggle(hideMinimizedToggle, to: expectedHideMinimized)

        firstLaunchApp.terminate()

        let relaunchApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        relaunchApp.launch()
        openSettingsTab(in: relaunchApp)

        let relaunchDelayInput = element(in: relaunchApp, identifier: Identifier.settingsWindowAutoEnterDelayInput)
        assertValuePrefix(of: relaunchDelayInput, expectedPrefix: "1.23")
        XCTAssertEqual(
            toggleIsOn(toggleElement(in: relaunchApp, identifier: Identifier.settingsWindowAutoRestoreMinimized)),
            expectedAutoRestore
        )
        XCTAssertEqual(
            toggleIsOn(toggleElement(in: relaunchApp, identifier: Identifier.settingsWindowHideMinimizedApps)),
            expectedHideMinimized
        )
    }

    func testSettingsSearchDisabledPreventsAutoSearchLaunchEntry() throws {
        let firstLaunchApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        firstLaunchApp.launch()
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
        relaunchApp.launch()
        XCTAssertTrue(relaunchApp.wait(for: .runningForeground, timeout: 10))

        let switcherPanel = element(in: relaunchApp, identifier: Identifier.switcherPanel)
        XCTAssertTrue(switcherPanel.waitForExistence(timeout: 8))
        XCTAssertFalse(element(in: relaunchApp, identifier: Identifier.switcherSearchInput).exists)
    }

    func testSettingsSearchDefaultWindowScopePersistsAndShowsWindowResults() throws {
        let firstLaunchApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        firstLaunchApp.launch()
        openSettingsTab(in: firstLaunchApp)

        let searchEnabledToggle = toggleElement(in: firstLaunchApp, identifier: Identifier.settingsSearchEnabled)
        XCTAssertTrue(searchEnabledToggle.waitForExistence(timeout: 5))
        setToggle(searchEnabledToggle, to: true)

        selectOption(in: firstLaunchApp, controlIdentifier: Identifier.settingsSearchDefaultScope, optionIdentifier: "window")
        assertValue(of: element(in: firstLaunchApp, identifier: Identifier.settingsSearchDefaultScope), equals: "window")
        firstLaunchApp.terminate()

        let relaunchApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        relaunchApp.launch()
        openSettingsTab(in: relaunchApp)
        assertValue(of: element(in: relaunchApp, identifier: Identifier.settingsSearchDefaultScope), equals: "window")
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
        firstLaunchApp.launch()
        openSettingsTab(in: firstLaunchApp)

        let searchEnabledToggle = toggleElement(in: firstLaunchApp, identifier: Identifier.settingsSearchEnabled)
        XCTAssertTrue(searchEnabledToggle.waitForExistence(timeout: 5))
        setToggle(searchEnabledToggle, to: true)

        selectOption(in: firstLaunchApp, controlIdentifier: Identifier.settingsSearchDefaultScope, optionIdentifier: "app")
        assertValue(of: element(in: firstLaunchApp, identifier: Identifier.settingsSearchDefaultScope), equals: "app")

        selectOption(in: firstLaunchApp, controlIdentifier: Identifier.settingsSearchDefaultScope, optionIdentifier: "window")
        assertValue(of: element(in: firstLaunchApp, identifier: Identifier.settingsSearchDefaultScope), equals: "window")
    }

    func testSettingsPermissionActionButtonsAreVisible() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-ax-trusted",
                "NO",
                "--flowtab-ui-screen-trusted",
                "NO"
            ]
        )
        app.launch()
        openSettingsTab(in: app)

        XCTAssertTrue(
            element(in: app, identifier: Identifier.settingsPermissionAccessibilityAction).waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            element(in: app, identifier: Identifier.settingsPermissionScreenCaptureAction).waitForExistence(timeout: 5)
        )
    }

    func testSettingsHotkeySelectionsPersistAcrossRelaunch() throws {
        let firstLaunchApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        firstLaunchApp.launch()
        openSettingsTab(in: firstLaunchApp)

        let expectedSelections: [(control: String, option: String)] = [
            (Identifier.settingsHotkeyMainKey, "space"),
            (Identifier.settingsHotkeyQuitKey, "z"),
            (Identifier.settingsHotkeyInAppKey, "a")
        ]
        for selection in expectedSelections {
            selectOption(in: firstLaunchApp, controlIdentifier: selection.control, optionIdentifier: selection.option)
            assertValue(of: element(in: firstLaunchApp, identifier: selection.control), equals: selection.option)
        }

        firstLaunchApp.terminate()

        let relaunchApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        relaunchApp.launch()
        openSettingsTab(in: relaunchApp)

        for selection in expectedSelections {
            assertValue(of: element(in: relaunchApp, identifier: selection.control), equals: selection.option)
        }
    }

    func testSettingsHotkeyInAppControlsDisabledWithoutAccessibilityPermission() throws {
        let app = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-ax-trusted",
                "NO",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        app.launch()
        openSettingsTab(in: app)

        let inAppModifier = element(in: app, identifier: Identifier.settingsHotkeyInAppModifier)
        let inAppKey = element(in: app, identifier: Identifier.settingsHotkeyInAppKey)
        XCTAssertTrue(inAppModifier.waitForExistence(timeout: 5))
        XCTAssertTrue(inAppKey.waitForExistence(timeout: 5))

        XCTAssertFalse(inAppModifier.isEnabled)
        XCTAssertFalse(inAppKey.isEnabled)
    }

    func testSwitcherPanelShowsMockAppTilesInStandardMode() throws {
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

        XCTAssertTrue(element(in: app, identifier: Identifier.switcherPanel).waitForExistence(timeout: 8))
        app.typeKey(.escape, modifierFlags: [])
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertFalse(element(in: app, identifier: Identifier.switcherSearchInput).exists)
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

    func testSwitcherPanelMoveAppThenAutoEnterWindowLayerShowsMockWindows() throws {
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
        XCTAssertTrue(switcherPanel.waitForExistence(timeout: 8))

        app.typeKey(.escape, modifierFlags: [])
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        let mailInboxWindow = switcherPanel.descendants(matching: .any)
            .matching(identifier: Identifier.switcherWindowMockMailInbox)
            .firstMatch
        let mailDraftWindow = switcherPanel.descendants(matching: .any)
            .matching(identifier: Identifier.switcherWindowMockMailDraft)
            .firstMatch
        XCTAssertFalse(mailInboxWindow.exists)
        XCTAssertFalse(mailDraftWindow.exists)

        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        app.typeKey(.leftArrow, modifierFlags: [])

        XCTAssertTrue(mailInboxWindow.waitForExistence(timeout: 3))
        XCTAssertTrue(mailDraftWindow.waitForExistence(timeout: 3))
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
        toggleElement(in: app, identifier: Identifier.permissionReminderSwitch)
    }

    private func openSettingsTab(in app: XCUIApplication) {
        XCTAssertTrue(
            tapFirstHittable(in: app.buttons.matching(identifier: Identifier.settingsTabButton), timeout: 6)
        )
        XCTAssertTrue(element(in: app, identifier: Identifier.settingsTabContent).waitForExistence(timeout: 6))
    }

    private func openLogsTab(in app: XCUIApplication) {
        XCTAssertTrue(
            tapFirstHittable(in: app.buttons.matching(identifier: Identifier.logsTabButton), timeout: 6)
        )
        XCTAssertTrue(element(in: app, identifier: Identifier.logsTabContent).waitForExistence(timeout: 6))
    }

    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func toggleElement(in app: XCUIApplication, identifier: String) -> XCUIElement {
        let switchElement = app.switches[identifier]
        if switchElement.exists || switchElement.waitForExistence(timeout: 1) {
            return switchElement
        }
        return app.checkBoxes[identifier]
    }

    private func toggleIsOn(_ element: XCUIElement) -> Bool {
        if let stringValue = element.value as? String {
            let normalized = stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized == "1" || normalized == "true" || normalized == "on"
        }
        if let numericValue = element.value as? NSNumber {
            return numericValue.intValue != 0
        }
        return element.isSelected
    }

    private func setToggle(_ element: XCUIElement, to expectedValue: Bool) {
        if toggleIsOn(element) != expectedValue {
            tapElement(element)
        }
    }

    private func selectOption(
        in app: XCUIApplication,
        controlIdentifier: String,
        optionIdentifier: String
    ) {
        let control = element(in: app, identifier: controlIdentifier)
        XCTAssertTrue(control.waitForExistence(timeout: 6), "Missing control: \(controlIdentifier)")
        tapElement(control)

        let optionsQuery = app.descendants(matching: .any).matching(identifier: optionIdentifier)
        XCTAssertTrue(
            tapFirstHittable(in: optionsQuery, timeout: 6),
            "Missing or non-hittable option: \(optionIdentifier)"
        )
    }

    private func elementStringValue(_ element: XCUIElement) -> String {
        if let value = element.value as? String {
            return value
        }
        if let numberValue = element.value as? NSNumber {
            return numberValue.stringValue
        }
        return element.label
    }

    private func assertValue(of element: XCUIElement, equals expectedValue: String, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.exists && elementStringValue(element) == expectedValue {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        XCTFail("Expected value '\(expectedValue)' for \(element.identifier), actual: '\(elementStringValue(element))'")
    }

    private func assertValuePrefix(of element: XCUIElement, expectedPrefix: String, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.exists && elementStringValue(element).hasPrefix(expectedPrefix) {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        XCTFail(
            "Expected prefix '\(expectedPrefix)' for \(element.identifier), actual: '\(elementStringValue(element))'"
        )
    }

    private func replaceText(in field: XCUIElement, with text: String, app: XCUIApplication) {
        tapElement(field)
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])
        app.typeText(text)
    }

    private func commitEditing(in app: XCUIApplication) {
        app.typeKey(.tab, modifierFlags: [])
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }

    private func tapElement(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
            return
        }
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
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
