import AppKit
import Foundation

extension RuntimeSnapshotProvider {
    func groupedAppsByBaseID(_ apps: [NSRunningApplication]) -> [String: [NSRunningApplication]] {
        Dictionary(grouping: apps, by: Self.baseAppID(for:))
    }

    func sortedAppsWithinGroup(
        _ apps: [NSRunningApplication],
        windowsByPID: [pid_t: [WindowListEntry]],
        rankByPID: [pid_t: Int]
    ) -> [NSRunningApplication] {
        apps.sorted { lhs, rhs in
            score(
                for: lhs,
                windowsByPID: windowsByPID,
                rankByPID: rankByPID
            ) > score(
                for: rhs,
                windowsByPID: windowsByPID,
                rankByPID: rankByPID
            )
        }
    }

    func mergedWindowEntries(
        for apps: [NSRunningApplication],
        windowsByPID: [pid_t: [WindowListEntry]],
        rankByPID: [pid_t: Int]
    ) -> [WindowListEntry] {
        sortedAppsWithinGroup(
            apps,
            windowsByPID: windowsByPID,
            rankByPID: rankByPID
        ).flatMap { app in
            windowsByPID[app.processIdentifier] ?? []
        }
    }

    func preferredRankForAppGroup(
        _ apps: [NSRunningApplication],
        rankByPID: [pid_t: Int],
        fallback: Int
    ) -> Int {
        apps.compactMap { app in
            rankByPID[app.processIdentifier]
        }.min() ?? fallback
    }

    static func mergedWindowStats(
        processIDs: [pid_t],
        windowStatsByPID: [pid_t: AXWindowStats]
    ) -> AXWindowStats {
        var windowCount = 0
        var hasVisibleWindow = false
        for pid in processIDs {
            guard let stats = windowStatsByPID[pid] else { continue }
            windowCount += stats.windowCount
            hasVisibleWindow = hasVisibleWindow || stats.hasVisibleWindow
        }
        return AXWindowStats(windowCount: windowCount, hasVisibleWindow: hasVisibleWindow)
    }

    static func mergedWindowStatsForTesting(
        processIDs: [pid_t],
        windowStatsByPID: [pid_t: AXWindowStats]
    ) -> AXWindowStats {
        mergedWindowStats(processIDs: processIDs, windowStatsByPID: windowStatsByPID)
    }
}
