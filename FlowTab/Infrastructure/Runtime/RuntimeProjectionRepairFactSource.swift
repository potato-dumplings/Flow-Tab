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
    let refreshEvidence: RuntimeFullRepairWindowRecordRefreshEvidence
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
    let signature: RuntimeSpaceTopologySignature?
    let signatureSummary: String?
}

struct RuntimeSpaceTopologyReconciliationTarget: Equatable {
    let pid: pid_t
    let affectedCGWindowIDs: Set<CGWindowID>
}

#if FLOWTAB_TESTING
struct RuntimeUITestProjectionDatasetFacts {
    let appDirectoryEntries: [RuntimeAppDirectoryEntry]
    let appCount: Int
    let windowCount: Int
    let windowRecordRefresh: RuntimeFullRepairWindowRecordRefreshEvidence
    private let focusedRepairEvidenceByPID: [pid_t: RuntimeCurrentAppRepairEvidence]

    init(
        appDirectoryEntries: [RuntimeAppDirectoryEntry],
        appCount: Int,
        windowCount: Int,
        windowRecordRefresh: RuntimeFullRepairWindowRecordRefreshEvidence,
        focusedRepairEvidenceByPID: [pid_t: RuntimeCurrentAppRepairEvidence]
    ) {
        self.appDirectoryEntries = appDirectoryEntries
        self.appCount = appCount
        self.windowCount = windowCount
        self.windowRecordRefresh = windowRecordRefresh
        self.focusedRepairEvidenceByPID = focusedRepairEvidenceByPID
    }

    func focusedCurrentAppRepairEvidence(processIdentifier pid: pid_t) -> RuntimeCurrentAppRepairEvidence? {
        focusedRepairEvidenceByPID[pid]
    }
}
#endif

extension RuntimeAppWindowSelectionFacts {
    func currentAppProjectionAssemblyInput(
        appID: String? = nil,
        rankByPID: [pid_t: Int],
        rankFallback: Int,
        generatedAt: TimeInterval
    ) -> RuntimeCurrentAppWindowProjectionAssemblyInput {
        RuntimeCurrentAppWindowProjectionAssemblyInput(
            appID: appID ?? RuntimeAppIdentity.appID(for: app),
            app: app,
            appGroup: appGroup,
            rankByPID: rankByPID,
            rankFallback: rankFallback,
            generatedAt: generatedAt,
            windowSeeds: windows.enumerated().map { entryIndex, entry in
                entry.projectionSeed(lastActiveAt: generatedAt - Double(entryIndex))
            }
        )
    }
}

extension RuntimeFullRepairAppSelectionFacts {
    func currentAppProjectionAssemblyInputs(
        rankByPID: [pid_t: Int],
        generatedAt: TimeInterval
    ) -> [RuntimeCurrentAppWindowProjectionAssemblyInput] {
        appLayerCandidates.enumerated().map { index, app in
            let appID = RuntimeAppIdentity.appID(for: app)
            return RuntimeAppWindowSelectionFacts(
                app: app,
                appGroup: appsGroupedByAppID[appID] ?? [app],
                windows: mergedWindowsByPrimaryPID[app.processIdentifier] ?? [],
                isIncludedInAppLayer: true
            ).currentAppProjectionAssemblyInput(
                appID: appID,
                rankByPID: rankByPID,
                rankFallback: 10_000 + index,
                generatedAt: generatedAt
            )
        }
    }
}

struct RuntimeProjectionRepairFactSource {
    private let runtimeFactProvider: any RuntimeProjectionRepairFactProviding
    private let windowRecordStore: RuntimeWindowRecordStore

