import AppKit
import ApplicationServices
import Foundation

enum RuntimeAppRankProvider {
    static func collectAppRankByPID(for runningApps: [NSRunningApplication]) -> [pid_t: Int] {
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
        let needsBootstrapFallback = SystemAppMRUTracker.shared.requiresBootstrapFallback()
        let fallbackRankByPID = needsBootstrapFallback ? collectWindowStackRankByPID() : [:]
        let fallbackReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let rankByPID = SystemAppMRUTracker.shared.rankByPID(
            for: runningApps,
            fallbackRankByPID: fallbackRankByPID
        )
        let completeMs = RuntimePerformanceClock.monotonicMilliseconds()
        RuntimeProjectionDiagnostics.logTiming(
            "collectAppRank",
            fields: [
                ("apps", "\(runningApps.count)"),
                ("bootstrapFallback", needsBootstrapFallback ? "1" : "0"),
                ("fallbackPIDs", "\(fallbackRankByPID.count)"),
                ("rankedPIDs", "\(rankByPID.count)"),
                ("fallbackMs", RuntimeProjectionDiagnostics.formatMilliseconds(fallbackReadyMs - startMs)),
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
