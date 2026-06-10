import AppKit
import ApplicationServices
import Foundation
import FlowTabCore

final class RuntimeSnapshotProvider {
    struct WindowListEntry {
        let windowID: String
        let title: String
        let isMinimized: Bool
        let ownerPID: pid_t
        let cgWindowID: CGWindowID?
        let activationHandleID: String?
        let axWindow: AXUIElement?
        let frame: CGRect?
        let spaceIDs: [Int]
        let isOnscreen: Bool
        let allowsPublicAXRecovery: Bool
        let hasStickyBinding: Bool
        let lastConfirmationSource: WindowBindingConfirmationSource?
        let bindingConfidenceOverride: WindowBindingConfidence?
        let bindingCandidateCount: Int
        let spaceEvidence: RuntimeSpaceEvidence?

        var bindingConfidence: WindowBindingConfidence {
            if let bindingConfidenceOverride {
                return bindingConfidenceOverride
            }
            if let lastConfirmationSource {
                return lastConfirmationSource.bindingConfidence
            }
            if hasStickyBinding {
                return .sticky
            }
            return .provisional
        }

        var bindingAllowedActions: Set<WindowBindingAction> {
            bindingConfidence.allowedActions
        }

        var bindingDiagnostic: WindowBindingDiagnostic {
            WindowBindingDiagnostic(
                stableWindowID: windowID,
                axWindowID: activationHandleID,
                cgWindowID: cgWindowID,
                confidence: bindingConfidence,
                source: lastConfirmationSource,
                reason: nil,
                candidateCount: bindingCandidateCount,
                allowedActions: bindingAllowedActions
            )
        }

        init(
            windowID: String,
            title: String,
            isMinimized: Bool,
            ownerPID: pid_t = 0,
            cgWindowID: CGWindowID?,
            activationHandleID: String? = nil,
            axWindow: AXUIElement? = nil,
            frame: CGRect? = nil,
            spaceIDs: [Int] = [],
            isOnscreen: Bool = false,
            allowsPublicAXRecovery: Bool = false,
            hasStickyBinding: Bool = false,
            lastConfirmationSource: WindowBindingConfirmationSource? = nil,
            bindingConfidenceOverride: WindowBindingConfidence? = nil,
            bindingCandidateCount: Int? = nil,
            spaceEvidence: RuntimeSpaceEvidence? = nil
        ) {
            self.windowID = windowID
            self.title = title
            self.isMinimized = isMinimized
            self.ownerPID = ownerPID
            self.cgWindowID = cgWindowID
            self.activationHandleID = activationHandleID
            self.axWindow = axWindow
            self.frame = frame
            let normalizedSpaceIDs = RuntimeWindowTopologyClassifier.normalizedSpaceIDs(spaceIDs)
            self.spaceIDs = normalizedSpaceIDs
            self.isOnscreen = isOnscreen
            self.allowsPublicAXRecovery = allowsPublicAXRecovery
            self.hasStickyBinding = hasStickyBinding
            self.lastConfirmationSource = lastConfirmationSource
            self.bindingConfidenceOverride = bindingConfidenceOverride
            self.bindingCandidateCount = bindingCandidateCount ?? (cgWindowID == nil ? 0 : 1)
            self.spaceEvidence = spaceEvidence ?? cgWindowID.map {
                RuntimeWindowTopologyClassifier.spaceEvidence(
                    cgWindowID: $0,
                    spaceIDs: normalizedSpaceIDs,
                    bounds: frame,
                    source: "window-list-entry"
                )
            }
        }
    }

    struct CGWindowEntry {
        let id: CGWindowID
        let title: String?
        let bounds: CGRect?
        let isOnscreen: Bool
        let alpha: Double
        let storeType: Int
        let spaceIDs: [Int]

        init(
            id: CGWindowID,
            title: String?,
            bounds: CGRect?,
            isOnscreen: Bool,
            alpha: Double,
            storeType: Int,
            spaceIDs: [Int] = []
        ) {
            self.id = id
            self.title = title
            self.bounds = bounds
            self.isOnscreen = isOnscreen
            self.alpha = alpha
            self.storeType = storeType
            self.spaceIDs = spaceIDs
        }
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

    struct AXWindowStats {
        let windowCount: Int
        let hasVisibleWindow: Bool
    }

    struct AXAppWindowCollection {
        let app: NSRunningApplication
        let appName: String
        let cgWindows: [CGWindowEntry]
        let allCGWindows: [CGWindowEntry]
        let publicWindowsFetchResult: AXWindowInspector.WindowsFetchResult
        let publicSwitchableWindowCount: Int
        let shouldIncludeRemoteAXWindows: Bool
        let windowsFetchResult: AXWindowInspector.WindowsFetchResult
        let windows: [AXUIElement]
        let axEntries: [AXWindowEntry]
        let cgPrepMs: Double
        let publicFetchMs: Double
        let publicSwitchableMs: Double
        let remoteDecisionMs: Double
        let finalFetchMs: Double
        let axInspectMs: Double
        let totalMs: Double
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
        let spaceIDs: [Int]

        init(
            windowID: String,
            title: String,
            isMinimized: Bool,
            cgWindowID: CGWindowID?,
            spaceIDs: [Int] = []
        ) {
            self.windowID = windowID
            self.title = title
            self.isMinimized = isMinimized
            self.cgWindowID = cgWindowID
            self.spaceIDs = RuntimeWindowTopologyClassifier.normalizedSpaceIDs(spaceIDs)
        }
    }

    struct SnapshotAssemblyRow {
        let pid: pid_t
        let candidate: AppSwitchCandidate
    }

    private static let maxConcurrentAXAppCollections = 4
    private let spaceTopologyProvider: RuntimeSpaceTopologyProviding
    let reconciliationCoordinator: RuntimeReconciliationCoordinator

    var windowMappingStateByPID: [pid_t: RuntimeWindowMappingState] = [:]

    init(
        spaceTopologyProvider: RuntimeSpaceTopologyProviding = RuntimeSystemSpaceTopologyProvider(),
        reconciliationCoordinator: RuntimeReconciliationCoordinator = RuntimeReconciliationCoordinator()
    ) {
        self.spaceTopologyProvider = spaceTopologyProvider
        self.reconciliationCoordinator = reconciliationCoordinator
    }

