import AppKit
import ApplicationServices
import Foundation

enum RuntimeAppRankProvider {
    static func collectAppRankByPID(for runningApps: [NSRunningApplication]) -> [pid_t: Int] {
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
        let systemOrderedPIDs = RuntimeSystemAppOrderProvider.collectOrderedPIDs(
            for: runningApps
        )
        let systemOrderReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let needsBootstrapFallback = systemOrderedPIDs == nil
            && SystemAppMRUTracker.shared.requiresBootstrapFallback()
        let fallbackRankByPID = needsBootstrapFallback ? collectWindowStackRankByPID() : [:]
        let fallbackReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let rankByPID = SystemAppMRUTracker.shared.rankByPID(
            for: runningApps,
            fallbackRankByPID: fallbackRankByPID,
            systemOrderedPIDs: systemOrderedPIDs
        )
        let completeMs = RuntimePerformanceClock.monotonicMilliseconds()
        RuntimeProjectionDiagnostics.logTiming(
            "collectAppRank",
            fields: [
                ("apps", "\(runningApps.count)"),
                ("systemOrderPIDs", "\(systemOrderedPIDs?.count ?? 0)"),
                ("bootstrapFallback", needsBootstrapFallback ? "1" : "0"),
                ("fallbackPIDs", "\(fallbackRankByPID.count)"),
                ("rankedPIDs", "\(rankByPID.count)"),
                ("systemOrderMs", RuntimeProjectionDiagnostics.formatMilliseconds(systemOrderReadyMs - startMs)),
                ("fallbackMs", RuntimeProjectionDiagnostics.formatMilliseconds(fallbackReadyMs - systemOrderReadyMs)),
                ("systemMRUMs", RuntimeProjectionDiagnostics.formatMilliseconds(completeMs - fallbackReadyMs)),
                ("totalMs", RuntimeProjectionDiagnostics.formatMilliseconds(completeMs - startMs))
            ]
        )
        return rankByPID
    }

    private static func collectWindowStackRankByPID() -> [pid_t: Int] {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard
            let rawList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else {
            return [:]
        }

        var rankByPID: [pid_t: Int] = [:]
        for (rank, item) in rawList.enumerated() {
            guard let ownerPID = item[kCGWindowOwnerPID as String] as? pid_t else { continue }
            guard let layer = item[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            if rankByPID[ownerPID] == nil {
                rankByPID[ownerPID] = rank
            }
        }
        return rankByPID
    }
}
