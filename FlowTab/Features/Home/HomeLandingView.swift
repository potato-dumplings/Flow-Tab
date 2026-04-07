import SwiftUI
import AppKit
import ApplicationServices
import FlowTabCore

@MainActor
struct HomeLandingView: View {
    private static let snapshotQueue = DispatchQueue(
        label: "FlowTab.HomeLandingSnapshotQueue",
        qos: .utility
    )
    private static let snapshotProvider = RuntimeSnapshotProvider()
    private static var cachedAppSummaries: [RuntimeHomeAppSummary] = []
    private static var cachedWindowsByAppID: [String: [WindowCandidate]] = [:]
    private static var cachedSelectedAppID: String?
    private static var cachedAccessibilityTrusted = AccessibilityPermissionChecker.isTrusted()
    private static var cachedScreenCaptureTrusted = ScreenCapturePermissionChecker.hasScreenCapturePermission
    private static var cachedRunningAppSignature: Set<String> = []

    let isActive: Bool
    let openSettings: () -> Void

    @AppStorage(AppPreferenceKeys.showPermissionReminder)
    private var showPermissionReminder = true
    @AppStorage(AppPreferenceKeys.hotkeyPrimaryModifier)
    private var hotkeyPrimaryModifierRaw = SwitcherHotkeyPreferencesStore.defaultPrimaryModifier.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyMainKey)
    private var hotkeyMainKeyRaw = SwitcherHotkeyPreferencesStore.defaultMainKey.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyQuitKey)
    private var hotkeyQuitKeyRaw = SwitcherHotkeyPreferencesStore.defaultQuitKey.rawValue
    @AppStorage(AppPreferenceKeys.appLanguage)
    private var appLanguageRaw = AppLanguagePreferencesStore.defaultLanguage.rawValue
    @State private var accessibilityTrusted = AccessibilityPermissionChecker.isTrusted()
    @State private var screenCaptureTrusted = ScreenCapturePermissionChecker.hasScreenCapturePermission
    @State private var appSummaries: [RuntimeHomeAppSummary] = []
    @State private var windowsByAppID: [String: [WindowCandidate]] = [:]
    @State private var selectedAppID: String?
    @State private var appSummariesRefreshTask: Task<Void, Never>?
    @State private var selectedAppRefreshTask: Task<Void, Never>?
    @State private var appRefreshTasksByID: [String: Task<Void, Never>] = [:]
    @State private var permissionWatchTask: Task<Void, Never>?
    @State private var windowChangeMonitor = HomeWindowChangeMonitor()

    private let appRefreshDebounceDelayNs: UInt64 = 220_000_000
    private let selectedAppRefreshDebounceDelayNs: UInt64 = 120_000_000
    private let permissionPollIntervalNs: UInt64 = 1_000_000_000

    private var hotkeyConfiguration: SwitcherHotkeyConfiguration {
        SwitcherHotkeyPreferencesStore.resolve(
            primaryModifierRaw: hotkeyPrimaryModifierRaw,
            mainKeyRaw: hotkeyMainKeyRaw,
            quitKeyRaw: hotkeyQuitKeyRaw
        )
    }

    private var shouldShowPermissionGuide: Bool {
        showPermissionReminder && (!accessibilityTrusted || !screenCaptureTrusted)
    }

    private var appLanguage: AppLanguage {
        AppLanguagePreferencesStore.resolve(rawValue: appLanguageRaw)
    }

    private var permissionGuideMessage: String {
        if !accessibilityTrusted && !screenCaptureTrusted {
            return AppStrings.text(.permissionGuideAll, language: appLanguage)
        }
        if !accessibilityTrusted {
            return AppStrings.text(.permissionGuideAccessibility, language: appLanguage)
        }
        if !screenCaptureTrusted {
            return AppStrings.text(.permissionGuideScreenCapture, language: appLanguage)
        }
        return AppStrings.text(.permissionGuideReady, language: appLanguage)
    }

    var body: some View {
        ZStack {
            HomeBackdropView()

            VStack(alignment: .leading, spacing: 12) {
                if shouldShowPermissionGuide {
                    permissionGuideBanner
                }

                HStack(alignment: .top, spacing: 12) {
                    appLayerCard
                    windowLayerCard
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .padding(.top, HomePageLayout.alignedTopInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            handleVisibilityChanged(isActive)
        }
        .onChange(of: isActive) { active in
            if active {
                handleVisibilityChanged(true)
            }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didLaunchApplicationNotification
        )) { _ in
            guard isActive else { return }
            scheduleAppSummariesRefresh(reason: "workspace_launch")
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didTerminateApplicationNotification
        )) { _ in
            guard isActive else { return }
            scheduleAppSummariesRefresh(reason: "workspace_terminate")
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            guard isActive else { return }
            refreshPermissionsIfNeeded(reason: "app_active")
            scheduleRefreshIfRunningAppsChanged(reason: "app_active")
        }
        .onDisappear {
            teardownActiveState()
        }
        .accessibilityIdentifier("flowtab.tab.home.content")
    }

    private var permissionGuideBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)

            Text(permissionGuideMessage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)

            FlowActionButton(
                title: AppStrings.text(.actionGoToSettings, language: appLanguage),
                tone: .blueDominant,
                accessibilityIdentifier: "flowtab.home.permission.open-settings"
            ) {
                openSettings()
            }

            FlowActionButton(
                title: AppStrings.text(.actionDontRemindAgain, language: appLanguage),
                tone: .grayDominant,
                accessibilityIdentifier: "flowtab.home.permission.dismiss"
            ) {
                showPermissionReminder = false
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("flowtab.home.permission.banner")
    }

    private var appLayerCard: some View {
        HomeSectionCard(
            title: AppStrings.text(.homeAppLayerTitle, language: appLanguage),
            subtitle: AppStrings.text(.homeAppLayerSubtitle, language: appLanguage)
        ) {
            if appSummaries.isEmpty {
                HomeLayerRowView(
                    title: AppStrings.text(.homeNoSwitchableApps, language: appLanguage),
                    subtitle: AppStrings.text(
                        .homeTriggerHotkeyFirst,
                        replacements: ["hotkey": hotkeyConfiguration.mainShortcutText],
                        language: appLanguage
                    ),
                    trailing: "0w",
                    isSelected: false
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(appSummaries) { app in
                            Button {
                                selectApp(app.appID)
                            } label: {
                                HomeLayerRowView(
                                    title: app.displayName,
                                    subtitle: app.appID,
                                    trailing: "\(app.windowCount)w",
                                    isSelected: app.appID == currentSelectedAppID
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("flowtab.home.app.\(app.appID.flowTabAccessibilitySlug)")
                        }
                    }
                }
                .frame(minHeight: 180, maxHeight: 500)
            }
        }
    }

    private var windowLayerCard: some View {
        let activeApp = appSummaries.first(where: { $0.appID == currentSelectedAppID }) ?? appSummaries.first
        let activeWindows = activeApp.flatMap { windowsByAppID[$0.appID] } ?? []

        return HomeSectionCard(
            title: AppStrings.text(.homeWindowLayerTitle, language: appLanguage),
            subtitle: activeApp.map {
                AppStrings.text(
                    .homeAppWindowsOf,
                    replacements: ["app": $0.displayName],
                    language: appLanguage
                )
            } ?? AppStrings.text(.homeCurrentAppWindows, language: appLanguage)
        ) {
            if let activeApp, windowsByAppID[activeApp.appID] == nil {
                HomeLayerRowView(
                    title: AppStrings.text(.homeWindowDataLoading, language: appLanguage),
                    subtitle: AppStrings.text(
                        .homeReadingWindowsOf,
                        replacements: ["app": activeApp.displayName],
                        language: appLanguage
                    ),
                    trailing: "--",
                    isSelected: false
                )
            } else if !activeWindows.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(activeWindows.enumerated()), id: \.element.id) { index, window in
                            HomeLayerRowView(
                                title: windowTitle(window.title, index: index),
                                subtitle: "",
                                trailing: windowIdentifier(window.id),
                                isSelected: index == 0
                            )
                            .accessibilityIdentifier(
                                "flowtab.home.window.\(window.id.flowTabAccessibilitySlug)"
                            )
                        }
                    }
                }
                .frame(minHeight: 180, maxHeight: 500)
            } else if activeApp != nil {
                HomeLayerRowView(
                    title: AppStrings.text(.homeNoSwitchableWindows, language: appLanguage),
                    subtitle: AppStrings.text(.homeConfirmAccessibility, language: appLanguage),
                    trailing: "0w",
                    isSelected: false
                )
            } else {
                HomeLayerRowView(
                    title: AppStrings.text(.homeNoWindowData, language: appLanguage),
                    subtitle: AppStrings.text(.homeWaitCacheUpdate, language: appLanguage),
                    trailing: "--",
                    isSelected: false
                )
            }
        }
    }

    private var currentSelectedAppID: String? {
        if let selectedAppID, appSummaries.contains(where: { $0.appID == selectedAppID }) {
            return selectedAppID
        }
        return appSummaries.first?.appID
    }

    private func windowTitle(_ title: String, index: Int) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Window #\(index + 1)"
        }
        return trimmed
    }

    private func windowIdentifier(_ rawID: String) -> String {
        rawID.replacingOccurrences(of: "ax:", with: "").replacingOccurrences(of: ":", with: "-")
    }

    private func handleVisibilityChanged(_ active: Bool) {
        guard active else { return }

        restoreCachedStateIfNeeded()
        setupWindowMonitorIfNeeded()
        refreshPermissionsIfNeeded(reason: "appear")
        startPermissionWatcherIfNeeded()

        if appSummaries.isEmpty {
            scheduleAppSummariesRefresh(reason: "initial_load")
            return
        }

        scheduleRefreshIfRunningAppsChanged(reason: "appear")
        if let selectedAppID = currentSelectedAppID {
            scheduleSelectedAppRefresh(
                appID: selectedAppID,
                force: windowsByAppID[selectedAppID] == nil,
                reason: "ensure_selected_cache"
            )
        }
    }

    private func setupWindowMonitorIfNeeded() {
        guard accessibilityTrusted else {
            windowChangeMonitor.stop()
            return
        }

        windowChangeMonitor.onAppWindowChanged = { appID in
            scheduleSingleAppRefresh(appID: appID, reason: "ax_window_changed")
        }
        windowChangeMonitor.rebind(appSummaries)
    }

    private func restoreCachedStateIfNeeded() {
        if appSummaries.isEmpty {
            appSummaries = Self.cachedAppSummaries
        }
        if windowsByAppID.isEmpty {
            windowsByAppID = Self.cachedWindowsByAppID
        }
        if selectedAppID == nil {
            selectedAppID = Self.cachedSelectedAppID
        }
        accessibilityTrusted = Self.cachedAccessibilityTrusted
        screenCaptureTrusted = Self.cachedScreenCaptureTrusted
        syncSelectedApp()
    }

    private func startPermissionWatcherIfNeeded() {
        guard permissionWatchTask == nil else { return }
        permissionWatchTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: permissionPollIntervalNs)
                guard !Task.isCancelled else { return }
                refreshPermissionsIfNeeded(reason: "permission_poll")
            }
        }
    }

    private func refreshPermissionsIfNeeded(reason: String) {
        let newAccessibilityTrusted = AccessibilityPermissionChecker.isTrusted()
        let newScreenCaptureTrusted = ScreenCapturePermissionChecker.hasScreenCapturePermission
        let permissionChanged =
            newAccessibilityTrusted != accessibilityTrusted || newScreenCaptureTrusted != screenCaptureTrusted

        accessibilityTrusted = newAccessibilityTrusted
        screenCaptureTrusted = newScreenCaptureTrusted

        if permissionChanged {
            scheduleAppSummariesRefresh(reason: "permission_changed_\(reason)")
            if !newAccessibilityTrusted {
                windowChangeMonitor.stop()
            }
        }
        persistCache()
    }

    private func scheduleRefreshIfRunningAppsChanged(reason: String) {
        if currentRunningAppSignature() != Self.cachedRunningAppSignature {
            scheduleAppSummariesRefresh(reason: "running_apps_changed_\(reason)")
        }
    }

    private func currentRunningAppSignature() -> Set<String> {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let includeCurrentProcessInAppLayer = AppVisibilityPreferencesStore.loadShowInCommandTab()
        return Set(NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, !app.isTerminated else { return nil }
            guard includeCurrentProcessInAppLayer || app.processIdentifier != currentPID else { return nil }
            let appID = app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
            return "\(appID)#\(app.processIdentifier)"
        })
    }

    private func selectApp(_ appID: String) {
        selectedAppID = appID
        persistCache()
        scheduleSelectedAppRefresh(
            appID: appID,
            force: windowsByAppID[appID] == nil,
            reason: "manual_select"
        )
    }

    private func scheduleAppSummariesRefresh(reason: String) {
        appSummariesRefreshTask?.cancel()
        appSummariesRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: appRefreshDebounceDelayNs)
            await refreshAppSummaries(reason: reason)
            appSummariesRefreshTask = nil
        }
    }

    private func refreshAppSummaries(reason: String) async {
        let summaries = await fetchHomeAppSummariesOnBackground()
        guard !Task.isCancelled else { return }

        appSummaries = summaries
        let validAppIDs = Set(summaries.map(\.appID))
        windowsByAppID = windowsByAppID.filter { validAppIDs.contains($0.key) }
        syncSelectedApp()
        setupWindowMonitorIfNeeded()
        persistCache(updateRunningSignature: true)

        if let selectedAppID = currentSelectedAppID {
            let summaryCount = summaries.first(where: { $0.appID == selectedAppID })?.windowCount
            let cachedCount = windowsByAppID[selectedAppID]?.count
            scheduleSelectedAppRefresh(
                appID: selectedAppID,
                force: summaryCount == nil || cachedCount != summaryCount,
                reason: "selected_after_\(reason)"
            )
        }
    }

    private func scheduleSelectedAppRefresh(appID: String, force: Bool, reason: String) {
        guard force || windowsByAppID[appID] == nil else { return }
        selectedAppRefreshTask?.cancel()
        selectedAppRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: selectedAppRefreshDebounceDelayNs)
            await refreshSingleAppCache(
                appID: appID,
                updateWindows: true,
                reason: reason
            )
            selectedAppRefreshTask = nil
        }
    }

    private func scheduleSingleAppRefresh(appID: String, reason: String) {
        appRefreshTasksByID[appID]?.cancel()
        appRefreshTasksByID[appID] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: appRefreshDebounceDelayNs)
            let shouldUpdateWindows = appID == currentSelectedAppID || windowsByAppID[appID] != nil
            await refreshSingleAppCache(
                appID: appID,
                updateWindows: shouldUpdateWindows,
                reason: reason
            )
            appRefreshTasksByID[appID] = nil
        }
    }

    private func refreshSingleAppCache(
        appID: String,
        updateWindows: Bool,
        reason _: String
    ) async {
        guard !Task.isCancelled else { return }
        if updateWindows {
            let snapshot = await fetchHomeAppSnapshotOnBackground(appID: appID)
            guard !Task.isCancelled else { return }

            guard let snapshot else {
                appSummaries.removeAll { $0.appID == appID }
                windowsByAppID.removeValue(forKey: appID)
                syncSelectedApp()
                setupWindowMonitorIfNeeded()
                persistCache()
                if let selectedAppID = currentSelectedAppID, windowsByAppID[selectedAppID] == nil {
                    scheduleSelectedAppRefresh(
                        appID: selectedAppID,
                        force: true,
                        reason: "selected_after_remove"
                    )
                }
                return
            }

            if let existingIndex = appSummaries.firstIndex(where: { $0.appID == appID }) {
                appSummaries[existingIndex] = snapshot.summary
            } else {
                appSummaries.append(snapshot.summary)
            }
            windowsByAppID[appID] = snapshot.candidate.windows
        } else {
            let summary = await fetchHomeAppSummaryOnBackground(appID: appID)
            guard !Task.isCancelled else { return }
            guard let summary else {
                appSummaries.removeAll { $0.appID == appID }
                windowsByAppID.removeValue(forKey: appID)
                syncSelectedApp()
                setupWindowMonitorIfNeeded()
                persistCache()
                return
            }
            if let existingIndex = appSummaries.firstIndex(where: { $0.appID == appID }) {
                appSummaries[existingIndex] = summary
            } else {
                appSummaries.append(summary)
            }
        }

        appSummaries.sort { lhs, rhs in
            if lhs.lastActiveAt == rhs.lastActiveAt {
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            return lhs.lastActiveAt > rhs.lastActiveAt
        }
        syncSelectedApp()
        setupWindowMonitorIfNeeded()
        persistCache()
    }

    private func fetchHomeAppSummariesOnBackground() async -> [RuntimeHomeAppSummary] {
        await withCheckedContinuation { continuation in
            Self.snapshotQueue.async {
                continuation.resume(returning: Self.snapshotProvider.homeAppSummaries())
            }
        }
    }

    private func fetchHomeAppSummaryOnBackground(appID: String) async -> RuntimeHomeAppSummary? {
        await withCheckedContinuation { continuation in
            Self.snapshotQueue.async {
                continuation.resume(returning: Self.snapshotProvider.homeAppSummary(for: appID))
            }
        }
    }

    private func fetchHomeAppSnapshotOnBackground(appID: String) async -> RuntimeHomeAppSnapshot? {
        await withCheckedContinuation { continuation in
            Self.snapshotQueue.async {
                continuation.resume(returning: Self.snapshotProvider.homeAppSnapshot(for: appID))
            }
        }
    }

    private func syncSelectedApp() {
        guard !appSummaries.isEmpty else {
            selectedAppID = nil
            return
        }
        if let selectedAppID, appSummaries.contains(where: { $0.appID == selectedAppID }) {
            return
        }
        selectedAppID = appSummaries.first?.appID
    }

    private func persistCache(updateRunningSignature: Bool = false) {
        Self.cachedAccessibilityTrusted = accessibilityTrusted
        Self.cachedScreenCaptureTrusted = screenCaptureTrusted
        Self.cachedAppSummaries = appSummaries
        Self.cachedWindowsByAppID = windowsByAppID
        Self.cachedSelectedAppID = selectedAppID
        if updateRunningSignature {
            Self.cachedRunningAppSignature = currentRunningAppSignature()
        }
    }

    private func teardownActiveState() {
        appSummariesRefreshTask?.cancel()
        appSummariesRefreshTask = nil
        selectedAppRefreshTask?.cancel()
        selectedAppRefreshTask = nil
        for task in appRefreshTasksByID.values {
            task.cancel()
        }
        appRefreshTasksByID.removeAll()
        permissionWatchTask?.cancel()
        permissionWatchTask = nil
        windowChangeMonitor.stop()
        persistCache()
    }
}

