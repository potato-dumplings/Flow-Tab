import SwiftUI
import AppKit
import FlowTabCore

struct AppSettingsView: View {
    let isActive: Bool
    let appVisibilityNavigationAnimationPolicy:
        SettingsAppVisibilityNavigationAnimationPolicy

    init(
        isActive: Bool,
        appVisibilityNavigationAnimationPolicy:
            SettingsAppVisibilityNavigationAnimationPolicy = .default
    ) {
        self.isActive = isActive
        self.appVisibilityNavigationAnimationPolicy =
            appVisibilityNavigationAnimationPolicy
    }

    @ObservedObject private var presentation = FlowPresentationState.shared
    @AppStorage(AppPreferenceKeys.showShortcutHint) private var showShortcutHint = true
    @AppStorage(AppPreferenceKeys.showInCommandTab)
    private var showInCommandTab = AppVisibilityPreferencesStore.defaultShowInCommandTab
    @AppStorage(AppPreferenceKeys.showPermissionReminder) private var showPermissionReminder = true
    @AppStorage(AppPreferenceKeys.allowLaunchAtLogin)
    private var allowLaunchAtLogin = LaunchAtLoginPreferencesStore.defaultAllowLaunchAtLogin
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
    private var hotkeyPrimaryModifierRaw = SwitcherHotkeyPreferencesStore.defaultBaseKeys.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyReverseModifiers)
    private var hotkeyReverseModifiersRaw =
        SwitcherHotkeyPreferencesStore.defaultReverseKeys.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyMainKey)
    private var hotkeyMainKeyRaw = SwitcherHotkeyPreferencesStore.defaultMainKeys.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyQuitKey)
    private var hotkeyQuitKeyRaw = SwitcherHotkeyPreferencesStore.defaultQuitKeys.rawValue
    @AppStorage(AppPreferenceKeys.inAppWindowHotkeyShortcutKeys)
    private var inAppWindowHotkeyShortcutKeysRaw =
        InAppWindowHotkeyPreferencesStore.defaultShortcutKeys.rawValue
    @AppStorage(AppPreferenceKeys.inAppWindowHotkeyReverseKeys)
    private var inAppWindowHotkeyReverseKeysRaw =
        InAppWindowHotkeyPreferencesStore.defaultReverseKeys.rawValue
    @AppStorage(AppPreferenceKeys.windowLayerAutoEnterDelay)
    private var windowLayerAutoEnterDelayRaw = WindowLayerPreferencesStore.defaultAutoEnterDelay
    @State private var accessibilityTrusted = AccessibilityPermissionChecker.isTrusted()
    @State private var screenCaptureTrusted = ScreenCapturePermissionChecker.hasScreenCapturePermission
    @State private var hasAttemptedScreenCapturePermissionRequest = false
    @StateObject private var permissionObservationCoordinator =
        RuntimePermissionObservationCoordinator()
    @StateObject private var hotkeyRegistrationObservationOwner =
        HotkeyRegistrationObservationOwner()
    @State private var windowLayerAutoEnterDelayText = ""
    @State private var didInitialize = false
    @State private var isWindowLayerAutoEnterDelayEditing = false
    @State private var isApplyingLaunchAtLoginPreference = false
    @State private var lastNotifiedHotkeySignature = ""
    @State private var hotkeyConflict: HotkeySettingsConflictPresentation?
    @State private var hotkeyPermissionRequirement:
        HotkeySettingsPermissionPresentation?
    @State private var hiddenAppCount = AppVisibilityPreferencesStore.loadHiddenAppIDs().count
    @State private var showsAppVisibilityManager = false

    private let permissionObservationPolicy:
        RuntimePermissionObservationPolicy = .standard

    private var appVisibilityNavigationAnimation: Animation {
        .easeInOut(duration: appVisibilityNavigationAnimationPolicy.duration)
    }

    private var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "unknown"
    }

    private var bundlePath: String {
        Bundle.main.bundlePath
    }

    private var hotkeyConfiguration: SwitcherHotkeyConfiguration {
        SwitcherHotkeyPreferencesStore.resolve(
            baseKeysRaw: hotkeyPrimaryModifierRaw,
            reverseKeysRaw: hotkeyReverseModifiersRaw,
            mainKeysRaw: hotkeyMainKeyRaw,
            quitKeysRaw: hotkeyQuitKeyRaw
        )
    }

    private var inAppWindowHotkeyConfiguration: SwitcherHotkeyConfiguration {
        let resolved = InAppWindowHotkeyPreferencesStore.resolve(
            shortcutKeysRaw: inAppWindowHotkeyShortcutKeysRaw,
            reverseKeysRaw: inAppWindowHotkeyReverseKeysRaw
        )
        return resolved.configuration
    }

    private var currentHotkeyRegistrationRequest: HotkeyRegistrationRequest {
        HotkeyRegistrationRequest(
            mainConfiguration: hotkeyConfiguration,
            inAppWindowConfiguration: inAppWindowHotkeyConfiguration
        )
    }

    private var commandTabTakeoverRegistrationState: CommandTabTakeoverRegistrationState {
        hotkeyRegistrationObservationOwner.takeoverState(
            matching: currentHotkeyRegistrationRequest
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
        presentation.context.appearanceRebuildIdentity
    }

    private var themeModeRaw: String {
        presentation.context.themeMode.rawValue
    }

    private var appLanguageRaw: String {
        presentation.context.appLanguage.rawValue
    }

    private var themeModeBinding: Binding<String> {
        Binding(
            get: { themeModeRaw },
            set: { FlowPresentationState.shared.setThemeMode(rawValue: $0) }
        )
    }

    private var appLanguageBinding: Binding<String> {
        Binding(
            get: { appLanguageRaw },
            set: { FlowPresentationState.shared.setAppLanguage(rawValue: $0) }
        )
    }

    var body: some View {
        ZStack {
            FlowPageBackdropView()

            AppKitSettingsPageContent(
                isActive: isActive && !showsAppVisibilityManager,
                showShortcutHint: $showShortcutHint,
                showInCommandTab: showInCommandTabPreference,
                themeModeRaw: themeModeBinding,
                appLanguageRaw: appLanguageBinding,
                presentationContext: presentation.context,
                windowLayerAutoEnterDelayText: windowLayerAutoEnterDelayText,
                autoRestoreMinimizedWindowOnSwitch: $autoRestoreMinimizedWindowOnSwitch,
                hideMinimizedAppsFromAppLayer: $hideMinimizedAppsFromAppLayer,
                showPermissionReminder: $showPermissionReminder,
                allowLaunchAtLogin: $allowLaunchAtLogin,
                searchEnabled: $searchEnabled,
                searchDefaultScopeRaw: $searchDefaultScopeRaw,
                hiddenAppCount: hiddenAppCount,
                hotkeyPrimaryModifierRaw: $hotkeyPrimaryModifierRaw,
                hotkeyReverseModifiersRaw: $hotkeyReverseModifiersRaw,
                hotkeyMainKeyRaw: $hotkeyMainKeyRaw,
                hotkeyQuitKeyRaw: $hotkeyQuitKeyRaw,
                inAppWindowHotkeyShortcutKeysRaw:
                    $inAppWindowHotkeyShortcutKeysRaw,
                inAppWindowHotkeyReverseKeysRaw:
                    $inAppWindowHotkeyReverseKeysRaw,
                commandTabTakeoverRegistrationState: commandTabTakeoverRegistrationState,
                hotkeyConflict: hotkeyConflict,
                hotkeyPermissionRequirement:
                    hotkeyPermissionRequirement,
                accessibilityTrusted: accessibilityTrusted,
                screenCaptureTrusted: screenCaptureTrusted,
                onWindowLayerAutoEnterDelayTextChanged: applyWindowLayerAutoEnterDelayText,
                onWindowLayerAutoEnterDelayTextCommitted: commitWindowLayerAutoEnterDelayText,
                onWindowLayerAutoEnterDelayEditingChanged: {
                    isWindowLayerAutoEnterDelayEditing = $0
                },
                onHotkeyChanged: handleHotkeyChanged,
                onDismissHotkeyConflict: dismissHotkeyValidation,
                onLaunchAtLoginChanged: handleLaunchAtLoginChanged,
                onManageAppVisibility: {
                    dismissHotkeyValidation()
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
        .onChange(of: hotkeyReverseModifiersRaw) { _ in
            handleStoredMainHotkeyChanged()
        }
        .onChange(of: hotkeyMainKeyRaw) { _ in
            handleStoredMainHotkeyChanged()
        }
        .onChange(of: hotkeyQuitKeyRaw) { _ in
            handleStoredMainHotkeyChanged()
        }
        .onChange(of: inAppWindowHotkeyShortcutKeysRaw) { _ in
            handleStoredInAppWindowHotkeyChanged()
        }
        .onChange(of: inAppWindowHotkeyReverseKeysRaw) { _ in
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
            for: NSApplication.didResignActiveNotification
        )) { _ in
            dismissHotkeyValidation()
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
            dismissHotkeyValidation()
            cancelPermissionObservation()
            hotkeyRegistrationObservationOwner.stop()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("flowtab.tab.settings.content")
    }

    @MainActor
    private func handleVisibilityChanged(_ active: Bool) {
        guard active else {
            dismissHotkeyValidation()
            cancelPermissionObservation()
            hotkeyRegistrationObservationOwner.stop()
            return
        }
        hotkeyRegistrationObservationOwner.start()
        if !didInitialize {
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

    private func cancelPermissionObservation() {
        permissionObservationCoordinator.cancelAll()
    }

    private func requestAccessibilityPermission() {
        let initialEvidence = startPermissionObservation(
            target: .accessibility
        )
        guard !initialEvidence.isGranted else { return }

        let requestReturnedGranted =
            AccessibilityPermissionChecker.requestPermission()
        RuntimeLog.info(
            .permission,
            "prompt requested returnedGranted=\(requestReturnedGranted) bundle=\(bundleIdentifier) path=\(bundlePath)"
        )
        permissionObservationCoordinator.readback(
            target: .accessibility,
            source: .requestReadback
        )
    }

    private func requestScreenCapturePermission() {
        let initialEvidence = startPermissionObservation(
            target: .screenCapture
        )
        guard !initialEvidence.isGranted else {
            hasAttemptedScreenCapturePermissionRequest = false
            return
        }

        let requestReturnedGranted =
            ScreenCapturePermissionChecker.requestScreenCapturePermission()
        RuntimeLog.info(
            .permission,
            "screenCapture prompt requested returnedGranted=\(requestReturnedGranted) bundle=\(bundleIdentifier) path=\(bundlePath)"
        )
        let requestEvidence = permissionObservationCoordinator.readback(
            target: .screenCapture,
            source: .requestReadback
        )
        if requestEvidence?.isGranted == false {
            // Screen capture prompts are often one-shot after denial; keep first click as request, then route later clicks.
            if hasAttemptedScreenCapturePermissionRequest {
                presentScreenCapturePermissionReminder()
            } else {
                hasAttemptedScreenCapturePermissionRequest = true
            }
        } else {
            hasAttemptedScreenCapturePermissionRequest = false
        }
    }

    private func presentScreenCapturePermissionReminder() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = AppStrings.text(.alertScreenDeniedTitle, language: presentation.context.appLanguage)
        alert.informativeText = AppStrings.text(.alertScreenDeniedMessage, language: presentation.context.appLanguage)
        alert.addButton(
            withTitle: AppStrings.text(.alertOpenSystemSettings, language: presentation.context.appLanguage)
        )
        alert.addButton(withTitle: AppStrings.text(.alertLater, language: presentation.context.appLanguage))
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
        if accessibilityTrusted {
            hotkeyPermissionRequirement = nil
        }
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
        if hotkeyPrimaryModifierRaw != resolved.baseKeys.rawValue {
            hotkeyPrimaryModifierRaw = resolved.baseKeys.rawValue
        }
        if hotkeyReverseModifiersRaw != resolved.reverseKeys.rawValue {
            hotkeyReverseModifiersRaw = resolved.reverseKeys.rawValue
        }
        if hotkeyMainKeyRaw != resolved.mainKeys.rawValue {
            hotkeyMainKeyRaw = resolved.mainKeys.rawValue
        }
        if hotkeyQuitKeyRaw != resolved.quitKeys.rawValue {
            hotkeyQuitKeyRaw = resolved.quitKeys.rawValue
        }
    }

    private func enforceInAppWindowHotkeyConsistency() {
        let resolved = InAppWindowHotkeyPreferencesStore.resolveAvoidingSwitcherHotkeyConflicts(
            shortcutKeysRaw: inAppWindowHotkeyShortcutKeysRaw,
            reverseKeysRaw: inAppWindowHotkeyReverseKeysRaw,
            switcherConfiguration: hotkeyConfiguration
        )
        if inAppWindowHotkeyShortcutKeysRaw != resolved.shortcutKeys.rawValue {
            inAppWindowHotkeyShortcutKeysRaw = resolved.shortcutKeys.rawValue
        }
        if inAppWindowHotkeyReverseKeysRaw
            != resolved.reverseKeys.rawValue
        {
            inAppWindowHotkeyReverseKeysRaw =
                resolved.reverseKeys.rawValue
        }
    }

    @MainActor
    private func handleHotkeyChanged(_ candidate: HotkeySettingsChangeCandidate) {
        let result = HotkeySettingsChangeTransaction.apply(
            candidate,
            accessibilityTrusted: accessibilityTrusted
        ) { request in
            applyNormalizedHotkeyValues(from: request)
            notifyHotkeyConfigChanged(using: request)
        }
        switch result {
        case .applied:
            dismissHotkeyValidation()
        case let .conflict(conflict):
            hotkeyPermissionRequirement = nil
            hotkeyConflict = HotkeySettingsConflictPresentation(
                field: candidate.field,
                conflict: conflict
            )
            RuntimeLog.warning(
                .hotKey,
                "settings conflict=\(conflict.rawValue) field=\(candidate.field.rawValue) action=rejected"
            )
        case .accessibilityRequired:
            hotkeyConflict = nil
            hotkeyPermissionRequirement =
                HotkeySettingsPermissionPresentation(
                    field: candidate.field
                )
            RuntimeLog.warning(
                .hotKey,
                "settings accessibilityRequired field=\(candidate.field.rawValue) action=rejected"
            )
        }
    }

    @MainActor
    private func dismissHotkeyValidation() {
        hotkeyConflict = nil
        hotkeyPermissionRequirement = nil
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

    private func applyNormalizedHotkeyValues(from request: HotkeyRegistrationRequest) {
        if hotkeyPrimaryModifierRaw != request.mainConfiguration.baseKeys.rawValue {
            hotkeyPrimaryModifierRaw = request.mainConfiguration.baseKeys.rawValue
        }
        if hotkeyReverseModifiersRaw
            != request.mainConfiguration.reverseKeys.rawValue
        {
            hotkeyReverseModifiersRaw =
                request.mainConfiguration.reverseKeys.rawValue
        }
        if hotkeyMainKeyRaw != request.mainConfiguration.mainKeys.rawValue {
            hotkeyMainKeyRaw = request.mainConfiguration.mainKeys.rawValue
        }
        if hotkeyQuitKeyRaw != request.mainConfiguration.quitKeys.rawValue {
            hotkeyQuitKeyRaw = request.mainConfiguration.quitKeys.rawValue
        }
        if inAppWindowHotkeyShortcutKeysRaw
            != request.inAppWindowConfiguration.baseKeys.rawValue
        {
            inAppWindowHotkeyShortcutKeysRaw =
                request.inAppWindowConfiguration.baseKeys.rawValue
        }
        if inAppWindowHotkeyReverseKeysRaw
            != request.inAppWindowConfiguration.reverseKeys.rawValue
        {
            inAppWindowHotkeyReverseKeysRaw =
                request.inAppWindowConfiguration.reverseKeys.rawValue
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
            request.mainConfiguration.baseKeys.rawValue,
            forKey: AppPreferenceKeys.hotkeyPrimaryModifier
        )
        userDefaults.set(
            request.mainConfiguration.reverseKeys.rawValue,
            forKey: AppPreferenceKeys.hotkeyReverseModifiers
        )
        userDefaults.set(request.mainConfiguration.mainKeys.rawValue, forKey: AppPreferenceKeys.hotkeyMainKey)
        userDefaults.set(request.mainConfiguration.quitKeys.rawValue, forKey: AppPreferenceKeys.hotkeyQuitKey)
        userDefaults.set(
            request.inAppWindowConfiguration.baseKeys.rawValue,
            forKey: AppPreferenceKeys.inAppWindowHotkeyShortcutKeys
        )
        userDefaults.set(
            request.inAppWindowConfiguration.reverseKeys.rawValue,
            forKey: AppPreferenceKeys.inAppWindowHotkeyReverseKeys
        )
    }

    @MainActor
    private func notifyHotkeyConfigChangedIfNeeded(using request: HotkeyRegistrationRequest) {
        let signature = request.configurationSignature
        guard signature != lastNotifiedHotkeySignature else { return }
        lastNotifiedHotkeySignature = signature
        guard
            !hotkeyRegistrationObservationOwner
                .hasMatchingRegistration(for: request)
        else {
            return
        }
        notifyHotkeyConfigChanged(using: request)
    }

    @MainActor
    private func notifyHotkeyConfigChanged(using request: HotkeyRegistrationRequest) {
        lastNotifiedHotkeySignature = request.configurationSignature
        hotkeyRegistrationObservationOwner.prepare(for: request)
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
        hotkeyRegistrationObservationOwner.readback()
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

    private func startPermissionObservation(
        target: RuntimePermissionTarget
    ) -> RuntimePermissionObservationEvidence {
        permissionObservationCoordinator.start(
            target: target,
            mode: permissionObservationPolicy.permissionRequestMode,
            readPermission: {
                permissionReadback(for: target)
            },
            onEvidence: { evidence in
                applyPermissionEvidence(evidence)
            },
            onWatchdog: { diagnostic in
                RuntimeLog.warning(.permission, diagnostic.logMessage)
            }
        )
    }

    private func permissionReadback(
        for target: RuntimePermissionTarget
    ) -> Bool {
        switch target {
        case .accessibility:
            return AccessibilityPermissionChecker.isTrusted()
        case .screenCapture:
            return ScreenCapturePermissionChecker.hasScreenCapturePermission
        }
    }

    private func applyPermissionEvidence(
        _ evidence: RuntimePermissionObservationEvidence
    ) {
        switch evidence.target {
        case .accessibility:
            accessibilityTrusted = evidence.isGranted
            if evidence.isGranted {
                hotkeyPermissionRequirement = nil
            }
        case .screenCapture:
            screenCaptureTrusted = evidence.isGranted
            if evidence.isGranted {
                hasAttemptedScreenCapturePermissionRequest = false
            }
        }
        guard evidence.isGranted,
              evidence.source != .initialReadback
        else {
            return
        }
        RuntimeLog.info(
            .permission,
            [
                "permission observed",
                "target=\(evidence.target.rawValue)",
                "source=\(evidence.source.rawValue)",
                "readbacks=\(evidence.readbackCount)",
                "elapsedMs=\(String(format: "%.3f", evidence.elapsedMs))",
                "bundle=\(bundleIdentifier)",
                "path=\(bundlePath)"
            ].joined(separator: " ")
        )
    }
}
