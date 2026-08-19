import AppKit
import XCTest
@testable import FlowTab

extension FlowTabTests {
    func testHotkeyRegistrationRequestNormalizesKeySetSettingsValues() {
        struct Case {
            let name: String
            let mainBaseKeysRaw: String
            let mainReverseKeysRaw: String
            let mainKeysRaw: String
            let quitKeysRaw: String
            let inAppBaseKeysRaw: String
            let inAppReverseKeysRaw: String
            let inAppMainKeysRaw: String
            let expectedMain: SwitcherHotkeyConfiguration
            let expectedInApp: SwitcherHotkeyConfiguration
        }

        let cases = [
            Case(
                name: "arbitrary key sets",
                mainBaseKeysRaw: "option+w",
                mainReverseKeysRaw: "shift",
                mainKeysRaw: SwitcherHotkeyKeySet([.tab, .f6]).rawValue,
                quitKeysRaw: "q",
                inAppBaseKeysRaw: "control",
                inAppReverseKeysRaw: "shift",
                inAppMainKeysRaw: "tab",
                expectedMain: SwitcherHotkeyConfiguration(
                    baseKeys: [.option, .w],
                    reverseKeys: [.shift],
                    mainKeys: [.tab, .f6],
                    quitKeys: [.q]
                ),
                expectedInApp: .inApp(
                    baseKeys: [.control],
                    reverseKeys: [.shift],
                    mainKeys: [.tab]
                )
            ),
            Case(
                name: "invalid values",
                mainBaseKeysRaw: "invalid-base",
                mainReverseKeysRaw: "invalid-reverse",
                mainKeysRaw: "invalid-main",
                quitKeysRaw: "invalid-quit",
                inAppBaseKeysRaw: "invalid-in-app-base",
                inAppReverseKeysRaw: "invalid-in-app-reverse",
                inAppMainKeysRaw: "invalid-in-app-main",
                expectedMain: SwitcherHotkeyConfiguration(
                    baseKeys: [.option],
                    reverseKeys: [.shift],
                    mainKeys: [.tab],
                    quitKeys: [.q]
                ),
                expectedInApp: .inApp(
                    baseKeys: [.control],
                    reverseKeys: [.shift],
                    mainKeys: [.tab]
                )
            ),
            Case(
                name: "quit field conflict",
                mainBaseKeysRaw: "option",
                mainReverseKeysRaw: "shift",
                mainKeysRaw: "q",
                quitKeysRaw: "q",
                inAppBaseKeysRaw: "control",
                inAppReverseKeysRaw: "shift",
                inAppMainKeysRaw: "space",
                expectedMain: SwitcherHotkeyConfiguration(
                    baseKeys: [.option],
                    reverseKeys: [.shift],
                    mainKeys: [.q],
                    quitKeys: [.w]
                ),
                expectedInApp: .inApp(
                    baseKeys: [.control],
                    reverseKeys: [.shift],
                    mainKeys: [.space]
                )
            )
        ]

        for item in cases {
            let request = HotkeyRegistrationRequest.normalized(
                mainBaseKeysRaw: item.mainBaseKeysRaw,
                mainReverseKeysRaw: item.mainReverseKeysRaw,
                mainKeysRaw: item.mainKeysRaw,
                quitKeysRaw: item.quitKeysRaw,
                inAppBaseKeysRaw: item.inAppBaseKeysRaw,
                inAppMainKeysRaw: item.inAppMainKeysRaw,
                inAppReverseKeysRaw: item.inAppReverseKeysRaw
            )

            XCTAssertEqual(request.mainConfiguration, item.expectedMain, item.name)
            XCTAssertEqual(
                request.inAppWindowConfiguration,
                item.expectedInApp,
                item.name
            )
            XCTAssertEqual(
                HotkeyRegistrationRequest(
                    notificationUserInfo: request.notificationUserInfo
                ),
                request,
                item.name
            )
        }
    }

