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
            [.control, .b]
        )
        XCTAssertEqual(request.inAppWindowConfiguration.reverseKeys, [.shift])
    }

    @MainActor
    func testSettingsBridgeKeepsCurrentHotkeyBindingsWhenCandidateIsRejected() throws {
        let state = HotkeySettingsBridgeBindingState()
        var rejectedCandidate: HotkeySettingsChangeCandidate?

        let content = AppKitSettingsPageContent(
            isActive: true,
            showShortcutHint: state.binding(\.showShortcutHint),
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
            inAppWindowHotkeyShortcutKeysRaw: state.binding(
                \.inAppWindowHotkeyShortcutKeysRaw
            ),
            inAppWindowHotkeyReverseKeysRaw: state.binding(
                \.inAppWindowHotkeyReverseKeysRaw
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
            inAppWindowHotkeyShortcutKeysRaw: "control+space",
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
            inAppWindowHotkeyShortcutKeysRaw: "control+space",
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
            inAppWindowHotkeyShortcutKeysRaw:
                SwitcherHotkeyKeySet([inAppModifier, inAppKey]).rawValue,
            inAppWindowHotkeyReverseKeysRaw: "shift"
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
    var showShortcutHint = true
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
    var inAppWindowHotkeyShortcutKeysRaw = "control+space"
    var inAppWindowHotkeyReverseKeysRaw = "shift"

    func binding<Value>(
        _ keyPath: ReferenceWritableKeyPath<HotkeySettingsBridgeBindingState, Value>
    ) -> Binding<Value> {
        Binding(
            get: { self[keyPath: keyPath] },
            set: { self[keyPath: keyPath] = $0 }
        )
    }
}
