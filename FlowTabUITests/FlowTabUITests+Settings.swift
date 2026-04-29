import XCTest

extension FlowTabUITests {
    func testSettingsAppearanceTogglesCanBeChanged() throws {
        let app = makeApp(
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
        launchFlowTabUITestApplication(app)
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
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-runtime-log-level",
                "debug",
                "--flowtab-ui-record-hotkey-reload-diagnostics",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(firstLaunchApp)
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
        launchFlowTabUITestApplication(relaunchApp)
        openSettingsTab(in: relaunchApp)

        assertValue(of: element(in: relaunchApp, identifier: Identifier.settingsAppearanceThemeMode), equals: "dark")
        assertValue(of: element(in: relaunchApp, identifier: Identifier.settingsAppearanceAppLanguage), equals: "en")
    }

    func testSettingsWindowBehaviorDelayAndTogglesPersistAcrossRelaunch() throws {
        let firstLaunchApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-runtime-log-level",
                "debug",
                "--flowtab-ui-record-hotkey-reload-diagnostics",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(firstLaunchApp)
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
        launchFlowTabUITestApplication(relaunchApp)
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

        let mockMailAppTile = element(in: relaunchApp, identifier: "flowtab.switcher.app.com-flowtab-mock-mail")
        XCTAssertTrue(mockMailAppTile.waitForExistence(timeout: 8))
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
        launchFlowTabUITestApplication(firstLaunchApp)
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
        launchFlowTabUITestApplication(relaunchApp)
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
        launchFlowTabUITestApplication(app)
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

        let expectedSelections: [(control: String, option: String)] = [
            (Identifier.settingsHotkeyMainModifier, "option"),
            (Identifier.settingsHotkeyMainKey, "space"),
            (Identifier.settingsHotkeyQuitKey, "z"),
            (Identifier.settingsHotkeyInAppModifier, "command"),
            (Identifier.settingsHotkeyInAppKey, "a")
        ]
        let baselineSelections: [(control: String, option: String)] = [
            (Identifier.settingsHotkeyMainModifier, "control"),
            (Identifier.settingsHotkeyMainKey, "x"),
            (Identifier.settingsHotkeyQuitKey, "y"),
            (Identifier.settingsHotkeyInAppModifier, "option"),
            (Identifier.settingsHotkeyInAppKey, "b")
        ]
        for selection in baselineSelections {
            selectOption(in: firstLaunchApp, controlIdentifier: selection.control, optionIdentifier: selection.option)
        }
        let hotkeyReloadLogSnapshot = makeRuntimeLogFileSnapshot()
        for selection in expectedSelections {
            selectOption(in: firstLaunchApp, controlIdentifier: selection.control, optionIdentifier: selection.option)
            assertValue(of: element(in: firstLaunchApp, identifier: selection.control), equals: selection.option)
        }

        waitForRuntimeLogFiles(
            containing: [
                "updated main=Option + Space",
                "quit=Option + Z",
                "inApp=Command + A",
                "hotkeyReloadNotification sender=AppDelegate main=Option + Space inApp=Command + A"
            ],
            since: hotkeyReloadLogSnapshot
        )
        let hotkeyTriggerLogSnapshot = makeRuntimeLogFileSnapshot()
        firstLaunchApp.activate()
        firstLaunchApp.typeKey(.space, modifierFlags: .option)
        waitForRuntimeLogFiles(
            containing: [
                "activeSpaceIgnore trigger=global_show",
                "releaseConfirm trigger=flags_changed"
            ],
            since: hotkeyTriggerLogSnapshot
        )

        firstLaunchApp.terminate()

        let relaunchApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-mock-runtime",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(relaunchApp)
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
        launchFlowTabUITestApplication(app)
        openSettingsTab(in: app)

        let inAppModifier = element(in: app, identifier: Identifier.settingsHotkeyInAppModifier)
        let inAppKey = element(in: app, identifier: Identifier.settingsHotkeyInAppKey)
        XCTAssertTrue(inAppModifier.waitForExistence(timeout: 5))
        XCTAssertTrue(inAppKey.waitForExistence(timeout: 5))

        XCTAssertFalse(inAppModifier.isEnabled)
        XCTAssertFalse(inAppKey.isEnabled)
    }

}
