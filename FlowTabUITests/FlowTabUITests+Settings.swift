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
        guard let controls =
            assertSettingsAppearanceControlsProjectionAfterNavigation(
                in: app,
                targetDescription: "Appearance toggle mutation",
                trigger: {
                    openSettingsTab(in: app)
                }
            )
        else {
            return
        }

        let showShortcutHintToggle = controls.shortcutHintToggle
        let showInCommandTabToggle = controls.currentAppToggle
        XCTAssertFalse(toggleIsOn(showInCommandTabToggle))

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
        guard
            assertSettingsInitialAppearanceProjectionAfterNavigation(
                in: app,
                targetDescription: "theme and language visible UI",
                trigger: {
                    openSettingsTab(in: app)
                }
            )
        else {
            return
        }

        let settingsContent = element(in: app, identifier: Identifier.settingsTabContent)
        let themeTransitionWatchdog =
            FlowTabUITestAverageLuminanceObservationPolicy
                .settingsThemeTransitionWatchdog

        let lightLuminance = try XCTUnwrap(
            performAndWaitForAverageLuminance(
                of: settingsContent,
                expectedDescription: "greater than 0.45",
                watchdog: themeTransitionWatchdog,
                trigger: {
                    self.selectOption(
                        in: app,
                        controlIdentifier:
                            Identifier.settingsAppearanceThemeMode,
                        optionIdentifier: "light"
                    )
                },
                matching: { $0 > 0.45 }
            ),
            "Settings content did not become visibly light"
        )
        assertValue(
            of: element(
                in: app,
                identifier:
                    Identifier.settingsAppearanceThemeMode
            ),
            equals: "light"
        )

        let maximumDarkLuminance =
            lightLuminance - 0.18
        let darkLuminance = try XCTUnwrap(
            performAndWaitForAverageLuminance(
                of: settingsContent,
                expectedDescription:
                    "less than \(maximumDarkLuminance)",
                watchdog: themeTransitionWatchdog,
                trigger: {
                    self.selectOption(
                        in: app,
                        controlIdentifier:
                            Identifier.settingsAppearanceThemeMode,
                        optionIdentifier: "dark"
                    )
                },
                matching: {
                    $0 < maximumDarkLuminance
                }
            ),
            "Settings content did not become visibly darker after selecting dark theme"
        )
        assertValue(
            of: element(
                in: app,
                identifier:
                    Identifier.settingsAppearanceThemeMode
            ),
            equals: "dark"
        )
        XCTAssertLessThan(
            darkLuminance,
            maximumDarkLuminance
        )

        guard let englishAppearance =
            assertSettingsEnglishAppearanceProjectionAfterSelectingEnglish(
                in: app,
                targetDescription: "theme and language visible UI"
            )
        else {
            return
        }
        assertSettingsPageSubtitleIsVisible(
            englishAppearance.pageSubtitle,
            below: englishAppearance.pageTitle
        )
    }

    func testSettingsWindowBehaviorDefaultIncludesMinimizedAppsInInitialSwitcher()
        throws
    {
        let baselineRequiredItemIDs: Set<String> = [
            "com.flowtab.mock.mail",
            "com.flowtab.mock.minimized-notes"
        ]
        let baselineResolutionRoute =
            FlowTabUITestInitialPresentationResolutionRoute()
        try baselineResolutionRoute.prepareReadback()
        let baselineResolutionOwner =
            FlowTabUITestInitialPresentationResolutionObservationOwner(
                route: baselineResolutionRoute,
                expectation:
                    FlowTabUITestInitialPresentationResolutionExpectation(
                        requiredItemIDs: baselineRequiredItemIDs,
                        searchFeatureEnabled: true,
                        searchIsActive: false,
                        searchActivationIsPending: false
                    )
            )
        baselineResolutionOwner.start()
        defer {
            baselineResolutionOwner.cancel()
            baselineResolutionRoute.removeReadback()
        }

        let baselineApp = makeApp(
            additionalArguments: windowBehaviorRuntimeArguments(
                resetDefaults: true,
                opensSwitcher: true
            )
                + baselineResolutionRoute.launchArguments
        )
        defer { baselineApp.terminate() }
        launchFlowTabUITestApplication(baselineApp)
        guard let baselineResolution =
                baselineResolutionOwner.waitForResolution(
                    timeout:
                        FlowTabUITestInitialPresentationResolutionPolicy
                            .watchdog
                )
        else {
            XCTFail(
                "Hide-minimized baseline initial presentation watchdog "
                    + "expired. "
                    + baselineResolutionOwner.diagnosticSummary
            )
            return
        }
        XCTAssertTrue(
            baselineRequiredItemIDs.isSubset(
                of: Set(baselineResolution.candidateItemIDs)
            ),
            baselineResolution.diagnosticSummary
        )
        XCTAssertEqual(
            baselineResolution.sessionItemIDs,
            baselineResolution.candidateItemIDs,
            baselineResolution.diagnosticSummary
        )
        XCTAssertTrue(
            baselineResolution.panelIsPresented,
            baselineResolution.diagnosticSummary
        )
        XCTAssertEqual(
            baselineResolution.sessionMode,
            "appCycle",
            baselineResolution.diagnosticSummary
        )
    }

    func testSettingsWindowBehaviorHideMinimizedAppsAffectsSwitcherAppLayer() throws {
        let settingsApp = makeApp(
            additionalArguments: windowBehaviorRuntimeArguments(
                resetDefaults: true
            )
        )
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
        assertInitialDeniedSettingsPermissionProjection(in: app) {
            openSettingsTab(in: app)
        }
    }

    func testSettingsSimplifiedChinesePermissionStatusesAreVisible() throws {
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
        XCTAssertTrue(waitForFlowTabUITestApplicationToBecomeReady(app, timeout: 10))
        assertInitialDeniedSettingsPermissionProjection(in: app) {
            openSettingsTab(in: app)
        }
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
                "presentationRecovery trigger=global_show action=trackInitialVisibility"
            ],
            since: hotkeyTriggerLogSnapshot
        )
        waitForRuntimeLogFiles(
            matching: #"releaseConfirm (start|alreadyRunning) trigger=flags_changed"#,
            since: hotkeyTriggerLogSnapshot,
            description: "flags-changed release delivery reaches the confirmation state machine"
        )
        waitForRuntimeLogFiles(
            matching: #"releaseConfirm confirmed trigger=(flags_changed|presentation_recovered) action=finishSelection"#,
            since: hotkeyTriggerLogSnapshot,
            description: "the first valid release confirmation commits the selection"
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

    func testSettingsHotkeyKeyDropdownOpensAsRightSideMenuWhenSpaceAllows() throws {
        let app = makeApp(additionalArguments: hotkeyEffectArguments(resetDefaults: true))
        launchFlowTabUITestApplication(app)
        openSettingsTab(in: app)

        let control = element(in: app, identifier: Identifier.settingsHotkeyMainKey)
        XCTAssertTrue(control.waitForExistence(timeout: 6))
        let controlFrame = control.frame
        let visibleMaxX = NSScreen.main?.visibleFrame.maxX ?? controlFrame.maxX
        guard visibleMaxX - controlFrame.maxX >= 190 else {
            throw XCTSkip("Current screen does not leave enough right-side room for the side-menu UI assertion.")
        }

        tapElement(control)
        let scopedOption = app.descendants(matching: .any)
            .matching(identifier: "\(Identifier.settingsHotkeyMainKey).option.space")
            .firstMatch
        let rawOption = app.descendants(matching: .any).matching(identifier: "space").firstMatch
        let option = scopedOption.waitForExistence(timeout: 2) ? scopedOption : rawOption
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(option.frame.minX, controlFrame.maxX - 1)

        tapElement(option)
        assertValue(of: control, equals: "space")
    }

    func testSettingsLanguageDropdownUsesLiveIntrinsicWidth() throws {
        let app = makeApp(additionalArguments: hotkeyEffectArguments(resetDefaults: true))
        launchFlowTabUITestApplication(app)
        openSettingsTab(in: app)

        let language = element(in: app, identifier: Identifier.settingsAppearanceAppLanguage)
        XCTAssertTrue(language.waitForExistence(timeout: 6))
        XCTAssertGreaterThanOrEqual(language.frame.width, 100)
        XCTAssertLessThan(language.frame.width, 120)
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
                    "presentationRecovery trigger=global_show action=trackInitialVisibility",
                    "HotKey Forward"
                ],
                since: logSnapshot
            )
            app.terminate()
        }
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

            let diagnosticsSummary = element(in: app, identifier: Identifier.switcherSummary)
            XCTAssertTrue(diagnosticsSummary.waitForExistence(timeout: 8))
            let browserTile = element(in: app, identifier: Identifier.switcherAppMockBrowser)
            XCTAssertTrue(browserTile.waitForExistence(timeout: 8))
            let selectedAppID = switcherPanelDiagnosticsValue(diagnosticsSummary, key: "selected")
            XCTAssertFalse(selectedAppID.isEmpty)
            let selectedTile = element(
                in: app,
                identifier: "flowtab.switcher.app.\(selectedAppID.flowTabUITestAccessibilityIdentifierComponent)"
            )
            XCTAssertTrue(selectedTile.waitForExistence(timeout: 8))

            let logSnapshot = makeRuntimeLogFileSnapshot()
            typeHotkey(in: app, key: item.triggerKey, modifier: "option")
            waitForRuntimeLogFiles(
                containing: [
                    "mock terminate request appID=\(selectedAppID)",
                    "terminate request app=",
                    "appID=\(selectedAppID) sent=true",
                    "terminate post-refresh reason=workspace_notification appID=\(selectedAppID)"
                ],
                since: logSnapshot,
                timeout: 10
            )
            XCTAssertTrue(waitForNonExistence(selectedTile, timeout: 6))
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
                    "presentationRecovery trigger=in_app_show action=trackInitialVisibility",
                    "InApp Window Forward"
                ],
                since: logSnapshot
            )
            app.terminate()
        }
    }

    func hotkeyEffectArguments(resetDefaults: Bool = false) -> [String] {
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

    private func assertSettingsPageSubtitleIsVisible(
        _ subtitle: XCUIElement,
        below title: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(title.exists, file: file, line: line)
        XCTAssertFalse(subtitle.frame.isEmpty, file: file, line: line)
        XCTAssertGreaterThan(subtitle.frame.width, 80, file: file, line: line)
        XCTAssertGreaterThan(subtitle.frame.height, 8, file: file, line: line)
        XCTAssertGreaterThan(subtitle.frame.minY, title.frame.maxY, file: file, line: line)
    }

}