    func snapshot() -> RuntimeSnapshot {
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
        if let uiTestRuntimeDataset = Self.uiTestRuntimeDataset() {
            let completeMs = RuntimePerformanceClock.monotonicMilliseconds()
            logSnapshotTiming(
                "provider",
                fields: [
                    ("result", "uiTestDataset"),
                    ("apps", "\(uiTestRuntimeDataset.snapshot.apps.count)"),
                    ("windows", "\(uiTestRuntimeDataset.snapshot.apps.reduce(0) { $0 + $1.windows.count })"),
                    ("totalMs", formatSnapshotMilliseconds(completeMs - startMs))
                ]
            )
            return uiTestRuntimeDataset.snapshot
        }
        let runningAppsStartMs = RuntimePerformanceClock.monotonicMilliseconds()
        let runningApps = filteredRunningApplications()
        let runningAppsReadyMs = RuntimePerformanceClock.monotonicMilliseconds()

        guard !runningApps.isEmpty else {
            logSnapshotTiming(
                "provider",
                fields: [
                    ("result", "empty"),
                    ("reason", "noRunningApps"),
                    ("runningAppsMs", formatSnapshotMilliseconds(runningAppsReadyMs - runningAppsStartMs)),
                    ("totalMs", formatSnapshotMilliseconds(runningAppsReadyMs - startMs))
                ]
            )
            return RuntimeSnapshot(apps: [], contextsByID: [:])
        }

        RuntimeLog.debug(.snapshot, "runningApps=\(runningApps.count)")
        let windowDataStartMs = RuntimePerformanceClock.monotonicMilliseconds()
        let windowData = collectWindowData(for: runningApps)
        let windowDataReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let selectionStartMs = windowDataReadyMs
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
        let selectionReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        RuntimeLog.debug(
            .snapshot,
            "selectedApps=\(selectedApps.count) appLayerCandidates=\(appLayerCandidates.count) hideMinimized=\(hideMinimizedAppsFromAppLayer)"
        )

        guard !appLayerCandidates.isEmpty else {
            let completeMs = RuntimePerformanceClock.monotonicMilliseconds()
            logSnapshotTiming(
                "provider",
                fields: [
                    ("result", "empty"),
                    ("reason", "noAppLayerCandidates"),
                    ("runningApps", "\(runningApps.count)"),
                    ("selectedApps", "\(selectedApps.count)"),
                    ("windows", "\(windowData.windowsByPID.values.reduce(0) { $0 + $1.count })"),
                    ("runningAppsMs", formatSnapshotMilliseconds(runningAppsReadyMs - runningAppsStartMs)),
                    ("windowDataMs", formatSnapshotMilliseconds(windowDataReadyMs - windowDataStartMs)),
                    ("selectionMs", formatSnapshotMilliseconds(selectionReadyMs - selectionStartMs)),
                    ("totalMs", formatSnapshotMilliseconds(completeMs - startMs))
                ]
            )
            return RuntimeSnapshot(apps: [], contextsByID: [:])
        }
        let now = Date.timeIntervalSinceReferenceDate

        var rows: [(candidate: AppSwitchCandidate, context: RuntimeAppContext)] = []
        rows.reserveCapacity(appLayerCandidates.count)

        let rowsStartMs = RuntimePerformanceClock.monotonicMilliseconds()
        for (index, app) in appLayerCandidates.enumerated() {
            let pid = app.processIdentifier
            let baseAppID = Self.baseAppID(for: app)
            let appGroup = appsGroupedByBaseID[baseAppID] ?? [app]
            let appID = baseAppID
            let displayName = app.localizedName ?? baseAppID

            let windows = mergedWindowsByPrimaryPID[pid] ?? []
            RuntimeLog.debug(
                .snapshot,
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
                            ownerPID: $0.ownerPID,
                            cgWindowID: $0.cgWindowID,
                            spaceIDs: $0.spaceIDs,
                            inferredTitleBarStyle: nil,
                            activationHandleID: $0.activationHandleID,
                            axWindow: $0.axWindow,
                            frame: $0.frame,
                            allowsPublicAXRecovery: $0.allowsPublicAXRecovery,
                            hasStickyBinding: $0.hasStickyBinding,
                            lastConfirmationSource: $0.lastConfirmationSource,
                            bindingConfidenceOverride: $0.bindingConfidenceOverride,
                            bindingCandidateCount: $0.bindingCandidateCount,
                            spaceEvidence: $0.spaceEvidence
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
        let rowsReadyMs = RuntimePerformanceClock.monotonicMilliseconds()

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
                RuntimeLog.debug(.snapshot, "duplicate appID fallback overwrite=\(row.context.appID)")
            }
            contextsByID[row.context.appID] = row.context
        }
        let completeMs = RuntimePerformanceClock.monotonicMilliseconds()

        logSnapshotTiming(
            "provider",
            fields: [
                ("result", "ready"),
                ("runningApps", "\(runningApps.count)"),
                ("selectedApps", "\(selectedApps.count)"),
                ("appLayerCandidates", "\(appLayerCandidates.count)"),
                ("windows", "\(rows.reduce(0) { $0 + $1.candidate.windows.count })"),
                ("contexts", "\(contextsByID.count)"),
                ("runningAppsMs", formatSnapshotMilliseconds(runningAppsReadyMs - runningAppsStartMs)),
                ("windowDataMs", formatSnapshotMilliseconds(windowDataReadyMs - windowDataStartMs)),
                ("selectionMs", formatSnapshotMilliseconds(selectionReadyMs - selectionStartMs)),
                ("rowsMs", formatSnapshotMilliseconds(rowsReadyMs - rowsStartMs)),
                ("sortContextMs", formatSnapshotMilliseconds(completeMs - rowsReadyMs)),
                ("totalMs", formatSnapshotMilliseconds(completeMs - startMs))
            ]
        )

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
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
        cleanupWindowMappingState(for: runningApps)
        let cleanupReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        AXLiveWindowRegistry.shared.prune(to: runningApps)
        let pruneReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let onScreenCGWindowsByPID = collectCGWindowsByPID()
        let onScreenCGReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let allCGWindowsByPID = collectCGWindowsByPID(options: [.optionAll, .excludeDesktopElements])
        let allCGReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let axWindowsByPID = collectAXWindowData(
            for: runningApps,
            cgWindowsByPID: onScreenCGWindowsByPID,
            allCGWindowsByPID: allCGWindowsByPID
        )
        let axReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let rankByPID = collectAppRankByPID(for: runningApps)
        let completeMs = RuntimePerformanceClock.monotonicMilliseconds()
        logSnapshotTiming(
            "collectWindowData",
            fields: [
                ("apps", "\(runningApps.count)"),
                ("onscreenCGWindows", "\(onScreenCGWindowsByPID.values.reduce(0) { $0 + $1.count })"),
                ("allCGWindows", "\(allCGWindowsByPID.values.reduce(0) { $0 + $1.count })"),
                ("windowPIDs", "\(axWindowsByPID.count)"),
                ("rankPIDs", "\(rankByPID.count)"),
                ("cleanupMs", formatSnapshotMilliseconds(cleanupReadyMs - startMs)),
                ("registryPruneMs", formatSnapshotMilliseconds(pruneReadyMs - cleanupReadyMs)),
                ("onscreenCGMs", formatSnapshotMilliseconds(onScreenCGReadyMs - pruneReadyMs)),
                ("allCGMs", formatSnapshotMilliseconds(allCGReadyMs - onScreenCGReadyMs)),
                ("axMs", formatSnapshotMilliseconds(axReadyMs - allCGReadyMs)),
                ("rankMs", formatSnapshotMilliseconds(completeMs - axReadyMs)),
                ("totalMs", formatSnapshotMilliseconds(completeMs - startMs))
            ]
        )
        // Keep a single source of truth for window counting and selection: AX window list.
        return (
            windowsByPID: axWindowsByPID,
            rankByPID: rankByPID
        )
    }

