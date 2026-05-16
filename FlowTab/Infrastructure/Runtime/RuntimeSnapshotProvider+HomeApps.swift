import AppKit
import Foundation
import FlowTabCore

extension RuntimeSnapshotProvider {
    func homeAppSummaries() -> [RuntimeHomeAppSummary] {
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

    func lightweightAppSnapshot() -> RuntimeSnapshot {
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
        if let uiTestRuntimeDataset = Self.uiTestRuntimeDataset() {
            logSnapshotTiming(
                "lightweightAppSnapshot",
                fields: [
                    ("result", "uiTestDataset"),
                    ("apps", "\(uiTestRuntimeDataset.snapshot.apps.count)"),
                    ("windows", "\(uiTestRuntimeDataset.snapshot.apps.reduce(0) { $0 + $1.windows.count })"),
                    ("totalMs", formatSnapshotMilliseconds(RuntimePerformanceClock.monotonicMilliseconds() - startMs))
                ]
            )
            return uiTestRuntimeDataset.snapshot
        }

        let runningAppsStartMs = RuntimePerformanceClock.monotonicMilliseconds()
        let runningApps = filteredRunningApplications()
        let runningAppsReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        guard !runningApps.isEmpty else {
            logSnapshotTiming(
                "lightweightAppSnapshot",
                fields: [
                    ("result", "empty"),
                    ("reason", "noRunningApps"),
                    ("runningAppsMs", formatSnapshotMilliseconds(runningAppsReadyMs - runningAppsStartMs)),
                    ("totalMs", formatSnapshotMilliseconds(runningAppsReadyMs - startMs))
                ]
            )
            return RuntimeSnapshot(apps: [], contextsByID: [:])
        }

        let rankStartMs = RuntimePerformanceClock.monotonicMilliseconds()
        let rankByPID = collectAppRankByPID(for: runningApps)
        let rankReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let selectedApps = selectPrimaryApps(
            from: runningApps,
            windowCountByPID: [:],
            rankByPID: rankByPID
        )
        let appsGroupedByBaseID = groupedAppsByBaseID(runningApps)
        let selectionReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let now = Date.timeIntervalSinceReferenceDate

        var rows: [(candidate: AppSwitchCandidate, context: RuntimeAppContext)] = []
        rows.reserveCapacity(selectedApps.count)
        for (index, app) in selectedApps.enumerated() {
            let appID = Self.baseAppID(for: app)
            let displayName = app.localizedName ?? appID
            let appGroup = appsGroupedByBaseID[appID] ?? [app]
            let rank = preferredRankForAppGroup(
                appGroup,
                rankByPID: rankByPID,
                fallback: 10_000 + index
            )
            let candidate = AppSwitchCandidate(
                id: appID,
                displayName: displayName,
                groupID: Self.groupID(for: app.bundleIdentifier, fallbackName: displayName),
                lastActiveAt: now - Double(rank),
                windows: []
            )
            let context = RuntimeAppContext(
                appID: appID,
                runningApp: app,
                windowsByID: [:]
            )
            rows.append((candidate, context))
        }

        let rowsReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        rows.sort { lhs, rhs in
            if lhs.candidate.lastActiveAt == rhs.candidate.lastActiveAt {
                return lhs.candidate.displayName.localizedCaseInsensitiveCompare(
                    rhs.candidate.displayName
                ) == .orderedAscending
            }
            return lhs.candidate.lastActiveAt > rhs.candidate.lastActiveAt
        }

        var contextsByID: [String: RuntimeAppContext] = [:]
        for row in rows {
            contextsByID[row.context.appID] = row.context
        }
        let completeMs = RuntimePerformanceClock.monotonicMilliseconds()
        logSnapshotTiming(
            "lightweightAppSnapshot",
            fields: [
                ("result", rows.isEmpty ? "empty" : "ready"),
                ("runningApps", "\(runningApps.count)"),
                ("selectedApps", "\(selectedApps.count)"),
                ("apps", "\(rows.count)"),
                ("windows", "deferred"),
                ("runningAppsMs", formatSnapshotMilliseconds(runningAppsReadyMs - runningAppsStartMs)),
                ("rankMs", formatSnapshotMilliseconds(rankReadyMs - rankStartMs)),
                ("selectionMs", formatSnapshotMilliseconds(selectionReadyMs - rankReadyMs)),
                ("rowsMs", formatSnapshotMilliseconds(rowsReadyMs - selectionReadyMs)),
                ("sortContextMs", formatSnapshotMilliseconds(completeMs - rowsReadyMs)),
                ("totalMs", formatSnapshotMilliseconds(completeMs - startMs))
            ]
        )
        return RuntimeSnapshot(
            apps: rows.map(\.candidate),
            contextsByID: contextsByID
        )
    }

    func homeAppSnapshot(for appID: String) -> RuntimeHomeAppSnapshot? {
        if let uiTestRuntimeDataset = Self.uiTestRuntimeDataset() {
            return uiTestRuntimeDataset.snapshotsByAppID[appID]
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

        return makeHomeAppSnapshot(
            appID: appID,
            app: app,
            appGroup: matchingApps,
            windows: windows,
            rankByPID: rankByPID,
            rankFallback: 10_000
        )
    }

    func focusedAppSnapshot(processIdentifier pid: pid_t) -> RuntimeHomeAppSnapshot? {
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
        if let uiTestRuntimeDataset = Self.uiTestRuntimeDataset() {
            let snapshot = uiTestRuntimeDataset.snapshotsByAppID.values.first {
                $0.summary.pid == pid
            }
            logSnapshotTiming(
                "focusedAppSnapshot",
                fields: [
                    ("result", snapshot == nil ? "missingPID" : "uiTestDataset"),
                    ("pid", "\(pid)"),
                    ("windows", "\(snapshot?.candidate.windows.count ?? 0)"),
                    ("totalMs", formatSnapshotMilliseconds(RuntimePerformanceClock.monotonicMilliseconds() - startMs))
                ]
            )
            return snapshot
        }

        let runningAppsStartMs = RuntimePerformanceClock.monotonicMilliseconds()
        let runningApps = filteredRunningApplications()
        let runningAppsReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        guard let app = runningApps.first(where: { $0.processIdentifier == pid })
            ?? NSRunningApplication(processIdentifier: pid)
        else {
            logSnapshotTiming(
                "focusedAppSnapshot",
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
                "focusedAppSnapshot",
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

        let snapshot = makeHomeAppSnapshot(
            appID: appID,
            app: app,
            appGroup: focusedApps,
            windows: windows,
            rankByPID: rankByPID,
            rankFallback: 0
        )
        let completeMs = RuntimePerformanceClock.monotonicMilliseconds()
        logSnapshotTiming(
            "focusedAppSnapshot",
            fields: [
                ("result", snapshot.candidate.windows.isEmpty ? "empty" : "ready"),
                ("appID", appID),
                ("pid", "\(pid)"),
                ("windows", "\(snapshot.candidate.windows.count)"),
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
        return snapshot
    }

    private func makeHomeAppSnapshot(
        appID: String,
        app: NSRunningApplication,
        appGroup: [NSRunningApplication],
        windows: [WindowListEntry],
        rankByPID: [pid_t: Int],
        rankFallback: Int
    ) -> RuntimeHomeAppSnapshot {
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
                        lastConfirmationSource: $0.lastConfirmationSource
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
        return RuntimeHomeAppSnapshot(
            summary: summary,
            candidate: candidate,
            context: context
        )
    }

    func homeAppSummary(for appID: String) -> RuntimeHomeAppSummary? {
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
        guard hideMinimizedAppsFromAppLayer else { return apps }

        return apps.filter { app in
            let windows = windowsByPID[app.processIdentifier] ?? []
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
        guard hideMinimizedAppsFromAppLayer else { return apps }

        return apps.filter { app in
            guard let stats = windowStatsByPID[app.processIdentifier] else { return true }
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

}
