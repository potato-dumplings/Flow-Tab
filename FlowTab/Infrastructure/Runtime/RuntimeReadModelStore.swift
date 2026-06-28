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
    private var stagingSearchIndex: RuntimeSearchIndexProjection?

    func commitAppSwitcherProjection(
        apps: [AppSwitchCandidate],
        contextsByID: [String: RuntimeAppContext],
        appDirectoryEntries: [RuntimeAppDirectoryEntry]?,
        clearsDirtyState: Bool = true,
        generatedAt: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) {
        lock.lock()
        defer { lock.unlock() }

        markProjectionCommittedLocked()
        if clearsDirtyState {
            clearDirtyStateLocked()
        }
        appSwitcherProjection = RuntimeAppSwitcherProjection(
            apps: apps,
            contextsByID: contextsByID,
            freshness: freshnessLocked(generatedAt: generatedAt, isCompleteForScope: !isDirtyLocked)
        )
        homeSummaryProjection = RuntimeHomeSummaryProjection(
            summaries: homeSummariesLocked(for: apps, contextsByID: contextsByID),
            freshness: freshnessLocked(generatedAt: generatedAt, isCompleteForScope: !isDirtyLocked)
        )
        if let appDirectoryEntries {
            replaceAppDirectoryStateLocked(
                entries: appDirectoryEntries,
                generatedAt: generatedAt
            )
        }
        if clearsDirtyState {
            committedSearchIndex = buildSearchIndexLocked(
                apps: apps,
                generatedAt: generatedAt,
                isCompleteForScope: true
            )
            stagingSearchIndex = nil
        }
    }

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

    func commitHomeSummaries(
        _ summaries: [RuntimeHomeAppSummary],
        generatedAt: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) {
        lock.lock()
        defer { lock.unlock() }

        markProjectionCommittedLocked()
        clearDirtyStateLocked()
        homeSummaryProjection = RuntimeHomeSummaryProjection(
            summaries: summaries,
            freshness: freshnessLocked(generatedAt: generatedAt, isCompleteForScope: true)
        )
    }

    func commitHomeSummary(
        _ summary: RuntimeHomeAppSummary,
        generatedAt: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) {
        lock.lock()
        defer { lock.unlock() }

        markProjectionCommittedLocked()
        clearDirtyStateForAppLocked(appID: summary.appID, pid: summary.pid)
        upsertHomeSummaryProjectionLocked(summary, generatedAt: generatedAt)
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
        upsertAppDirectoryStateLocked(
            entries: payload.appDirectoryEntries,
            generatedAt: generatedAt
        )
        upsertHomeSummaryProjectionLocked(payload.summary, generatedAt: generatedAt)
        upsertAppSwitcherProjectionLocked(payload, generatedAt: generatedAt)
    }

    private func stageSearchIndexAppLocked(
        _ app: AppSwitchCandidate,
        generatedAt: TimeInterval
    ) -> RuntimeSearchIndexProjection? {
        guard let base = stagingSearchIndex ?? committedSearchIndex else { return nil }
        let appEntry = buildSearchAppIndexEntryLocked(app: app)
        let windowEntries = buildSearchWindowIndexEntriesLocked(
            app: app,
            appSearchIndex: appEntry.searchIndex
        )
        var appEntries = base.appEntries
        if let index = appEntries.firstIndex(where: { $0.appID == app.id }) {
            appEntries[index] = appEntry
        } else {
            appEntries.append(appEntry)
        }
        let mergedWindowEntries = base.windowEntries.filter { $0.appID != app.id }
            + windowEntries
        stagingSearchIndex = RuntimeSearchIndexProjection(
            appEntries: appEntries,
            windowEntries: mergedWindowEntries,
            freshness: freshnessLocked(
                generatedAt: generatedAt,
                isCompleteForScope: false
            )
        )
        return stagingSearchIndex
    }

    private func stageSearchIndexCurrentAppWindowPayloadsLocked(
        _ payloads: [RuntimeCurrentAppWindowPayload],
        generatedAt: TimeInterval
    ) -> RuntimeSearchIndexProjection? {
        guard !payloads.isEmpty else { return nil }

        var stagedProjection: RuntimeSearchIndexProjection?
        for payload in payloads {
            stagedProjection = stageSearchIndexAppLocked(
                payload.candidate,
                generatedAt: generatedAt
            )
        }
        return stagedProjection
    }

    private func commitStagedSearchIndexLocked(
        clearsDirtyState: Bool,
        generatedAt: TimeInterval
    ) -> RuntimeSearchIndexProjection? {
        guard let staged = stagingSearchIndex else { return nil }
        markProjectionCommittedLocked()
        if clearsDirtyState {
            clearDirtyStateLocked()
        }
        committedSearchIndex = RuntimeSearchIndexProjection(
            appEntries: staged.appEntries,
            windowEntries: staged.windowEntries,
            freshness: freshnessLocked(generatedAt: generatedAt, isCompleteForScope: !isDirtyLocked)
        )
        stagingSearchIndex = nil
        return committedSearchIndex
    }

    @discardableResult
    func commitSearchFreshnessBarrierPayloads(
        _ payloads: [RuntimeCurrentAppWindowPayload],
        deferredRequestCount: Int,
        hasPendingRequests: Bool,
        generatedAt: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) -> RuntimeSearchFreshnessBarrierCommitResult {
        lock.lock()
        defer { lock.unlock() }

        let stagedSearchIndex = stageSearchIndexCurrentAppWindowPayloadsLocked(
            payloads,
            generatedAt: generatedAt
        )
        let canCommit = stagedSearchIndex != nil
            && deferredRequestCount == 0
            && !hasPendingRequests
        let committedSearchIndex = canCommit
            ? commitStagedSearchIndexLocked(clearsDirtyState: true, generatedAt: generatedAt)
            : nil
        return RuntimeSearchFreshnessBarrierCommitResult(
            stagedSearchIndex: stagedSearchIndex,
            committedSearchIndex: committedSearchIndex
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
        stagingSearchIndex = nil
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

    func markAppTerminated(appID: String, pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }

        guard shouldRemoveTerminatedAppLocked(appID: appID, pid: pid) else {
            dirtyPIDs.remove(pid)
            return
        }
        let survivingDirectoryEntries = appDirectoryEntriesLocked(forAppID: appID)
            .filter { $0.pid != pid }
        if !survivingDirectoryEntries.isEmpty {
            markAppInstanceTerminatedLocked(appID: appID, pid: pid)
            return
        }

        let hadAppSwitcherState = appSwitcherProjection?.apps.contains { $0.id == appID } == true
            || appSwitcherProjection?.contextsByID[appID] != nil
        let hadHomeState = homeSummaryProjection?.summaries.contains { $0.appID == appID } == true
        let hadCurrentAppState = currentAppWindowProjectionsByAppID[appID] != nil
        let hadCommittedSearchState = committedSearchIndex?.appEntries.contains { $0.appID == appID } == true
            || committedSearchIndex?.windowEntries.contains { $0.appID == appID } == true
        let hadStagingSearchState = stagingSearchIndex?.appEntries.contains { $0.appID == appID } == true
            || stagingSearchIndex?.windowEntries.contains { $0.appID == appID } == true
        let hadDirtyState = dirtyAppIDs.contains(appID)
            || dirtyPIDs.contains(pid)
            || pendingRepairScopes.contains { $0.contains(appID) }
        guard hadAppSwitcherState
            || hadHomeState
            || hadCurrentAppState
            || hadCommittedSearchState
            || hadStagingSearchState
            || hadDirtyState
        else {
            return
        }

        let generatedAt = Date.timeIntervalSinceReferenceDate
        generation.appLifecycle &+= 1
        markProjectionCommittedLocked()
        dirtyAppIDs.remove(appID)
        dirtyPIDs.remove(pid)
        pendingRepairScopes = pendingRepairScopes.filter { !$0.contains(appID) }
        currentAppWindowProjectionsByAppID.removeValue(forKey: appID)
        appDirectoryState.remove(appID: appID, pid: pid, generatedAt: generatedAt)
        if let projection = appSwitcherProjection {
            appSwitcherProjection = RuntimeAppSwitcherProjection(
                apps: projection.apps.filter { $0.id != appID },
                contextsByID: projection.contextsByID.filter { $0.key != appID },
                freshness: freshnessLocked(
                    generatedAt: generatedAt,
                    isCompleteForScope: !isDirtyLocked
                )
            )
        }
        if let summaries = homeSummaryProjection?.summaries.filter({ $0.appID != appID }) {
            homeSummaryProjection = RuntimeHomeSummaryProjection(
                summaries: summaries,
                freshness: freshnessLocked(
                    generatedAt: generatedAt,
                    isCompleteForScope: !isDirtyLocked
                )
            )
        }
        if let projection = committedSearchIndex {
            committedSearchIndex = projection.removingApp(
                appID,
                freshness: freshnessLocked(
                    generatedAt: generatedAt,
                    isCompleteForScope: !isDirtyLocked
                )
            )
        }
        if let projection = stagingSearchIndex {
            stagingSearchIndex = projection.removingApp(
                appID,
                freshness: freshnessLocked(
                    generatedAt: generatedAt,
                    isCompleteForScope: false
                )
            )
        }
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

    private func markAppInstanceTerminatedLocked(appID: String, pid: pid_t) {
        let generatedAt = Date.timeIntervalSinceReferenceDate
        generation.appLifecycle &+= 1
        markProjectionCommittedLocked()
        dirtyAppIDs.insert(appID)
        dirtyPIDs.remove(pid)
        pendingRepairScopes.insert("appTerminated:\(appID)")

        appDirectoryState.remove(pid: pid, generatedAt: generatedAt)
        if let projection = appSwitcherProjection {
            var contextsByID = projection.contextsByID
            if contextsByID[appID]?.runningApp.processIdentifier == pid {
                contextsByID.removeValue(forKey: appID)
            }
            appSwitcherProjection = RuntimeAppSwitcherProjection(
                apps: projection.apps,
                contextsByID: contextsByID,
                freshness: freshnessLocked(
                    generatedAt: generatedAt,
                    isCompleteForScope: !isDirtyLocked
                )
            )
        }
        if let projection = currentAppWindowProjectionsByAppID[appID],
           (
            projection.currentAppWindowPayload.summary.pid == pid
                || projection.currentAppWindowPayload.context.runningApp.processIdentifier == pid
           ) {
            currentAppWindowProjectionsByAppID.removeValue(forKey: appID)
        }
        if let projection = homeSummaryProjection {
            homeSummaryProjection = RuntimeHomeSummaryProjection(
                summaries: projection.summaries,
                freshness: freshnessLocked(
                    generatedAt: generatedAt,
                    isCompleteForScope: !isDirtyLocked
                )
            )
        }
        if let projection = committedSearchIndex {
            committedSearchIndex = RuntimeSearchIndexProjection(
                appEntries: projection.appEntries,
                windowEntries: projection.windowEntries,
                freshness: freshnessLocked(
                    generatedAt: generatedAt,
                    isCompleteForScope: !isDirtyLocked
                )
            )
        }
        if let projection = stagingSearchIndex {
            stagingSearchIndex = RuntimeSearchIndexProjection(
                appEntries: projection.appEntries,
                windowEntries: projection.windowEntries,
                freshness: freshnessLocked(
                    generatedAt: generatedAt,
                    isCompleteForScope: false
                )
            )
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

        if let projection = currentAppWindowProjectionsByAppID[appID] {
            return RuntimeHomeAppDetailProjection(
                currentAppWindowPayload: projection.currentAppWindowPayload
            )
        }
        guard
            let appProjection = appSwitcherProjection ?? appSwitcherProjectionFromAppDirectoryLocked(),
            let app = appProjection.apps.first(where: { $0.id == appID }),
            let context = appProjection.contextsByID[appID]
        else {
            return nil
        }
        return RuntimeHomeAppDetailProjection(
            summary: homeSummaryLocked(for: app, context: context),
            candidate: app,
            context: context
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
            && stagingSearchIndex == nil
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
            hasStagingSearchIndex: stagingSearchIndex != nil,
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

    private func upsertAppSwitcherProjectionLocked(
        _ payload: RuntimeCurrentAppWindowPayload,
        generatedAt: TimeInterval
    ) {
        var apps = appSwitcherProjection?.apps ?? []
        if let index = apps.firstIndex(where: { $0.id == payload.candidate.id }) {
            apps[index] = payload.candidate
        } else {
            apps.append(payload.candidate)
        }
        apps.sort { lhs, rhs in
            if lhs.lastActiveAt == rhs.lastActiveAt {
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            return lhs.lastActiveAt > rhs.lastActiveAt
        }

        var contextsByID = appSwitcherProjection?.contextsByID ?? [:]
        contextsByID[payload.context.appID] = payload.context
        appSwitcherProjection = RuntimeAppSwitcherProjection(
            apps: apps,
            contextsByID: contextsByID,
            freshness: freshnessLocked(generatedAt: generatedAt, isCompleteForScope: !isDirtyLocked)
        )
    }

    private func upsertHomeSummaryProjectionLocked(
        _ summary: RuntimeHomeAppSummary,
        generatedAt: TimeInterval
    ) {
        var summaries = homeSummaryProjection?.summaries
            ?? appSwitcherProjection?.apps.map { app in
                homeSummaryLocked(
                    for: app,
                    context: appSwitcherProjection?.contextsByID[app.id]
                )
            }
            ?? []
        if let index = summaries.firstIndex(where: { $0.appID == summary.appID }) {
            summaries[index] = summary
        } else {
            summaries.append(summary)
        }
        summaries.sort { lhs, rhs in
            if lhs.lastActiveAt == rhs.lastActiveAt {
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            return lhs.lastActiveAt > rhs.lastActiveAt
        }
        homeSummaryProjection = RuntimeHomeSummaryProjection(
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