    func collectAXWindowData(
        for runningApps: [NSRunningApplication],
        cgWindowsByPID: [pid_t: [CGWindowEntry]],
        allCGWindowsByPID: [pid_t: [CGWindowEntry]] = [:]
    ) -> [pid_t: [WindowListEntry]] {
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
        guard AccessibilityPermissionChecker.isTrusted() else {
            RuntimeLog.warning(.ax, "not trusted; all app windows will be reported as 0")
            logSnapshotTiming(
                "collectAXWindowData",
                fields: [
                    ("result", "notTrusted"),
                    ("apps", "\(runningApps.count)"),
                    ("totalMs", formatSnapshotMilliseconds(RuntimePerformanceClock.monotonicMilliseconds() - startMs))
                ]
            )
            return [:]
        }

        let collections = collectAXAppWindowCollections(
            for: runningApps,
            cgWindowsByPID: cgWindowsByPID,
            allCGWindowsByPID: allCGWindowsByPID
        )
        var windowsByPID: [pid_t: [WindowListEntry]] = [:]
        var totalRawWindows = 0
        var totalSwitchableWindows = 0
        var totalResolvedWindows = 0

        for collection in collections {
            let app = collection.app
            let appName = collection.appName
            let windows = collection.windows
            let publicWindowsFetchResult = collection.publicWindowsFetchResult
            let windowsFetchResult = collection.windowsFetchResult
            let axEntries = collection.axEntries
            let registryStartMs = RuntimePerformanceClock.monotonicMilliseconds()
            AXLiveWindowRegistry.shared.refreshSnapshot(
                forPID: app.processIdentifier,
                windows: windows
            )
            let registryReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
            RuntimeLog.debug(
                .ax,
                "\(appName) rawWindows=\(windows.count) \(windowsFetchResult.logDetails)"
            )

            logChromeLikeTopologySnapshot(
                appName: appName,
                pid: app.processIdentifier,
                publicWindowsFetchResult: publicWindowsFetchResult,
                finalWindowsFetchResult: windowsFetchResult,
                includeRemoteAXWindows: collection.shouldIncludeRemoteAXWindows,
                publicSwitchableWindowCount: collection.publicSwitchableWindowCount,
                axWindows: axEntries,
                cgWindows: collection.allCGWindows
            )
            let topologyLogReadyMs = RuntimePerformanceClock.monotonicMilliseconds()

            let resolvedEntries = resolvedWindowEntries(
                axWindows: axEntries,
                cgWindows: collection.allCGWindows,
                pid: app.processIdentifier,
                appName: appName,
                remoteScanCompleteness: windowsFetchResult.remoteScanCompleteness
            )
            let resolveReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
            totalRawWindows += windows.count
            totalSwitchableWindows += axEntries.count
            totalResolvedWindows += resolvedEntries.count
            logSnapshotTiming(
                "collectAXApp",
                fields: [
                    ("appID", logAppIdentifier(app)),
                    ("pid", "\(app.processIdentifier)"),
                    ("name", logAppName(appName)),
                    ("cgOnscreen", "\(collection.cgWindows.count)"),
                    ("cgAll", "\(collection.allCGWindows.count)"),
                    ("rawAX", "\(windows.count)"),
                    ("publicRawAX", "\(publicWindowsFetchResult.windows.count)"),
                    ("publicSwitchableAX", "\(collection.publicSwitchableWindowCount)"),
                    ("switchableAX", "\(axEntries.count)"),
                    ("resolved", "\(resolvedEntries.count)"),
                    ("includeRemote", collection.shouldIncludeRemoteAXWindows ? "1" : "0"),
                    ("publicError", "\(publicWindowsFetchResult.error.rawValue)"),
                    ("finalError", "\(windowsFetchResult.error.rawValue)"),
                    ("cgPrepMs", formatSnapshotMilliseconds(collection.cgPrepMs)),
                    ("publicFetchMs", formatSnapshotMilliseconds(collection.publicFetchMs)),
                    ("publicSwitchableMs", formatSnapshotMilliseconds(collection.publicSwitchableMs)),
                    ("remoteDecisionMs", formatSnapshotMilliseconds(collection.remoteDecisionMs)),
                    ("finalFetchMs", formatSnapshotMilliseconds(collection.finalFetchMs)),
                    ("registryMs", formatSnapshotMilliseconds(registryReadyMs - registryStartMs)),
                    ("axInspectMs", formatSnapshotMilliseconds(collection.axInspectMs)),
                    ("topologyLogMs", formatSnapshotMilliseconds(topologyLogReadyMs - registryReadyMs)),
                    ("resolveMs", formatSnapshotMilliseconds(resolveReadyMs - topologyLogReadyMs)),
                    ("totalMs", formatSnapshotMilliseconds(collection.totalMs + resolveReadyMs - registryStartMs))
                ]
            )
            guard !resolvedEntries.isEmpty else { continue }
            RuntimeLog.debug(.ax, "\(appName) switchableWindows=\(resolvedEntries.count)")
            logResolvedWindowEntrySummary(
                appName: appName,
                pid: app.processIdentifier,
                axWindowCount: axEntries.count,
                entries: resolvedEntries
            )
            windowsByPID[app.processIdentifier] = resolvedEntries
        }
        logSnapshotTiming(
            "collectAXWindowData",
            fields: [
                ("result", "ready"),
                ("apps", "\(runningApps.count)"),
                ("appsWithWindows", "\(windowsByPID.count)"),
                ("rawAX", "\(totalRawWindows)"),
                ("switchableAX", "\(totalSwitchableWindows)"),
                ("resolved", "\(totalResolvedWindows)"),
                ("concurrency", "\(Self.maxConcurrentAXAppCollections)"),
                ("totalMs", formatSnapshotMilliseconds(RuntimePerformanceClock.monotonicMilliseconds() - startMs))
            ]
        )
        return windowsByPID
    }

    private func collectAXAppWindowCollections(
        for runningApps: [NSRunningApplication],
        cgWindowsByPID: [pid_t: [CGWindowEntry]],
        allCGWindowsByPID: [pid_t: [CGWindowEntry]]
    ) -> [AXAppWindowCollection] {
        Self.collectBoundedAXAppResults(count: runningApps.count) { [self] index in
            collectAXAppWindowCollection(
                index: index,
                app: runningApps[index],
                cgWindowsByPID: cgWindowsByPID,
                allCGWindowsByPID: allCGWindowsByPID
            )
        }
    }

