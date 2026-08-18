import Carbon
import CoreGraphics
import XCTest

extension FlowTabUITests {
    func testOptionWTabGlobalChordCanOpenMainSwitcherRepeatedly() throws {
        let app = makeApp(
            additionalArguments: hotkeyEffectArguments(
                resetDefaults: true,
                usesSystemAccessibilityPermission: true
            ) + [
                "--flowtab-ui-enable-shortcut-event-injection"
            ]
        )
        launchFlowTabUITestApplication(app)
        defer { app.terminate() }
        openSettingsTab(in: app)

        let registrationLogSnapshot = makeRuntimeLogFileSnapshot()
        recordShortcut(
            in: app,
            .keySet(
                controlIdentifier: Identifier.settingsHotkeyMainModifiers,
                keyCodes: [CGKeyCode(kVK_ANSI_W)],
                modifierFlags: .option,
                expectedValue: "Option + W"
            )
        )
        waitForRuntimeLogFiles(
            containing: [
                "updated main=Option + W + Tab",
                "chord event monitor active mode=accessibility "
                    + "forward=Option + W + Tab",
                "chord event monitor active mode=accessibility "
                    + "forward=Control + Tab"
            ],
            since: registrationLogSnapshot
        )

        let triggerLogSnapshot = makeRuntimeLogFileSnapshot()
        app.activate()
        let firstReleaseLogSnapshot = makeRuntimeLogFileSnapshot()
        injectRuntimeKeySet(
            in: app,
            keyCodes: [
                CGKeyCode(kVK_ANSI_W),
                CGKeyCode(kVK_Tab)
            ],
            modifierFlags: .option,
            phase: "press"
        )

        waitForRuntimeLogFiles(
            containing: [
                "dispatch chord phase=pressed dir=forward",
                "hotkeyPressed dir=forward panelVisible=0 action=show",
                "show kind=global result=presented",
                "HotKey Forward"
            ],
            since: triggerLogSnapshot
        )

        injectRuntimeKeySet(
            in: app,
            keyCodes: [
                CGKeyCode(kVK_ANSI_W),
                CGKeyCode(kVK_Tab)
            ],
            modifierFlags: .option,
            phase: "release"
        )
        waitForRuntimeLogFiles(
            containing: [
                "dispatch chord phase=released dir=forward",
                "HotKey Forward Released",
                "releaseConfirm confirmed",
                "hotkeyReplaySuppression end "
                    + "trigger=selection_end:finishSelection"
            ],
            since: firstReleaseLogSnapshot
        )

        let secondTriggerLogSnapshot = makeRuntimeLogFileSnapshot()
        app.activate()
        injectRuntimeKeySet(
            in: app,
            keyCodes: [
                CGKeyCode(kVK_ANSI_W),
                CGKeyCode(kVK_Tab)
            ],
            modifierFlags: .option,
            phase: "press"
        )
        waitForRuntimeLogFiles(
            containing: [
                "dispatch chord phase=pressed dir=forward",
                "hotkeyPressed dir=forward panelVisible=0 action=show",
                "show kind=global result=presented",
                "HotKey Forward"
            ],
            since: secondTriggerLogSnapshot
        )

        let secondReleaseLogSnapshot = makeRuntimeLogFileSnapshot()
        injectRuntimeKeySet(
            in: app,
            keyCodes: [
                CGKeyCode(kVK_ANSI_W),
                CGKeyCode(kVK_Tab)
            ],
            modifierFlags: .option,
            phase: "release"
        )
        waitForRuntimeLogFiles(
            containing: [
                "dispatch chord phase=released dir=forward",
                "hotkeyReplaySuppression end "
                    + "trigger=selection_end:finishSelection"
            ],
            since: secondReleaseLogSnapshot
        )
    }

    func testSettingsRecordsAndPersistsArbitraryMultiKeySets() throws {
        let app = makeApp(
            additionalArguments: hotkeyEffectArguments(resetDefaults: true) + [
                "--flowtab-ui-enable-shortcut-event-injection"
            ]
        )
        launchFlowTabUITestApplication(app)
        openSettingsTab(in: app)

        let recordings: [FlowTabUITestShortcutRecording] = [
            .keySet(
                controlIdentifier: Identifier.settingsHotkeyMainKey,
                keyCodes: [
                    CGKeyCode(kVK_ANSI_A),
                    CGKeyCode(kVK_ANSI_7),
                    CGKeyCode(kVK_F6),
                    CGKeyCode(kVK_F8)
                ],
                expectedValue: "A + 7 + F6 + F8"
            ),
            .keySet(
                controlIdentifier: Identifier.settingsHotkeyMainModifiers,
                keyCodes: [
                    CGKeyCode(kVK_ANSI_D),
                    CGKeyCode(kVK_ANSI_E)
                ],
                modifierFlags: [.command, .option],
                expectedValue: "Command + Option + D + E"
            ),
            .modifiers(
                controlIdentifier: Identifier.settingsHotkeyQuitKey,
                modifierFlags: .control,
                expectedValue: "Control"
            )
        ]
        for recording in recordings {
            recordShortcut(in: app, recording)
        }
        app.terminate()

        let relaunchedApp = makeApp(
            additionalArguments: hotkeyEffectArguments()
        )
        defer { relaunchedApp.terminate() }
        launchFlowTabUITestApplication(relaunchedApp)
        openSettingsTab(in: relaunchedApp)
        for recording in recordings {
            assertValue(
                of: element(
                    in: relaunchedApp,
                    identifier: recording.controlIdentifier
                ),
                equals: recording.expectedValue
            )
        }
    }

