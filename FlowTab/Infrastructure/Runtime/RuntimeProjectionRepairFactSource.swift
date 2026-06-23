import AppKit
import CoreGraphics
import Foundation

struct RuntimeRepairRunningApps {
    let runningApps: [NSRunningApplication]
}

struct RuntimeFullRepairRunningAppFacts {
    let runningApps: [NSRunningApplication]
    let appDirectoryEntries: [RuntimeAppDirectoryEntry]
}

struct RuntimeFullRepairWindowFacts {
    let windowsByPID: [pid_t: [RuntimeWindowListEntry]]
    let rankByPID: [pid_t: Int]
}

struct RuntimeFullRepairAppSelectionFacts {
    let appsGroupedByAppID: [String: [NSRunningApplication]]
    let selectedApps: [NSRunningApplication]
    let mergedWindowsByPrimaryPID: [pid_t: [RuntimeWindowListEntry]]
    let appLayerCandidates: [NSRunningApplication]
}

struct RuntimeCurrentAppWindowFacts {
    let windowsByPID: [pid_t: [RuntimeWindowListEntry]]
    let rankByPID: [pid_t: Int]
}

struct RuntimeFocusedCurrentAppWindowFactTimings {
    let cleanupMs: Double
    let onScreenCGMs: Double
    let allCGMs: Double
    let axMs: Double
}

struct RuntimeFocusedCurrentAppWindowFacts {
    let windowsByPID: [pid_t: [RuntimeWindowListEntry]]
    let rankByPID: [pid_t: Int]
    let timings: RuntimeFocusedCurrentAppWindowFactTimings
}

struct RuntimeAppWindowSelectionFacts {
    let app: NSRunningApplication
    let appGroup: [NSRunningApplication]
    let windows: [RuntimeWindowListEntry]
    let isIncludedInAppLayer: Bool
}

struct RuntimeRepairAppLayerPolicyFacts {
    let hideMinimizedAppsFromAppLayer: Bool
}

struct RuntimeSpaceTopologySignalFacts {
    let affectedCGWindowIDs: Set<CGWindowID>
    let signatureSummary: String?
}

struct RuntimeSpaceTopologyReconciliationTarget: Equatable {
    let pid: pid_t
    let affectedCGWindowIDs: Set<CGWindowID>
}

struct RuntimeUITestProjectionDatasetFacts {
    let fullRepairProjectionPayload: RuntimeFullRepairProjectionPayload
    let currentAppWindowPayloadsByAppID: [String: RuntimeCurrentAppWindowPayload]

    var appCount: Int {
        fullRepairProjectionPayload.apps.count
    }

    var windowCount: Int {
        fullRepairProjectionPayload.apps.reduce(0) { $0 + $1.windows.count }
    }

    func currentAppWindowPayload(for appID: String) -> RuntimeCurrentAppWindowPayload? {
        currentAppWindowPayloadsByAppID[appID]
    }

    func focusedCurrentAppWindowPayload(processIdentifier pid: pid_t) -> RuntimeCurrentAppWindowPayload? {
        currentAppWindowPayloadsByAppID.values.first {
            $0.summary.pid == pid
        }
    }
}

struct RuntimeProjectionRepairFactSource {
    let runtimeFactProvider: RuntimeSnapshotProvider

    func collectUITestProjectionDatasetFacts() -> RuntimeUITestProjectionDatasetFacts? {
        guard let dataset = FlowTabUITestRuntimeProjectionDataset.current() else { return nil }
        return RuntimeUITestProjectionDatasetFacts(
            fullRepairProjectionPayload: RuntimeFullRepairProjectionPayload(
                apps: dataset.appSwitcherApps,
                contextsByID: dataset.appSwitcherContextsByID,
                appDirectoryEntries: dataset.appDirectoryEntries
            ),
            currentAppWindowPayloadsByAppID: dataset.currentAppWindowPayloadsByAppID
        )
    }

    func collectRepairRunningApps() -> RuntimeRepairRunningApps {
        let runningApps = RuntimeAppDirectoryFactSource.currentAppLayerRunningApplications(
            includeCurrentProcessInAppLayer: AppVisibilityPreferencesStore.loadShowInCommandTab()
        )
        return RuntimeRepairRunningApps(runningApps: runningApps)
    }

