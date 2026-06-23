import AppKit
import ApplicationServices
import Foundation
import FlowTabCore

private typealias FactDiagnostics = RuntimeFactCollectionDiagnostics

final class RuntimeSnapshotProvider {
    private let cgWindowListProvider: RuntimeCGWindowListProviding
    private let spaceTopologyProvider: RuntimeSpaceTopologyProviding
    let windowRecordStore: RuntimeWindowRecordStore
    let reconciliationCoordinator: RuntimeReconciliationCoordinator

    var windowMappingStateByPID: [pid_t: RuntimeWindowMappingState] {
        get { windowRecordStore.mappingStatesByPID }
        set { windowRecordStore.mappingStatesByPID = newValue }
    }

    init(
        cgWindowListProvider: RuntimeCGWindowListProviding = RuntimeSystemCGWindowListProvider(),
        spaceTopologyProvider: RuntimeSpaceTopologyProviding = RuntimeSystemSpaceTopologyProvider(),
        windowRecordStore: RuntimeWindowRecordStore = RuntimeWindowRecordStore(),
        reconciliationCoordinator: RuntimeReconciliationCoordinator = RuntimeReconciliationCoordinator()
    ) {
        self.cgWindowListProvider = cgWindowListProvider
        self.spaceTopologyProvider = spaceTopologyProvider
        self.windowRecordStore = windowRecordStore
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
            FactDiagnostics.logTiming(
                "collectAXWindowData",
                fields: [
                    ("result", "notTrusted"),
                    ("apps", "\(runningApps.count)"),
                    ("totalMs", FactDiagnostics.formatMilliseconds(RuntimePerformanceClock.monotonicMilliseconds() - startMs))
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
            AXLiveWindowRegistry.shared.replaceWindows(
                forPID: app.processIdentifier,
                with: windows
            )
            let registryReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
            RuntimeLog.debug(
                .ax,
                "\(appName) rawWindows=\(windows.count) \(windowsFetchResult.logDetails)"
            )

            RuntimeWindowListDiagnostics.logChromeLikeTopologyFacts(
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
            FactDiagnostics.logTiming(
                "collectAXApp",
                fields: [
                    ("appID", FactDiagnostics.logAppIdentifier(app)),
                    ("pid", "\(app.processIdentifier)"),
                    ("name", FactDiagnostics.logAppName(appName)),
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
                    ("cgPrepMs", FactDiagnostics.formatMilliseconds(collection.cgPrepMs)),
                    ("publicFetchMs", FactDiagnostics.formatMilliseconds(collection.publicFetchMs)),
                    ("publicSwitchableMs", FactDiagnostics.formatMilliseconds(collection.publicSwitchableMs)),
                    ("remoteDecisionMs", FactDiagnostics.formatMilliseconds(collection.remoteDecisionMs)),
                    ("finalFetchMs", FactDiagnostics.formatMilliseconds(collection.finalFetchMs)),
                    ("registryMs", FactDiagnostics.formatMilliseconds(registryReadyMs - registryStartMs)),
                    ("axInspectMs", FactDiagnostics.formatMilliseconds(collection.axInspectMs)),
                    ("topologyLogMs", FactDiagnostics.formatMilliseconds(topologyLogReadyMs - registryReadyMs)),
                    ("resolveMs", FactDiagnostics.formatMilliseconds(resolveReadyMs - topologyLogReadyMs)),
                    ("totalMs", FactDiagnostics.formatMilliseconds(collection.totalMs + resolveReadyMs - registryStartMs))
                ]
            )
            guard !resolvedEntries.isEmpty else { continue }
            RuntimeLog.debug(.ax, "\(appName) switchableWindows=\(resolvedEntries.count)")
            RuntimeWindowListDiagnostics.logResolvedWindowEntrySummary(
                appName: appName,
                pid: app.processIdentifier,
                axWindowCount: axEntries.count,
                entries: resolvedEntries
            )
            windowsByPID[app.processIdentifier] = resolvedEntries
        }
        FactDiagnostics.logTiming(
            "collectAXWindowData",
            fields: [
                ("result", "ready"),
                ("apps", "\(runningApps.count)"),
                ("appsWithWindows", "\(windowsByPID.count)"),
                ("rawAX", "\(totalRawWindows)"),
                ("switchableAX", "\(totalSwitchableWindows)"),
                ("resolved", "\(totalResolvedWindows)"),
                ("concurrency", "\(RuntimeAXAppCollectionCoordinator.maxConcurrentCollections)"),
                ("totalMs", FactDiagnostics.formatMilliseconds(RuntimePerformanceClock.monotonicMilliseconds() - startMs))
            ]
        )
        return windowsByPID
    }

    private func collectAXAppWindowCollections(
        for runningApps: [NSRunningApplication],
        cgWindowsByPID: [pid_t: [RuntimeCGWindowEntry]],
        allCGWindowsByPID: [pid_t: [RuntimeCGWindowEntry]]
    ) -> [RuntimeAXAppWindowCollection] {
        RuntimeAXAppCollectionCoordinator.collect(count: runningApps.count) { [self] index in
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
    ) -> RuntimeAXAppWindowCollection {
        let appStartMs = RuntimePerformanceClock.monotonicMilliseconds()
        let appName = app.localizedName ?? app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
        let cgWindows = cgWindowsByPID[app.processIdentifier] ?? []
        let allCGWindows = RuntimeCGWindowFacts.mergingCurrentOnscreenStatus(
            allCGWindows: allCGWindowsByPID[app.processIdentifier] ?? cgWindows,
            currentOnscreenCGWindows: cgWindows
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
        let shouldIncludeRemoteAXWindows = RuntimeAXRemoteWindowResolver.shouldIncludeRemoteWindows(
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

        return RuntimeAXAppWindowCollection(
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

    func collectCGWindowsWithSpaceTopologyDiff(
        options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements],
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> RuntimeCGWindowCollection {
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
        guard
            let rawList = cgWindowListProvider.windowInfo(
                options: options,
                relativeToWindow: kCGNullWindowID
            )
        else {
            FactDiagnostics.logTiming(
                "collectCGWindows",
                fields: [
                    ("result", "copyFailed"),
                    ("scope", options.contains(.optionOnScreenOnly) ? "onscreen" : "all"),
                    ("totalMs", FactDiagnostics.formatMilliseconds(RuntimePerformanceClock.monotonicMilliseconds() - startMs))
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
        let spaceTopologyDiff = RuntimeWindowRecordEvidence.recordSpaceTopologySnapshot(
            spaceTopologySnapshot,
            now: now,
            reconciliationCoordinator: reconciliationCoordinator,
            mappingStatesByPID: &windowRecordStore.mappingStatesByPID
        )
        let spaceIDsByWindowID = Dictionary(
            uniqueKeysWithValues: spaceTopologySnapshot.spaceIDsByCGWindowID.map { windowID, spaceIDs in
                (windowID, Array(spaceIDs).sorted())
            }
        )
        let spaceReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let scope = options.contains(.optionOnScreenOnly) ? "onscreen" : "all"
        let signatureLogFields = spaceTopologyDiff.signatureLogFields
        FactDiagnostics.logTiming(
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
                ("copyMs", FactDiagnostics.formatMilliseconds(copyReadyMs - startMs)),
                ("parseMs", FactDiagnostics.formatMilliseconds(parseReadyMs - copyReadyMs)),
                ("spaceMs", FactDiagnostics.formatMilliseconds(spaceReadyMs - parseReadyMs)),
                ("totalMs", FactDiagnostics.formatMilliseconds(spaceReadyMs - startMs))
            ]
        )
        let enrichedWindowsByPID = RuntimeCGWindowFacts.mergingSpaceTopology(
            windowsByPID: windowsByPID,
            spaceIDsByCGWindowID: spaceIDsByWindowID
        )
        return RuntimeCGWindowCollection(
            windowsByPID: enrichedWindowsByPID,
            spaceTopologyDiff: spaceTopologyDiff
        )
    }

}
