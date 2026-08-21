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
        permissionObservationOwner: HomePermissionObservationOwner? = nil,
        initialProjectionObservationOwner: HomeInitialProjectionObservationOwner? = nil,
        appSummaryProjectionObservationOwner: HomeAppSummaryProjectionObservationOwner? = nil,
        appDetailProjectionObservationOwner: HomeAppDetailProjectionObservationOwner? = nil,
        openSettings: @escaping () -> Void
    ) {
        self.isActive = isActive
        self.appLanguage = appLanguage
        self.runtimeProjectionService = runtimeProjectionService
        _permissionObservationOwner = StateObject(
            wrappedValue: permissionObservationOwner
                ?? HomePermissionObservationOwner(
                    accessibilityTrusted: Self.cachedAccessibilityTrusted,
                    screenCaptureTrusted: Self.cachedScreenCaptureTrusted
                )
        )
        _initialProjectionObservationOwner = StateObject(
            wrappedValue: initialProjectionObservationOwner
                ?? HomeInitialProjectionObservationOwner(
                    runtimeProjectionService: runtimeProjectionService
                )
        )
        _appSummaryProjectionObservationOwner = StateObject(
            wrappedValue: appSummaryProjectionObservationOwner
                ?? HomeAppSummaryProjectionObservationOwner(
                    runtimeProjectionService: runtimeProjectionService
                )
        )
        _appDetailProjectionObservationOwner = StateObject(
            wrappedValue: appDetailProjectionObservationOwner
                ?? HomeAppDetailProjectionObservationOwner(
                    runtimeProjectionService: runtimeProjectionService
                )
        )
        self.openSettings = openSettings
    }

    @AppStorage(AppPreferenceKeys.showPermissionReminder)
    private var showPermissionReminder = true
    @AppStorage(AppPreferenceKeys.hotkeyPrimaryModifier)
    private var hotkeyPrimaryModifierRaw = SwitcherHotkeyPreferencesStore.defaultBaseKeys.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyReverseModifiers)
    private var hotkeyReverseModifiersRaw =
        SwitcherHotkeyPreferencesStore.defaultReverseKeys.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyMainKey)
    private var hotkeyMainKeyRaw = SwitcherHotkeyPreferencesStore.defaultMainKeys.rawValue
    @AppStorage(AppPreferenceKeys.hotkeyQuitKey)
    private var hotkeyQuitKeyRaw = SwitcherHotkeyPreferencesStore.defaultQuitKeys.rawValue
    @StateObject private var permissionObservationOwner:
        HomePermissionObservationOwner
    @StateObject private var initialProjectionObservationOwner: HomeInitialProjectionObservationOwner
    @StateObject private var appSummaryProjectionObservationOwner: HomeAppSummaryProjectionObservationOwner
    @StateObject private var appDetailProjectionObservationOwner: HomeAppDetailProjectionObservationOwner
    @State private var appSummaries: [RuntimeHomeAppSummary] = []
    @State private var hiddenAppIDs = AppVisibilityPreferencesStore.loadHiddenAppIDs()
    @State private var windowsByAppID: [String: [WindowCandidate]] = [:]
    @State private var homeDetailProjectionsByAppID: [String: RuntimeHomeAppDetailProjection] = [:]
    @State private var homeSummaryProjectionFreshness: RuntimeProjectionFreshness?
    @State private var loadingWindowCountAppIDs: Set<String> = []
    @State private var selectedDetailRefreshExpectations:
        [String: HomeSelectedAppRefreshExpectation] = [:]
    @State private var selectedAppID: String?
    @State private var windowChangeMonitor = RuntimeAXWindowChangeMonitor()

    private var accessibilityTrusted: Bool {
        permissionObservationOwner.accessibilityTrusted
    }

    private var screenCaptureTrusted: Bool {
        permissionObservationOwner.screenCaptureTrusted
    }

    private var hotkeyConfiguration: SwitcherHotkeyConfiguration {
        SwitcherHotkeyPreferencesStore.resolve(
            baseKeysRaw: hotkeyPrimaryModifierRaw,
            reverseKeysRaw: hotkeyReverseModifiersRaw,
            mainKeysRaw: hotkeyMainKeyRaw,
            quitKeysRaw: hotkeyQuitKeyRaw
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
            handleVisibilityChanged(active)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            guard isActive else { return }
            requestAppSummaryProjectionMaintenance(reason: "app_active")
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
        guard active else {
            initialProjectionObservationOwner.stop(reason: "homeInactive")
            appSummaryProjectionObservationOwner.stop(reason: "homeInactive")
            appDetailProjectionObservationOwner.stopAll(reason: "homeInactive")
            permissionObservationOwner.stop()
            windowChangeMonitor.stop()
            return
        }

        refreshHomeAppVisibility()
        restoreCachedStateIfNeeded()

        if appSummaries.isEmpty || homeSummaryProjectionFreshness?.isCompleteForScope != true {
            scheduleInitialAppSummariesRefresh(reason: "initial_load")
        } else {
            startAppSummaryProjectionObservation(reason: "appear")
        }

        startPermissionObservationIfNeeded()
        setupWindowMonitorIfNeeded()
        if let selectedAppID = currentSelectedAppID {
            requestSelectedAppRefresh(
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

        windowChangeMonitor.onAppWindowChanged = { evidence in
            guard evidence.requiresReconciliation else { return }
            requestAppDetailProjection(
                .appWindowsChanged(
                    appID: evidence.appID,
                    pid: evidence.pid
                ),
                reason: "ax_window_changed"
            )
        }
        windowChangeMonitor.onAXWindowDestroyed = { appID, pid, axWindowID in
            requestAppDetailProjection(
                .axWindowDestroyed(
                    appID: appID,
                    pid: pid,
                    axWindowID: axWindowID
                ),
                reason: "ax_window_destroyed"
            )
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
        syncSelectedApp()
    }

    private func refreshHomeAppVisibility() {
        let latestHiddenAppIDs = AppVisibilityPreferencesStore.loadHiddenAppIDs()
        guard latestHiddenAppIDs != hiddenAppIDs else { return }

        hiddenAppIDs = latestHiddenAppIDs
        syncSelectedApp()
    }

    private func startPermissionObservationIfNeeded() {
        permissionObservationOwner.start { evidence in
            requestAppSummaryProjectionMaintenance(
                reason: "permission_changed_\(evidence.source.rawValue)"
            )
            if evidence.target == .accessibility,
               !evidence.isGranted
            {
                windowChangeMonitor.stop()
            }
            persistCache()
        }
    }

    private func persistPermissionCache() {
        Self.cachedAccessibilityTrusted = accessibilityTrusted
        Self.cachedScreenCaptureTrusted = screenCaptureTrusted
    }

    private func persistCache() {
        persistPermissionCache()
        if loadingWindowCountAppIDs.isEmpty {
            Self.cachedAppSummaries = appSummaries
            Self.cachedWindowsByAppID = windowsByAppID
            Self.cachedSelectedAppID = selectedAppID
        }
    }

    private func selectApp(_ appID: String) {
        selectedAppID = appID
        persistCache()
        requestSelectedAppRefresh(
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
        appSummaryProjectionObservationOwner.stop(reason: "initialProjectionRequired")
        RuntimeLog.debug(.projection, "homeInitialProjectionObservation state=starting reason=\(reason)")
        initialProjectionObservationOwner.start(reason: reason) { evidence in
            applyInitialProjectionEvidence(evidence, reason: reason)
        }
    }

    private func requestAppSummaryProjectionMaintenance(reason: String) {
        if initialProjectionObservationOwner.isObserving {
            scheduleInitialAppSummariesRefresh(reason: reason)
            return
        }
        guard appSummaryProjectionObservationOwner.isObserving else {
            let initialEvidence = startAppSummaryProjectionObservation(reason: reason)
            if initialEvidence.projectionRead.isProjectionBacked {
                appSummaryProjectionObservationOwner.requestMaintenance(reason: reason)
            }
            return
        }
        appSummaryProjectionObservationOwner.requestMaintenance(reason: reason)
    }

    @discardableResult
    private func startAppSummaryProjectionObservation(reason: String)
        -> HomeAppSummaryProjectionObservationEvidence {
        RuntimeLog.debug(
            .projection,
            "homeAppSummaryProjectionObservation state=starting reason=\(reason)"
        )
        return appSummaryProjectionObservationOwner.start(reason: reason) { evidence in
            applyAppSummaryProjectionEvidence(evidence, reason: reason)
        }
    }

    private func applyInitialProjectionEvidence(
        _ evidence: HomeInitialProjectionObservationEvidence,
        reason: String
    ) {
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
        let projectionRead = evidence.projectionRead
        guard evidence.shouldApply else {
            RuntimeLog.debug(
                .projection,
                "homeInitialProjectionRead result=\(evidence.transition.rawValue) source=\(evidence.source.rawValue) reason=\(reason) readbacks=\(evidence.readbackCount)"
            )
            return
        }
        guard projectionRead.isProjectionBacked else {
            RuntimeLog.debug(
                .projection,
                "homeInitialProjectionRead result=projectionMissing source=\(evidence.source.rawValue) reason=\(reason)"
            )
            return
        }

        let summaries = projectionRead.summaries
        homeSummaryProjectionFreshness = projectionRead.freshness
        appSummaries = summaries
        loadingWindowCountAppIDs = accessibilityTrusted && !evidence.isReadyForPresentation
            ? Set(summaries.map(\.appID))
            : []
        let validAppIDs = Set(summaries.map(\.appID))
        windowsByAppID = windowsByAppID.filter { validAppIDs.contains($0.key) }
        homeDetailProjectionsByAppID = homeDetailProjectionsByAppID.filter {
            validAppIDs.contains($0.key)
        }
        selectedDetailRefreshExpectations = selectedDetailRefreshExpectations.filter {
            validAppIDs.contains($0.key)
        }
        appDetailProjectionObservationOwner.retainObservations(
            for: validAppIDs
        )
        syncSelectedApp()
        setupWindowMonitorIfCountsReady()
        persistCache()

        if evidence.isReadyForPresentation {
            startAppSummaryProjectionObservation(
                reason: "initial_projection_\(evidence.source.rawValue)"
            )
        }
        if !evidence.isReady,
           accessibilityTrusted,
           let selectedAppID = currentSelectedAppID {
            requestSelectedAppRefresh(
                appID: selectedAppID,
                force: true,
                reason: "selected_after_initial_projection"
            )
        }
        RuntimeLog.debug(
            .projection,
            "homeInitialProjectionRead result=\(evidence.isReadyForPresentation ? "ready" : "observing") source=\(evidence.source.rawValue) transition=\(evidence.transition.rawValue) freshnessComplete=\(projectionRead.freshness?.isCompleteForScope == true ? 1 : 0) apps=\(summaries.count) selected=\(currentSelectedAppID ?? "nil") loadingCounts=\(loadingWindowCountAppIDs.count) accessibilityTrusted=\(accessibilityTrusted) totalMs=\(formatHomeMilliseconds(RuntimePerformanceClock.monotonicMilliseconds() - startMs))"
        )
    }

    private func applyAppSummaryProjectionEvidence(
        _ evidence: HomeAppSummaryProjectionObservationEvidence,
        reason: String
    ) {
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
        let projectionRead = evidence.projectionRead
        guard evidence.shouldApply else {
            RuntimeLog.debug(
                .projection,
                "homeAppSummaryProjectionRead result=\(evidence.transition.rawValue) source=\(evidence.source.rawValue) reason=\(reason) readbacks=\(evidence.readbackCount)"
            )
            return
        }
        guard projectionRead.isProjectionBacked else {
            RuntimeLog.debug(
                .projection,
                "homeAppSummaryProjectionRead result=projectionMissing source=\(evidence.source.rawValue) reason=\(reason)"
            )
            return
        }

        let summaries = projectionRead.summaries
        homeSummaryProjectionFreshness = projectionRead.freshness
        appSummaries = summaries
        loadingWindowCountAppIDs.removeAll()
        let validAppIDs = Set(summaries.map(\.appID))
        windowsByAppID = windowsByAppID.filter { validAppIDs.contains($0.key) }
        homeDetailProjectionsByAppID = homeDetailProjectionsByAppID.filter { validAppIDs.contains($0.key) }
        selectedDetailRefreshExpectations = selectedDetailRefreshExpectations.filter {
            validAppIDs.contains($0.key)
        }
        appDetailProjectionObservationOwner.retainObservations(
            for: validAppIDs
        )
        syncSelectedApp()
        setupWindowMonitorIfNeeded()
        persistCache()

        if let selectedAppID = currentSelectedAppID,
           let summary = summaries.first(where: { $0.appID == selectedAppID })
        {
            let cachedCount = windowsByAppID[selectedAppID]?.count
            switch HomeSelectedAppSummaryRefreshPolicy.decision(
                summaryProcessIdentifier: summary.pid,
                summaryWindowCount: summary.windowCount,
                cachedWindowCount: cachedCount,
                outstandingExpectation:
                    selectedDetailRefreshExpectations[selectedAppID]
            )
            {
            case .noRequest:
                break
            case .clearOutstanding:
                selectedDetailRefreshExpectations.removeValue(
                    forKey: selectedAppID
                )
            case .request(let expectation):
                selectedDetailRefreshExpectations[selectedAppID] = expectation
                requestSelectedAppRefresh(
                    appID: selectedAppID,
                    force: true,
                    reason: "selected_after_\(reason)"
                )
            }
        }
        RuntimeLog.debug(
            .projection,
            "homeAppSummaryProjectionRead result=applied reason=\(reason) source=\(evidence.source.rawValue) transition=\(evidence.transition.rawValue) freshnessComplete=\(projectionRead.freshness?.isCompleteForScope == true ? 1 : 0) apps=\(summaries.count) totalMs=\(formatHomeMilliseconds(RuntimePerformanceClock.monotonicMilliseconds() - startMs))"
        )
    }

    private func requestSelectedAppRefresh(
        appID: String,
        force: Bool,
        reason: String
    ) {
        guard force || windowsByAppID[appID] == nil else { return }
        guard let pid = appSummaries.first(where: { $0.appID == appID })?.pid,
              pid > 0
        else {
            RuntimeLog.debug(
                .projection,
                "homeAppDetailProjectionObservation state=requestUnavailable appID=\(appID) reason=\(reason) unmet=missingPositivePID"
            )
            return
        }
        requestAppDetailProjection(
            .selected(appID: appID, pid: pid),
            updateWindows: true,
            reason: reason
        )
    }

    private func requestAppDetailProjection(
        _ request: HomeAppDetailProjectionRequest,
        updateWindows: Bool? = nil,
        reason: String
    ) {
        guard request.pid > 0 else {
            RuntimeLog.debug(
                .projection,
                "homeAppDetailProjectionObservation state=requestUnavailable appID=\(request.appID) reason=\(reason) unmet=missingPositivePID"
            )
            return
        }
        let appID = request.appID
        if let summary = appSummaries.first(where: { $0.appID == appID }) {
            selectedDetailRefreshExpectations[appID] =
                HomeSelectedAppRefreshExpectation(
                    processIdentifier: summary.pid,
                    windowCount: summary.windowCount
                )
        }
        let shouldUpdateWindows = updateWindows
            ?? (appID == currentSelectedAppID
                || windowsByAppID[appID] != nil)
        appDetailProjectionObservationOwner.request(
            request,
            reason: reason
        ) { evidence in
            applyAppDetailProjectionEvidence(
                evidence,
                updateWindows: shouldUpdateWindows,
                reason: reason
            )
        }
    }

    private func applyAppDetailProjectionEvidence(
        _ evidence: HomeAppDetailProjectionObservationEvidence,
        updateWindows: Bool,
        reason: String
    ) {
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
        guard evidence.shouldApply, let detailProjection = evidence.projection else {
            RuntimeLog.debug(
                .projection,
                "homeAppDetailProjectionRead result=\(evidence.transition.rawValue) appID=\(evidence.appID) source=\(evidence.source.rawValue) reason=\(reason) readbacks=\(evidence.readbackCount)"
            )
            return
        }
        let appID = evidence.appID
        RuntimeLog.debug(
            .projection,
            "homeAppDetailProjectionRead result=observed appID=\(appID) updateWindows=\(updateWindows) source=\(evidence.source.rawValue) transition=\(evidence.transition.rawValue) complete=\(evidence.isComplete ? 1 : 0) reason=\(reason)"
        )

        let shouldCommitSummary =
            HomeInitialAppSummaryUpdatePolicy.shouldCommitSingleAppSummary(
                appID: appID,
                selectedAppID: currentSelectedAppID,
                loadingWindowCountAppIDs: loadingWindowCountAppIDs
            )
        if shouldCommitSummary {
            if let existingIndex = appSummaries.firstIndex(where: {
                $0.appID == appID
            }) {
                appSummaries[existingIndex] = detailProjection.summary
            } else {
                appSummaries.append(detailProjection.summary)
            }
            if evidence.isComplete {
                loadingWindowCountAppIDs.remove(appID)
            }
        }
        if updateWindows {
            windowsByAppID[appID] = detailProjection.candidate.windows
            homeDetailProjectionsByAppID[appID] = detailProjection
            if let expectation = selectedDetailRefreshExpectations[appID],
               expectation.processIdentifier == detailProjection.summary.pid,
               expectation.windowCount == detailProjection.candidate.windows.count
            {
                selectedDetailRefreshExpectations.removeValue(forKey: appID)
            }
        }

        syncSelectedApp()
        setupWindowMonitorIfCountsReady()
        persistCache()
        RuntimeLog.debug(
            .projection,
            "homeAppDetailProjectionRead result=applied appID=\(appID) updateWindows=\(updateWindows) complete=\(evidence.isComplete ? 1 : 0) reason=\(reason) windows=\(windowsByAppID[appID]?.count ?? -1) totalMs=\(formatHomeMilliseconds(RuntimePerformanceClock.monotonicMilliseconds() - startMs))"
        )
    }

    private func setupWindowMonitorIfCountsReady() {
        guard loadingWindowCountAppIDs.isEmpty else { return }
        setupWindowMonitorIfNeeded()
    }

    private func formatHomeMilliseconds(_ value: Double) -> String {
        String(format: "%.3f", value)
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

    private func teardownActiveState() {
        initialProjectionObservationOwner.stop(reason: "homeDisappeared")
        appSummaryProjectionObservationOwner.stop(reason: "homeDisappeared")
        appDetailProjectionObservationOwner.stopAll(
            reason: "homeDisappeared"
        )
        selectedDetailRefreshExpectations.removeAll()
        permissionObservationOwner.stop()
        windowChangeMonitor.stop()
        persistCache()
    }
}
