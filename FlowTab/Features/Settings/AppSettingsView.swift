import SwiftUI
import AppKit
import FlowTabCore

enum PermissionPollingTarget: String, CaseIterable, Equatable {
    case accessibility
    case screenCapture
}

struct PermissionPollingTaskRegistry: Equatable {
    private(set) var activeTargets: Set<PermissionPollingTarget> = []

    mutating func markStarted(_ target: PermissionPollingTarget) {
        activeTargets.insert(target)
    }

    mutating func markStopped(_ target: PermissionPollingTarget) {
        activeTargets.remove(target)
    }

    mutating func markAllStopped() {
        activeTargets.removeAll()
    }

    func isActive(_ target: PermissionPollingTarget) -> Bool {
        activeTargets.contains(target)
    }
}

struct PermissionPollingPolicy: Equatable {
    var intervalNanoseconds: UInt64
    var attemptLimit: Int

    static let `default` = PermissionPollingPolicy(
        intervalNanoseconds: 500_000_000,
        attemptLimit: 40
    )

    var timeoutSeconds: Double {
        Double(intervalNanoseconds * UInt64(attemptLimit)) / 1_000_000_000
    }

    var timeoutDescription: String {
        "\(Int(timeoutSeconds))s"
    }
}

struct PermissionPollingDiagnostic: Equatable {
    enum Action: String, Equatable {
        case timeout
    }

    let target: PermissionPollingTarget
    let attempt: Int
    let attemptLimit: Int
    let elapsedMs: Double
    let finalPermissionGranted: Bool
    let timeoutDescription: String
    let bundleIdentifier: String
    let bundlePath: String
    let action: Action

    var logMessage: String {
        [
            "permission poll",
            "target=\(target.rawValue)",
            "action=\(action.rawValue)",
            "attempt=\(attempt)/\(attemptLimit)",
            "elapsedMs=\(String(format: "%.3f", elapsedMs))",
            "finalPermissionGranted=\(finalPermissionGranted)",
            "timeout=\(timeoutDescription)",
            "bundle=\(bundleIdentifier)",
            "path=\(bundlePath)"
        ].joined(separator: " ")
    }
}

struct AppSettingsView: View {
    let isActive: Bool

    @AppStorage(AppPreferenceKeys.showShortcutHint) private var showShortcutHint = true
    @AppStorage(AppPreferenceKeys.showInCommandTab)
    private var showInCommandTab = AppVisibilityPreferencesStore.defaultShowInCommandTab
    @AppStorage(AppPreferenceKeys.showPermissionReminder) private var showPermissionReminder = true
    @AppStorage(AppPreferenceKeys.allowLaunchAtLogin)
    private var allowLaunchAtLogin = LaunchAtLoginPreferencesStore.defaultAllowLaunchAtLogin
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
    @State private var permissionPollTasksByTarget: [PermissionPollingTarget: Task<Void, Never>] = [:]
    @State private var permissionPollingGenerationsByTarget: [PermissionPollingTarget: UInt64] = [:]
    @State private var permissionPollingTaskRegistry = PermissionPollingTaskRegistry()
    @State private var windowLayerAutoEnterDelayText = ""
    @State private var didInitialize = false
    @State private var isWindowLayerAutoEnterDelayEditing = false
    @State private var isApplyingLaunchAtLoginPreference = false
    @State private var lastNotifiedHotkeySignature = ""
    @State private var hiddenAppCount = AppVisibilityPreferencesStore.loadHiddenAppIDs().count
    @State private var showsAppVisibilityManager = false

    private let appVisibilityNavigationAnimation = Animation.easeInOut(duration: 0.18)
    private let permissionPollingPolicy: PermissionPollingPolicy = .default

    private var permissionPollIntervalNanoseconds: UInt64 {
        permissionPollingPolicy.intervalNanoseconds
    }

    private var permissionPollAttemptLimit: Int {
        permissionPollingPolicy.attemptLimit
    }

    private var permissionPollTimeoutSeconds: Double {
        permissionPollingPolicy.timeoutSeconds
    }

    private var permissionPollTimeoutDescription: String {
        permissionPollingPolicy.timeoutDescription
    }

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