    private func collectAXAppWindowCollection(
        index: Int,
        app: NSRunningApplication,
        cgWindowsByPID: [pid_t: [CGWindowEntry]],
        allCGWindowsByPID: [pid_t: [CGWindowEntry]]
    ) -> AXAppWindowCollection {
        let appStartMs = RuntimePerformanceClock.monotonicMilliseconds()
        let appName = app.localizedName ?? app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
        let cgWindows = cgWindowsByPID[app.processIdentifier] ?? []
        let allCGWindows = markCurrentOnscreenCGWindows(
            allCGWindowsByPID[app.processIdentifier] ?? cgWindows,
            onscreenCGWindows: cgWindows
        )
        let cgReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let publicWindowsFetchResult = AXWindowInspector.windowsFetchResult(
            for: app,
            includeRemoteWindows: false
        )
        let publicFetchReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let publicSwitchableWindowCount = publicWindowsFetchResult.windows.filter {
            AXWindowInspector.isSwitchable($0)
        }.count
        let publicSwitchableReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let shouldIncludeRemoteAXWindows = shouldIncludeRemoteAXWindows(
            allCGWindows: allCGWindows,
            publicSwitchableWindowCount: publicSwitchableWindowCount,
            publicFetchSucceeded: publicWindowsFetchResult.error == .success
        )
        let remoteDecisionReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let windowsFetchResult = shouldIncludeRemoteAXWindows
            ? AXWindowInspector.windowsFetchResult(for: app, includeRemoteWindows: true)
            : publicWindowsFetchResult
        let windows = windowsFetchResult.windows
        let finalFetchReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let axEntries = windows.enumerated().compactMap { windowIndex, window -> AXWindowEntry? in
            guard AXWindowInspector.isSwitchable(window) else {
                let role = AXWindowInspector.role(for: window) ?? "unknown"
                RuntimeLog.debug(.ax, "\(appName) skip[\(windowIndex)] role=\(role)")
                return nil
            }
            let windowID = AXWindowInspector.makeWindowID(
                pid: app.processIdentifier,
                index: windowIndex
            )
            let titleFromAX = AXWindowInspector.title(for: window)
            return AXWindowEntry(
                index: windowIndex,
                id: windowID,
                title: titleFromAX ?? "",
                sourceTitle: titleFromAX,
                isMinimized: AXWindowInspector.isMinimized(window),
                window: window,
                frame: AXWindowInspector.frame(for: window)
            )
        }
        let axInspectReadyMs = RuntimePerformanceClock.monotonicMilliseconds()

        return AXAppWindowCollection(
            app: app,
            appName: appName,
            cgWindows: cgWindows,
            allCGWindows: allCGWindows,
            publicWindowsFetchResult: publicWindowsFetchResult,
            publicSwitchableWindowCount: publicSwitchableWindowCount,
            shouldIncludeRemoteAXWindows: shouldIncludeRemoteAXWindows,
            windowsFetchResult: windowsFetchResult,
            windows: windows,
            axEntries: axEntries,
            cgPrepMs: cgReadyMs - appStartMs,
            publicFetchMs: publicFetchReadyMs - cgReadyMs,
            publicSwitchableMs: publicSwitchableReadyMs - publicFetchReadyMs,
            remoteDecisionMs: remoteDecisionReadyMs - publicSwitchableReadyMs,
            finalFetchMs: finalFetchReadyMs - remoteDecisionReadyMs,
            axInspectMs: axInspectReadyMs - finalFetchReadyMs,
            totalMs: axInspectReadyMs - appStartMs
        )
    }

    private static func collectBoundedAXAppResults<Result>(
        count: Int,
        collect: @escaping (Int) -> Result
    ) -> [Result] {
        guard count > 1 else {
            return (0..<count).map { collect($0) }
        }

        let group = DispatchGroup()
        let resultLock = NSLock()
        let concurrencyLimit = min(maxConcurrentAXAppCollections, count)
        let concurrencyGate = DispatchSemaphore(value: concurrencyLimit)
        var results = Array<Result?>(repeating: nil, count: count)

        for index in 0..<count {
            concurrencyGate.wait()
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer {
                    concurrencyGate.signal()
                    group.leave()
                }
                let result = collect(index)
                resultLock.lock()
                results[index] = result
                resultLock.unlock()
            }
        }

        group.wait()
        return results.compactMap { $0 }
    }

    private func shouldIncludeRemoteAXWindows(
        allCGWindows: [CGWindowEntry],
        publicSwitchableWindowCount: Int,
        publicFetchSucceeded: Bool
    ) -> Bool {
        let userFacingCGWindows = userFacingCGWindowsForRemoteAXDecision(allCGWindows)
        guard userFacingCGWindows.contains(where: { window in
            RuntimeWindowTopologyClassifier.hasOffDesktopSpace(spaceIDs: window.spaceIDs)
                || !window.isOnscreen
        }) else {
            return false
        }
        guard publicFetchSucceeded else { return true }
        return publicSwitchableWindowCount < userFacingCGWindows.count
    }

    private func userFacingCGWindowsForRemoteAXDecision(
        _ allCGWindows: [CGWindowEntry]
    ) -> [CGWindowEntry] {
        let validCGWindows = selectSupplementalOffSpaceCGWindows(
            existingCGWindowIDs: [],
            allCGWindows: allCGWindows
        )
        let fullscreenContentBounds = validCGWindows.compactMap { window -> CGRect? in
            guard RuntimeWindowTopologyClassifier.isLikelyOffDesktopFullscreenContent(
                bounds: window.bounds,
                spaceIDs: window.spaceIDs
            ) else { return nil }
            return window.bounds
        }
        return validCGWindows.filter { window in
            !RuntimeWindowTopologyClassifier.isLikelyDesktopWrapper(
                bounds: window.bounds,
                spaceIDs: window.spaceIDs,
                fullscreenContentBounds: fullscreenContentBounds
            )
        }
    }

    private func markCurrentOnscreenCGWindows(
        _ allCGWindows: [CGWindowEntry],
        onscreenCGWindows: [CGWindowEntry]
    ) -> [CGWindowEntry] {
        let onscreenCGWindowIDs = Set(onscreenCGWindows.map(\.id))
        guard !onscreenCGWindowIDs.isEmpty else { return allCGWindows }

        return allCGWindows.map { window in
            guard onscreenCGWindowIDs.contains(window.id), !window.isOnscreen else {
                return window
            }
            return CGWindowEntry(
                id: window.id,
                title: window.title,
                bounds: window.bounds,
                isOnscreen: true,
                alpha: window.alpha,
                storeType: window.storeType,
                spaceIDs: window.spaceIDs
            )
        }
    }

    private func resolvedWindowEntries(
        axWindows: [AXWindowEntry],
        cgWindows: [CGWindowEntry],
        pid: pid_t,
        appName: String,
        remoteScanCompleteness: RuntimeAXRemoteWindowResolver.RemoteScanCompleteness? = nil
    ) -> [WindowListEntry] {
        resolvedStableWindowEntries(
            axWindows: axWindows,
            cgWindows: cgWindows,
            pid: pid,
            appName: appName,
            remoteScanCompleteness: remoteScanCompleteness
        )
    }

