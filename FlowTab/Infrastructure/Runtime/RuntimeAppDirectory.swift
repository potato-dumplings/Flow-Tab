import AppKit
import Foundation

struct RuntimeAppWindowStats {
    let windowCount: Int
    let hasVisibleWindow: Bool
}

struct RuntimeAppDirectoryEntry {
    let pid: pid_t
    let appID: String
    let bundleIdentifier: String?
    let localizedName: String?
    let launchDate: Date?

    init(
        pid: pid_t,
        appID: String,
        bundleIdentifier: String?,
        localizedName: String?,
        launchDate: Date?
    ) {
        self.pid = pid
        self.appID = appID
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.launchDate = launchDate
    }

    init(app: NSRunningApplication) {
        self.init(
            pid: app.processIdentifier,
            appID: RuntimeAppIdentity.appID(for: app),
            bundleIdentifier: app.bundleIdentifier,
            localizedName: app.localizedName,
            launchDate: app.launchDate
        )
    }
}

struct RuntimeAppDirectory {
    private let apps: [NSRunningApplication]
    private let candidateAppBundlePaths: Set<String>

    init(apps: [NSRunningApplication]) {
        self.apps = apps
        candidateAppBundlePaths = Set(apps.compactMap { Self.standardizedAppBundlePath(for: $0.bundleURL) })
    }

    func groupedAppsByAppID() -> [String: [NSRunningApplication]] {
        Dictionary(grouping: apps, by: RuntimeAppIdentity.appID(for:))
    }

    static func groupedEntriesByAppID(
        _ entries: [RuntimeAppDirectoryEntry]
    ) -> [String: [RuntimeAppDirectoryEntry]] {
        Dictionary(grouping: entries, by: \.appID)
    }

    func selectPrimaryApps(
        windowStatsByPID: [pid_t: RuntimeAppWindowStats],
        rankByPID: [pid_t: Int]
    ) -> [NSRunningApplication] {
        let appsByPID = Dictionary(uniqueKeysWithValues: apps.map { app in
            (app.processIdentifier, app)
        })
        let selectedEntries = Self.selectPrimaryEntries(
            from: apps.map(RuntimeAppDirectoryEntry.init(app:)),
            windowStatsByPID: windowStatsByPID,
            rankByPID: rankByPID
        ) { appID, primaryPID, droppedPIDs in
            RuntimeLog.debug(
                .projection,
                "dedupe appID=\(appID) keepPID=\(primaryPID) dropPIDs=\(droppedPIDs)"
            )
        }

        return selectedEntries.compactMap { entry in
            appsByPID[entry.pid]
        }
    }

    static func selectPrimaryEntries(
        from entries: [RuntimeAppDirectoryEntry],
        windowStatsByPID: [pid_t: RuntimeAppWindowStats],
        rankByPID: [pid_t: Int],
        duplicateHandler: ((String, pid_t, [pid_t]) -> Void)? = nil
    ) -> [RuntimeAppDirectoryEntry] {
        let grouped = groupedEntriesByAppID(entries)
        var selected: [RuntimeAppDirectoryEntry] = []
        selected.reserveCapacity(grouped.count)

        for (appID, group) in grouped {
            guard
                let primary = primaryEntry(
                    in: group,
                    windowStatsByPID: windowStatsByPID,
                    rankByPID: rankByPID
                )
            else {
                continue
            }
            selected.append(primary)

            if group.count > 1 {
                let sorted = sortedEntriesWithinGroup(
                    group,
                    windowStatsByPID: windowStatsByPID,
                    rankByPID: rankByPID
                )
                duplicateHandler?(appID, primary.pid, sorted.dropFirst().map(\.pid))
            }
        }

        return selected
    }

    static func primaryEntry(
        in group: [RuntimeAppDirectoryEntry],
        windowStatsByPID: [pid_t: RuntimeAppWindowStats],
        rankByPID: [pid_t: Int]
    ) -> RuntimeAppDirectoryEntry? {
        sortedEntriesWithinGroup(
            group,
            windowStatsByPID: windowStatsByPID,
            rankByPID: rankByPID
        ).first
    }

    func sortedAppsWithinGroup(
        _ group: [NSRunningApplication],
        windowStatsByPID: [pid_t: RuntimeAppWindowStats],
        rankByPID: [pid_t: Int]
    ) -> [NSRunningApplication] {
        let appsByPID = Dictionary(uniqueKeysWithValues: group.map { app in
            (app.processIdentifier, app)
        })
        return Self.sortedEntriesWithinGroup(
            group.map(RuntimeAppDirectoryEntry.init(app:)),
            windowStatsByPID: windowStatsByPID,
            rankByPID: rankByPID
        ).compactMap { entry in
            appsByPID[entry.pid]
        }
    }