    private var showInCommandTabPreference: Binding<Bool> {
        Binding(
            get: { showInCommandTab },
            set: { newValue in
                guard showInCommandTab != newValue else { return }
                AppVisibilityPreferencesStore.setAppHidden(
                    !newValue,
                    appID: AppVisibilityPreferencesStore.currentAppID()
                )
                showInCommandTab = AppVisibilityPreferencesStore.loadShowInCommandTab()
                refreshHiddenAppCount()
            }
        )
    }

    private var settingsPageBridgeIdentity: String {
        "\(themeModeRaw)|\(appLanguageRaw)"
    }

    var body: some View {
        ZStack {
            HomeBackdropView()

            AppKitSettingsPageContent(
                isActive: isActive && !showsAppVisibilityManager,
                showShortcutHint: $showShortcutHint,
                showInCommandTab: showInCommandTabPreference,
                themeModeRaw: $themeModeRaw,
                appLanguageRaw: $appLanguageRaw,
                windowLayerAutoEnterDelayText: windowLayerAutoEnterDelayText,
                autoRestoreMinimizedWindowOnSwitch: $autoRestoreMinimizedWindowOnSwitch,
                hideMinimizedAppsFromAppLayer: $hideMinimizedAppsFromAppLayer,
                showPermissionReminder: $showPermissionReminder,
                allowLaunchAtLogin: $allowLaunchAtLogin,
                searchEnabled: $searchEnabled,
                searchDefaultScopeRaw: $searchDefaultScopeRaw,
                hiddenAppCount: hiddenAppCount,
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
                onMainHotkeyChanged: handleMainHotkeyChanged,
                onQuitHotkeyChanged: handleQuitHotkeyChanged,
                onInAppWindowHotkeyChanged: handleInAppWindowHotkeyChanged,
                onLaunchAtLoginChanged: handleLaunchAtLoginChanged,
                onManageAppVisibility: {
                    refreshHiddenAppCount()
                    withAnimation(appVisibilityNavigationAnimation) {
                        showsAppVisibilityManager = true
                    }
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
            .id(settingsPageBridgeIdentity)
            .opacity(showsAppVisibilityManager ? 0 : 1)
            .allowsHitTesting(!showsAppVisibilityManager)
            .accessibilityHidden(showsAppVisibilityManager)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if showsAppVisibilityManager {
                AppVisibilityManagerView {
                    withAnimation(appVisibilityNavigationAnimation) {
                        showsAppVisibilityManager = false
                    }
                    refreshHiddenAppCount()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .transition(.opacity)
            }
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
        .onChange(of: windowLayerAutoEnterDelayRaw) { _ in
            enforceWindowLayerPreferencesConsistency()
            if !isWindowLayerAutoEnterDelayEditing {
                syncWindowLayerAutoEnterDelayText()
            }
        }
        .onChange(of: searchDefaultScopeRaw) { _ in
            enforceSearchPreferencesConsistency()
        }
        .onChange(of: hotkeyPrimaryModifierRaw) { _ in
            handleStoredMainHotkeyChanged()
        }
        .onChange(of: hotkeyMainKeyRaw) { _ in
            handleStoredMainHotkeyChanged()
        }
        .onChange(of: hotkeyQuitKeyRaw) { _ in
            handleStoredMainHotkeyChanged()
        }
        .onChange(of: inAppWindowHotkeyPrimaryModifierRaw) { _ in
            handleStoredInAppWindowHotkeyChanged()
        }
        .onChange(of: inAppWindowHotkeyMainKeyRaw) { _ in
            handleStoredInAppWindowHotkeyChanged()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            guard isActive else { return }
            refreshAccessibilityStatus()
            refreshScreenCaptureStatus()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UserDefaults.didChangeNotification
        )) { _ in
            handleStoredHotkeyDefaultsDidChange()
            refreshHiddenAppCount()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .flowTabAppVisibilityPreferenceChanged
        )) { _ in
            refreshHiddenAppCount()
        }
        .onDisappear {
            cancelPermissionPolling()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("flowtab.tab.settings.content")
    }

    @MainActor
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
        permissionPollTasksByTarget.values.forEach { $0.cancel() }
        permissionPollTasksByTarget.removeAll()
        for target in PermissionPollingTarget.allCases {
            advancePermissionPollingGeneration(for: target)
        }
        permissionPollingTaskRegistry.markAllStopped()
    }

    private func cancelPermissionPolling(target: PermissionPollingTarget) {
        permissionPollTasksByTarget[target]?.cancel()
        permissionPollTasksByTarget[target] = nil
        advancePermissionPollingGeneration(for: target)
        permissionPollingTaskRegistry.markStopped(target)
    }

    private func requestAccessibilityPermission() {
        cancelPermissionPolling(target: .accessibility)
        let trusted = AccessibilityPermissionChecker.requestPermission()
        RuntimeLog.info(
            .permission,
            "prompt requested immediateTrusted=\(trusted) bundle=\(bundleIdentifier) path=\(bundlePath)"
        )
        refreshAccessibilityStatus()
        if !trusted {
            startPermissionPolling(target: .accessibility)
        }
    }

    private func requestScreenCapturePermission() {
        cancelPermissionPolling(target: .screenCapture)
        let trusted = ScreenCapturePermissionChecker.requestScreenCapturePermission()
        RuntimeLog.info(
            .permission,
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
            startPermissionPolling(target: .screenCapture)
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

    @MainActor
    private func handleLaunchAtLoginChanged(_ allowed: Bool) {
        guard !isApplyingLaunchAtLoginPreference else { return }

        let status: LaunchAtLoginStatus
        if let appDelegate = AppDelegate.shared {
            status = appDelegate.setLaunchAtLoginAllowed(allowed, source: "settings_view")
        } else {
            status = setLaunchAtLoginAllowedWithoutDelegate(allowed, source: "settings_view")
        }

        let resolvedAllowed = status.preferenceAllowedValue
        guard resolvedAllowed != allowed else { return }

        isApplyingLaunchAtLoginPreference = true
        allowLaunchAtLogin = resolvedAllowed
        DispatchQueue.main.async {
            isApplyingLaunchAtLoginPreference = false
        }
    }

    private func setLaunchAtLoginAllowedWithoutDelegate(
        _ allowed: Bool,
        source: String
    ) -> LaunchAtLoginStatus {
        do {
            try LaunchAtLoginController.shared.reconcile(allowed: allowed)
            let currentStatus = LaunchAtLoginController.shared.status
            RuntimeLog.info(
                .permission,
                "launchAtLogin allowed=\(allowed) status=\(currentStatus.logValue) source=\(source)"
            )
            return currentStatus
        } catch {
            let currentStatus = LaunchAtLoginController.shared.status
            RuntimeLog.error(
                .permission,
                "launchAtLogin failed allowed=\(allowed) status=\(currentStatus.logValue) source=\(source) error=\(error.localizedDescription)"
            )
            return currentStatus
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

    @MainActor
    private func handleMainHotkeyChanged(_ values: AppKitSettingsHotkeyRawValues) {
        let request = normalizedHotkeyRegistrationRequest(from: values)
        applyNormalizedHotkeyValues(from: request)
        notifyHotkeyConfigChanged(using: request)
    }

    @MainActor
    private func handleQuitHotkeyChanged(_ values: AppKitSettingsHotkeyRawValues) {
        let request = normalizedHotkeyRegistrationRequest(from: values)
        applyNormalizedHotkeyValues(from: request)
        notifyHotkeyConfigChanged(using: request)
    }

    @MainActor
    private func handleInAppWindowHotkeyChanged(_ values: AppKitSettingsHotkeyRawValues) {
        let request = normalizedHotkeyRegistrationRequest(from: values)
        applyNormalizedHotkeyValues(from: request)
        notifyHotkeyConfigChanged(using: request)
    }

    @MainActor
    private func handleStoredMainHotkeyChanged() {
        enforceHotkeyConsistency()
        enforceInAppWindowHotkeyConsistency()
        notifyHotkeyConfigChangedIfNeeded(using: HotkeyRegistrationRequest.load())
    }

    @MainActor
    private func handleStoredInAppWindowHotkeyChanged() {
        enforceInAppWindowHotkeyConsistency()
        notifyHotkeyConfigChangedIfNeeded(using: HotkeyRegistrationRequest.load())
    }

    @MainActor
    private func handleStoredHotkeyDefaultsDidChange() {
        notifyHotkeyConfigChangedIfNeeded(using: HotkeyRegistrationRequest.load())
    }

    private func normalizedHotkeyRegistrationRequest(
        from values: AppKitSettingsHotkeyRawValues
    ) -> HotkeyRegistrationRequest {
        HotkeyRegistrationRequest.normalized(
            mainPrimaryModifierRaw: values.hotkeyPrimaryModifierRaw,
            mainKeyRaw: values.hotkeyMainKeyRaw,
            quitKeyRaw: values.hotkeyQuitKeyRaw,
            inAppPrimaryModifierRaw: values.inAppWindowHotkeyPrimaryModifierRaw,
            inAppMainKeyRaw: values.inAppWindowHotkeyMainKeyRaw
        )
    }

    private func applyNormalizedHotkeyValues(from request: HotkeyRegistrationRequest) {
        if hotkeyPrimaryModifierRaw != request.mainConfiguration.primaryModifier.rawValue {
            hotkeyPrimaryModifierRaw = request.mainConfiguration.primaryModifier.rawValue
        }
        if hotkeyMainKeyRaw != request.mainConfiguration.mainKey.rawValue {
            hotkeyMainKeyRaw = request.mainConfiguration.mainKey.rawValue
        }
        if hotkeyQuitKeyRaw != request.mainConfiguration.quitKey.rawValue {
            hotkeyQuitKeyRaw = request.mainConfiguration.quitKey.rawValue
        }
        if inAppWindowHotkeyPrimaryModifierRaw != request.inAppWindowConfiguration.primaryModifier.rawValue {
            inAppWindowHotkeyPrimaryModifierRaw = request.inAppWindowConfiguration.primaryModifier.rawValue
        }
        if inAppWindowHotkeyMainKeyRaw != request.inAppWindowConfiguration.mainKey.rawValue {
            inAppWindowHotkeyMainKeyRaw = request.inAppWindowConfiguration.mainKey.rawValue
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
        notifyHotkeyConfigChanged(using: request)
    }

    @MainActor
    private func notifyHotkeyConfigChangedIfNeeded(using request: HotkeyRegistrationRequest) {
        let signature = hotkeyRequestSignature(request)
        guard signature != lastNotifiedHotkeySignature else { return }
        lastNotifiedHotkeySignature = signature
        notifyHotkeyConfigChanged(using: request)
    }

    @MainActor
    private func notifyHotkeyConfigChanged(using request: HotkeyRegistrationRequest) {
        lastNotifiedHotkeySignature = hotkeyRequestSignature(request)
        persistHotkeyRegistrationRequest(request)
        RuntimeLog.info(
            .hotKey,
            "updated main=\(request.mainConfiguration.mainShortcutText) backward=\(request.mainConfiguration.backwardShortcutText) quit=\(request.mainConfiguration.quitShortcutText) inApp=\(request.inAppWindowConfiguration.mainShortcutText) inAppBackward=\(request.inAppWindowConfiguration.backwardShortcutText)"
        )
        if let appDelegate = AppDelegate.shared {
            appDelegate.requestHotkeyReload(using: request, source: "settings_view")
        } else {
            RuntimeLog.info(
                .hotKey,
                "re-register requested source=settings_view requestID=\(request.requestID.uuidString) action=notification_only"
            )
            NotificationCenter.default.post(
                name: .flowTabReRegisterHotkeys,
                object: nil,
                userInfo: request.notificationUserInfo
            )
        }
    }

    private func hotkeyRequestSignature(_ request: HotkeyRegistrationRequest) -> String {
        [
            request.mainConfiguration.primaryModifier.rawValue,
            request.mainConfiguration.mainKey.rawValue,
            request.mainConfiguration.quitKey.rawValue,
            request.inAppWindowConfiguration.primaryModifier.rawValue,
            request.inAppWindowConfiguration.mainKey.rawValue
        ].joined(separator: "|")
    }

    private func notifyAppVisibilityPreferenceChanged() {
        refreshHiddenAppCount()
        RuntimeLog.info(
            .app,
            "showInCommandTab=\(showInCommandTab)"
        )
        NotificationCenter.default.post(name: .flowTabAppVisibilityPreferenceChanged, object: nil)
    }

    private func refreshHiddenAppCount() {
        hiddenAppCount = AppVisibilityPreferencesStore.loadHiddenAppIDs().count
    }

    private func notifyLanguagePreferenceChanged() {
        RuntimeLog.info(.app, "language=\(appLanguageRaw)")
        NotificationCenter.default.post(name: .flowTabLanguagePreferenceChanged, object: nil)
    }

    private func startPermissionPolling(target: PermissionPollingTarget) {
        cancelPermissionPolling(target: target)
        let generation = advancePermissionPollingGeneration(for: target)
        let task = Task { @MainActor in
            let startMs = RuntimePerformanceClock.monotonicMilliseconds()
            for _ in 0..<permissionPollAttemptLimit {
                try? await Task.sleep(nanoseconds: permissionPollIntervalNanoseconds)
                let trusted = refreshPermissionStatus(for: target)
                if trusted {
                    RuntimeLog.info(.permission, permissionPollingSuccessMessage(for: target))
                    clearPermissionPollingTaskIfCurrent(target: target, generation: generation)
                    return
                }
            }
            let diagnostic = permissionPollingDiagnostic(
                target: target,
                startMs: startMs,
                finalPermissionGranted: permissionGranted(for: target)
            )
            RuntimeLog.warning(
                .permission,
                diagnostic.logMessage
            )
            clearPermissionPollingTaskIfCurrent(target: target, generation: generation)
        }
        permissionPollTasksByTarget[target] = task
        permissionPollingTaskRegistry.markStarted(target)
    }

    @discardableResult
    private func advancePermissionPollingGeneration(for target: PermissionPollingTarget) -> UInt64 {
        let nextGeneration = (permissionPollingGenerationsByTarget[target] ?? 0) &+ 1
        permissionPollingGenerationsByTarget[target] = nextGeneration
        return nextGeneration
    }

    private func clearPermissionPollingTaskIfCurrent(
        target: PermissionPollingTarget,
        generation: UInt64
    ) {
        guard permissionPollingGenerationsByTarget[target] == generation else { return }
        permissionPollTasksByTarget[target] = nil
        permissionPollingTaskRegistry.markStopped(target)
    }

    private func refreshPermissionStatus(for target: PermissionPollingTarget) -> Bool {
        switch target {
        case .accessibility:
            refreshAccessibilityStatus()
        case .screenCapture:
            refreshScreenCaptureStatus()
        }
        return permissionGranted(for: target)
    }

    private func permissionGranted(for target: PermissionPollingTarget) -> Bool {
        switch target {
        case .accessibility:
            accessibilityTrusted
        case .screenCapture:
            screenCaptureTrusted
        }
    }

    private func permissionPollingSuccessMessage(for target: PermissionPollingTarget) -> String {
        switch target {
        case .accessibility:
            return "trusted=true after prompt bundle=\(bundleIdentifier) path=\(bundlePath)"
        case .screenCapture:
            return "screenCapture trusted=true after prompt bundle=\(bundleIdentifier) path=\(bundlePath)"
        }
    }

    private func permissionPollingDiagnostic(
        target: PermissionPollingTarget,
        startMs: Double,
        finalPermissionGranted: Bool
    ) -> PermissionPollingDiagnostic {
        PermissionPollingDiagnostic(
            target: target,
            attempt: permissionPollAttemptLimit,
            attemptLimit: permissionPollAttemptLimit,
            elapsedMs: max(0, RuntimePerformanceClock.monotonicMilliseconds() - startMs),
            finalPermissionGranted: finalPermissionGranted,
            timeoutDescription: permissionPollTimeoutDescription,
            bundleIdentifier: bundleIdentifier,
            bundlePath: bundlePath,
            action: .timeout
        )
    }
}
