import AppKit
import Carbon
import FlowTabCore
import XCTest
@testable import FlowTab

extension FlowTabTests {
    func testArbitraryKeySetRoundTripsWithoutCountLimit() throws {
        let reservedModifierCodes: Set<UInt16> = [
            UInt16(kVK_Command), UInt16(kVK_RightCommand),
            UInt16(kVK_Control), UInt16(kVK_RightControl),
            UInt16(kVK_Option), UInt16(kVK_RightOption),
            UInt16(kVK_Shift), UInt16(kVK_RightShift)
        ]
        let ordinaryKeys = (0...127)
            .map(UInt16.init)
            .filter { !reservedModifierCodes.contains($0) }
            .prefix(64)
            .map(SwitcherHotkeyKey.init(keyCode:))
        let keys = SwitcherHotkeyKeySet(
            Set(ordinaryKeys + [.command, .control, .option, .shift])
        )

        XCTAssertEqual(keys.count, 68)
        XCTAssertEqual(
            try XCTUnwrap(SwitcherHotkeyKeySet(rawValue: keys.rawValue)),
            keys
        )
        XCTAssertEqual(
            keys.orderedKeys.prefix(4),
            [.command, .control, .option, .shift]
        )
    }

    func testArbitraryKeyConfigurationBuildsFiveEffectiveActions() {
        let main = SwitcherHotkeyConfiguration(
            baseKeys: [.option, .command, .a],
            reverseKeys: [.shift, .control, .b],
            mainKeys: [.tab, .f6, SwitcherHotkeyKey(keyCode: UInt16(kVK_ANSI_7))],
            quitKeys: [.q, .w]
        )
        let inApp = SwitcherHotkeyConfiguration.inApp(
            baseKeys: [.control],
            reverseKeys: [.shift, .option, .f8],
            mainKeys: [.tab, .a, .b]
        )

        XCTAssertEqual(main.mainShortcut.keys.count, 6)
        XCTAssertEqual(main.backwardShortcut.keys.count, 9)
        XCTAssertEqual(main.quitShortcut.keys.count, 5)
        XCTAssertEqual(inApp.mainShortcut.keys.count, 4)
        XCTAssertEqual(inApp.backwardShortcut.keys.count, 7)
        XCTAssertFalse(main.supportsCarbonRegistration)
        XCTAssertFalse(inApp.supportsCarbonRegistration)
    }

    func testHotkeyChordStateMachineRequiresFullReleaseBeforeDirectionChange() {
        var stateMachine = HotkeyChordStateMachine(
            forwardKeys: [.option, .a, .tab, .b],
            backwardKeys: [.option, .a, .shift, .c, .tab, .b],
            holdKeys: [.option, .a]
        )

        XCTAssertEqual(
            stateMachine.update(pressedKeys: [.option, .a, .tab]),
            []
        )
        XCTAssertEqual(
            stateMachine.update(pressedKeys: [.option, .a, .tab, .b]),
            [HotkeyChordTransition(phase: .pressed, isBackward: false)]
        )
        XCTAssertEqual(
            stateMachine.update(
                pressedKeys: [.option, .a, .shift, .c, .tab, .b]
            ),
            []
        )
        XCTAssertEqual(
            stateMachine.update(
                pressedKeys: [.option, .a, .shift, .c]
            ),
            [HotkeyChordTransition(phase: .released, isBackward: false)]
        )
        XCTAssertEqual(
            stateMachine.update(
                pressedKeys: [.option, .a, .shift, .c, .tab, .b]
            ),
            [HotkeyChordTransition(phase: .pressed, isBackward: true)]
        )
    }

    func testHotkeyChordStateMachineReportsBaseReleaseAfterMainKeyRelease() {
        var stateMachine = HotkeyChordStateMachine(
            forwardKeys: [.option, .w, .tab],
            backwardKeys: [.option, .shift, .w, .tab],
            holdKeys: [.option, .w]
        )

        XCTAssertEqual(
            stateMachine.update(
                pressedKeys: [.option, .w, .tab]
            ),
            [HotkeyChordTransition(phase: .pressed, isBackward: false)]
        )
        XCTAssertEqual(
            stateMachine.update(pressedKeys: [.option, .w]),
            [HotkeyChordTransition(phase: .released, isBackward: false)]
        )
        XCTAssertEqual(
            stateMachine.update(pressedKeys: [.option]),
            [
                HotkeyChordTransition(
                    phase: .released,
                    isBackward: false,
                    isHoldSetPressed: false
                )
            ]
        )
    }

