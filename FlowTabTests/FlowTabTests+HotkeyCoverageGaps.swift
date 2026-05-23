import Carbon
import XCTest
@testable import FlowTab

extension FlowTabTests {
    func testHotkeyRegistrationRequestNormalizesRawSettingsValues() {
        struct Case {
            let name: String
            let mainModifierRaw: String
            let mainKeyRaw: String
            let quitKeyRaw: String
            let inAppModifierRaw: String
            let inAppKeyRaw: String
            let expectedMainModifier: SwitcherPrimaryModifier
            let expectedMainKey: SwitcherHotkeyKey
            let expectedQuitKey: SwitcherHotkeyKey
            let expectedInAppModifier: SwitcherPrimaryModifier
            let expectedInAppKey: SwitcherHotkeyKey
        }

        let cases = [
            Case(
                name: "normal values",
                mainModifierRaw: SwitcherPrimaryModifier.command.rawValue,
                mainKeyRaw: SwitcherHotkeyKey.space.rawValue,
                quitKeyRaw: SwitcherHotkeyKey.w.rawValue,
                inAppModifierRaw: SwitcherPrimaryModifier.control.rawValue,
                inAppKeyRaw: SwitcherHotkeyKey.tab.rawValue,
                expectedMainModifier: .command,
                expectedMainKey: .space,
                expectedQuitKey: .w,
                expectedInAppModifier: .control,
                expectedInAppKey: .tab
            ),
            Case(
                name: "invalid values",
                mainModifierRaw: "bad-modifier",
                mainKeyRaw: "bad-main-key",
                quitKeyRaw: "bad-quit-key",
                inAppModifierRaw: "bad-in-app-modifier",
                inAppKeyRaw: "bad-in-app-key",
                expectedMainModifier: .option,
                expectedMainKey: .tab,
                expectedQuitKey: .q,
                expectedInAppModifier: .control,
                expectedInAppKey: .tab
            ),
            Case(
                name: "quit conflicts with main",
                mainModifierRaw: SwitcherPrimaryModifier.option.rawValue,
                mainKeyRaw: SwitcherHotkeyKey.q.rawValue,
                quitKeyRaw: SwitcherHotkeyKey.q.rawValue,
                inAppModifierRaw: SwitcherPrimaryModifier.control.rawValue,
                inAppKeyRaw: SwitcherHotkeyKey.space.rawValue,
                expectedMainModifier: .option,
                expectedMainKey: .q,
                expectedQuitKey: .w,
                expectedInAppModifier: .control,
                expectedInAppKey: .space
            ),
            Case(
                name: "in-app conflicts with main control tab",
                mainModifierRaw: SwitcherPrimaryModifier.control.rawValue,
                mainKeyRaw: SwitcherHotkeyKey.tab.rawValue,
                quitKeyRaw: SwitcherHotkeyKey.q.rawValue,
                inAppModifierRaw: SwitcherPrimaryModifier.control.rawValue,
                inAppKeyRaw: SwitcherHotkeyKey.tab.rawValue,
                expectedMainModifier: .control,
                expectedMainKey: .tab,
                expectedQuitKey: .q,
                expectedInAppModifier: .option,
                expectedInAppKey: .tab
            ),
            Case(
                name: "in-app conflicts with main option space",
                mainModifierRaw: SwitcherPrimaryModifier.option.rawValue,
                mainKeyRaw: SwitcherHotkeyKey.space.rawValue,
                quitKeyRaw: SwitcherHotkeyKey.q.rawValue,
                inAppModifierRaw: SwitcherPrimaryModifier.option.rawValue,
                inAppKeyRaw: SwitcherHotkeyKey.space.rawValue,
                expectedMainModifier: .option,
                expectedMainKey: .space,
                expectedQuitKey: .q,
                expectedInAppModifier: .control,
                expectedInAppKey: .space
            )
        ]

        for item in cases {
            let request = HotkeyRegistrationRequest.normalized(
                mainPrimaryModifierRaw: item.mainModifierRaw,
                mainKeyRaw: item.mainKeyRaw,
                quitKeyRaw: item.quitKeyRaw,
                inAppPrimaryModifierRaw: item.inAppModifierRaw,
                inAppMainKeyRaw: item.inAppKeyRaw
            )

            XCTAssertEqual(request.mainConfiguration.primaryModifier, item.expectedMainModifier, item.name)
            XCTAssertEqual(request.mainConfiguration.mainKey, item.expectedMainKey, item.name)
            XCTAssertEqual(request.mainConfiguration.quitKey, item.expectedQuitKey, item.name)
            XCTAssertEqual(
                request.inAppWindowConfiguration.primaryModifier,
                item.expectedInAppModifier,
                item.name
            )
            XCTAssertEqual(request.inAppWindowConfiguration.mainKey, item.expectedInAppKey, item.name)
            XCTAssertEqual(request.inAppWindowConfiguration.quitKey, .q, item.name)

            let roundTripRequest = HotkeyRegistrationRequest(
                notificationUserInfo: request.notificationUserInfo
            )
            XCTAssertEqual(roundTripRequest?.mainConfiguration.primaryModifier, item.expectedMainModifier, item.name)
            XCTAssertEqual(roundTripRequest?.mainConfiguration.mainKey, item.expectedMainKey, item.name)
            XCTAssertEqual(roundTripRequest?.mainConfiguration.quitKey, item.expectedQuitKey, item.name)
            XCTAssertEqual(
                roundTripRequest?.inAppWindowConfiguration.primaryModifier,
                item.expectedInAppModifier,
                item.name
            )
            XCTAssertEqual(roundTripRequest?.inAppWindowConfiguration.mainKey, item.expectedInAppKey, item.name)
        }
    }

