import AppKit
import Foundation
import FlowTabCore

protocol RuntimeMainTableProjectionBuilding: AnyObject {
    func currentAppWindowPayloadFromMainTables(
        appID: String,
        pid: pid_t,
        appDirectoryEntries: [RuntimeAppDirectoryEntry],
        generatedAt: TimeInterval
    ) -> RuntimeCurrentAppWindowPayload?

    func appSwitcherProjectionPayloadFromMainTables(
        appDirectoryEntries: [RuntimeAppDirectoryEntry],
        generatedAt: TimeInterval
    ) -> RuntimeAppSwitcherProjectionPayload?
}

final class RuntimeMainTableProjectionBuilder: RuntimeMainTableProjectionBuilding {
    private let windowRecordStore: RuntimeWindowRecordStore

    init(windowRecordStore: RuntimeWindowRecordStore) {
        self.windowRecordStore = windowRecordStore
    }

    func currentAppWindowPayloadFromMainTables(
        appID: String,
        pid: pid_t,
        appDirectoryEntries: [RuntimeAppDirectoryEntry],
        generatedAt: TimeInterval
    ) -> RuntimeCurrentAppWindowPayload? {
        guard
            let runningApp = NSRunningApplication(processIdentifier: pid),
            let selectedEntry = appDirectoryEntries.first(where: { $0.appID == appID && $0.pid == pid })
        else {
            return nil
        }
        let directoryEntries = appDirectoryEntries.filter { $0.appID == appID }
        let displayName = selectedEntry.localizedName
            ?? runningApp.localizedName
            ?? selectedEntry.bundleIdentifier
            ?? appID
        let rankByPID = RuntimeAppDirectory.activationRankByPID(from: appDirectoryEntries)
        let summaryRank = RuntimeAppDirectory.preferredRank(
            for: directoryEntries,
            rankByPID: rankByPID,
            fallback: 0
        )
        let windowEntries = windowRecordStore.projectedWindowEntries(
            processIdentifier: pid,
            appName: displayName
        )
        guard !windowEntries.isEmpty else { return nil }

        return RuntimeCurrentAppWindowPayload(
            assemblyInput: RuntimeCurrentAppWindowProjectionAssemblyInput(
                appID: appID,
                displayName: displayName,
                groupID: RuntimeAppIdentity.groupID(
                    for: selectedEntry.bundleIdentifier ?? runningApp.bundleIdentifier,
                    fallbackName: displayName
                ),
                summaryLastActiveAt: RuntimeAppDirectory.stableLastActiveValue(forRank: summaryRank),
                candidateLastActiveAt: generatedAt - Double(summaryRank),
                pid: selectedEntry.pid,
                runningApp: runningApp,
                windowSeeds: windowEntries.enumerated().map { index, entry in
                    entry.projectionSeed(lastActiveAt: generatedAt - Double(index))
                },
                appDirectoryEntries: directoryEntries
            )
        )
    }