    func testHotkeyChordStateMachineHoldSetPressurePreservesTransitions() {
        var stateMachine = HotkeyChordStateMachine(
            forwardKeys: [.option, .w, .tab],
            backwardKeys: [.option, .shift, .w, .tab],
            holdKeys: [.option, .w]
        )
        let pressed = [
            HotkeyChordTransition(
                phase: .pressed,
                isBackward: false
            )
        ]
        let mainReleased = [
            HotkeyChordTransition(
                phase: .released,
                isBackward: false
            )
        ]
        let baseReleased = [
            HotkeyChordTransition(
                phase: .released,
                isBackward: false,
                isHoldSetPressed: false
            )
        ]

        for _ in 0..<1_000 {
            XCTAssertEqual(
                stateMachine.update(
                    pressedKeys: [.option, .w, .tab]
                ),
                pressed
            )
            XCTAssertEqual(
                stateMachine.update(
                    pressedKeys: [.option, .w]
                ),
                mainReleased
            )
            XCTAssertEqual(
                stateMachine.update(
                    pressedKeys: [.option, .w, .tab]
                ),
                pressed
            )
            XCTAssertEqual(
                stateMachine.update(
                    pressedKeys: [.option, .w]
                ),
                mainReleased
            )
            XCTAssertEqual(
                stateMachine.update(pressedKeys: [.option]),
                baseReleased
            )
        }
    }

    func testArbitraryKeyMonitorSelectsChordEventBackend() {
        let configuration = SwitcherHotkeyConfiguration(
            baseKeys: [.option, .a],
            reverseKeys: [.shift, .b],
            mainKeys: [.tab, .f6],
            quitKeys: [.q, .w]
        )
        var installedConfigurations: [SwitcherHotkeyConfiguration] = []
        var carbonRegistrations = 0
        var stopCount = 0
        let monitor = OptionTabHotkeyMonitor(
            configuration: configuration,
            startsMonitoring: false,
            handlerInstallerOverride: { true },
            hotkeyRegistrarOverride: { _, _, _ in
                carbonRegistrations += 1
                return true
            },
            chordEventMonitorStarterOverride: {
                installedConfigurations.append($0)
                return true
            },
            chordEventMonitorStopperOverride: {
                stopCount += 1
            }
        )

        monitor.start()
        monitor.start()

        XCTAssertEqual(installedConfigurations, [configuration])
        XCTAssertEqual(carbonRegistrations, 0)
        XCTAssertTrue(monitor.isChordEventMonitorActiveForTesting)

        monitor.stop()

        XCTAssertEqual(stopCount, 1)
        XCTAssertFalse(monitor.isChordEventMonitorActiveForTesting)
    }

