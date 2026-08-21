import XCTest

extension FlowTabUITests {
    func testSettingsHotkeyConflictsShowWarningAndKeepCurrentSelections() throws {
        let app = makeApp(
            additionalArguments: hotkeyEffectArguments(resetDefaults: true)
        )
        defer { app.terminate() }
        launchFlowTabUITestApplication(app)
        openSettingsTab(in: app)

        recordShortcut(
            in: app,
            FlowTabUITestShortcutRecording.key(
                controlIdentifier: Identifier.settingsHotkeyQuitKey,
                key: "z",
                expectedValue: "Z"
            )
        )
        enterShortcut(
            in: app,
            controlIdentifier: Identifier.settingsHotkeyQuitKey,
            key: "tab",
            modifierFlags: []
        )

        assertValue(
            of: element(
                in: app,
                identifier: Identifier.settingsHotkeyQuitKey
            ),
            equals: "Z"
        )
        assertHotkeyConflictVisible(
            in: app,
            controlIdentifier: Identifier.settingsHotkeyQuitKey
        )

        recordShortcut(
            in: app,
            FlowTabUITestShortcutRecording.key(
                controlIdentifier: Identifier.settingsHotkeyMainKey,
                key: "space",
                expectedValue: "Space"
            )
        )
        recordShortcut(
            in: app,
            .key(
                controlIdentifier: Identifier.settingsHotkeyInAppMainKeys,
                key: "b",
                expectedValue: "B"
            )
        )
        recordShortcut(
            in: app,
            .modifiers(
                controlIdentifier: Identifier.settingsHotkeyInAppBaseKeys,
                modifierFlags: .option,
                expectedValue: "Option"
            )
        )
        enterShortcut(
            in: app,
            controlIdentifier: Identifier.settingsHotkeyMainKey,
            key: "b",
            modifierFlags: []
        )

        assertValue(
            of: element(
                in: app,
                identifier: Identifier.settingsHotkeyMainKey
            ),
            equals: "Space"
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

        recordShortcut(
            in: app,
            .key(
                controlIdentifier: Identifier.settingsHotkeyInAppMainKeys,
                key: "q",
                expectedValue: "Q"
            )
        )
        recordShortcut(
            in: app,
            .modifiers(
                controlIdentifier: Identifier.settingsHotkeyInAppBaseKeys,
                modifierFlags: .command,
                expectedValue: "Command"
            )
        )
        enterModifiers(
            in: app,
            controlIdentifier: Identifier.settingsHotkeyInAppBaseKeys,
            modifierFlags: .option
        )

        assertValue(
            of: element(
                in: app,
                identifier: Identifier.settingsHotkeyInAppBaseKeys
            ),
            equals: "Command"
        )
        assertHotkeyConflictVisible(
            in: app,
            controlIdentifier: Identifier.settingsHotkeyInAppBaseKeys
        )
    }

    func testSettingsHotkeyConflictFeedbackDismissesAfterOtherClick() throws {
        let app = makeApp(
            additionalArguments: hotkeyEffectArguments(resetDefaults: true)
        )
        defer { app.terminate() }
        launchFlowTabUITestApplication(app)
        openSettingsTab(in: app)

        recordShortcut(
            in: app,
            FlowTabUITestShortcutRecording.key(
                controlIdentifier: Identifier.settingsHotkeyQuitKey,
                key: "z",
                expectedValue: "Z"
            )
        )
        enterShortcut(
            in: app,
            controlIdentifier: Identifier.settingsHotkeyQuitKey,
            key: "tab",
            modifierFlags: []
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
            of: element(
                in: app,
                identifier: Identifier.settingsHotkeyQuitKey
            ),
            equals: "Z"
        )
    }

    func testSettingsInAppHotkeyExplicitMatrixStartsFocusedWindowSession() throws {
        let cases: [(
            recordings: [FlowTabUITestShortcutRecording],
            triggerModifier: String,
            triggerKey: String,
            expectedInAppShortcut: String
        )] = [
            (
                hotkeyRecordings(
                    mainModifiers: .option,
                    mainModifiersText: "Option",
                    mainKey: "space",
                    quitKey: "z",
                    inAppBaseKeys: .option,
                    inAppBaseKeysText: "Option",
                    inAppMainKey: "b"
                ),
                "option",
                "b",
                "Option + B"
            ),
            (
                hotkeyRecordings(
                    mainModifiers: .option,
                    mainModifiersText: "Option",
                    mainKey: "b",
                    quitKey: "z",
                    inAppBaseKeys: .control,
                    inAppBaseKeysText: "Control",
                    inAppMainKey: "b"
                ),
                "control",
                "b",
                "Control + B"
            )
        ]
        let targetAppID = FlowTabUITestAppIdentity
            .configured()
            .bundleIdentifier

        for item in cases {
            configureShortcutsThroughSettings(
                recordings: item.recordings,
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