@MainActor
private final class HomeWindowChangeMonitor {
    private final class ObserverContext {
        weak var monitor: HomeWindowChangeMonitor?
        let appID: String

        init(monitor: HomeWindowChangeMonitor, appID: String) {
            self.monitor = monitor
            self.appID = appID
        }
    }

    var onAppWindowChanged: ((String) -> Void)?

    private var observersByPID: [pid_t: AXObserver] = [:]
    private var observerContextByPID: [pid_t: ObserverContext] = [:]
    private var appIDByPID: [pid_t: String] = [:]
    private var lastEventAtByAppID: [String: TimeInterval] = [:]
    private let eventThrottleInterval: TimeInterval = 0.16
    private let watchedNotifications: [CFString] = [
        kAXWindowCreatedNotification as CFString,
        kAXUIElementDestroyedNotification as CFString,
        kAXFocusedWindowChangedNotification as CFString,
        kAXMainWindowChangedNotification as CFString,
        kAXWindowMiniaturizedNotification as CFString,
        kAXWindowDeminiaturizedNotification as CFString
    ]

    func rebind(_ appSummaries: [RuntimeHomeAppSummary]) {
        guard AccessibilityPermissionChecker.isTrusted() else {
            stop()
            return
        }

        let expectedByPID = Dictionary(uniqueKeysWithValues: appSummaries.map { ($0.pid, $0.appID) })

        for pid in Array(observersByPID.keys) {
            guard let expectedAppID = expectedByPID[pid], expectedAppID == appIDByPID[pid] else {
                removeObserver(pid: pid)
                continue
            }
        }

        for (pid, appID) in expectedByPID where observersByPID[pid] == nil {
            installObserver(pid: pid, appID: appID)
        }
    }

