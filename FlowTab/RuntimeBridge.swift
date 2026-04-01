import AppKit
import ApplicationServices
import Foundation
import FlowTabCore
import ScreenCaptureKit

enum WindowTitleBarStyleGuess: String {
    case dark
    case light
}

struct RuntimeSnapshot {
    let apps: [AppSwitchCandidate]
    let contextsByID: [String: RuntimeAppContext]
}

struct RuntimeAppContext {
    let appID: String
    let runningApp: NSRunningApplication
    let windowsByID: [String: RuntimeWindowContext]
}

struct RuntimeWindowContext {
    let id: String
    let title: String
    let isMinimized: Bool
    var cgWindowID: CGWindowID?
    var inferredTitleBarStyle: WindowTitleBarStyleGuess?
}

enum FlowTabTestLaunchOptions {
    private static var arguments: [String] {
        ProcessInfo.processInfo.arguments
    }

    static var usesMockRuntimeSnapshot: Bool {
        arguments.contains("--flowtab-ui-mock-runtime")
    }

    static var resetsUserDefaultsOnLaunch: Bool {
        arguments.contains("--flowtab-ui-reset-defaults")
    }

    static var opensSwitcherOnLaunch: Bool {
        arguments.contains("--flowtab-ui-open-switcher")
            || arguments.contains("--flowtab-ui-open-switcher-search")
    }

    static var entersSearchOnLaunch: Bool {
        arguments.contains("--flowtab-ui-open-switcher-search")
    }

    static var accessibilityTrustedOverride: Bool? {
        boolValue(after: "--flowtab-ui-ax-trusted")
    }

    static var screenCaptureTrustedOverride: Bool? {
        boolValue(after: "--flowtab-ui-screen-trusted")
    }

    static var seededLogCount: Int? {
        guard let rawValue = value(after: "--flowtab-ui-seed-logs") else { return nil }
        return Int(rawValue)
    }

    private static func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let nextIndex = arguments.index(after: index)
        guard nextIndex < arguments.endIndex else { return nil }
        return arguments[nextIndex]
    }

    private static func boolValue(after flag: String) -> Bool? {
        guard let rawValue = value(after: flag)?.lowercased() else { return nil }
        switch rawValue {
        case "1", "true", "yes":
            return true
        case "0", "false", "no":
            return false
        default:
            return nil
        }
    }
}

enum AccessibilityPermissionChecker {
    static var isTrustedOverrideForTesting: (() -> Bool)?
    static var requestPermissionOverrideForTesting: (() -> Bool)?

    static func isTrusted() -> Bool {
        if let isTrustedOverrideForTesting {
            return isTrustedOverrideForTesting()
        }
        if let override = FlowTabTestLaunchOptions.accessibilityTrustedOverride {
            return override
        }
        return AXIsProcessTrusted()
    }

    @discardableResult
    static func requestPermission() -> Bool {
        if let requestPermissionOverrideForTesting {
            return requestPermissionOverrideForTesting()
        }
        if let override = FlowTabTestLaunchOptions.accessibilityTrustedOverride {
            return override
        }
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

struct RuntimeHomeAppSummary: Equatable, Identifiable {
    let appID: String
    let displayName: String
    let groupID: String
    let lastActiveAt: TimeInterval
    let windowCount: Int
    let pid: pid_t

    var id: String { appID }
}

struct RuntimeHomeAppSnapshot {
    let summary: RuntimeHomeAppSummary
    let candidate: AppSwitchCandidate
    let context: RuntimeAppContext
}

final class SystemAppMRUTracker {
    static let shared = SystemAppMRUTracker()

    private let lock = NSLock()
    private var hasStarted = false
    private var observers: [NSObjectProtocol] = []
    private var mruPIDs: [pid_t] = []

    private init() {}

    func startIfNeeded() {
        if Thread.isMainThread {
            startOnMainThreadIfNeeded()
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.startOnMainThreadIfNeeded()
        }
    }

    func rankByPID(
        for runningApps: [NSRunningApplication],
        fallbackRankByPID: [pid_t: Int]
    ) -> [pid_t: Int] {
        startIfNeeded()

        let runningPIDs = Set(runningApps.map(\.processIdentifier))
        let trackedOrder = trackedMRUOrder(for: runningPIDs)
        let currentPID = ProcessInfo.processInfo.processIdentifier
        return Self.rankByPID(
            runningPIDs: runningApps.map(\.processIdentifier),
            trackedOrder: trackedOrder,
            currentPID: currentPID,
            launchRankByPID: Self.launchRankByPID(for: runningApps),
            fallbackRankByPID: fallbackRankByPID
        )
    }

    static func rankByPID(
        runningPIDs: [pid_t],
        trackedOrder: [pid_t],
        currentPID: pid_t,
        launchRankByPID: [pid_t: Int],
        fallbackRankByPID: [pid_t: Int]
    ) -> [pid_t: Int] {
        var rankByPID: [pid_t: Int] = [:]
        rankByPID.reserveCapacity(runningPIDs.count)

        var nextRank = 0
        for pid in trackedOrder where runningPIDs.contains(pid) && rankByPID[pid] == nil {
            rankByPID[pid] = nextRank
            nextRank += 1
        }

        let fallbackPIDs = runningPIDs
            .filter { rankByPID[$0] == nil }
            .sorted { lhs, rhs in
                let lhsRank = fallbackRank(
                    for: lhs,
                    currentPID: currentPID,
                    launchRankByPID: launchRankByPID,
                    fallbackRankByPID: fallbackRankByPID
                )
                let rhsRank = fallbackRank(
                    for: rhs,
                    currentPID: currentPID,
                    launchRankByPID: launchRankByPID,
                    fallbackRankByPID: fallbackRankByPID
                )
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                return lhs < rhs
            }

        for pid in fallbackPIDs {
            rankByPID[pid] = nextRank
            nextRank += 1
        }

        return rankByPID
    }

    private func startOnMainThreadIfNeeded() {
        lock.lock()
        if hasStarted {
            lock.unlock()
            return
        }
        hasStarted = true
        lock.unlock()

        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter

        let didActivateObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.handleApplicationNotification(notification, removeOnly: false)
        }

        let didTerminateObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.handleApplicationNotification(notification, removeOnly: true)
        }

        lock.lock()
        observers.append(contentsOf: [didActivateObserver, didTerminateObserver])
        lock.unlock()

        if let frontmost = NSWorkspace.shared.frontmostApplication {
            recordActivation(of: frontmost.processIdentifier)
        }
    }

    private func handleApplicationNotification(_ notification: Notification, removeOnly: Bool) {
        guard
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else {
            return
        }
        if removeOnly {
            remove(pid: app.processIdentifier)
            return
        }
        recordActivation(of: app.processIdentifier)
    }