    static func sortedEntriesWithinGroup(
        _ group: [RuntimeAppDirectoryEntry],
        windowStatsByPID: [pid_t: RuntimeAppWindowStats],
        rankByPID: [pid_t: Int]
    ) -> [RuntimeAppDirectoryEntry] {
        group.sorted { lhs, rhs in
            score(for: lhs, windowStatsByPID: windowStatsByPID, rankByPID: rankByPID)
                > score(for: rhs, windowStatsByPID: windowStatsByPID, rankByPID: rankByPID)
        }
    }

    func preferredRank(
        for group: [NSRunningApplication],
        rankByPID: [pid_t: Int],
        fallback: Int
    ) -> Int {
        Self.preferredRank(
            for: group.map(RuntimeAppDirectoryEntry.init(app:)),
            rankByPID: rankByPID,
            fallback: fallback
        )
    }

    static func preferredRank(
        for group: [RuntimeAppDirectoryEntry],
        rankByPID: [pid_t: Int],
        fallback: Int
    ) -> Int {
        group.compactMap { entry in
            rankByPID[entry.pid]
        }.min() ?? fallback
    }

    func filterAppLayerCandidates(
        windowStatsByPID: [pid_t: RuntimeAppWindowStats],
        hideMinimizedAppsFromAppLayer: Bool
    ) -> [NSRunningApplication] {
        apps.filter { app in
            let stats = windowStatsByPID[app.processIdentifier]
                ?? RuntimeAppWindowStats(windowCount: 0, hasVisibleWindow: false)
            guard !Self.shouldHideZeroWindowNestedApp(
                hasWindows: stats.windowCount > 0,
                bundleURL: app.bundleURL,
                candidateAppBundlePaths: candidateAppBundlePaths
            ) else {
                logSkippedApp(app, reason: "nested zero-window")
                return false
            }
            guard RuntimeAppLayerProjectionFilter.shouldIncludeAppInAppLayer(
                hasWindows: stats.windowCount > 0,
                hasVisibleWindow: stats.hasVisibleWindow,
                hideMinimizedAppsFromAppLayer: hideMinimizedAppsFromAppLayer
            ) else {
                logSkippedApp(app, reason: "minimized-only")
                return false
            }
            return true
        }
    }

    static func mergedWindowStats(
        processIDs: [pid_t],
        windowStatsByPID: [pid_t: RuntimeAppWindowStats]
    ) -> RuntimeAppWindowStats {
        var windowCount = 0
        var hasVisibleWindow = false
        for pid in processIDs {
            guard let stats = windowStatsByPID[pid] else { continue }
            windowCount += stats.windowCount
            hasVisibleWindow = hasVisibleWindow || stats.hasVisibleWindow
        }
        return RuntimeAppWindowStats(windowCount: windowCount, hasVisibleWindow: hasVisibleWindow)
    }

    static func stableLastActiveValue(forRank rank: Int) -> TimeInterval {
        -Double(max(rank, 0))
    }

    static func shouldHideZeroWindowNestedApp(
        hasWindows: Bool,
        bundleURL: URL?,
        candidateAppBundlePaths: Set<String>
    ) -> Bool {
        guard !hasWindows else { return false }
        guard
            let bundlePath = standardizedAppBundlePath(for: bundleURL),
            candidateAppBundlePaths.count > 1
        else {
            return false
        }

        return appBundleAncestorPaths(for: bundlePath).contains { candidateAppBundlePaths.contains($0) }
    }

    static func standardizedAppBundlePath(for bundleURL: URL?) -> String? {
        guard let bundleURL else { return nil }
        let standardizedURL = bundleURL.standardizedFileURL
        guard standardizedURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
            return nil
        }
        return standardizedURL.path
    }

    private static func appBundleAncestorPaths(for bundlePath: String) -> [String] {
        var ancestorPaths: [String] = []
        var currentURL = URL(fileURLWithPath: bundlePath).deletingLastPathComponent()

        while currentURL.path != "/" {
            let standardizedURL = currentURL.standardizedFileURL
            if standardizedURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                ancestorPaths.append(standardizedURL.path)
            }

            let parentURL = currentURL.deletingLastPathComponent()
            guard parentURL.path != currentURL.path else { break }
            currentURL = parentURL
        }

        return ancestorPaths
    }

    private static func score(
        for entry: RuntimeAppDirectoryEntry,
        windowStatsByPID: [pid_t: RuntimeAppWindowStats],
        rankByPID: [pid_t: Int]
    ) -> Int {
        let pid = entry.pid
        let windowCount = windowStatsByPID[pid]?.windowCount ?? 0
        let hasWindowsScore = windowCount > 0 ? 1_000_000 : 0
        let windowCountScore = min(windowCount, 9_999) * 100
        let rankScore = 10_000 - min(rankByPID[pid] ?? 10_000, 10_000)
        let launchScore = Int(entry.launchDate?.timeIntervalSince1970 ?? 0) % 10_000
        return hasWindowsScore + windowCountScore + rankScore + launchScore
    }

    private func logSkippedApp(_ app: NSRunningApplication, reason: String) {
        let appName = app.localizedName ?? app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
        RuntimeLog.debug(.projection, "skip \(reason) app=\(appName) pid=\(app.processIdentifier)")
    }
}
