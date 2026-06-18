import AppKit
import Foundation
import FlowTabCore

extension RuntimeSnapshotProvider {
    func homeSummaryProjections() -> [RuntimeHomeAppSummary] {
        if let uiTestRuntimeDataset = Self.uiTestRuntimeDataset() {
            return uiTestRuntimeDataset.summaries
        }
        let runningApps = filteredRunningApplications()
        guard !runningApps.isEmpty else { return [] }

        let windowData = collectWindowData(for: runningApps)
        let appsGroupedByBaseID = groupedAppsByBaseID(runningApps)
        let selectedApps = selectPrimaryApps(
            from: runningApps,
            windowsByPID: windowData.windowsByPID,
            rankByPID: windowData.rankByPID
        )
        let mergedWindowsByPrimaryPID = Dictionary(uniqueKeysWithValues: selectedApps.map { app in
            let appGroup = appsGroupedByBaseID[Self.baseAppID(for: app)] ?? [app]
            return (
                app.processIdentifier,
                mergedWindowEntries(
                    for: appGroup,
                    windowsByPID: windowData.windowsByPID,
                    rankByPID: windowData.rankByPID
                )
            )
        })
        let hideMinimizedAppsFromAppLayer =
            SwitcherBehaviorPreferencesStore.loadHideMinimizedAppsFromAppLayer()
        let appLayerCandidates = filterAppsForAppLayer(
            selectedApps,
            windowsByPID: mergedWindowsByPrimaryPID,
            hideMinimizedAppsFromAppLayer: hideMinimizedAppsFromAppLayer
        )
        guard !appLayerCandidates.isEmpty else { return [] }

        var summaries: [RuntimeHomeAppSummary] = []
        summaries.reserveCapacity(appLayerCandidates.count)
        for (index, app) in appLayerCandidates.enumerated() {
            let pid = app.processIdentifier
            let appID = Self.baseAppID(for: app)
            let appGroup = appsGroupedByBaseID[appID] ?? [app]
            let displayName = app.localizedName ?? appID
            let rank = preferredRankForAppGroup(
                appGroup,
                rankByPID: windowData.rankByPID,
                fallback: 10_000 + index
            )
            summaries.append(
                RuntimeHomeAppSummary(
                    appID: appID,
                    displayName: displayName,
                    groupID: Self.groupID(for: app.bundleIdentifier, fallbackName: displayName),
                    lastActiveAt: Self.stableLastActiveValue(forRank: rank),
                    windowCount: mergedWindowsByPrimaryPID[pid]?.count ?? 0,
                    pid: pid
                )
            )
        }

        summaries.sort { lhs, rhs in
            if lhs.lastActiveAt == rhs.lastActiveAt {
                return lhs.displayName.localizedCaseInsensitiveCompare(
                    rhs.displayName
                ) == .orderedAscending
            }
            return lhs.lastActiveAt > rhs.lastActiveAt
        }
        return summaries
    }

    func appWindowRepairPayload(for appID: String) -> RuntimeAppWindowRepairPayload? {
        if let uiTestRuntimeDataset = Self.uiTestRuntimeDataset() {
            return uiTestRuntimeDataset.repairPayloadsByAppID[appID]
        }
        let runningApps = filteredRunningApplications()
        let matchingApps = runningApps.filter { Self.baseAppID(for: $0) == appID }
        guard !matchingApps.isEmpty else { return nil }

        let rankByPID = collectAppRankByPID(for: runningApps)
        let cgWindowsByPID = collectCGWindowsByPID()
        let allCGWindowsByPID = collectCGWindowsByPID(options: [.optionAll, .excludeDesktopElements])
        let windowsByPID = collectAXWindowData(
            for: matchingApps,
            cgWindowsByPID: cgWindowsByPID,
            allCGWindowsByPID: allCGWindowsByPID
        )
        let sortedApps = sortedAppsWithinGroup(
            matchingApps,
            windowsByPID: windowsByPID,
            rankByPID: rankByPID
        )
        guard let app = sortedApps.first else { return nil }

        let windows = mergedWindowEntries(
            for: sortedApps,
            windowsByPID: windowsByPID,
            rankByPID: rankByPID
        )
        let hideMinimizedAppsFromAppLayer =
            SwitcherBehaviorPreferencesStore.loadHideMinimizedAppsFromAppLayer()
        if hideMinimizedAppsFromAppLayer && !windows.isEmpty && !windows.contains(where: { !$0.isMinimized }) {
            return nil
        }

        return makeAppWindowRepairPayload(
            appID: appID,
            app: app,
            appGroup: matchingApps,
            windows: windows,
            rankByPID: rankByPID,
            rankFallback: 10_000
        )
    }

