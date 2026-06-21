import AppKit
import ApplicationServices
import Foundation
import FlowTabCore

final class RuntimeSnapshotProvider {
    struct AXAppWindowCollection {
        let app: NSRunningApplication
        let appName: String
        let cgWindows: [RuntimeCGWindowEntry]
        let allCGWindows: [RuntimeCGWindowEntry]
        let publicWindowsFetchResult: AXWindowInspector.WindowsFetchResult
        let publicSwitchableWindowCount: Int
        let shouldIncludeRemoteAXWindows: Bool
        let windowsFetchResult: AXWindowInspector.WindowsFetchResult
        let windows: [AXUIElement]
        let axEntries: [RuntimeAXWindowEntry]
        let cgPrepMs: Double
        let publicFetchMs: Double
        let publicSwitchableMs: Double
        let remoteDecisionMs: Double
        let finalFetchMs: Double
        let axInspectMs: Double
        let totalMs: Double
    }

    private static let maxConcurrentAXAppCollections = 4
    private let cgWindowListProvider: RuntimeCGWindowListProviding
    private let spaceTopologyProvider: RuntimeSpaceTopologyProviding
    let reconciliationCoordinator: RuntimeReconciliationCoordinator

    var windowMappingStateByPID: [pid_t: RuntimeWindowMappingState] = [:]

    init(
        cgWindowListProvider: RuntimeCGWindowListProviding = RuntimeSystemCGWindowListProvider(),
        spaceTopologyProvider: RuntimeSpaceTopologyProviding = RuntimeSystemSpaceTopologyProvider(),
        reconciliationCoordinator: RuntimeReconciliationCoordinator = RuntimeReconciliationCoordinator()
    ) {
        self.cgWindowListProvider = cgWindowListProvider
        self.spaceTopologyProvider = spaceTopologyProvider
        self.reconciliationCoordinator = reconciliationCoordinator
    }