    init(
        runtimeFactProvider: any RuntimeProjectionRepairFactProviding,
        windowRecordStore: RuntimeWindowRecordStore
    ) {
        self.runtimeFactProvider = runtimeFactProvider
        self.windowRecordStore = windowRecordStore
    }

#if FLOWTAB_TESTING
    func collectUITestProjectionDatasetFacts() -> RuntimeUITestProjectionDatasetFacts? {
        guard let dataset = FlowTabUITestRuntimeProjectionDataset.current() else { return nil }
        let windowRecordRefresh = dataset.seedWindowRecordCoverage(in: windowRecordStore)
        let focusedRepairEvidenceByPID = Dictionary(
            dataset.currentAppWindowPayloadsByAppID.values.map { payload in
                (
                    payload.summary.pid,
                    RuntimeCurrentAppRepairEvidence(
                        appID: payload.summary.appID,
                        pid: payload.summary.pid,
                        appDirectoryEntries: payload.appDirectoryEntries,
                        currentAppWindowPayloadWasEmpty: payload.candidate.windows.isEmpty,
                        authoritativeCGWindowIDs: Set(
                            payload.context.windowsByID.values.compactMap(\.cgWindowID)
                        )
                    )
                )
            },
            uniquingKeysWith: { existing, _ in existing }
        )
        return RuntimeUITestProjectionDatasetFacts(
            appDirectoryEntries: dataset.appDirectoryEntries,
            appCount: dataset.appSwitcherApps.count,
            windowCount: dataset.appSwitcherApps.reduce(0) { $0 + $1.windows.count },
            windowRecordRefresh: windowRecordRefresh,
            focusedRepairEvidenceByPID: focusedRepairEvidenceByPID
        )
    }
#endif

    func collectRepairRunningApps() -> RuntimeRepairRunningApps {
        let runningApps = RuntimeAppDirectoryFactSource.currentAppLayerRunningApplications(
            includeCurrentProcessInAppLayer: AppVisibilityPreferencesStore.loadShowInCommandTab()
        )
        return RuntimeRepairRunningApps(runningApps: runningApps)
    }

    func collectFullRepairRunningAppFacts() -> RuntimeFullRepairRunningAppFacts {
        let runningApps = collectRepairRunningApps().runningApps
        let rankByPID = RuntimeAppRankProvider.collectAppRankByPID(for: runningApps)
        return RuntimeFullRepairRunningAppFacts(
            runningApps: runningApps,
            appDirectoryEntries: RuntimeAppDirectoryFactSource.entries(
                from: runningApps,
                rankByPID: rankByPID
            )
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
            signature: collection.spaceTopologyDiff?.currentSignature,
            signatureSummary: collection.spaceTopologyDiff?.currentSignature.diagnosticSummary
        )
    }

