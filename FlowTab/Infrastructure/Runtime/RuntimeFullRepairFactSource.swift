import AppKit
import Foundation

struct RuntimeFullRepairWindowFacts {
    let windowsByPID: [pid_t: [RuntimeWindowListEntry]]
    let rankByPID: [pid_t: Int]
}

struct RuntimeFullRepairFactSource {
    let snapshotProvider: RuntimeSnapshotProvider

    func collectWindowFacts(for runningApps: [NSRunningApplication]) -> RuntimeFullRepairWindowFacts {
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
}