    func collectFullRepairRunningAppFacts() -> RuntimeFullRepairRunningAppFacts {
        let runningApps = collectRepairRunningApps().runningApps
        return RuntimeFullRepairRunningAppFacts(
            runningApps: runningApps,
            appDirectoryEntries: RuntimeAppDirectoryFactSource.entries(from: runningApps)
        )
    }

    func collectRepairAppLayerPolicyFacts() -> RuntimeRepairAppLayerPolicyFacts {
        RuntimeRepairAppLayerPolicyFacts(
            hideMinimizedAppsFromAppLayer: SwitcherBehaviorPreferencesStore.loadHideMinimizedAppsFromAppLayer()
        )
    }

    func collectSpaceTopologySignalFacts(now: TimeInterval) -> RuntimeSpaceTopologySignalFacts {
        let collection = runtimeFactProvider.collectCGWindowsWithSpaceTopologyDiff(
            options: [.excludeDesktopElements],
            now: now
        )
        return RuntimeSpaceTopologySignalFacts(
            affectedCGWindowIDs: collection.spaceTopologyDiff?.affectedCGWindowIDs ?? [],
            signatureSummary: collection.spaceTopologyDiff?.currentSignature.diagnosticSummary
        )
    }

    func collectSpaceTopologyReconciliationTargets(
        affectedCGWindowIDs: Set<CGWindowID>
    ) -> [RuntimeSpaceTopologyReconciliationTarget] {
        let cgWindowsByPID = runtimeFactProvider.collectCGWindowsWithSpaceTopologyDiff(
            options: [.excludeDesktopElements]
        ).windowsByPID
        let affectedCGWindowIDsByPID = RuntimeWindowMappingState.affectedCGWindowIDsByPID(
            affectedCGWindowIDs: affectedCGWindowIDs,
            currentCGWindowsByPID: cgWindowsByPID,
            mappingStatesByPID: runtimeFactProvider.windowRecordStore.mappingStatesByPID
        )
        guard !affectedCGWindowIDsByPID.isEmpty else { return [] }

        return affectedCGWindowIDsByPID.keys.sorted().map { pid in
            RuntimeSpaceTopologyReconciliationTarget(
                pid: pid,
                affectedCGWindowIDs: affectedCGWindowIDsByPID[pid] ?? []
            )
        }
    }

    func collectFullRepairWindowFacts(for runningApps: [NSRunningApplication]) -> RuntimeFullRepairWindowFacts {
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
        runtimeFactProvider.cleanupWindowMappingState(for: runningApps)
        let cleanupReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        AXLiveWindowRegistry.shared.prune(to: runningApps)
        let pruneReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let onScreenCGWindowsByPID = runtimeFactProvider.collectCGWindowsWithSpaceTopologyDiff().windowsByPID
        let onScreenCGReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let allCGWindowsByPID = runtimeFactProvider.collectCGWindowsWithSpaceTopologyDiff(
            options: [.optionAll, .excludeDesktopElements]
        ).windowsByPID
        let allCGReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let axWindowsByPID = runtimeFactProvider.collectAXWindowData(
            for: runningApps,
            cgWindowsByPID: onScreenCGWindowsByPID,
            allCGWindowsByPID: allCGWindowsByPID
        )
        let axReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let rankByPID = RuntimeAppRankProvider.collectAppRankByPID(for: runningApps)
        let completeMs = RuntimePerformanceClock.monotonicMilliseconds()
        RuntimeProjectionDiagnostics.logTiming(
            "collectWindowData",
            fields: [
                ("apps", "\(runningApps.count)"),
                ("onscreenCGWindows", "\(onScreenCGWindowsByPID.values.reduce(0) { $0 + $1.count })"),
                ("allCGWindows", "\(allCGWindowsByPID.values.reduce(0) { $0 + $1.count })"),
                ("windowPIDs", "\(axWindowsByPID.count)"),
                ("rankPIDs", "\(rankByPID.count)"),
                ("cleanupMs", RuntimeProjectionDiagnostics.formatMilliseconds(cleanupReadyMs - startMs)),
                ("registryPruneMs", RuntimeProjectionDiagnostics.formatMilliseconds(pruneReadyMs - cleanupReadyMs)),
                ("onscreenCGMs", RuntimeProjectionDiagnostics.formatMilliseconds(onScreenCGReadyMs - pruneReadyMs)),
                ("allCGMs", RuntimeProjectionDiagnostics.formatMilliseconds(allCGReadyMs - onScreenCGReadyMs)),
                ("axMs", RuntimeProjectionDiagnostics.formatMilliseconds(axReadyMs - allCGReadyMs)),
                ("rankMs", RuntimeProjectionDiagnostics.formatMilliseconds(completeMs - axReadyMs)),
                ("totalMs", RuntimeProjectionDiagnostics.formatMilliseconds(completeMs - startMs))
            ]
        )
        // Keep a single source of truth for window counting and selection: AX window list.
        return RuntimeFullRepairWindowFacts(
            windowsByPID: axWindowsByPID,
            rankByPID: rankByPID
        )
    }