    func appSwitcherProjectionPayloadFromMainTables(
        appDirectoryEntries: [RuntimeAppDirectoryEntry],
        generatedAt: TimeInterval
    ) -> RuntimeAppSwitcherProjectionPayload? {
        guard !appDirectoryEntries.isEmpty else { return nil }

        var windowsByPID: [pid_t: [RuntimeWindowListEntry]] = [:]
        for entry in appDirectoryEntries {
            let displayName = Self.displayName(for: entry)
            windowsByPID[entry.pid] = windowRecordStore.projectedWindowEntries(
                processIdentifier: entry.pid,
                appName: displayName
            )
        }
        let windowStatsByPID = RuntimeAppDirectory.windowStats(
            for: appDirectoryEntries,
            windowsByPID: windowsByPID,
            isVisibleWindow: { !$0.isMinimized }
        )
        let rankByPID = RuntimeAppDirectory.activationRankByPID(from: appDirectoryEntries)
        let entriesByAppID = RuntimeAppDirectory.groupedEntriesByAppID(appDirectoryEntries)
        let selectedEntries = RuntimeAppDirectory.selectPrimaryEntries(
            from: appDirectoryEntries,
            windowStatsByPID: windowStatsByPID,
            rankByPID: rankByPID
        )
        let appLayerEntries = RuntimeAppDirectory.filterAppLayerEntries(
            selectedEntries,
            windowStatsByPID: windowStatsByPID,
            hideMinimizedAppsFromAppLayer: SwitcherBehaviorPreferencesStore.loadHideMinimizedAppsFromAppLayer()
        )
        let sortedEntries = appLayerEntries.sorted { lhs, rhs in
            let lhsRank = rankByPID[lhs.pid] ?? Int.max
            let rhsRank = rankByPID[rhs.pid] ?? Int.max
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }

            let lhsDisplayName = Self.displayName(for: lhs)
            let rhsDisplayName = Self.displayName(for: rhs)
            if lhsDisplayName == rhsDisplayName {
                return lhs.appID < rhs.appID
            }
            return lhsDisplayName.localizedCaseInsensitiveCompare(rhsDisplayName) == .orderedAscending
        }

        let rows = sortedEntries.enumerated().map { index, entry in
            let displayName = Self.displayName(for: entry)
            let appGroup = RuntimeAppDirectory.sortedEntriesWithinGroup(
                entriesByAppID[entry.appID] ?? [entry],
                windowStatsByPID: windowStatsByPID,
                rankByPID: rankByPID
            )
            let windowSeeds = appGroup
                .flatMap { windowsByPID[$0.pid] ?? [] }
                .enumerated()
                .map { windowIndex, windowEntry in
                    windowEntry.projectionSeed(
                        lastActiveAt: generatedAt - Double(windowIndex)
                    )
                }
            let candidate = AppSwitchCandidate(
                id: entry.appID,
                displayName: displayName,
                groupID: RuntimeAppIdentity.groupID(
                    for: entry.bundleIdentifier,
                    fallbackName: displayName
                ),
                lastActiveAt: RuntimeAppDirectory.stableLastActiveValue(forRank: rankByPID[entry.pid] ?? index),
                windows: windowSeeds.map(\.candidate)
            )
            let context = NSRunningApplication(processIdentifier: entry.pid).map { runningApp in
                RuntimeAppContext(
                    appID: entry.appID,
                    runningApp: runningApp,
                    windowsByID: Dictionary(
                        uniqueKeysWithValues: windowSeeds.map { seed in
                            (seed.windowID, seed.context)
                        }
                    )
                )
            }
            return (candidate: candidate, context: context)
        }

        return RuntimeAppSwitcherProjectionPayload(
            apps: rows.map(\.candidate),
            contextsByID: Dictionary(
                uniqueKeysWithValues: rows.compactMap { row in
                    row.context.map { ($0.appID, $0) }
                }
            ),
            hasCompleteWindowCoverage: rows.allSatisfy { row in
                guard let context = row.context,
                      !row.candidate.windows.isEmpty
                else { return false }
                return context.windowsByID.count == row.candidate.windows.count
            }
        )
    }

    private static func displayName(for entry: RuntimeAppDirectoryEntry) -> String {
        entry.localizedName ?? entry.bundleIdentifier ?? entry.appID
    }
}

final class RuntimeUnavailableMainTableProjectionBuilder: RuntimeMainTableProjectionBuilding {
    func currentAppWindowPayloadFromMainTables(
        appID: String,
        pid: pid_t,
        appDirectoryEntries: [RuntimeAppDirectoryEntry],
        generatedAt: TimeInterval
    ) -> RuntimeCurrentAppWindowPayload? {
        nil
    }

    func appSwitcherProjectionPayloadFromMainTables(
        appDirectoryEntries: [RuntimeAppDirectoryEntry],
        generatedAt: TimeInterval
    ) -> RuntimeAppSwitcherProjectionPayload? {
        nil
    }
}
