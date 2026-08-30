import Combine
import SwiftUI

@MainActor
final class AppKitSettingsPageBridgeCoordinator {
    private var content: AppKitSettingsPageContent?
    private weak var connectedContainer: AppKitSettingsPageContainerView?
    private weak var connectedPageView: AppKitSettingsPageView?
    private weak var lifecycle: HomeRetainedTabLifecycle?
    private var lifecycleObservation: AnyCancellable?
    private var isVisible = true

    func update(with content: AppKitSettingsPageContent) {
        self.content = content
        isVisible = content.isVisible
        bindLifecycleIfNeeded(content.lifecycle)
        applyActivity()
    }

    func connect(to container: AppKitSettingsPageContainerView) {
        if connectedContainer !== container {
            connectedContainer?.setActive(false)
            connectedContainer = container
        }
        connectCallbacks(to: container.pageView)
        applyActivity()
    }

    func stop() {
        connectedContainer?.setActive(false)
        lifecycleObservation?.cancel()
        lifecycleObservation = nil
        lifecycle = nil
        connectedContainer = nil
        connectedPageView = nil
        content = nil
    }

    private func bindLifecycleIfNeeded(
        _ lifecycle: HomeRetainedTabLifecycle
    ) {
        guard self.lifecycle !== lifecycle else { return }
        lifecycleObservation?.cancel()
        self.lifecycle = lifecycle
        lifecycleObservation = lifecycle.transitions.sink {
            [weak self] state in
            self?.applyActivity(state: state)
        }
    }

    private func applyActivity(
        state: HomeRetainedTabLifecycle.State? = nil
    ) {
        guard let lifecycle else { return }
        let resolvedState = state ?? lifecycle.state
        connectedContainer?.setActive(
            resolvedState == .active && isVisible
        )
    }

    private func connectCallbacks(to pageView: AppKitSettingsPageView) {
        guard connectedPageView !== pageView else { return }
        connectedPageView = pageView

        pageView.onShowInCommandTabChanged = { [weak self] value in
            self?.content?.showInCommandTab = value
        }
        pageView.onThemeModeChanged = { [weak self] value in
            self?.content?.themeModeRaw = value
        }
        pageView.onAppLanguageChanged = { [weak self] value in
            self?.content?.appLanguageRaw = value
        }
        pageView.onWindowLayerAutoEnterDelayTextChanged = { [weak self] value in
            self?.content?.onWindowLayerAutoEnterDelayTextChanged(value)
        }
        pageView.onWindowLayerAutoEnterDelayTextCommitted = { [weak self] in
            self?.content?.onWindowLayerAutoEnterDelayTextCommitted()
        }
        pageView.onWindowLayerAutoEnterDelayEditingChanged = { [weak self] value in
            self?.content?.onWindowLayerAutoEnterDelayEditingChanged(value)
        }
        pageView.onAutoRestoreMinimizedWindowOnSwitchChanged = { [weak self] value in
            self?.content?.autoRestoreMinimizedWindowOnSwitch = value
        }
        pageView.onHideMinimizedAppsFromAppLayerChanged = { [weak self] value in
            self?.content?.hideMinimizedAppsFromAppLayer = value
        }
        pageView.onSearchEnabledChanged = { [weak self] value in
            self?.content?.searchEnabled = value
        }
        pageView.onSearchDefaultScopeChanged = { [weak self] value in
            self?.content?.searchDefaultScopeRaw = value
        }
        pageView.onManageAppVisibility = { [weak self] in
            self?.content?.onManageAppVisibility()
        }
        pageView.onDismissHotkeyConflict = { [weak self] in
            self?.content?.onDismissHotkeyConflict()
        }
        pageView.onMainModifiersChanged = { [weak self] value in
            self?.applyHotkeyChange(.mainModifiers, rawValue: value.rawValue)
        }
        pageView.onMainReverseModifiersChanged = { [weak self] value in
            self?.applyHotkeyChange(
                .mainReverseModifiers,
                rawValue: value.rawValue
            )
        }
        pageView.onMainKeyChanged = { [weak self] value in
            self?.applyHotkeyChange(.mainKey, rawValue: value.rawValue)
        }
        pageView.onQuitKeyChanged = { [weak self] value in
            self?.applyHotkeyChange(.quitKey, rawValue: value.rawValue)
        }
        pageView.onInAppBaseKeysChanged = { [weak self] value in
            self?.applyHotkeyChange(.inAppBaseKeys, rawValue: value.rawValue)
        }
        pageView.onInAppReverseModifiersChanged = { [weak self] value in
            self?.applyHotkeyChange(
                .inAppReverseModifiers,
                rawValue: value.rawValue
            )
        }
        pageView.onInAppMainKeysChanged = { [weak self] value in
            self?.applyHotkeyChange(.inAppMainKeys, rawValue: value.rawValue)
        }
        pageView.onShowPermissionReminderChanged = { [weak self] value in
            self?.content?.showPermissionReminder = value
        }
        pageView.onAllowLaunchAtLoginChanged = { [weak self] value in
            guard let self else { return }
            content?.allowLaunchAtLogin = value
            content?.onLaunchAtLoginChanged(value)
        }
        pageView.onAccessibilityAction = { [weak self] in
            self?.content?.onAccessibilityAction()
        }
        pageView.onScreenCaptureAction = { [weak self] in
            self?.content?.onScreenCaptureAction()
        }
    }

    private func applyHotkeyChange(
        _ field: HotkeySettingsField,
        rawValue: String
    ) {
        guard let content else { return }
        let candidate = HotkeySettingsChangeCandidate(
            field: field,
            values: hotkeyValues(from: content).replacing(
                field,
                with: rawValue
            )
        )
        content.onHotkeyChanged(candidate)

        guard let latestContent = self.content else { return }
        connectedPageView?.updateHotkeyContent(
            with: hotkeyValues(from: latestContent)
        )
    }

    private func hotkeyValues(
        from content: AppKitSettingsPageContent
    ) -> AppKitSettingsHotkeyRawValues {
        AppKitSettingsHotkeyRawValues(
            hotkeyPrimaryModifierRaw: content.hotkeyPrimaryModifierRaw,
            hotkeyReverseModifiersRaw: content.hotkeyReverseModifiersRaw,
            hotkeyMainKeyRaw: content.hotkeyMainKeyRaw,
            hotkeyQuitKeyRaw: content.hotkeyQuitKeyRaw,
            inAppWindowHotkeyBaseKeysRaw:
                content.inAppWindowHotkeyBaseKeysRaw,
            inAppWindowHotkeyReverseKeysRaw:
                content.inAppWindowHotkeyReverseKeysRaw,
            inAppWindowHotkeyMainKeysRaw:
                content.inAppWindowHotkeyMainKeysRaw
        )
    }
}