    private func recordActivation(of pid: pid_t) {
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }
        lock.lock()
        defer { lock.unlock() }
        mruPIDs.removeAll { $0 == pid }
        mruPIDs.insert(pid, at: 0)
    }

    private func remove(pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        mruPIDs.removeAll { $0 == pid }
    }

    private func trackedMRUOrder(for runningPIDs: Set<pid_t>) -> [pid_t] {
        lock.lock()
        defer { lock.unlock() }
        mruPIDs.removeAll { !runningPIDs.contains($0) }
        return mruPIDs
    }

    private static func fallbackRank(
        for pid: pid_t,
        currentPID: pid_t,
        launchRankByPID: [pid_t: Int],
        fallbackRankByPID: [pid_t: Int]
    ) -> Int {
        if pid == currentPID {
            return launchRankByPID[pid] ?? Int.max
        }
        return fallbackRankByPID[pid] ?? Int.max
    }

    private static func launchRankByPID(for runningApps: [NSRunningApplication]) -> [pid_t: Int] {
        let sorted = runningApps.sorted { lhs, rhs in
            let lhsLaunchDate = lhs.launchDate ?? Date.distantPast
            let rhsLaunchDate = rhs.launchDate ?? Date.distantPast
            if lhsLaunchDate != rhsLaunchDate {
                return lhsLaunchDate > rhsLaunchDate
            }
            return lhs.processIdentifier < rhs.processIdentifier
        }

        var rankByPID: [pid_t: Int] = [:]
        rankByPID.reserveCapacity(sorted.count)
        for (rank, app) in sorted.enumerated() {
            rankByPID[app.processIdentifier] = rank
        }
        return rankByPID
    }
}

final class RuntimeSnapshotProvider {
    private struct WindowListEntry {
        let windowID: String
        let title: String
        let isMinimized: Bool
        let cgWindowID: CGWindowID?
    }

    private struct CGWindowEntry {
        let id: CGWindowID
        let title: String?
    }

    private struct AXWindowStats {
        let windowCount: Int
        let hasVisibleWindow: Bool
    }

    struct SnapshotAssemblyApp {
        let pid: pid_t
        let bundleIdentifier: String?
        let localizedName: String?
        let launchDate: Date?
    }

    struct SnapshotAssemblyWindow {
        let windowID: String
        let title: String
        let isMinimized: Bool
        let cgWindowID: CGWindowID?
    }

    struct SnapshotAssemblyRow {
        let pid: pid_t
        let candidate: AppSwitchCandidate
    }

    private struct UITestRuntimeDataset {
        let snapshot: RuntimeSnapshot
        let summaries: [RuntimeHomeAppSummary]
        let snapshotsByAppID: [String: RuntimeHomeAppSnapshot]
    }

    private static func uiTestRuntimeDataset() -> UITestRuntimeDataset? {
        guard FlowTabTestLaunchOptions.usesMockRuntimeSnapshot else { return nil }

        let runningApp = NSRunningApplication.current
        let appDefinitions: [(appID: String, name: String, windows: [WindowCandidate], rank: Int)] = [
            (
                appID: "com.flowtab.mock.mail",
                name: "Mock Mail",
                windows: [
                    WindowCandidate(id: "mock-mail-inbox", title: "Inbox", isMinimized: false, lastActiveAt: 300),
                    WindowCandidate(id: "mock-mail-draft", title: "Draft", isMinimized: false, lastActiveAt: 299)
                ],
                rank: 0
            ),
            (
                appID: "com.flowtab.mock.browser",
                name: "Mock Browser",
                windows: [
                    WindowCandidate(id: "mock-browser-docs", title: "Docs", isMinimized: false, lastActiveAt: 290)
                ],
                rank: 1
            )
        ]

        let candidates = appDefinitions.map { definition in
            AppSwitchCandidate(
                id: definition.appID,
                displayName: definition.name,
                groupID: "mock",
                lastActiveAt: Self.stableLastActiveValue(forRank: definition.rank),
                windows: definition.windows
            )
        }

        let summaries = appDefinitions.enumerated().map { index, definition in
            RuntimeHomeAppSummary(
                appID: definition.appID,
                displayName: definition.name,
                groupID: "mock",
                lastActiveAt: Self.stableLastActiveValue(forRank: definition.rank),
                windowCount: definition.windows.count,
                pid: pid_t(10_000 + index)
            )
        }

        let snapshotsByAppID = Dictionary(uniqueKeysWithValues: appDefinitions.enumerated().map { index, definition in
            let windowContexts = Dictionary(uniqueKeysWithValues: definition.windows.map { window in
                (
                    window.id,
                    RuntimeWindowContext(
                        id: window.id,
                        title: window.title,
                        isMinimized: window.isMinimized,
                        cgWindowID: nil,
                        inferredTitleBarStyle: nil
                    )
                )
            })
            let context = RuntimeAppContext(
                appID: definition.appID,
                runningApp: runningApp,
                windowsByID: windowContexts
            )
            let snapshot = RuntimeHomeAppSnapshot(
                summary: summaries[index],
                candidate: candidates[index],
                context: context
            )
            return (definition.appID, snapshot)
        })

        return UITestRuntimeDataset(
            snapshot: RuntimeSnapshot(apps: candidates, contextsByID: [:]),
            summaries: summaries,
            snapshotsByAppID: snapshotsByAppID
        )
    }

    func snapshot() -> RuntimeSnapshot {
        if let uiTestRuntimeDataset = Self.uiTestRuntimeDataset() {
            return uiTestRuntimeDataset.snapshot
        }
        let runningApps = filteredRunningApplications()

        guard !runningApps.isEmpty else {
            return RuntimeSnapshot(apps: [], contextsByID: [:])
        }

        RuntimeLog.info("Snapshot", "runningApps=\(runningApps.count)")
        let windowData = collectWindowData(for: runningApps)
        let selectedApps = selectPrimaryApps(
            from: runningApps,
            windowsByPID: windowData.windowsByPID,
            rankByPID: windowData.rankByPID
        )
        let hideMinimizedAppsFromAppLayer =
            SwitcherBehaviorPreferencesStore.loadHideMinimizedAppsFromAppLayer()
        let appLayerCandidates = filterAppsForAppLayer(
            selectedApps,
            windowsByPID: windowData.windowsByPID,
            hideMinimizedAppsFromAppLayer: hideMinimizedAppsFromAppLayer
        )
        RuntimeLog.info(
            "Snapshot",
            "selectedApps=\(selectedApps.count) appLayerCandidates=\(appLayerCandidates.count) hideMinimized=\(hideMinimizedAppsFromAppLayer)"
        )

        guard !appLayerCandidates.isEmpty else {
            return RuntimeSnapshot(apps: [], contextsByID: [:])
        }
        let now = Date.timeIntervalSinceReferenceDate

        var rows: [(candidate: AppSwitchCandidate, context: RuntimeAppContext)] = []
        rows.reserveCapacity(appLayerCandidates.count)

        for (index, app) in appLayerCandidates.enumerated() {
            let pid = app.processIdentifier
            let baseAppID = Self.baseAppID(for: app)
            let appID = baseAppID
            let displayName = app.localizedName ?? baseAppID

            let windows = windowData.windowsByPID[pid] ?? []
            RuntimeLog.info(
                "Snapshot",
                "\(displayName) pid=\(pid) appID=\(appID) windows=\(windows.count)"
            )
            let windowCandidates = windows.enumerated().map { entryIndex, entry in
                WindowCandidate(
                    id: entry.windowID,
                    title: entry.title,
                    isMinimized: entry.isMinimized,
                    lastActiveAt: now - Double(entryIndex)
                )
            }

            let rank = windowData.rankByPID[pid] ?? (10_000 + index)
            let candidate = AppSwitchCandidate(
                id: appID,
                displayName: displayName,
                groupID: Self.groupID(for: app.bundleIdentifier, fallbackName: displayName),
                lastActiveAt: now - Double(rank),
                windows: windowCandidates
            )

            let windowContexts = Dictionary(
                uniqueKeysWithValues: windows.map {
                    let id = $0.windowID
                    return (
                        id,
                        RuntimeWindowContext(
                            id: id,
                            title: $0.title,
                            isMinimized: $0.isMinimized,
                            cgWindowID: $0.cgWindowID,
                            inferredTitleBarStyle: nil
                        )
                    )
                }
            )
            let context = RuntimeAppContext(
                appID: appID,
                runningApp: app,
                windowsByID: windowContexts
            )
            rows.append((candidate, context))
        }

        rows.sort { lhs, rhs in
            if lhs.candidate.lastActiveAt == rhs.candidate.lastActiveAt {
                return lhs.candidate.displayName.localizedCaseInsensitiveCompare(
                    rhs.candidate.displayName
                ) == .orderedAscending
            }
            return lhs.candidate.lastActiveAt > rhs.candidate.lastActiveAt
        }

        var contextsByID: [String: RuntimeAppContext] = [:]
        for row in rows {
            if contextsByID[row.context.appID] != nil {
                RuntimeLog.info("Snapshot", "duplicate appID fallback overwrite=\(row.context.appID)")
            }
            contextsByID[row.context.appID] = row.context
        }

        return RuntimeSnapshot(
            apps: rows.map(\.candidate),
            contextsByID: contextsByID
        )
    }

