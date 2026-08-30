import AppKit
import FlowTabCore
import SwiftUI
import XCTest
@testable import FlowTab

extension FlowTabTests {
    @MainActor
    func testSettingsSelectControlPublishesInteractionBeforeOpening() {
        let control = FlowSettingsSelectControl(frame: .zero)
        control.configure(options: [(id: "one", title: "One")])
        var interactionCount = 0
        control.onInteraction = { interactionCount += 1 }

        XCTAssertTrue(control.accessibilityPerformPress())
        XCTAssertEqual(interactionCount, 1)
    }

    func testHotkeySettingsChangeTransactionRejectsConflictMatrixWithoutCommit() {
        let cases: [(AppKitSettingsHotkeyRawValues, HotkeySettingsConflict)] = [
            (
                hotkeyValues(
                    mainModifier: .option,
                    mainKey: .tab,
                    quitKey: .tab,
                    inAppModifier: .control,
                    inAppKey: .space
                ),
                .mainAndQuit
            ),
            (
                hotkeyValues(
                    mainModifier: .option,
                    mainKey: .tab,
                    quitKey: .q,
                    inAppModifier: .option,
                    inAppKey: .tab
                ),
                .mainAndInApp
            ),
            (
                hotkeyValues(
                    mainModifier: .option,
                    mainKey: .tab,
                    quitKey: .q,
                    inAppModifier: .option,
                    inAppKey: .q
                ),
                .quitAndInApp
            )
        ]

        for (values, expectedConflict) in cases {
            var committedRequest: HotkeyRegistrationRequest?

            let result = HotkeySettingsChangeTransaction.apply(values) {
                committedRequest = $0
            }

            XCTAssertEqual(result, .conflict(expectedConflict))
            XCTAssertNil(committedRequest)
        }
    }

    func testHotkeySettingsChangeTransactionCommitsNonConflictingCandidate() {
        let values = hotkeyValues(
            mainModifier: .command,
            mainKey: .space,
            quitKey: .z,
            inAppModifier: .control,
            inAppKey: .b
        )
        var committedRequest: HotkeyRegistrationRequest?

        let result = HotkeySettingsChangeTransaction.apply(values) {
            committedRequest = $0
        }

        guard case let .applied(request) = result else {
            return XCTFail("Expected non-conflicting hotkey candidate to be applied")
        }
        XCTAssertEqual(committedRequest, request)
        XCTAssertEqual(request.mainConfiguration.baseKeys, [.command])
        XCTAssertEqual(request.mainConfiguration.reverseKeys, [.shift])
        XCTAssertEqual(request.mainConfiguration.mainKeys, [.space])
        XCTAssertEqual(request.mainConfiguration.quitKeys, [.z])
        XCTAssertEqual(
            request.inAppWindowConfiguration.baseKeys,
            [.control]
        )
        XCTAssertEqual(request.inAppWindowConfiguration.reverseKeys, [.shift])
        XCTAssertEqual(request.inAppWindowConfiguration.mainKeys, [.b])
    }