    @MainActor
    func testModifierOnlyQuitKeyTriggersOnPressAndIgnoresRelease() throws {
        let preferenceKeys = [
            AppPreferenceKeys.hotkeyPrimaryModifier,
            AppPreferenceKeys.hotkeyReverseModifiers,
            AppPreferenceKeys.hotkeyMainKey,
            AppPreferenceKeys.hotkeyQuitKey
        ]
        let previousValues = preferenceKeys.reduce(
            into: [String: Any]()
        ) { result, key in
            if let value = UserDefaults.standard.object(forKey: key) {
                result[key] = value
            }
        }
        defer {
            for key in preferenceKeys {
                if let previousValue = previousValues[key] {
                    UserDefaults.standard.set(previousValue, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }
        UserDefaults.standard.set(
            SwitcherHotkeyKeySet([.option]).rawValue,
            forKey: AppPreferenceKeys.hotkeyPrimaryModifier
        )
        UserDefaults.standard.set(
            SwitcherHotkeyKeySet([.control]).rawValue,
            forKey: AppPreferenceKeys.hotkeyReverseModifiers
        )
        UserDefaults.standard.set(
            SwitcherHotkeyKeySet([.tab]).rawValue,
            forKey: AppPreferenceKeys.hotkeyMainKey
        )
        UserDefaults.standard.set(
            SwitcherHotkeyKeySet([.shift]).rawValue,
            forKey: AppPreferenceKeys.hotkeyQuitKey
        )

        let controller = SwitcherPanelController()
        let press = try modifierEvent(
            flags: [.option, .shift],
            keyCode: UInt16(kVK_Shift)
        )
        let release = try modifierEvent(
            flags: [.option],
            keyCode: UInt16(kVK_Shift)
        )

        XCTAssertTrue(controller.isTerminateSelectedAppShortcut(press))
        XCTAssertFalse(controller.isTerminateSelectedAppShortcut(release))
    }

    func testHotkeyConfigurationSupportsAllModifiersAndArbitraryVirtualKeyCode() {
        let key = SwitcherHotkeyKey(keyCode: UInt16(kVK_F13))
        let configuration = SwitcherHotkeyConfiguration(
            baseKeys: [.command, .option],
            reverseKeys: [.control, .shift],
            mainKeys: SwitcherHotkeyKeySet([key]),
            quitKeys: [.q]
        )

        XCTAssertEqual(SwitcherHotkeyKey(rawValue: key.rawValue), key)
        XCTAssertEqual(
            configuration.mainShortcut.carbonRegistration?.modifiers,
            UInt32(cmdKey) | UInt32(optionKey)
        )
        XCTAssertEqual(
            configuration.backwardShortcut.carbonRegistration?.modifiers,
            UInt32(cmdKey) | UInt32(controlKey) | UInt32(optionKey) | UInt32(shiftKey)
        )
        XCTAssertEqual(
            configuration.mainShortcutText,
            "Command + Option + F13"
        )
        XCTAssertEqual(
            configuration.backwardShortcutText,
            "Command + Control + Option + Shift + F13"
        )
    }

    func testCompositeShortcutPreferencesPersistAndRegisterExactCarbonFlags() {
        let suiteName = "FlowTabTests.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Failed to create isolated user defaults suite")
        }
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let baseKeys: SwitcherHotkeyKeySet = [.command, .option]
        let reverseKeys: SwitcherHotkeyKeySet = [.control, .shift]
        let key = SwitcherHotkeyKey(keyCode: UInt16(kVK_F13))
        userDefaults.set(
            baseKeys.rawValue,
            forKey: AppPreferenceKeys.hotkeyPrimaryModifier
        )
        userDefaults.set(
            reverseKeys.rawValue,
            forKey: AppPreferenceKeys.hotkeyReverseModifiers
        )
        userDefaults.set(key.rawValue, forKey: AppPreferenceKeys.hotkeyMainKey)
        userDefaults.set(SwitcherHotkeyKey.q.rawValue, forKey: AppPreferenceKeys.hotkeyQuitKey)

        let configuration = SwitcherHotkeyPreferencesStore.load(userDefaults: userDefaults)
        XCTAssertEqual(configuration.baseKeys, baseKeys)
        XCTAssertEqual(configuration.reverseKeys, reverseKeys)
        XCTAssertEqual(configuration.mainKeys, SwitcherHotkeyKeySet([key]))

        var registrations: [(id: UInt32, keyCode: UInt32, modifiers: UInt32)] = []
        let monitor = OptionTabHotkeyMonitor(
            configuration: configuration,
            startsMonitoring: false,
            handlerInstallerOverride: { true },
            hotkeyRegistrarOverride: { id, keyCode, carbonModifiers in
                registrations.append((id, keyCode, carbonModifiers))
                return true
            },
            hotkeyUnregisterOverride: { _ in },
            eventHandlerRemoverOverride: {}
        )
        monitor.start()
        defer { monitor.stop() }

        XCTAssertEqual(registrations.map(\.id), [1, 2])
        XCTAssertEqual(registrations.map(\.keyCode), [UInt32(key.keyCode), UInt32(key.keyCode)])
        XCTAssertEqual(
            registrations[0].modifiers,
            configuration.mainShortcut.carbonRegistration?.modifiers
        )
        XCTAssertEqual(
            registrations[1].modifiers,
            configuration.backwardShortcut.carbonRegistration?.modifiers
        )
    }

    func testHotkeyTransactionRejectsBaseAndReverseModifierComponentOverlap() {
        let cases: [(AppKitSettingsHotkeyRawValues, HotkeySettingsConflict)] = [
            (
                AppKitSettingsHotkeyRawValues(
                    hotkeyPrimaryModifierRaw: "option+shift",
                    hotkeyReverseModifiersRaw: "shift",
                    hotkeyMainKeyRaw: "tab",
                    hotkeyQuitKeyRaw: "q",
                    inAppWindowHotkeyBaseKeysRaw: "control",
                    inAppWindowHotkeyReverseKeysRaw: "shift",
                    inAppWindowHotkeyMainKeysRaw: "tab"
                ),
                .mainAndReverseModifier
            ),
            (
                AppKitSettingsHotkeyRawValues(
                    hotkeyPrimaryModifierRaw: "option",
                    hotkeyReverseModifiersRaw: "shift",
                    hotkeyMainKeyRaw: "tab",
                    hotkeyQuitKeyRaw: "q",
                    inAppWindowHotkeyBaseKeysRaw: "control",
                    inAppWindowHotkeyReverseKeysRaw: "shift",
                    inAppWindowHotkeyMainKeysRaw: "shift+tab"
            ),
                .inAppFamilyDuplicateKey
            ),
            (
                AppKitSettingsHotkeyRawValues(
                    hotkeyPrimaryModifierRaw: "option+a",
                    hotkeyReverseModifiersRaw: "shift+b",
                    hotkeyMainKeyRaw: "tab+a",
                    hotkeyQuitKeyRaw: "q+w",
                    inAppWindowHotkeyBaseKeysRaw: "control",
                    inAppWindowHotkeyReverseKeysRaw: "shift",
                    inAppWindowHotkeyMainKeysRaw: "tab"
                ),
                .mainFamilyDuplicateKey
            ),
            (
                AppKitSettingsHotkeyRawValues(
                    hotkeyPrimaryModifierRaw: "option+a",
                    hotkeyReverseModifiersRaw: "shift+b",
                    hotkeyMainKeyRaw: "tab+q",
                    hotkeyQuitKeyRaw: "q+w",
                    inAppWindowHotkeyBaseKeysRaw: "control",
                    inAppWindowHotkeyReverseKeysRaw: "shift",
                    inAppWindowHotkeyMainKeysRaw: "tab"
                ),
                .mainAndQuit
            )
        ]

        for (values, expectedConflict) in cases {
            XCTAssertEqual(
                HotkeySettingsChangeTransaction.apply(values, commit: { _ in }),
                .conflict(expectedConflict)
            )
        }
    }

    func testHotkeyStoresExposeSevenDefaultRecordedValues() {
        let main = SwitcherHotkeyPreferencesStore.resolve(
            baseKeysRaw: "invalid",
            reverseKeysRaw: nil,
            mainKeysRaw: "invalid",
            quitKeysRaw: "invalid"
        )
        let inApp = InAppWindowHotkeyPreferencesStore.resolve(
            baseKeysRaw: "invalid",
            reverseKeysRaw: nil,
            mainKeysRaw: "invalid"
        )

        XCTAssertEqual(main.baseKeys, [.option])
        XCTAssertEqual(main.reverseKeys, [.shift])
        XCTAssertEqual(main.mainKeys, [.tab])
        XCTAssertEqual(main.quitKeys, [.q])
        XCTAssertEqual(inApp.baseKeys, [.control])
        XCTAssertEqual(inApp.reverseKeys, [.shift])
        XCTAssertEqual(inApp.mainKeys, [.tab])
    }

    func testInAppShortcutSeparatesHoldAndMainKeySets() {
        let resolved = InAppWindowHotkeyPreferencesStore.resolve(
            baseKeysRaw: "control",
            reverseKeysRaw: "shift",
            mainKeysRaw: "tab+w"
        )
        let configuration = resolved.configuration

        XCTAssertEqual(configuration.baseKeys, [.control])
        XCTAssertEqual(configuration.mainKeys, [.tab, .w])
        XCTAssertEqual(
            configuration.mainShortcut.keys,
            [.control, .tab, .w]
        )
        XCTAssertEqual(
            configuration.backwardShortcut.keys,
            [.control, .shift, .tab, .w]
        )

        var stateMachine = HotkeyChordStateMachine(
            forwardKeys: configuration.mainShortcut.keys,
            backwardKeys: configuration.backwardShortcut.keys,
            holdKeys: configuration.baseKeys
        )
        XCTAssertEqual(
            stateMachine.update(
                pressedKeys: [.control, .tab, .w]
            ),
            [HotkeyChordTransition(phase: .pressed, isBackward: false)]
        )
        XCTAssertEqual(
            stateMachine.update(pressedKeys: [.control]),
            [
                HotkeyChordTransition(
                    phase: .released,
                    isBackward: false,
                    isHoldSetPressed: true
                )
            ]
        )
    }

    func testCommandTabFallbackKeepsModifierSetsDisjoint() {
        let requested = SwitcherHotkeyConfiguration(
            baseKeys: [.command],
            reverseKeys: [.option],
            mainKeys: [.tab],
            quitKeys: [.q]
        )

        let fallback = SwitcherHotkeyPreferencesStore.commandTabFallback(
            for: requested
        )

        XCTAssertEqual(fallback.baseKeys, [.option])
        XCTAssertTrue(fallback.baseKeys.isDisjoint(with: fallback.reverseKeys))
        XCTAssertFalse(fallback.usesCommandTab)
        XCTAssertEqual(fallback.mainShortcutText, "Option + Tab")
        XCTAssertEqual(fallback.backwardShortcutText, "Option + Shift + Tab")
    }

    func testArbitraryKeyPreferencesAndNotificationRoundTrip() throws {
        let main = SwitcherHotkeyConfiguration(
            baseKeys: [.option, .command, .a],
            reverseKeys: [.shift, .control, .b],
            mainKeys: [.tab, .f6],
            quitKeys: [.q, .w]
        )
        let inApp = SwitcherHotkeyConfiguration.inApp(
            baseKeys: [.control],
            reverseKeys: [.shift, .option, .f8],
            mainKeys: [.tab, .a, .b]
        )
        let request = HotkeyRegistrationRequest(
            mainConfiguration: main,
            inAppWindowConfiguration: inApp
        )
        let roundTrip = try XCTUnwrap(
            HotkeyRegistrationRequest(
                notificationUserInfo: request.notificationUserInfo
            )
        )

        XCTAssertEqual(roundTrip.mainConfiguration, main)
        XCTAssertEqual(roundTrip.inAppWindowConfiguration, inApp)
        XCTAssertFalse(roundTrip.mainConfiguration.supportsCarbonRegistration)
        XCTAssertFalse(roundTrip.inAppWindowConfiguration.supportsCarbonRegistration)
    }

    func testArbitraryKeyPreferencesPersistThroughUserDefaults() {
        let suiteName = "FlowTabTests.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Failed to create isolated user defaults suite")
        }
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let main = SwitcherHotkeyConfiguration(
            baseKeys: [.option, .command, .a],
            reverseKeys: [.shift, .control, .b],
            mainKeys: [.tab, .f6],
            quitKeys: [.q, .w]
        )
        let inApp = SwitcherHotkeyConfiguration.inApp(
            baseKeys: [.control],
            reverseKeys: [.shift, .option, .f8],
            mainKeys: [.tab, .a, .b]
        )
        userDefaults.set(
            main.baseKeys.rawValue,
            forKey: AppPreferenceKeys.hotkeyPrimaryModifier
        )
        userDefaults.set(
            main.reverseKeys.rawValue,
            forKey: AppPreferenceKeys.hotkeyReverseModifiers
        )
        userDefaults.set(
            main.mainKeys.rawValue,
            forKey: AppPreferenceKeys.hotkeyMainKey
        )
        userDefaults.set(
            main.quitKeys.rawValue,
            forKey: AppPreferenceKeys.hotkeyQuitKey
        )
        userDefaults.set(
            inApp.baseKeys.rawValue,
            forKey: AppPreferenceKeys.inAppWindowHotkeyBaseKeys
        )
        userDefaults.set(
            inApp.reverseKeys.rawValue,
            forKey: AppPreferenceKeys.inAppWindowHotkeyReverseKeys
        )
        userDefaults.set(
            inApp.mainKeys.rawValue,
            forKey: AppPreferenceKeys.inAppWindowHotkeyMainKeys
        )