    func focusedAppWindowRepairPayload(processIdentifier pid: pid_t) -> RuntimeAppWindowRepairPayload? {
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
        if let uiTestRuntimeDataset = Self.uiTestRuntimeDataset() {
            let repairPayload = uiTestRuntimeDataset.repairPayloadsByAppID.values.first {
                $0.summary.pid == pid
            }
            logSnapshotTiming(
                "focusedAppWindowRepairPayload",
                fields: [
                    ("result", repairPayload == nil ? "missingPID" : "uiTestDataset"),
                    ("pid", "\(pid)"),
                    ("windows", "\(repairPayload?.candidate.windows.count ?? 0)"),
                    ("totalMs", formatSnapshotMilliseconds(RuntimePerformanceClock.monotonicMilliseconds() - startMs))
                ]
            )
            return repairPayload
        }

        let runningAppsStartMs = RuntimePerformanceClock.monotonicMilliseconds()
        let runningApps = filteredRunningApplications()
        let runningAppsReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        guard let app = runningApps.first(where: { $0.processIdentifier == pid })
            ?? NSRunningApplication(processIdentifier: pid)
        else {
            logSnapshotTiming(
                "focusedAppWindowRepairPayload",
                fields: [
                    ("result", "missingRunningApp"),
                    ("pid", "\(pid)"),
                    ("knownApps", "\(runningApps.count)"),
                    ("runningAppsMs", formatSnapshotMilliseconds(runningAppsReadyMs - runningAppsStartMs)),
                    ("totalMs", formatSnapshotMilliseconds(runningAppsReadyMs - startMs))
                ]
            )
            return nil
        }

        cleanupWindowMappingState(for: runningApps)
        AXLiveWindowRegistry.shared.prune(to: runningApps)
        let cleanupReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let cgWindowsByPID = collectCGWindowsByPID()
        let onScreenCGReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let allCGWindowsByPID = collectCGWindowsByPID(options: [.optionAll, .excludeDesktopElements])
        let allCGReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let focusedApps = [app]
        let windowsByPID = collectAXWindowData(
            for: focusedApps,
            cgWindowsByPID: cgWindowsByPID,
            allCGWindowsByPID: allCGWindowsByPID
        )
        let axReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let rankByPID = [pid: 0]
        let appID = Self.baseAppID(for: app)
        let windows = mergedWindowEntries(
            for: focusedApps,
            windowsByPID: windowsByPID,
            rankByPID: rankByPID
        )
        let rowsReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let hideMinimizedAppsFromAppLayer =
            SwitcherBehaviorPreferencesStore.loadHideMinimizedAppsFromAppLayer()
        if hideMinimizedAppsFromAppLayer && !windows.isEmpty && !windows.contains(where: { !$0.isMinimized }) {
            let completeMs = RuntimePerformanceClock.monotonicMilliseconds()
            logSnapshotTiming(
                "focusedAppWindowRepairPayload",
                fields: [
                    ("result", "minimizedOnly"),
                    ("appID", appID),
                    ("pid", "\(pid)"),
                    ("windows", "\(windows.count)"),
                    ("knownApps", "\(runningApps.count)"),
                    ("axApps", "\(focusedApps.count)"),
                    ("runningAppsMs", formatSnapshotMilliseconds(runningAppsReadyMs - runningAppsStartMs)),
                    ("cleanupMs", formatSnapshotMilliseconds(cleanupReadyMs - runningAppsReadyMs)),
                    ("onscreenCGMs", formatSnapshotMilliseconds(onScreenCGReadyMs - cleanupReadyMs)),
                    ("allCGMs", formatSnapshotMilliseconds(allCGReadyMs - onScreenCGReadyMs)),
                    ("axMs", formatSnapshotMilliseconds(axReadyMs - allCGReadyMs)),
                    ("rowsMs", formatSnapshotMilliseconds(rowsReadyMs - axReadyMs)),
                    ("totalMs", formatSnapshotMilliseconds(completeMs - startMs))
                ]
            )
            return nil
        }

        let repairPayload = makeAppWindowRepairPayload(
            appID: appID,
            app: app,
            appGroup: focusedApps,
            windows: windows,
            rankByPID: rankByPID,
            rankFallback: 0
        )
        let completeMs = RuntimePerformanceClock.monotonicMilliseconds()
        logSnapshotTiming(
            "focusedAppWindowRepairPayload",
            fields: [
                ("result", repairPayload.candidate.windows.isEmpty ? "empty" : "ready"),
                ("appID", appID),
                ("pid", "\(pid)"),
                ("windows", "\(repairPayload.candidate.windows.count)"),
                ("knownApps", "\(runningApps.count)"),
                ("axApps", "\(focusedApps.count)"),
                ("runningAppsMs", formatSnapshotMilliseconds(runningAppsReadyMs - runningAppsStartMs)),
                ("cleanupMs", formatSnapshotMilliseconds(cleanupReadyMs - runningAppsReadyMs)),
                ("onscreenCGMs", formatSnapshotMilliseconds(onScreenCGReadyMs - cleanupReadyMs)),
                ("allCGMs", formatSnapshotMilliseconds(allCGReadyMs - onScreenCGReadyMs)),
                ("axMs", formatSnapshotMilliseconds(axReadyMs - allCGReadyMs)),
                ("rowsMs", formatSnapshotMilliseconds(rowsReadyMs - axReadyMs)),
                ("totalMs", formatSnapshotMilliseconds(completeMs - startMs))
            ]
        )
        return repairPayload
    }

