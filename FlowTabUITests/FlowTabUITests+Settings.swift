import AppKit
import XCTest

enum FlowTabUITestSettingsQuitHotkeyWatchdogPolicy {
    static let runtimeCompletion: TimeInterval = 10
    static let selectedRowDisappearance: TimeInterval = 6
}

extension FlowTabUITests {
    func testSettingsQuitHotkeyWatchdogPolicyPreservesCompatibleRuntimeCompletionBound() {
        XCTAssertEqual(
            FlowTabUITestSettingsQuitHotkeyWatchdogPolicy
                .runtimeCompletion,
            10
        )
        XCTAssertTrue(
            FlowTabUITestSettingsQuitHotkeyWatchdogPolicy
                .runtimeCompletion.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSettingsQuitHotkeyWatchdogPolicy
                .runtimeCompletion,
            0
        )
    }

    func testSettingsQuitHotkeyWatchdogPolicyPreservesCompatibleSelectedRowDisappearanceBound() {
        XCTAssertEqual(
            FlowTabUITestSettingsQuitHotkeyWatchdogPolicy
                .selectedRowDisappearance,
            6
        )
        XCTAssertTrue(
            FlowTabUITestSettingsQuitHotkeyWatchdogPolicy
                .selectedRowDisappearance.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSettingsQuitHotkeyWatchdogPolicy
                .selectedRowDisappearance,
            0
        )
    }

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
        try assertInitialSwitcherPresentationResolution(
            additionalArguments: windowBehaviorRuntimeArguments(
                resetDefaults: true,
                opensSwitcher: true
            ),
            expectation:
                FlowTabUITestInitialPresentationResolutionExpectation(
                    requiredItemIDs: [
                        "com.flowtab.mock.mail",
                        "com.flowtab.mock.minimized-notes"
                    ],
                    excludedItemIDs: [],
                    searchFeatureEnabled: true,
                    searchIsActive: false,
                    searchActivationIsPending: false
                ),
            targetDescription: "hide-minimized baseline"
        )
    }

    func testSettingsWindowBehaviorHideMinimizedAppsAffectsSwitcherAppLayer() throws {
        let settingsApp = makeApp(
            additionalArguments: windowBehaviorRuntimeArguments(
                resetDefaults: true
            )
        )
        defer { settingsApp.terminate() }
        launchFlowTabUITestApplication(settingsApp)
        guard
            assertSettingsWindowBehaviorHideMinimizedAppsCanBeSet(
                in: settingsApp,
                to: true,
                targetDescription: "filtered Switcher setup"
            )
        else {
            return
        }
        settingsApp.terminate()

        try assertInitialSwitcherPresentationResolution(
            additionalArguments:
                windowBehaviorRuntimeArguments(opensSwitcher: true),
            expectation:
                FlowTabUITestInitialPresentationResolutionExpectation(
                    requiredItemIDs: ["com.flowtab.mock.mail"],
                    excludedItemIDs: [
                        "com.flowtab.mock.minimized-notes"
                    ],
                    searchFeatureEnabled: true,
                    searchIsActive: false,
                    searchActivationIsPending: false
                ),
            targetDescription: "hide-minimized filtered projection"
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

            let logSnapshot = makeRuntimeLogFileSnapshot()
            let app = makeApp(additionalArguments: hotkeyEffectArguments())
            launchFlowTabUITestApplication(app)
            waitForRuntimeLogFiles(
                containing: [
                    "register ok signature=1179926850 id=1",
                    "register ok signature=1179926850 id=2",
                    "register main=\(item.shortcutText) backward=",
                    "registration evidence generation=1"
                ],
                since: logSnapshot
            )
            XCTAssertTrue(
                waitForFlowTabUITestApplicationToBecomeReady(
                    app,
                    timeout:
                        FlowTabUITestSupportWatchdogPolicy
                            .foregroundActivation,
                    traceLabel:
                        "settings.mainHotkey.\(item.modifier).\(item.key).inputReadiness"
                ),
                "Expected foreground input readiness for \(item.shortcutText); "
                    + "finalState=\(String(describing: app.state))"
            )

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

            guard let launch = try
                launchFlowTabUITestApplicationResolvingInitialPresentation(
                    additionalArguments:
                        hotkeyEffectArguments() + [
                            "--flowtab-ui-open-switcher"
                        ],
                    expectation:
                        FlowTabUITestInitialPresentationResolutionExpectation(
                            requiredItemIDs: [
                                "com.flowtab.mock.browser"
                            ],
                            excludedItemIDs: [],
                            searchFeatureEnabled: true,
                            searchIsActive: false,
                            searchActivationIsPending: false
                        ),
                    targetDescription:
                        "settings quit hotkey "
                            + item.expectedQuitShortcut
                )
            else {
                continue
            }
            let app = launch.application
            defer { app.terminate() }
            let selectedAppID = launch.resolution.selectedAppID
            let selectedRowIdentifier =
                switcherAppRowIdentifier(selectedAppID)
            let selectedTile = element(
                in: app,
                identifier: selectedRowIdentifier
            )
            let disappearanceOwner =
                FlowTabUITestElementNonExistenceObservationOwner(
                    elementIdentifier: selectedRowIdentifier,
                    readback: { selectedTile.exists }
                )
            disappearanceOwner.start()
            defer { disappearanceOwner.cancel() }

            let completionBaseline = makeRuntimeLogFileSnapshot()
            defer { completionBaseline.cancel() }
            typeHotkey(
                in: app,
                key: item.triggerKey,
                modifier: "option"
            )
            disappearanceOwner.markTriggerCompleted()
            waitForRuntimeLogFiles(
                containing: [
                    "mock terminate request appID=\(selectedAppID)",
                    "terminate request app=",
                    "appID=\(selectedAppID) sent=true",
                    "terminate post-refresh reason=workspace_notification appID=\(selectedAppID)"
                ],
                since: completionBaseline,
                timeout:
                    FlowTabUITestSettingsQuitHotkeyWatchdogPolicy
                        .runtimeCompletion
            )
            completionBaseline.cancel()
            guard
                let disappearanceEvidence =
                    disappearanceOwner.waitForResolution(
                        timeout:
                            FlowTabUITestSettingsQuitHotkeyWatchdogPolicy
                                .selectedRowDisappearance
                    )
            else {
                XCTFail(
                    "Selected App row disappearance watchdog expired. "
                        + "selectedAppID=\(selectedAppID) "
                        + disappearanceOwner.diagnosticSummary
                )
                continue
            }
            XCTAssertFalse(disappearanceEvidence.value.exists)
            disappearanceOwner.cancel()
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
            "--flowtab-ui-mock-window-previews",
            "--flowtab-ui-ax-trusted",
            "YES",
            "--flowtab-ui-screen-trusted",
            "YES"
        ]
        return arguments
    }

    func windowBehaviorRuntimeArguments(
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
            "--flowtab-ui-mock-window-previews",
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

    func configureHotkeysThroughSettings(
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

    func typeHotkey(in app: XCUIApplication, key: String, modifier: String) {
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