    @MainActor
    func testSettingsBridgeKeepsCurrentHotkeyBindingsWhenCandidateIsRejected() throws {
        let state = HotkeySettingsBridgeBindingState()
        var rejectedCandidate: HotkeySettingsChangeCandidate?

        let content = AppKitSettingsPageContent(
            lifecycle: HomeRetainedTabLifecycle(state: .active),
            isVisible: true,
            showInCommandTab: state.binding(\.showInCommandTab),
            themeModeRaw: state.binding(\.themeModeRaw),
            appLanguageRaw: state.binding(\.appLanguageRaw),
            presentationContext: FlowPresentationState.shared.context,
            windowLayerAutoEnterDelayText: "0.3",
            autoRestoreMinimizedWindowOnSwitch: state.binding(
                \.autoRestoreMinimizedWindowOnSwitch
            ),
            hideMinimizedAppsFromAppLayer: state.binding(\.hideMinimizedAppsFromAppLayer),
            showPermissionReminder: state.binding(\.showPermissionReminder),
            allowLaunchAtLogin: state.binding(\.allowLaunchAtLogin),
            searchEnabled: state.binding(\.searchEnabled),
            searchDefaultScopeRaw: state.binding(\.searchDefaultScopeRaw),
            hiddenAppCount: 0,
            hotkeyPrimaryModifierRaw: state.binding(\.hotkeyPrimaryModifierRaw),
            hotkeyReverseModifiersRaw: state.binding(\.hotkeyReverseModifiersRaw),
            hotkeyMainKeyRaw: state.binding(\.hotkeyMainKeyRaw),
            hotkeyQuitKeyRaw: state.binding(\.hotkeyQuitKeyRaw),
            inAppWindowHotkeyBaseKeysRaw: state.binding(
                \.inAppWindowHotkeyBaseKeysRaw
            ),
            inAppWindowHotkeyReverseKeysRaw: state.binding(
                \.inAppWindowHotkeyReverseKeysRaw
            ),
            inAppWindowHotkeyMainKeysRaw: state.binding(
                \.inAppWindowHotkeyMainKeysRaw
            ),
            commandTabTakeoverRegistrationState: .inactive,
            hotkeyConflict: nil,
            accessibilityTrusted: true,
            screenCaptureTrusted: true,
            onWindowLayerAutoEnterDelayTextChanged: { _ in },
            onWindowLayerAutoEnterDelayTextCommitted: {},
            onWindowLayerAutoEnterDelayEditingChanged: { _ in },
            onHotkeyChanged: { rejectedCandidate = $0 },
            onDismissHotkeyConflict: {},
            onLaunchAtLoginChanged: { _ in },
            onManageAppVisibility: {},
            onAccessibilityAction: {},
            onScreenCaptureAction: {}
        )
        let hostedView = NSHostingView(
            rootView: content.frame(width: 1_200, height: 820, alignment: .topLeading)
        )
        hostedView.frame = NSRect(x: 0, y: 0, width: 1_200, height: 820)
        hostedView.layoutSubtreeIfNeeded()

        let mainModifiersRecorder: FlowSettingsShortcutRecorderControl = try XCTUnwrap(
            hotkeyConflictDescendant(
                in: hostedView,
                identifier: "flowtab.settings.hotkey.main-modifiers"
            )
        )
        let conflictingPress = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .flagsChanged,
                location: .zero,
                modifierFlags: [.option, .shift],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: SwitcherHotkeyKey.shift.keyCode
            )
        )
        let conflictingRelease = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .flagsChanged,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: SwitcherHotkeyKey.shift.keyCode
            )
        )

        XCTAssertTrue(mainModifiersRecorder.accessibilityPerformPress())
        mainModifiersRecorder.flagsChanged(with: conflictingPress)
        mainModifiersRecorder.flagsChanged(with: conflictingRelease)

        XCTAssertEqual(rejectedCandidate?.field, .mainModifiers)
        XCTAssertEqual(
            rejectedCandidate?.values.hotkeyPrimaryModifierRaw,
            "option+shift"
        )
        XCTAssertEqual(state.hotkeyPrimaryModifierRaw, "option")
        XCTAssertEqual(mainModifiersRecorder.recordedKeys, [.option])
    }

    @MainActor
    func testHotkeySettingsCardShowsCenteredConflictWhileProjectingCurrentSelection() throws {
        var state = HotkeySettingsCardState(
            hotkeyPrimaryModifierRaw: SwitcherHotkeyKey.option.rawValue,
            hotkeyMainKeyRaw: SwitcherHotkeyKey.tab.rawValue,
            hotkeyQuitKeyRaw: SwitcherHotkeyKey.z.rawValue,
            inAppWindowHotkeyBaseKeysRaw: "control",
            inAppWindowHotkeyMainKeysRaw: "space",
            commandTabTakeoverRegistrationState: .inactive,
            accessibilityTrusted: true,
            appLanguageRaw: AppLanguage.simplifiedChinese.rawValue,
            hotkeyConflict: HotkeySettingsConflictPresentation(
                field: .mainModifiers,
                conflict: .mainAndReverseModifier
            )
        )
        let view = HotkeySettingsCardAppKitView()
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 420)

        view.update(with: state)
        view.layoutSubtreeIfNeeded()

        let conflictLabel: NSTextField = try XCTUnwrap(
            hotkeyConflictDescendant(
                in: view,
                identifier: "flowtab.settings.hotkey.main-modifiers.conflict-status"
            )
        )
        let reverseConflictLabel: NSTextField = try XCTUnwrap(
            hotkeyConflictDescendant(
                in: view,
                identifier: "flowtab.settings.hotkey.main-reverse-modifiers.conflict-status"
            )
        )
        let mainModifiersRecorder: FlowSettingsShortcutRecorderControl = try XCTUnwrap(
            hotkeyConflictDescendant(
                in: view,
                identifier: "flowtab.settings.hotkey.main-modifiers"
            )
        )

        XCTAssertFalse(conflictLabel.isHidden)
        XCTAssertEqual(conflictLabel.stringValue, AppStrings.text(.hotkeyConflict))
        XCTAssertEqual(conflictLabel.alignment, .center)
        XCTAssertTrue(reverseConflictLabel.isHidden)
        XCTAssertEqual(
            mainModifiersRecorder.accessibilityHelp(),
            AppStrings.text(.hotkeyConflict)
        )
        XCTAssertEqual(mainModifiersRecorder.recordedKeys, [.option])
        let conflictFrame = view.convert(conflictLabel.bounds, from: conflictLabel)
        let controlFrame = view.convert(
            mainModifiersRecorder.bounds,
            from: mainModifiersRecorder
        )
        XCTAssertEqual(conflictFrame.midX, controlFrame.midX, accuracy: 1)
        XCTAssertLessThanOrEqual(conflictFrame.maxY, controlFrame.minY + 1)

        state.hotkeyConflict = nil
        view.update(with: state)
        XCTAssertTrue(conflictLabel.isHidden)
        XCTAssertNil(mainModifiersRecorder.accessibilityHelp())
    }

    @MainActor
    func testHotkeyConflictFeedbackUsesMicroTypography() throws {
        let state = HotkeySettingsCardState(
            hotkeyPrimaryModifierRaw: SwitcherHotkeyKey.option.rawValue,
            hotkeyMainKeyRaw: SwitcherHotkeyKey.tab.rawValue,
            hotkeyQuitKeyRaw: SwitcherHotkeyKey.z.rawValue,
            inAppWindowHotkeyBaseKeysRaw: "control",
            inAppWindowHotkeyMainKeysRaw: "space",
            commandTabTakeoverRegistrationState: .inactive,
            accessibilityTrusted: true,
            appLanguageRaw: AppLanguage.simplifiedChinese.rawValue,
            hotkeyConflict: HotkeySettingsConflictPresentation(
                field: .mainModifiers,
                conflict: .mainAndReverseModifier
            )
        )
        let view = HotkeySettingsCardAppKitView()
        view.update(with: state)
        let conflictLabel: NSTextField = try XCTUnwrap(
            hotkeyConflictDescendant(
                in: view,
                identifier: "flowtab.settings.hotkey.main-modifiers.conflict-status"
            )
        )
        let expectedFont = FlowTypography.appKit(.micro)

        XCTAssertEqual(conflictLabel.font?.pointSize, expectedFont.pointSize)
        XCTAssertEqual(conflictLabel.font?.fontName, expectedFont.fontName)
        XCTAssertEqual(
            AppStrings.text(.hotkeyConflict, language: .english),
            "Already in use"
        )
    }

    func testPermissionlessGlobalSwitchingCompatibilityUsesFinalShortcuts() {
        let cases: [(SwitcherHotkeyConfiguration, Bool)] = [
            (
                SwitcherHotkeyConfiguration(
                    baseKeys: [.option],
                    reverseKeys: [.shift],
                    mainKeys: [.tab],
                    quitKeys: [.q]
                ),
                true
            ),
            (
                SwitcherHotkeyConfiguration(
                    baseKeys: [.command, .control, .option],
                    reverseKeys: [.shift],
                    mainKeys: [.f6],
                    quitKeys: [.q, .w]
                ),
                true
            ),
            (
                SwitcherHotkeyConfiguration(
                    baseKeys: [.control, .w],
                    reverseKeys: [.shift],
                    mainKeys: [.tab],
                    quitKeys: [.q]
                ),
                false
            ),
            (
                SwitcherHotkeyConfiguration(
                    baseKeys: [.tab],
                    reverseKeys: [.shift],
                    mainKeys: [],
                    quitKeys: [.q]
                ),
                false
            ),
            (
                SwitcherHotkeyConfiguration(
                    baseKeys: [.control],
                    reverseKeys: [.shift, .w],
                    mainKeys: [.tab],
                    quitKeys: [.q]
                ),
                false
            )
        ]

        for (configuration, expected) in cases {
            XCTAssertEqual(
                configuration.supportsPermissionlessGlobalSwitching,
                expected,
                configuration.mainShortcutText
                    + " / "
                    + configuration.backwardShortcutText
            )
        }
    }

    func testHotkeySettingsChangeTransactionAppliesAccessibilityTierAtomically() {
        let arbitraryValues = AppKitSettingsHotkeyRawValues(
            hotkeyPrimaryModifierRaw: "control+w",
            hotkeyReverseModifiersRaw: "shift",
            hotkeyMainKeyRaw: "tab",
            hotkeyQuitKeyRaw: "q",
            inAppWindowHotkeyBaseKeysRaw: "option",
            inAppWindowHotkeyReverseKeysRaw: "shift",
            inAppWindowHotkeyMainKeysRaw: "space"
        )
        let candidate = HotkeySettingsChangeCandidate(
            field: .mainModifiers,
            values: arbitraryValues
        )
        var deniedCommit: HotkeyRegistrationRequest?

        XCTAssertEqual(
            HotkeySettingsChangeTransaction.apply(
                candidate,
                accessibilityTrusted: false
            ) { deniedCommit = $0 },
            .accessibilityRequired
        )
        XCTAssertNil(deniedCommit)

        var trustedCommit: HotkeyRegistrationRequest?
        let trustedResult = HotkeySettingsChangeTransaction.apply(
            candidate,
            accessibilityTrusted: true
        ) { trustedCommit = $0 }
        guard case let .applied(request) = trustedResult else {
            return XCTFail("Expected trusted arbitrary key set to commit")
        }
        XCTAssertEqual(request.mainConfiguration.baseKeys, [.control, .w])
        XCTAssertEqual(trustedCommit, request)
    }

    func testHotkeySettingsChangeTransactionKeepsQuitArbitraryWithoutAccessibility() {
        let candidate = HotkeySettingsChangeCandidate(
            field: .quitKey,
            values: AppKitSettingsHotkeyRawValues(
                hotkeyPrimaryModifierRaw: "option",
                hotkeyReverseModifiersRaw: "shift",
                hotkeyMainKeyRaw: "tab",
                hotkeyQuitKeyRaw: "q+w",
                inAppWindowHotkeyBaseKeysRaw: "control",
                inAppWindowHotkeyReverseKeysRaw: "shift",
                inAppWindowHotkeyMainKeysRaw: "space"
            )
        )
        var committed: HotkeyRegistrationRequest?

        let result = HotkeySettingsChangeTransaction.apply(
            candidate,
            accessibilityTrusted: false
        ) { committed = $0 }

        guard case let .applied(request) = result else {
            return XCTFail("Expected panel-local quit shortcut to commit")
        }
        XCTAssertEqual(request.mainConfiguration.quitKeys, [.q, .w])
        XCTAssertEqual(committed, request)
    }

    func testHotkeySettingsChangeTransactionKeepsConflictPrecedence() {
        let candidate = HotkeySettingsChangeCandidate(
            field: .mainModifiers,
            values: AppKitSettingsHotkeyRawValues(
                hotkeyPrimaryModifierRaw: "option+shift+w",
                hotkeyReverseModifiersRaw: "shift",
                hotkeyMainKeyRaw: "tab",
                hotkeyQuitKeyRaw: "q",
                inAppWindowHotkeyBaseKeysRaw: "control",
                inAppWindowHotkeyReverseKeysRaw: "shift",
                inAppWindowHotkeyMainKeysRaw: "space"
            )
        )

        XCTAssertEqual(
            HotkeySettingsChangeTransaction.apply(
                candidate,
                accessibilityTrusted: false,
                commit: { _ in XCTFail("Conflict must not commit") }
            ),
            .conflict(.mainAndReverseModifier)
        )
    }

    @MainActor
    func testHotkeySettingsCardShowsRejectedModifierFieldValidation() throws {
        let state = HotkeySettingsCardState(
            hotkeyPrimaryModifierRaw: "option",
            hotkeyMainKeyRaw: "tab",
            hotkeyQuitKeyRaw: "q",
            inAppWindowHotkeyBaseKeysRaw: "control",
            inAppWindowHotkeyMainKeysRaw: "tab",
            commandTabTakeoverRegistrationState: .inactive,
            accessibilityTrusted: false,
            appLanguageRaw: AppLanguage.simplifiedChinese.rawValue,
            hotkeyPermissionRequirement:
                HotkeySettingsPermissionPresentation(
                    field: .mainModifiers
                )
        )
        let view = HotkeySettingsCardAppKitView()
        view.update(with: state)
        let validationLabel: NSTextField = try XCTUnwrap(
            hotkeyConflictDescendant(
                in: view,
                identifier:
                    "flowtab.settings.hotkey.main-modifiers.conflict-status"
            )
        )
        let mainRecorder: FlowSettingsShortcutRecorderControl = try XCTUnwrap(
            hotkeyConflictDescendant(
                in: view,
                identifier: "flowtab.settings.hotkey.main-modifiers"
            )
        )

        XCTAssertEqual(
            validationLabel.stringValue,
            AppStrings.text(.hotkeyModifierPermissionlessRequirement)
        )
        XCTAssertEqual(
            mainRecorder.accessibilityHelp(),
            AppStrings.text(.hotkeyModifierPermissionlessRequirement)
        )
        XCTAssertEqual(mainRecorder.recordedKeys, [.option])
    }

    func testDeniedHotkeyTransactionValidatesOnlyEditedField() {
        let screenshotQuitKeys = SwitcherHotkeyKeySet([
            .r,
            .t,
            SwitcherHotkeyKey(keyCode: 21)
        ])
        let screenshotValues = AppKitSettingsHotkeyRawValues(
            hotkeyPrimaryModifierRaw: "option+w",
            hotkeyReverseModifiersRaw: "shift+c",
            hotkeyMainKeyRaw: "e+tab",
            hotkeyQuitKeyRaw: screenshotQuitKeys.rawValue,
            inAppWindowHotkeyBaseKeysRaw: "control",
            inAppWindowHotkeyReverseKeysRaw: "command",
            inAppWindowHotkeyMainKeysRaw: "space"
        )
        let mainKeyCandidate = HotkeySettingsChangeCandidate(
            field: .mainKey,
            values: AppKitSettingsHotkeyRawValues(
                hotkeyPrimaryModifierRaw:
                    screenshotValues.hotkeyPrimaryModifierRaw,
                hotkeyReverseModifiersRaw:
                    screenshotValues.hotkeyReverseModifiersRaw,
                hotkeyMainKeyRaw: "tab",
                hotkeyQuitKeyRaw: screenshotValues.hotkeyQuitKeyRaw,
                inAppWindowHotkeyBaseKeysRaw:
                    screenshotValues.inAppWindowHotkeyBaseKeysRaw,
                inAppWindowHotkeyReverseKeysRaw:
                    screenshotValues.inAppWindowHotkeyReverseKeysRaw,
                inAppWindowHotkeyMainKeysRaw:
                    screenshotValues.inAppWindowHotkeyMainKeysRaw
            )
        )
        var committed: HotkeyRegistrationRequest?

        let result = HotkeySettingsChangeTransaction.apply(
            mainKeyCandidate,
            accessibilityTrusted: false
        ) { committed = $0 }

        guard case let .applied(request) = result else {
            return XCTFail(
                "Expected a valid main-key field to commit independently"
            )
        }
        XCTAssertEqual(request.mainConfiguration.mainKeys, [.tab])
        XCTAssertEqual(request.mainConfiguration.baseKeys, [.option, .w])
        XCTAssertEqual(request.mainConfiguration.reverseKeys, [.shift, .c])
        XCTAssertEqual(request.mainConfiguration.quitKeys, screenshotQuitKeys)
        XCTAssertEqual(committed, request)
    }

    func testPermissionlessHotkeyFieldPolicyMatchesFieldRoles() {
        let cases: [(
            HotkeySettingsField,
            SwitcherHotkeyKeySet,
            Bool
        )] = [
            (.mainModifiers, [.option], true),
            (.mainModifiers, [.command, .control, .option], true),
            (.mainModifiers, [.control, .w], false),
            (.mainModifiers, SwitcherHotkeyKeySet(), false),
            (.mainReverseModifiers, [.shift], true),
            (.mainReverseModifiers, [.shift, .c], false),
            (.mainKey, [.tab], true),
            (.mainKey, [.control, .w], true),
            (.mainKey, [.command, .option, .f6], true),
            (.mainKey, [.e, .tab], false),
            (.mainKey, [.shift], false),
            (.quitKey, [.r, .t, SwitcherHotkeyKey(keyCode: 21)], true)
        ]

        for (field, keys, expected) in cases {
            XCTAssertEqual(
                HotkeySettingsPermissionlessFieldPolicy
                    .allows(keys: keys, for: field),
                expected,
                "field=\(field.rawValue) keys=\(keys.rawValue)"
            )
        }
    }

    @MainActor
    func testDeniedHotkeyCardMarksEveryInvalidFieldWithoutGroupStatus() throws {
        let screenshotQuitKeys = SwitcherHotkeyKeySet([
            .r,
            .t,
            SwitcherHotkeyKey(keyCode: 21)
        ])
        let state = HotkeySettingsCardState(
            hotkeyPrimaryModifierRaw: "option+w",
            hotkeyReverseModifiersRaw: "shift+c",
            hotkeyMainKeyRaw: "e+tab",
            hotkeyQuitKeyRaw: screenshotQuitKeys.rawValue,
            inAppWindowHotkeyBaseKeysRaw: "control",
            inAppWindowHotkeyMainKeysRaw: "space",
            commandTabTakeoverRegistrationState: .inactive,
            accessibilityTrusted: false,
            appLanguageRaw: AppLanguage.simplifiedChinese.rawValue
        )
        let view = HotkeySettingsCardAppKitView()
        view.update(with: state)

        for fieldIdentifier in [
            "flowtab.settings.hotkey.main-modifiers",
            "flowtab.settings.hotkey.main-reverse-modifiers"
        ] {
            let label: NSTextField = try XCTUnwrap(
                hotkeyConflictDescendant(
                    in: view,
                    identifier: "\(fieldIdentifier).conflict-status"
                )
            )
            XCTAssertFalse(label.isHidden)
            XCTAssertEqual(label.stringValue, "未授权时仅支持修饰键")
        }
        let mainKeyLabel: NSTextField = try XCTUnwrap(
            hotkeyConflictDescendant(
                in: view,
                identifier:
                    "flowtab.settings.hotkey.main-key.conflict-status"
            )
        )
        XCTAssertFalse(mainKeyLabel.isHidden)
        XCTAssertEqual(
            mainKeyLabel.stringValue,
            "未授权时仅支持任意修饰键加一个普通键或功能键"
        )
        XCTAssertNil(
            hotkeyConflictDescendant(
                in: view,
                identifier: "flowtab.settings.hotkey.main-accessibility-status",
                as: NSTextField.self
            ) as NSTextField?
        )
    }

    private func hotkeyValues(
        mainModifier: SwitcherHotkeyKey,
        mainKey: SwitcherHotkeyKey,
        quitKey: SwitcherHotkeyKey,
        inAppModifier: SwitcherHotkeyKey,
        inAppKey: SwitcherHotkeyKey
    ) -> AppKitSettingsHotkeyRawValues {
        AppKitSettingsHotkeyRawValues(
            hotkeyPrimaryModifierRaw: mainModifier.rawValue,
            hotkeyReverseModifiersRaw: "shift",
            hotkeyMainKeyRaw: mainKey.rawValue,
            hotkeyQuitKeyRaw: quitKey.rawValue,
            inAppWindowHotkeyBaseKeysRaw: inAppModifier.rawValue,
            inAppWindowHotkeyReverseKeysRaw: "shift",
            inAppWindowHotkeyMainKeysRaw: inAppKey.rawValue
        )
    }

    private func hotkeyConflictDescendant<T: NSView>(
        in view: NSView,
        identifier: String,
        as type: T.Type = T.self
    ) -> T? {
        if view.identifier?.rawValue == identifier, let match = view as? T {
            return match
        }
        for subview in view.subviews {
            if let match = hotkeyConflictDescendant(
                in: subview,
                identifier: identifier,
                as: type
            ) {
                return match
            }
        }
        return nil
    }

    private func hotkeyConflictDescendant<T: NSView>(
        in view: NSView,
        as type: T.Type = T.self
    ) -> T? {
        if let match = view as? T {
            return match
        }
        for subview in view.subviews {
            if let match = hotkeyConflictDescendant(in: subview, as: type) {
                return match
            }
        }
        return nil
    }
}