    private func resolvedAXWindowTitle(
        sourceTitle: String?,
        matchedCGTitle: String?,
        appName: String,
        fallbackIndex: Int,
        refreshedAXTitle: String?
    ) -> String {
        let normalizedSourceTitle = normalizedWindowTitle(sourceTitle)
        let normalizedMatchedCGTitle = normalizedWindowTitle(matchedCGTitle)
        let normalizedRefreshedAXTitle = normalizedWindowTitle(refreshedAXTitle)
        let sourceLooksLikeAppNameFallback = isAppNameFallbackTitle(
            normalizedSourceTitle,
            appName: appName
        )

        if !sourceLooksLikeAppNameFallback,
            let sourceTitle = normalizedSourceTitle
        {
            return sourceTitle
        }

        if let matchedCGTitle = normalizedMatchedCGTitle,
            !isAppNameFallbackTitle(matchedCGTitle, appName: appName)
        {
            return matchedCGTitle
        }

        if let refreshedAXTitle = normalizedRefreshedAXTitle,
            !isAppNameFallbackTitle(refreshedAXTitle, appName: appName)
        {
            RuntimeLog.info(.ax, "\(appName) untitled[\(fallbackIndex)] recovered-from-ax")
            return refreshedAXTitle
        }

        if let matchedCGTitle = normalizedMatchedCGTitle {
            return matchedCGTitle
        }
        if let refreshedAXTitle = normalizedRefreshedAXTitle {
            return refreshedAXTitle
        }
        if let sourceTitle = normalizedSourceTitle {
            return sourceTitle
        }

        RuntimeLog.info(.ax, "\(appName) untitled[\(fallbackIndex)] use app-name fallback")
        return appName
    }

    private func normalizedWindowTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func isAppNameFallbackTitle(_ title: String?, appName: String) -> Bool {
        guard let normalizedTitle = normalizedWindowTitle(title) else { return false }
        guard let normalizedAppName = normalizedWindowTitle(appName) else { return false }
        return normalizedTitle.caseInsensitiveCompare(normalizedAppName) == .orderedSame
    }

