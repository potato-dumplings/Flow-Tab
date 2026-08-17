import AppKit
import SwiftUI

struct AppKitSettingsPageContent: NSViewRepresentable {
    let isActive: Bool
    @Binding var showShortcutHint: Bool
    @Binding var showInCommandTab: Bool
    @Binding var themeModeRaw: String
    @Binding var appLanguageRaw: String
    let presentationContext: FlowPresentationContext
    let windowLayerAutoEnterDelayText: String
    @Binding var autoRestoreMinimizedWindowOnSwitch: Bool
    @Binding var hideMinimizedAppsFromAppLayer: Bool
    @Binding var showPermissionReminder: Bool
    @Binding var allowLaunchAtLogin: Bool
    @Binding var searchEnabled: Bool
    @Binding var searchDefaultScopeRaw: String
    let hiddenAppCount: Int
    @Binding var hotkeyPrimaryModifierRaw: String
    @Binding var hotkeyMainKeyRaw: String
    @Binding var hotkeyQuitKeyRaw: String
    @Binding var inAppWindowHotkeyPrimaryModifierRaw: String
    @Binding var inAppWindowHotkeyMainKeyRaw: String
    let commandTabTakeoverRegistrationState: CommandTabTakeoverRegistrationState
    let hotkeyConflict: HotkeySettingsConflictPresentation?
    let accessibilityTrusted: Bool
    let screenCaptureTrusted: Bool
    let onWindowLayerAutoEnterDelayTextChanged: (String) -> Void
    let onWindowLayerAutoEnterDelayTextCommitted: () -> Void
    let onWindowLayerAutoEnterDelayEditingChanged: (Bool) -> Void
    let onHotkeyChanged: (HotkeySettingsChangeCandidate) -> Void
    let onDismissHotkeyConflict: () -> Void
    let onLaunchAtLoginChanged: (Bool) -> Void
    let onManageAppVisibility: () -> Void
    let onAccessibilityAction: () -> Void
    let onScreenCaptureAction: () -> Void

    func makeNSView(context: Context) -> AppKitSettingsPageContainerView {
        AppKitSettingsPageContainerView()
    }

