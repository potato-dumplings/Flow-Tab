import CoreGraphics
import Foundation
import FlowTabCore

final class RuntimeReadModelStore: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = RuntimeReadModelGeneration()
    private var dirtyAppIDs: Set<String> = []
    private var dirtyPIDs: Set<pid_t> = []
    private var dirtyCGWindowIDs: Set<CGWindowID> = []
    private var spaceTopologySignatureSummary: String?
    private var pendingRepairScopes: Set<String> = []
    private var appDirectoryState = RuntimeAppDirectoryState()
    private var spaceTopologySignature: RuntimeSpaceTopologySignature?
    private var spaceTopologyAffectedCGWindowIDs: Set<CGWindowID> = []
    private var spaceTopologyGeneratedAt: TimeInterval?
    private var appSwitcherProjection: RuntimeAppSwitcherProjection?
    private var homeSummaryProjection: RuntimeHomeSummaryProjection?
    private var currentAppWindowProjectionsByAppID: [String: RuntimeCurrentAppWindowProjection] = [:]
    private var committedSearchIndex: RuntimeSearchIndexProjection?

    @discardableResult
    func commitMainTableAppSwitcherProjectionPayload(
        _ payload: RuntimeAppSwitcherProjectionPayload,
        clearsDirtyForAppID: String? = nil,
        clearsDirtyForPID: pid_t? = nil,
        clearsDirtyCGWindowIDs: Set<CGWindowID> = [],
        generatedAt: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) -> RuntimeAppSwitcherProjectionCommitSummary {
        lock.lock()
        defer { lock.unlock() }

        let clearsDirtyState = appSwitcherProjection == nil && !isDirtyLocked
        markProjectionCommittedLocked()
        if clearsDirtyState {
            clearDirtyStateLocked()
        } else if let clearsDirtyForAppID {
            clearDirtyStateForAppLocked(appID: clearsDirtyForAppID)
            if let clearsDirtyForPID {
                dirtyPIDs.remove(clearsDirtyForPID)
            }
        }
        clearDirtyStateForCoveredCGWindowsLocked(
            clearsDirtyCGWindowIDs,
            coveredCGWindowIDs: payload.coveredCGWindowIDs,
            hasCompleteWindowCoverage: payload.hasCompleteWindowCoverage
        )
        let isCompleteForScope = !isDirtyLocked && payload.hasCompleteWindowCoverage
        appSwitcherProjection = RuntimeAppSwitcherProjection(
            apps: payload.apps,
            contextsByID: payload.contextsByID,
            freshness: freshnessLocked(generatedAt: generatedAt, isCompleteForScope: isCompleteForScope)
        )
        homeSummaryProjection = RuntimeHomeSummaryProjection(
            summaries: payload.homeSummaries,
            freshness: freshnessLocked(generatedAt: generatedAt, isCompleteForScope: isCompleteForScope)
        )
        return RuntimeAppSwitcherProjectionCommitSummary(
            coldStartCommittedCount: clearsDirtyState && isCompleteForScope ? 1 : 0,
            degradedCommittedCount: clearsDirtyState && isCompleteForScope ? 0 : 1
        )
    }

    func commitFullRepairAppDirectoryEvidence(
        _ entries: [RuntimeAppDirectoryEntry],
        generatedAt: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) {
        lock.lock()
        defer { lock.unlock() }

        if replaceAppDirectoryStateLocked(
            entries: entries,
            generatedAt: generatedAt
        ) {
            generation.appLifecycle &+= 1
        }
    }

    func commitAppDirectoryProviderEvidence(
        _ entries: [RuntimeAppDirectoryEntry],
        generatedAt: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) {
        lock.lock()
        defer { lock.unlock() }

        if replaceAppDirectoryStateLocked(
            entries: entries,
            generatedAt: generatedAt
        ) {
            generation.appLifecycle &+= 1
        }
    }

    func commitCurrentAppRepairAppDirectoryEvidence(
        _ entries: [RuntimeAppDirectoryEntry],
        generatedAt: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) {
        lock.lock()
        defer { lock.unlock() }

        if upsertAppDirectoryStateLocked(
            entries: entries,
            generatedAt: generatedAt
        ) {
            generation.appLifecycle &+= 1
        }
    }

    func commitCurrentAppWindowProjection(
        _ payload: RuntimeCurrentAppWindowPayload,
        clearsDirtyState: Bool = true,
        generatedAt: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) {
        lock.lock()
        defer { lock.unlock() }

        markProjectionCommittedLocked()
        if clearsDirtyState {
            clearDirtyStateForAppLocked(appID: payload.summary.appID, pid: payload.summary.pid)
        }
        currentAppWindowProjectionsByAppID[payload.summary.appID] = RuntimeCurrentAppWindowProjection(
            appID: payload.summary.appID,
            currentAppWindowPayload: payload,
            freshness: freshnessLocked(
                generatedAt: generatedAt,
                isCompleteForScope: clearsDirtyState
            )
        )
    }

    @discardableResult
    func commitSearchFreshnessBarrierFromProjectionCache(
        deferredRequestCount: Int,
        hasPendingRequests: Bool,
        generatedAt: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) -> RuntimeSearchIndexProjection? {
        lock.lock()
        defer { lock.unlock() }

        guard deferredRequestCount == 0,
              !hasPendingRequests,
              let projection = appSwitcherProjection,
              projection.freshness.isCompleteForScope,
              projection.freshness.sourceGeneration == generation
        else {
            return nil
        }
        markProjectionCommittedLocked()
        clearDirtyStateLocked()
        committedSearchIndex = buildSearchIndexLocked(
            apps: projection.apps,
            generatedAt: generatedAt,
            isCompleteForScope: true
        )
        return committedSearchIndex
    }

    func markAppLifecycleDirty(
        appID: String,
        pid: pid_t,
        pendingScope: String,
        appDirectoryEntry: RuntimeAppDirectoryEntry? = nil,
        generatedAt: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) {
        lock.lock()
        defer { lock.unlock() }

        generation.appLifecycle &+= 1
        dirtyAppIDs.insert(appID)
        dirtyPIDs.insert(pid)
        pendingRepairScopes.insert(pendingScope)
        if let appDirectoryEntry {
            upsertAppDirectoryStateLocked(
                entries: [appDirectoryEntry],
                generatedAt: generatedAt
            )
        }
    }

    func markAppWindowsDirty(appID: String, pid: pid_t, pendingScope: String) {
        lock.lock()
        defer { lock.unlock() }

        generation.axDirty &+= 1
        dirtyAppIDs.insert(appID)
        dirtyPIDs.insert(pid)
        pendingRepairScopes.insert(pendingScope)
    }

    func markSpaceTopologyDirty(
        affectedCGWindowIDs: Set<CGWindowID>,
        signature: RuntimeSpaceTopologySignature? = nil,
        signatureSummary: String?,
        pendingScope: String,
        generatedAt: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) {
        lock.lock()
        defer { lock.unlock() }

        generation.space &+= 1
        dirtyCGWindowIDs.formUnion(affectedCGWindowIDs)
        if let signature {
            spaceTopologySignature = signature
            spaceTopologyGeneratedAt = generatedAt
        }
        spaceTopologyAffectedCGWindowIDs = affectedCGWindowIDs
        spaceTopologySignatureSummary = signature?.diagnosticSummary ?? signatureSummary
        pendingRepairScopes.insert(pendingScope)
    }

    func markWindowFocusVerified(appID: String, pid: pid_t, affectedCGWindowIDs: Set<CGWindowID>) {
        lock.lock()
        defer { lock.unlock() }

        generation.axDirty &+= 1
        dirtyAppIDs.insert(appID)
        dirtyPIDs.insert(pid)
        dirtyCGWindowIDs.formUnion(affectedCGWindowIDs)
        pendingRepairScopes.insert("activationVerified:\(appID)")
    }

    func markAppTerminatedForMainTableProjection(appID: String, pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }

        guard shouldRemoveTerminatedAppLocked(appID: appID, pid: pid) else {
            dirtyPIDs.remove(pid)
            return
        }
        let survivingDirectoryEntries = appDirectoryEntriesLocked(forAppID: appID)
            .filter { $0.pid != pid }
        if !survivingDirectoryEntries.isEmpty {
            markAppInstanceTerminatedForMainTableProjectionLocked(appID: appID, pid: pid)
            return
        }

        guard hasTerminatedAppStateLocked(appID: appID, pid: pid) else {
            return
        }

        let generatedAt = Date.timeIntervalSinceReferenceDate
        generation.appLifecycle &+= 1
        dirtyAppIDs.insert(appID)
        dirtyPIDs.remove(pid)
        pendingRepairScopes.insert("appTerminated:\(appID)")
        currentAppWindowProjectionsByAppID.removeValue(forKey: appID)
        appDirectoryState.remove(appID: appID, pid: pid, generatedAt: generatedAt)
    }

    private func shouldRemoveTerminatedAppLocked(appID: String, pid: pid_t) -> Bool {
        let directoryEntries = appDirectoryEntriesLocked(forAppID: appID)
        if appDirectoryState.isInitialized {
            return directoryEntries.contains { $0.pid == pid }
        }

        var knownPIDs = Set<pid_t>()
        if let context = appSwitcherProjection?.contextsByID[appID] {
            knownPIDs.insert(context.runningApp.processIdentifier)
        }
        if let context = currentAppWindowProjectionsByAppID[appID]?.currentAppWindowPayload.context {
            knownPIDs.insert(context.runningApp.processIdentifier)
        }
        if let summary = homeSummaryProjection?.summary(for: appID) {
            knownPIDs.insert(summary.pid)
        }
        knownPIDs.formUnion(directoryEntries.map(\.pid))
        return knownPIDs.isEmpty || knownPIDs.contains(pid)
    }

    private func hasTerminatedAppStateLocked(appID: String, pid: pid_t) -> Bool {
        appSwitcherProjection?.apps.contains { $0.id == appID } == true
            || appSwitcherProjection?.contextsByID[appID] != nil
            || homeSummaryProjection?.summaries.contains { $0.appID == appID } == true
            || currentAppWindowProjectionsByAppID[appID] != nil
            || committedSearchIndex?.appEntries.contains { $0.appID == appID } == true
            || committedSearchIndex?.windowEntries.contains { $0.appID == appID } == true
            || dirtyAppIDs.contains(appID)
            || dirtyPIDs.contains(pid)
            || pendingRepairScopes.contains { $0.contains(appID) }
            || appDirectoryEntriesLocked(forAppID: appID).contains { $0.pid == pid }
    }

    private func markAppInstanceTerminatedForMainTableProjectionLocked(appID: String, pid: pid_t) {
        let generatedAt = Date.timeIntervalSinceReferenceDate
        generation.appLifecycle &+= 1
        dirtyAppIDs.insert(appID)
        dirtyPIDs.remove(pid)
        pendingRepairScopes.insert("appTerminated:\(appID)")
        appDirectoryState.remove(pid: pid, generatedAt: generatedAt)
        if let projection = currentAppWindowProjectionsByAppID[appID],
           (
            projection.currentAppWindowPayload.summary.pid == pid
                || projection.currentAppWindowPayload.context.runningApp.processIdentifier == pid
           ) {
            currentAppWindowProjectionsByAppID.removeValue(forKey: appID)
        }
    }

    func readAppSwitcherProjection() -> RuntimeAppSwitcherProjection? {
        lock.lock()
        defer { lock.unlock() }

        if var projection = appSwitcherProjection {
            projection.freshness = freshnessLocked(
                generatedAt: projection.freshness.generatedAt,
                isCompleteForScope: projection.freshness.isCompleteForScope && !isDirtyLocked
            )
            return projection
        }

        guard var projection = appSwitcherProjectionFromAppDirectoryLocked() else {
            return nil
        }
        projection.freshness = appDirectoryDerivedProjectionFreshnessLocked(
            generatedAt: projection.freshness.generatedAt
        )
        return projection
    }

    func readCommittedAppSwitcherProjectionCacheForMaintenance() -> RuntimeAppSwitcherProjection? {
        lock.lock()
        defer { lock.unlock() }

        guard var projection = appSwitcherProjection else { return nil }
        projection.freshness = freshnessLocked(
            generatedAt: projection.freshness.generatedAt,
            isCompleteForScope: projection.freshness.isCompleteForScope && !isDirtyLocked
        )
        return projection
    }

    func readHomeSummaryProjection() -> RuntimeHomeSummaryProjection? {
        lock.lock()
        defer { lock.unlock() }

        if var projection = homeSummaryProjection {
            projection.freshness = freshnessLocked(
                generatedAt: projection.freshness.generatedAt,
                isCompleteForScope: projection.freshness.isCompleteForScope && !isDirtyLocked
            )
            return projection
        }

        guard var projection = homeSummaryProjectionFromAppDirectoryLocked() else {
            return nil
        }
        projection.freshness = appDirectoryDerivedProjectionFreshnessLocked(
            generatedAt: projection.freshness.generatedAt
        )
        return projection
    }

    func readAppDirectoryProjection() -> RuntimeAppDirectoryProjection? {
        lock.lock()
        defer { lock.unlock() }

        return appDirectoryProjectionLocked()
    }

    func readSpaceTopologyProjection() -> RuntimeSpaceTopologyProjection? {
        lock.lock()
        defer { lock.unlock() }

        guard let signature = spaceTopologySignature,
              let generatedAt = spaceTopologyGeneratedAt
        else {
            return nil
        }
        return RuntimeSpaceTopologyProjection(
            signature: signature,
            affectedCGWindowIDs: spaceTopologyAffectedCGWindowIDs,
            freshness: RuntimeProjectionFreshness(
                generatedAt: generatedAt,
                sourceGeneration: generation,
                dirtyAppIDs: dirtyAppIDs,
                dirtyPIDs: dirtyPIDs,
                dirtyCGWindowIDs: dirtyCGWindowIDs,
                spaceTopologySignatureSummary: spaceTopologySignatureSummary,
                pendingRepairScopes: pendingRepairScopes,
                isCompleteForScope: dirtyCGWindowIDs.isEmpty
                    && !pendingRepairScopes.contains("spaceTopology")
            )
        )
    }

    func readHomeAppDetailProjection(appID: String) -> RuntimeHomeAppDetailProjection? {
        lock.lock()
        defer { lock.unlock() }

        guard let projection = currentAppWindowProjectionLocked(appID: appID) else { return nil }
        return RuntimeHomeAppDetailProjection(
            currentAppWindowPayload: projection.currentAppWindowPayload,
            freshness: projection.freshness
        )
    }

    func readCurrentAppWindowProjection(appID: String) -> RuntimeCurrentAppWindowProjection? {
        lock.lock()
        defer { lock.unlock() }

        return currentAppWindowProjectionLocked(appID: appID)
    }

    func readFocusedCurrentAppWindowProjection() -> RuntimeFocusedCurrentAppWindowProjectionRead? {
        lock.lock()
        defer { lock.unlock() }

        guard let focusedEntry = focusedCurrentAppDirectoryEntryLocked() else { return nil }
        let projection = currentAppWindowProjectionLocked(appID: focusedEntry.appID).flatMap { projection in
            projection.currentAppWindowPayload.summary.pid == focusedEntry.pid ? projection : nil
        }
        return RuntimeFocusedCurrentAppWindowProjectionRead(
            appID: focusedEntry.appID,
            pid: focusedEntry.pid,
            projection: projection
        )
    }

    private func currentAppWindowProjectionLocked(appID: String) -> RuntimeCurrentAppWindowProjection? {
        guard var projection = currentAppWindowProjectionsByAppID[appID] else { return nil }
        let isScopeDirty = dirtyAppIDs.contains(appID)
            || dirtyPIDs.contains(projection.currentAppWindowPayload.summary.pid)
            || !dirtyCGWindowIDs.isEmpty
            || !pendingRepairScopes.isEmpty
        projection.freshness = freshnessLocked(
            generatedAt: projection.freshness.generatedAt,
            isCompleteForScope: projection.freshness.isCompleteForScope && !isScopeDirty
        )
        return projection
    }

    private func focusedCurrentAppDirectoryEntryLocked() -> RuntimeAppDirectoryEntry? {
        appDirectoryState.entries
            .compactMap { entry -> (entry: RuntimeAppDirectoryEntry, rank: Int)? in
                guard let rank = entry.activationRank else { return nil }
                return (entry, rank)
            }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank {
                    return lhs.rank < rhs.rank
                }
                return lhs.entry.pid < rhs.entry.pid
            }
            .first?
            .entry
    }

    func readCommittedSearchIndexForSearch() -> RuntimeSearchIndexRead {
        lock.lock()
        defer { lock.unlock() }

        guard var projection = committedSearchIndex else {
            return RuntimeSearchIndexRead(
                projection: nil,
                readiness: .missingCommittedIndex
            )
        }
        let committedSourceGeneration = projection.freshness.sourceGeneration
        let coversCurrentGeneration = committedSourceGeneration == generation
        let isCommittedGenerationValidated = coversCurrentGeneration
            && !isDirtyLocked
        projection.freshness = RuntimeProjectionFreshness(
            generatedAt: projection.freshness.generatedAt,
            sourceGeneration: committedSourceGeneration,
            dirtyAppIDs: dirtyAppIDs,
            dirtyPIDs: dirtyPIDs,
            dirtyCGWindowIDs: dirtyCGWindowIDs,
            spaceTopologySignatureSummary: spaceTopologySignatureSummary,
            pendingRepairScopes: pendingRepairScopes,
            isCompleteForScope: isCommittedGenerationValidated
        )
        return RuntimeSearchIndexRead(
            projection: projection,
            readiness: isCommittedGenerationValidated
                ? .committedGenerationValidated
                : .degradedStaleCommitted
        )
    }

    func diagnostics() -> RuntimeReadModelDiagnostics {
        lock.lock()
        defer { lock.unlock() }

        return RuntimeReadModelDiagnostics(
            generation: generation,
            dirtyAppIDs: dirtyAppIDs,
            dirtyPIDs: dirtyPIDs,
            dirtyCGWindowIDs: dirtyCGWindowIDs,
            spaceTopologySignatureSummary: spaceTopologySignatureSummary,
            pendingRepairScopes: pendingRepairScopes,
            hasAppSwitcherProjection: appSwitcherProjection != nil || appDirectoryState.isInitialized,
            hasHomeSummaryProjection: homeSummaryProjection != nil || appDirectoryState.isInitialized,
            hasCompleteAppSwitcherProjection: appSwitcherProjection?.freshness.isCompleteForScope == true
                && !isDirtyLocked,
            hasCompleteHomeSummaryProjection: homeSummaryProjection?.freshness.isCompleteForScope == true
                && !isDirtyLocked,
            hasAppDirectoryProjection: appDirectoryState.isInitialized,
            hasCompleteAppDirectoryProjection: appDirectoryState.hasCompleteAppLayerCoverage
                && !isDirtyLocked,
            hasSpaceTopologyProjection: spaceTopologySignature != nil,
            spaceTopologyTrackedSpaceCount: spaceTopologySignature?.trackedSpaceCount ?? 0,
            spaceTopologyTrackedWindowCount: spaceTopologySignature?.trackedWindowCount ?? 0,
            spaceTopologyFullscreenWindowCount: spaceTopologySignature?.fullscreenWindowCount ?? 0,
            hasCommittedSearchIndex: committedSearchIndex != nil,
            currentAppWindowProjectionAppIDs: Set(currentAppWindowProjectionsByAppID.keys),
            appDirectoryEntryPIDs: appDirectoryState.entryPIDs
        )
    }

    private var isDirtyLocked: Bool {
        !dirtyAppIDs.isEmpty
            || !dirtyPIDs.isEmpty
            || !dirtyCGWindowIDs.isEmpty
            || !pendingRepairScopes.isEmpty
    }

    private func markProjectionCommittedLocked() {
        generation.projection &+= 1
    }

    private func clearDirtyStateLocked() {
        dirtyAppIDs.removeAll()
        dirtyPIDs.removeAll()
        dirtyCGWindowIDs.removeAll()
        spaceTopologySignatureSummary = nil
        pendingRepairScopes.removeAll()
    }

    private func clearDirtyStateForAppLocked(appID: String, pid: pid_t) {
        clearDirtyStateForAppLocked(appID: appID)
        dirtyPIDs.remove(pid)
    }

    private func clearDirtyStateForAppLocked(appID: String) {
        dirtyAppIDs.remove(appID)
        pendingRepairScopes = pendingRepairScopes.filter { !$0.contains(appID) }
    }

    private func clearDirtyStateForCoveredCGWindowsLocked(
        _ requestedCGWindowIDs: Set<CGWindowID>,
        coveredCGWindowIDs: Set<CGWindowID>,
        hasCompleteWindowCoverage: Bool
    ) {
        guard hasCompleteWindowCoverage, !requestedCGWindowIDs.isEmpty else { return }
        let reconciledCGWindowIDs = requestedCGWindowIDs.intersection(coveredCGWindowIDs)
        guard !reconciledCGWindowIDs.isEmpty else { return }

        dirtyCGWindowIDs.subtract(reconciledCGWindowIDs)
        if dirtyCGWindowIDs.isEmpty {
            pendingRepairScopes.remove("spaceTopology")
            spaceTopologySignatureSummary = nil
        }
    }

    @discardableResult
    private func replaceAppDirectoryStateLocked(
        entries: [RuntimeAppDirectoryEntry],
        generatedAt: TimeInterval
    ) -> Bool {
        let wasInitialized = appDirectoryState.isInitialized
        let previousEntries = appDirectoryState.entries
        appDirectoryState.replace(entries: entries, generatedAt: generatedAt)
        return !wasInitialized || previousEntries != appDirectoryState.entries
    }

    @discardableResult
    private func upsertAppDirectoryStateLocked(
        entries: [RuntimeAppDirectoryEntry],
        generatedAt: TimeInterval
    ) -> Bool {
        let previousEntries = appDirectoryState.entries
        appDirectoryState.upsert(entries: entries, generatedAt: generatedAt)
        return previousEntries != appDirectoryState.entries
    }

    private func appDirectoryProjectionLocked() -> RuntimeAppDirectoryProjection? {
        appDirectoryState.projection { generatedAt in
            freshnessLocked(
                generatedAt: generatedAt,
                isCompleteForScope: appDirectoryState.hasCompleteAppLayerCoverage && !isDirtyLocked
            )
        }
    }

    private func appDirectoryEntriesLocked(forAppID appID: String) -> [RuntimeAppDirectoryEntry] {
        appDirectoryState.entries(forAppID: appID)
    }

    private func appSwitcherProjectionFromAppDirectoryLocked() -> RuntimeAppSwitcherProjection? {
        guard let generatedAt = appDirectoryState.generatedAt else { return nil }

        let rankByPID = RuntimeAppDirectory.activationRankByPID(from: appDirectoryState.entries)
        let selectedEntries = RuntimeAppDirectory.selectPrimaryEntries(
            from: appDirectoryState.entries,
            windowStatsByPID: [:],
            rankByPID: rankByPID
        )
        let apps = Self.sortedAppDirectoryEntriesForProjection(
            selectedEntries,
            rankByPID: rankByPID
        ).enumerated().map { index, entry in
            let rank = rankByPID[entry.pid] ?? index
            let displayName = entry.localizedName ?? entry.bundleIdentifier ?? entry.appID
            return AppSwitchCandidate(
                id: entry.appID,
                displayName: displayName,
                groupID: RuntimeAppIdentity.groupID(
                    for: entry.bundleIdentifier,
                    fallbackName: displayName
                ),
                lastActiveAt: RuntimeAppDirectory.stableLastActiveValue(forRank: rank),
                windows: []
            )
        }
        return RuntimeAppSwitcherProjection(
            apps: apps,
            contextsByID: [:],
            freshness: appDirectoryDerivedProjectionFreshnessLocked(generatedAt: generatedAt)
        )
    }

    private func homeSummaryProjectionFromAppDirectoryLocked() -> RuntimeHomeSummaryProjection? {
        guard let generatedAt = appDirectoryState.generatedAt else { return nil }

        let rankByPID = RuntimeAppDirectory.activationRankByPID(from: appDirectoryState.entries)
        let selectedEntries = RuntimeAppDirectory.selectPrimaryEntries(
            from: appDirectoryState.entries,
            windowStatsByPID: [:],
            rankByPID: rankByPID
        )
        let summaries = Self.sortedAppDirectoryEntriesForProjection(
            selectedEntries,
            rankByPID: rankByPID
        ).enumerated().map { index, entry in
            let rank = rankByPID[entry.pid] ?? index
            let displayName = entry.localizedName ?? entry.bundleIdentifier ?? entry.appID
            return RuntimeHomeAppSummary(
                appID: entry.appID,
                displayName: displayName,
                groupID: RuntimeAppIdentity.groupID(
                    for: entry.bundleIdentifier,
                    fallbackName: displayName
                ),
                lastActiveAt: RuntimeAppDirectory.stableLastActiveValue(forRank: rank),
                windowCount: 0,
                pid: entry.pid,
                bundleIdentifier: entry.bundleIdentifier,
                bundleURL: entry.bundleURL
            )
        }
        return RuntimeHomeSummaryProjection(
            summaries: summaries,
            freshness: appDirectoryDerivedProjectionFreshnessLocked(generatedAt: generatedAt)
        )
    }

    private static func sortedAppDirectoryEntriesForProjection(
        _ entries: [RuntimeAppDirectoryEntry],
        rankByPID: [pid_t: Int]
    ) -> [RuntimeAppDirectoryEntry] {
        entries.sorted { lhs, rhs in
            let lhsRank = rankByPID[lhs.pid] ?? Int.max
            let rhsRank = rankByPID[rhs.pid] ?? Int.max
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }

            let lhsDisplayName = lhs.localizedName ?? lhs.bundleIdentifier ?? lhs.appID
            let rhsDisplayName = rhs.localizedName ?? rhs.bundleIdentifier ?? rhs.appID
            if lhsDisplayName == rhsDisplayName {
                return lhs.appID < rhs.appID
            }
            return lhsDisplayName.localizedCaseInsensitiveCompare(rhsDisplayName) == .orderedAscending
        }
    }

    private func freshnessLocked(
        generatedAt: TimeInterval,
        isCompleteForScope: Bool
    ) -> RuntimeProjectionFreshness {
        RuntimeProjectionFreshness(
            generatedAt: generatedAt,
            sourceGeneration: generation,
            dirtyAppIDs: dirtyAppIDs,
            dirtyPIDs: dirtyPIDs,
            dirtyCGWindowIDs: dirtyCGWindowIDs,
            spaceTopologySignatureSummary: spaceTopologySignatureSummary,
            pendingRepairScopes: pendingRepairScopes,
            isCompleteForScope: isCompleteForScope
        )
    }

    private func appDirectoryDerivedProjectionFreshnessLocked(
        generatedAt: TimeInterval
    ) -> RuntimeProjectionFreshness {
        freshnessLocked(
            generatedAt: generatedAt,
            isCompleteForScope: false
        )
    }

    private func buildSearchIndexLocked(
        apps: [AppSwitchCandidate],
        generatedAt: TimeInterval,
        isCompleteForScope: Bool
    ) -> RuntimeSearchIndexProjection {
        let appEntries = apps.map(buildSearchAppIndexEntryLocked)
        let appSearchIndexes = Dictionary(uniqueKeysWithValues: appEntries.map { ($0.appID, $0.searchIndex) })
        let windowEntries = apps.flatMap { app -> [RuntimeSearchWindowIndexEntry] in
            let appSearchIndex = appSearchIndexes[app.id]
                ?? SearchTextMatcher.buildIndex(for: app.displayName, identifier: app.id)
            return buildSearchWindowIndexEntriesLocked(
                app: app,
                appSearchIndex: appSearchIndex
            )
        }
        return RuntimeSearchIndexProjection(
            appEntries: appEntries,
            windowEntries: windowEntries,
            freshness: freshnessLocked(
                generatedAt: generatedAt,
                isCompleteForScope: isCompleteForScope && !isDirtyLocked
            )
        )
    }

    private func buildSearchAppIndexEntryLocked(app: AppSwitchCandidate) -> RuntimeSearchAppIndexEntry {
        RuntimeSearchAppIndexEntry(
            appID: app.id,
            appDisplayName: app.displayName,
            searchIndex: SearchTextMatcher.buildIndex(for: app.displayName, identifier: app.id)
        )
    }

    private func buildSearchWindowIndexEntriesLocked(
        app: AppSwitchCandidate,
        appSearchIndex: SearchTextMatcher.Index
    ) -> [RuntimeSearchWindowIndexEntry] {
        app.windows.map { window in
            RuntimeSearchWindowIndexEntry(
                appID: app.id,
                appDisplayName: app.displayName,
                windowID: window.id,
                windowTitle: window.title.trimmingCharacters(in: .whitespacesAndNewlines),
                windowSearchIndex: SearchTextMatcher.buildIndex(for: window.title),
                appSearchIndex: appSearchIndex
            )
        }
    }
}