    static func assembleSnapshotRowsForTesting(
        apps: [SnapshotAssemblyApp],
        windowsByPID: [pid_t: [SnapshotAssemblyWindow]],
        rankByPID: [pid_t: Int],
        hideMinimizedAppsFromAppLayer: Bool,
        now: TimeInterval
    ) -> [SnapshotAssemblyRow] {
        func baseAppID(for app: SnapshotAssemblyApp) -> String {
            app.bundleIdentifier ?? "pid:\(app.pid)"
        }

        func score(for app: SnapshotAssemblyApp) -> Int {
            let windows = windowsByPID[app.pid] ?? []
            let hasWindowsScore = windows.isEmpty ? 0 : 1_000_000
            let windowCountScore = min(windows.count, 9_999) * 100
            let rankScore = 10_000 - min(rankByPID[app.pid] ?? 10_000, 10_000)
            let launchScore = Int(app.launchDate?.timeIntervalSince1970 ?? 0) % 10_000
            return hasWindowsScore + windowCountScore + rankScore + launchScore
        }

        let groupedApps = Dictionary(grouping: apps, by: baseAppID(for:))
        let selectedApps = groupedApps.values.compactMap { group -> SnapshotAssemblyApp? in
            group.max { lhs, rhs in
                score(for: lhs) < score(for: rhs)
            }
        }

        let filteredApps = selectedApps.filter { app in
            let windows = windowsByPID[app.pid] ?? []
            return shouldIncludeAppInAppLayer(
                hasWindows: !windows.isEmpty,
                hasVisibleWindow: windows.contains(where: { !$0.isMinimized }),
                hideMinimizedAppsFromAppLayer: hideMinimizedAppsFromAppLayer
            )
        }

        var rows: [SnapshotAssemblyRow] = []
        rows.reserveCapacity(filteredApps.count)

        for (index, app) in filteredApps.enumerated() {
            let appID = baseAppID(for: app)
            let displayName = app.localizedName ?? appID
            let windows = windowsByPID[app.pid] ?? []
            let rank = rankByPID[app.pid] ?? (10_000 + index)
            let candidate = AppSwitchCandidate(
                id: appID,
                displayName: displayName,
                groupID: groupID(for: app.bundleIdentifier, fallbackName: displayName),
                lastActiveAt: now - Double(rank),
                windows: windows.enumerated().map { entryIndex, entry in
                    WindowCandidate(
                        id: entry.windowID,
                        title: entry.title,
                        isMinimized: entry.isMinimized,
                        lastActiveAt: now - Double(entryIndex)
                    )
                }
            )
            rows.append(SnapshotAssemblyRow(pid: app.pid, candidate: candidate))
        }

        rows.sort { lhs, rhs in
            if lhs.candidate.lastActiveAt == rhs.candidate.lastActiveAt {
                return lhs.candidate.displayName.localizedCaseInsensitiveCompare(
                    rhs.candidate.displayName
                ) == .orderedAscending
            }
            return lhs.candidate.lastActiveAt > rhs.candidate.lastActiveAt
        }
        return rows
    }

    func homeAppSummaries() -> [RuntimeHomeAppSummary] {
        if let uiTestRuntimeDataset = Self.uiTestRuntimeDataset() {
            return uiTestRuntimeDataset.summaries
        }
        let runningApps = filteredRunningApplications()
        guard !runningApps.isEmpty else { return [] }

        let rankByPID = collectAppRankByPID(for: runningApps)
        let windowStatsByPID = collectAXWindowStats(for: runningApps)
        let windowCountByPID = Dictionary(
            uniqueKeysWithValues: windowStatsByPID.map { ($0.key, $0.value.windowCount) }
        )
        let selectedApps = selectPrimaryApps(
            from: runningApps,
            windowCountByPID: windowCountByPID,
            rankByPID: rankByPID
        )
        let hideMinimizedAppsFromAppLayer =
            SwitcherBehaviorPreferencesStore.loadHideMinimizedAppsFromAppLayer()
        let appLayerCandidates = filterAppsForAppLayer(
            selectedApps,
            windowStatsByPID: windowStatsByPID,
            hideMinimizedAppsFromAppLayer: hideMinimizedAppsFromAppLayer
        )
        guard !appLayerCandidates.isEmpty else { return [] }

        var summaries: [RuntimeHomeAppSummary] = []
        summaries.reserveCapacity(appLayerCandidates.count)
        for (index, app) in appLayerCandidates.enumerated() {
            let pid = app.processIdentifier
            let appID = Self.baseAppID(for: app)
            let displayName = app.localizedName ?? appID
            let rank = rankByPID[pid] ?? (10_000 + index)
            summaries.append(
                RuntimeHomeAppSummary(
                    appID: appID,
                    displayName: displayName,
                    groupID: Self.groupID(for: app.bundleIdentifier, fallbackName: displayName),
                    lastActiveAt: Self.stableLastActiveValue(forRank: rank),
                    windowCount: windowStatsByPID[pid]?.windowCount ?? 0,
                    pid: pid
                )
            )
        }

        summaries.sort { lhs, rhs in
            if lhs.lastActiveAt == rhs.lastActiveAt {
                return lhs.displayName.localizedCaseInsensitiveCompare(
                    rhs.displayName
                ) == .orderedAscending
            }
            return lhs.lastActiveAt > rhs.lastActiveAt
        }
        return summaries
    }