    func collectFullRepairAppSelectionFacts(
        for runningApps: [NSRunningApplication],
        windowFacts: RuntimeFullRepairWindowFacts,
        policyFacts: RuntimeRepairAppLayerPolicyFacts
    ) -> RuntimeFullRepairAppSelectionFacts {
        let appDirectory = RuntimeAppDirectory(apps: runningApps)
        let appsGroupedByAppID = appDirectory.groupedAppsByAppID()
        let windowStatsByPID = RuntimeAppDirectory.windowStats(
            for: runningApps,
            windowsByPID: windowFacts.windowsByPID,
            isVisibleWindow: { !$0.isMinimized }
        )
        let selectedApps = appDirectory.selectPrimaryApps(
            windowStatsByPID: windowStatsByPID,
            rankByPID: windowFacts.rankByPID
        )
        let mergedWindowsByPrimaryPID = Dictionary(uniqueKeysWithValues: selectedApps.map { app in
            let appGroup = appsGroupedByAppID[RuntimeAppIdentity.appID(for: app)] ?? [app]
            return (
                app.processIdentifier,
                appDirectory.mergedWindows(
                    for: appGroup,
                    windowsByPID: windowFacts.windowsByPID,
                    windowStatsByPID: windowStatsByPID,
                    rankByPID: windowFacts.rankByPID
                )
            )
        })
        let appLayerWindowStatsByPID = RuntimeAppDirectory.windowStats(
            for: selectedApps,
            windowsByPID: mergedWindowsByPrimaryPID,
            isVisibleWindow: { !$0.isMinimized }
        )
        let appLayerCandidates = RuntimeAppDirectory(apps: selectedApps).filterAppLayerCandidates(
            windowStatsByPID: appLayerWindowStatsByPID,
            hideMinimizedAppsFromAppLayer: policyFacts.hideMinimizedAppsFromAppLayer
        )
        return RuntimeFullRepairAppSelectionFacts(
            appsGroupedByAppID: appsGroupedByAppID,
            selectedApps: selectedApps,
            mergedWindowsByPrimaryPID: mergedWindowsByPrimaryPID,
            appLayerCandidates: appLayerCandidates
        )
    }

    func collectCurrentAppWindowFacts(
        for matchingApps: [NSRunningApplication],
        in runningApps: [NSRunningApplication]
    ) -> RuntimeCurrentAppWindowFacts {
        let rankByPID = RuntimeAppRankProvider.collectAppRankByPID(for: runningApps)
        let cgWindowsByPID = runtimeFactProvider.collectCGWindowsWithSpaceTopologyDiff().windowsByPID
        let allCGWindowsByPID = runtimeFactProvider.collectCGWindowsWithSpaceTopologyDiff(
            options: [.optionAll, .excludeDesktopElements]
        ).windowsByPID
        let windowsByPID = runtimeFactProvider.collectAXWindowData(
            for: matchingApps,
            cgWindowsByPID: cgWindowsByPID,
            allCGWindowsByPID: allCGWindowsByPID
        )
        return RuntimeCurrentAppWindowFacts(
            windowsByPID: windowsByPID,
            rankByPID: rankByPID
        )
    }

