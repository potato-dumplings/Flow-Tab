import AppKit
import Foundation

protocol RuntimeFocusedWindowFactCollecting {
    func collect(for app: NSRunningApplication, in runningApps: [NSRunningApplication])
        -> RuntimeFocusedCurrentAppWindowFacts
}

struct RuntimeFocusedWindowFactCollector: RuntimeFocusedWindowFactCollecting {
    let runtimeFactProvider: any RuntimeProjectionRepairFactProviding
    let windowEntries: any RuntimeWindowEntryProjecting

    func collect(
        for app: NSRunningApplication,
        in runningApps: [NSRunningApplication]
    ) -> RuntimeFocusedCurrentAppWindowFacts {
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
        let focusedApps = RuntimeProjectionRepairFactSource.focusedAppGroup(for: app, in: runningApps)
        AXLiveWindowRegistry.shared.prune(to: runningApps)
        let cleanupReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let cgCollection = runtimeFactProvider.collectCGWindowsWithSpaceTopologyDiff(
            options: [.optionOnScreenOnly, .excludeDesktopElements],
            now: ProcessInfo.processInfo.systemUptime
        )
        let cgWindowsByPID = cgCollection.windowsByPID
        let onScreenCGReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let allCGCollection = runtimeFactProvider.collectCGWindowsWithSpaceTopologyDiff(
            options: [.optionAll, .excludeDesktopElements],
            now: ProcessInfo.processInfo.systemUptime
        )
        let allCGWindowsByPID = allCGCollection.windowsByPID
        let allCGReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        _ = runtimeFactProvider.collectAXWindowData(
            for: focusedApps,
            cgWindowsByPID: cgWindowsByPID,
            allCGWindowsByPID: allCGWindowsByPID,
            allCGCollectionIsComplete: allCGCollection.isComplete
        )
        let axReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let windowsByPID = windowEntries.entries(for: focusedApps)
        return RuntimeFocusedCurrentAppWindowFacts(
            windowsByPID: windowsByPID,
            rankByPID: [:],
            authoritativeCGWindowIDsByPID: allCGCollection.isComplete
                ? allCGWindowsByPID.mapValues { Set($0.map(\.id)) }
                : nil,
            timings: RuntimeFocusedCurrentAppWindowFactTimings(
                cleanupMs: cleanupReadyMs - startMs,
                onScreenCGMs: onScreenCGReadyMs - cleanupReadyMs,
                allCGMs: allCGReadyMs - onScreenCGReadyMs,
                axMs: axReadyMs - allCGReadyMs
            )
        )
    }
}
