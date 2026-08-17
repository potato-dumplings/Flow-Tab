import XCTest

extension FlowTabUITests {
    func testSettingsHotkeyConflictsShowWarningAndKeepCurrentSelections() throws {
        let app = makeApp(
            additionalArguments: hotkeyEffectArguments(resetDefaults: true)
        )
        defer { app.terminate() }
        launchFlowTabUITestApplication(app)
        openSettingsTab(in: app)

        selectOption(
            in: app,
            controlIdentifier: Identifier.settingsHotkeyQuitKey,
            optionIdentifier: "z"
        )
        assertValue(
            of: element(
                in: app,
                identifier: Identifier.settingsHotkeyQuitKey
            ),
            equals: "z"
        )

        selectOption(
            in: app,
            controlIdentifier: Identifier.settingsHotkeyQuitKey,
            optionIdentifier: "tab"
        )

        assertValue(
            of: element(
                in: app,
                identifier: Identifier.settingsHotkeyQuitKey
            ),
            equals: "z"
        )
        assertHotkeyConflictVisible(
            in: app,
            controlIdentifier: Identifier.settingsHotkeyQuitKey
        )

        selectOption(
            in: app,
            controlIdentifier: Identifier.settingsHotkeyMainKey,
            optionIdentifier: "space"
        )
        assertValue(
            of: element(
                in: app,
                identifier: Identifier.settingsHotkeyMainKey
            ),
            equals: "space"
        )
        selectOption(
            in: app,
            controlIdentifier: Identifier.settingsHotkeyInAppKey,
            optionIdentifier: "b"
        )
        selectOption(
            in: app,
            controlIdentifier: Identifier.settingsHotkeyInAppModifier,
            optionIdentifier: "option"
        )
        selectOption(
            in: app,
            controlIdentifier: Identifier.settingsHotkeyMainKey,
            optionIdentifier: "b"
        )

        assertValue(
            of: element(in: app, identifier: Identifier.settingsHotkeyMainKey),
            equals: "space"
        )
        assertHotkeyConflictVisible(
            in: app,
            controlIdentifier: Identifier.settingsHotkeyMainKey
        )
    }

    func testSettingsInAppHotkeyConflictWithQuitShowsWarningAndKeepsCurrentSelection() throws {
        let app = makeApp(
            additionalArguments: hotkeyEffectArguments(resetDefaults: true)
        )
        defer { app.terminate() }
        launchFlowTabUITestApplication(app)
        openSettingsTab(in: app)

        selectOption(
            in: app,
            controlIdentifier: Identifier.settingsHotkeyInAppKey,
            optionIdentifier: "q"
        )
        selectOption(
            in: app,
            controlIdentifier: Identifier.settingsHotkeyInAppModifier,
            optionIdentifier: "command"
        )
        assertValue(
            of: element(
                in: app,
                identifier: Identifier.settingsHotkeyInAppModifier
            ),
            equals: "command"
        )
        selectOption(
            in: app,
            controlIdentifier: Identifier.settingsHotkeyInAppModifier,
            optionIdentifier: "option"
        )

        assertValue(
            of: element(
                in: app,
                identifier: Identifier.settingsHotkeyInAppModifier
            ),
            equals: "command"
        )
        assertValue(
            of: element(
                in: app,
                identifier: Identifier.settingsHotkeyInAppKey
            ),
            equals: "q"
        )
        assertHotkeyConflictVisible(
            in: app,
            controlIdentifier: Identifier.settingsHotkeyInAppModifier
        )
    }

