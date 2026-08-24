import AppKit
import Foundation
import FlowTabCore

struct RuntimeAppWindowStats {
    let windowCount: Int
    let hasVisibleWindow: Bool
}

enum RuntimeApplicationDirectoryFilter {
    static func shouldIncludeRunningApplication(
        activationPolicy: NSApplication.ActivationPolicy,
        isTerminated: Bool,
        pid: pid_t,
        currentPID: pid_t
    ) -> Bool {
        ApplicationIdentityPolicy.decision(
            for: ApplicationIdentityFacts(
                isCurrentProcess: pid == currentPID,
                isTerminated: isTerminated,
                runtimeActivationPolicy: activationPolicy.flowTabCorePolicy,
                bundleSource: .none,
                isUIElement: false,
                isBackgroundOnly: false
            )
        ).isIncluded
    }
}

enum RuntimeAppLayerProjectionFilter {
    static func isEligibleRunningApplication(
        activationPolicy: NSApplication.ActivationPolicy,
        isTerminated: Bool
    ) -> Bool {
        activationPolicy == .regular && !isTerminated
    }

    static func shouldIncludeRunningApplication(
        activationPolicy: NSApplication.ActivationPolicy,
        isTerminated: Bool,
        pid: pid_t,
        currentPID: pid_t,
        includeCurrentProcessInAppLayer: Bool
    ) -> Bool {
        isEligibleRunningApplication(
            activationPolicy: activationPolicy,
            isTerminated: isTerminated
        )
            && (includeCurrentProcessInAppLayer || pid != currentPID)
    }

    static func shouldIncludeAppInAppLayer(
        hasWindows: Bool,
        hasVisibleWindow: Bool,
        hideMinimizedAppsFromAppLayer: Bool
    ) -> Bool {
        guard hideMinimizedAppsFromAppLayer else { return true }
        guard hasWindows else { return true }
        return hasVisibleWindow
    }
}

struct RuntimeAppDirectoryMaintenanceFacts {
    let windowRepairApplications: [NSRunningApplication]
    let entries: [RuntimeAppDirectoryEntry]
}

