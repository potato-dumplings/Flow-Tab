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

    func searchIndexPayloadFromMainTables(
        appDirectoryEntries: [RuntimeAppDirectoryEntry],
        generatedAt: TimeInterval
    ) -> RuntimeSearchIndexPayload?
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
            let selectedEntry = appDirectoryEntries.first(where: { $0.appID == appID && $0.pid == pid }),
            selectedEntry.isEligibleForAppSwitcherProjection,
            let runningApp = selectedEntry.runningApplication
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
        guard !windowEntries.isEmpty
            || windowRecordStore.hasWindowProjectionCoverage(processIdentifier: pid)
        else { return nil }

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

        let appSwitcherDirectoryEntries = appDirectoryEntries.filter(
            \.isEligibleForAppSwitcherProjection
        )
        var windowsByPID: [pid_t: [RuntimeWindowListEntry]] = [:]
        var windowCoverageByPID: [pid_t: Bool] = [:]
        for entry in appSwitcherDirectoryEntries {
            let displayName = Self.displayName(for: entry)
            windowsByPID[entry.pid] = windowRecordStore.projectedWindowEntries(
                processIdentifier: entry.pid,
                appName: displayName
            )
            windowCoverageByPID[entry.pid] = windowRecordStore.hasWindowProjectionCoverage(
                processIdentifier: entry.pid
            )
        }
        let windowStatsByPID = RuntimeAppDirectory.windowStats(
            for: appSwitcherDirectoryEntries,
            windowsByPID: windowsByPID,
            isVisibleWindow: { !$0.isMinimized }
        )
        let rankByPID = RuntimeAppDirectory.activationRankByPID(from: appDirectoryEntries)
        let entriesByAppID = RuntimeAppDirectory.groupedEntriesByAppID(
            appSwitcherDirectoryEntries
        )
        let selectedEntries = RuntimeAppDirectory.selectPrimaryEntries(
            from: appSwitcherDirectoryEntries,
            windowStatsByPID: windowStatsByPID,
            rankByPID: rankByPID
        )
        let appLayerEntries = RuntimeAppDirectory.filterAppLayerEntries(
            selectedEntries,
            windowStatsByPID: windowStatsByPID,
            hideMinimizedAppsFromAppLayer: SwitcherBehaviorPreferencesStore.loadHideMinimizedAppsFromAppLayer()
        )
        let sortedEntries = Self.sortedEntriesForProjection(
            appLayerEntries,
            rankByPID: rankByPID
        )

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
            let context = entry.runningApplication.map { runningApp in
                RuntimeAppContext(
                    appID: entry.appID,
                    runningApp: runningApp,
                    ownerPID: entry.pid,
                    windowsByID: Dictionary(
                        uniqueKeysWithValues: windowSeeds.map { seed in
                            (seed.windowID, seed.context)
                        }
                    )
                )
            }
            let hasCoveredAppGroupWindowState = appGroup.allSatisfy {
                windowCoverageByPID[$0.pid] == true
            }
            return (
                appID: entry.appID,
                appGroupPIDs: Set(appGroup.map(\.pid)),
                candidate: candidate,
                context: context,
                hasCoveredAppGroupWindowState: hasCoveredAppGroupWindowState
            )
        }
        let incompleteContextAppIDs = Set(rows.compactMap { row -> String? in
            guard let context = row.context,
                  context.windowsByID.count == row.candidate.windows.count
            else {
                return row.appID
            }
            return nil
        })
        let missingWindowCoveragePIDs = Set(rows.flatMap { row in
            row.appGroupPIDs.filter { windowCoverageByPID[$0] != true }
        })
        let completeAppGroupCount = rows.filter { row in
            guard let context = row.context,
                  context.windowsByID.count == row.candidate.windows.count
            else {
                return false
            }
            return row.hasCoveredAppGroupWindowState
        }.count
        let coverageDiagnostics = RuntimeProjectionCoverageDiagnostics(
            projectedAppCount: rows.count,
            contextAppCount: rows.compactMap { $0.context }.count,
            completeAppGroupCount: completeAppGroupCount,
            missingWindowCoveragePIDs: missingWindowCoveragePIDs,
            incompleteContextAppIDs: incompleteContextAppIDs
        )
        let homeSummaries = Self.homeSummariesFromApplicationDirectory(
            appDirectoryEntries,
            windowsByPID: windowsByPID,
            rankByPID: rankByPID
        )

        return RuntimeAppSwitcherProjectionPayload(
            apps: rows.map(\.candidate),
            contextsByID: Dictionary(
                uniqueKeysWithValues: rows.compactMap { row in
                    row.context.map { ($0.appID, $0) }
                }
            ),
            homeSummaries: homeSummaries,
            hasCompleteWindowCoverage: coverageDiagnostics.hasCompleteCoverage,
            coverageDiagnostics: coverageDiagnostics
        )
    }

    func searchIndexPayloadFromMainTables(
        appDirectoryEntries: [RuntimeAppDirectoryEntry],
        generatedAt: TimeInterval
    ) -> RuntimeSearchIndexPayload? {
        guard let appSwitcherPayload = appSwitcherProjectionPayloadFromMainTables(
            appDirectoryEntries: appDirectoryEntries,
            generatedAt: generatedAt
        ) else {
            return nil
        }
        let appEntries = appSwitcherPayload.apps.map { app in
            RuntimeSearchAppIndexEntry(
                appID: app.id,
                appDisplayName: app.displayName,
                appGroupID: app.groupID,
                appLastActiveAt: app.lastActiveAt,
                searchIndex: SearchTextMatcher.buildIndex(for: app.displayName, identifier: app.id)
            )
        }
        let appSearchIndexes = Dictionary(uniqueKeysWithValues: appEntries.map { ($0.appID, $0.searchIndex) })
        let windowEntries = appSwitcherPayload.apps.flatMap { app -> [RuntimeSearchWindowIndexEntry] in
            let appSearchIndex = appSearchIndexes[app.id]
                ?? SearchTextMatcher.buildIndex(for: app.displayName, identifier: app.id)
            return app.windows.map { window in
                RuntimeSearchWindowIndexEntry(
                    appID: app.id,
                    appDisplayName: app.displayName,
                    windowID: window.id,
                    windowTitle: window.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    windowIsMinimized: window.isMinimized,
                    windowLastActiveAt: window.lastActiveAt,
                    windowSearchIndex: SearchTextMatcher.buildIndex(for: window.title),
                    appSearchIndex: appSearchIndex
                )
            }
        }
        return RuntimeSearchIndexPayload(
            appEntries: appEntries,
            windowEntries: windowEntries,
            hasCompleteWindowCoverage: appSwitcherPayload.hasCompleteWindowCoverage,
            coverageDiagnostics: appSwitcherPayload.coverageDiagnostics
        )
    }

    private static func homeSummariesFromApplicationDirectory(
        _ entries: [RuntimeAppDirectoryEntry],
        windowsByPID: [pid_t: [RuntimeWindowListEntry]],
        rankByPID: [pid_t: Int]
    ) -> [RuntimeHomeAppSummary] {
        let entriesByAppID = RuntimeAppDirectory.groupedEntriesByAppID(entries)
        let primaryEntries = RuntimeAppDirectory.selectPrimaryEntries(
            from: entries,
            windowStatsByPID: [:],
            rankByPID: rankByPID
        )
        return sortedEntriesForProjection(
            primaryEntries,
            rankByPID: rankByPID
        ).enumerated().map { index, entry in
            let eligibleGroup = (entriesByAppID[entry.appID] ?? [entry]).filter(
                \.isEligibleForAppSwitcherProjection
            )
            let windowCount = eligibleGroup.reduce(into: 0) { count, groupEntry in
                count += windowsByPID[groupEntry.pid]?.count ?? 0
            }
            let displayName = displayName(for: entry)
            return RuntimeHomeAppSummary(
                appID: entry.appID,
                displayName: displayName,
                groupID: RuntimeAppIdentity.groupID(
                    for: entry.bundleIdentifier,
                    fallbackName: displayName
                ),
                lastActiveAt: RuntimeAppDirectory.stableLastActiveValue(
                    forRank: rankByPID[entry.pid] ?? index
                ),
                windowCount: windowCount,
                pid: entry.pid,
                bundleIdentifier: entry.bundleIdentifier,
                bundleURL: entry.bundleURL
            )
        }
    }

    private static func sortedEntriesForProjection(
        _ entries: [RuntimeAppDirectoryEntry],
        rankByPID: [pid_t: Int]
    ) -> [RuntimeAppDirectoryEntry] {
        entries.sorted { lhs, rhs in
            let lhsRank = rankByPID[lhs.pid] ?? Int.max
            let rhsRank = rankByPID[rhs.pid] ?? Int.max
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }

            let lhsDisplayName = displayName(for: lhs)
            let rhsDisplayName = displayName(for: rhs)
            if lhsDisplayName == rhsDisplayName {
                return lhs.appID < rhs.appID
            }
            return lhsDisplayName.localizedCaseInsensitiveCompare(rhsDisplayName) == .orderedAscending
        }
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

    func searchIndexPayloadFromMainTables(
        appDirectoryEntries: [RuntimeAppDirectoryEntry],
        generatedAt: TimeInterval
    ) -> RuntimeSearchIndexPayload? {
        nil
    }
}
