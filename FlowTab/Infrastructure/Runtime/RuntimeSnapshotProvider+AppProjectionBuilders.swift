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
        let appDirectory = RuntimeAppDirectory(apps: runningApps)
        let appsGroupedByBaseID = appDirectory.groupedAppsByAppID()
        let windowStatsByPID = RuntimeAppDirectory.windowStats(
            for: runningApps,
            windowsByPID: windowData.windowsByPID,
            isVisibleWindow: { !$0.isMinimized }
        )
        let selectedApps = appDirectory.selectPrimaryApps(
            windowStatsByPID: windowStatsByPID,
            rankByPID: windowData.rankByPID
        )
        let mergedWindowsByPrimaryPID = Dictionary(uniqueKeysWithValues: selectedApps.map { app in
            let appGroup = appsGroupedByBaseID[RuntimeAppIdentity.appID(for: app)] ?? [app]
            return (
                app.processIdentifier,
                appDirectory.mergedWindows(
                    for: appGroup,
                    windowsByPID: windowData.windowsByPID,
                    windowStatsByPID: windowStatsByPID,
                    rankByPID: windowData.rankByPID
                )
            )
        })
        let hideMinimizedAppsFromAppLayer =
            SwitcherBehaviorPreferencesStore.loadHideMinimizedAppsFromAppLayer()
        let appLayerWindowStatsByPID = RuntimeAppDirectory.windowStats(
            for: selectedApps,
            windowsByPID: mergedWindowsByPrimaryPID,
            isVisibleWindow: { !$0.isMinimized }
        )
        let appLayerCandidates = RuntimeAppDirectory(apps: selectedApps).filterAppLayerCandidates(
            windowStatsByPID: appLayerWindowStatsByPID,
            hideMinimizedAppsFromAppLayer: hideMinimizedAppsFromAppLayer
        )
        let selectionReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        RuntimeLog.debug(
            .projection,
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

        var currentAppProjectionInputs: [RuntimeCurrentAppWindowProjectionAssemblyInput] = []
        currentAppProjectionInputs.reserveCapacity(appLayerCandidates.count)

        let rowsStartMs = RuntimePerformanceClock.monotonicMilliseconds()
        for (index, app) in appLayerCandidates.enumerated() {
            let pid = app.processIdentifier
            let baseAppID = RuntimeAppIdentity.appID(for: app)
            let appGroup = appsGroupedByBaseID[baseAppID] ?? [app]
            let appID = baseAppID
            let displayName = app.localizedName ?? baseAppID

            let windows = mergedWindowsByPrimaryPID[pid] ?? []
            RuntimeLog.debug(
                .projection,
                "\(displayName) pid=\(pid) appID=\(appID) windows=\(windows.count)"
            )

            let input = RuntimeCurrentAppWindowProjectionAssemblyInput(
                appID: appID,
                app: app,
                appGroup: appGroup,
                rankByPID: windowData.rankByPID,
                rankFallback: 10_000 + index,
                generatedAt: now,
                windowSeeds: windows.enumerated().map { entryIndex, entry in
                    entry.projectionSeed(lastActiveAt: now - Double(entryIndex))
                }
            )
            currentAppProjectionInputs.append(input)
        }
        let rowsReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let payload = RuntimeFullRepairProjectionAssembler.payload(
            fromCurrentAppWindowProjectionInputs: currentAppProjectionInputs,
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
        let appDirectory = RuntimeAppDirectory(apps: matchingApps)
        let windowStatsByPID = RuntimeAppDirectory.windowStats(
            for: matchingApps,
            windowsByPID: windowsByPID,
            isVisibleWindow: { !$0.isMinimized }
        )
        let sortedApps = appDirectory.sortedAppsWithinGroup(
            matchingApps,
            windowStatsByPID: windowStatsByPID,
            rankByPID: rankByPID
        )
        guard let app = sortedApps.first else { return nil }

        let windows = appDirectory.mergedWindows(
            for: sortedApps,
            windowsByPID: windowsByPID,
            windowStatsByPID: windowStatsByPID,
            rankByPID: rankByPID
        )
        let hideMinimizedAppsFromAppLayer =
            SwitcherBehaviorPreferencesStore.loadHideMinimizedAppsFromAppLayer()
        if !RuntimeAppLayerProjectionFilter.shouldIncludeAppInAppLayer(
            hasWindows: !windows.isEmpty,
            hasVisibleWindow: windows.contains { !$0.isMinimized },
            hideMinimizedAppsFromAppLayer: hideMinimizedAppsFromAppLayer
        ) {
            return nil
        }

        let now = Date.timeIntervalSinceReferenceDate
        return RuntimeCurrentAppWindowPayload(
            assemblyInput: RuntimeCurrentAppWindowProjectionAssemblyInput(
                appID: appID,
                app: app,
                appGroup: matchingApps,
                rankByPID: rankByPID,
                rankFallback: 10_000,
                generatedAt: now,
                windowSeeds: windows.enumerated().map { entryIndex, entry in
                    entry.projectionSeed(lastActiveAt: now - Double(entryIndex))
                }
            )
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
        let windowStatsByPID = RuntimeAppDirectory.windowStats(
            for: focusedApps,
            windowsByPID: windowsByPID,
            isVisibleWindow: { !$0.isMinimized }
        )
        let windows = RuntimeAppDirectory(apps: focusedApps).mergedWindows(
            for: focusedApps,
            windowsByPID: windowsByPID,
            windowStatsByPID: windowStatsByPID,
            rankByPID: rankByPID
        )
        let rowsReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let hideMinimizedAppsFromAppLayer =
            SwitcherBehaviorPreferencesStore.loadHideMinimizedAppsFromAppLayer()
        if !RuntimeAppLayerProjectionFilter.shouldIncludeAppInAppLayer(
            hasWindows: !windows.isEmpty,
            hasVisibleWindow: windows.contains { !$0.isMinimized },
            hideMinimizedAppsFromAppLayer: hideMinimizedAppsFromAppLayer
        ) {
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

        let now = Date.timeIntervalSinceReferenceDate
        let payload = RuntimeCurrentAppWindowPayload(
            assemblyInput: RuntimeCurrentAppWindowProjectionAssemblyInput(
                appID: appID,
                app: app,
                appGroup: focusedApps,
                rankByPID: rankByPID,
                rankFallback: 0,
                generatedAt: now,
                windowSeeds: windows.enumerated().map { entryIndex, entry in
                    entry.projectionSeed(lastActiveAt: now - Double(entryIndex))
                }
            )
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

    func filteredRunningApplications() -> [NSRunningApplication] {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let includeCurrentProcessInAppLayer = AppVisibilityPreferencesStore.loadShowInCommandTab()
        return NSWorkspace.shared.runningApplications.filter {
            RuntimeAppLayerProjectionFilter.shouldIncludeRunningApplication(
                activationPolicy: $0.activationPolicy,
                isTerminated: $0.isTerminated,
                pid: $0.processIdentifier,
                currentPID: currentPID,
                includeCurrentProcessInAppLayer: includeCurrentProcessInAppLayer
            )
        }
    }

}