    func testHotkeyRegistrationRequestLoadPersistsNormalizedStoredValues() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }

        userDefaults.set("bad-modifier", forKey: AppPreferenceKeys.hotkeyPrimaryModifier)
        userDefaults.set(SwitcherHotkeyKey.z.rawValue, forKey: AppPreferenceKeys.hotkeyMainKey)
        userDefaults.set(SwitcherHotkeyKey.z.rawValue, forKey: AppPreferenceKeys.hotkeyQuitKey)
        userDefaults.set("bad-in-app-modifier", forKey: AppPreferenceKeys.inAppWindowHotkeyPrimaryModifier)
        userDefaults.set("bad-in-app-key", forKey: AppPreferenceKeys.inAppWindowHotkeyMainKey)

        let request = HotkeyRegistrationRequest.load(userDefaults: userDefaults)

        XCTAssertEqual(request.mainConfiguration.primaryModifier, .option)
        XCTAssertEqual(request.mainConfiguration.mainKey, .z)
        XCTAssertEqual(request.mainConfiguration.quitKey, .q)
        XCTAssertEqual(request.inAppWindowConfiguration.primaryModifier, .control)
        XCTAssertEqual(request.inAppWindowConfiguration.mainKey, .tab)
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.hotkeyPrimaryModifier),
            SwitcherPrimaryModifier.option.rawValue
        )
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.hotkeyQuitKey),
            SwitcherHotkeyKey.q.rawValue
        )
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.inAppWindowHotkeyPrimaryModifier),
            SwitcherPrimaryModifier.control.rawValue
        )
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.inAppWindowHotkeyMainKey),
            SwitcherHotkeyKey.tab.rawValue
        )
    }

    func testHotkeyRegistrationRequestLoadNormalizesStoredInAppConflict() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }

        userDefaults.set(
            SwitcherPrimaryModifier.control.rawValue,
            forKey: AppPreferenceKeys.hotkeyPrimaryModifier
        )
        userDefaults.set(SwitcherHotkeyKey.tab.rawValue, forKey: AppPreferenceKeys.hotkeyMainKey)
        userDefaults.set(SwitcherHotkeyKey.q.rawValue, forKey: AppPreferenceKeys.hotkeyQuitKey)
        userDefaults.set(
            SwitcherPrimaryModifier.control.rawValue,
            forKey: AppPreferenceKeys.inAppWindowHotkeyPrimaryModifier
        )
        userDefaults.set(SwitcherHotkeyKey.tab.rawValue, forKey: AppPreferenceKeys.inAppWindowHotkeyMainKey)

        let request = HotkeyRegistrationRequest.load(userDefaults: userDefaults)

        XCTAssertEqual(request.mainConfiguration.primaryModifier, .control)
        XCTAssertEqual(request.mainConfiguration.mainKey, .tab)
        XCTAssertEqual(request.inAppWindowConfiguration.primaryModifier, .option)
        XCTAssertEqual(request.inAppWindowConfiguration.mainKey, .tab)
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.inAppWindowHotkeyPrimaryModifier),
            SwitcherPrimaryModifier.option.rawValue
        )
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.inAppWindowHotkeyMainKey),
            SwitcherHotkeyKey.tab.rawValue
        )
    }

    func testHotkeyRegistrationRequestCoversSupportedSettingsMatrixAxes() {
        for modifier in SwitcherPrimaryModifier.allCases {
            for mainKey in SwitcherHotkeyKey.allCases {
                let quitKey: SwitcherHotkeyKey = mainKey == .q ? .w : .q
                let inAppModifier: SwitcherPrimaryModifier = modifier == .control ? .option : .control

                let request = HotkeyRegistrationRequest.normalized(
                    mainPrimaryModifierRaw: modifier.rawValue,
                    mainKeyRaw: mainKey.rawValue,
                    quitKeyRaw: quitKey.rawValue,
                    inAppPrimaryModifierRaw: inAppModifier.rawValue,
                    inAppMainKeyRaw: mainKey.rawValue
                )

                XCTAssertEqual(request.mainConfiguration.primaryModifier, modifier)
                XCTAssertEqual(request.mainConfiguration.mainKey, mainKey)
                XCTAssertEqual(request.mainConfiguration.quitKey, quitKey)
                XCTAssertEqual(request.inAppWindowConfiguration.primaryModifier, inAppModifier)
                XCTAssertEqual(request.inAppWindowConfiguration.mainKey, mainKey)
                XCTAssertEqual(
                    HotkeyRegistrationRequest(notificationUserInfo: request.notificationUserInfo)?
                        .mainConfiguration.mainKey,
                    mainKey
                )
            }
        }

        for modifier in SwitcherPrimaryModifier.allCases {
            for mainKey in SwitcherHotkeyKey.allCases {
                let request = HotkeyRegistrationRequest.normalized(
                    mainPrimaryModifierRaw: modifier.rawValue,
                    mainKeyRaw: mainKey.rawValue,
                    quitKeyRaw: mainKey.rawValue,
                    inAppPrimaryModifierRaw: SwitcherPrimaryModifier.control.rawValue,
                    inAppMainKeyRaw: SwitcherHotkeyKey.tab.rawValue
                )
                let expectedQuitKey: SwitcherHotkeyKey = mainKey == .q ? .w : .q

                XCTAssertEqual(request.mainConfiguration.primaryModifier, modifier)
                XCTAssertEqual(request.mainConfiguration.mainKey, mainKey)
                XCTAssertEqual(request.mainConfiguration.quitKey, expectedQuitKey)
            }
        }

        for modifier in SwitcherPrimaryModifier.allCases {
            for mainKey in SwitcherHotkeyKey.allCases {
                let quitKey: SwitcherHotkeyKey = mainKey == .q ? .w : .q
                let request = HotkeyRegistrationRequest.normalized(
                    mainPrimaryModifierRaw: modifier.rawValue,
                    mainKeyRaw: mainKey.rawValue,
                    quitKeyRaw: quitKey.rawValue,
                    inAppPrimaryModifierRaw: modifier.rawValue,
                    inAppMainKeyRaw: mainKey.rawValue
                )
                let expectedInAppModifier: SwitcherPrimaryModifier = modifier == .control ? .option : .control

                XCTAssertEqual(request.inAppWindowConfiguration.primaryModifier, expectedInAppModifier)
                XCTAssertEqual(request.inAppWindowConfiguration.mainKey, mainKey)
                XCTAssertEqual(request.inAppWindowConfiguration.quitKey, .q)
            }
        }
    }

    func testHotkeyConfigurationDerivedFieldsCoverSupportedModifiersAndRepresentativeKeys() {
        let modifiers: [(modifier: SwitcherPrimaryModifier, carbon: UInt32, display: String)] = [
            (.option, UInt32(optionKey), "Option"),
            (.control, UInt32(controlKey), "Control"),
            (.command, UInt32(cmdKey), "Command")
        ]
        let keys: [(key: SwitcherHotkeyKey, code: UInt16, display: String)] = [
            (.tab, UInt16(kVK_Tab), "Tab"),
            (.space, UInt16(kVK_Space), "Space"),
            (.grave, UInt16(kVK_ANSI_Grave), "`"),
            (.q, UInt16(kVK_ANSI_Q), "Q"),
            (.w, UInt16(kVK_ANSI_W), "W")
        ]

        for modifier in modifiers {
            for mainKey in keys {
                for quitKey in keys where quitKey.key != mainKey.key {
                    let configuration = SwitcherHotkeyConfiguration(
                        primaryModifier: modifier.modifier,
                        mainKey: mainKey.key,
                        quitKey: quitKey.key
                    )

                    XCTAssertEqual(configuration.forwardKeyCode, UInt32(mainKey.code))
                    XCTAssertEqual(configuration.forwardModifiers, modifier.carbon)
                    XCTAssertEqual(configuration.backwardModifiers, modifier.carbon | UInt32(shiftKey))
                    XCTAssertEqual(configuration.quitKeyCode, quitKey.code)
                    XCTAssertEqual(
                        configuration.mainShortcutText,
                        "\(modifier.display) + \(mainKey.display)"
                    )
                    XCTAssertEqual(
                        configuration.backwardShortcutText,
                        "\(modifier.display) + Shift + \(mainKey.display)"
                    )
                    XCTAssertEqual(
                        configuration.quitShortcutText,
                        "\(modifier.display) + \(quitKey.display)"
                    )
                }
            }
        }
    }
}
