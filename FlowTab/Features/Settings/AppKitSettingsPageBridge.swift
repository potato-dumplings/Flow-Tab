import AppKit
import SwiftUI

struct AppKitSettingsPageContent: NSViewRepresentable {
    let lifecycle: HomeRetainedTabLifecycle
    let isVisible: Bool
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

    func makeCoordinator() -> AppKitSettingsPageBridgeCoordinator {
        AppKitSettingsPageBridgeCoordinator()
    }

    func makeNSView(context: Context) -> AppKitSettingsPageContainerView {
        let container = AppKitSettingsPageContainerView()
        container.update(with: state)
        context.coordinator.update(with: self)
        context.coordinator.connect(to: container)
        return container
    }

    func updateNSView(_ nsView: AppKitSettingsPageContainerView, context: Context) {
        context.coordinator.update(with: self)
        context.coordinator.connect(to: nsView)
        nsView.update(with: state)
    }

    static func dismantleNSView(
        _ nsView: AppKitSettingsPageContainerView,
        coordinator: AppKitSettingsPageBridgeCoordinator
    ) {
        coordinator.stop()
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: AppKitSettingsPageContainerView,
        context: Context
    ) -> CGSize? {
        FlowFillViewportSizing.resolve(
            proposal: proposal,
            currentSize: nsView.bounds.size
        )
    }

    private var state: AppKitSettingsPageState {
        AppKitSettingsPageState(
            showInCommandTab: showInCommandTab,
            themeModeRaw: themeModeRaw,
            appLanguageRaw: appLanguageRaw,
            windowLayerAutoEnterDelayText: windowLayerAutoEnterDelayText,
            autoRestoreMinimizedWindowOnSwitch:
                autoRestoreMinimizedWindowOnSwitch,
            hideMinimizedAppsFromAppLayer:
                hideMinimizedAppsFromAppLayer,
            showPermissionReminder: showPermissionReminder,
            allowLaunchAtLogin: allowLaunchAtLogin,
            searchEnabled: searchEnabled,
            searchDefaultScopeRaw: searchDefaultScopeRaw,
            hiddenAppCount: hiddenAppCount,
            hotkeyPrimaryModifierRaw: hotkeyPrimaryModifierRaw,
            hotkeyReverseModifiersRaw: hotkeyReverseModifiersRaw,
            hotkeyMainKeyRaw: hotkeyMainKeyRaw,
            hotkeyQuitKeyRaw: hotkeyQuitKeyRaw,
            inAppWindowHotkeyBaseKeysRaw:
                inAppWindowHotkeyBaseKeysRaw,
            inAppWindowHotkeyReverseKeysRaw:
                inAppWindowHotkeyReverseKeysRaw,
            inAppWindowHotkeyMainKeysRaw:
                inAppWindowHotkeyMainKeysRaw,
            commandTabTakeoverRegistrationState:
                commandTabTakeoverRegistrationState,
            accessibilityTrusted: accessibilityTrusted,
            screenCaptureTrusted: screenCaptureTrusted,
            targetNSAppearanceName:
                presentationContext.targetNSAppearanceName,
            hotkeyConflict: hotkeyConflict,
            hotkeyPermissionRequirement: hotkeyPermissionRequirement
        )
    }
}

extension AppKitSettingsHotkeyRawValues {
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