    func testSettingsInAppShortcutRecordsControlTab() throws {
        let app = makeApp(
            additionalArguments: hotkeyEffectArguments(resetDefaults: true)
        )
        launchFlowTabUITestApplication(app)
        defer { app.terminate() }
        openSettingsTab(in: app)

        recordShortcut(
            in: app,
            FlowTabUITestShortcutRecording(
                controlIdentifier: Identifier.settingsHotkeyInAppShortcut,
                key: "b",
                modifierFlags: .option,
                expectedValue: "Option + B"
            )
        )
        recordShortcut(
            in: app,
            FlowTabUITestShortcutRecording(
                controlIdentifier: Identifier.settingsHotkeyInAppShortcut,
                key: "tab",
                modifierFlags: .control,
                expectedValue: "Control + Tab"
            )
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

        let expectedRecordings = hotkeyRecordings(
            mainModifiers: .option,
            mainModifiersText: "Option",
            mainKey: "space",
            quitKey: "z",
            inAppModifiers: .command,
            inAppShortcutText: "Command + A",
            inAppKey: "a"
        )
        let baselineRecordings = hotkeyRecordings(
            mainModifiers: .control,
            mainModifiersText: "Control",
            mainKey: "x",
            quitKey: "y",
            inAppModifiers: .option,
            inAppShortcutText: "Option + B",
            inAppKey: "b"
        )
        for recording in baselineRecordings {
            recordShortcut(in: firstLaunchApp, recording)
        }
        let hotkeyReloadLogSnapshot = makeRuntimeLogFileSnapshot()
        for recording in expectedRecordings {
            recordShortcut(in: firstLaunchApp, recording)
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

        for recording in expectedRecordings {
            assertValue(
                of: element(
                    in: relaunchApp,
                    identifier: recording.controlIdentifier
                ),
                equals: recording.expectedValue
            )
        }
    }

    func testSettingsHotkeySixDefaultsRejectOverlappingModifierComponents() throws {
        let app = makeApp(
            additionalArguments: hotkeyEffectArguments(resetDefaults: true)
        )
        launchFlowTabUITestApplication(app)
        defer { app.terminate() }
        openSettingsTab(in: app)

        let defaults = hotkeyRecordings(
            mainModifiers: .option,
            mainModifiersText: "Option",
            mainKey: "tab",
            quitKey: "q",
            inAppModifiers: .control,
            inAppShortcutText: "Control + Tab",
            inAppKey: "tab"
        )
        for recording in defaults {
            assertValue(
                of: element(
                    in: app,
                    identifier: recording.controlIdentifier
                ),
                equals: recording.expectedValue
            )
        }

        enterModifiers(
            in: app,
            controlIdentifier: Identifier.settingsHotkeyMainModifiers,
            modifierFlags: [.option, .shift]
        )

        assertValue(
            of: element(in: app, identifier: Identifier.settingsHotkeyMainModifiers),
            equals: "Option"
        )
        let conflictStatus = element(
            in: app,
            identifier: Identifier.settingsHotkeyConflictStatus(
                for: Identifier.settingsHotkeyMainModifiers
            )
        )
        XCTAssertTrue(conflictStatus.waitForExistence(timeout: 5))

        enterShortcut(
            in: app,
            controlIdentifier: Identifier.settingsHotkeyInAppShortcut,
            key: "b",
            modifierFlags: [.control, .shift]
        )

        assertValue(
            of: element(
                in: app,
                identifier: Identifier.settingsHotkeyInAppShortcut
            ),
            equals: "Control + Tab"
        )
        let inAppConflictStatus = element(
            in: app,
            identifier: Identifier.settingsHotkeyConflictStatus(
                for: Identifier.settingsHotkeyInAppShortcut
            )
        )
        XCTAssertTrue(inAppConflictStatus.waitForExistence(timeout: 5))
    }
}
