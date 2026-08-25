import AppKit
import SwiftUI

struct AppKitSettingsPageContent: NSViewRepresentable {
    let isActive: Bool
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
    @Binding var hotkeyReverseModifiersRaw: String
    @Binding var hotkeyMainKeyRaw: String
    @Binding var hotkeyQuitKeyRaw: String
    @Binding var inAppWindowHotkeyBaseKeysRaw: String
    @Binding var inAppWindowHotkeyReverseKeysRaw: String
    @Binding var inAppWindowHotkeyMainKeysRaw: String
    let commandTabTakeoverRegistrationState: CommandTabTakeoverRegistrationState
    let hotkeyConflict: HotkeySettingsConflictPresentation?
    var hotkeyPermissionRequirement:
        HotkeySettingsPermissionPresentation? = nil
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
        let hotkeyReverseModifiersRaw = $hotkeyReverseModifiersRaw
        let hotkeyMainKeyRaw = $hotkeyMainKeyRaw
        let hotkeyQuitKeyRaw = $hotkeyQuitKeyRaw
        let inAppWindowHotkeyBaseKeysRaw =
            $inAppWindowHotkeyBaseKeysRaw
        let inAppWindowHotkeyReverseKeysRaw =
            $inAppWindowHotkeyReverseKeysRaw
        let inAppWindowHotkeyMainKeysRaw =
            $inAppWindowHotkeyMainKeysRaw
        let pageView = nsView.pageView
        let currentHotkeyValues = {
            AppKitSettingsHotkeyRawValues(
                hotkeyPrimaryModifierRaw: hotkeyPrimaryModifierRaw.wrappedValue,
                hotkeyReverseModifiersRaw: hotkeyReverseModifiersRaw.wrappedValue,
                hotkeyMainKeyRaw: hotkeyMainKeyRaw.wrappedValue,
                hotkeyQuitKeyRaw: hotkeyQuitKeyRaw.wrappedValue,
                inAppWindowHotkeyBaseKeysRaw:
                    inAppWindowHotkeyBaseKeysRaw.wrappedValue,
                inAppWindowHotkeyReverseKeysRaw:
                    inAppWindowHotkeyReverseKeysRaw.wrappedValue,
                inAppWindowHotkeyMainKeysRaw:
                    inAppWindowHotkeyMainKeysRaw.wrappedValue
            )
        }
        let updateHotkeyContent = { [weak pageView] in
            pageView?.updateHotkeyContent(with: currentHotkeyValues())
        }

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
        pageView.onMainModifiersChanged = {
            onHotkeyChanged(
                HotkeySettingsChangeCandidate(
                    field: .mainModifiers,
                    values: currentHotkeyValues().replacing(
                        .mainModifiers,
                        with: $0.rawValue
                    )
                )
            )
            updateHotkeyContent()
        }
        pageView.onMainReverseModifiersChanged = {
            onHotkeyChanged(
                HotkeySettingsChangeCandidate(
                    field: .mainReverseModifiers,
                    values: currentHotkeyValues().replacing(
                        .mainReverseModifiers,
                        with: $0.rawValue
                    )
                )
            )
            updateHotkeyContent()
        }
        pageView.onMainKeyChanged = {
            onHotkeyChanged(
                HotkeySettingsChangeCandidate(
                    field: .mainKey,
                    values: currentHotkeyValues().replacing(
                        .mainKey,
                        with: $0.rawValue
                    )
                )
            )
            updateHotkeyContent()
        }
        pageView.onQuitKeyChanged = {
            onHotkeyChanged(
                HotkeySettingsChangeCandidate(
                    field: .quitKey,
                    values: currentHotkeyValues().replacing(
                        .quitKey,
                        with: $0.rawValue
                    )
                )
            )
            updateHotkeyContent()
        }
        pageView.onInAppBaseKeysChanged = {
            onHotkeyChanged(
                HotkeySettingsChangeCandidate(
                    field: .inAppBaseKeys,
                    values: currentHotkeyValues().replacing(
                        .inAppBaseKeys,
                        with: $0.rawValue
                    )
                )
            )
            updateHotkeyContent()
        }
        pageView.onInAppReverseModifiersChanged = {
            onHotkeyChanged(
                HotkeySettingsChangeCandidate(
                    field: .inAppReverseModifiers,
                    values: currentHotkeyValues().replacing(
                        .inAppReverseModifiers,
                        with: $0.rawValue
                    )
                )
            )
            updateHotkeyContent()
        }
        pageView.onInAppMainKeysChanged = {
            onHotkeyChanged(
                HotkeySettingsChangeCandidate(
                    field: .inAppMainKeys,
                    values: currentHotkeyValues().replacing(
                        .inAppMainKeys,
                        with: $0.rawValue
                    )
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
                hotkeyReverseModifiersRaw: hotkeyReverseModifiersRaw.wrappedValue,
                hotkeyMainKeyRaw: hotkeyMainKeyRaw.wrappedValue,
                hotkeyQuitKeyRaw: hotkeyQuitKeyRaw.wrappedValue,
                inAppWindowHotkeyBaseKeysRaw:
                    inAppWindowHotkeyBaseKeysRaw.wrappedValue,
                inAppWindowHotkeyReverseKeysRaw:
                    inAppWindowHotkeyReverseKeysRaw.wrappedValue,
                inAppWindowHotkeyMainKeysRaw:
                    inAppWindowHotkeyMainKeysRaw.wrappedValue,
                commandTabTakeoverRegistrationState: commandTabTakeoverRegistrationState,
                accessibilityTrusted: accessibilityTrusted,
                screenCaptureTrusted: screenCaptureTrusted,
                targetNSAppearanceName: presentationContext.targetNSAppearanceName,
                hotkeyConflict: hotkeyConflict,
                hotkeyPermissionRequirement:
                    hotkeyPermissionRequirement
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
            hotkeyPrimaryModifierRaw: field == .mainModifiers
                ? rawValue : hotkeyPrimaryModifierRaw,
            hotkeyReverseModifiersRaw: field == .mainReverseModifiers
                ? rawValue : hotkeyReverseModifiersRaw,
            hotkeyMainKeyRaw: field == .mainKey ? rawValue : hotkeyMainKeyRaw,
            hotkeyQuitKeyRaw: field == .quitKey ? rawValue : hotkeyQuitKeyRaw,
            inAppWindowHotkeyBaseKeysRaw:
                field == .inAppBaseKeys
                ? rawValue : inAppWindowHotkeyBaseKeysRaw,
            inAppWindowHotkeyReverseKeysRaw:
                field == .inAppReverseModifiers
                ? rawValue : inAppWindowHotkeyReverseKeysRaw,
            inAppWindowHotkeyMainKeysRaw:
                field == .inAppMainKeys
                ? rawValue : inAppWindowHotkeyMainKeysRaw
        )
    }
}