        XCTAssertEqual(
            SwitcherHotkeyPreferencesStore.load(userDefaults: userDefaults),
            main
        )
        XCTAssertEqual(
            InAppWindowHotkeyPreferencesStore.load(userDefaults: userDefaults),
            inApp
        )
    }

    @MainActor
    func testShortcutRecorderCapturesFourModifierKeyboardInput() throws {
        let control = FlowSettingsShortcutRecorderControl(frame: .zero)
        control.update(
            keys: [.option, .tab],
            recordingPrompt: "Press shortcut",
            keyRequiredPrompt: "Press at least one key",
            accessibilityLabel: "Main switch shortcut"
        )
        var recordedKeys: SwitcherHotkeyKeySet?
        control.onKeysChanged = { recordedKeys = $0 }

        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command, .control, .option, .shift],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "k",
                charactersIgnoringModifiers: "k",
                isARepeat: false,
                keyCode: UInt16(kVK_ANSI_K)
            )
        )

        XCTAssertTrue(control.accessibilityPerformPress())
        control.keyDown(with: event)
        control.keyUp(
            with: try keyEvent(
                type: .keyUp,
                flags: [.command, .control, .option, .shift],
                keyCode: UInt16(kVK_ANSI_K)
            )
        )
        control.flagsChanged(
            with: try modifierEvent(flags: [], keyCode: UInt16(kVK_Shift))
        )

        XCTAssertEqual(recordedKeys, [.command, .control, .option, .shift, .k])
        XCTAssertEqual(
            control.accessibilityValue() as? String,
            "Command + Control + Option + Shift + K"
        )
    }

    @MainActor
    func testShortcutRecorderCapturesMultipleOrdinaryKeysUntilFullRelease() throws {
        let control = FlowSettingsShortcutRecorderControl(frame: .zero)
        control.update(
            keys: [.option],
            recordingPrompt: "Press keys",
            keyRequiredPrompt: "Press at least one key",
            accessibilityLabel: "Main keys"
        )
        var recordedKeys: SwitcherHotkeyKeySet?
        control.onKeysChanged = { recordedKeys = $0 }

        XCTAssertTrue(control.accessibilityPerformPress())
        control.flagsChanged(
            with: try modifierEvent(
                flags: [.option, .command],
                keyCode: UInt16(kVK_Command)
            )
        )
        for keyCode in [
            UInt16(kVK_ANSI_A),
            UInt16(kVK_F6),
            UInt16(kVK_ANSI_7)
        ] {
            control.keyDown(
                with: try keyEvent(
                    type: .keyDown,
                    flags: [.option, .command],
                    keyCode: keyCode
                )
            )
        }
        for keyCode in [
            UInt16(kVK_ANSI_A),
            UInt16(kVK_F6),
            UInt16(kVK_ANSI_7)
        ] {
            control.keyUp(
                with: try keyEvent(
                    type: .keyUp,
                    flags: [.option, .command],
                    keyCode: keyCode
                )
            )
        }
        XCTAssertNil(recordedKeys)
        control.flagsChanged(
            with: try modifierEvent(flags: [], keyCode: UInt16(kVK_Option))
        )

        XCTAssertEqual(
            recordedKeys,
            [.command, .option, .a, .f6, SwitcherHotkeyKey(keyCode: UInt16(kVK_ANSI_7))]
        )
        XCTAssertEqual(
            control.accessibilityValue() as? String,
            "Command + Option + A + 7 + F6"
        )
    }

    @MainActor
    func testShortcutRecorderCapturesModifierOnlyCombinationOnRelease() throws {
        let control = FlowSettingsShortcutRecorderControl(frame: .zero)
        control.update(
            keys: [.option],
            recordingPrompt: "Press shortcut",
            keyRequiredPrompt: "Press at least one key",
            accessibilityLabel: "Main modifiers"
        )
        var recordedKeys: SwitcherHotkeyKeySet?
        control.onKeysChanged = { recordedKeys = $0 }

        XCTAssertTrue(control.accessibilityPerformPress())
        control.flagsChanged(
            with: try modifierEvent(flags: [.option], keyCode: UInt16(kVK_Option))
        )
        control.flagsChanged(
            with: try modifierEvent(
                flags: [.option, .shift],
                keyCode: UInt16(kVK_Shift)
            )
        )
        control.flagsChanged(
            with: try modifierEvent(flags: [.shift], keyCode: UInt16(kVK_Option))
        )
        control.flagsChanged(
            with: try modifierEvent(flags: [], keyCode: UInt16(kVK_Shift))
        )

        XCTAssertEqual(recordedKeys, [.option, .shift])
        XCTAssertEqual(control.accessibilityValue() as? String, "Option + Shift")
    }

    private func modifierEvent(
        flags: NSEvent.ModifierFlags,
        keyCode: UInt16
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .flagsChanged,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }

    private func keyEvent(
        type: NSEvent.EventType,
        flags: NSEvent.ModifierFlags,
        keyCode: UInt16
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: type,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }
}