    private func makeAppWindowRepairPayload(
        appID: String,
        app: NSRunningApplication,
        appGroup: [NSRunningApplication],
        windows: [WindowListEntry],
        rankByPID: [pid_t: Int],
        rankFallback: Int
    ) -> RuntimeAppWindowRepairPayload {
        let now = Date.timeIntervalSinceReferenceDate
        let displayName = app.localizedName ?? appID
        let rank = preferredRankForAppGroup(
            appGroup,
            rankByPID: rankByPID,
            fallback: rankFallback
        )
        let windowCandidates = windows.enumerated().map { entryIndex, entry in
            WindowCandidate(
                id: entry.windowID,
                title: entry.title,
                isMinimized: entry.isMinimized,
                lastActiveAt: now - Double(entryIndex)
            )
        }
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: displayName,
            groupID: Self.groupID(for: app.bundleIdentifier, fallbackName: displayName),
            lastActiveAt: now - Double(rank),
            windows: windowCandidates
        )
        let windowContexts = Dictionary(
            uniqueKeysWithValues: windows.map {
                let id = $0.windowID
                return (
                    id,
                    RuntimeWindowContext(
                        id: id,
                        title: $0.title,
                        isMinimized: $0.isMinimized,
                        ownerPID: $0.ownerPID,
                        cgWindowID: $0.cgWindowID,
                        spaceIDs: $0.spaceIDs,
                        inferredTitleBarStyle: nil,
                        activationHandleID: $0.activationHandleID,
                        axWindow: $0.axWindow,
                        frame: $0.frame,
                        allowsPublicAXRecovery: $0.allowsPublicAXRecovery,
                        hasStickyBinding: $0.hasStickyBinding,
                        lastConfirmationSource: $0.lastConfirmationSource,
                        spaceEvidence: $0.spaceEvidence
                    )
                )
            }
        )
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: app,
            windowsByID: windowContexts
        )
        let summary = RuntimeHomeAppSummary(
            appID: appID,
            displayName: displayName,
            groupID: Self.groupID(for: app.bundleIdentifier, fallbackName: displayName),
            lastActiveAt: Self.stableLastActiveValue(forRank: rank),
            windowCount: windows.count,
            pid: app.processIdentifier
        )
        return RuntimeAppWindowRepairPayload(
            summary: summary,
            candidate: candidate,
            context: context
        )
    }

    func homeSummaryProjection(for appID: String) -> RuntimeHomeAppSummary? {
        if let uiTestRuntimeDataset = Self.uiTestRuntimeDataset() {
            return uiTestRuntimeDataset.summaries.first(where: { $0.appID == appID })
        }
        let runningApps = filteredRunningApplications()
        let matchingApps = runningApps.filter { Self.baseAppID(for: $0) == appID }
        guard !matchingApps.isEmpty else { return nil }

        let rankByPID = collectAppRankByPID(for: runningApps)
        let cgWindowsByPID = collectCGWindowsByPID()
        let allCGWindowsByPID = collectCGWindowsByPID(options: [.optionAll, .excludeDesktopElements])
        let windowsByPID = collectAXWindowData(
            for: matchingApps,
            cgWindowsByPID: cgWindowsByPID,
            allCGWindowsByPID: allCGWindowsByPID
        )
        let mergedWindows = mergedWindowEntries(
            for: matchingApps,
            windowsByPID: windowsByPID,
            rankByPID: rankByPID
        )
        let sortedApps = sortedAppsWithinGroup(
            matchingApps,
            windowsByPID: windowsByPID,
            rankByPID: rankByPID
        )
        guard let app = sortedApps.first else { return nil }

        if
            SwitcherBehaviorPreferencesStore.loadHideMinimizedAppsFromAppLayer(),
            !mergedWindows.isEmpty,
            !mergedWindows.contains(where: { !$0.isMinimized })
        {
            return nil
        }

        let displayName = app.localizedName ?? appID
        let rank = preferredRankForAppGroup(
            matchingApps,
            rankByPID: rankByPID,
            fallback: 10_000
        )
        return RuntimeHomeAppSummary(
            appID: appID,
            displayName: displayName,
            groupID: Self.groupID(for: app.bundleIdentifier, fallbackName: displayName),
            lastActiveAt: Self.stableLastActiveValue(forRank: rank),
            windowCount: mergedWindows.count,
            pid: app.processIdentifier
        )
    }

    func filteredRunningApplications() -> [NSRunningApplication] {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let includeCurrentProcessInAppLayer = AppVisibilityPreferencesStore.loadShowInCommandTab()
        return NSWorkspace.shared.runningApplications.filter {
            Self.shouldIncludeRunningApplication(
                activationPolicy: $0.activationPolicy,
                isTerminated: $0.isTerminated,
                pid: $0.processIdentifier,
                currentPID: currentPID,
                includeCurrentProcessInAppLayer: includeCurrentProcessInAppLayer
            )
        }
    }

    static func shouldIncludeRunningApplication(
        activationPolicy: NSApplication.ActivationPolicy,
        isTerminated: Bool,
        pid: pid_t,
        currentPID: pid_t,
        includeCurrentProcessInAppLayer: Bool
    ) -> Bool {
        activationPolicy == .regular
            && !isTerminated
            && (includeCurrentProcessInAppLayer || pid != currentPID)
    }

    func filterAppsForAppLayer(
        _ apps: [NSRunningApplication],
        windowsByPID: [pid_t: [WindowListEntry]],
        hideMinimizedAppsFromAppLayer: Bool
    ) -> [NSRunningApplication] {
        let candidateAppBundlePaths = Self.appBundlePaths(for: apps)

        return apps.filter { app in
            let windows = windowsByPID[app.processIdentifier] ?? []
            guard !Self.shouldHideZeroWindowNestedApp(
                hasWindows: !windows.isEmpty,
                bundleURL: app.bundleURL,
                candidateAppBundlePaths: candidateAppBundlePaths
            ) else {
                let appName = app.localizedName ?? app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
                RuntimeLog.debug(.snapshot, "skip nested zero-window app=\(appName) pid=\(app.processIdentifier)")
                return false
            }
            let hasVisibleWindow = windows.contains(where: { !$0.isMinimized })
            guard Self.shouldIncludeAppInAppLayer(
                hasWindows: !windows.isEmpty,
                hasVisibleWindow: hasVisibleWindow,
                hideMinimizedAppsFromAppLayer: hideMinimizedAppsFromAppLayer
            ) else {
                let appName = app.localizedName ?? app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
                RuntimeLog.debug(.snapshot, "skip minimized-only app=\(appName) pid=\(app.processIdentifier)")
                return false
            }
            return true
        }
    }

    static func shouldIncludeAppInAppLayer(
        hasWindows: Bool,
        hasVisibleWindow: Bool,
        hideMinimizedAppsFromAppLayer: Bool
    ) -> Bool {
        guard hideMinimizedAppsFromAppLayer else { return true }
        guard hasWindows else { return true }
        return hasVisibleWindow
    }

    func filterAppsForAppLayer(
        _ apps: [NSRunningApplication],
        windowStatsByPID: [pid_t: AXWindowStats],
        hideMinimizedAppsFromAppLayer: Bool
    ) -> [NSRunningApplication] {
        let candidateAppBundlePaths = Self.appBundlePaths(for: apps)

        return apps.filter { app in
            let stats = windowStatsByPID[app.processIdentifier]
                ?? AXWindowStats(windowCount: 0, hasVisibleWindow: false)
            guard !Self.shouldHideZeroWindowNestedApp(
                hasWindows: stats.windowCount > 0,
                bundleURL: app.bundleURL,
                candidateAppBundlePaths: candidateAppBundlePaths
            ) else {
                let appName = app.localizedName ?? app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
                RuntimeLog.debug(.snapshot, "skip nested zero-window app=\(appName) pid=\(app.processIdentifier)")
                return false
            }
            guard Self.shouldIncludeAppInAppLayer(
                hasWindows: stats.windowCount > 0,
                hasVisibleWindow: stats.hasVisibleWindow,
                hideMinimizedAppsFromAppLayer: hideMinimizedAppsFromAppLayer
            ) else {
                let appName = app.localizedName ?? app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
                RuntimeLog.debug(.snapshot, "skip minimized-only app=\(appName) pid=\(app.processIdentifier)")
                return false
            }
            return true
        }
    }

    private static func appBundlePaths(for apps: [NSRunningApplication]) -> Set<String> {
        Set(apps.compactMap { standardizedAppBundlePath(for: $0.bundleURL) })
    }

    static func shouldHideZeroWindowNestedApp(
        hasWindows: Bool,
        bundleURL: URL?,
        candidateAppBundlePaths: Set<String>
    ) -> Bool {
        guard !hasWindows else { return false }
        guard
            let bundlePath = standardizedAppBundlePath(for: bundleURL),
            candidateAppBundlePaths.count > 1
        else {
            return false
        }

        return appBundleAncestorPaths(for: bundlePath).contains { candidateAppBundlePaths.contains($0) }
    }

    static func standardizedAppBundlePath(for bundleURL: URL?) -> String? {
        guard let bundleURL else { return nil }
        let standardizedURL = bundleURL.standardizedFileURL
        guard standardizedURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
            return nil
        }
        return standardizedURL.path
    }

    private static func appBundleAncestorPaths(for bundlePath: String) -> [String] {
        var ancestorPaths: [String] = []
        var currentURL = URL(fileURLWithPath: bundlePath).deletingLastPathComponent()

        while currentURL.path != "/" {
            let standardizedURL = currentURL.standardizedFileURL
            if standardizedURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                ancestorPaths.append(standardizedURL.path)
            }

            let parentURL = currentURL.deletingLastPathComponent()
            guard parentURL.path != currentURL.path else { break }
            currentURL = parentURL
        }

        return ancestorPaths
    }

}