    func collectAXWindowStats(for runningApps: [NSRunningApplication]) -> [pid_t: AXWindowStats] {
        guard AccessibilityPermissionChecker.isTrusted() else {
            RuntimeLog.warning(.ax, "not trusted; all app windows will be reported as 0")
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
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
        guard
            let rawList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else {
            logSnapshotTiming(
                "collectCGWindows",
                fields: [
                    ("result", "copyFailed"),
                    ("scope", options.contains(.optionOnScreenOnly) ? "onscreen" : "all"),
                    ("totalMs", formatSnapshotMilliseconds(RuntimePerformanceClock.monotonicMilliseconds() - startMs))
                ]
            )
            return [:]
        }
        let copyReadyMs = RuntimePerformanceClock.monotonicMilliseconds()

        var windowsByPID: [pid_t: [CGWindowEntry]] = [:]
        var windowIDs: [CGWindowID] = []
        for item in rawList {
            guard let ownerPID = item[kCGWindowOwnerPID as String] as? pid_t else { continue }
            guard let layer = item[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let windowNumber = item[kCGWindowNumber as String] as? NSNumber else { continue }
            let cgWindowID = CGWindowID(windowNumber.uint32Value)
            let title = (item[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let bounds = (item[kCGWindowBounds as String] as? [String: Any])
                .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }?
                .standardized
            let isOnscreen = (item[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue
                ?? options.contains(.optionOnScreenOnly)
            let alpha = (item[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1.0
            let storeType = (item[kCGWindowStoreType as String] as? NSNumber)?.intValue ?? 1
            windowIDs.append(cgWindowID)
            windowsByPID[ownerPID, default: []].append(
                CGWindowEntry(
                    id: cgWindowID,
                    title: title,
                    bounds: bounds,
                    isOnscreen: isOnscreen,
                    alpha: alpha,
                    storeType: storeType
                )
            )
        }
        let parseReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let spaceTopologySnapshot = spaceTopologyProvider.snapshot(for: windowIDs)
        let spaceTopologyDiff = recordSpaceTopologySnapshot(spaceTopologySnapshot)
        let spaceIDsByWindowID = Dictionary(
            uniqueKeysWithValues: spaceTopologySnapshot.spaceIDsByCGWindowID.map { windowID, spaceIDs in
                (windowID, Array(spaceIDs).sorted())
            }
        )
        let spaceReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let scope = options.contains(.optionOnScreenOnly) ? "onscreen" : "all"
        logSnapshotTiming(
            "collectCGWindows",
            fields: [
                ("result", "ready"),
                ("scope", scope),
                ("raw", "\(rawList.count)"),
                ("accepted", "\(windowIDs.count)"),
                ("pids", "\(windowsByPID.count)"),
                ("spaceIDs", "\(spaceIDsByWindowID.count)"),
                ("affected", "\(spaceTopologyDiff.affectedCGWindowIDs.count)"),
                ("copyMs", formatSnapshotMilliseconds(copyReadyMs - startMs)),
                ("parseMs", formatSnapshotMilliseconds(parseReadyMs - copyReadyMs)),
                ("spaceMs", formatSnapshotMilliseconds(spaceReadyMs - parseReadyMs)),
                ("totalMs", formatSnapshotMilliseconds(spaceReadyMs - startMs))
            ]
        )
        guard !spaceIDsByWindowID.isEmpty else { return windowsByPID }

        return Dictionary(uniqueKeysWithValues: windowsByPID.map { pid, windows in
            (
                pid,
                windows.map { window in
                    CGWindowEntry(
                        id: window.id,
                        title: window.title,
                        bounds: window.bounds,
                        isOnscreen: window.isOnscreen,
                        alpha: window.alpha,
                        storeType: window.storeType,
                        spaceIDs: spaceIDsByWindowID[window.id] ?? window.spaceIDs
                    )
                }
            )
        })
    }

    static func matchCGWindowAssignments(
        axWindows: [AXWindowEntry],
        cgWindows: [CGWindowEntry],
        appName: String? = nil,
        previousMatches: [String: CGWindowID] = [:]
    ) -> [String: CGWindowID] {
        matchCGWindowAssignmentsWithDiagnostics(
            axWindows: axWindows,
            cgWindows: cgWindows,
            appName: appName,
            previousMatches: previousMatches
        ).matches
    }

    static func matchCGWindowAssignmentsWithDiagnostics(
        axWindows: [AXWindowEntry],
        cgWindows: [CGWindowEntry],
        appName: String? = nil,
        previousMatches: [String: CGWindowID] = [:]
    ) -> RuntimeWindowAssignmentMatchResult {
        _ = previousMatches
        guard !axWindows.isEmpty, !cgWindows.isEmpty else {
            return RuntimeWindowAssignmentMatchResult(matches: [:], bindingDiagnostics: [])
        }

        var candidateCGIDsByAXWindowID: [String: Set<CGWindowID>] = [:]
        var candidateAXWindowIDsByCGWindowID: [CGWindowID: Set<String>] = [:]

        for axWindow in axWindows {
            let candidateCGWindowIDs = Set(cgWindows.compactMap { cgWindow -> CGWindowID? in
                guard exactCandidateMatch(
                    axWindow: axWindow,
                    cgWindow: cgWindow,
                    appName: appName
                ) else {
                    return nil
                }
                return cgWindow.id
            })
            if !candidateCGWindowIDs.isEmpty {
                candidateCGIDsByAXWindowID[axWindow.id] = candidateCGWindowIDs
            }
        }

        for cgWindow in cgWindows {
            let candidateAXWindowIDs = Set(axWindows.compactMap { axWindow -> String? in
                guard exactCandidateMatch(
                    axWindow: axWindow,
                    cgWindow: cgWindow,
                    appName: appName
                ) else {
                    return nil
                }
                return axWindow.id
            })
            if !candidateAXWindowIDs.isEmpty {
                candidateAXWindowIDsByCGWindowID[cgWindow.id] = candidateAXWindowIDs
            }
        }

        var remainingCGIDsByAXWindowID = candidateCGIDsByAXWindowID
        var remainingAXIDsByCGWindowID = candidateAXWindowIDsByCGWindowID
        var matchedByWindowID: [String: CGWindowID] = [:]

        while true {
            let exactPairs = remainingCGIDsByAXWindowID.compactMap { axWindowID, candidateCGWindowIDs -> (String, CGWindowID)? in
                guard candidateCGWindowIDs.count == 1, let cgWindowID = candidateCGWindowIDs.first else {
                    return nil
                }
                guard remainingAXIDsByCGWindowID[cgWindowID]?.count == 1 else { return nil }
                return (axWindowID, cgWindowID)
            }
            if exactPairs.isEmpty {
                break
            }

            for (axWindowID, cgWindowID) in exactPairs.sorted(by: { lhs, rhs in
                if lhs.0 == rhs.0 {
                    return lhs.1 < rhs.1
                }
                return lhs.0 < rhs.0
            }) {
                matchedByWindowID[axWindowID] = cgWindowID
                remainingCGIDsByAXWindowID.removeValue(forKey: axWindowID)
                remainingAXIDsByCGWindowID.removeValue(forKey: cgWindowID)
                for key in remainingCGIDsByAXWindowID.keys {
                    remainingCGIDsByAXWindowID[key]?.remove(cgWindowID)
                }
                for key in remainingAXIDsByCGWindowID.keys {
                    remainingAXIDsByCGWindowID[key]?.remove(axWindowID)
                }
            }
        }

        let bindingDiagnostics = unresolvedAssignmentDiagnostics(
            remainingCGIDsByAXWindowID: remainingCGIDsByAXWindowID,
            remainingAXIDsByCGWindowID: remainingAXIDsByCGWindowID,
            matchedByWindowID: matchedByWindowID
        )
        for diagnostic in bindingDiagnostics {
            RuntimeLog.debug(
                .axMatch,
                "binding-assignment ambiguous ax=\(diagnostic.axWindowID ?? "nil") candidates=\(diagnostic.candidateCount) candidateCG=\(diagnostic.cgWindowID.map(String.init) ?? "nil") allowedActions=\(diagnostic.allowedActions.map(\.rawValue).sorted().joined(separator: ","))"
            )
        }
        return RuntimeWindowAssignmentMatchResult(
            matches: matchedByWindowID,
            bindingDiagnostics: bindingDiagnostics
        )
    }

    private static func unresolvedAssignmentDiagnostics(
        remainingCGIDsByAXWindowID: [String: Set<CGWindowID>],
        remainingAXIDsByCGWindowID: [CGWindowID: Set<String>],
        matchedByWindowID: [String: CGWindowID]
    ) -> [WindowBindingDiagnostic] {
        remainingCGIDsByAXWindowID.compactMap { axWindowID, candidateCGWindowIDs in
            guard matchedByWindowID[axWindowID] == nil else { return nil }
            guard !candidateCGWindowIDs.isEmpty else { return nil }
            let candidateCount = candidateCGWindowIDs.count
            let conflictedCGCount = candidateCGWindowIDs.filter {
                (remainingAXIDsByCGWindowID[$0]?.count ?? 0) > 1
            }.count
            let totalCandidateCount = max(candidateCount, conflictedCGCount)
            return WindowBindingDiagnostic(
                stableWindowID: axWindowID,
                axWindowID: axWindowID,
                cgWindowID: candidateCount == 1 ? candidateCGWindowIDs.first : nil,
                confidence: .ambiguous,
                source: nil,
                reason: .publicAssignmentAmbiguous,
                candidateCount: totalCandidateCount,
                allowedActions: WindowBindingConfidence.ambiguous.allowedActions
            )
        }
        .sorted { lhs, rhs in
            lhs.stableWindowID < rhs.stableWindowID
        }
    }

    private static func normalizedMatchingTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func exactCandidateMatch(
        axWindow: AXWindowEntry,
        cgWindow: CGWindowEntry,
        appName: String?
    ) -> Bool {
        guard cgWindowPassesValidityConstraints(cgWindow) else { return false }
        guard
            let normalizedAXTitle = exactMatchingTitle(axWindow.sourceTitle ?? axWindow.title, appName: appName),
            let normalizedCGTitle = exactMatchingTitle(cgWindow.title, appName: appName),
            normalizedAXTitle.caseInsensitiveCompare(normalizedCGTitle) == .orderedSame
        else {
            return false
        }
        if let axFrame = axWindow.frame, let cgFrame = cgWindow.bounds {
            return framesApproximatelyMatch(axFrame: axFrame, cgFrame: cgFrame)
        }
        return true
    }

    private static func exactMatchingTitle(_ title: String?, appName: String?) -> String? {
        guard let normalizedTitle = normalizedMatchingTitle(title) else { return nil }
        guard let appName else { return normalizedTitle }
        guard let normalizedAppName = normalizedMatchingTitle(appName) else { return normalizedTitle }
        if normalizedTitle.caseInsensitiveCompare(normalizedAppName) == .orderedSame {
            return nil
        }
        return normalizedTitle
    }

    private static func framesApproximatelyMatch(axFrame: CGRect, cgFrame: CGRect) -> Bool {
        let normalizedAXFrame = axFrame.standardized
        let normalizedCGFrame = cgFrame.standardized
        guard
            normalizedAXFrame.width > 0,
            normalizedAXFrame.height > 0,
            normalizedCGFrame.width > 0,
            normalizedCGFrame.height > 0
        else {
            return false
        }
        return abs(normalizedAXFrame.minX - normalizedCGFrame.minX) <= 24
            && abs(normalizedAXFrame.minY - normalizedCGFrame.minY) <= 24
            && abs(normalizedAXFrame.width - normalizedCGFrame.width) <= 40
            && abs(normalizedAXFrame.height - normalizedCGFrame.height) <= 40
    }

    func collectAppRankByPID(for runningApps: [NSRunningApplication]) -> [pid_t: Int] {
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
        let fallbackRankByPID = collectWindowStackRankByPID()
        let fallbackReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let rankByPID = SystemAppMRUTracker.shared.rankByPID(
            for: runningApps,
            fallbackRankByPID: fallbackRankByPID
        )
        let completeMs = RuntimePerformanceClock.monotonicMilliseconds()
        logSnapshotTiming(
            "collectAppRank",
            fields: [
                ("apps", "\(runningApps.count)"),
                ("fallbackPIDs", "\(fallbackRankByPID.count)"),
                ("rankedPIDs", "\(rankByPID.count)"),
                ("fallbackMs", formatSnapshotMilliseconds(fallbackReadyMs - startMs)),
                ("systemMRUMs", formatSnapshotMilliseconds(completeMs - fallbackReadyMs)),
                ("totalMs", formatSnapshotMilliseconds(completeMs - startMs))
            ]
        )
        return rankByPID
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
        fallbackIndex: Int,
        refreshedAXTitle: String? = nil
    ) -> String {
        RuntimeSnapshotProvider().resolvedAXWindowTitle(
            sourceTitle: sourceTitle,
            matchedCGTitle: matchedCGTitle,
            appName: appName,
            fallbackIndex: fallbackIndex,
            refreshedAXTitle: refreshedAXTitle
        )
    }

    struct BoundedAXAppCollectionPressureResultForTesting {
        let orderedResults: [Int]
        let elapsedMs: Double
        let configuredConcurrency: Int
        let maxInFlight: Int
    }

    static func boundedAXAppCollectionPressureForTesting(
        taskCount: Int,
        delayNanoseconds: UInt64
    ) -> BoundedAXAppCollectionPressureResultForTesting {
        let inFlightLock = NSLock()
        var inFlight = 0
        var maxInFlight = 0
        let startNs = DispatchTime.now().uptimeNanoseconds

        let orderedResults: [Int] = collectBoundedAXAppResults(count: taskCount) { index in
            inFlightLock.lock()
            inFlight += 1
            maxInFlight = max(maxInFlight, inFlight)
            inFlightLock.unlock()

            Thread.sleep(forTimeInterval: Double(delayNanoseconds) / 1_000_000_000.0)

            inFlightLock.lock()
            inFlight -= 1
            inFlightLock.unlock()
            return index
        }
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startNs) / 1_000_000.0

        return BoundedAXAppCollectionPressureResultForTesting(
            orderedResults: orderedResults,
            elapsedMs: elapsedMs,
            configuredConcurrency: min(maxConcurrentAXAppCollections, taskCount),
            maxInFlight: maxInFlight
        )
    }

    struct CGWindowEntryForTesting {
        let id: CGWindowID
        let title: String?
        let bounds: CGRect?
        let isOnscreen: Bool
        let alpha: Double
        let storeType: Int
        let spaceIDs: [Int]

        init(
            id: CGWindowID,
            title: String?,
            bounds: CGRect?,
            isOnscreen: Bool = true,
            alpha: Double = 1.0,
            storeType: Int = 1,
            spaceIDs: [Int] = []
        ) {
            self.id = id
            self.title = title
            self.bounds = bounds
            self.isOnscreen = isOnscreen
            self.alpha = alpha
            self.storeType = storeType
            self.spaceIDs = spaceIDs
        }
    }

    struct AXWindowEntryForTesting {
        let id: String
        let index: Int
        let title: String?
        let bounds: CGRect?
        let bridgedCGWindowID: CGWindowID?

        init(
            id: String,
            index: Int,
            title: String? = nil,
            bounds: CGRect?,
            bridgedCGWindowID: CGWindowID? = nil
        ) {
            self.id = id
            self.index = index
            self.title = title
            self.bounds = bounds
            self.bridgedCGWindowID = bridgedCGWindowID
        }
    }

    static func resolveCGWindowAssignmentsForTesting(
        axWindows: [AXWindowEntryForTesting],
        cgWindows: [CGWindowEntryForTesting],
        previousMatches: [String: CGWindowID] = [:],
        previousAXWindowIDs: Set<String> = [],
        previousCGWindowIDs: Set<CGWindowID> = [],
        pid: pid_t = 100,
        appName: String = "FlowTab Test"
    ) -> [String: CGWindowID] {
        let provider = RuntimeSnapshotProvider()
        provider.windowMappingStateByPID[pid] = windowMappingStateForTesting(
            previousMatches: previousMatches,
            previousAXWindowIDs: previousAXWindowIDs,
            previousCGWindowIDs: previousCGWindowIDs,
            pid: pid
        )
        let axEntries = axWindows.map {
            AXWindowEntry(
                index: $0.index,
                id: $0.id,
                title: $0.title ?? "",
                sourceTitle: $0.title,
                isMinimized: false,
                window: AXUIElementCreateApplication(pid + pid_t($0.index) + 1),
                frame: $0.bounds
            )
        }
        let previousExactBridgeOverride = AXWindowInspector.cgWindowIDOverrideForTesting
        AXWindowInspector.cgWindowIDOverrideForTesting = exactBridgeOverrideForTesting(
            axEntries: axEntries,
            requestedWindowIDsByAXWindowID: requestedWindowIDsByAXWindowIDForTesting(axWindows)
        )
        defer {
            AXWindowInspector.cgWindowIDOverrideForTesting = previousExactBridgeOverride
        }
        return provider.resolveStableWindowMapping(
            axWindows: axEntries,
            cgWindows: cgWindows.map {
                CGWindowEntry(
                    id: $0.id,
                    title: $0.title,
                    bounds: $0.bounds,
                    isOnscreen: $0.isOnscreen,
                    alpha: $0.alpha,
                    storeType: $0.storeType,
                    spaceIDs: $0.spaceIDs
                )
            },
            pid: pid,
            appName: appName
        ).exactMatchesByAXWindowID
    }

    static func resolveCGWindowAssignmentDiagnosticsForTesting(
        axWindows: [AXWindowEntryForTesting],
        cgWindows: [CGWindowEntryForTesting],
        previousMatches: [String: CGWindowID] = [:],
        previousAXWindowIDs: Set<String> = [],
        previousCGWindowIDs: Set<CGWindowID> = [],
        pid: pid_t = 100,
        appName: String = "FlowTab Test"
    ) -> [WindowBindingDiagnostic] {
        let provider = RuntimeSnapshotProvider()
        provider.windowMappingStateByPID[pid] = windowMappingStateForTesting(
            previousMatches: previousMatches,
            previousAXWindowIDs: previousAXWindowIDs,
            previousCGWindowIDs: previousCGWindowIDs,
            pid: pid
        )
        let axEntries = axWindows.map {
            AXWindowEntry(
                index: $0.index,
                id: $0.id,
                title: $0.title ?? "",
                sourceTitle: $0.title,
                isMinimized: false,
                window: AXUIElementCreateApplication(pid + pid_t($0.index) + 1),
                frame: $0.bounds
            )
        }
        let previousExactBridgeOverride = AXWindowInspector.cgWindowIDOverrideForTesting
        AXWindowInspector.cgWindowIDOverrideForTesting = exactBridgeOverrideForTesting(
            axEntries: axEntries,
            requestedWindowIDsByAXWindowID: requestedWindowIDsByAXWindowIDForTesting(axWindows)
        )
        defer {
            AXWindowInspector.cgWindowIDOverrideForTesting = previousExactBridgeOverride
        }
        return provider.resolveStableWindowMapping(
            axWindows: axEntries,
            cgWindows: cgWindows.map {
                CGWindowEntry(
                    id: $0.id,
                    title: $0.title,
                    bounds: $0.bounds,
                    isOnscreen: $0.isOnscreen,
                    alpha: $0.alpha,
                    storeType: $0.storeType,
                    spaceIDs: $0.spaceIDs
                )
            },
            pid: pid,
            appName: appName
        ).bindingDiagnostics
    }

    static func shouldIncludeRemoteAXWindowsForTesting(
        allCGWindows: [CGWindowEntryForTesting],
        publicSwitchableWindowCount: Int,
        publicFetchSucceeded: Bool = true
    ) -> Bool {
        RuntimeSnapshotProvider().shouldIncludeRemoteAXWindows(
            allCGWindows: allCGWindows.map {
                CGWindowEntry(
                    id: $0.id,
                    title: $0.title,
                    bounds: $0.bounds,
                    isOnscreen: $0.isOnscreen,
                    alpha: $0.alpha,
                    storeType: $0.storeType,
                    spaceIDs: $0.spaceIDs
                )
            },
            publicSwitchableWindowCount: publicSwitchableWindowCount,
            publicFetchSucceeded: publicFetchSucceeded
        )
    }

    static func resolveWindowEntriesForTesting(
        axWindows: [AXWindowEntryForTesting],
        cgWindows: [CGWindowEntryForTesting],
        previousMatches: [String: CGWindowID] = [:],
        previousAXWindowIDs: Set<String> = [],
        previousCGWindowIDs: Set<CGWindowID> = [],
        pid: pid_t = 100,
        appName: String = "FlowTab Test"
    ) -> [SupplementalMergeEntryForTesting] {
        let provider = RuntimeSnapshotProvider()
        provider.windowMappingStateByPID[pid] = windowMappingStateForTesting(
            previousMatches: previousMatches,
            previousAXWindowIDs: previousAXWindowIDs,
            previousCGWindowIDs: previousCGWindowIDs,
            pid: pid
        )
        let axEntries = axWindows.map {
            AXWindowEntry(
                index: $0.index,
                id: $0.id,
                title: $0.title ?? "",
                sourceTitle: $0.title,
                isMinimized: false,
                window: AXUIElementCreateApplication(pid + pid_t($0.index) + 1),
                frame: $0.bounds
            )
        }
        let previousExactBridgeOverride = AXWindowInspector.cgWindowIDOverrideForTesting
        AXWindowInspector.cgWindowIDOverrideForTesting = exactBridgeOverrideForTesting(
            axEntries: axEntries,
            requestedWindowIDsByAXWindowID: requestedWindowIDsByAXWindowIDForTesting(axWindows)
        )
        defer {
            AXWindowInspector.cgWindowIDOverrideForTesting = previousExactBridgeOverride
        }
        return provider.resolvedWindowEntries(
            axWindows: axEntries,
            cgWindows: cgWindows.map {
                CGWindowEntry(
                    id: $0.id,
                    title: $0.title,
                    bounds: $0.bounds,
                    isOnscreen: $0.isOnscreen,
                    alpha: $0.alpha,
                    storeType: $0.storeType,
                    spaceIDs: $0.spaceIDs
                )
            },
            pid: pid,
            appName: appName
        ).map {
            SupplementalMergeEntryForTesting(
                windowID: $0.windowID,
                title: $0.title,
                isMinimized: $0.isMinimized,
                cgWindowID: $0.cgWindowID,
                frame: $0.frame,
                spaceIDs: $0.spaceIDs,
                hasActivationHandle: $0.activationHandleID != nil || $0.axWindow != nil,
                lastConfirmationSource: $0.lastConfirmationSource
            )
        }
    }

    private static func exactBridgeOverrideForTesting(
        axEntries: [AXWindowEntry],
        requestedWindowIDsByAXWindowID: [String: CGWindowID]
    ) -> ((AXUIElement) -> CGWindowID?)? {
        guard !requestedWindowIDsByAXWindowID.isEmpty else { return nil }
        let requestedWindowIDsByPointer = [UnsafeMutableRawPointer: CGWindowID](
            uniqueKeysWithValues: axEntries.compactMap { axEntry in
                guard let cgWindowID = requestedWindowIDsByAXWindowID[axEntry.id] else { return nil }
                let pointer = Unmanaged.passUnretained(axEntry.window).toOpaque()
                return (pointer, cgWindowID)
            }
        )
        return { window in
            requestedWindowIDsByPointer[Unmanaged.passUnretained(window).toOpaque()]
        }
    }

    private static func requestedWindowIDsByAXWindowIDForTesting(
        _ axWindows: [AXWindowEntryForTesting]
    ) -> [String: CGWindowID] {
        [String: CGWindowID](
            uniqueKeysWithValues: axWindows.compactMap { axWindow in
                guard let bridgedCGWindowID = axWindow.bridgedCGWindowID else { return nil }
                return (axWindow.id, bridgedCGWindowID)
            }
        )
    }

    private static func windowMappingStateForTesting(
        previousMatches: [String: CGWindowID],
        previousAXWindowIDs: Set<String>,
        previousCGWindowIDs: Set<CGWindowID>,
        pid: pid_t
    ) -> RuntimeWindowMappingState {
        let seedTimestamp = Date.timeIntervalSinceReferenceDate
        let historicalCGWindowIDs = Set(previousMatches.values).union(previousCGWindowIDs)
        let records = Dictionary(uniqueKeysWithValues: historicalCGWindowIDs.map { cgWindowID in
            var record = RuntimeWindowRecord(
                cgWindowID: cgWindowID,
                stableWindowID: makeCGWindowID(pid: pid, cgWindowID: cgWindowID),
                firstSeenAt: seedTimestamp
            )
            if let previousAXWindowID = previousMatches.first(where: { $0.value == cgWindowID })?.key {
                if previousAXWindowIDs.contains(previousAXWindowID) {
                    record.lastExactAXWindowID = previousAXWindowID
                }
                record.lastConfirmationSource = .stickyBinding
                record.lastExactConfirmedAt = seedTimestamp
            }
            return (cgWindowID, record)
        })
        return RuntimeWindowMappingState(
            windowRecordsByCGWindowID: records,
            validCGWindowIDs: previousCGWindowIDs,
            lastAXWindowIDs: previousAXWindowIDs
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
            RuntimeLog.debug(
                .snapshot,
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
            RuntimeLog.debug(
                .snapshot,
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
