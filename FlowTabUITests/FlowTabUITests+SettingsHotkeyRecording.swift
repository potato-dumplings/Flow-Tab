import Carbon
import CoreGraphics
import XCTest

extension FlowTabUITests {
    func testSettingsShortcutRecorderTransfersAndDismissesAfterOutsideClick() throws {
        let app = makeApp(
            additionalArguments: hotkeyEffectArguments(resetDefaults: true)
        )
        launchFlowTabUITestApplication(app)
        defer { app.terminate() }
        openSettingsTab(in: app)

        let mainModifiers = element(
            in: app,
            identifier: Identifier.settingsHotkeyMainModifiers
        )
        let mainKey = element(
            in: app,
            identifier: Identifier.settingsHotkeyMainKey
        )
        let settingsContent = element(
            in: app,
            identifier: Identifier.settingsTabContent
        )
        XCTAssertTrue(mainModifiers.waitForExistence(timeout: 5))
        XCTAssertTrue(mainKey.waitForExistence(timeout: 5))
        XCTAssertTrue(settingsContent.waitForExistence(timeout: 5))
        assertValue(of: mainModifiers, equals: "Option")
        assertValue(of: mainKey, equals: "Tab")

        assertTriggerMakesValue(
            of: mainModifiers,
            equals: "请按下快捷键",
            trigger: { self.tapElement(mainModifiers) }
        )
        assertTriggerMakesValue(
            of: mainModifiers,
            equals: "Option",
            trigger: { self.tapElement(mainKey) }
        )
        assertValue(of: mainKey, equals: "请按下快捷键")
        assertTriggerMakesValue(
            of: mainKey,
            equals: "Tab",
            trigger: {
                settingsContent.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.98, dy: 0.98)
                ).tap()
            }
        )
    }

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

        let baseKeyCodes = [CGKeyCode(kVK_ANSI_W)]
        let completeChordKeyCodes = baseKeyCodes + [CGKeyCode(kVK_Tab)]
        defer {
            setRuntimePressedKeySet(
                in: app,
                keyCodes: [],
                modifierFlags: []
            )
        }

        let triggerLogSnapshot = makeRuntimeLogFileSnapshot()
        app.activate()
        setRuntimePressedKeySet(
            in: app,
            keyCodes: completeChordKeyCodes,
            modifierFlags: .option
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

        let firstMainKeyReleaseLogSnapshot =
            makeRuntimeLogFileSnapshot()
        setRuntimePressedKeySet(
            in: app,
            keyCodes: baseKeyCodes,
            modifierFlags: .option
        )
        waitForRuntimeLogFiles(
            containing: [
                "dispatch chord phase=released dir=forward",
                "HotKey Forward Released"
            ],
            since: firstMainKeyReleaseLogSnapshot
        )

        let repeatedAdvanceLogSnapshot = makeRuntimeLogFileSnapshot()
        setRuntimePressedKeySet(
            in: app,
            keyCodes: completeChordKeyCodes,
            modifierFlags: .option
        )
        waitForRuntimeLogFiles(
            containing: [
                "dispatch chord phase=pressed dir=forward",
                "hotkeyPressed dir=forward panelVisible=1 "
                    + "modifierPressed=1 action=advance",
                "HotKey Forward"
            ],
            since: repeatedAdvanceLogSnapshot
        )

        let secondMainKeyReleaseLogSnapshot =
            makeRuntimeLogFileSnapshot()
        setRuntimePressedKeySet(
            in: app,
            keyCodes: baseKeyCodes,
            modifierFlags: .option
        )
        waitForRuntimeLogFiles(
            containing: [
                "dispatch chord phase=released dir=forward",
                "HotKey Forward Released"
            ],
            since: secondMainKeyReleaseLogSnapshot
        )

        let baseKeyReleaseLogSnapshot = makeRuntimeLogFileSnapshot()
        setRuntimePressedKeySet(
            in: app,
            keyCodes: [],
            modifierFlags: .option
        )
        waitForRuntimeLogFiles(
            containing: [
                "dispatch chord phase=released dir=forward",
                "hotkeyReleased panelVisible=1 "
                    + "action=scheduleReleaseConfirm",
                "releaseConfirm confirmed trigger=hotkey_released "
                    + "action=finishSelection"
            ],
            since: baseKeyReleaseLogSnapshot
        )
        setRuntimePressedKeySet(
            in: app,
            keyCodes: [],
            modifierFlags: []
        )
        waitForRuntimeLogFiles(
            containing: [
                "hotkeyReplaySuppression end "
                    + "trigger=selection_end:finishSelection"
            ],
            since: baseKeyReleaseLogSnapshot
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

    func testSettingsRejectsArbitraryMainHotkeyWithoutAccessibility() throws {
        let app = makeApp(
            additionalArguments: hotkeyEffectArguments(
                resetDefaults: true,
                accessibilityTrusted: false
            ) + [
                "--flowtab-ui-enable-shortcut-event-injection"
            ]
        )
        launchFlowTabUITestApplication(app)
        defer { app.terminate() }
        openSettingsTab(in: app)

        enterKeySet(
            in: app,
            controlIdentifier: Identifier.settingsHotkeyMainModifiers,
            keyCodes: [CGKeyCode(kVK_ANSI_W)],
            modifierFlags: .control
        )

        assertValue(
            of: element(
                in: app,
                identifier: Identifier.settingsHotkeyMainModifiers
            ),
            equals: "Option"
        )
        assertHotkeyStatus(
            in: app,
            identifier: Identifier.settingsHotkeyConflictStatus(
                for: Identifier.settingsHotkeyMainModifiers
            ),
            text: "未授权时仅支持修饰键"
        )
    }

    func testSettingsRetainsArbitraryMainHotkeyWhenAccessibilityIsUnavailable() throws {
        let trustedApp = makeApp(
            additionalArguments: hotkeyEffectArguments(
                resetDefaults: true
            ) + [
                "--flowtab-ui-enable-shortcut-event-injection"
            ]
        )
        launchFlowTabUITestApplication(trustedApp)
        openSettingsTab(in: trustedApp)
        recordShortcut(
            in: trustedApp,
            .keySet(
                controlIdentifier: Identifier.settingsHotkeyMainModifiers,
                keyCodes: [CGKeyCode(kVK_ANSI_W)],
                modifierFlags: .control,
                expectedValue: "Control + W"
            )
        )
        trustedApp.terminate()

        let deniedApp = makeApp(
            additionalArguments: hotkeyEffectArguments(
                accessibilityTrusted: false
            )
        )
        launchFlowTabUITestApplication(deniedApp)
        defer { deniedApp.terminate() }
        openSettingsTab(in: deniedApp)

        assertValue(
            of: element(
                in: deniedApp,
                identifier: Identifier.settingsHotkeyMainModifiers
            ),
            equals: "Control + W"
        )
        assertHotkeyStatus(
            in: deniedApp,
            identifier: Identifier.settingsHotkeyConflictStatus(
                for: Identifier.settingsHotkeyMainModifiers
            ),
            text: "未授权时仅支持修饰键"
        )
        XCTAssertFalse(
            element(
                in: deniedApp,
                identifier:
                    "flowtab.settings.hotkey.main-accessibility-status"
            ).exists
        )
    }

    func testSettingsRepairsDeniedArbitraryHotkeysFieldByField() throws {
        let trustedApp = makeApp(
            additionalArguments: hotkeyEffectArguments(
                resetDefaults: true
            ) + [
                "--flowtab-ui-enable-shortcut-event-injection"
            ]
        )
        launchFlowTabUITestApplication(trustedApp)
        openSettingsTab(in: trustedApp)
        for recording in [
            FlowTabUITestShortcutRecording.keySet(
                controlIdentifier: Identifier.settingsHotkeyMainModifiers,
                keyCodes: [CGKeyCode(kVK_ANSI_W)],
                modifierFlags: .option,
                expectedValue: "Option + W"
            ),
            .keySet(
                controlIdentifier:
                    Identifier.settingsHotkeyMainReverseModifiers,
                keyCodes: [CGKeyCode(kVK_ANSI_C)],
                modifierFlags: .shift,
                expectedValue: "Shift + C"
            ),
            .keySet(
                controlIdentifier: Identifier.settingsHotkeyMainKey,
                keyCodes: [
                    CGKeyCode(kVK_ANSI_E),
                    CGKeyCode(kVK_Tab)
                ],
                expectedValue: "E + Tab"
            ),
            .keySet(
                controlIdentifier: Identifier.settingsHotkeyQuitKey,
                keyCodes: [
                    CGKeyCode(kVK_ANSI_R),
                    CGKeyCode(kVK_ANSI_T),
                    CGKeyCode(kVK_ANSI_4)
                ],
                expectedValue: "R + T + 4"
            )
        ] {
            recordShortcut(in: trustedApp, recording)
        }
        trustedApp.terminate()

        let deniedApp = makeApp(
            additionalArguments: hotkeyEffectArguments(
                accessibilityTrusted: false
            )
        )
        launchFlowTabUITestApplication(deniedApp)
        defer { deniedApp.terminate() }
        openSettingsTab(in: deniedApp)

        assertHotkeyStatus(
            in: deniedApp,
            identifier: Identifier.settingsHotkeyConflictStatus(
                for: Identifier.settingsHotkeyMainModifiers
            ),
            text: "未授权时仅支持修饰键"
        )
        assertHotkeyStatus(
            in: deniedApp,
            identifier: Identifier.settingsHotkeyConflictStatus(
                for: Identifier.settingsHotkeyMainReverseModifiers
            ),
            text: "未授权时仅支持修饰键"
        )
        assertHotkeyStatus(
            in: deniedApp,
            identifier: Identifier.settingsHotkeyConflictStatus(
                for: Identifier.settingsHotkeyMainKey
            ),
            text: "未授权时仅支持任意修饰键加一个普通键或功能键"
        )
        XCTAssertFalse(
            element(
                in: deniedApp,
                identifier:
                    "flowtab.settings.hotkey.main-accessibility-status"
            ).exists
        )

        let registrationBaseline = makeRuntimeLogFileSnapshot()
        enterShortcut(
            in: deniedApp,
            controlIdentifier: Identifier.settingsHotkeyMainKey,
            key: "tab",
            modifierFlags: []
        )
        assertValue(
            of: element(
                in: deniedApp,
                identifier: Identifier.settingsHotkeyMainKey
            ),
            equals: "Tab"
        )
        assertHotkeyStatusAbsent(
            in: deniedApp,
            identifier: Identifier.settingsHotkeyConflictStatus(
                for: Identifier.settingsHotkeyMainKey
            )
        )
        for identifier in [
            Identifier.settingsHotkeyMainModifiers,
            Identifier.settingsHotkeyMainReverseModifiers
        ] {
            assertHotkeyStatus(
                in: deniedApp,
                identifier: Identifier.settingsHotkeyConflictStatus(
                    for: identifier
                ),
                text: "未授权时仅支持修饰键"
            )
        }

        enterModifiers(
            in: deniedApp,
            controlIdentifier: Identifier.settingsHotkeyMainModifiers,
            modifierFlags: .option
        )
        enterModifiers(
            in: deniedApp,
            controlIdentifier:
                Identifier.settingsHotkeyMainReverseModifiers,
            modifierFlags: .shift
        )

        for identifier in [
            Identifier.settingsHotkeyMainModifiers,
            Identifier.settingsHotkeyMainReverseModifiers,
            Identifier.settingsHotkeyMainKey
        ] {
            assertHotkeyStatusAbsent(
                in: deniedApp,
                identifier: Identifier.settingsHotkeyConflictStatus(
                    for: identifier
                )
            )
        }
        waitForRuntimeLogFiles(
            containing: ["mainRoute=carbon"],
            since: registrationBaseline
        )
    }

    private func assertHotkeyStatus(
        in app: XCUIApplication,
        identifier: String,
        text: String
    ) {
        let status = app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format:
                        "identifier == %@ AND (label CONTAINS %@ OR value CONTAINS %@)",
                    identifier,
                    text,
                    text
                )
            )
            .firstMatch
        XCTAssertTrue(
            status.waitForExistence(timeout: 5),
            "Expected hotkey status text: \(text)"
        )
    }

    private func assertHotkeyStatusAbsent(
        in app: XCUIApplication,
        identifier: String
    ) {
        XCTAssertFalse(
            app.descendants(matching: .any)
                .matching(identifier: identifier)
                .firstMatch.exists,
            "Expected hotkey status to be absent: \(identifier)"
        )
    }
}
