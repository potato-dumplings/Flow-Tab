import AppKit
import CoreGraphics
import Foundation
import FlowTabCore

struct RuntimeReadModelGeneration: Equatable {
    var appLifecycle: UInt64 = 0
    var cg: UInt64 = 0
    var space: UInt64 = 0
    var axDirty: UInt64 = 0
    var projection: UInt64 = 0
}

struct RuntimeProjectionFreshness: Equatable {
    let generatedAt: TimeInterval
    let sourceGeneration: RuntimeReadModelGeneration
    let dirtyAppIDs: Set<String>
    let dirtyPIDs: Set<pid_t>
    let dirtyCGWindowIDs: Set<CGWindowID>
    let pendingRepairScopes: Set<String>
    let isCompleteForScope: Bool

    var isDirty: Bool {
        !dirtyAppIDs.isEmpty
            || !dirtyPIDs.isEmpty
            || !dirtyCGWindowIDs.isEmpty
            || !pendingRepairScopes.isEmpty
    }
}

struct RuntimeAppSwitcherProjection {
    let apps: [AppSwitchCandidate]
    let contextsByID: [String: RuntimeAppContext]
    var freshness: RuntimeProjectionFreshness

    var appCycleApps: [AppSwitchCandidate] {
        guard !freshness.isCompleteForScope else { return apps }
        let suppressesAllWindowLists = !freshness.dirtyCGWindowIDs.isEmpty
            || (!freshness.pendingRepairScopes.isEmpty && freshness.dirtyAppIDs.isEmpty)
        return apps.map { app -> AppSwitchCandidate in
            guard suppressesAllWindowLists || freshness.dirtyAppIDs.contains(app.id) else {
                return app
            }
            var app = app
            app.windows = []
            return app
        }
    }
}

struct RuntimeHomeSummaryProjection {
    let summaries: [RuntimeHomeAppSummary]
    var freshness: RuntimeProjectionFreshness

    func summary(for appID: String) -> RuntimeHomeAppSummary? {
        summaries.first { $0.appID == appID }
    }
}

struct RuntimeHomeAppDetailProjection {
    let summary: RuntimeHomeAppSummary
    let candidate: AppSwitchCandidate
    let context: RuntimeAppContext

    init(summary: RuntimeHomeAppSummary, candidate: AppSwitchCandidate, context: RuntimeAppContext) {
        self.summary = summary
        self.candidate = candidate
        self.context = context
    }

    init(currentAppWindowPayload payload: RuntimeCurrentAppWindowPayload) {
        self.init(
            summary: payload.summary,
            candidate: payload.candidate,
            context: payload.context
        )
    }
}

struct RuntimeAppDirectoryProjection {
    let entries: [RuntimeAppDirectoryEntry]
    var freshness: RuntimeProjectionFreshness

    func entries(forAppID appID: String) -> [RuntimeAppDirectoryEntry] {
        entries.filter { $0.appID == appID }
    }
}

struct RuntimeCurrentAppWindowProjection {
    let appID: String
    let currentAppWindowPayload: RuntimeCurrentAppWindowPayload
    var freshness: RuntimeProjectionFreshness

    init(
        appID: String,
        currentAppWindowPayload: RuntimeCurrentAppWindowPayload,
        freshness: RuntimeProjectionFreshness
    ) {
        self.appID = appID
        self.currentAppWindowPayload = currentAppWindowPayload
        self.freshness = freshness
    }

}

struct RuntimeReadModelDiagnostics: Equatable {
    let generation: RuntimeReadModelGeneration
    let dirtyAppIDs: Set<String>
    let dirtyPIDs: Set<pid_t>
    let dirtyCGWindowIDs: Set<CGWindowID>
    let pendingRepairScopes: Set<String>
    let hasAppSwitcherProjection: Bool
    let hasHomeSummaryProjection: Bool
    let hasAppDirectoryProjection: Bool
    let hasCommittedSearchIndex: Bool
    let hasStagingSearchIndex: Bool
    let currentAppWindowProjectionAppIDs: Set<String>
    let appDirectoryEntryPIDs: Set<pid_t>

    var hasDirtyState: Bool {
        !dirtyAppIDs.isEmpty
            || !dirtyPIDs.isEmpty
            || !dirtyCGWindowIDs.isEmpty
            || !pendingRepairScopes.isEmpty
    }
}

struct RuntimeFullRepairProjectionCommitSummary {
    var coldStartCommittedCount = 0
    var degradedCommittedCount = 0
}

