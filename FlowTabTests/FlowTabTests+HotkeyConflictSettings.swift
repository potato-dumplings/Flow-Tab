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
        XCTAssertEqual(request.mainConfiguration.primaryModifier, .command)
        XCTAssertEqual(request.mainConfiguration.mainKey, .space)
        XCTAssertEqual(request.mainConfiguration.quitKey, .z)
        XCTAssertEqual(request.inAppWindowConfiguration.primaryModifier, .control)
        XCTAssertEqual(request.inAppWindowConfiguration.mainKey, .b)
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
            hotkeyMainKeyRaw: state.binding(\.hotkeyMainKeyRaw),
            hotkeyQuitKeyRaw: state.binding(\.hotkeyQuitKeyRaw),
            inAppWindowHotkeyPrimaryModifierRaw: state.binding(
                \.inAppWindowHotkeyPrimaryModifierRaw
            ),
            inAppWindowHotkeyMainKeyRaw: state.binding(\.inAppWindowHotkeyMainKeyRaw),
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

        let quitSelect: FlowSettingsSelectControl = try XCTUnwrap(
            hotkeyConflictDescendant(
                in: hostedView,
                identifier: "flowtab.settings.hotkey.quit-key"
            )
        )
        let quitDropdown: FlowDropdownControl = try XCTUnwrap(
            hotkeyConflictDescendant(in: quitSelect, as: FlowDropdownControl.self)
        )

        quitDropdown.selectOptionForTesting(SwitcherHotkeyKey.tab.rawValue)

        XCTAssertEqual(rejectedCandidate?.field, .quitKey)
        XCTAssertEqual(
            rejectedCandidate?.values.hotkeyQuitKeyRaw,
            SwitcherHotkeyKey.tab.rawValue
        )
        XCTAssertEqual(state.hotkeyQuitKeyRaw, SwitcherHotkeyKey.z.rawValue)
        XCTAssertEqual(quitDropdown.selectedIdentifierForTesting, SwitcherHotkeyKey.z.rawValue)
    }

    @MainActor
    func testHotkeySettingsCardShowsCenteredConflictWhileProjectingCurrentSelection() throws {
        var state = HotkeySettingsCardState(
            hotkeyPrimaryModifierRaw: SwitcherPrimaryModifier.option.rawValue,
            hotkeyMainKeyRaw: SwitcherHotkeyKey.tab.rawValue,
            hotkeyQuitKeyRaw: SwitcherHotkeyKey.z.rawValue,
            inAppWindowHotkeyPrimaryModifierRaw: SwitcherPrimaryModifier.control.rawValue,
            inAppWindowHotkeyMainKeyRaw: SwitcherHotkeyKey.space.rawValue,
            commandTabTakeoverRegistrationState: .inactive,
            accessibilityTrusted: true,
            appLanguageRaw: AppLanguage.simplifiedChinese.rawValue,
            hotkeyConflict: HotkeySettingsConflictPresentation(
                field: .quitKey,
                conflict: .mainAndQuit
            )
        )
        let view = HotkeySettingsCardAppKitView()
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 420)

        view.update(with: state)
        view.layoutSubtreeIfNeeded()

        let conflictLabel: NSTextField = try XCTUnwrap(
            hotkeyConflictDescendant(
                in: view,
                identifier: "flowtab.settings.hotkey.quit-key.conflict-status"
            )
        )
        let mainKeyConflictLabel: NSTextField = try XCTUnwrap(
            hotkeyConflictDescendant(
                in: view,
                identifier: "flowtab.settings.hotkey.main-key.conflict-status"
            )
        )
        let quitSelect: FlowSettingsSelectControl = try XCTUnwrap(
            hotkeyConflictDescendant(
                in: view,
                identifier: "flowtab.settings.hotkey.quit-key"
            )
        )
        let quitDropdown: FlowDropdownControl = try XCTUnwrap(
            hotkeyConflictDescendant(in: quitSelect, as: FlowDropdownControl.self)
        )

        XCTAssertFalse(conflictLabel.isHidden)
        XCTAssertEqual(conflictLabel.stringValue, AppStrings.text(.hotkeyConflict))
        XCTAssertEqual(conflictLabel.alignment, .center)
        XCTAssertTrue(mainKeyConflictLabel.isHidden)
        XCTAssertEqual(quitSelect.accessibilityHelp(), AppStrings.text(.hotkeyConflict))
        XCTAssertEqual(quitDropdown.selectedIdentifierForTesting, SwitcherHotkeyKey.z.rawValue)
        let conflictFrame = view.convert(conflictLabel.bounds, from: conflictLabel)
        let quitControlFrame = view.convert(quitSelect.bounds, from: quitSelect)
        XCTAssertEqual(conflictFrame.midX, quitControlFrame.midX, accuracy: 1)
        XCTAssertLessThanOrEqual(conflictFrame.maxY, quitControlFrame.minY + 1)

        state.hotkeyConflict = nil
        view.update(with: state)
        XCTAssertTrue(conflictLabel.isHidden)
        XCTAssertNil(quitSelect.accessibilityHelp())
    }

    @MainActor
    func testHotkeyConflictFeedbackUsesMicroTypography() throws {
        let state = HotkeySettingsCardState(
            hotkeyPrimaryModifierRaw: SwitcherPrimaryModifier.option.rawValue,
            hotkeyMainKeyRaw: SwitcherHotkeyKey.tab.rawValue,
            hotkeyQuitKeyRaw: SwitcherHotkeyKey.z.rawValue,
            inAppWindowHotkeyPrimaryModifierRaw: SwitcherPrimaryModifier.control.rawValue,
            inAppWindowHotkeyMainKeyRaw: SwitcherHotkeyKey.space.rawValue,
            commandTabTakeoverRegistrationState: .inactive,
            accessibilityTrusted: true,
            appLanguageRaw: AppLanguage.simplifiedChinese.rawValue,
            hotkeyConflict: HotkeySettingsConflictPresentation(
                field: .quitKey,
                conflict: .mainAndQuit
            )
        )
        let view = HotkeySettingsCardAppKitView()
        view.update(with: state)
        let conflictLabel: NSTextField = try XCTUnwrap(
            hotkeyConflictDescendant(
                in: view,
                identifier: "flowtab.settings.hotkey.quit-key.conflict-status"
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
        mainModifier: SwitcherPrimaryModifier,
        mainKey: SwitcherHotkeyKey,
        quitKey: SwitcherHotkeyKey,
        inAppModifier: SwitcherPrimaryModifier,
        inAppKey: SwitcherHotkeyKey
    ) -> AppKitSettingsHotkeyRawValues {
        AppKitSettingsHotkeyRawValues(
            hotkeyPrimaryModifierRaw: mainModifier.rawValue,
            hotkeyMainKeyRaw: mainKey.rawValue,
            hotkeyQuitKeyRaw: quitKey.rawValue,
            inAppWindowHotkeyPrimaryModifierRaw: inAppModifier.rawValue,
            inAppWindowHotkeyMainKeyRaw: inAppKey.rawValue
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
    var hotkeyPrimaryModifierRaw = SwitcherPrimaryModifier.option.rawValue
    var hotkeyMainKeyRaw = SwitcherHotkeyKey.tab.rawValue
    var hotkeyQuitKeyRaw = SwitcherHotkeyKey.z.rawValue
    var inAppWindowHotkeyPrimaryModifierRaw = SwitcherPrimaryModifier.control.rawValue
    var inAppWindowHotkeyMainKeyRaw = SwitcherHotkeyKey.space.rawValue

    func binding<Value>(
        _ keyPath: ReferenceWritableKeyPath<HotkeySettingsBridgeBindingState, Value>
    ) -> Binding<Value> {
        Binding(
            get: { self[keyPath: keyPath] },
            set: { self[keyPath: keyPath] = $0 }
        )
    }
}