    func testHotkeyRegistrationRequestLoadPersistsNormalizedKeySets() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }

        userDefaults.set(
            "invalid-base",
            forKey: AppPreferenceKeys.hotkeyPrimaryModifier
        )
        userDefaults.set(
            SwitcherHotkeyKey.z.rawValue,
            forKey: AppPreferenceKeys.hotkeyMainKey
        )
        userDefaults.set(
            SwitcherHotkeyKey.z.rawValue,
            forKey: AppPreferenceKeys.hotkeyQuitKey
        )
        userDefaults.set(
            "invalid-in-app",
            forKey: AppPreferenceKeys.inAppWindowHotkeyShortcutKeys
        )

        let request = HotkeyRegistrationRequest.load(userDefaults: userDefaults)

        XCTAssertEqual(request.mainConfiguration.baseKeys, [.option])
        XCTAssertEqual(request.mainConfiguration.mainKeys, [.z])
        XCTAssertEqual(request.mainConfiguration.quitKeys, [.q])
        XCTAssertEqual(
            request.inAppWindowConfiguration.baseKeys,
            [.control]
        )
        XCTAssertEqual(
            request.inAppWindowConfiguration.mainKeys,
            [.tab]
        )
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.hotkeyPrimaryModifier),
            SwitcherHotkeyKeySet([.option]).rawValue
        )
        XCTAssertEqual(
            userDefaults.string(forKey: AppPreferenceKeys.hotkeyQuitKey),
            SwitcherHotkeyKeySet([.q]).rawValue
        )
        XCTAssertEqual(
            userDefaults.string(
                forKey: AppPreferenceKeys.inAppWindowHotkeyBaseKeys
            ),
            SwitcherHotkeyKeySet([.control]).rawValue
        )
        XCTAssertEqual(
            userDefaults.string(
                forKey: AppPreferenceKeys.inAppWindowHotkeyMainKeys
            ),
            SwitcherHotkeyKeySet([.tab]).rawValue
        )
    }

    func testHotkeyRegistrationRequestLoadNormalizesStoredInAppConflict() {
        guard let userDefaults = makeIsolatedUserDefaults() else { return }
        defer { clearIsolatedUserDefaults(userDefaults) }

        userDefaults.set("control", forKey: AppPreferenceKeys.hotkeyPrimaryModifier)
        userDefaults.set("tab", forKey: AppPreferenceKeys.hotkeyMainKey)
        userDefaults.set("q", forKey: AppPreferenceKeys.hotkeyQuitKey)
        userDefaults.set(
            "control+tab",
            forKey: AppPreferenceKeys.inAppWindowHotkeyShortcutKeys
        )

        let request = HotkeyRegistrationRequest.load(userDefaults: userDefaults)

        XCTAssertEqual(request.mainConfiguration.mainShortcut.keys, [.control, .tab])
        XCTAssertEqual(request.inAppWindowConfiguration.baseKeys, [.option])
        XCTAssertEqual(request.inAppWindowConfiguration.mainKeys, [.tab])
        XCTAssertEqual(
            userDefaults.string(
                forKey: AppPreferenceKeys.inAppWindowHotkeyBaseKeys
            ),
            SwitcherHotkeyKeySet([.option]).rawValue
        )
    }

    @MainActor
    func testHotkeySettingsCardProjectsResolvedInAppShortcutKeySet() throws {
        let request = HotkeyRegistrationRequest.normalized(
            mainBaseKeysRaw: "option",
            mainReverseKeysRaw: "shift",
            mainKeysRaw: "tab",
            quitKeysRaw: "q",
            inAppBaseKeysRaw: "option",
            inAppMainKeysRaw: "q",
            inAppReverseKeysRaw: "shift"
        )
        let view = HotkeySettingsCardAppKitView()
        view.update(
            with: HotkeySettingsCardState(
                hotkeyPrimaryModifierRaw:
                    request.mainConfiguration.baseKeys.rawValue,
                hotkeyReverseModifiersRaw:
                    request.mainConfiguration.reverseKeys.rawValue,
                hotkeyMainKeyRaw:
                    request.mainConfiguration.mainKeys.rawValue,
                hotkeyQuitKeyRaw:
                    request.mainConfiguration.quitKeys.rawValue,
                inAppWindowHotkeyBaseKeysRaw:
                    request.inAppWindowConfiguration.baseKeys.rawValue,
                inAppWindowHotkeyReverseKeysRaw:
                    request.inAppWindowConfiguration.reverseKeys.rawValue,
                inAppWindowHotkeyMainKeysRaw:
                    request.inAppWindowConfiguration.mainKeys.rawValue,
                commandTabTakeoverRegistrationState: .inactive,
                accessibilityTrusted: true,
                appLanguageRaw: AppLanguage.simplifiedChinese.rawValue
            )
        )

        let inAppBaseRecorder: FlowSettingsShortcutRecorderControl = try XCTUnwrap(
            hotkeyDescendant(
                in: view,
                identifier: "flowtab.settings.hotkey.in-app-base-keys"
            )
        )
        let inAppMainRecorder: FlowSettingsShortcutRecorderControl = try XCTUnwrap(
            hotkeyDescendant(
                in: view,
                identifier: "flowtab.settings.hotkey.in-app-main-keys"
            )
        )

        XCTAssertEqual(inAppBaseRecorder.recordedKeys, [.control])
        XCTAssertEqual(inAppMainRecorder.recordedKeys, [.q])
    }

    private func hotkeyDescendant<T: NSView>(
        in view: NSView,
        identifier: String,
        as type: T.Type = T.self
    ) -> T? {
        if view.identifier?.rawValue == identifier
            || view.accessibilityIdentifier() == identifier
        {
            return view as? T
        }
        for subview in view.subviews {
            if let match: T = hotkeyDescendant(
                in: subview,
                identifier: identifier,
                as: type
            ) {
                return match
            }
        }
        return nil
    }
}