    func collectSpaceTopologyReconciliationTargets(
        affectedCGWindowIDs: Set<CGWindowID>
    ) -> [RuntimeSpaceTopologyReconciliationTarget] {
        let cgWindowsByPID = runtimeFactProvider.collectCGWindowsWithSpaceTopologyDiff(
            options: [.excludeDesktopElements],
            now: ProcessInfo.processInfo.systemUptime
        ).windowsByPID
        let affectedCGWindowIDsByPID = windowRecordStore.affectedCGWindowIDsByPID(
            affectedCGWindowIDs: affectedCGWindowIDs,
            currentCGWindowsByPID: cgWindowsByPID
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
        windowRecordStore.cleanup(keepingRunningApps: runningApps)
        let cleanupReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        AXLiveWindowRegistry.shared.prune(to: runningApps)
        let pruneReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let onScreenCGWindowsByPID = runtimeFactProvider.collectCGWindowsWithSpaceTopologyDiff(
            options: [.optionOnScreenOnly, .excludeDesktopElements],
            now: ProcessInfo.processInfo.systemUptime
        ).windowsByPID
        let onScreenCGReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let allCGWindowsByPID = runtimeFactProvider.collectCGWindowsWithSpaceTopologyDiff(
            options: [.optionAll, .excludeDesktopElements],
            now: ProcessInfo.processInfo.systemUptime
        ).windowsByPID
        let allCGReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let sampledWindowsByPID = runtimeFactProvider.collectAXWindowData(
            for: runningApps,
            cgWindowsByPID: onScreenCGWindowsByPID,
            allCGWindowsByPID: allCGWindowsByPID
        )
        let axReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let windowsByPID = projectedWindowEntriesByPID(for: runningApps)
        let rankByPID = RuntimeAppRankProvider.collectAppRankByPID(for: runningApps)
        let completeMs = RuntimePerformanceClock.monotonicMilliseconds()
        RuntimeProjectionDiagnostics.logTiming(
            "collectWindowData",
            fields: [
                ("apps", "\(runningApps.count)"),
                ("onscreenCGWindows", "\(onScreenCGWindowsByPID.values.reduce(0) { $0 + $1.count })"),
                ("allCGWindows", "\(allCGWindowsByPID.values.reduce(0) { $0 + $1.count })"),
                ("sampledWindowPIDs", "\(sampledWindowsByPID.count)"),
                ("projectedWindowPIDs", "\(windowsByPID.count)"),
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
        // Sampling updates WindowRecord; projection selection reads the long-lived record table.
        return RuntimeFullRepairWindowFacts(
            windowsByPID: windowsByPID,
            rankByPID: rankByPID,
            refreshEvidence: RuntimeFullRepairWindowRecordRefreshEvidence(
                runningAppCount: runningApps.count,
                projectedWindowPIDCount: windowsByPID.count,
                projectedWindowCount: windowsByPID.values.reduce(0) { $0 + $1.count }
            )
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
        let cgWindowsByPID = runtimeFactProvider.collectCGWindowsWithSpaceTopologyDiff(
            options: [.optionOnScreenOnly, .excludeDesktopElements],
            now: ProcessInfo.processInfo.systemUptime
        ).windowsByPID
        let allCGWindowsByPID = runtimeFactProvider.collectCGWindowsWithSpaceTopologyDiff(
            options: [.optionAll, .excludeDesktopElements],
            now: ProcessInfo.processInfo.systemUptime
        ).windowsByPID
        _ = runtimeFactProvider.collectAXWindowData(
            for: matchingApps,
            cgWindowsByPID: cgWindowsByPID,
            allCGWindowsByPID: allCGWindowsByPID
        )
        let windowsByPID = projectedWindowEntriesByPID(for: matchingApps)
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
        in runningApps: [NSRunningApplication]
    ) -> RuntimeFocusedCurrentAppWindowFacts {
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
        AXLiveWindowRegistry.shared.prune(to: runningApps)
        let cleanupReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let cgWindowsByPID = runtimeFactProvider.collectCGWindowsWithSpaceTopologyDiff(
            options: [.optionOnScreenOnly, .excludeDesktopElements],
            now: ProcessInfo.processInfo.systemUptime
        ).windowsByPID
        let onScreenCGReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let allCGWindowsByPID = runtimeFactProvider.collectCGWindowsWithSpaceTopologyDiff(
            options: [.optionAll, .excludeDesktopElements],
            now: ProcessInfo.processInfo.systemUptime
        ).windowsByPID
        let allCGReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        _ = runtimeFactProvider.collectAXWindowData(
            for: [app],
            cgWindowsByPID: cgWindowsByPID,
            allCGWindowsByPID: allCGWindowsByPID
        )
        let axReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let windowsByPID = projectedWindowEntriesByPID(for: [app])
        return RuntimeFocusedCurrentAppWindowFacts(
            windowsByPID: windowsByPID,
            rankByPID: [:],
            timings: RuntimeFocusedCurrentAppWindowFactTimings(
                cleanupMs: cleanupReadyMs - startMs,
                onScreenCGMs: onScreenCGReadyMs - cleanupReadyMs,
                allCGMs: allCGReadyMs - onScreenCGReadyMs,
                axMs: axReadyMs - allCGReadyMs
            )
        )
    }

    private func projectedWindowEntriesByPID(
        for runningApps: [NSRunningApplication]
    ) -> [pid_t: [RuntimeWindowListEntry]] {
        Dictionary(
            uniqueKeysWithValues: runningApps.compactMap { app in
                let appName = app.localizedName ?? app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
                let entries = windowRecordStore.projectedWindowEntries(
                    processIdentifier: app.processIdentifier,
                    appName: appName
                )
                guard !entries.isEmpty else { return nil }
                return (app.processIdentifier, entries)
            }
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
