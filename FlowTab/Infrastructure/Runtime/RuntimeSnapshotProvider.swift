import AppKit
import ApplicationServices
import Foundation
import FlowTabCore

final class RuntimeSnapshotProvider {
    struct WindowListEntry {
        let windowID: String
        let title: String
        let isMinimized: Bool
        let cgWindowID: CGWindowID?
        let axWindow: AXUIElement?
    }

    struct CGWindowEntry {
        let id: CGWindowID
        let title: String?
        let bounds: CGRect?
        let isOnscreen: Bool
        let alpha: Double
        let storeType: Int
    }

    struct AXWindowEntry {
        let index: Int
        let id: String
        let title: String
        let sourceTitle: String?
        let isMinimized: Bool
        let window: AXUIElement
        let frame: CGRect?
    }

    private struct WindowPairScore {
        let axIndex: Int
        let cgIndex: Int
        let score: Double
    }

    struct AXWindowStats {
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

    private static let cgMatchMinimumConfidence = 0.56
    private static let cgMatchAmbiguityDelta = 0.10
    private static let cgMatchStickyBonus = 0.18
    private static let cgMatchIndexWeight = 0.20

    private var lastCGWindowIDByAXWindowID: [String: CGWindowID] = [:]

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
        let appsGroupedByBaseID = groupedAppsByBaseID(runningApps)
        let selectedApps = selectPrimaryApps(
            from: runningApps,
            windowsByPID: windowData.windowsByPID,
            rankByPID: windowData.rankByPID
        )
        let mergedWindowsByPrimaryPID = Dictionary(uniqueKeysWithValues: selectedApps.map { app in
            let appGroup = appsGroupedByBaseID[Self.baseAppID(for: app)] ?? [app]
            return (
                app.processIdentifier,
                mergedWindowEntries(
                    for: appGroup,
                    windowsByPID: windowData.windowsByPID,
                    rankByPID: windowData.rankByPID
                )
            )
        })
        let hideMinimizedAppsFromAppLayer =
            SwitcherBehaviorPreferencesStore.loadHideMinimizedAppsFromAppLayer()
        let appLayerCandidates = filterAppsForAppLayer(
            selectedApps,
            windowsByPID: mergedWindowsByPrimaryPID,
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
            let appGroup = appsGroupedByBaseID[baseAppID] ?? [app]
            let appID = baseAppID
            let displayName = app.localizedName ?? baseAppID

            let windows = mergedWindowsByPrimaryPID[pid] ?? []
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

            let rank = preferredRankForAppGroup(
                appGroup,
                rankByPID: windowData.rankByPID,
                fallback: 10_000 + index
            )
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
                            inferredTitleBarStyle: nil,
                            axWindow: $0.axWindow
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
        var rows: [SnapshotAssemblyRow] = []
        rows.reserveCapacity(groupedApps.count)

        for group in groupedApps.values {
            guard let app = group.max(by: { lhs, rhs in
                score(for: lhs) < score(for: rhs)
            }) else {
                continue
            }
            let appID = baseAppID(for: app)
            let displayName = app.localizedName ?? appID
            let windows = group
                .sorted(by: { lhs, rhs in
                    score(for: lhs) > score(for: rhs)
                })
                .flatMap { groupApp in
                    windowsByPID[groupApp.pid] ?? []
                }
            guard shouldIncludeAppInAppLayer(
                hasWindows: !windows.isEmpty,
                hasVisibleWindow: windows.contains(where: { !$0.isMinimized }),
                hideMinimizedAppsFromAppLayer: hideMinimizedAppsFromAppLayer
            ) else {
                continue
            }
            let rank = group.compactMap { groupApp in
                rankByPID[groupApp.pid]
            }.min() ?? (10_000 + rows.count)
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

    func collectWindowData(for runningApps: [NSRunningApplication]) -> (
        windowsByPID: [pid_t: [WindowListEntry]],
        rankByPID: [pid_t: Int]
    ) {
        AXLiveWindowRegistry.shared.rebind(runningApps)
        let onScreenCGWindowsByPID = collectCGWindowsByPID()
        let allCGWindowsByPID = collectCGWindowsByPID(options: [.optionAll, .excludeDesktopElements])
        // Keep a single source of truth for window counting and selection: AX window list.
        return (
            windowsByPID: collectAXWindowData(
                for: runningApps,
                cgWindowsByPID: onScreenCGWindowsByPID,
                allCGWindowsByPID: allCGWindowsByPID
            ),
            rankByPID: collectAppRankByPID(for: runningApps)
        )
    }

    func collectAXWindowData(
        for runningApps: [NSRunningApplication],
        cgWindowsByPID: [pid_t: [CGWindowEntry]],
        allCGWindowsByPID: [pid_t: [CGWindowEntry]] = [:]
    ) -> [pid_t: [WindowListEntry]] {
        guard AccessibilityPermissionChecker.isTrusted() else {
            RuntimeLog.info("AX", "not trusted; all app windows will be reported as 0")
            return [:]
        }

        var windowsByPID: [pid_t: [WindowListEntry]] = [:]
        for app in runningApps {
            let appName = app.localizedName ?? app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
            let windows = AXWindowInspector.windows(for: app)
            AXLiveWindowRegistry.shared.refreshSnapshot(
                forPID: app.processIdentifier,
                windows: windows
            )
            let cgWindows = cgWindowsByPID[app.processIdentifier] ?? []
            let allCGWindows = allCGWindowsByPID[app.processIdentifier] ?? cgWindows
            RuntimeLog.info("AX", "\(appName) rawWindows=\(windows.count)")
            guard !windows.isEmpty else { continue }

            let axEntries = windows.enumerated().compactMap { index, window -> AXWindowEntry? in
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
                return AXWindowEntry(
                    index: index,
                    id: windowID,
                    title: titleFromAX ?? "",
                    sourceTitle: titleFromAX,
                    isMinimized: AXWindowInspector.isMinimized(window),
                    window: window,
                    frame: AXWindowInspector.frame(for: window)
                )
            }

            guard !axEntries.isEmpty else {
                pruneCachedCGMatches(for: app.processIdentifier, validWindowIDs: Set<String>())
                continue
            }

            let cgMatchesByAXWindowID = resolveCGWindowAssignments(
                axWindows: axEntries,
                cgWindows: cgWindows
            )
            let cgWindowByID = Dictionary(uniqueKeysWithValues: cgWindows.map { ($0.id, $0) })
            let entries: [WindowListEntry] = axEntries.map { axEntry in
                let matchedCGTitle = cgMatchesByAXWindowID[axEntry.id]
                    .flatMap { cgWindowByID[$0]?.title }
                let title = resolvedAXWindowTitle(
                    sourceTitle: axEntry.sourceTitle,
                    matchedCGTitle: matchedCGTitle,
                    appName: appName,
                    fallbackIndex: axEntry.index
                )
                return WindowListEntry(
                    windowID: axEntry.id,
                    title: title,
                    isMinimized: axEntry.isMinimized,
                    cgWindowID: cgMatchesByAXWindowID[axEntry.id],
                    axWindow: axEntry.window
                )
            }
            let mergedEntries = appendOffSpaceCGWindows(
                to: entries,
                appName: appName,
                pid: app.processIdentifier,
                allCGWindows: allCGWindows
            )

            pruneCachedCGMatches(
                for: app.processIdentifier,
                validWindowIDs: Set(mergedEntries.map(\.windowID))
            )
            RuntimeLog.info("AX", "\(appName) switchableWindows=\(mergedEntries.count)")
            windowsByPID[app.processIdentifier] = mergedEntries
        }
        return windowsByPID
    }

    private func resolvedAXWindowTitle(
        sourceTitle: String?,
        matchedCGTitle: String?,
        appName: String,
        fallbackIndex: Int
    ) -> String {
        if let sourceTitle = normalizedWindowTitle(sourceTitle) {
            return sourceTitle
        }
        if let matchedCGTitle = normalizedWindowTitle(matchedCGTitle) {
            return matchedCGTitle
        }
        RuntimeLog.info("AX", "\(appName) untitled[\(fallbackIndex)] use app-name fallback")
        return appName
    }

    private func normalizedWindowTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func collectAXWindowStats(for runningApps: [NSRunningApplication]) -> [pid_t: AXWindowStats] {
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

    func collectCGWindowsByPID(
        options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    ) -> [pid_t: [CGWindowEntry]] {
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
            let bounds = (item[kCGWindowBounds as String] as? [String: Any])
                .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }?
                .standardized
            let isOnscreen = (item[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue
                ?? options.contains(.optionOnScreenOnly)
            let alpha = (item[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1.0
            let storeType = (item[kCGWindowStoreType as String] as? NSNumber)?.intValue ?? 1
            windowsByPID[ownerPID, default: []].append(
                CGWindowEntry(
                    id: CGWindowID(windowNumber.uint32Value),
                    title: title,
                    bounds: bounds,
                    isOnscreen: isOnscreen,
                    alpha: alpha,
                    storeType: storeType
                )
            )
        }
        return windowsByPID
    }

    private func resolveCGWindowAssignments(
        axWindows: [AXWindowEntry],
        cgWindows: [CGWindowEntry]
    ) -> [String: CGWindowID] {
        guard !axWindows.isEmpty, !cgWindows.isEmpty else { return [:] }

        var allScores: [WindowPairScore] = []
        allScores.reserveCapacity(axWindows.count * cgWindows.count)
        var sortedScoresByAXIndex: [[Double]] = Array(repeating: [], count: axWindows.count)

        for (axIndex, axWindow) in axWindows.enumerated() {
            var scoresForAX: [Double] = []
            scoresForAX.reserveCapacity(cgWindows.count)
            for (cgIndex, cgWindow) in cgWindows.enumerated() {
                let score = cgMatchScore(
                    axWindow: axWindow,
                    cgWindow: cgWindow,
                    cgIndex: cgIndex,
                    axCount: axWindows.count,
                    cgCount: cgWindows.count
                )
                scoresForAX.append(score)
                allScores.append(WindowPairScore(axIndex: axIndex, cgIndex: cgIndex, score: score))
            }
            scoresForAX.sort(by: >)
            sortedScoresByAXIndex[axIndex] = scoresForAX
        }

        var ambiguousAXIndexes: Set<Int> = []
        for (axIndex, scores) in sortedScoresByAXIndex.enumerated() {
            guard let bestScore = scores.first else {
                ambiguousAXIndexes.insert(axIndex)
                continue
            }
            if bestScore < Self.cgMatchMinimumConfidence {
                ambiguousAXIndexes.insert(axIndex)
                continue
            }
            if scores.count > 1, bestScore - scores[1] < Self.cgMatchAmbiguityDelta {
                ambiguousAXIndexes.insert(axIndex)
            }
        }

        var matchedCGIndexes: Set<Int> = []
        var assignmentByAXIndex: [Int: Int] = [:]
        for pair in allScores.sorted(by: { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.axIndex != rhs.axIndex { return lhs.axIndex < rhs.axIndex }
            return lhs.cgIndex < rhs.cgIndex
        }) {
            guard !ambiguousAXIndexes.contains(pair.axIndex) else { continue }
            guard pair.score >= Self.cgMatchMinimumConfidence else { continue }
            guard assignmentByAXIndex[pair.axIndex] == nil else { continue }
            guard !matchedCGIndexes.contains(pair.cgIndex) else { continue }
            assignmentByAXIndex[pair.axIndex] = pair.cgIndex
            matchedCGIndexes.insert(pair.cgIndex)
        }

        var matchedByWindowID: [String: CGWindowID] = [:]
        for (axIndex, cgIndex) in assignmentByAXIndex {
            let windowID = axWindows[axIndex].id
            let cgWindowID = cgWindows[cgIndex].id
            matchedByWindowID[windowID] = cgWindowID
            lastCGWindowIDByAXWindowID[windowID] = cgWindowID
        }
        return matchedByWindowID
    }

    private func cgMatchScore(
        axWindow: AXWindowEntry,
        cgWindow: CGWindowEntry,
        cgIndex: Int,
        axCount: Int,
        cgCount: Int
    ) -> Double {
        let indexRange = max(1, max(axCount, cgCount) - 1)
        let indexDistance = Double(abs(axWindow.index - cgIndex))
        let indexScore = max(0, 1.0 - (indexDistance / Double(indexRange)))

        let frameScore: Double
        if let axFrame = axWindow.frame, let cgBounds = cgWindow.bounds {
            frameScore = geometryScore(axFrame: axFrame, cgFrame: cgBounds)
        } else {
            frameScore = 0.10
        }

        var score = frameScore * (1.0 - Self.cgMatchIndexWeight)
        score += indexScore * Self.cgMatchIndexWeight

        if lastCGWindowIDByAXWindowID[axWindow.id] == cgWindow.id {
            score += Self.cgMatchStickyBonus
        }

        return min(1.0, max(0.0, score))
    }

    private func geometryScore(axFrame: CGRect, cgFrame: CGRect) -> Double {
        let ax = axFrame.standardized
        let cg = cgFrame.standardized
        guard ax.width > 0, ax.height > 0, cg.width > 0, cg.height > 0 else { return 0.0 }

        let intersection = ax.intersection(cg)
        let intersectionArea = max(0, intersection.width * intersection.height)
        let unionArea = max(0, ax.width * ax.height + cg.width * cg.height - intersectionArea)
        let iou = unionArea > 0 ? min(1.0, intersectionArea / unionArea) : 0.0

        let axCenter = CGPoint(x: ax.midX, y: ax.midY)
        let cgCenter = CGPoint(x: cg.midX, y: cg.midY)
        let distance = hypot(axCenter.x - cgCenter.x, axCenter.y - cgCenter.y)
        let distanceScore = max(0.0, 1.0 - min(1.0, distance / 650.0))

        let axArea = ax.width * ax.height
        let cgArea = cg.width * cg.height
        let areaScore = max(0.0, min(1.0, min(axArea, cgArea) / max(axArea, cgArea)))

        return iou * 0.65 + distanceScore * 0.25 + areaScore * 0.10
    }

    private func pruneCachedCGMatches(for pid: pid_t, validWindowIDs: Set<String>) {
        let prefix = "ax:\(pid):"
        let staleKeys = lastCGWindowIDByAXWindowID.keys.filter { key in
            key.hasPrefix(prefix) && !validWindowIDs.contains(key)
        }
        for key in staleKeys {
            lastCGWindowIDByAXWindowID.removeValue(forKey: key)
        }
    }

    func collectAppRankByPID(for runningApps: [NSRunningApplication]) -> [pid_t: Int] {
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

    static func groupID(for bundleIdentifier: String?, fallbackName: String) -> String {
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

    static func groupIDForTesting(bundleIdentifier: String?, fallbackName: String) -> String {
        groupID(for: bundleIdentifier, fallbackName: fallbackName)
    }

    static func resolvedAXWindowTitleForTesting(
        sourceTitle: String?,
        matchedCGTitle: String?,
        appName: String,
        fallbackIndex: Int
    ) -> String {
        RuntimeSnapshotProvider().resolvedAXWindowTitle(
            sourceTitle: sourceTitle,
            matchedCGTitle: matchedCGTitle,
            appName: appName,
            fallbackIndex: fallbackIndex
        )
    }

    struct CGWindowEntryForTesting {
        let id: CGWindowID
        let title: String?
        let bounds: CGRect?
        let isOnscreen: Bool
        let alpha: Double
        let storeType: Int

        init(
            id: CGWindowID,
            title: String?,
            bounds: CGRect?,
            isOnscreen: Bool = true,
            alpha: Double = 1.0,
            storeType: Int = 1
        ) {
            self.id = id
            self.title = title
            self.bounds = bounds
            self.isOnscreen = isOnscreen
            self.alpha = alpha
            self.storeType = storeType
        }
    }

    struct AXWindowEntryForTesting {
        let id: String
        let index: Int
        let bounds: CGRect?
    }

    static func resolveCGWindowAssignmentsForTesting(
        axWindows: [AXWindowEntryForTesting],
        cgWindows: [CGWindowEntryForTesting],
        previousMatches: [String: CGWindowID] = [:]
    ) -> [String: CGWindowID] {
        let provider = RuntimeSnapshotProvider()
        provider.lastCGWindowIDByAXWindowID = previousMatches
        return provider.resolveCGWindowAssignments(
            axWindows: axWindows.map {
                AXWindowEntry(
                    index: $0.index,
                    id: $0.id,
                    title: "",
                    sourceTitle: nil,
                    isMinimized: false,
                    window: AXUIElementCreateSystemWide(),
                    frame: $0.bounds
                )
            },
            cgWindows: cgWindows.map {
                CGWindowEntry(
                    id: $0.id,
                    title: $0.title,
                    bounds: $0.bounds,
                    isOnscreen: $0.isOnscreen,
                    alpha: $0.alpha,
                    storeType: $0.storeType
                )
            }
        )
    }

    func selectPrimaryApps(
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

    func selectPrimaryApps(
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

    func score(
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

    func score(
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

    static func baseAppID(for app: NSRunningApplication) -> String {
        let pid = app.processIdentifier
        return app.bundleIdentifier ?? "pid:\(pid)"
    }

    static func stableLastActiveValue(forRank rank: Int) -> TimeInterval {
        -Double(max(rank, 0))
    }
}
