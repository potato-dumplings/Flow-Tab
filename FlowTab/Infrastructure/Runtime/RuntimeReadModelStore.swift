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

    var snapshot: RuntimeSnapshot {
        RuntimeSnapshot(apps: apps, contextsByID: contextsByID)
    }
}

struct RuntimeHomeSummaryProjection {
    let summaries: [RuntimeHomeAppSummary]
    var freshness: RuntimeProjectionFreshness

    func summary(for appID: String) -> RuntimeHomeAppSummary? {
        summaries.first { $0.appID == appID }
    }
}

struct RuntimeCurrentAppWindowProjection {
    let appID: String
    let snapshot: RuntimeHomeAppSnapshot
    var freshness: RuntimeProjectionFreshness
}

struct RuntimeReadModelDiagnostics: Equatable {
    let generation: RuntimeReadModelGeneration
    let dirtyAppIDs: Set<String>
    let dirtyPIDs: Set<pid_t>
    let dirtyCGWindowIDs: Set<CGWindowID>
    let pendingRepairScopes: Set<String>
    let hasAppSwitcherProjection: Bool
    let hasHomeSummaryProjection: Bool
    let currentAppWindowProjectionAppIDs: Set<String>
}

final class RuntimeReadModelStore: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = RuntimeReadModelGeneration()
    private var dirtyAppIDs: Set<String> = []
    private var dirtyPIDs: Set<pid_t> = []
    private var dirtyCGWindowIDs: Set<CGWindowID> = []
    private var pendingRepairScopes: Set<String> = []
    private var appSwitcherProjection: RuntimeAppSwitcherProjection?
    private var homeSummaryProjection: RuntimeHomeSummaryProjection?
    private var currentAppWindowProjectionsByAppID: [String: RuntimeCurrentAppWindowProjection] = [:]

    func commitAppSwitcherSnapshot(
        _ snapshot: RuntimeSnapshot,
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
            apps: snapshot.apps,
            contextsByID: snapshot.contextsByID,
            freshness: freshnessLocked(generatedAt: generatedAt, isCompleteForScope: !isDirtyLocked)
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
        var summaries = homeSummaryProjection?.summaries ?? []
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
            freshness: freshnessLocked(generatedAt: generatedAt, isCompleteForScope: true)
        )
    }

    func commitCurrentAppWindowSnapshot(
        _ snapshot: RuntimeHomeAppSnapshot,
        generatedAt: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) {
        lock.lock()
        defer { lock.unlock() }

        markProjectionCommittedLocked()
        clearDirtyStateForAppLocked(appID: snapshot.summary.appID, pid: snapshot.summary.pid)
        currentAppWindowProjectionsByAppID[snapshot.summary.appID] = RuntimeCurrentAppWindowProjection(
            appID: snapshot.summary.appID,
            snapshot: snapshot,
            freshness: freshnessLocked(generatedAt: generatedAt, isCompleteForScope: true)
        )
    }

    func markAppLifecycleDirty(appID: String, pid: pid_t, pendingScope: String) {
        lock.lock()
        defer { lock.unlock() }

        generation.appLifecycle &+= 1
        dirtyAppIDs.insert(appID)
        dirtyPIDs.insert(pid)
        pendingRepairScopes.insert(pendingScope)
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

        generation.appLifecycle &+= 1
        dirtyAppIDs.remove(appID)
        dirtyPIDs.remove(pid)
        pendingRepairScopes = pendingRepairScopes.filter { !$0.contains(appID) }
        currentAppWindowProjectionsByAppID.removeValue(forKey: appID)
        if let summaries = homeSummaryProjection?.summaries.filter({ $0.appID != appID }) {
            homeSummaryProjection = RuntimeHomeSummaryProjection(
                summaries: summaries,
                freshness: freshnessLocked(
                    generatedAt: Date.timeIntervalSinceReferenceDate,
                    isCompleteForScope: !isDirtyLocked
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

    func readCurrentAppWindowProjection(appID: String) -> RuntimeCurrentAppWindowProjection? {
        lock.lock()
        defer { lock.unlock() }

        guard var projection = currentAppWindowProjectionsByAppID[appID] else { return nil }
        let isScopeDirty = dirtyAppIDs.contains(appID)
            || dirtyPIDs.contains(projection.snapshot.summary.pid)
            || !dirtyCGWindowIDs.isEmpty
            || !pendingRepairScopes.isEmpty
        projection.freshness = freshnessLocked(
            generatedAt: projection.freshness.generatedAt,
            isCompleteForScope: !isScopeDirty
        )
        return projection
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
            currentAppWindowProjectionAppIDs: Set(currentAppWindowProjectionsByAppID.keys)
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
}
