import SwiftUI
import AppKit
import FlowTabCore

struct AppSettingsView: View {
    let isActive: Bool

    @AppStorage(AppPreferenceKeys.showShortcutHint) private var showShortcutHint = true
    @AppStorage(AppPreferenceKeys.showInCommandTab)
    private var showInCommandTab = AppVisibilityPreferencesStore.defaultShowInCommandTab
    @AppStorage(AppPreferenceKeys.showPermissionReminder) private var showPermissionReminder = true
    @AppStorage(AppPreferenceKeys.themeMode) private var themeModeRaw = ThemePreferencesStore.defaultMode.rawValue
    @AppStorage(AppPreferenceKeys.appLanguage)
    private var appLanguageRaw = AppLanguagePreferencesStore.defaultLanguage.rawValue
    @AppStorage(AppPreferenceKeys.autoRestoreMinimizedWindowOnSwitch)
    private var autoRestoreMinimizedWindowOnSwitch =
        SwitcherBehaviorPreferencesStore.defaultAutoRestoreMinimizedWindowOnSwitch
    @AppStorage(AppPreferenceKeys.hideMinimizedAppsFromAppLayer)
    private var hideMinimizedAppsFromAppLayer =
        SwitcherBehaviorPreferencesStore.defaultHideMinimizedAppsFromAppLayer
    @AppStorage(AppPreferenceKeys.searchEnabled)
    private var searchEnabled = SearchInteractionPreferencesStore.defaultIsEnabled
    @AppStorage(AppPreferenceKeys.searchDefaultScope)
    private var searchDefaultScopeRaw = SearchInteractionPreferencesStore.defaultScope.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyPrimaryModifier)
    private var hotkeyPrimaryModifierRaw = SwitcherHotkeyPreferencesStore.defaultPrimaryModifier.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyMainKey)
    private var hotkeyMainKeyRaw = SwitcherHotkeyPreferencesStore.defaultMainKey.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyQuitKey)
    private var hotkeyQuitKeyRaw = SwitcherHotkeyPreferencesStore.defaultQuitKey.rawValue
    @AppStorage(CommandTabTakeoverController.takeoverMarkerKey)
    private var commandTabTakeoverActive = false
    @AppStorage(AppPreferenceKeys.inAppWindowHotkeyPrimaryModifier)
    private var inAppWindowHotkeyPrimaryModifierRaw =
        InAppWindowHotkeyPreferencesStore.defaultPrimaryModifier.rawValue
    @AppStorage(AppPreferenceKeys.inAppWindowHotkeyMainKey)
    private var inAppWindowHotkeyMainKeyRaw = InAppWindowHotkeyPreferencesStore.defaultMainKey.rawValue
    @AppStorage(AppPreferenceKeys.windowLayerAutoEnterDelay)
    private var windowLayerAutoEnterDelayRaw = WindowLayerPreferencesStore.defaultAutoEnterDelay
    @State private var accessibilityTrusted = AccessibilityPermissionChecker.isTrusted()
    @State private var screenCaptureTrusted = ScreenCapturePermissionChecker.hasScreenCapturePermission
    @State private var hasAttemptedScreenCapturePermissionRequest = false
    @State private var accessibilityPermissionPollTask: Task<Void, Never>?
    @State private var screenCapturePollTask: Task<Void, Never>?
    @State private var windowLayerAutoEnterDelayText = ""
    @State private var didInitialize = false
    @State private var isWindowLayerAutoEnterDelayEditing = false

    private var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "unknown"
    }

    private var bundlePath: String {
        Bundle.main.bundlePath
    }

    private var hotkeyConfiguration: SwitcherHotkeyConfiguration {
        SwitcherHotkeyPreferencesStore.resolve(
            primaryModifierRaw: hotkeyPrimaryModifierRaw,
            mainKeyRaw: hotkeyMainKeyRaw,
            quitKeyRaw: hotkeyQuitKeyRaw
        )
    }

    private var inAppWindowHotkeyConfiguration: SwitcherHotkeyConfiguration {
        let resolved = InAppWindowHotkeyPreferencesStore.resolve(
            primaryModifierRaw: inAppWindowHotkeyPrimaryModifierRaw,
            mainKeyRaw: inAppWindowHotkeyMainKeyRaw
        )
        return SwitcherHotkeyConfiguration(
            primaryModifier: resolved.primaryModifier,
            mainKey: resolved.mainKey,
            quitKey: .q
        )
    }

    private var windowLayerAutoEnterDelay: Double {
        WindowLayerPreferencesStore.normalizedAutoEnterDelay(windowLayerAutoEnterDelayRaw)
    }

    var body: some View {
        ZStack {
            HomeBackdropView()

            AppKitSettingsPageContent(
                isActive: isActive,
                showShortcutHint: $showShortcutHint,
                showInCommandTab: $showInCommandTab,
                themeModeRaw: $themeModeRaw,
                appLanguageRaw: $appLanguageRaw,
                windowLayerAutoEnterDelayText: windowLayerAutoEnterDelayText,
                autoRestoreMinimizedWindowOnSwitch: $autoRestoreMinimizedWindowOnSwitch,
                hideMinimizedAppsFromAppLayer: $hideMinimizedAppsFromAppLayer,
                showPermissionReminder: $showPermissionReminder,
                searchEnabled: $searchEnabled,
                searchDefaultScopeRaw: $searchDefaultScopeRaw,
                hotkeyPrimaryModifierRaw: $hotkeyPrimaryModifierRaw,
                hotkeyMainKeyRaw: $hotkeyMainKeyRaw,
                hotkeyQuitKeyRaw: $hotkeyQuitKeyRaw,
                inAppWindowHotkeyPrimaryModifierRaw: $inAppWindowHotkeyPrimaryModifierRaw,
                inAppWindowHotkeyMainKeyRaw: $inAppWindowHotkeyMainKeyRaw,
                commandTabTakeoverActive: commandTabTakeoverActive,
                accessibilityTrusted: accessibilityTrusted,
                screenCaptureTrusted: screenCaptureTrusted,
                onWindowLayerAutoEnterDelayTextChanged: applyWindowLayerAutoEnterDelayText,
                onWindowLayerAutoEnterDelayTextCommitted: commitWindowLayerAutoEnterDelayText,
                onWindowLayerAutoEnterDelayEditingChanged: {
                    isWindowLayerAutoEnterDelayEditing = $0
                },
                onAccessibilityAction: {
                    if accessibilityTrusted {
                        openAccessibilityPrivacySettings()
                    } else {
                        requestAccessibilityPermission()
                    }
                },
                onScreenCaptureAction: {
                    if screenCaptureTrusted {
                        openScreenCapturePrivacySettings()
                    } else {
                        requestScreenCapturePermission()
                    }
                }
            )
            .id(appLanguageRaw)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            handleVisibilityChanged(isActive)
        }
        .onChange(of: isActive) { active in
            handleVisibilityChanged(active)
        }
        .onChange(of: themeModeRaw) { _ in
            enforceThemeModeConsistency()
        }
        .onChange(of: appLanguageRaw) { _ in
            enforceLanguageConsistency()
            notifyLanguagePreferenceChanged()
        }
        .onChange(of: showInCommandTab) { _ in
            notifyAppVisibilityPreferenceChanged()
        }
        .onChange(of: hotkeyPrimaryModifierRaw) { _ in
            enforceHotkeyConsistency()
            enforceInAppWindowHotkeyConsistency()
            notifyHotkeyConfigChanged()
        }
        .onChange(of: hotkeyMainKeyRaw) { _ in
            enforceHotkeyConsistency()
            enforceInAppWindowHotkeyConsistency()
            notifyHotkeyConfigChanged()
        }
        .onChange(of: hotkeyQuitKeyRaw) { _ in
            enforceHotkeyConsistency()
            notifyHotkeyConfigChanged()
        }
        .onChange(of: inAppWindowHotkeyPrimaryModifierRaw) { _ in
            enforceInAppWindowHotkeyConsistency()
            notifyHotkeyConfigChanged()
        }
        .onChange(of: inAppWindowHotkeyMainKeyRaw) { _ in
            enforceInAppWindowHotkeyConsistency()
            notifyHotkeyConfigChanged()
        }
        .onChange(of: windowLayerAutoEnterDelayRaw) { _ in
            enforceWindowLayerPreferencesConsistency()
            if !isWindowLayerAutoEnterDelayEditing {
                syncWindowLayerAutoEnterDelayText()
            }
        }
        .onChange(of: searchDefaultScopeRaw) { _ in
            enforceSearchPreferencesConsistency()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            guard isActive else { return }
            refreshAccessibilityStatus()
            refreshScreenCaptureStatus()
        }
        .onDisappear {
            cancelPermissionPolling()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("flowtab.tab.settings.content")
    }

    private func handleVisibilityChanged(_ active: Bool) {
        guard active else {
            cancelPermissionPolling()
            return
        }
        if !didInitialize {
            enforceThemeModeConsistency()
            enforceLanguageConsistency()
            enforceHotkeyConsistency()
            enforceInAppWindowHotkeyConsistency()
            enforceWindowLayerPreferencesConsistency()
            enforceSearchPreferencesConsistency()
            syncWindowLayerAutoEnterDelayText()
            didInitialize = true
        }
        refreshAccessibilityStatus()
        refreshScreenCaptureStatus()
    }

    private func cancelPermissionPolling() {
        accessibilityPermissionPollTask?.cancel()
        accessibilityPermissionPollTask = nil
        screenCapturePollTask?.cancel()
        screenCapturePollTask = nil
    }

    private func requestAccessibilityPermission() {
        accessibilityPermissionPollTask?.cancel()
        let trusted = AccessibilityPermissionChecker.requestPermission()
        RuntimeLog.info(
            "Permission",
            "prompt requested immediateTrusted=\(trusted) bundle=\(bundleIdentifier) path=\(bundlePath)"
        )
        refreshAccessibilityStatus()
        if !trusted {
            startAccessibilityPermissionPolling()
        }
    }

    private func requestScreenCapturePermission() {
        screenCapturePollTask?.cancel()
        let trusted = ScreenCapturePermissionChecker.requestScreenCapturePermission()
        RuntimeLog.info(
            "Preview",
            "screenCapture prompt requested immediateTrusted=\(trusted) bundle=\(bundleIdentifier) path=\(bundlePath)"
        )
        refreshScreenCaptureStatus()
        if !trusted {
            // Screen capture prompts are often one-shot after denial; keep first click as request, then route later clicks.
            if hasAttemptedScreenCapturePermissionRequest {
                presentScreenCapturePermissionReminder()
            } else {
                hasAttemptedScreenCapturePermissionRequest = true
            }
            startScreenCapturePermissionPolling()
        } else {
            hasAttemptedScreenCapturePermissionRequest = false
        }
    }

    private func presentScreenCapturePermissionReminder() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = AppStrings.text(.alertScreenDeniedTitle)
        alert.informativeText = AppStrings.text(.alertScreenDeniedMessage)
        alert.addButton(withTitle: AppStrings.text(.alertOpenSystemSettings))
        alert.addButton(withTitle: AppStrings.text(.alertLater))
        if alert.runModal() == .alertFirstButtonReturn {
            openScreenCapturePrivacySettings()
        }
    }

    private func openAccessibilityPrivacySettings() {
        openPrivacySettings(anchor: "Privacy_Accessibility")
    }

    private func openScreenCapturePrivacySettings() {
        openPrivacySettings(anchor: "Privacy_ScreenCapture")
    }

    private func openPrivacySettings(anchor: String) {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?\(anchor)",
            "x-apple.systempreferences:com.apple.preference.security"
        ]
        for rawURL in candidates {
            if let url = URL(string: rawURL), NSWorkspace.shared.open(url) {
                return
            }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    private func refreshAccessibilityStatus() {
        accessibilityTrusted = AccessibilityPermissionChecker.isTrusted()
    }

    private func refreshScreenCaptureStatus() {
        let trusted = ScreenCapturePermissionChecker.hasScreenCapturePermission
        screenCaptureTrusted = trusted
        if trusted {
            hasAttemptedScreenCapturePermissionRequest = false
        }
    }

    private func enforceHotkeyConsistency() {
        let resolved = hotkeyConfiguration
        if hotkeyPrimaryModifierRaw != resolved.primaryModifier.rawValue {
            hotkeyPrimaryModifierRaw = resolved.primaryModifier.rawValue
        }
        if hotkeyMainKeyRaw != resolved.mainKey.rawValue {
            hotkeyMainKeyRaw = resolved.mainKey.rawValue
        }
        if hotkeyQuitKeyRaw != resolved.quitKey.rawValue {
            hotkeyQuitKeyRaw = resolved.quitKey.rawValue
        }
    }

    private func enforceInAppWindowHotkeyConsistency() {
        let resolved = InAppWindowHotkeyPreferencesStore.resolveAvoidingMainHotkeyConflict(
            primaryModifierRaw: inAppWindowHotkeyPrimaryModifierRaw,
            mainKeyRaw: inAppWindowHotkeyMainKeyRaw,
            mainHotkeyConfiguration: hotkeyConfiguration
        )
        if inAppWindowHotkeyPrimaryModifierRaw != resolved.primaryModifier.rawValue {
            inAppWindowHotkeyPrimaryModifierRaw = resolved.primaryModifier.rawValue
        }
        if inAppWindowHotkeyMainKeyRaw != resolved.mainKey.rawValue {
            inAppWindowHotkeyMainKeyRaw = resolved.mainKey.rawValue
        }
    }

    private func enforceThemeModeConsistency() {
        let resolved = ThemePreferencesStore.resolve(rawValue: themeModeRaw)
        if themeModeRaw != resolved.rawValue {
            themeModeRaw = resolved.rawValue
        }
    }

    private func enforceLanguageConsistency() {
        let resolved = AppLanguagePreferencesStore.resolve(rawValue: appLanguageRaw)
        if appLanguageRaw != resolved.rawValue {
            appLanguageRaw = resolved.rawValue
        }
    }

    private func enforceSearchPreferencesConsistency() {
        let resolved = SearchInteractionPreferencesStore.loadDefaultScope()
        if searchDefaultScopeRaw != resolved.rawValue {
            searchDefaultScopeRaw = resolved.rawValue
        }
    }

    private func enforceWindowLayerPreferencesConsistency() {
        let resolved = WindowLayerPreferencesStore.normalizedAutoEnterDelay(
            windowLayerAutoEnterDelayRaw
        )
        if abs(windowLayerAutoEnterDelayRaw - resolved) > 0.0001 {
            windowLayerAutoEnterDelayRaw = resolved
        }
    }

    private func syncWindowLayerAutoEnterDelayText() {
        let formatted = String(format: "%.2f", windowLayerAutoEnterDelay)
        if windowLayerAutoEnterDelayText != formatted {
            windowLayerAutoEnterDelayText = formatted
        }
    }

    private func applyWindowLayerAutoEnterDelayText(_ rawText: String) {
        let sanitized = WindowLayerPreferencesStore.sanitizeAutoEnterDelayText(rawText)
        if windowLayerAutoEnterDelayText != sanitized {
            windowLayerAutoEnterDelayText = sanitized
        }
        guard !sanitized.isEmpty else { return }
        guard sanitized != "." else { return }
        guard let parsedValue = Double(sanitized) else { return }
        let normalizedValue = WindowLayerPreferencesStore.normalizedAutoEnterDelay(parsedValue)
        if abs(windowLayerAutoEnterDelayRaw - normalizedValue) > 0.0001 {
            windowLayerAutoEnterDelayRaw = normalizedValue
        }
    }

    private func commitWindowLayerAutoEnterDelayText() {
        let sanitized = WindowLayerPreferencesStore.sanitizeAutoEnterDelayText(
            windowLayerAutoEnterDelayText
        )
        if windowLayerAutoEnterDelayText != sanitized {
            windowLayerAutoEnterDelayText = sanitized
        }
        if let parsedValue = Double(sanitized) {
            windowLayerAutoEnterDelayRaw = WindowLayerPreferencesStore.normalizedAutoEnterDelay(
                parsedValue
            )
        }
        syncWindowLayerAutoEnterDelayText()
    }

    @MainActor
    private func persistHotkeyRegistrationRequest(_ request: HotkeyRegistrationRequest) {
        let userDefaults = UserDefaults.standard
        userDefaults.set(
            request.mainConfiguration.primaryModifier.rawValue,
            forKey: AppPreferenceKeys.hotkeyPrimaryModifier
        )
        userDefaults.set(request.mainConfiguration.mainKey.rawValue, forKey: AppPreferenceKeys.hotkeyMainKey)
        userDefaults.set(request.mainConfiguration.quitKey.rawValue, forKey: AppPreferenceKeys.hotkeyQuitKey)
        userDefaults.set(
            request.inAppWindowConfiguration.primaryModifier.rawValue,
            forKey: AppPreferenceKeys.inAppWindowHotkeyPrimaryModifier
        )
        userDefaults.set(
            request.inAppWindowConfiguration.mainKey.rawValue,
            forKey: AppPreferenceKeys.inAppWindowHotkeyMainKey
        )
    }

    @MainActor
    private func notifyHotkeyConfigChanged() {
        let request = HotkeyRegistrationRequest(
            mainConfiguration: hotkeyConfiguration,
            inAppWindowConfiguration: inAppWindowHotkeyConfiguration
        )
        persistHotkeyRegistrationRequest(request)
        RuntimeLog.info(
            "HotKey",
            "updated main=\(request.mainConfiguration.mainShortcutText) backward=\(request.mainConfiguration.backwardShortcutText) quit=\(request.mainConfiguration.quitShortcutText) inApp=\(request.inAppWindowConfiguration.mainShortcutText) inAppBackward=\(request.inAppWindowConfiguration.backwardShortcutText)"
        )
        if let appDelegate = AppDelegate.shared {
            appDelegate.requestHotkeyReload(using: request, source: "settings_view")
        } else {
            RuntimeLog.info(
                "HotKey",
                "re-register requested source=settings_view requestID=\(request.requestID.uuidString) action=notification_only"
            )
            NotificationCenter.default.post(
                name: .flowTabReRegisterHotkeys,
                object: nil,
                userInfo: request.notificationUserInfo
            )
        }
    }

    private func notifyAppVisibilityPreferenceChanged() {
        RuntimeLog.info(
            "App",
            "showInCommandTab=\(showInCommandTab)"
        )
        NotificationCenter.default.post(name: .flowTabAppVisibilityPreferenceChanged, object: nil)
    }

    private func notifyLanguagePreferenceChanged() {
        RuntimeLog.info("App", "language=\(appLanguageRaw)")
        NotificationCenter.default.post(name: .flowTabLanguagePreferenceChanged, object: nil)
    }

    private func startAccessibilityPermissionPolling() {
        accessibilityPermissionPollTask = Task { @MainActor in
            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                refreshAccessibilityStatus()
                if accessibilityTrusted {
                    RuntimeLog.info(
                        "Permission",
                        "trusted=true after prompt bundle=\(bundleIdentifier) path=\(bundlePath)"
                    )
                    accessibilityPermissionPollTask = nil
                    return
                }
            }
            RuntimeLog.info(
                "Permission",
                "still untrusted after waiting 20s bundle=\(bundleIdentifier) path=\(bundlePath)"
            )
            accessibilityPermissionPollTask = nil
        }
    }

    private func startScreenCapturePermissionPolling() {
        screenCapturePollTask = Task { @MainActor in
            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                refreshScreenCaptureStatus()
                if screenCaptureTrusted {
                    RuntimeLog.info(
                        "Preview",
                        "screenCapture trusted=true after prompt bundle=\(bundleIdentifier) path=\(bundlePath)"
                    )
                    screenCapturePollTask = nil
                    return
                }
            }
            RuntimeLog.info(
                "Preview",
                "screenCapture still untrusted after waiting 20s bundle=\(bundleIdentifier) path=\(bundlePath)"
            )
            screenCapturePollTask = nil
        }
    }
}
