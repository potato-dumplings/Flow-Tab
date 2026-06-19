import AppKit
import Foundation

struct RuntimeAppWindowStats {
    let windowCount: Int
    let hasVisibleWindow: Bool
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

    func selectPrimaryApps(
        windowStatsByPID: [pid_t: RuntimeAppWindowStats],
        rankByPID: [pid_t: Int]
    ) -> [NSRunningApplication] {
        let grouped = groupedAppsByAppID()
        var selected: [NSRunningApplication] = []
        selected.reserveCapacity(grouped.count)

        for (appID, group) in grouped {
            guard group.count > 1 else {
                if let app = group.first {
                    selected.append(app)
                }
                continue
            }

            let sorted = sortedAppsWithinGroup(
                group,
                windowStatsByPID: windowStatsByPID,
                rankByPID: rankByPID
            )
            guard let primary = sorted.first else { continue }
            selected.append(primary)

            let droppedPIDs = sorted.dropFirst().map(\.processIdentifier)
            RuntimeLog.debug(
                .projection,
                "dedupe appID=\(appID) keepPID=\(primary.processIdentifier) dropPIDs=\(droppedPIDs)"
            )
        }

        return selected
    }

    func sortedAppsWithinGroup(
        _ group: [NSRunningApplication],
        windowStatsByPID: [pid_t: RuntimeAppWindowStats],
        rankByPID: [pid_t: Int]
    ) -> [NSRunningApplication] {
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
        group.compactMap { app in
            rankByPID[app.processIdentifier]
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

    private func score(
        for app: NSRunningApplication,
        windowStatsByPID: [pid_t: RuntimeAppWindowStats],
        rankByPID: [pid_t: Int]
    ) -> Int {
        let pid = app.processIdentifier
        let windowCount = windowStatsByPID[pid]?.windowCount ?? 0
        let hasWindowsScore = windowCount > 0 ? 1_000_000 : 0
        let windowCountScore = min(windowCount, 9_999) * 100
        let rankScore = 10_000 - min(rankByPID[pid] ?? 10_000, 10_000)
        let launchScore = Int(app.launchDate?.timeIntervalSince1970 ?? 0) % 10_000
        return hasWindowsScore + windowCountScore + rankScore + launchScore
    }

    private func logSkippedApp(_ app: NSRunningApplication, reason: String) {
        let appName = app.localizedName ?? app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
        RuntimeLog.debug(.projection, "skip \(reason) app=\(appName) pid=\(app.processIdentifier)")
    }
}