enum RuntimeAppDirectoryFactSource {
    static func currentAppLayerRunningApplications(
        includeCurrentProcessInAppLayer: Bool,
        workspace: NSWorkspace = .shared,
        currentPID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> [NSRunningApplication] {
        appLayerRunningApplications(
            from: workspace.runningApplications,
            currentPID: currentPID,
            includeCurrentProcessInAppLayer: includeCurrentProcessInAppLayer
        )
    }

    static func appLayerRunningApplications(
        from runningApplications: [NSRunningApplication],
        currentPID: pid_t,
        includeCurrentProcessInAppLayer: Bool
    ) -> [NSRunningApplication] {
        runningApplications.filter {
            RuntimeAppLayerProjectionFilter.shouldIncludeRunningApplication(
                activationPolicy: $0.activationPolicy,
                isTerminated: $0.isTerminated,
                pid: $0.processIdentifier,
                currentPID: currentPID,
                includeCurrentProcessInAppLayer: includeCurrentProcessInAppLayer
            )
        }
    }

    static func maintenanceFacts(
        from runningApplications: [NSRunningApplication],
        currentPID: pid_t,
        includeCurrentProcessInAppLayer: Bool,
        rankProvider: ([NSRunningApplication]) -> [pid_t: Int] = {
            RuntimeAppRankProvider.collectAppRankByPID(for: $0)
        }
    ) -> RuntimeAppDirectoryMaintenanceFacts {
        let directoryApplications = runningApplications.filter { app in
            RuntimeApplicationDirectoryFilter.shouldIncludeRunningApplication(
                activationPolicy: app.activationPolicy,
                isTerminated: app.isTerminated,
                pid: app.processIdentifier,
                currentPID: currentPID
            )
        }
        let windowRepairApplications = appLayerRunningApplications(
            from: directoryApplications,
            currentPID: currentPID,
            includeCurrentProcessInAppLayer: includeCurrentProcessInAppLayer
        )
        let eligiblePIDs = Set(windowRepairApplications.map(\.processIdentifier))
        let rankByPID = rankProvider(directoryApplications)
        let entries = directoryApplications.map { app in
            RuntimeAppDirectoryEntry(
                app: app,
                activationRank: rankByPID[app.processIdentifier],
                isEligibleForAppSwitcherProjection: eligiblePIDs.contains(app.processIdentifier)
            )
        }
        return RuntimeAppDirectoryMaintenanceFacts(
            windowRepairApplications: windowRepairApplications,
            entries: entries
        )
    }

    static func currentMaintenanceFacts(
        includeCurrentProcessInAppLayer: Bool,
        workspace: NSWorkspace = .shared,
        currentPID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> RuntimeAppDirectoryMaintenanceFacts {
        maintenanceFacts(
            from: workspace.runningApplications,
            currentPID: currentPID,
            includeCurrentProcessInAppLayer: includeCurrentProcessInAppLayer
        )
    }

    static func runningApplicationEntry(
        for app: NSRunningApplication,
        activationRank: Int? = nil,
        currentPID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> RuntimeAppDirectoryEntry? {
        guard RuntimeApplicationDirectoryFilter.shouldIncludeRunningApplication(
            activationPolicy: app.activationPolicy,
            isTerminated: app.isTerminated,
            pid: app.processIdentifier,
            currentPID: currentPID
        ) else {
            return nil
        }
        return RuntimeAppDirectoryEntry(
            app: app,
            activationRank: activationRank,
            isEligibleForAppSwitcherProjection:
                RuntimeAppLayerProjectionFilter.isEligibleRunningApplication(
                    activationPolicy: app.activationPolicy,
                    isTerminated: app.isTerminated
                )
        )
    }

    static func entries(
        from runningApplications: [NSRunningApplication],
        rankByPID: [pid_t: Int] = [:],
        currentPID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> [RuntimeAppDirectoryEntry] {
        runningApplications.compactMap { app in
            runningApplicationEntry(
                for: app,
                activationRank: rankByPID[app.processIdentifier],
                currentPID: currentPID
            )
        }
    }

    static func entries(
        from runningApplications: [NSRunningApplication],
        preservingRankFrom rankByPID: [pid_t: Int]
    ) -> [RuntimeAppDirectoryEntry] {
        entries(from: runningApplications, rankByPID: rankByPID)
    }
}

extension NSApplication.ActivationPolicy {
    var flowTabCorePolicy: ApplicationRuntimeActivationPolicy {
        switch self {
        case .regular:
            return .regular
        case .accessory:
            return .accessory
        case .prohibited:
            return .prohibited
        @unknown default:
            return .prohibited
        }
    }
}

struct RuntimeAppDirectoryEntry: Equatable {
    let pid: pid_t
    let appID: String
    let bundleIdentifier: String?
    let localizedName: String?
    let bundleURL: URL?
    let launchDate: Date?
    let activationRank: Int?
    let runningApplication: NSRunningApplication?
    let isEligibleForAppSwitcherProjection: Bool

    init(
        pid: pid_t,
        appID: String,
        bundleIdentifier: String?,
        localizedName: String?,
        bundleURL: URL? = nil,
        launchDate: Date?,
        activationRank: Int? = nil,
        runningApplication: NSRunningApplication? = nil,
        isEligibleForAppSwitcherProjection: Bool = true
    ) {
        self.pid = pid
        self.appID = appID
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.bundleURL = bundleURL
        self.launchDate = launchDate
        self.activationRank = activationRank
        self.runningApplication = runningApplication
        self.isEligibleForAppSwitcherProjection = isEligibleForAppSwitcherProjection
    }

    init(
        app: NSRunningApplication,
        activationRank: Int? = nil,
        isEligibleForAppSwitcherProjection: Bool = true
    ) {
        self.init(
            pid: app.processIdentifier,
            appID: RuntimeAppIdentity.appID(for: app),
            bundleIdentifier: app.bundleIdentifier,
            localizedName: app.localizedName,
            bundleURL: app.bundleURL,
            launchDate: app.launchDate,
            activationRank: activationRank,
            runningApplication: app,
            isEligibleForAppSwitcherProjection: isEligibleForAppSwitcherProjection
        )
    }

    static func == (lhs: RuntimeAppDirectoryEntry, rhs: RuntimeAppDirectoryEntry) -> Bool {
        lhs.pid == rhs.pid
            && lhs.appID == rhs.appID
            && lhs.bundleIdentifier == rhs.bundleIdentifier
            && lhs.localizedName == rhs.localizedName
            && lhs.bundleURL == rhs.bundleURL
            && lhs.launchDate == rhs.launchDate
            && lhs.activationRank == rhs.activationRank
            && lhs.runningApplication?.processIdentifier == rhs.runningApplication?.processIdentifier
            && lhs.isEligibleForAppSwitcherProjection == rhs.isEligibleForAppSwitcherProjection
    }

    func preservingMissingRuntimeFacts(from existing: RuntimeAppDirectoryEntry?) -> RuntimeAppDirectoryEntry {
        let preservedRank = activationRank ?? existing?.activationRank
        let preservedBundleURL = bundleURL ?? existing?.bundleURL
        let preservedRunningApplication = runningApplication ?? existing?.runningApplication
        let preservedAppSwitcherEligibility =
            existing?.isEligibleForAppSwitcherProjection ?? isEligibleForAppSwitcherProjection
        guard preservedRank != activationRank
            || preservedBundleURL != bundleURL
            || preservedRunningApplication?.processIdentifier != runningApplication?.processIdentifier
            || preservedAppSwitcherEligibility != isEligibleForAppSwitcherProjection
        else { return self }
        return RuntimeAppDirectoryEntry(
            pid: pid,
            appID: appID,
            bundleIdentifier: bundleIdentifier,
            localizedName: localizedName,
            bundleURL: preservedBundleURL,
            launchDate: launchDate,
            activationRank: preservedRank,
            runningApplication: preservedRunningApplication,
            isEligibleForAppSwitcherProjection: preservedAppSwitcherEligibility
        )
    }

    func preservingSnapshotMetadata(from existing: RuntimeAppDirectoryEntry?) -> RuntimeAppDirectoryEntry {
        guard let existing, existing.appID == appID else { return self }
        return RuntimeAppDirectoryEntry(
            pid: pid,
            appID: appID,
            bundleIdentifier: existing.bundleIdentifier ?? bundleIdentifier,
            localizedName: existing.localizedName ?? localizedName,
            bundleURL: existing.bundleURL ?? bundleURL,
            launchDate: existing.launchDate ?? launchDate,
            activationRank: existing.activationRank ?? activationRank,
            runningApplication: existing.runningApplication ?? runningApplication,
            isEligibleForAppSwitcherProjection: isEligibleForAppSwitcherProjection
        )
    }

    func withActivationRank(_ activationRank: Int?) -> RuntimeAppDirectoryEntry {
        RuntimeAppDirectoryEntry(
            pid: pid,
            appID: appID,
            bundleIdentifier: bundleIdentifier,
            localizedName: localizedName,
            bundleURL: bundleURL,
            launchDate: launchDate,
            activationRank: activationRank,
            runningApplication: runningApplication,
            isEligibleForAppSwitcherProjection: isEligibleForAppSwitcherProjection
        )
    }
}

struct RuntimeAppDirectoryState: Equatable {
    private var entriesByPID: [pid_t: RuntimeAppDirectoryEntry] = [:]
    private(set) var generatedAt: TimeInterval?
    private(set) var hasCompleteApplicationDirectoryCoverage = false

    var isInitialized: Bool {
        generatedAt != nil
    }

    var entryPIDs: Set<pid_t> {
        Set(entriesByPID.keys)
    }

    var entries: [RuntimeAppDirectoryEntry] {
        Self.sortedUniqueEntries(Array(entriesByPID.values))
    }

    mutating func replace(
        entries: [RuntimeAppDirectoryEntry],
        generatedAt: TimeInterval,
        hasCompleteApplicationDirectoryCoverage: Bool = true
    ) {
        entriesByPID = Dictionary(
            uniqueKeysWithValues: Self.sortedUniqueEntries(entries).map { ($0.pid, $0) }
        )
        self.generatedAt = generatedAt
        self.hasCompleteApplicationDirectoryCoverage = hasCompleteApplicationDirectoryCoverage
    }

    mutating func upsert(
        entries: [RuntimeAppDirectoryEntry],
        generatedAt: TimeInterval,
        completesApplicationDirectoryCoverage: Bool = false
    ) {
        guard !entries.isEmpty else { return }

        for entry in entries {
            entriesByPID[entry.pid] = entry.preservingMissingRuntimeFacts(from: entriesByPID[entry.pid])
        }
        self.generatedAt = generatedAt
        hasCompleteApplicationDirectoryCoverage =
            hasCompleteApplicationDirectoryCoverage || completesApplicationDirectoryCoverage
    }

    mutating func remove(
        pid: pid_t,
        generatedAt: TimeInterval
    ) {
        guard isInitialized else { return }

        entriesByPID.removeValue(forKey: pid)
        self.generatedAt = generatedAt
    }

    mutating func remove(
        appID: String,
        pid: pid_t,
        generatedAt: TimeInterval
    ) {
        guard isInitialized else { return }

        entriesByPID = entriesByPID.filter { _, entry in
            entry.appID != appID && entry.pid != pid
        }
        self.generatedAt = generatedAt
    }

    func entries(forAppID appID: String) -> [RuntimeAppDirectoryEntry] {
        entries.filter { $0.appID == appID }
    }

    func projection(
        freshness: (TimeInterval) -> RuntimeProjectionFreshness
    ) -> RuntimeAppDirectoryProjection? {
        guard let generatedAt else { return nil }
        return RuntimeAppDirectoryProjection(
            entries: entries,
            freshness: freshness(generatedAt)
        )
    }

    private static func sortedUniqueEntries(
        _ entries: [RuntimeAppDirectoryEntry]
    ) -> [RuntimeAppDirectoryEntry] {
        var entriesByPID: [pid_t: RuntimeAppDirectoryEntry] = [:]
        for entry in entries {
            entriesByPID[entry.pid] = entry
        }
        return entriesByPID.values
            .sorted { lhs, rhs in
                if lhs.appID == rhs.appID {
                    return lhs.pid < rhs.pid
                }
                return lhs.appID.localizedCaseInsensitiveCompare(rhs.appID) == .orderedAscending
            }
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

    static func activationRankByPID(
        from entries: [RuntimeAppDirectoryEntry]
    ) -> [pid_t: Int] {
        var rankByPID: [pid_t: Int] = [:]
        for entry in entries {
            guard let activationRank = entry.activationRank else { continue }
            rankByPID[entry.pid] = activationRank
        }
        return rankByPID
    }

    func selectPrimaryApps(
        windowStatsByPID: [pid_t: RuntimeAppWindowStats],
        rankByPID: [pid_t: Int]
    ) -> [NSRunningApplication] {
        let appsByPID = Dictionary(uniqueKeysWithValues: apps.map { app in
            (app.processIdentifier, app)
        })
        let selectedEntries = Self.selectPrimaryEntries(
            from: apps.map { RuntimeAppDirectoryEntry(app: $0) },
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
            group.map { RuntimeAppDirectoryEntry(app: $0) },
            windowStatsByPID: windowStatsByPID,
            rankByPID: rankByPID
        ).compactMap { entry in
            appsByPID[entry.pid]
        }
    }

    func mergedWindows<Window>(
        for group: [NSRunningApplication],
        windowsByPID: [pid_t: [Window]],
        windowStatsByPID: [pid_t: RuntimeAppWindowStats],
        rankByPID: [pid_t: Int]
    ) -> [Window] {
        sortedAppsWithinGroup(
            group,
            windowStatsByPID: windowStatsByPID,
            rankByPID: rankByPID
        ).flatMap { app in
            windowsByPID[app.processIdentifier] ?? []
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
            for: group.map { RuntimeAppDirectoryEntry(app: $0) },
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

    static func filterAppLayerEntries(
        _ entries: [RuntimeAppDirectoryEntry],
        windowStatsByPID: [pid_t: RuntimeAppWindowStats],
        hideMinimizedAppsFromAppLayer: Bool
    ) -> [RuntimeAppDirectoryEntry] {
        let candidateAppBundlePaths = Set(entries.compactMap { entry in
            standardizedAppBundlePath(for: entry.bundleURL)
        })
        return entries.filter { entry in
            let stats = windowStatsByPID[entry.pid]
                ?? RuntimeAppWindowStats(windowCount: 0, hasVisibleWindow: false)
            guard !shouldHideZeroWindowNestedApp(
                hasWindows: stats.windowCount > 0,
                bundleURL: entry.bundleURL,
                candidateAppBundlePaths: candidateAppBundlePaths
            ) else {
                return false
            }
            return RuntimeAppLayerProjectionFilter.shouldIncludeAppInAppLayer(
                hasWindows: stats.windowCount > 0,
                hasVisibleWindow: stats.hasVisibleWindow,
                hideMinimizedAppsFromAppLayer: hideMinimizedAppsFromAppLayer
            )
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

    static func windowStats<Window>(
        for entries: [RuntimeAppDirectoryEntry],
        windowsByPID: [pid_t: [Window]],
        isVisibleWindow: (Window) -> Bool
    ) -> [pid_t: RuntimeAppWindowStats] {
        Dictionary(uniqueKeysWithValues: entries.map { entry in
            let windows = windowsByPID[entry.pid] ?? []
            return (
                entry.pid,
                RuntimeAppWindowStats(
                    windowCount: windows.count,
                    hasVisibleWindow: windows.contains(where: isVisibleWindow)
                )
            )
        })
    }

    static func windowStats<Window>(
        for apps: [NSRunningApplication],
        windowsByPID: [pid_t: [Window]],
        isVisibleWindow: (Window) -> Bool
    ) -> [pid_t: RuntimeAppWindowStats] {
        windowStats(
            for: apps.map { RuntimeAppDirectoryEntry(app: $0) },
            windowsByPID: windowsByPID,
            isVisibleWindow: isVisibleWindow
        )
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
