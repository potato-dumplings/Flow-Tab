import AppKit
import Foundation

extension RuntimeSnapshotProvider {
    private func sortedAppsWithinGroup(
        _ apps: [NSRunningApplication],
        windowsByPID: [pid_t: [WindowListEntry]],
        rankByPID: [pid_t: Int]
    ) -> [NSRunningApplication] {
        RuntimeAppDirectory(apps: apps).sortedAppsWithinGroup(
            apps,
            windowStatsByPID: windowStatsByPID(for: apps, windowsByPID: windowsByPID),
            rankByPID: rankByPID
        )
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

    func windowStatsByPID(
        for apps: [NSRunningApplication],
        windowsByPID: [pid_t: [WindowListEntry]]
    ) -> [pid_t: RuntimeAppWindowStats] {
        Dictionary(uniqueKeysWithValues: apps.map { app in
            let windows = windowsByPID[app.processIdentifier] ?? []
            return (
                app.processIdentifier,
                RuntimeAppWindowStats(
                    windowCount: windows.count,
                    hasVisibleWindow: windows.contains(where: { !$0.isMinimized })
                )
            )
        })
    }
}