    func testSettingsHotkeyConflictFeedbackDismissesAfterOtherClick() throws {
        let app = makeApp(
            additionalArguments: hotkeyEffectArguments(resetDefaults: true)
        )
        defer { app.terminate() }
        launchFlowTabUITestApplication(app)
        openSettingsTab(in: app)

        selectOption(
            in: app,
            controlIdentifier: Identifier.settingsHotkeyQuitKey,
            optionIdentifier: "z"
        )
        selectOption(
            in: app,
            controlIdentifier: Identifier.settingsHotkeyQuitKey,
            optionIdentifier: "tab"
        )

        let conflictStatus = element(
            in: app,
            identifier: Identifier.settingsHotkeyConflictStatus(
                for: Identifier.settingsHotkeyQuitKey
            )
        )
        XCTAssertTrue(conflictStatus.waitForExistence(timeout: 5))
        let shortcutHintToggle = element(
            in: app,
            identifier: Identifier.settingsAppearanceShowShortcutHint
        )
        assertElementDoesNotExistAfterTrigger(
            conflictStatus,
            timeout: 5,
            description: "Hotkey conflict feedback click-away dismissal",
            trigger: { tapElement(shortcutHintToggle) }
        )
        assertValue(
            of: element(in: app, identifier: Identifier.settingsHotkeyQuitKey),
            equals: "z"
        )
    }

    func testSettingsInAppHotkeyExplicitMatrixStartsFocusedWindowSession() throws {
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
                    (Identifier.settingsHotkeyInAppModifier, "control"),
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
        let targetAppID = FlowTabUITestAppIdentity
            .configured()
            .bundleIdentifier

        for item in cases {
            configureHotkeysThroughSettings(
                rawSelections: item.rawSelections,
                expectedValues: item.expectedValues,
                expectedLogMarkers: [
                    "inApp=\(item.expectedInAppShortcut)",
                    "hotkeyReloadNotification sender=AppDelegate"
                ]
            )

            let registrationBaseline = makeRuntimeLogFileSnapshot()
            defer { registrationBaseline.cancel() }
            let app = makeApp(
                additionalArguments: hotkeyEffectArguments() + [
                    "--flowtab-ui-mock-runtime-variant",
                    "focused-current-app"
                ]
            )
            defer { app.terminate() }
            launchFlowTabUITestApplication(app)
            waitForRuntimeLogFiles(
                containing: [
                    "hotkeyInputSource route=inAppWindowSwitcher action=register",
                    "register ok signature=1179932494 id=101",
                    "register ok signature=1179932494 id=102",
                    "register in-app main=\(item.expectedInAppShortcut) backward=",
                    "registration evidence generation=1"
                ],
                since: registrationBaseline
            )
            registrationBaseline.cancel()

            app.activate()
            XCTAssertTrue(
                waitForFlowTabUITestApplicationToBecomeReady(
                    app,
                    timeout:
                        FlowTabUITestSupportWatchdogPolicy
                            .foregroundActivation,
                    traceLabel:
                        "settings.inAppHotkey."
                        + "\(item.triggerModifier)."
                        + "\(item.triggerKey).inputReadiness"
                ),
                "Expected foreground input readiness for "
                    + "\(item.expectedInAppShortcut); "
                    + "finalState=\(String(describing: app.state))"
            )

            let inputBaseline = makeRuntimeLogFileSnapshot()
            defer { inputBaseline.cancel() }
            typeHotkey(
                in: app,
                key: item.triggerKey,
                modifier: item.triggerModifier
            )
            waitForRuntimeLogFiles(
                containing: [
                    "hotkeyInput route=inAppWindowSwitcher phase=pressed action=accepted",
                    "inAppHotkeyPressed dir=forward panelVisible=0 action=show",
                    "startFocusedWindowSession result=ready appID=\(targetAppID) windows=2",
                    "show kind=inApp action=initialAdvance key=tabForward",
                    "presentationRecovery trigger=in_app_show action=trackInitialVisibility",
                    "show kind=inApp result=presented",
                    "InApp Window Forward"
                ],
                since: inputBaseline
            )
            inputBaseline.cancel()
        }
    }

    private func assertHotkeyConflictVisible(
        in app: XCUIApplication,
        controlIdentifier: String
    ) {
        let conflictText = "已被使用"
        let conflictIdentifier = Identifier.settingsHotkeyConflictStatus(
            for: controlIdentifier
        )
        let conflictStatus = app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier == %@ AND (label CONTAINS %@ OR value CONTAINS %@)",
                    conflictIdentifier,
                    conflictText,
                    conflictText
                )
            )
            .firstMatch

        XCTAssertTrue(
            conflictStatus.waitForExistence(timeout: 5),
            "Expected field-level hotkey conflict feedback to be visible"
        )
    }
}
