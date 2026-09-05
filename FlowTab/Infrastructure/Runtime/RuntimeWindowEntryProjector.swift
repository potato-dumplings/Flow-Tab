import AppKit

protocol RuntimeWindowEntryProjecting {
    func entries(for runningApps: [NSRunningApplication]) -> [pid_t: [RuntimeWindowListEntry]]
}

struct RuntimeWindowEntryProjector: RuntimeWindowEntryProjecting {
    let windowRecordStore: RuntimeWindowRecordStore

    func entries(for runningApps: [NSRunningApplication]) -> [pid_t: [RuntimeWindowListEntry]] {
        Dictionary(uniqueKeysWithValues: runningApps.compactMap { app in
            let appName = app.localizedName ?? app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
            let entries = windowRecordStore.projectedWindowEntries(
                processIdentifier: app.processIdentifier, appName: appName
            )
            guard !entries.isEmpty else { return nil }
            return (app.processIdentifier, entries)
        })
    }
}
