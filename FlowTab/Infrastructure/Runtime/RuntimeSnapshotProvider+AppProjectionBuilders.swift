import AppKit
import Foundation
import FlowTabCore

extension RuntimeSnapshotProvider {
    func fullRepairProjectionPayload() -> RuntimeFullRepairProjectionPayload {
        fullRepairProjectionPayload(timingEvent: "fullRepairProjectionPayload")
    }

    private func collectWindowData(for runningApps: [NSRunningApplication]) -> (
        windowsByPID: [pid_t: [WindowListEntry]],
        rankByPID: [pid_t: Int]
    ) {
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
        cleanupWindowMappingState(for: runningApps)
        let cleanupReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        AXLiveWindowRegistry.shared.prune(to: runningApps)
        let pruneReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let onScreenCGWindowsByPID = collectCGWindowsWithSpaceTopologyDiff().windowsByPID
        let onScreenCGReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let allCGWindowsByPID = collectCGWindowsWithSpaceTopologyDiff(
            options: [.optionAll, .excludeDesktopElements]
        ).windowsByPID
        let allCGReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let axWindowsByPID = collectAXWindowData(
            for: runningApps,
            cgWindowsByPID: onScreenCGWindowsByPID,
            allCGWindowsByPID: allCGWindowsByPID
        )
        let axReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let rankByPID = collectAppRankByPID(for: runningApps)
        let completeMs = RuntimePerformanceClock.monotonicMilliseconds()
        logProjectionTiming(
            "collectWindowData",
            fields: [
                ("apps", "\(runningApps.count)"),
                ("onscreenCGWindows", "\(onScreenCGWindowsByPID.values.reduce(0) { $0 + $1.count })"),
                ("allCGWindows", "\(allCGWindowsByPID.values.reduce(0) { $0 + $1.count })"),
                ("windowPIDs", "\(axWindowsByPID.count)"),
                ("rankPIDs", "\(rankByPID.count)"),
                ("cleanupMs", formatProjectionMilliseconds(cleanupReadyMs - startMs)),
                ("registryPruneMs", formatProjectionMilliseconds(pruneReadyMs - cleanupReadyMs)),
                ("onscreenCGMs", formatProjectionMilliseconds(onScreenCGReadyMs - pruneReadyMs)),
                ("allCGMs", formatProjectionMilliseconds(allCGReadyMs - onScreenCGReadyMs)),
                ("axMs", formatProjectionMilliseconds(axReadyMs - allCGReadyMs)),
                ("rankMs", formatProjectionMilliseconds(completeMs - axReadyMs)),
                ("totalMs", formatProjectionMilliseconds(completeMs - startMs))
            ]
        )
        // Keep a single source of truth for window counting and selection: AX window list.
        return (
            windowsByPID: axWindowsByPID,
            rankByPID: rankByPID
        )
    }