    func updateNSView(_ nsView: AppKitSettingsPageContainerView, context: Context) {
        let showShortcutHint = $showShortcutHint
        let showInCommandTab = $showInCommandTab
        let themeModeRaw = $themeModeRaw
        let appLanguageRaw = $appLanguageRaw
        let autoRestoreMinimizedWindowOnSwitch = $autoRestoreMinimizedWindowOnSwitch
        let hideMinimizedAppsFromAppLayer = $hideMinimizedAppsFromAppLayer
        let showPermissionReminder = $showPermissionReminder
        let allowLaunchAtLogin = $allowLaunchAtLogin
        let searchEnabled = $searchEnabled
        let searchDefaultScopeRaw = $searchDefaultScopeRaw
        let hotkeyPrimaryModifierRaw = $hotkeyPrimaryModifierRaw
        let hotkeyMainKeyRaw = $hotkeyMainKeyRaw
        let hotkeyQuitKeyRaw = $hotkeyQuitKeyRaw
        let inAppWindowHotkeyPrimaryModifierRaw = $inAppWindowHotkeyPrimaryModifierRaw
        let inAppWindowHotkeyMainKeyRaw = $inAppWindowHotkeyMainKeyRaw
        let pageView = nsView.pageView
        let currentHotkeyValues = {
            AppKitSettingsHotkeyRawValues(
                hotkeyPrimaryModifierRaw: hotkeyPrimaryModifierRaw.wrappedValue,
                hotkeyMainKeyRaw: hotkeyMainKeyRaw.wrappedValue,
                hotkeyQuitKeyRaw: hotkeyQuitKeyRaw.wrappedValue,
                inAppWindowHotkeyPrimaryModifierRaw: inAppWindowHotkeyPrimaryModifierRaw.wrappedValue,
                inAppWindowHotkeyMainKeyRaw: inAppWindowHotkeyMainKeyRaw.wrappedValue
            )
        }
        let updateHotkeyContent = { [weak pageView] in
            pageView?.updateHotkeyContent(with: currentHotkeyValues())
        }

        pageView.onShowShortcutHintChanged = { showShortcutHint.wrappedValue = $0 }
        pageView.onShowInCommandTabChanged = { showInCommandTab.wrappedValue = $0 }
        pageView.onThemeModeChanged = { themeModeRaw.wrappedValue = $0 }
        pageView.onAppLanguageChanged = { appLanguageRaw.wrappedValue = $0 }
        pageView.onWindowLayerAutoEnterDelayTextChanged = onWindowLayerAutoEnterDelayTextChanged
        pageView.onWindowLayerAutoEnterDelayTextCommitted = onWindowLayerAutoEnterDelayTextCommitted
        pageView.onWindowLayerAutoEnterDelayEditingChanged = onWindowLayerAutoEnterDelayEditingChanged
        pageView.onAutoRestoreMinimizedWindowOnSwitchChanged = {
            autoRestoreMinimizedWindowOnSwitch.wrappedValue = $0
        }
        pageView.onHideMinimizedAppsFromAppLayerChanged = {
            hideMinimizedAppsFromAppLayer.wrappedValue = $0
        }
        pageView.onSearchEnabledChanged = { searchEnabled.wrappedValue = $0 }
        pageView.onSearchDefaultScopeChanged = { searchDefaultScopeRaw.wrappedValue = $0 }
        pageView.onManageAppVisibility = onManageAppVisibility
        pageView.onDismissHotkeyConflict = onDismissHotkeyConflict
        pageView.onHotkeyPrimaryModifierChanged = {
            onHotkeyChanged(
                HotkeySettingsChangeCandidate(
                    field: .mainModifier,
                    values: currentHotkeyValues().replacing(.mainModifier, with: $0)
                )
            )
            updateHotkeyContent()
        }
        pageView.onHotkeyMainKeyChanged = {
            onHotkeyChanged(
                HotkeySettingsChangeCandidate(
                    field: .mainKey,
                    values: currentHotkeyValues().replacing(.mainKey, with: $0)
                )
            )
            updateHotkeyContent()
        }
        pageView.onHotkeyQuitKeyChanged = {
            onHotkeyChanged(
                HotkeySettingsChangeCandidate(
                    field: .quitKey,
                    values: currentHotkeyValues().replacing(.quitKey, with: $0)
                )
            )
            updateHotkeyContent()
        }
        pageView.onInAppWindowPrimaryModifierChanged = {
            onHotkeyChanged(
                HotkeySettingsChangeCandidate(
                    field: .inAppModifier,
                    values: currentHotkeyValues().replacing(.inAppModifier, with: $0)
                )
            )
            updateHotkeyContent()
        }
        pageView.onInAppWindowMainKeyChanged = {
            onHotkeyChanged(
                HotkeySettingsChangeCandidate(
                    field: .inAppKey,
                    values: currentHotkeyValues().replacing(.inAppKey, with: $0)
                )
            )
            updateHotkeyContent()
        }
        pageView.onShowPermissionReminderChanged = { showPermissionReminder.wrappedValue = $0 }
        pageView.onAllowLaunchAtLoginChanged = {
            allowLaunchAtLogin.wrappedValue = $0
            onLaunchAtLoginChanged($0)
        }
        pageView.onAccessibilityAction = onAccessibilityAction
        pageView.onScreenCaptureAction = onScreenCaptureAction
        nsView.update(
            with: AppKitSettingsPageState(
                showShortcutHint: showShortcutHint.wrappedValue,
                showInCommandTab: showInCommandTab.wrappedValue,
                themeModeRaw: themeModeRaw.wrappedValue,
                appLanguageRaw: appLanguageRaw.wrappedValue,
                windowLayerAutoEnterDelayText: windowLayerAutoEnterDelayText,
                autoRestoreMinimizedWindowOnSwitch: autoRestoreMinimizedWindowOnSwitch.wrappedValue,
                hideMinimizedAppsFromAppLayer: hideMinimizedAppsFromAppLayer.wrappedValue,
                showPermissionReminder: showPermissionReminder.wrappedValue,
                allowLaunchAtLogin: allowLaunchAtLogin.wrappedValue,
                searchEnabled: searchEnabled.wrappedValue,
                searchDefaultScopeRaw: searchDefaultScopeRaw.wrappedValue,
                hiddenAppCount: hiddenAppCount,
                hotkeyPrimaryModifierRaw: hotkeyPrimaryModifierRaw.wrappedValue,
                hotkeyMainKeyRaw: hotkeyMainKeyRaw.wrappedValue,
                hotkeyQuitKeyRaw: hotkeyQuitKeyRaw.wrappedValue,
                inAppWindowHotkeyPrimaryModifierRaw: inAppWindowHotkeyPrimaryModifierRaw.wrappedValue,
                inAppWindowHotkeyMainKeyRaw: inAppWindowHotkeyMainKeyRaw.wrappedValue,
                commandTabTakeoverRegistrationState: commandTabTakeoverRegistrationState,
                accessibilityTrusted: accessibilityTrusted,
                screenCaptureTrusted: screenCaptureTrusted,
                targetNSAppearanceName: presentationContext.targetNSAppearanceName,
                hotkeyConflict: hotkeyConflict
            ),
            isActive: isActive
        )
    }
}

private extension AppKitSettingsHotkeyRawValues {
    func replacing(
        _ field: HotkeySettingsField,
        with rawValue: String
    ) -> AppKitSettingsHotkeyRawValues {
        AppKitSettingsHotkeyRawValues(
            hotkeyPrimaryModifierRaw: field == .mainModifier
                ? rawValue : hotkeyPrimaryModifierRaw,
            hotkeyMainKeyRaw: field == .mainKey ? rawValue : hotkeyMainKeyRaw,
            hotkeyQuitKeyRaw: field == .quitKey ? rawValue : hotkeyQuitKeyRaw,
            inAppWindowHotkeyPrimaryModifierRaw: field == .inAppModifier
                ? rawValue : inAppWindowHotkeyPrimaryModifierRaw,
            inAppWindowHotkeyMainKeyRaw: field == .inAppKey
                ? rawValue : inAppWindowHotkeyMainKeyRaw
        )
    }
}