    func homeAppSnapshot(for appID: String) -> RuntimeHomeAppSnapshot? {
        if let uiTestRuntimeDataset = Self.uiTestRuntimeDataset() {
            return uiTestRuntimeDataset.snapshotsByAppID[appID]
        }
        let runningApps = filteredRunningApplications()
        let matchingApps = runningApps.filter { Self.baseAppID(for: $0) == appID }
        guard !matchingApps.isEmpty else { return nil }

        let rankByPID = collectAppRankByPID(for: runningApps)
        let cgWindowsByPID = collectCGWindowsByPID()
        let windowsByPID = collectAXWindowData(for: matchingApps, cgWindowsByPID: cgWindowsByPID)
        let windowCountByPID = Dictionary(
            uniqueKeysWithValues: windowsByPID.map { ($0.key, $0.value.count) }
        )
        let sortedApps = matchingApps.sorted { lhs, rhs in
            score(
                for: lhs,
                windowCountByPID: windowCountByPID,
                rankByPID: rankByPID
            ) > score(
                for: rhs,
                windowCountByPID: windowCountByPID,
                rankByPID: rankByPID
            )
        }
        guard let app = sortedApps.first else { return nil }

        let windows = windowsByPID[app.processIdentifier] ?? []
        let hideMinimizedAppsFromAppLayer =
            SwitcherBehaviorPreferencesStore.loadHideMinimizedAppsFromAppLayer()
        if hideMinimizedAppsFromAppLayer && !windows.isEmpty && !windows.contains(where: { !$0.isMinimized }) {
            return nil
        }

        let now = Date.timeIntervalSinceReferenceDate
        let displayName = app.localizedName ?? appID
        let rank = rankByPID[app.processIdentifier] ?? 10_000
        let windowCandidates = windows.enumerated().map { entryIndex, entry in
            WindowCandidate(
                id: entry.windowID,
                title: entry.title,
                isMinimized: entry.isMinimized,
                lastActiveAt: now - Double(entryIndex)
            )
        }
        let candidate = AppSwitchCandidate(
            id: appID,
            displayName: displayName,
            groupID: Self.groupID(for: app.bundleIdentifier, fallbackName: displayName),
            lastActiveAt: now - Double(rank),
            windows: windowCandidates
        )
        let windowContexts = Dictionary(
            uniqueKeysWithValues: windows.map {
                let id = $0.windowID
                return (
                    id,
                    RuntimeWindowContext(
                        id: id,
                        title: $0.title,
                        isMinimized: $0.isMinimized,
                        cgWindowID: $0.cgWindowID,
                        inferredTitleBarStyle: nil
                    )
                )
            }
        )
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: app,
            windowsByID: windowContexts
        )
        let summary = RuntimeHomeAppSummary(
            appID: appID,
            displayName: displayName,
            groupID: Self.groupID(for: app.bundleIdentifier, fallbackName: displayName),
            lastActiveAt: Self.stableLastActiveValue(forRank: rank),
            windowCount: windows.count,
            pid: app.processIdentifier
        )
        return RuntimeHomeAppSnapshot(
            summary: summary,
            candidate: candidate,
            context: context
        )
    }

    func homeAppSummary(for appID: String) -> RuntimeHomeAppSummary? {
        if let uiTestRuntimeDataset = Self.uiTestRuntimeDataset() {
            return uiTestRuntimeDataset.summaries.first(where: { $0.appID == appID })
        }
        let runningApps = filteredRunningApplications()
        let matchingApps = runningApps.filter { Self.baseAppID(for: $0) == appID }
        guard !matchingApps.isEmpty else { return nil }

        let rankByPID = collectAppRankByPID(for: runningApps)
        let windowStatsByPID = collectAXWindowStats(for: matchingApps)
        let windowCountByPID = Dictionary(
            uniqueKeysWithValues: windowStatsByPID.map { ($0.key, $0.value.windowCount) }
        )
        let sortedApps = matchingApps.sorted { lhs, rhs in
            score(
                for: lhs,
                windowCountByPID: windowCountByPID,
                rankByPID: rankByPID
            ) > score(
                for: rhs,
                windowCountByPID: windowCountByPID,
                rankByPID: rankByPID
            )
        }
        guard let app = sortedApps.first else { return nil }

        if
            SwitcherBehaviorPreferencesStore.loadHideMinimizedAppsFromAppLayer(),
            let stats = windowStatsByPID[app.processIdentifier],
            stats.windowCount > 0,
            !stats.hasVisibleWindow
        {
            return nil
        }

        let displayName = app.localizedName ?? appID
        let rank = rankByPID[app.processIdentifier] ?? 10_000
        return RuntimeHomeAppSummary(
            appID: appID,
            displayName: displayName,
            groupID: Self.groupID(for: app.bundleIdentifier, fallbackName: displayName),
            lastActiveAt: Self.stableLastActiveValue(forRank: rank),
            windowCount: windowStatsByPID[app.processIdentifier]?.windowCount ?? 0,
            pid: app.processIdentifier
        )
    }

    private func filteredRunningApplications() -> [NSRunningApplication] {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let includeCurrentProcessInAppLayer = AppVisibilityPreferencesStore.loadShowInCommandTab()
        return NSWorkspace.shared.runningApplications.filter {
            Self.shouldIncludeRunningApplication(
                activationPolicy: $0.activationPolicy,
                isTerminated: $0.isTerminated,
                pid: $0.processIdentifier,
                currentPID: currentPID,
                includeCurrentProcessInAppLayer: includeCurrentProcessInAppLayer
            )
        }
    }

    static func shouldIncludeRunningApplication(
        activationPolicy: NSApplication.ActivationPolicy,
        isTerminated: Bool,
        pid: pid_t,
        currentPID: pid_t,
        includeCurrentProcessInAppLayer: Bool
    ) -> Bool {
        activationPolicy == .regular
            && !isTerminated
            && (includeCurrentProcessInAppLayer || pid != currentPID)
    }

    private func filterAppsForAppLayer(
        _ apps: [NSRunningApplication],
        windowsByPID: [pid_t: [WindowListEntry]],
        hideMinimizedAppsFromAppLayer: Bool
    ) -> [NSRunningApplication] {
        guard hideMinimizedAppsFromAppLayer else { return apps }

        return apps.filter { app in
            let windows = windowsByPID[app.processIdentifier] ?? []
            let hasVisibleWindow = windows.contains(where: { !$0.isMinimized })
            guard Self.shouldIncludeAppInAppLayer(
                hasWindows: !windows.isEmpty,
                hasVisibleWindow: hasVisibleWindow,
                hideMinimizedAppsFromAppLayer: hideMinimizedAppsFromAppLayer
            ) else {
                let appName = app.localizedName ?? app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
                RuntimeLog.info("Snapshot", "skip minimized-only app=\(appName) pid=\(app.processIdentifier)")
                return false
            }
            return true
        }
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

    private func filterAppsForAppLayer(
        _ apps: [NSRunningApplication],
        windowStatsByPID: [pid_t: AXWindowStats],
        hideMinimizedAppsFromAppLayer: Bool
    ) -> [NSRunningApplication] {
        guard hideMinimizedAppsFromAppLayer else { return apps }

        return apps.filter { app in
            guard let stats = windowStatsByPID[app.processIdentifier] else { return true }
            guard Self.shouldIncludeAppInAppLayer(
                hasWindows: stats.windowCount > 0,
                hasVisibleWindow: stats.hasVisibleWindow,
                hideMinimizedAppsFromAppLayer: hideMinimizedAppsFromAppLayer
            ) else {
                let appName = app.localizedName ?? app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
                RuntimeLog.info("Snapshot", "skip minimized-only app=\(appName) pid=\(app.processIdentifier)")
                return false
            }
            return true
        }
    }

    private func collectWindowData(for runningApps: [NSRunningApplication]) -> (
        windowsByPID: [pid_t: [WindowListEntry]],
        rankByPID: [pid_t: Int]
    ) {
        let cgWindowsByPID = collectCGWindowsByPID()
        // Keep a single source of truth for window counting and selection: AX window list.
        return (
            windowsByPID: collectAXWindowData(for: runningApps, cgWindowsByPID: cgWindowsByPID),
            rankByPID: collectAppRankByPID(for: runningApps)
        )
    }

    private func collectAXWindowData(
        for runningApps: [NSRunningApplication],
        cgWindowsByPID: [pid_t: [CGWindowEntry]]
    ) -> [pid_t: [WindowListEntry]] {
        guard AccessibilityPermissionChecker.isTrusted() else {
            RuntimeLog.info("AX", "not trusted; all app windows will be reported as 0")
            return [:]
        }

        var windowsByPID: [pid_t: [WindowListEntry]] = [:]
        for app in runningApps {
            let appName = app.localizedName ?? app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
            let windows = AXWindowInspector.windows(for: app)
            let cgWindows = cgWindowsByPID[app.processIdentifier] ?? []
            var matchedCGWindowIndexes: Set<Int> = []
            RuntimeLog.info("AX", "\(appName) rawWindows=\(windows.count)")
            guard !windows.isEmpty else { continue }

            let entries = windows.enumerated().compactMap { index, window -> WindowListEntry? in
                guard AXWindowInspector.isSwitchable(window) else {
                    let role = AXWindowInspector.role(for: window) ?? "unknown"
                    RuntimeLog.info("AX", "\(appName) skip[\(index)] role=\(role)")
                    return nil
                }
                let windowID = AXWindowInspector.makeWindowID(
                    pid: app.processIdentifier,
                    index: index
                )
                let titleFromAX = AXWindowInspector.title(for: window)
                let title = titleFromAX ?? {
                    RuntimeLog.info("AX", "\(appName) untitled[\(index)] use fallback")
                    return AXWindowInspector.fallbackTitle(index: index)
                }()
                let cgWindowID = resolveCGWindowID(
                    preferredTitle: titleFromAX,
                    fallbackIndex: index,
                    cgWindows: cgWindows,
                    usedIndexes: &matchedCGWindowIndexes
                )
                return WindowListEntry(
                    windowID: windowID,
                    title: title,
                    isMinimized: AXWindowInspector.isMinimized(window),
                    cgWindowID: cgWindowID
                )
            }

            guard !entries.isEmpty else { continue }
            RuntimeLog.info("AX", "\(appName) switchableWindows=\(entries.count)")
            windowsByPID[app.processIdentifier] = entries
        }
        return windowsByPID
    }

    private func collectAXWindowStats(for runningApps: [NSRunningApplication]) -> [pid_t: AXWindowStats] {
        guard AccessibilityPermissionChecker.isTrusted() else {
            RuntimeLog.info("AX", "not trusted; all app windows will be reported as 0")
            return [:]
        }

        var statsByPID: [pid_t: AXWindowStats] = [:]
        for app in runningApps {
            let windows = AXWindowInspector.windows(for: app)
            guard !windows.isEmpty else { continue }

            var count = 0
            var hasVisibleWindow = false
            for window in windows {
                guard AXWindowInspector.isSwitchable(window) else { continue }
                count += 1
                if !AXWindowInspector.isMinimized(window) {
                    hasVisibleWindow = true
                }
            }
            guard count > 0 else { continue }
            statsByPID[app.processIdentifier] = AXWindowStats(
                windowCount: count,
                hasVisibleWindow: hasVisibleWindow
            )
        }
        return statsByPID
    }

    private func collectCGWindowsByPID() -> [pid_t: [CGWindowEntry]] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard
            let rawList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else {
            return [:]
        }

        var windowsByPID: [pid_t: [CGWindowEntry]] = [:]
        for item in rawList {
            guard let ownerPID = item[kCGWindowOwnerPID as String] as? pid_t else { continue }
            guard let layer = item[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let windowNumber = item[kCGWindowNumber as String] as? NSNumber else { continue }
            let title = (item[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            windowsByPID[ownerPID, default: []].append(
                CGWindowEntry(
                    id: CGWindowID(windowNumber.uint32Value),
                    title: title
                )
            )
        }
        return windowsByPID
    }

    private func resolveCGWindowID(
        preferredTitle: String?,
        fallbackIndex: Int,
        cgWindows: [CGWindowEntry],
        usedIndexes: inout Set<Int>
    ) -> CGWindowID? {
        if let preferredTitle, !preferredTitle.isEmpty {
            if let exactMatchIndex = cgWindows.indices.first(where: { index in
                !usedIndexes.contains(index) && cgWindows[index].title == preferredTitle
            }) {
                usedIndexes.insert(exactMatchIndex)
                return cgWindows[exactMatchIndex].id
            }
            if let insensitiveMatchIndex = cgWindows.indices.first(where: { index in
                guard !usedIndexes.contains(index), let title = cgWindows[index].title else { return false }
                return title.caseInsensitiveCompare(preferredTitle) == .orderedSame
            }) {
                usedIndexes.insert(insensitiveMatchIndex)
                return cgWindows[insensitiveMatchIndex].id
            }
        }

        if cgWindows.indices.contains(fallbackIndex), !usedIndexes.contains(fallbackIndex) {
            usedIndexes.insert(fallbackIndex)
            return cgWindows[fallbackIndex].id
        }

        guard let firstUnmatchedIndex = cgWindows.indices.first(where: { !usedIndexes.contains($0) }) else {
            return nil
        }
        usedIndexes.insert(firstUnmatchedIndex)
        return cgWindows[firstUnmatchedIndex].id
    }

    private func collectAppRankByPID(for runningApps: [NSRunningApplication]) -> [pid_t: Int] {
        let fallbackRankByPID = collectWindowStackRankByPID()
        return SystemAppMRUTracker.shared.rankByPID(
            for: runningApps,
            fallbackRankByPID: fallbackRankByPID
        )
    }

    private func collectWindowStackRankByPID() -> [pid_t: Int] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
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

    private static func groupID(for bundleIdentifier: String?, fallbackName: String) -> String {
        guard let bundleIdentifier else {
            return String(fallbackName.prefix(1)).lowercased()
        }

        let components = bundleIdentifier.split(separator: ".")
        if components.count >= 2 {
            return String(components[1])
        }
        if let first = components.first {
            return String(first)
        }
        return "apps"
    }

    private func selectPrimaryApps(
        from runningApps: [NSRunningApplication],
        windowsByPID: [pid_t: [WindowListEntry]],
        rankByPID: [pid_t: Int]
    ) -> [NSRunningApplication] {
        let grouped = Dictionary(grouping: runningApps, by: Self.baseAppID(for:))
        var selected: [NSRunningApplication] = []
        selected.reserveCapacity(grouped.count)

        for (baseAppID, apps) in grouped {
            guard apps.count > 1 else {
                if let app = apps.first {
                    selected.append(app)
                }
                continue
            }

            let sorted = apps.sorted { lhs, rhs in
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

            guard let primary = sorted.first else { continue }
            selected.append(primary)

            let droppedPIDs = sorted.dropFirst().map(\.processIdentifier)
            RuntimeLog.info(
                "Snapshot",
                "dedupe baseAppID=\(baseAppID) keepPID=\(primary.processIdentifier) dropPIDs=\(droppedPIDs)"
            )
        }

        return selected
    }

    private func selectPrimaryApps(
        from runningApps: [NSRunningApplication],
        windowCountByPID: [pid_t: Int],
        rankByPID: [pid_t: Int]
    ) -> [NSRunningApplication] {
        let grouped = Dictionary(grouping: runningApps, by: Self.baseAppID(for:))
        var selected: [NSRunningApplication] = []
        selected.reserveCapacity(grouped.count)

        for (baseAppID, apps) in grouped {
            guard apps.count > 1 else {
                if let app = apps.first {
                    selected.append(app)
                }
                continue
            }

            let sorted = apps.sorted { lhs, rhs in
                score(
                    for: lhs,
                    windowCountByPID: windowCountByPID,
                    rankByPID: rankByPID
                ) > score(
                    for: rhs,
                    windowCountByPID: windowCountByPID,
                    rankByPID: rankByPID
                )
            }

            guard let primary = sorted.first else { continue }
            selected.append(primary)

            let droppedPIDs = sorted.dropFirst().map(\.processIdentifier)
            RuntimeLog.info(
                "Snapshot",
                "dedupe baseAppID=\(baseAppID) keepPID=\(primary.processIdentifier) dropPIDs=\(droppedPIDs)"
            )
        }

        return selected
    }

    private func score(
        for app: NSRunningApplication,
        windowsByPID: [pid_t: [WindowListEntry]],
        rankByPID: [pid_t: Int]
    ) -> Int {
        let pid = app.processIdentifier
        let windowCount = windowsByPID[pid]?.count ?? 0
        let hasWindowsScore = windowCount > 0 ? 1_000_000 : 0
        let windowCountScore = min(windowCount, 9_999) * 100
        let rankScore = 10_000 - min(rankByPID[pid] ?? 10_000, 10_000)
        let launchScore = Int(app.launchDate?.timeIntervalSince1970 ?? 0) % 10_000
        return hasWindowsScore + windowCountScore + rankScore + launchScore
    }

    private func score(
        for app: NSRunningApplication,
        windowCountByPID: [pid_t: Int],
        rankByPID: [pid_t: Int]
    ) -> Int {
        let pid = app.processIdentifier
        let windowCount = windowCountByPID[pid] ?? 0
        let hasWindowsScore = windowCount > 0 ? 1_000_000 : 0
        let windowCountScore = min(windowCount, 9_999) * 100
        let rankScore = 10_000 - min(rankByPID[pid] ?? 10_000, 10_000)
        let launchScore = Int(app.launchDate?.timeIntervalSince1970 ?? 0) % 10_000
        return hasWindowsScore + windowCountScore + rankScore + launchScore
    }

    private static func baseAppID(for app: NSRunningApplication) -> String {
        let pid = app.processIdentifier
        return app.bundleIdentifier ?? "pid:\(pid)"
    }

    private static func stableLastActiveValue(forRank rank: Int) -> TimeInterval {
        -Double(max(rank, 0))
    }
}

@MainActor
final class RuntimeActivator {
    var activateCurrentAppIfNeededOverride: ((NSRunningApplication) -> Bool)?
    var requestActivationOverride: ((NSRunningApplication, ((NSRunningApplication) -> Void)?) -> Void)?
    var focusWindowOverride: ((String, String, Bool, NSRunningApplication) -> Void)?

    func activate(target: ActivationTarget, contextsByID: [String: RuntimeAppContext]) {
        switch target {
        case .app(let appID):
            activateApp(appID: appID, contextsByID: contextsByID)
        case .window(let appID, let windowID, let restoreIfMinimized):
            activateWindow(
                appID: appID,
                windowID: windowID,
                restoreIfMinimized: restoreIfMinimized,
                contextsByID: contextsByID
            )
        }
    }

    private func activateApp(appID: String, contextsByID: [String: RuntimeAppContext]) {
        guard let context = contextsByID[appID] else { return }
        if activateCurrentAppIfNeeded(context.runningApp) {
            return
        }
        requestActivation(of: context.runningApp)
    }

    private func activateWindow(
        appID: String,
        windowID: String,
        restoreIfMinimized: Bool,
        contextsByID: [String: RuntimeAppContext]
    ) {
        guard let context = contextsByID[appID] else { return }
        if activateCurrentAppIfNeeded(context.runningApp) {
            return
        }
        guard let windowContext = context.windowsByID[windowID] else {
            requestActivation(of: context.runningApp)
            return
        }
        requestActivation(of: context.runningApp) { [weak self] activatedApp in
            guard let self else { return }
            self.focusWindow(
                withID: windowID,
                withTitle: windowContext.title,
                restoreIfMinimized: restoreIfMinimized || windowContext.isMinimized,
                in: activatedApp
            )
        }
    }

    private func focusWindow(
        withID targetWindowID: String,
        withTitle targetTitle: String,
        restoreIfMinimized: Bool,
        in app: NSRunningApplication
    ) {
        if let focusWindowOverride {
            focusWindowOverride(targetWindowID, targetTitle, restoreIfMinimized, app)
            return
        }
        let windows = AXWindowInspector.windows(for: app)
        guard !windows.isEmpty else { return }

        if
            let index = AXWindowInspector.windowIndex(
                from: targetWindowID,
                expectedPID: app.processIdentifier
            ),
            windows.indices.contains(index)
        {
            focus(
                window: windows[index],
                restoreIfMinimized: restoreIfMinimized
            )
            return
        }

        for window in windows {
            guard let title = AXWindowInspector.title(for: window), title == targetTitle else { continue }
            focus(window: window, restoreIfMinimized: restoreIfMinimized)
            return
        }
    }

    private func requestActivation(
        of app: NSRunningApplication,
        completion: ((NSRunningApplication) -> Void)? = nil
    ) {
        if let requestActivationOverride {
            requestActivationOverride(app, completion)
            return
        }
        guard let bundleURL = app.bundleURL else {
            _ = app.activate()
            completeActivation(app, completion: completion)
            return
        }

        // On modern macOS, NSWorkspace participates in cooperative activation
        // and is more reliable than asking the target process to activate itself.
        NSWorkspace.shared.openApplication(
            at: bundleURL,
            configuration: Self.makeOpenConfiguration()
        ) { openedApp, error in
            if let error {
                RuntimeLog.info(
                    "Activation",
                    "openApplication failed pid=\(app.processIdentifier) bundle=\(app.bundleIdentifier ?? "nil") error=\(error.localizedDescription)"
                )
                _ = app.activate()
                self.completeActivation(app, completion: completion)
                return
            }

            self.completeActivation(openedApp ?? app, completion: completion)
        }
    }

    private func completeActivation(
        _ app: NSRunningApplication,
        completion: ((NSRunningApplication) -> Void)?
    ) {
        guard let completion else { return }
        Task { @MainActor in
            completion(app)
        }
    }

    nonisolated static func makeOpenConfiguration() -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        return configuration
    }

    @discardableResult
    private func activateCurrentAppIfNeeded(_ app: NSRunningApplication) -> Bool {
        if let activateCurrentAppIfNeededOverride {
            return activateCurrentAppIfNeededOverride(app)
        }
        guard app.processIdentifier == ProcessInfo.processInfo.processIdentifier else {
            return false
        }
        AppWindowCoordinator.activateMainWindowOrOpenHomeScene()
        return true
    }

    private func focus(window: AXUIElement, restoreIfMinimized: Bool) {
        if restoreIfMinimized {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

}

private enum AXWindowInspector {
    private static let windowIDPrefix = "ax"

    static func windows(for app: NSRunningApplication) -> [AXUIElement] {
        guard AccessibilityPermissionChecker.isTrusted() else { return [] }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
                == .success,
            let windows = windowsValue as? [AXUIElement]
        else {
            return []
        }
        return windows
    }

    static func makeWindowID(pid: pid_t, index: Int) -> String {
        "\(windowIDPrefix):\(pid):\(index)"
    }

    static func windowIndex(from windowID: String, expectedPID: pid_t) -> Int? {
        let parts = windowID.split(separator: ":")
        guard parts.count == 3 else { return nil }
        guard parts[0] == Substring(windowIDPrefix) else { return nil }
        guard let pid = pid_t(parts[1]), pid == expectedPID else { return nil }
        return Int(parts[2])
    }

    static func fallbackTitle(index: Int) -> String {
        "Window #\(index + 1)"
    }

    static func title(for window: AXUIElement) -> String? {
        var titleValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
                == .success,
            let title = (titleValue as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !title.isEmpty
        else {
            return nil
        }
        return title
    }

    static func isSwitchable(_ window: AXUIElement) -> Bool {
        guard let role = role(for: window) else { return true }
        return role == kAXWindowRole as String
    }

    static func role(for window: AXUIElement) -> String? {
        var roleValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleValue)
                == .success,
            let role = roleValue as? String
        else {
            return nil
        }
        return role
    }

    static func isMinimized(_ window: AXUIElement) -> Bool {
        var minimizedValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue)
                == .success,
            let number = minimizedValue as? NSNumber
        else {
            return false
        }
        return number.boolValue
    }
}

enum RuntimeWindowPreviewProvider {
    private struct LiveCGWindowEntry {
        let id: CGWindowID
        let title: String?
    }

    private struct StripStats {
        let meanLuminance: Double
        let stdLuminance: Double
        let meanSaturation: Double
        let sampleCount: Int

        var uniformityScore: Double {
            stdLuminance + meanSaturation * 0.6
        }
    }

    private static var hasLoggedScreenCapturePermissionWarning = false
    private static let shareableContentLookupTimeout: TimeInterval = 1.0
    private static let screenshotCaptureTimeout: TimeInterval = 1.0
    private static let maxPreviewCaptureDimension: CGFloat = 1_200

    static func captureWindowPreview(
        preferredWindowID: CGWindowID?,
        ownerPID: pid_t,
        preferredTitle: String?,
        inferTitleBarStyle: Bool
    ) -> (image: NSImage, resolvedWindowID: CGWindowID, titleBarStyle: WindowTitleBarStyleGuess?)? {
        guard ScreenCapturePermissionChecker.hasScreenCapturePermission else {
            if !hasLoggedScreenCapturePermissionWarning {
                RuntimeLog.info("Preview", "screen recording permission missing; window preview unavailable")
                hasLoggedScreenCapturePermissionWarning = true
            }
            return nil
        }

        let candidateIDs = candidateWindowIDs(
            preferredWindowID: preferredWindowID,
            ownerPID: ownerPID,
            preferredTitle: preferredTitle
        )
        guard !candidateIDs.isEmpty else {
            RuntimeLog.info(
                "Preview",
                "no candidate windows pid=\(ownerPID) preferredID=\(preferredWindowID.map(String.init) ?? "nil") title=\(preferredTitle ?? "<empty>")"
            )
            return nil
        }

        let shareableWindowsByID = fetchShareableWindowsByID()
        for candidateID in candidateIDs {
            guard let shareableWindow = shareableWindowsByID[candidateID] else { continue }
            guard let cgImage = captureWindow(shareableWindow: shareableWindow) else { continue }
            let titleBarStyle = inferTitleBarStyle ? estimateTitleBarStyle(from: cgImage) : nil
            let image = NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )
            RuntimeLog.info(
                "Preview",
                "capture success pid=\(ownerPID) windowID=\(candidateID) candidates=\(candidateIDs.count) titleBarStyle=\(titleBarStyle?.rawValue ?? "nil")"
            )
            return (image: image, resolvedWindowID: candidateID, titleBarStyle: titleBarStyle)
        }

        RuntimeLog.info(
            "Preview",
            "capture failed pid=\(ownerPID) preferredID=\(preferredWindowID.map(String.init) ?? "nil") title=\(preferredTitle ?? "<empty>") candidates=\(candidateIDs.map(String.init).joined(separator: ","))"
        )
        return nil
    }

    private static func candidateWindowIDs(
        preferredWindowID: CGWindowID?,
        ownerPID: pid_t,
        preferredTitle: String?
    ) -> [CGWindowID] {
        let liveWindows = collectLiveCGWindows(ownerPID: ownerPID)
        var candidateIDs: [CGWindowID] = []
        var seen: Set<CGWindowID> = []

        func appendCandidate(_ id: CGWindowID) {
            guard !seen.contains(id) else { return }
            seen.insert(id)
            candidateIDs.append(id)
        }

        if let preferredWindowID {
            appendCandidate(preferredWindowID)
        }

        let trimmedTitle = preferredTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedTitle, !trimmedTitle.isEmpty {
            for window in liveWindows {
                guard let title = window.title else { continue }
                if title == trimmedTitle {
                    appendCandidate(window.id)
                }
            }
            for window in liveWindows {
                guard let title = window.title else { continue }
                if title.caseInsensitiveCompare(trimmedTitle) == .orderedSame {
                    appendCandidate(window.id)
                }
            }
        }

        for window in liveWindows {
            appendCandidate(window.id)
        }
        return candidateIDs
    }

    private static func collectLiveCGWindows(ownerPID: pid_t) -> [LiveCGWindowEntry] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard
            let rawList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else {
            return []
        }

        var windows: [LiveCGWindowEntry] = []
        windows.reserveCapacity(rawList.count)
        for item in rawList {
            guard let pid = item[kCGWindowOwnerPID as String] as? pid_t, pid == ownerPID else { continue }
            guard let layer = item[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let windowNumber = item[kCGWindowNumber as String] as? NSNumber else { continue }
            let title = (item[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            windows.append(
                LiveCGWindowEntry(
                    id: CGWindowID(windowNumber.uint32Value),
                    title: title
                )
            )
        }
        return windows
    }

    private static func fetchShareableWindowsByID() -> [CGWindowID: SCWindow] {
        var shareableContent: SCShareableContent?
        var capturedError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, error in
            shareableContent = content
            capturedError = error
            semaphore.signal()
        }

        let timeoutDate = DispatchTime.now() + shareableContentLookupTimeout
        guard semaphore.wait(timeout: timeoutDate) == .success else {
            RuntimeLog.info("Preview", "shareable-content lookup timed out")
            return [:]
        }
        if let capturedError {
            RuntimeLog.info("Preview", "shareable-content lookup failed error=\(capturedError.localizedDescription)")
            return [:]
        }
        guard let shareableContent else { return [:] }

        var windowsByID: [CGWindowID: SCWindow] = [:]
        windowsByID.reserveCapacity(shareableContent.windows.count)
        for window in shareableContent.windows {
            windowsByID[window.windowID] = window
        }
        return windowsByID
    }

    private static func captureWindow(shareableWindow: SCWindow) -> CGImage? {
        let filter = SCContentFilter(desktopIndependentWindow: shareableWindow)
        let configuration = SCStreamConfiguration()
        let sourceWidth = max(1, shareableWindow.frame.width)
        let sourceHeight = max(1, shareableWindow.frame.height)
        let scale = min(1, maxPreviewCaptureDimension / max(sourceWidth, sourceHeight))
        let width = max(1, Int(ceil(sourceWidth * scale)))
        let height = max(1, Int(ceil(sourceHeight * scale)))
        configuration.width = width
        configuration.height = height
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true

        var capturedImage: CGImage?
        var capturedError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
            capturedImage = image
            capturedError = error
            semaphore.signal()
        }

        let timeoutDate = DispatchTime.now() + screenshotCaptureTimeout
        guard semaphore.wait(timeout: timeoutDate) == .success else {
            RuntimeLog.info("Preview", "screenshot capture timed out windowID=\(shareableWindow.windowID)")
            return nil
        }
        if let capturedError {
            RuntimeLog.info(
                "Preview",
                "screenshot capture failed windowID=\(shareableWindow.windowID) error=\(capturedError.localizedDescription)"
            )
        }
        return capturedImage
    }

    private static func estimateTitleBarStyle(from image: CGImage) -> WindowTitleBarStyleGuess? {
        let sourceWidth = image.width
        let sourceHeight = image.height
        guard sourceWidth >= 24, sourceHeight >= 24 else { return nil }

        let targetWidth = min(sourceWidth, 720)
        let scale = Double(targetWidth) / Double(sourceWidth)
        let targetHeight = max(
            1,
            Int((Double(sourceHeight) * scale).rounded(.toNearestOrAwayFromZero))
        )
        let bytesPerPixel = 4
        let bytesPerRow = targetWidth * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: targetHeight * bytesPerRow)

        let didRender = pixels.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return false }
            guard
                let context = CGContext(
                    data: baseAddress,
                    width: targetWidth,
                    height: targetHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else {
                return false
            }
            context.interpolationQuality = .low
            context.draw(
                image,
                in: CGRect(
                    x: 0,
                    y: 0,
                    width: targetWidth,
                    height: targetHeight
                )
            )
            return true
        }
        guard didRender else { return nil }

        let bandHeight = max(8, min(48, Int(Double(targetHeight) * 0.11)))
        let horizontalInset = min(
            max(4, Int(Double(targetWidth) * 0.10)),
            max(0, targetWidth / 2 - 1)
        )
        let xStart = horizontalInset
        let xEnd = targetWidth - horizontalInset
        guard xEnd > xStart else { return nil }

        let topStrip = analyzeStrip(
            pixels: pixels,
            bytesPerRow: bytesPerRow,
            yRange: (targetHeight - bandHeight)..<targetHeight,
            xRange: xStart..<xEnd
        )
        let bottomStrip = analyzeStrip(
            pixels: pixels,
            bytesPerRow: bytesPerRow,
            yRange: 0..<bandHeight,
            xRange: xStart..<xEnd
        )
        guard
            let strip = preferredStrip(top: topStrip, bottom: bottomStrip),
            strip.sampleCount >= 160
        else {
            return nil
        }
        guard strip.uniformityScore <= 0.30 else { return nil }

        if strip.meanLuminance <= 0.47 {
            return .dark
        }
        if strip.meanLuminance >= 0.60 {
            return .light
        }
        if strip.stdLuminance <= 0.10, strip.meanSaturation <= 0.17 {
            return strip.meanLuminance < 0.53 ? .dark : .light
        }
        return nil
    }

    private static func preferredStrip(
        top: StripStats?,
        bottom: StripStats?
    ) -> StripStats? {
        switch (top, bottom) {
        case (nil, nil):
            return nil
        case let (top?, nil):
            return top
        case let (nil, bottom?):
            return bottom
        case let (top?, bottom?):
            return top.uniformityScore <= bottom.uniformityScore ? top : bottom
        }
    }

    private static func analyzeStrip(
        pixels: [UInt8],
        bytesPerRow: Int,
        yRange: Range<Int>,
        xRange: Range<Int>
    ) -> StripStats? {
        var luminanceSum = 0.0
        var luminanceSquareSum = 0.0
        var saturationSum = 0.0
        var sampleCount = 0

        for y in yRange {
            let rowOffset = y * bytesPerRow
            for x in xRange {
                let base = rowOffset + x * 4
                let alpha = Double(pixels[base + 3]) / 255.0
                guard alpha >= 0.90 else { continue }

                let normalizer = max(alpha, 0.0001)
                let red = min(1.0, Double(pixels[base]) / 255.0 / normalizer)
                let green = min(1.0, Double(pixels[base + 1]) / 255.0 / normalizer)
                let blue = min(1.0, Double(pixels[base + 2]) / 255.0 / normalizer)
                let maxChannel = max(red, max(green, blue))
                let minChannel = min(red, min(green, blue))
                let saturation = maxChannel > 0 ? (maxChannel - minChannel) / maxChannel : 0
                let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue

                luminanceSum += luminance
                luminanceSquareSum += luminance * luminance
                saturationSum += saturation
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else { return nil }
        let meanLuminance = luminanceSum / Double(sampleCount)
        let variance = max(
            0,
            luminanceSquareSum / Double(sampleCount) - meanLuminance * meanLuminance
        )
        return StripStats(
            meanLuminance: meanLuminance,
            stdLuminance: sqrt(variance),
            meanSaturation: saturationSum / Double(sampleCount),
            sampleCount: sampleCount
        )
    }

    static func guessTitleBarStyleForTesting(from image: CGImage) -> WindowTitleBarStyleGuess? {
        estimateTitleBarStyle(from: image)
    }
}

enum ScreenCapturePermissionChecker {
    static var hasPermissionOverrideForTesting: (() -> Bool)?
    static var requestPermissionOverrideForTesting: (() -> Bool)?

    static var hasScreenCapturePermission: Bool {
        if let hasPermissionOverrideForTesting {
            return hasPermissionOverrideForTesting()
        }
        if let override = FlowTabTestLaunchOptions.screenCaptureTrustedOverride {
            return override
        }
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }

    @discardableResult
    static func requestScreenCapturePermission() -> Bool {
        if let requestPermissionOverrideForTesting {
            return requestPermissionOverrideForTesting()
        }
        if let override = FlowTabTestLaunchOptions.screenCaptureTrustedOverride {
            return override
        }
        if #available(macOS 10.15, *) {
            return CGRequestScreenCaptureAccess()
        }
        return true
    }
}

final class BoundedImageCache {
    private let storage = NSCache<NSString, NSImage>()

    init(countLimit: Int, totalCostLimit: Int) {
        storage.countLimit = countLimit
        storage.totalCostLimit = totalCostLimit
    }

    func image(forKey key: String) -> NSImage? {
        storage.object(forKey: key as NSString)
    }

    func insert(_ image: NSImage, forKey key: String) {
        storage.setObject(
            image,
            forKey: key as NSString,
            cost: image.estimatedByteCost
        )
    }

    func removeAll() {
        storage.removeAllObjects()
    }
}

private extension NSImage {
    var estimatedByteCost: Int {
        if let bitmap = representations.first(where: { $0.pixelsWide > 0 && $0.pixelsHigh > 0 }) {
            return bitmap.pixelsWide * bitmap.pixelsHigh * 4
        }
        let width = max(1, Int(ceil(size.width)))
        let height = max(1, Int(ceil(size.height)))
        return width * height * 4
    }
}

final class AppIconProvider {
    private let cache: BoundedImageCache
    private let applicationURLProvider: (String) -> URL?
    private let fileIconProvider: (String) -> NSImage
    private var missingAppIDs: Set<String> = []

    init(
        cache: BoundedImageCache = BoundedImageCache(
            countLimit: 256,
            totalCostLimit: 64 * 1_024 * 1_024
        ),
        applicationURLProvider: ((String) -> URL?)? = nil,
        fileIconProvider: ((String) -> NSImage)? = nil
    ) {
        self.cache = cache
        self.applicationURLProvider = applicationURLProvider
            ?? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        self.fileIconProvider = fileIconProvider
            ?? { NSWorkspace.shared.icon(forFile: $0) }
    }

    func icon(for app: AppSwitchCandidate, context: RuntimeAppContext?) -> NSImage? {
        if let cached = cache.image(forKey: app.id) {
            return cached
        }
        if missingAppIDs.contains(app.id) {
            return nil
        }

        if let runtimeIcon = context?.runningApp.icon {
            cache.insert(runtimeIcon, forKey: app.id)
            return runtimeIcon
        }

        guard let url = applicationURLProvider(app.id) else {
            missingAppIDs.insert(app.id)
            return nil
        }

        let icon = fileIconProvider(url.path)
        cache.insert(icon, forKey: app.id)
        return icon
    }
}
