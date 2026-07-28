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
    let accessibilityTrusted: Bool
    let screenCaptureTrusted: Bool
    let onWindowLayerAutoEnterDelayTextChanged: (String) -> Void
    let onWindowLayerAutoEnterDelayTextCommitted: () -> Void
    let onWindowLayerAutoEnterDelayEditingChanged: (Bool) -> Void
    let onMainHotkeyChanged: (AppKitSettingsHotkeyRawValues) -> Void
    let onQuitHotkeyChanged: (AppKitSettingsHotkeyRawValues) -> Void
    let onInAppWindowHotkeyChanged: (AppKitSettingsHotkeyRawValues) -> Void
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
        pageView.onHotkeyPrimaryModifierChanged = {
            hotkeyPrimaryModifierRaw.wrappedValue = $0
            onMainHotkeyChanged(currentHotkeyValues())
        }
        pageView.onHotkeyMainKeyChanged = {
            hotkeyMainKeyRaw.wrappedValue = $0
            onMainHotkeyChanged(currentHotkeyValues())
        }
        pageView.onHotkeyQuitKeyChanged = {
            hotkeyQuitKeyRaw.wrappedValue = $0
            onQuitHotkeyChanged(currentHotkeyValues())
        }
        pageView.onInAppWindowPrimaryModifierChanged = {
            inAppWindowHotkeyPrimaryModifierRaw.wrappedValue = $0
            onInAppWindowHotkeyChanged(currentHotkeyValues())
        }
        pageView.onInAppWindowMainKeyChanged = {
            inAppWindowHotkeyMainKeyRaw.wrappedValue = $0
            onInAppWindowHotkeyChanged(currentHotkeyValues())
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
                targetNSAppearanceName: presentationContext.targetNSAppearanceName
            ),
            isActive: isActive
        )
    }
}