final class RuntimeReadModelStore: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = RuntimeReadModelGeneration()
    private var dirtyAppIDs: Set<String> = []
    private var dirtyPIDs: Set<pid_t> = []
    private var dirtyCGWindowIDs: Set<CGWindowID> = []
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
    func commitFullRepairProjectionPayload(
        _ payload: RuntimeFullRepairProjectionPayload,
        generatedAt: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) -> RuntimeFullRepairProjectionCommitSummary {
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
        replaceAppDirectoryStateLocked(
            entries: payload.appDirectoryEntries,
            generatedAt: generatedAt
        )
        if clearsDirtyState {
            committedSearchIndex = buildSearchIndexLocked(
                apps: payload.apps,
                generatedAt: generatedAt,
                isCompleteForScope: true
            )
            stagingSearchIndex = nil
        }
        return RuntimeFullRepairProjectionCommitSummary(
            coldStartCommittedCount: clearsDirtyState ? 1 : 0,
            degradedCommittedCount: clearsDirtyState ? 0 : 1
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
        generatedAt: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) {
        lock.lock()
        defer { lock.unlock() }

        markProjectionCommittedLocked()
        clearDirtyStateForAppLocked(appID: payload.summary.appID, pid: payload.summary.pid)
        currentAppWindowProjectionsByAppID[payload.summary.appID] = RuntimeCurrentAppWindowProjection(
            appID: payload.summary.appID,
            currentAppWindowPayload: payload,
            freshness: freshnessLocked(generatedAt: generatedAt, isCompleteForScope: true)
        )
        upsertAppDirectoryStateLocked(
            entries: payload.appDirectoryEntries,
            generatedAt: generatedAt
        )
        upsertHomeSummaryProjectionLocked(payload.summary, generatedAt: generatedAt)
        upsertAppSwitcherProjectionLocked(payload, generatedAt: generatedAt)
    }

    func stageSearchIndexApps(
        _ apps: [AppSwitchCandidate],
        generatedAt: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) {
        lock.lock()
        defer { lock.unlock() }

        stagingSearchIndex = buildSearchIndexLocked(
            apps: apps,
            generatedAt: generatedAt,
            isCompleteForScope: false
        )
    }

    @discardableResult
    func stageSearchIndexApp(
        _ app: AppSwitchCandidate,
        generatedAt: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) -> RuntimeSearchIndexProjection? {
        lock.lock()
        defer { lock.unlock() }

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

    @discardableResult
    func stageSearchIndexCurrentAppWindowPayloads(
        _ payloads: [RuntimeCurrentAppWindowPayload],
        generatedAt: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) -> RuntimeSearchIndexProjection? {
        guard !payloads.isEmpty else { return nil }

        var stagedProjection: RuntimeSearchIndexProjection?
        for payload in payloads {
            stagedProjection = stageSearchIndexApp(
                payload.candidate,
                generatedAt: generatedAt
            )
        }
        return stagedProjection
    }

    @discardableResult
    func commitStagedSearchIndex(
        clearsDirtyState: Bool = true,
        generatedAt: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) -> RuntimeSearchIndexProjection? {
        lock.lock()
        defer { lock.unlock() }

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

    func markSpaceTopologyDirty(affectedCGWindowIDs: Set<CGWindowID>, pendingScope: String) {
        lock.lock()
        defer { lock.unlock() }

        generation.space &+= 1
        dirtyCGWindowIDs.formUnion(affectedCGWindowIDs)
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

        guard var projection = appSwitcherProjection else { return nil }
        projection.freshness = freshnessLocked(
            generatedAt: projection.freshness.generatedAt,
            isCompleteForScope: !isDirtyLocked
        )
        return projection
    }

    func readHomeSummaryProjection() -> RuntimeHomeSummaryProjection? {
        lock.lock()
        defer { lock.unlock() }

        guard var projection = homeSummaryProjection else { return nil }
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
        projection.freshness = freshnessLocked(
            generatedAt: projection.freshness.generatedAt,
            isCompleteForScope: !isDirtyLocked
        )
        return RuntimeSearchIndexRead(
            projection: projection,
            readiness: projection.freshness.isCompleteForScope
                ? .currentGenerationCommitted
                : .staleCommitted
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
            pendingRepairScopes: pendingRepairScopes,
            hasAppSwitcherProjection: appSwitcherProjection != nil,
            hasHomeSummaryProjection: homeSummaryProjection != nil,
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
