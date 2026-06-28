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
    private var appSwitcherProjection: RuntimeAppSwitcherProjection?
    private var homeSummaryProjection: RuntimeHomeSummaryProjection?
    private var currentAppWindowProjectionsByAppID: [String: RuntimeCurrentAppWindowProjection] = [:]
    private var committedSearchIndex: RuntimeSearchIndexProjection?

    @discardableResult
    func commitMainTableAppSwitcherProjectionPayload(
        _ payload: RuntimeAppSwitcherProjectionPayload,
        generatedAt: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) -> RuntimeAppSwitcherProjectionCommitSummary {
        lock.lock()
        defer { lock.unlock() }

        let clearsDirtyState = appSwitcherProjection == nil && !isDirtyLocked
        markProjectionCommittedLocked()
        if clearsDirtyState {
            clearDirtyStateLocked()
        }
        appSwitcherProjection = RuntimeAppSwitcherProjection(
            apps: payload.apps,
            contextsByID: payload.contextsByID,
            freshness: freshnessLocked(generatedAt: generatedAt, isCompleteForScope: !isDirtyLocked)
        )
        homeSummaryProjection = RuntimeHomeSummaryProjection(
            summaries: homeSummariesLocked(for: payload.apps, contextsByID: payload.contextsByID),
            freshness: freshnessLocked(generatedAt: generatedAt, isCompleteForScope: !isDirtyLocked)
        )
        return RuntimeAppSwitcherProjectionCommitSummary(
            coldStartCommittedCount: clearsDirtyState ? 1 : 0,
            degradedCommittedCount: clearsDirtyState ? 0 : 1
        )
    }

    func commitFullRepairAppDirectoryEvidence(
        _ entries: [RuntimeAppDirectoryEntry],
        generatedAt: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) {
        lock.lock()
        defer { lock.unlock() }

        replaceAppDirectoryStateLocked(
            entries: entries,
            generatedAt: generatedAt
        )
    }

    func commitAppDirectoryProviderEvidence(
        _ entries: [RuntimeAppDirectoryEntry],
        generatedAt: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) {
        lock.lock()
        defer { lock.unlock() }

        replaceAppDirectoryStateLocked(
            entries: entries,
            generatedAt: generatedAt
        )
    }

    func commitCurrentAppRepairAppDirectoryEvidence(
        _ entries: [RuntimeAppDirectoryEntry],
        generatedAt: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) {
        lock.lock()
        defer { lock.unlock() }

        upsertAppDirectoryStateLocked(
            entries: entries,
            generatedAt: generatedAt
        )
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
        signatureSummary: String?,
        pendingScope: String
    ) {
        lock.lock()
        defer { lock.unlock() }

        generation.space &+= 1
        dirtyCGWindowIDs.formUnion(affectedCGWindowIDs)
        spaceTopologySignatureSummary = signatureSummary
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
        dirtyAppIDs.remove(appID)
        dirtyPIDs.remove(pid)
        pendingRepairScopes = pendingRepairScopes.filter { !$0.contains(appID) }
        currentAppWindowProjectionsByAppID.removeValue(forKey: appID)
        appDirectoryState.remove(appID: appID, pid: pid, generatedAt: generatedAt)
    }

    private func shouldRemoveTerminatedAppLocked(appID: String, pid: pid_t) -> Bool {
        let directoryEntries = appDirectoryEntriesLocked(forAppID: appID)
        if appDirectoryState.isInitialized,
           !directoryEntries.isEmpty {
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

        guard var projection = appSwitcherProjection ?? appSwitcherProjectionFromAppDirectoryLocked() else {
            return nil
        }
        projection.freshness = freshnessLocked(
            generatedAt: projection.freshness.generatedAt,
            isCompleteForScope: !isDirtyLocked
        )
        return projection
    }

    func readHomeSummaryProjection() -> RuntimeHomeSummaryProjection? {
        lock.lock()
        defer { lock.unlock() }

        guard var projection = homeSummaryProjection ?? homeSummaryProjectionFromAppDirectoryLocked() else {
            return nil
        }
        projection.freshness = freshnessLocked(
            generatedAt: projection.freshness.generatedAt,
            isCompleteForScope: !isDirtyLocked
        )
        return projection
    }

    func readAppDirectoryProjection() -> RuntimeAppDirectoryProjection? {
        lock.lock()
        defer { lock.unlock() }

        return appDirectoryProjectionLocked()
    }

    func readHomeAppDetailProjection(appID: String) -> RuntimeHomeAppDetailProjection? {
        lock.lock()
        defer { lock.unlock() }

        guard let projection = currentAppWindowProjectionsByAppID[appID] else { return nil }
        return RuntimeHomeAppDetailProjection(
            currentAppWindowPayload: projection.currentAppWindowPayload
        )
    }

    func readCurrentAppWindowProjection(appID: String) -> RuntimeCurrentAppWindowProjection? {
        lock.lock()
        defer { lock.unlock() }

        guard var projection = currentAppWindowProjectionsByAppID[appID] else { return nil }
        let isScopeDirty = dirtyAppIDs.contains(appID)
            || dirtyPIDs.contains(projection.currentAppWindowPayload.summary.pid)
            || !dirtyCGWindowIDs.isEmpty
            || !pendingRepairScopes.isEmpty
        projection.freshness = freshnessLocked(
            generatedAt: projection.freshness.generatedAt,
            isCompleteForScope: !isScopeDirty
        )
        return projection
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
            hasAppDirectoryProjection: appDirectoryState.isInitialized,
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
        dirtyAppIDs.remove(appID)
        dirtyPIDs.remove(pid)
        pendingRepairScopes = pendingRepairScopes.filter { !$0.contains(appID) }
    }

    private func replaceAppDirectoryStateLocked(
        entries: [RuntimeAppDirectoryEntry],
        generatedAt: TimeInterval
    ) {
        appDirectoryState.replace(entries: entries, generatedAt: generatedAt)
    }

    private func upsertAppDirectoryStateLocked(
        entries: [RuntimeAppDirectoryEntry],
        generatedAt: TimeInterval
    ) {
        appDirectoryState.upsert(entries: entries, generatedAt: generatedAt)
    }

    private func appDirectoryProjectionLocked() -> RuntimeAppDirectoryProjection? {
        appDirectoryState.projection { generatedAt in
            freshnessLocked(generatedAt: generatedAt, isCompleteForScope: !isDirtyLocked)
        }
    }

    private func appDirectoryEntriesLocked(forAppID appID: String) -> [RuntimeAppDirectoryEntry] {
        appDirectoryState.entries(forAppID: appID)
    }

    private func appSwitcherProjectionFromAppDirectoryLocked() -> RuntimeAppSwitcherProjection? {
        guard let generatedAt = appDirectoryState.generatedAt else { return nil }

        let selectedEntries = RuntimeAppDirectory.selectPrimaryEntries(
            from: appDirectoryState.entries,
            windowStatsByPID: [:],
            rankByPID: [:]
        )
        let apps = selectedEntries.enumerated().map { index, entry in
            let displayName = entry.localizedName ?? entry.bundleIdentifier ?? entry.appID
            return AppSwitchCandidate(
                id: entry.appID,
                displayName: displayName,
                groupID: RuntimeAppIdentity.groupID(
                    for: entry.bundleIdentifier,
                    fallbackName: displayName
                ),
                lastActiveAt: RuntimeAppDirectory.stableLastActiveValue(forRank: index),
                windows: []
            )
        }
        return RuntimeAppSwitcherProjection(
            apps: apps,
            contextsByID: [:],
            freshness: freshnessLocked(generatedAt: generatedAt, isCompleteForScope: !isDirtyLocked)
        )
    }

    private func homeSummaryProjectionFromAppDirectoryLocked() -> RuntimeHomeSummaryProjection? {
        guard let generatedAt = appDirectoryState.generatedAt else { return nil }

        let selectedEntries = RuntimeAppDirectory.selectPrimaryEntries(
            from: appDirectoryState.entries,
            windowStatsByPID: [:],
            rankByPID: [:]
        )
        let summaries = selectedEntries.enumerated().map { index, entry in
            let displayName = entry.localizedName ?? entry.bundleIdentifier ?? entry.appID
            return RuntimeHomeAppSummary(
                appID: entry.appID,
                displayName: displayName,
                groupID: RuntimeAppIdentity.groupID(
                    for: entry.bundleIdentifier,
                    fallbackName: displayName
                ),
                lastActiveAt: RuntimeAppDirectory.stableLastActiveValue(forRank: index),
                windowCount: 0,
                pid: entry.pid
            )
        }
        return RuntimeHomeSummaryProjection(
            summaries: summaries,
            freshness: freshnessLocked(generatedAt: generatedAt, isCompleteForScope: !isDirtyLocked)
        )
    }

    private func homeSummaryLocked(
        for app: AppSwitchCandidate,
        context: RuntimeAppContext?
    ) -> RuntimeHomeAppSummary {
        RuntimeHomeAppSummary(
            appID: app.id,
            displayName: app.displayName,
            groupID: app.groupID,
            lastActiveAt: app.lastActiveAt,
            windowCount: app.windows.count,
            pid: context?.runningApp.processIdentifier ?? 0
        )
    }

    private func homeSummariesLocked(
        for apps: [AppSwitchCandidate],
        contextsByID: [String: RuntimeAppContext]
    ) -> [RuntimeHomeAppSummary] {
        apps.map { app in
            homeSummaryLocked(
                for: app,
                context: contextsByID[app.id]
            )
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