    func collectCurrentAppSelectionFacts(
        for matchingApps: [NSRunningApplication],
        windowFacts: RuntimeCurrentAppWindowFacts,
        policyFacts: RuntimeRepairAppLayerPolicyFacts
    ) -> RuntimeAppWindowSelectionFacts? {
        let appDirectory = RuntimeAppDirectory(apps: matchingApps)
        let windowStatsByPID = RuntimeAppDirectory.windowStats(
            for: matchingApps,
            windowsByPID: windowFacts.windowsByPID,
            isVisibleWindow: { !$0.isMinimized }
        )
        let sortedApps = appDirectory.sortedAppsWithinGroup(
            matchingApps,
            windowStatsByPID: windowStatsByPID,
            rankByPID: windowFacts.rankByPID
        )
        guard let app = sortedApps.first else { return nil }

        let windows = appDirectory.mergedWindows(
            for: sortedApps,
            windowsByPID: windowFacts.windowsByPID,
            windowStatsByPID: windowStatsByPID,
            rankByPID: windowFacts.rankByPID
        )
        return RuntimeAppWindowSelectionFacts(
            app: app,
            appGroup: matchingApps,
            windows: windows,
            isIncludedInAppLayer: RuntimeAppLayerProjectionFilter.shouldIncludeAppInAppLayer(
                hasWindows: !windows.isEmpty,
                hasVisibleWindow: windows.contains { !$0.isMinimized },
                hideMinimizedAppsFromAppLayer: policyFacts.hideMinimizedAppsFromAppLayer
            )
        )
    }

    func collectFocusedCurrentAppWindowFacts(
        for app: NSRunningApplication,
        in runningApps: [NSRunningApplication],
        processIdentifier pid: pid_t
    ) -> RuntimeFocusedCurrentAppWindowFacts {
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
        runtimeFactProvider.cleanupWindowMappingState(for: runningApps)
        AXLiveWindowRegistry.shared.prune(to: runningApps)
        let cleanupReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let cgWindowsByPID = runtimeFactProvider.collectCGWindowsWithSpaceTopologyDiff().windowsByPID
        let onScreenCGReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let allCGWindowsByPID = runtimeFactProvider.collectCGWindowsWithSpaceTopologyDiff(
            options: [.optionAll, .excludeDesktopElements]
        ).windowsByPID
        let allCGReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let windowsByPID = runtimeFactProvider.collectAXWindowData(
            for: [app],
            cgWindowsByPID: cgWindowsByPID,
            allCGWindowsByPID: allCGWindowsByPID
        )
        let axReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        return RuntimeFocusedCurrentAppWindowFacts(
            windowsByPID: windowsByPID,
            rankByPID: [pid: 0],
            timings: RuntimeFocusedCurrentAppWindowFactTimings(
                cleanupMs: cleanupReadyMs - startMs,
                onScreenCGMs: onScreenCGReadyMs - cleanupReadyMs,
                allCGMs: allCGReadyMs - onScreenCGReadyMs,
                axMs: axReadyMs - allCGReadyMs
            )
        )
    }

    func collectFocusedCurrentAppSelectionFacts(
        for app: NSRunningApplication,
        windowFacts: RuntimeFocusedCurrentAppWindowFacts,
        policyFacts: RuntimeRepairAppLayerPolicyFacts
    ) -> RuntimeAppWindowSelectionFacts {
        let focusedApps = [app]
        let windowStatsByPID = RuntimeAppDirectory.windowStats(
            for: focusedApps,
            windowsByPID: windowFacts.windowsByPID,
            isVisibleWindow: { !$0.isMinimized }
        )
        let windows = RuntimeAppDirectory(apps: focusedApps).mergedWindows(
            for: focusedApps,
            windowsByPID: windowFacts.windowsByPID,
            windowStatsByPID: windowStatsByPID,
            rankByPID: windowFacts.rankByPID
        )
        return RuntimeAppWindowSelectionFacts(
            app: app,
            appGroup: focusedApps,
            windows: windows,
            isIncludedInAppLayer: RuntimeAppLayerProjectionFilter.shouldIncludeAppInAppLayer(
                hasWindows: !windows.isEmpty,
                hasVisibleWindow: windows.contains { !$0.isMinimized },
                hideMinimizedAppsFromAppLayer: policyFacts.hideMinimizedAppsFromAppLayer
            )
        )
    }
}