    func stop() {
        for pid in Array(observersByPID.keys) {
            removeObserver(pid: pid)
        }
        lastEventAtByAppID.removeAll()
    }

    private func installObserver(pid: pid_t, appID: String) {
        var observerRef: AXObserver?
        let result = AXObserverCreate(pid, Self.callback, &observerRef)
        guard result == .success, let observerRef else { return }

        let appElement = AXUIElementCreateApplication(pid)
        let context = ObserverContext(monitor: self, appID: appID)
        let contextPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(context).toOpaque())
        for notification in watchedNotifications {
            let addResult = AXObserverAddNotification(
                observerRef,
                appElement,
                notification,
                contextPointer
            )
            if addResult == .notificationUnsupported {
                continue
            }
            guard addResult == .success || addResult == .notificationAlreadyRegistered else { continue }
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observerRef),
            .defaultMode
        )
        observersByPID[pid] = observerRef
        observerContextByPID[pid] = context
        appIDByPID[pid] = appID
    }

    private func removeObserver(pid: pid_t) {
        guard let observer = observersByPID.removeValue(forKey: pid) else { return }

        let appElement = AXUIElementCreateApplication(pid)
        for notification in watchedNotifications {
            AXObserverRemoveNotification(observer, appElement, notification)
        }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        observerContextByPID.removeValue(forKey: pid)
        appIDByPID.removeValue(forKey: pid)
    }

    private func emitWindowChanged(for appID: String) {
        let now = ProcessInfo.processInfo.systemUptime
        if let lastTimestamp = lastEventAtByAppID[appID], now - lastTimestamp < eventThrottleInterval {
            return
        }
        lastEventAtByAppID[appID] = now
        onAppWindowChanged?(appID)
    }

    private static let callback: AXObserverCallback = { _, _, _, refcon in
        guard let refcon else { return }
        let context = Unmanaged<ObserverContext>.fromOpaque(refcon).takeUnretainedValue()
        Task { @MainActor in
            context.monitor?.emitWindowChanged(for: context.appID)
        }
    }
}

private struct HomeLayerRowView: View {
    let title: String
    let subtitle: String
    let trailing: String
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(trailing)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04))
        )
    }
}
