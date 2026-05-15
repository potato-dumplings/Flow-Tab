import AppKit
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
        XCTAssertFalse(toggleIsOn(showInCommandTabToggle))
        XCTAssertTrue(app.staticTexts["像普通应用一样显示"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["关闭后，当前应用将仅作为菜单栏辅助应用运行。"].waitForExistence(timeout: 5))

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

    func testSettingsAppearanceThemeAndLanguageUpdateVisibleUI() throws {
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
        openSettingsTab(in: app)

        let settingsContent = element(in: app, identifier: Identifier.settingsTabContent)
        XCTAssertTrue(settingsContent.waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["外观"].waitForExistence(timeout: 5))

        selectOption(in: app, controlIdentifier: Identifier.settingsAppearanceThemeMode, optionIdentifier: "light")
        assertValue(of: element(in: app, identifier: Identifier.settingsAppearanceThemeMode), equals: "light")
        let lightLuminance = try XCTUnwrap(
            waitForAverageLuminance(of: settingsContent, timeout: 5) { $0 > 0.45 },
            "Settings content did not become visibly light"
        )

        selectOption(in: app, controlIdentifier: Identifier.settingsAppearanceThemeMode, optionIdentifier: "dark")
        assertValue(of: element(in: app, identifier: Identifier.settingsAppearanceThemeMode), equals: "dark")
        let darkLuminance = try XCTUnwrap(
            waitForAverageLuminance(of: settingsContent, timeout: 5) { $0 < lightLuminance - 0.18 },
            "Settings content did not become visibly darker after selecting dark theme"
        )
        XCTAssertLessThan(darkLuminance, lightLuminance - 0.18)

        selectOption(in: app, controlIdentifier: Identifier.settingsAppearanceAppLanguage, optionIdentifier: "en")
        assertValue(of: element(in: app, identifier: Identifier.settingsAppearanceAppLanguage), equals: "en")
        XCTAssertTrue(app.staticTexts["Display, hotkeys, and permissions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Theme mode"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForNonExistence(app.staticTexts["基础显示设置、快捷键与权限"], timeout: 2)
        )
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

    func testSettingsWindowBehaviorHideMinimizedAppsAffectsSwitcherAppLayer() throws {
        let baselineApp = makeApp(
            additionalArguments: windowBehaviorRuntimeArguments(
                resetDefaults: true,
                opensSwitcher: true
            )
        )
        launchFlowTabUITestApplication(baselineApp)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(baselineApp, timeout: 10))
        XCTAssertTrue(element(in: baselineApp, identifier: Identifier.switcherAppMockMail).waitForExistence(timeout: 8))
        XCTAssertTrue(
            element(
                in: baselineApp,
                identifier: Identifier.switcherAppMockMinimizedNotes
            ).waitForExistence(timeout: 8)
        )
        baselineApp.terminate()

        let settingsApp = makeApp(additionalArguments: windowBehaviorRuntimeArguments())
        launchFlowTabUITestApplication(settingsApp)
        openSettingsTab(in: settingsApp)

        let hideMinimizedToggle = toggleElement(in: settingsApp, identifier: Identifier.settingsWindowHideMinimizedApps)
        XCTAssertTrue(hideMinimizedToggle.waitForExistence(timeout: 5))
        setToggle(hideMinimizedToggle, to: true)
        XCTAssertTrue(toggleIsOn(hideMinimizedToggle))
        settingsApp.terminate()

        let filteredApp = makeApp(
            additionalArguments: windowBehaviorRuntimeArguments(opensSwitcher: true)
        )
        launchFlowTabUITestApplication(filteredApp)
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(filteredApp, timeout: 10))
        XCTAssertTrue(element(in: filteredApp, identifier: Identifier.switcherAppMockMail).waitForExistence(timeout: 8))
        XCTAssertTrue(
            waitForNonExistence(
                element(in: filteredApp, identifier: Identifier.switcherAppMockMinimizedNotes),
                timeout: 2
            )
        )
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

    func testSettingsMainHotkeyRepresentativeMatrixTriggersSwitcher() throws {
        let cases: [(modifier: String, key: String, shortcutText: String)] = [
            ("option", "space", "Option + Space"),
            ("control", "grave", "Control + `"),
            ("command", "b", "Command + B")
        ]

        for item in cases {
            configureHotkeysThroughSettings(
                rawSelections: [
                    (Identifier.settingsHotkeyMainModifier, item.modifier),
                    (Identifier.settingsHotkeyMainKey, item.key),
                    (Identifier.settingsHotkeyQuitKey, "z"),
                    (Identifier.settingsHotkeyInAppModifier, "option"),
                    (Identifier.settingsHotkeyInAppKey, "c")
                ],
                expectedValues: [
                    (Identifier.settingsHotkeyMainModifier, item.modifier),
                    (Identifier.settingsHotkeyMainKey, item.key),
                    (Identifier.settingsHotkeyQuitKey, "z"),
                    (Identifier.settingsHotkeyInAppModifier, "option"),
                    (Identifier.settingsHotkeyInAppKey, "c")
                ],
                expectedLogMarkers: [
                    "updated main=\(item.shortcutText)",
                    "hotkeyReloadNotification sender=AppDelegate main=\(item.shortcutText)"
                ]
            )

            let app = makeApp(additionalArguments: hotkeyEffectArguments())
            launchFlowTabUITestApplication(app)
            XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

            let logSnapshot = makeRuntimeLogFileSnapshot()
            app.activate()
            typeHotkey(in: app, key: item.key, modifier: item.modifier)
            waitForRuntimeLogFiles(
                containing: [
                    "hotkeyPressed dir=forward panelVisible=0 action=show",
                    "activeSpaceIgnore trigger=global_show",
                    "HotKey Forward"
                ],
                since: logSnapshot
            )
            app.terminate()
        }
    }

    func testSettingsCommandTabTakeoverTriggersSwitcherAndRestoresSystemShortcut() throws {
        let app = makeApp(additionalArguments: hotkeyEffectArguments(resetDefaults: true))
        launchFlowTabUITestApplication(app)
        defer {
            if app.state != .notRunning {
                app.activate()
                app.typeKey("q", modifierFlags: .command)
                if !app.wait(for: .notRunning, timeout: 6) {
                    app.terminate()
                    _ = app.wait(for: .notRunning, timeout: 6)
                }
            }
        }
        openSettingsTab(in: app)

        selectOption(in: app, controlIdentifier: Identifier.settingsHotkeyMainKey, optionIdentifier: "space")
        assertValue(of: element(in: app, identifier: Identifier.settingsHotkeyMainKey), equals: "space")

        let takeoverLogSnapshot = makeRuntimeLogFileSnapshot()
        selectOption(in: app, controlIdentifier: Identifier.settingsHotkeyMainModifier, optionIdentifier: "command")
        selectOption(in: app, controlIdentifier: Identifier.settingsHotkeyMainKey, optionIdentifier: "tab")
        assertValue(of: element(in: app, identifier: Identifier.settingsHotkeyMainModifier), equals: "command")
        assertValue(of: element(in: app, identifier: Identifier.settingsHotkeyMainKey), equals: "tab")

        waitForRuntimeLogFiles(
            containing: [
                "updated main=Command + Tab",
                "system Command+Tab shortcuts disabled for FlowTab takeover",
                "hotkeyReloadNotification sender=AppDelegate main=Command + Tab"
            ],
            since: takeoverLogSnapshot,
            timeout: 10
        )
        XCTAssertTrue(waitForCommandTabTakeoverMarker(true, timeout: 5))
        XCTAssertTrue(
            element(in: app, identifier: Identifier.settingsHotkeyMainTakeoverStatus)
                .waitForExistence(timeout: 5)
        )

        let triggerLogSnapshot = makeRuntimeLogFileSnapshot()
        app.activate()
        app.typeKey(.tab, modifierFlags: .command)
        waitForRuntimeLogFiles(
            containing: [
                "hotkeyPressed dir=forward panelVisible=0 action=show",
                "HotKey Forward"
            ],
            since: triggerLogSnapshot,
            timeout: 10
        )

        app.activate()
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 8))
        XCTAssertTrue(waitForCommandTabTakeoverMarker(false, timeout: 5))

        resetHotkeyDefaultsAfterCommandTabTakeoverTest()
    }

    func testSettingsQuitHotkeyExplicitAndFallbackMatrixTerminatesSelectedApp() throws {
        let cases: [(
            rawSelections: [(control: String, option: String)],
            expectedValues: [(control: String, value: String)],
            triggerKey: String,
            expectedQuitShortcut: String
        )] = [
            (
                [
                    (Identifier.settingsHotkeyMainModifier, "option"),
                    (Identifier.settingsHotkeyMainKey, "space"),
                    (Identifier.settingsHotkeyQuitKey, "z"),
                    (Identifier.settingsHotkeyInAppModifier, "option"),
                    (Identifier.settingsHotkeyInAppKey, "b")
                ],
                [
                    (Identifier.settingsHotkeyMainModifier, "option"),
                    (Identifier.settingsHotkeyMainKey, "space"),
                    (Identifier.settingsHotkeyQuitKey, "z"),
                    (Identifier.settingsHotkeyInAppModifier, "option"),
                    (Identifier.settingsHotkeyInAppKey, "b")
                ],
                "z",
                "Option + Z"
            ),
            (
                [
                    (Identifier.settingsHotkeyMainModifier, "option"),
                    (Identifier.settingsHotkeyMainKey, "q"),
                    (Identifier.settingsHotkeyQuitKey, "q"),
                    (Identifier.settingsHotkeyInAppModifier, "control"),
                    (Identifier.settingsHotkeyInAppKey, "b")
                ],
                [
                    (Identifier.settingsHotkeyMainModifier, "option"),
                    (Identifier.settingsHotkeyMainKey, "q"),
                    (Identifier.settingsHotkeyQuitKey, "w"),
                    (Identifier.settingsHotkeyInAppModifier, "control"),
                    (Identifier.settingsHotkeyInAppKey, "b")
                ],
                "w",
                "Option + W"
            )
        ]

        for item in cases {
            configureHotkeysThroughSettings(
                rawSelections: item.rawSelections,
                expectedValues: item.expectedValues,
                expectedLogMarkers: [
                    "quit=\(item.expectedQuitShortcut)",
                    "hotkeyReloadNotification sender=AppDelegate"
                ]
            )

            let app = makeApp(additionalArguments: hotkeyEffectArguments() + ["--flowtab-ui-open-switcher"])
            launchFlowTabUITestApplication(app)
            XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

            let browserTile = element(in: app, identifier: Identifier.switcherAppMockBrowser)
            XCTAssertTrue(browserTile.waitForExistence(timeout: 8))

            let logSnapshot = makeRuntimeLogFileSnapshot()
            typeHotkey(in: app, key: item.triggerKey, modifier: "option")
            waitForRuntimeLogFiles(
                containing: [
                    "mock terminate request appID=com.flowtab.mock.browser",
                    "terminate request app=Mock Browser appID=com.flowtab.mock.browser sent=true",
                    "terminate post-refresh reason=poll appID=com.flowtab.mock.browser"
                ],
                since: logSnapshot,
                timeout: 10
            )
            XCTAssertTrue(waitForNonExistence(browserTile, timeout: 6))
            app.terminate()
        }
    }

    func testSettingsInAppHotkeyExplicitAndFallbackMatrixStartsFocusedWindowSession() throws {
        let cases: [(
            rawSelections: [(control: String, option: String)],
            expectedValues: [(control: String, value: String)],
            triggerModifier: String,
            triggerKey: String,
            expectedInAppShortcut: String
        )] = [
            (
                [
                    (Identifier.settingsHotkeyMainModifier, "option"),
                    (Identifier.settingsHotkeyMainKey, "space"),
                    (Identifier.settingsHotkeyQuitKey, "z"),
                    (Identifier.settingsHotkeyInAppModifier, "option"),
                    (Identifier.settingsHotkeyInAppKey, "b")
                ],
                [
                    (Identifier.settingsHotkeyMainModifier, "option"),
                    (Identifier.settingsHotkeyMainKey, "space"),
                    (Identifier.settingsHotkeyQuitKey, "z"),
                    (Identifier.settingsHotkeyInAppModifier, "option"),
                    (Identifier.settingsHotkeyInAppKey, "b")
                ],
                "option",
                "b",
                "Option + B"
            ),
            (
                [
                    (Identifier.settingsHotkeyMainModifier, "option"),
                    (Identifier.settingsHotkeyMainKey, "b"),
                    (Identifier.settingsHotkeyQuitKey, "z"),
                    (Identifier.settingsHotkeyInAppModifier, "option"),
                    (Identifier.settingsHotkeyInAppKey, "b")
                ],
                [
                    (Identifier.settingsHotkeyMainModifier, "option"),
                    (Identifier.settingsHotkeyMainKey, "b"),
                    (Identifier.settingsHotkeyQuitKey, "z"),
                    (Identifier.settingsHotkeyInAppModifier, "control"),
                    (Identifier.settingsHotkeyInAppKey, "b")
                ],
                "control",
                "b",
                "Control + B"
            )
        ]

        for item in cases {
            configureHotkeysThroughSettings(
                rawSelections: item.rawSelections,
                expectedValues: item.expectedValues,
                expectedLogMarkers: [
                    "inApp=\(item.expectedInAppShortcut)",
                    "hotkeyReloadNotification sender=AppDelegate"
                ]
            )

            let app = makeApp(
                additionalArguments: hotkeyEffectArguments() + [
                    "--flowtab-ui-mock-runtime-variant",
                    "focused-current-app"
                ]
            )
            launchFlowTabUITestApplication(app)
            XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))

            let logSnapshot = makeRuntimeLogFileSnapshot()
            app.activate()
            typeHotkey(in: app, key: item.triggerKey, modifier: item.triggerModifier)
            waitForRuntimeLogFiles(
                containing: [
                    "inAppHotkeyPressed dir=forward panelVisible=0 action=show",
                    "activeSpaceIgnore trigger=in_app_show",
                    "InApp Window Forward"
                ],
                since: logSnapshot
            )
            app.terminate()
        }
    }

    private func hotkeyEffectArguments(resetDefaults: Bool = false) -> [String] {
        var arguments: [String] = []
        if resetDefaults {
            arguments.append("--flowtab-ui-reset-defaults")
        }
        arguments += [
            "--flowtab-ui-mock-runtime",
            "--flowtab-ui-runtime-log-level",
            "DEBUG",
            "--flowtab-ui-enable-verbose-logs",
            "--flowtab-ui-record-hotkey-reload-diagnostics",
            "--flowtab-ui-enable-mock-hotkey-effects",
            "--flowtab-ui-ax-trusted",
            "YES",
            "--flowtab-ui-screen-trusted",
            "YES"
        ]
        return arguments
    }

    private func windowBehaviorRuntimeArguments(
        resetDefaults: Bool = false,
        opensSwitcher: Bool = false
    ) -> [String] {
        var arguments: [String] = []
        if resetDefaults {
            arguments.append("--flowtab-ui-reset-defaults")
        }
        arguments += [
            "--flowtab-ui-mock-runtime",
            "--flowtab-ui-mock-runtime-variant",
            "minimized-window-behavior",
            "-showPermissionReminder",
            "NO",
            "--flowtab-ui-ax-trusted",
            "YES",
            "--flowtab-ui-screen-trusted",
            "YES"
        ]
        if opensSwitcher {
            arguments.append("--flowtab-ui-open-switcher")
        }
        return arguments
    }

    private func configureHotkeysThroughSettings(
        rawSelections: [(control: String, option: String)],
        expectedValues: [(control: String, value: String)],
        expectedLogMarkers: [String]
    ) {
        let app = makeApp(additionalArguments: hotkeyEffectArguments(resetDefaults: true))
        launchFlowTabUITestApplication(app)
        openSettingsTab(in: app)

        let logSnapshot = makeRuntimeLogFileSnapshot()
        for selection in rawSelections {
            selectOption(in: app, controlIdentifier: selection.control, optionIdentifier: selection.option)
        }
        for expectedValue in expectedValues {
            assertValue(of: element(in: app, identifier: expectedValue.control), equals: expectedValue.value)
        }
        waitForRuntimeLogFiles(containing: expectedLogMarkers, since: logSnapshot)
        app.terminate()
    }

    private func resetHotkeyDefaultsAfterCommandTabTakeoverTest() {
        let cleanupApp = makeApp(
            additionalArguments: [
                "--flowtab-ui-reset-defaults",
                "-showPermissionReminder",
                "NO",
                "--flowtab-ui-ax-trusted",
                "YES",
                "--flowtab-ui-screen-trusted",
                "YES"
            ]
        )
        launchFlowTabUITestApplication(cleanupApp)
        cleanupApp.terminate()
        _ = cleanupApp.wait(for: .notRunning, timeout: 6)
    }

    private func waitForCommandTabTakeoverMarker(_ expectedValue: Bool, timeout: TimeInterval) -> Bool {
        let defaults = UserDefaults(suiteName: "io.github.potato-dumplings.flowtab") ?? .standard
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            defaults.synchronize()
            if defaults.bool(forKey: "commandTabTakeoverPendingRestore") == expectedValue {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return false
    }

    private func typeHotkey(in app: XCUIApplication, key: String, modifier: String) {
        let modifierFlags = modifierFlags(for: modifier)
        switch key {
        case "space":
            app.typeKey(.space, modifierFlags: modifierFlags)
        case "tab":
            app.typeKey(.tab, modifierFlags: modifierFlags)
        case "grave":
            app.typeKey("`", modifierFlags: modifierFlags)
        default:
            app.typeKey(key, modifierFlags: modifierFlags)
        }
    }

    private func modifierFlags(for modifier: String) -> XCUIElement.KeyModifierFlags {
        switch modifier {
        case "option":
            return .option
        case "control":
            return .control
        case "command":
            return .command
        default:
            XCTFail("Unsupported hotkey modifier: \(modifier)")
            return []
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

    private func waitForAverageLuminance(
        of element: XCUIElement,
        timeout: TimeInterval,
        matching predicate: (CGFloat) -> Bool
    ) -> CGFloat? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let luminance = averageLuminance(of: element), predicate(luminance) {
                return luminance
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return nil
    }

    private func averageLuminance(of element: XCUIElement) -> CGFloat? {
        guard element.exists,
              let bitmap = NSBitmapImageRep(data: element.screenshot().pngRepresentation),
              bitmap.pixelsWide > 0,
              bitmap.pixelsHigh > 0
        else {
            return nil
        }

        let sampleStep = max(1, min(bitmap.pixelsWide, bitmap.pixelsHigh) / 80)
        var total: CGFloat = 0
        var samples = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: sampleStep) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: sampleStep) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                total += color.redComponent * 0.2126
                    + color.greenComponent * 0.7152
                    + color.blueComponent * 0.0722
                samples += 1
            }
        }
        return samples > 0 ? total / CGFloat(samples) : nil
    }

}