    private func fullRepairProjectionPayload(timingEvent: String) -> RuntimeFullRepairProjectionPayload {
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
        if let uiTestRuntimeDataset = Self.uiTestRuntimeDataset() {
            let completeMs = RuntimePerformanceClock.monotonicMilliseconds()
            logProjectionTiming(
                timingEvent,
                fields: [
                    ("result", "uiTestDataset"),
                    ("apps", "\(uiTestRuntimeDataset.appSwitcherApps.count)"),
                    ("windows", "\(uiTestRuntimeDataset.appSwitcherApps.reduce(0) { $0 + $1.windows.count })"),
                    ("totalMs", formatProjectionMilliseconds(completeMs - startMs))
                ]
            )
            return RuntimeFullRepairProjectionPayload(
                apps: uiTestRuntimeDataset.appSwitcherApps,
                contextsByID: uiTestRuntimeDataset.appSwitcherContextsByID
            )
        }
        let runningAppsStartMs = RuntimePerformanceClock.monotonicMilliseconds()
        let runningApps = filteredRunningApplications()
        let runningAppsReadyMs = RuntimePerformanceClock.monotonicMilliseconds()

        guard !runningApps.isEmpty else {
            logProjectionTiming(
                timingEvent,
                fields: [
                    ("result", "empty"),
                    ("reason", "noRunningApps"),
                    ("runningAppsMs", formatProjectionMilliseconds(runningAppsReadyMs - runningAppsStartMs)),
                    ("totalMs", formatProjectionMilliseconds(runningAppsReadyMs - startMs))
                ]
            )
            return RuntimeFullRepairProjectionPayload(apps: [], contextsByID: [:])
        }

        RuntimeLog.debug(.projection, "runningApps=\(runningApps.count)")
        let windowDataStartMs = RuntimePerformanceClock.monotonicMilliseconds()
        let windowData = collectWindowData(for: runningApps)
        let windowDataReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let selectionStartMs = windowDataReadyMs
        let appsGroupedByBaseID = groupedAppsByBaseID(runningApps)
        let selectedApps = selectPrimaryApps(
            from: runningApps,
            windowsByPID: windowData.windowsByPID,
            rankByPID: windowData.rankByPID
        )
        let mergedWindowsByPrimaryPID = Dictionary(uniqueKeysWithValues: selectedApps.map { app in
            let appGroup = appsGroupedByBaseID[RuntimeAppIdentity.appID(for: app)] ?? [app]
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
        let selectionReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        RuntimeLog.debug(
            .snapshot,
            "selectedApps=\(selectedApps.count) appLayerCandidates=\(appLayerCandidates.count) hideMinimized=\(hideMinimizedAppsFromAppLayer)"
        )

        guard !appLayerCandidates.isEmpty else {
            let completeMs = RuntimePerformanceClock.monotonicMilliseconds()
            logProjectionTiming(
                timingEvent,
                fields: [
                    ("result", "empty"),
                    ("reason", "noAppLayerCandidates"),
                    ("runningApps", "\(runningApps.count)"),
                    ("selectedApps", "\(selectedApps.count)"),
                    ("windows", "\(windowData.windowsByPID.values.reduce(0) { $0 + $1.count })"),
                    ("runningAppsMs", formatProjectionMilliseconds(runningAppsReadyMs - runningAppsStartMs)),
                    ("windowDataMs", formatProjectionMilliseconds(windowDataReadyMs - windowDataStartMs)),
                    ("selectionMs", formatProjectionMilliseconds(selectionReadyMs - selectionStartMs)),
                    ("totalMs", formatProjectionMilliseconds(completeMs - startMs))
                ]
            )
            return RuntimeFullRepairProjectionPayload(apps: [], contextsByID: [:])
        }
        let now = Date.timeIntervalSinceReferenceDate

        var currentAppPayloads: [RuntimeCurrentAppWindowPayload] = []
        currentAppPayloads.reserveCapacity(appLayerCandidates.count)

        let rowsStartMs = RuntimePerformanceClock.monotonicMilliseconds()
        for (index, app) in appLayerCandidates.enumerated() {
            let pid = app.processIdentifier
            let baseAppID = RuntimeAppIdentity.appID(for: app)
            let appGroup = appsGroupedByBaseID[baseAppID] ?? [app]
            let appID = baseAppID
            let displayName = app.localizedName ?? baseAppID

            let windows = mergedWindowsByPrimaryPID[pid] ?? []
            RuntimeLog.debug(
                .snapshot,
                "\(displayName) pid=\(pid) appID=\(appID) windows=\(windows.count)"
            )

            let rank = preferredRankForAppGroup(
                appGroup,
                rankByPID: windowData.rankByPID,
                fallback: 10_000 + index
            )
            let payload = RuntimeCurrentAppWindowPayload(
                appID: appID,
                displayName: displayName,
                groupID: Self.groupID(for: app.bundleIdentifier, fallbackName: displayName),
                summaryLastActiveAt: Self.stableLastActiveValue(forRank: rank),
                candidateLastActiveAt: now - Double(rank),
                pid: pid,
                runningApp: app,
                windowSeeds: windows.enumerated().map { entryIndex, entry in
                    entry.projectionSeed(lastActiveAt: now - Double(entryIndex))
                }
            )
            currentAppPayloads.append(payload)
        }
        let rowsReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let payload = RuntimeFullRepairProjectionAssembler.payload(
            fromCurrentAppWindowPayloads: currentAppPayloads,
            duplicateContextHandler: { appID in
                RuntimeLog.debug(.projection, "duplicate appID fallback overwrite=\(appID)")
            }
        )
        let completeMs = RuntimePerformanceClock.monotonicMilliseconds()

        logProjectionTiming(
            timingEvent,
            fields: [
                ("result", "ready"),
                ("runningApps", "\(runningApps.count)"),
                ("selectedApps", "\(selectedApps.count)"),
                ("appLayerCandidates", "\(appLayerCandidates.count)"),
                ("windows", "\(payload.apps.reduce(0) { $0 + $1.windows.count })"),
                ("contexts", "\(payload.contextsByID.count)"),
                ("runningAppsMs", formatProjectionMilliseconds(runningAppsReadyMs - runningAppsStartMs)),
                ("windowDataMs", formatProjectionMilliseconds(windowDataReadyMs - windowDataStartMs)),
                ("selectionMs", formatProjectionMilliseconds(selectionReadyMs - selectionStartMs)),
                ("rowsMs", formatProjectionMilliseconds(rowsReadyMs - rowsStartMs)),
                ("sortContextMs", formatProjectionMilliseconds(completeMs - rowsReadyMs)),
                ("totalMs", formatProjectionMilliseconds(completeMs - startMs))
            ]
        )

        return payload
    }

    func currentAppWindowPayload(for appID: String) -> RuntimeCurrentAppWindowPayload? {
        if let uiTestRuntimeDataset = Self.uiTestRuntimeDataset() {
            return uiTestRuntimeDataset.currentAppWindowPayloadsByAppID[appID]
        }
        let runningApps = filteredRunningApplications()
        let matchingApps = runningApps.filter { RuntimeAppIdentity.appID(for: $0) == appID }
        guard !matchingApps.isEmpty else { return nil }

        let rankByPID = collectAppRankByPID(for: runningApps)
        let cgWindowsByPID = collectCGWindowsWithSpaceTopologyDiff().windowsByPID
        let allCGWindowsByPID = collectCGWindowsWithSpaceTopologyDiff(
            options: [.optionAll, .excludeDesktopElements]
        ).windowsByPID
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

        return makeCurrentAppWindowPayload(
            appID: appID,
            app: app,
            appGroup: matchingApps,
            windows: windows,
            rankByPID: rankByPID,
            rankFallback: 10_000
        )
    }

    func focusedCurrentAppWindowPayload(processIdentifier pid: pid_t) -> RuntimeCurrentAppWindowPayload? {
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
        if let uiTestRuntimeDataset = Self.uiTestRuntimeDataset() {
            let payload = uiTestRuntimeDataset.currentAppWindowPayloadsByAppID.values.first {
                $0.summary.pid == pid
            }
            logProjectionTiming(
                "focusedCurrentAppWindowPayload",
                fields: [
                    ("result", payload == nil ? "missingPID" : "uiTestDataset"),
                    ("pid", "\(pid)"),
                    ("windows", "\(payload?.candidate.windows.count ?? 0)"),
                    ("totalMs", formatProjectionMilliseconds(RuntimePerformanceClock.monotonicMilliseconds() - startMs))
                ]
            )
            return payload
        }

        let runningAppsStartMs = RuntimePerformanceClock.monotonicMilliseconds()
        let runningApps = filteredRunningApplications()
        let runningAppsReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        guard let app = runningApps.first(where: { $0.processIdentifier == pid })
            ?? NSRunningApplication(processIdentifier: pid)
        else {
            logProjectionTiming(
                "focusedCurrentAppWindowPayload",
                fields: [
                    ("result", "missingRunningApp"),
                    ("pid", "\(pid)"),
                    ("knownApps", "\(runningApps.count)"),
                    ("runningAppsMs", formatProjectionMilliseconds(runningAppsReadyMs - runningAppsStartMs)),
                    ("totalMs", formatProjectionMilliseconds(runningAppsReadyMs - startMs))
                ]
            )
            return nil
        }

        cleanupWindowMappingState(for: runningApps)
        AXLiveWindowRegistry.shared.prune(to: runningApps)
        let cleanupReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let cgWindowsByPID = collectCGWindowsWithSpaceTopologyDiff().windowsByPID
        let onScreenCGReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let allCGWindowsByPID = collectCGWindowsWithSpaceTopologyDiff(
            options: [.optionAll, .excludeDesktopElements]
        ).windowsByPID
        let allCGReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let focusedApps = [app]
        let windowsByPID = collectAXWindowData(
            for: focusedApps,
            cgWindowsByPID: cgWindowsByPID,
            allCGWindowsByPID: allCGWindowsByPID
        )
        let axReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let rankByPID = [pid: 0]
        let appID = RuntimeAppIdentity.appID(for: app)
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
            logProjectionTiming(
                "focusedCurrentAppWindowPayload",
                fields: [
                    ("result", "minimizedOnly"),
                    ("appID", appID),
                    ("pid", "\(pid)"),
                    ("windows", "\(windows.count)"),
                    ("knownApps", "\(runningApps.count)"),
                    ("axApps", "\(focusedApps.count)"),
                    ("runningAppsMs", formatProjectionMilliseconds(runningAppsReadyMs - runningAppsStartMs)),
                    ("cleanupMs", formatProjectionMilliseconds(cleanupReadyMs - runningAppsReadyMs)),
                    ("onscreenCGMs", formatProjectionMilliseconds(onScreenCGReadyMs - cleanupReadyMs)),
                    ("allCGMs", formatProjectionMilliseconds(allCGReadyMs - onScreenCGReadyMs)),
                    ("axMs", formatProjectionMilliseconds(axReadyMs - allCGReadyMs)),
                    ("rowsMs", formatProjectionMilliseconds(rowsReadyMs - axReadyMs)),
                    ("totalMs", formatProjectionMilliseconds(completeMs - startMs))
                ]
            )
            return nil
        }

        let payload = makeCurrentAppWindowPayload(
            appID: appID,
            app: app,
            appGroup: focusedApps,
            windows: windows,
            rankByPID: rankByPID,
            rankFallback: 0
        )
        let completeMs = RuntimePerformanceClock.monotonicMilliseconds()
        logProjectionTiming(
            "focusedCurrentAppWindowPayload",
            fields: [
                ("result", payload.candidate.windows.isEmpty ? "empty" : "ready"),
                ("appID", appID),
                ("pid", "\(pid)"),
                ("windows", "\(payload.candidate.windows.count)"),
                ("knownApps", "\(runningApps.count)"),
                ("axApps", "\(focusedApps.count)"),
                ("runningAppsMs", formatProjectionMilliseconds(runningAppsReadyMs - runningAppsStartMs)),
                ("cleanupMs", formatProjectionMilliseconds(cleanupReadyMs - runningAppsReadyMs)),
                ("onscreenCGMs", formatProjectionMilliseconds(onScreenCGReadyMs - cleanupReadyMs)),
                ("allCGMs", formatProjectionMilliseconds(allCGReadyMs - onScreenCGReadyMs)),
                ("axMs", formatProjectionMilliseconds(axReadyMs - allCGReadyMs)),
                ("rowsMs", formatProjectionMilliseconds(rowsReadyMs - axReadyMs)),
                ("totalMs", formatProjectionMilliseconds(completeMs - startMs))
            ]
        )
        return payload
    }

    private func makeCurrentAppWindowPayload(
        appID: String,
        app: NSRunningApplication,
        appGroup: [NSRunningApplication],
        windows: [WindowListEntry],
        rankByPID: [pid_t: Int],
        rankFallback: Int
    ) -> RuntimeCurrentAppWindowPayload {
        let now = Date.timeIntervalSinceReferenceDate
        let displayName = app.localizedName ?? appID
        let rank = preferredRankForAppGroup(
            appGroup,
            rankByPID: rankByPID,
            fallback: rankFallback
        )
        let groupID = Self.groupID(for: app.bundleIdentifier, fallbackName: displayName)
        return RuntimeCurrentAppWindowPayload(
            appID: appID,
            displayName: displayName,
            groupID: groupID,
            summaryLastActiveAt: Self.stableLastActiveValue(forRank: rank),
            candidateLastActiveAt: now - Double(rank),
            pid: app.processIdentifier,
            runningApp: app,
            windowSeeds: windows.enumerated().map { entryIndex, entry in
                entry.projectionSeed(lastActiveAt: now - Double(entryIndex))
            }
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
                RuntimeLog.debug(.projection, "skip nested zero-window app=\(appName) pid=\(app.processIdentifier)")
                return false
            }
            let hasVisibleWindow = windows.contains(where: { !$0.isMinimized })
            guard Self.shouldIncludeAppInAppLayer(
                hasWindows: !windows.isEmpty,
                hasVisibleWindow: hasVisibleWindow,
                hideMinimizedAppsFromAppLayer: hideMinimizedAppsFromAppLayer
            ) else {
                let appName = app.localizedName ?? app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
                RuntimeLog.debug(.projection, "skip minimized-only app=\(appName) pid=\(app.processIdentifier)")
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
        RuntimeAppLayerProjectionFilter.shouldIncludeAppInAppLayer(
            hasWindows: hasWindows,
            hasVisibleWindow: hasVisibleWindow,
            hideMinimizedAppsFromAppLayer: hideMinimizedAppsFromAppLayer
        )
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
                RuntimeLog.debug(.projection, "skip nested zero-window app=\(appName) pid=\(app.processIdentifier)")
                return false
            }
            guard Self.shouldIncludeAppInAppLayer(
                hasWindows: stats.windowCount > 0,
                hasVisibleWindow: stats.hasVisibleWindow,
                hideMinimizedAppsFromAppLayer: hideMinimizedAppsFromAppLayer
            ) else {
                let appName = app.localizedName ?? app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
                RuntimeLog.debug(.projection, "skip minimized-only app=\(appName) pid=\(app.processIdentifier)")
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
