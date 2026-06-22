import AppKit
import Foundation

struct RuntimeRepairRunningAppFacts {
    let runningApps: [NSRunningApplication]
    let appDirectoryEntries: [RuntimeAppDirectoryEntry]
}

struct RuntimeFullRepairWindowFacts {
    let windowsByPID: [pid_t: [RuntimeWindowListEntry]]
    let rankByPID: [pid_t: Int]
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

struct RuntimeProjectionRepairFactSource {
    let snapshotProvider: RuntimeSnapshotProvider

    func collectRepairRunningAppFacts() -> RuntimeRepairRunningAppFacts {
        let runningApps = RuntimeAppDirectoryFactSource.currentAppLayerRunningApplications(
            includeCurrentProcessInAppLayer: AppVisibilityPreferencesStore.loadShowInCommandTab()
        )
        return RuntimeRepairRunningAppFacts(
            runningApps: runningApps,
            appDirectoryEntries: RuntimeAppDirectoryFactSource.entries(from: runningApps)
        )
    }

    func collectFullRepairWindowFacts(for runningApps: [NSRunningApplication]) -> RuntimeFullRepairWindowFacts {
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
        snapshotProvider.cleanupWindowMappingState(for: runningApps)
        let cleanupReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        AXLiveWindowRegistry.shared.prune(to: runningApps)
        let pruneReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let onScreenCGWindowsByPID = snapshotProvider.collectCGWindowsWithSpaceTopologyDiff().windowsByPID
        let onScreenCGReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let allCGWindowsByPID = snapshotProvider.collectCGWindowsWithSpaceTopologyDiff(
            options: [.optionAll, .excludeDesktopElements]
        ).windowsByPID
        let allCGReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let axWindowsByPID = snapshotProvider.collectAXWindowData(
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

    func collectCurrentAppWindowFacts(
        for matchingApps: [NSRunningApplication],
        in runningApps: [NSRunningApplication]
    ) -> RuntimeCurrentAppWindowFacts {
        let rankByPID = RuntimeAppRankProvider.collectAppRankByPID(for: runningApps)
        let cgWindowsByPID = snapshotProvider.collectCGWindowsWithSpaceTopologyDiff().windowsByPID
        let allCGWindowsByPID = snapshotProvider.collectCGWindowsWithSpaceTopologyDiff(
            options: [.optionAll, .excludeDesktopElements]
        ).windowsByPID
        let windowsByPID = snapshotProvider.collectAXWindowData(
            for: matchingApps,
            cgWindowsByPID: cgWindowsByPID,
            allCGWindowsByPID: allCGWindowsByPID
        )
        return RuntimeCurrentAppWindowFacts(
            windowsByPID: windowsByPID,
            rankByPID: rankByPID
        )
    }

    func collectFocusedCurrentAppWindowFacts(
        for app: NSRunningApplication,
        in runningApps: [NSRunningApplication],
        processIdentifier pid: pid_t
    ) -> RuntimeFocusedCurrentAppWindowFacts {
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
        snapshotProvider.cleanupWindowMappingState(for: runningApps)
        AXLiveWindowRegistry.shared.prune(to: runningApps)
        let cleanupReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let cgWindowsByPID = snapshotProvider.collectCGWindowsWithSpaceTopologyDiff().windowsByPID
        let onScreenCGReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let allCGWindowsByPID = snapshotProvider.collectCGWindowsWithSpaceTopologyDiff(
            options: [.optionAll, .excludeDesktopElements]
        ).windowsByPID
        let allCGReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let windowsByPID = snapshotProvider.collectAXWindowData(
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
}