@MainActor
private final class HotkeySettingsBridgeBindingState {
    var showInCommandTab = false
    var themeModeRaw = ThemeMode.followSystem.rawValue
    var appLanguageRaw = AppLanguage.simplifiedChinese.rawValue
    var autoRestoreMinimizedWindowOnSwitch = true
    var hideMinimizedAppsFromAppLayer = false
    var showPermissionReminder = true
    var allowLaunchAtLogin = false
    var searchEnabled = true
    var searchDefaultScopeRaw = SwitcherSearchScope.app.rawValue
    var hotkeyPrimaryModifierRaw = SwitcherHotkeyKey.option.rawValue
    var hotkeyReverseModifiersRaw = "shift"
    var hotkeyMainKeyRaw = SwitcherHotkeyKey.tab.rawValue
    var hotkeyQuitKeyRaw = SwitcherHotkeyKey.z.rawValue
    var inAppWindowHotkeyBaseKeysRaw = "control"
    var inAppWindowHotkeyReverseKeysRaw = "shift"
    var inAppWindowHotkeyMainKeysRaw = "space"

    func binding<Value>(
        _ keyPath: ReferenceWritableKeyPath<HotkeySettingsBridgeBindingState, Value>
    ) -> Binding<Value> {
        Binding(
            get: { self[keyPath: keyPath] },
            set: { self[keyPath: keyPath] = $0 }
        )
    }
}
