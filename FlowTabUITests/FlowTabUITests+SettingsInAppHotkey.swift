import XCTest

extension FlowTabUITests {
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
}
