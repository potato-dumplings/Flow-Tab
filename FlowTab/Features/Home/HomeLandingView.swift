import SwiftUI
import AppKit
import FlowTabCore

@MainActor
struct HomeLandingView: View {
    private static var cachedAppSummaries: [RuntimeHomeAppSummary] = []
    private static var cachedWindowsByAppID: [String: [WindowCandidate]] = [:]
    private static var cachedSelectedAppID: String?
    private static var cachedAccessibilityTrusted = AccessibilityPermissionChecker.isTrusted()
    private static var cachedScreenCaptureTrusted = ScreenCapturePermissionChecker.hasScreenCapturePermission

    let isActive: Bool
    let appLanguage: AppLanguage
    let openSettings: () -> Void
    private let runtimeProjectionService: any RuntimeProjectionServing

    init(
        isActive: Bool,
        appLanguage: AppLanguage,
        runtimeProjectionService: any RuntimeProjectionServing = homeRuntimeProjectionService,
        openSettings: @escaping () -> Void
    ) {
        self.isActive = isActive
        self.appLanguage = appLanguage
        self.runtimeProjectionService = runtimeProjectionService
        self.openSettings = openSettings
    }

    @AppStorage(AppPreferenceKeys.showPermissionReminder)
    private var showPermissionReminder = true
    @AppStorage(AppPreferenceKeys.hotkeyPrimaryModifier)
    private var hotkeyPrimaryModifierRaw = SwitcherHotkeyPreferencesStore.defaultPrimaryModifier.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyMainKey)
    private var hotkeyMainKeyRaw = SwitcherHotkeyPreferencesStore.defaultMainKey.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyQuitKey)
    private var hotkeyQuitKeyRaw = SwitcherHotkeyPreferencesStore.defaultQuitKey.rawValue
    @State private var accessibilityTrusted = AccessibilityPermissionChecker.isTrusted()
    @State private var screenCaptureTrusted = ScreenCapturePermissionChecker.hasScreenCapturePermission
    @State private var appSummaries: [RuntimeHomeAppSummary] = []
    @State private var hiddenAppIDs = AppVisibilityPreferencesStore.loadHiddenAppIDs()
    @State private var windowsByAppID: [String: [WindowCandidate]] = [:]
    @State private var homeDetailProjectionsByAppID: [String: RuntimeHomeAppDetailProjection] = [:]
    @State private var homeSummaryProjectionFreshness: RuntimeProjectionFreshness?
    @State private var loadingWindowCountAppIDs: Set<String> = []
    @State private var selectedAppID: String?
    @State private var appSummariesRefreshTask: Task<Void, Never>?
    @State private var selectedAppRefreshTask: Task<Void, Never>?
    @State private var appRefreshTasksByID: [String: Task<Void, Never>] = [:]
    @State private var permissionWatchTask: Task<Void, Never>?
    @State private var windowChangeMonitor = RuntimeAXWindowChangeMonitor()

    private let appRefreshDebounceDelayNs: UInt64 = 220_000_000
    private let initialPreciseAppRefreshDelayNs: UInt64 = 900_000_000
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

    private var appVisibilityPresentation: HomeAppVisibilityPresentation {
        HomeAppVisibilityPresentation(hiddenAppIDs: hiddenAppIDs)
    }

    private var presentedAppSummaries: [RuntimeHomeAppSummary] {
        appVisibilityPresentation.orderedAppSummaries(appSummaries)
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
            FlowPageBackdropView()

            VStack(alignment: .leading, spacing: 12) {
                pageHeader

                if shouldShowPermissionGuide {
                    permissionGuideBanner
                }

                HStack(alignment: .top, spacing: 12) {
                    appLayerCard
                    windowLayerCard
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .top)

                HomeOverviewStatsBar(
                    stats: overviewStats,
                    language: appLanguage
                )
                .frame(
                    maxWidth: .infinity,
                    minHeight: HomePageLayout.bottomStatusHeight,
                    maxHeight: HomePageLayout.bottomStatusHeight
                )
            }
            .padding(.horizontal, FlowPageLayout.horizontalInset)
            .padding(.bottom, FlowPageLayout.bottomInset)
            .padding(.top, FlowPageLayout.alignedTopInset)
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
            for: .runtimeAppSwitcherProjectionDidUpdate
        )) { _ in
            guard isActive else { return }
            scheduleAppSummariesRefresh(reason: "runtime_projection_updated")
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            guard isActive else { return }
            refreshPermissionsIfNeeded(reason: "app_active")
            scheduleRuntimeProjectionRefresh(reason: "app_active")
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .flowTabAppVisibilityPreferenceChanged
        )) { _ in
            refreshHomeAppVisibility()
        }
        .onDisappear {
            teardownActiveState()
        }
        .accessibilityIdentifier("flowtab.tab.home.content")
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            HomeAccessibleText(
                text: AppStrings.text(.tabHome, language: appLanguage),
                font: .systemFont(ofSize: 22, weight: .semibold),
                textColor: .labelColor,
                accessibilityIdentifier: "flowtab.home.header"
            )
            .frame(height: 27)

            Text(AppStrings.text(.homePageSubtitle, language: appLanguage))
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var overviewStats: HomeOverviewStats {
        HomeOverviewStats.make(
            appSummaries: appSummaries,
            hiddenAppIDs: hiddenAppIDs,
            loadingWindowCountAppIDs: loadingWindowCountAppIDs
        )
    }

    private var permissionGuideBanner: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                permissionGuideMessageRow
                Spacer(minLength: 0)
                permissionGuideActionRow
            }

            VStack(alignment: .leading, spacing: 9) {
                permissionGuideMessageRow
                permissionGuideActionRow
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

    private var permissionGuideMessageRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)

            Text(permissionGuideMessage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var permissionGuideActionRow: some View {
        HStack(spacing: 8) {
            FlowPageActionButton(
                title: AppStrings.text(.actionGoToSettings, language: appLanguage),
                tone: .homePrimaryGradient,
                accessibilityIdentifier: "flowtab.home.permission.open-settings"
            ) {
                openSettings()
            }

            FlowPageActionButton(
                title: AppStrings.text(.actionDontRemindAgain, language: appLanguage),
                tone: .homeSecondaryGradient,
                accessibilityIdentifier: "flowtab.home.permission.dismiss"
            ) {
                showPermissionReminder = false
            }
        }
    }

    private var appLayerCard: some View {
        FlowPageSectionCard(
            title: AppStrings.text(.homeAppLayerTitle, language: appLanguage),
            subtitle: AppStrings.text(.homeAppLayerSubtitle, language: appLanguage),
            trailingText: AppStrings.appCount(presentedAppSummaries.count, language: appLanguage),
            trailingAccessibilityIdentifier: "flowtab.home.app.count"
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
                FlowSnappedListScrollView(
                    rowCount: presentedAppSummaries.count,
                    rowHeight: HomePageLayout.appLayerRowHeight,
                    rowSpacing: HomePageLayout.layerListRowSpacing,
                    accessibilityIdentifier: "flowtab.home.app.list"
                ) {
                    ForEach(presentedAppSummaries) { app in
                        let isHidden = appVisibilityPresentation.isHidden(appID: app.appID)
                        let isWindowCountLoading = loadingWindowCountAppIDs.contains(app.appID)
                        let appIDComponent = app.appID.flowTabAccessibilityIdentifierComponent
                        let hiddenBadge = isHidden
                            ? AppStrings.text(.homeAppNotShownBadge, language: appLanguage)
                            : nil
                        Button {
                            selectApp(app.appID)
                        } label: {
                            HomeLayerRowView(
                                title: app.displayName,
                                subtitle: app.appID,
                                trailing: "\(app.windowCount)w",
                                icon: HomeAppIconProvider.icon(for: app),
                                isTrailingLoading: isWindowCountLoading,
                                badge: hiddenBadge,
                                badgeAccessibilityIdentifier: isHidden
                                    ? "flowtab.home.app.hidden-badge.\(appIDComponent)"
                                    : nil,
                                isSelected: app.appID == currentSelectedAppID
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(height: HomePageLayout.appLayerRowHeight)
                        .accessibilityIdentifier("flowtab.home.app.\(appIDComponent)")
                        .accessibilityLabel(hiddenBadge.map { "\(app.displayName) \($0)" } ?? app.displayName)
                        .accessibilityValue(appAccessibilityValue(
                            windowCount: app.windowCount,
                            isHidden: isHidden,
                            isWindowCountLoading: isWindowCountLoading
                        ))
                    }
                }
            }
        }
    }

    private var windowLayerCard: some View {
        let activeApp = presentedAppSummaries.first(where: { $0.appID == currentSelectedAppID })
            ?? presentedAppSummaries.first
        let activeWindows = activeApp.flatMap { windowsByAppID[$0.appID] } ?? []

        return FlowPageSectionCard(
            title: AppStrings.text(.homeWindowLayerTitle, language: appLanguage),
            subtitle: activeApp.map {
                AppStrings.text(
                    .homeAppWindowsOf,
                    replacements: ["app": $0.displayName],
                    language: appLanguage
                )
            } ?? AppStrings.text(.homeCurrentAppWindows, language: appLanguage),
            trailingText: activeApp.flatMap { windowsByAppID[$0.appID] } == nil
                ? "--"
                : AppStrings.windowCount(activeWindows.count, language: appLanguage),
            trailingAccessibilityIdentifier: "flowtab.home.window.count"
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
            } else if let activeApp, !activeWindows.isEmpty {
                FlowSnappedListScrollView(
                    rowCount: activeWindows.count,
                    rowHeight: HomePageLayout.windowLayerRowHeight,
                    rowSpacing: HomePageLayout.layerListRowSpacing,
                    accessibilityIdentifier: "flowtab.home.window.list"
                ) {
                    ForEach(Array(activeWindows.enumerated()), id: \.element.id) { index, window in
                        HomeWindowRowButton(
                            title: windowTitle(window.title, index: index),
                            subtitle: activeApp.appID,
                            status: windowStatusText(window: window, index: index),
                            icon: HomeAppIconProvider.icon(for: activeApp),
                            isSelected: index == 0,
                            accessibilityIdentifier: "flowtab.home.window.\(window.id.flowTabAccessibilityIdentifierComponent)"
                        ) {
                            activateWindow(activeApp.appID, windowID: window.id)
                        }
                        .frame(height: HomePageLayout.windowLayerRowHeight)
                        .frame(maxWidth: .infinity)
                    }
                }
            } else if activeApp != nil {
                HomeLayerRowView(
                    title: AppStrings.text(.homeNoSwitchableWindows, language: appLanguage),
                    subtitle: activeApp.flatMap(noSwitchableWindowsSubtitle(for:))
                        ?? AppStrings.text(.homeConfirmAccessibility, language: appLanguage),
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
        return presentedAppSummaries.first?.appID
    }

    private func windowTitle(_ title: String, index: Int) -> String {
        let trimmed = title
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if trimmed.isEmpty {
            return "Window #\(index + 1)"
        }
        return trimmed
    }

    private func windowStatusText(window: WindowCandidate, index: Int) -> String {
        if window.isMinimized {
            return AppStrings.text(.homeWindowStatusMinimized, language: appLanguage)
        }
        if index == 0 {
            return AppStrings.text(.homeWindowStatusCurrent, language: appLanguage)
        }
        return AppStrings.text(.homeWindowStatusSwitchable, language: appLanguage)
    }

    private func noSwitchableWindowsSubtitle(for app: RuntimeHomeAppSummary) -> String {
        if
            accessibilityTrusted,
            HomeRuntimeProjectionReader.shouldWaitForNoSwitchableWindowProjection(
                appID: app.appID,
                pid: app.pid,
                from: runtimeProjectionService
            )
        {
            return AppStrings.text(.homeWaitCacheUpdate, language: appLanguage)
        }
        return AppStrings.text(.homeConfirmAccessibility, language: appLanguage)
    }

    private func handleVisibilityChanged(_ active: Bool) {
        guard active else { return }

        refreshHomeAppVisibility()
        restoreCachedStateIfNeeded()
        setupWindowMonitorIfNeeded()
        refreshPermissionsIfNeeded(reason: "appear")
        startPermissionWatcherIfNeeded()

        if appSummaries.isEmpty {
            scheduleInitialAppSummariesRefresh(reason: "initial_load")
            return
        }

        scheduleRuntimeProjectionRefresh(reason: "appear")
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

        windowChangeMonitor.onAppWindowChanged = { appID, pid in
            runtimeProjectionService.signalAppWindowsChanged(appID: appID, pid: pid)
            scheduleSingleAppRefresh(appID: appID, reason: "ax_window_changed")
        }
        windowChangeMonitor.onAXWindowDestroyed = { appID, pid, axWindowID in
            runtimeProjectionService.signalAXWindowDestroyed(appID: appID, pid: pid, axWindowID: axWindowID)
            scheduleSingleAppRefresh(appID: appID, reason: "ax_window_destroyed")
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

    private func refreshHomeAppVisibility() {
        let latestHiddenAppIDs = AppVisibilityPreferencesStore.loadHiddenAppIDs()
        guard latestHiddenAppIDs != hiddenAppIDs else { return }

        hiddenAppIDs = latestHiddenAppIDs
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

    private func scheduleRuntimeProjectionRefresh(reason: String) {
        guard HomeRuntimeProjectionRefreshPolicy.shouldRequestAppSummaryRefresh(
            appSummaryCount: appSummaries.count,
            loadingWindowCountAppCount: loadingWindowCountAppIDs.count
        ) else {
            RuntimeLog.debug(
                .projection,
                "homeSkipRuntimeProjectionRefresh reason=\(reason) phase=initializing apps=\(appSummaries.count) loadingCounts=\(loadingWindowCountAppIDs.count)"
            )
            return
        }
        scheduleAppSummariesRefresh(reason: "runtime_projection_refresh_\(reason)")
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

    private func appAccessibilityValue(
        windowCount: Int,
        isHidden: Bool,
        isWindowCountLoading: Bool
    ) -> String {
        if isWindowCountLoading {
            return isHidden ? "loading hidden" : "loading"
        }
        return isHidden ? "\(windowCount)w hidden" : "\(windowCount)w"
    }

    private func activateWindow(_ appID: String, windowID: String) {
        HomeWindowActivationController.shared.activateWindow(
            appID: appID,
            windowID: windowID,
            detailProjection: homeDetailProjectionsByAppID[appID]
        )
    }

    private func scheduleInitialAppSummariesRefresh(reason: String) {
        appSummariesRefreshTask?.cancel()
        appSummariesRefreshTask = Task { @MainActor in
            RuntimeLog.debug(.projection, "homeInitialProjectionRead begin reason=\(reason)")
            await refreshInitialAppSummaryProjection()
            guard accessibilityTrusted else {
                RuntimeLog.debug(
                    .projection,
                    "homeInitialProjectionRead detailSkipped reason=\(reason) accessibilityTrusted=false"
                )
                appSummariesRefreshTask = nil
                return
            }
            RuntimeLog.debug(
                .projection,
                "homeInitialProjectionRead detailScheduled reason=\(reason) delayMs=900"
            )
            try? await Task.sleep(nanoseconds: initialPreciseAppRefreshDelayNs)
            await refreshAppSummaries(reason: reason)
            appSummariesRefreshTask = nil
        }
    }

    private func scheduleAppSummariesRefresh(reason: String) {
        appSummariesRefreshTask?.cancel()
        appSummariesRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: appRefreshDebounceDelayNs)
            await refreshAppSummaries(reason: reason)
            appSummariesRefreshTask = nil
        }
    }

    private func refreshInitialAppSummaryProjection() async {
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
        let projectionRead = initialHomeAppSummaryProjection()
        let summaries = projectionRead.summaries
        guard !Task.isCancelled, appSummaries.isEmpty else { return }
        guard !summaries.isEmpty else { return }

        homeSummaryProjectionFreshness = projectionRead.freshness
        appSummaries = summaries
        loadingWindowCountAppIDs = accessibilityTrusted ? Set(summaries.map(\.appID)) : []
        syncSelectedApp()
        persistCache()

        if accessibilityTrusted, let selectedAppID = currentSelectedAppID {
            scheduleSelectedAppRefresh(
                appID: selectedAppID,
                force: true,
                reason: "selected_after_initial_projection"
            )
        }
        RuntimeLog.debug(
            .projection,
            "homeInitialProjectionRead result=ready source=\(projectionRead.isProjectionBacked ? "runtimeProjection" : "currentFallback") freshnessComplete=\(projectionRead.freshness?.isCompleteForScope == true ? 1 : 0) apps=\(summaries.count) selected=\(currentSelectedAppID ?? "nil") loadingCounts=\(loadingWindowCountAppIDs.count) accessibilityTrusted=\(accessibilityTrusted) totalMs=\(formatHomeMilliseconds(RuntimePerformanceClock.monotonicMilliseconds() - startMs))"
        )
    }

    private func refreshAppSummaries(reason: String) async {
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
        RuntimeLog.debug(.projection, "homeRefreshAppSummaryProjection begin reason=\(reason)")
        let projectionRead = await readHomeAppSummaryProjection()
        let summaries = projectionRead.summaries
        guard !Task.isCancelled else { return }

        homeSummaryProjectionFreshness = projectionRead.freshness
        appSummaries = summaries
        loadingWindowCountAppIDs.removeAll()
        let validAppIDs = Set(summaries.map(\.appID))
        windowsByAppID = windowsByAppID.filter { validAppIDs.contains($0.key) }
        homeDetailProjectionsByAppID = homeDetailProjectionsByAppID.filter { validAppIDs.contains($0.key) }
        syncSelectedApp()
        setupWindowMonitorIfNeeded()
        persistCache()

        if let selectedAppID = currentSelectedAppID {
            let summaryCount = summaries.first(where: { $0.appID == selectedAppID })?.windowCount
            let cachedCount = windowsByAppID[selectedAppID]?.count
            scheduleSelectedAppRefresh(
                appID: selectedAppID,
                force: summaryCount == nil || cachedCount != summaryCount,
                reason: "selected_after_\(reason)"
            )
        }
        RuntimeLog.debug(
            .projection,
            "homeRefreshAppSummaryProjection result=ready reason=\(reason) source=\(projectionRead.isProjectionBacked ? "runtimeProjection" : "currentFallback") freshnessComplete=\(projectionRead.freshness?.isCompleteForScope == true ? 1 : 0) apps=\(summaries.count) totalMs=\(formatHomeMilliseconds(RuntimePerformanceClock.monotonicMilliseconds() - startMs))"
        )
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
        reason: String
    ) async {
        guard !Task.isCancelled else { return }
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
        RuntimeLog.debug(
            .projection,
            "homeRefreshSingleApp begin appID=\(appID) updateWindows=\(updateWindows) reason=\(reason)"
        )
        if updateWindows {
            let detailProjection = await readHomeAppDetailProjection(appID: appID)
            guard !Task.isCancelled else { return }

            guard let detailProjection else {
                if HomeInitialAppSummaryUpdatePolicy.shouldCommitSingleAppSummary(
                    appID: appID,
                    selectedAppID: currentSelectedAppID,
                    loadingWindowCountAppIDs: loadingWindowCountAppIDs
                ) {
                    loadingWindowCountAppIDs.remove(appID)
                }
                setupWindowMonitorIfCountsReady()
                persistCache()
                RuntimeLog.debug(
                    .projection,
                    "homeRefreshSingleAppProjection result=detailUnavailable appID=\(appID) reason=\(reason) totalMs=\(formatHomeMilliseconds(RuntimePerformanceClock.monotonicMilliseconds() - startMs))"
                )
                return
            }

            let shouldCommitSummary = HomeInitialAppSummaryUpdatePolicy.shouldCommitSingleAppSummary(
                appID: appID,
                selectedAppID: currentSelectedAppID,
                loadingWindowCountAppIDs: loadingWindowCountAppIDs
            )
            if shouldCommitSummary {
                if let existingIndex = appSummaries.firstIndex(where: { $0.appID == appID }) {
                    appSummaries[existingIndex] = detailProjection.summary
                } else {
                    appSummaries.append(detailProjection.summary)
                }
                loadingWindowCountAppIDs.remove(appID)
            }
            windowsByAppID[appID] = detailProjection.candidate.windows
            homeDetailProjectionsByAppID[appID] = detailProjection
        } else {
            let summary = await readHomeAppSummaryProjection(appID: appID)
            guard !Task.isCancelled else { return }
            guard let summary else {
                appSummaries.removeAll { $0.appID == appID }
                windowsByAppID.removeValue(forKey: appID)
                homeDetailProjectionsByAppID.removeValue(forKey: appID)
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

        syncSelectedApp()
        setupWindowMonitorIfCountsReady()
        persistCache()
        RuntimeLog.debug(
            .projection,
            "homeRefreshSingleAppProjection result=ready appID=\(appID) updateWindows=\(updateWindows) reason=\(reason) windows=\(windowsByAppID[appID]?.count ?? -1) totalMs=\(formatHomeMilliseconds(RuntimePerformanceClock.monotonicMilliseconds() - startMs))"
        )
    }

    private func readHomeAppSummaryProjection() async -> HomeAppSummaryProjectionRead {
        HomeRuntimeRefreshReader.appSummaryProjection(
            from: runtimeProjectionService,
            current: appSummaries
        )
    }

    private func setupWindowMonitorIfCountsReady() {
        guard loadingWindowCountAppIDs.isEmpty else { return }
        setupWindowMonitorIfNeeded()
    }

    private func initialHomeAppSummaryProjection() -> HomeAppSummaryProjectionRead {
        HomeInitialAppSummaryReader.appSummaryProjection(from: runtimeProjectionService)
    }

    private func formatHomeMilliseconds(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private func readHomeAppSummaryProjection(appID: String) async -> RuntimeHomeAppSummary? {
        HomeRuntimeRefreshReader.appSummary(
            for: appID,
            from: runtimeProjectionService,
            current: appSummaries
        )
    }

    private func readHomeAppDetailProjection(appID: String) async -> RuntimeHomeAppDetailProjection? {
        HomeRuntimeRefreshReader.appDetailProjection(
            for: appID,
            from: runtimeProjectionService,
            current: homeDetailProjectionsByAppID[appID],
            currentSummary: appSummaries.first { $0.appID == appID }
        )
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

    private func persistCache() {
        Self.cachedAccessibilityTrusted = accessibilityTrusted
        Self.cachedScreenCaptureTrusted = screenCaptureTrusted
        if loadingWindowCountAppIDs.isEmpty {
            Self.cachedAppSummaries = appSummaries
            Self.cachedWindowsByAppID = windowsByAppID
            Self.cachedSelectedAppID = selectedAppID
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

enum HomeInitialAppSummaryUpdatePolicy {
    static func shouldCommitSingleAppSummary(
        appID: String,
        selectedAppID: String?,
        loadingWindowCountAppIDs: Set<String>
    ) -> Bool {
        loadingWindowCountAppIDs.isEmpty || appID == selectedAppID
    }
}