    func collectAXWindowData(
        for runningApps: [NSRunningApplication],
        cgWindowsByPID: [pid_t: [RuntimeCGWindowEntry]],
        allCGWindowsByPID: [pid_t: [RuntimeCGWindowEntry]] = [:]
    ) -> [pid_t: [RuntimeWindowListEntry]] {
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
        var windowsByPID: [pid_t: [RuntimeWindowListEntry]] = [:]
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
        cgWindowsByPID: [pid_t: [RuntimeCGWindowEntry]],
        allCGWindowsByPID: [pid_t: [RuntimeCGWindowEntry]]
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
        cgWindowsByPID: [pid_t: [RuntimeCGWindowEntry]],
        allCGWindowsByPID: [pid_t: [RuntimeCGWindowEntry]]
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
        let axEntries = windows.enumerated().compactMap { windowIndex, window -> RuntimeAXWindowEntry? in
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
            return RuntimeAXWindowEntry(
                index: windowIndex,
                id: windowID,
                title: titleFromAX ?? "",
                sourceTitle: titleFromAX,
                isMinimized: AXWindowInspector.isMinimized(window),
                isFocused: AXWindowInspector.isFocused(window),
                isMain: AXWindowInspector.isMain(window),
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
        allCGWindows: [RuntimeCGWindowEntry],
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
        _ allCGWindows: [RuntimeCGWindowEntry]
    ) -> [RuntimeCGWindowEntry] {
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
        _ allCGWindows: [RuntimeCGWindowEntry],
        onscreenCGWindows: [RuntimeCGWindowEntry]
    ) -> [RuntimeCGWindowEntry] {
        let onscreenCGWindowIDs = Set(onscreenCGWindows.map(\.id))
        guard !onscreenCGWindowIDs.isEmpty else { return allCGWindows }

        return allCGWindows.map { window in
            guard onscreenCGWindowIDs.contains(window.id), !window.isOnscreen else {
                return window
            }
            return RuntimeCGWindowEntry(
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
        axWindows: [RuntimeAXWindowEntry],
        cgWindows: [RuntimeCGWindowEntry],
        pid: pid_t,
        appName: String,
        remoteScanCompleteness: RuntimeAXRemoteWindowResolver.RemoteScanCompleteness? = nil
    ) -> [RuntimeWindowListEntry] {
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

    func collectAXWindowStats(for runningApps: [NSRunningApplication]) -> [pid_t: RuntimeAppWindowStats] {
        guard AccessibilityPermissionChecker.isTrusted() else {
            RuntimeLog.warning(.ax, "not trusted; all app windows will be reported as 0")
            return [:]
        }

        var statsByPID: [pid_t: RuntimeAppWindowStats] = [:]
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
            statsByPID[app.processIdentifier] = RuntimeAppWindowStats(
                windowCount: count,
                hasVisibleWindow: hasVisibleWindow
            )
        }
        return statsByPID
    }

    func collectCGWindowsWithSpaceTopologyDiff(
        options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    ) -> RuntimeCGWindowCollection {
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
        guard
            let rawList = cgWindowListProvider.windowInfo(
                options: options,
                relativeToWindow: kCGNullWindowID
            )
        else {
            logSnapshotTiming(
                "collectCGWindows",
                fields: [
                    ("result", "copyFailed"),
                    ("scope", options.contains(.optionOnScreenOnly) ? "onscreen" : "all"),
                    ("totalMs", formatSnapshotMilliseconds(RuntimePerformanceClock.monotonicMilliseconds() - startMs))
                ]
            )
            return RuntimeCGWindowCollection(windowsByPID: [:], spaceTopologyDiff: nil)
        }
        let copyReadyMs = RuntimePerformanceClock.monotonicMilliseconds()

        var windowsByPID: [pid_t: [RuntimeCGWindowEntry]] = [:]
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
                RuntimeCGWindowEntry(
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
        let signatureLogFields = spaceTopologyDiff.signatureLogFields
        logSnapshotTiming(
            "collectCGWindows",
            fields: [
                ("result", "ready"),
                ("scope", scope),
                ("raw", "\(rawList.count)"),
                ("accepted", "\(windowIDs.count)"),
                ("pids", "\(windowsByPID.count)"),
                ("spaceIDs", "\(spaceIDsByWindowID.count)"),
                ("affected", "\(spaceTopologyDiff.affectedCGWindowIDs.count)")
            ] + signatureLogFields + [
                ("copyMs", formatSnapshotMilliseconds(copyReadyMs - startMs)),
                ("parseMs", formatSnapshotMilliseconds(parseReadyMs - copyReadyMs)),
                ("spaceMs", formatSnapshotMilliseconds(spaceReadyMs - parseReadyMs)),
                ("totalMs", formatSnapshotMilliseconds(spaceReadyMs - startMs))
            ]
        )
        guard !spaceIDsByWindowID.isEmpty else {
            return RuntimeCGWindowCollection(
                windowsByPID: windowsByPID,
                spaceTopologyDiff: spaceTopologyDiff
            )
        }

        let enrichedWindowsByPID = Dictionary(uniqueKeysWithValues: windowsByPID.map { pid, windows in
            (
                pid,
                windows.map { window in
                    RuntimeCGWindowEntry(
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
        return RuntimeCGWindowCollection(
            windowsByPID: enrichedWindowsByPID,
            spaceTopologyDiff: spaceTopologyDiff
        )
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

    static func shouldIncludeRemoteAXWindowsForTesting(
        allCGWindows: [RuntimeCGWindowEntry],
        publicSwitchableWindowCount: Int,
        publicFetchSucceeded: Bool = true
    ) -> Bool {
        RuntimeSnapshotProvider().shouldIncludeRemoteAXWindows(
            allCGWindows: allCGWindows,
            publicSwitchableWindowCount: publicSwitchableWindowCount,
            publicFetchSucceeded: publicFetchSucceeded
        )
    }

}
