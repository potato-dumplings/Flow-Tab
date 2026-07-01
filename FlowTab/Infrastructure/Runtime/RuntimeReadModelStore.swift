import CoreGraphics
import Foundation
import FlowTabCore

final class RuntimeReadModelStore: @unchecked Sendable {
    private enum CurrentAppWindowPreservationSourceKind {
        case currentAppProjection
        case appSwitcherProjection
    }

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
    private var activationTargetProjection: RuntimeActivationTargetProjection?
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
        clearDirtyStateForCompletedCGWindowRequestsLocked(
            clearsDirtyCGWindowIDs,
            hasCompleteWindowCoverage: payload.hasCompleteWindowCoverage
        )
        let normalizedPayload = mainTableAppSwitcherProjectionPayloadByNormalizingPresentationLocked(payload)
        let isCompleteForScope = !isDirtyLocked && normalizedPayload.hasCompleteWindowCoverage
        appSwitcherProjection = RuntimeAppSwitcherProjection(
            apps: normalizedPayload.apps,
            contextsByID: normalizedPayload.contextsByID,
            freshness: freshnessLocked(generatedAt: generatedAt, isCompleteForScope: isCompleteForScope)
        )
        homeSummaryProjection = RuntimeHomeSummaryProjection(
            summaries: normalizedPayload.homeSummaries,
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
        clearsDirtyState: Bool = false,
        generatedAt: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) {
        lock.lock()
        defer { lock.unlock() }

        let preservedPayload = currentAppWindowPayloadByPreservingPriorCommittedWindowsLocked(payload)
        let normalizedPayload = currentAppWindowPayloadByNormalizingPresentationLocked(preservedPayload)
        let committedPayload = currentAppWindowPayloadByApplyingActivationReadbackLocked(normalizedPayload)
        markProjectionCommittedLocked()
        if clearsDirtyState {
            clearDirtyStateForAppLocked(appID: committedPayload.summary.appID, pid: committedPayload.summary.pid)
            clearDirtyStateForProjectedCGWindowsLocked(in: committedPayload)
        }
        currentAppWindowProjectionsByAppID[committedPayload.summary.appID] = RuntimeCurrentAppWindowProjection(
            appID: committedPayload.summary.appID,
            currentAppWindowPayload: committedPayload,
            freshness: freshnessLocked(
                generatedAt: generatedAt,
                isCompleteForScope: clearsDirtyState
            )
        )
    }

    @discardableResult
    func commitSearchFreshnessBarrierFromMainTablePayload(
        _ payload: RuntimeSearchIndexPayload,
        deferredRequestCount: Int,
        hasPendingRequests: Bool,
        generatedAt: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) -> RuntimeSearchIndexProjection? {
        lock.lock()
        defer { lock.unlock() }

        guard deferredRequestCount == 0,
              !hasPendingRequests,
              payload.hasCompleteWindowCoverage,
              !isDirtyLocked
        else {
            return nil
        }
        markProjectionCommittedLocked()
        clearDirtyStateLocked()
        committedSearchIndex = RuntimeSearchIndexProjection(
            appEntries: payload.appEntries,
            windowEntries: payload.windowEntries,
            freshness: freshnessLocked(generatedAt: generatedAt, isCompleteForScope: true)
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

    func markWindowFocusVerified(
        _ verification: RuntimeWindowFocusVerification,
        affectedCGWindowIDs: Set<CGWindowID>,
        generatedAt: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) {
        lock.lock()
        defer { lock.unlock() }

        generation.axDirty &+= 1
        dirtyAppIDs.insert(verification.appID)
        dirtyPIDs.insert(verification.ownerPID)
        dirtyCGWindowIDs.formUnion(affectedCGWindowIDs)
        pendingRepairScopes.insert("activationVerified:\(verification.appID)")
        activationTargetProjection = RuntimeActivationTargetProjection(
            verification: verification,
            affectedCGWindowIDs: affectedCGWindowIDs,
            freshness: freshnessLocked(generatedAt: generatedAt, isCompleteForScope: false)
        )
    }

    func markWindowFocusReadbackMismatch(
        _ diagnostic: WindowBindingReadbackDiagnostic,
        affectedCGWindowIDs: Set<CGWindowID>,
        generatedAt _: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) {
        lock.lock()
        defer { lock.unlock() }

        generation.axDirty &+= 1
        dirtyAppIDs.insert(diagnostic.appID)
        dirtyPIDs.insert(diagnostic.ownerPID)
        dirtyCGWindowIDs.formUnion(affectedCGWindowIDs)
        pendingRepairScopes.insert("activationReadbackMismatch:\(diagnostic.appID)")
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

        return true
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

    func readActivationTargetProjection() -> RuntimeActivationTargetProjection? {
        lock.lock()
        defer { lock.unlock() }

        guard var projection = activationTargetProjection else { return nil }
        projection.freshness = freshnessLocked(
            generatedAt: projection.freshness.generatedAt,
            isCompleteForScope: false
        )
        return projection
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
        let isScopeDirty = isCurrentAppWindowProjectionScopeDirtyLocked(projection)
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
            hasActivationTargetProjection: activationTargetProjection != nil,
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

    private func clearDirtyStateForCompletedCGWindowRequestsLocked(
        _ requestedCGWindowIDs: Set<CGWindowID>,
        hasCompleteWindowCoverage: Bool
    ) {
        guard hasCompleteWindowCoverage, !requestedCGWindowIDs.isEmpty else { return }
        dirtyCGWindowIDs.subtract(requestedCGWindowIDs)
        if dirtyCGWindowIDs.isEmpty {
            pendingRepairScopes.remove("spaceTopology")
            spaceTopologySignatureSummary = nil
        }
    }

    private func clearDirtyStateForProjectedCGWindowsLocked(in payload: RuntimeCurrentAppWindowPayload) {
        let projectedCGWindowIDs = currentAppProjectedCGWindowIDs(in: payload)
        guard !projectedCGWindowIDs.isEmpty else { return }
        dirtyCGWindowIDs.subtract(projectedCGWindowIDs)
        if dirtyCGWindowIDs.isEmpty {
            pendingRepairScopes.remove("spaceTopology")
            spaceTopologySignatureSummary = nil
        }
    }

    private func currentAppWindowPayloadByApplyingActivationReadbackLocked(
        _ payload: RuntimeCurrentAppWindowPayload
    ) -> RuntimeCurrentAppWindowPayload {
        guard let activationTargetProjection else { return payload }
        guard activationTargetProjection.appID == payload.summary.appID else { return payload }
        guard activationTargetProjection.ownerPID == payload.summary.pid
            || activationTargetProjection.ownerPID == payload.context.runningApp.processIdentifier
        else {
            return payload
        }
        guard payload.candidate.windows.count > 1 else { return payload }

        let readbackCGWindowIDs = Set([
            activationTargetProjection.focusedCGWindowID,
            activationTargetProjection.targetCGWindowID
        ].compactMap { $0 })
        guard !readbackCGWindowIDs.isEmpty || !activationTargetProjection.windowID.isEmpty else {
            return payload
        }
        guard let verifiedWindowID = payload.candidate.windows.first(where: { window in
            if window.id == activationTargetProjection.windowID {
                return true
            }
            return payload.context.windowsByID[window.id]?.cgWindowID.map {
                readbackCGWindowIDs.contains($0)
            } ?? false
        })?.id else {
            return payload
        }

        let baseLastActiveAt = payload.candidate.windows.map(\.lastActiveAt).max() ?? payload.candidate.lastActiveAt
        let priorOrderByWindowID = currentAppWindowProjectionPriorOrderLocked(
            for: payload,
            excludingWindowID: verifiedWindowID
        )
        let originalOrderByWindowID = Dictionary(
            uniqueKeysWithValues: payload.candidate.windows.enumerated().map { index, window in
                (window.id, index)
            }
        )
        let reorderedWindows = payload.candidate.windows.map { window in
            guard window.id == verifiedWindowID else { return window }
            return WindowCandidate(
                id: window.id,
                title: window.title,
                isMinimized: window.isMinimized,
                lastActiveAt: baseLastActiveAt + 1
            )
        }.sorted { lhs, rhs in
            if lhs.id == verifiedWindowID {
                return true
            }
            if rhs.id == verifiedWindowID {
                return false
            }
            let lhsPriorOrder = priorOrderByWindowID[lhs.id]
            let rhsPriorOrder = priorOrderByWindowID[rhs.id]
            switch (lhsPriorOrder, rhsPriorOrder) {
            case let (.some(lhsPriorOrder), .some(rhsPriorOrder)) where lhsPriorOrder != rhsPriorOrder:
                return lhsPriorOrder < rhsPriorOrder
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return (originalOrderByWindowID[lhs.id] ?? .max)
                    < (originalOrderByWindowID[rhs.id] ?? .max)
            }
        }
        let candidate = AppSwitchCandidate(
            id: payload.candidate.id,
            displayName: payload.candidate.displayName,
            groupID: payload.candidate.groupID,
            lastActiveAt: payload.candidate.lastActiveAt,
            windows: reorderedWindows
        )
        return RuntimeCurrentAppWindowPayload(
            summary: payload.summary,
            candidate: candidate,
            context: payload.context,
            appDirectoryEntries: payload.appDirectoryEntries
        )
    }

    private func mainTableAppSwitcherProjectionPayloadByNormalizingPresentationLocked(
        _ payload: RuntimeAppSwitcherProjectionPayload
    ) -> RuntimeAppSwitcherProjectionPayload {
        guard !payload.apps.isEmpty else { return payload }

        var contextsByID = payload.contextsByID
        let apps = payload.apps.map { app -> AppSwitchCandidate in
            guard let context = contextsByID[app.id] else { return app }
            let normalized = appCandidateAndContextByNormalizingPresentationLocked(
                candidate: app,
                context: context,
                appName: app.displayName,
                stage: "read-model-app-switcher-normalization"
            )
            contextsByID[app.id] = normalized.context
            return normalized.candidate
        }
        let homeSummaries = payload.homeSummaries.map { summary -> RuntimeHomeAppSummary in
            guard let app = apps.first(where: { $0.id == summary.appID }) else { return summary }
            return RuntimeHomeAppSummary(
                appID: summary.appID,
                displayName: summary.displayName,
                groupID: summary.groupID,
                lastActiveAt: summary.lastActiveAt,
                windowCount: app.windows.count,
                pid: summary.pid,
                bundleIdentifier: summary.bundleIdentifier,
                bundleURL: summary.bundleURL
            )
        }
        return RuntimeAppSwitcherProjectionPayload(
            apps: apps,
            contextsByID: contextsByID,
            homeSummaries: homeSummaries,
            hasCompleteWindowCoverage: payload.hasCompleteWindowCoverage,
            coverageDiagnostics: payload.coverageDiagnostics
        )
    }

    private func currentAppWindowPayloadByNormalizingPresentationLocked(
        _ payload: RuntimeCurrentAppWindowPayload
    ) -> RuntimeCurrentAppWindowPayload {
        let normalized = appCandidateAndContextByNormalizingPresentationLocked(
            candidate: payload.candidate,
            context: payload.context,
            appName: payload.candidate.displayName,
            stage: "read-model-current-app-normalization"
        )
        guard normalized.candidate.windows.map(\.id) != payload.candidate.windows.map(\.id) else {
            return payload
        }

        let summary = RuntimeHomeAppSummary(
            appID: payload.summary.appID,
            displayName: payload.summary.displayName,
            groupID: payload.summary.groupID,
            lastActiveAt: payload.summary.lastActiveAt,
            windowCount: normalized.candidate.windows.count,
            pid: payload.summary.pid,
            bundleIdentifier: payload.summary.bundleIdentifier,
            bundleURL: payload.summary.bundleURL
        )
        return RuntimeCurrentAppWindowPayload(
            summary: summary,
            candidate: normalized.candidate,
            context: normalized.context,
            appDirectoryEntries: payload.appDirectoryEntries
        )
    }

    private func appCandidateAndContextByNormalizingPresentationLocked(
        candidate: AppSwitchCandidate,
        context: RuntimeAppContext,
        appName: String,
        stage: String
    ) -> (candidate: AppSwitchCandidate, context: RuntimeAppContext) {
        guard candidate.windows.count > 1 else {
            return (candidate, context)
        }

        let entries = candidate.windows.compactMap { window -> RuntimeWindowListEntry? in
            guard let windowContext = context.windowsByID[window.id] else { return nil }
            return RuntimeWindowListEntry(
                windowID: window.id,
                title: window.title,
                isMinimized: window.isMinimized,
                ownerPID: windowContext.ownerPID,
                cgWindowID: windowContext.cgWindowID,
                activationHandleID: windowContext.activationHandleID,
                axWindow: windowContext.axWindow,
                frame: windowContext.frame,
                spaceIDs: windowContext.spaceIDs,
                isOnscreen: false,
                allowsPublicAXRecovery: windowContext.allowsPublicAXRecovery,
                hasStickyBinding: windowContext.hasStickyBinding,
                lastConfirmationSource: windowContext.lastConfirmationSource,
                bindingConfidenceOverride: windowContext.bindingConfidenceOverride,
                bindingAllowedActionsOverride: windowContext.bindingAllowedActionsOverride,
                bindingCandidateCount: windowContext.bindingCandidateCount,
                spaceEvidence: windowContext.spaceEvidence
            )
        }
        guard !entries.isEmpty else {
            return (candidate, context)
        }

        let knownCGWindowsByID = Dictionary(
            uniqueKeysWithValues: entries.compactMap { entry -> (CGWindowID, RuntimeCGWindowEntry)? in
                guard let cgWindowID = entry.cgWindowID else { return nil }
                return (
                    cgWindowID,
                    RuntimeCGWindowEntry(
                        id: cgWindowID,
                        title: entry.title,
                        bounds: entry.frame,
                        isOnscreen: entry.isOnscreen,
                        spaceIDs: entry.spaceIDs
                    )
                )
            }
        )
        let hasFullscreenTopology = knownCGWindowsByID.values.contains {
            RuntimeWindowTopologyClassifier.isLikelyOffDesktopFullscreenContent(
                bounds: $0.bounds,
                spaceIDs: $0.spaceIDs
            )
        }
        let cgWindowOrderByID = Dictionary(
            uniqueKeysWithValues: entries.enumerated().compactMap { index, entry in
                entry.cgWindowID.map { ($0, index) }
            }
        )
        let filteredEntries = RuntimeWindowPresentationFilter.filteredAndOrderedEntriesForPresentation(
            entries,
            allEntriesForHostArtifacts: entries,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName,
            hasFullscreenTopology: hasFullscreenTopology,
            cgWindowOrderByID: cgWindowOrderByID,
            stage: stage,
            finalStage: "\(stage)-final"
        )
        guard filteredEntries.map(\.windowID) != candidate.windows.map(\.id) else {
            return (candidate, context)
        }

        let windowByID = Dictionary(uniqueKeysWithValues: candidate.windows.map { ($0.id, $0) })
        let windows = filteredEntries.compactMap { windowByID[$0.windowID] }
        let retainedWindowIDs = Set(windows.map(\.id))
        let windowsByID = context.windowsByID.filter { retainedWindowIDs.contains($0.key) }
        return (
            AppSwitchCandidate(
                id: candidate.id,
                displayName: candidate.displayName,
                groupID: candidate.groupID,
                lastActiveAt: candidate.lastActiveAt,
                windows: windows
            ),
            RuntimeAppContext(
                appID: context.appID,
                runningApp: context.runningApp,
                windowsByID: windowsByID
            )
        )
    }

    private func currentAppWindowPayloadByPreservingPriorCommittedWindowsLocked(
        _ payload: RuntimeCurrentAppWindowPayload
    ) -> RuntimeCurrentAppWindowPayload {
        let priorSources = currentAppWindowPreservationSourcesLocked(for: payload)
        guard !priorSources.isEmpty else { return payload }
        let projectedWindowIDs = Set(payload.candidate.windows.map(\.id))
        var projectedCGWindowIDs = Set(payload.context.windowsByID.values.compactMap(\.cgWindowID))
        var preservedWindows: [WindowCandidate] = []
        var preservedContextsByID: [String: RuntimeWindowContext] = [:]
        var preservedWindowIDs: Set<String> = []
        for source in priorSources {
            for window in source.candidate.windows {
                guard !projectedWindowIDs.contains(window.id),
                      !preservedWindowIDs.contains(window.id),
                      let priorContext = source.context.windowsByID[window.id]
                else {
                    continue
                }
                guard currentAppWindowPreservationAllowsActivationLocked(priorContext, from: source.kind) else {
                    continue
                }
                if let cgWindowID = priorContext.cgWindowID {
                    guard !projectedCGWindowIDs.contains(cgWindowID),
                          !dirtyCGWindowIDs.contains(cgWindowID)
                    else {
                        continue
                    }
                    projectedCGWindowIDs.insert(cgWindowID)
                }
                preservedWindows.append(window)
                preservedContextsByID[window.id] = priorContext
                preservedWindowIDs.insert(window.id)
            }
        }
        guard !preservedWindows.isEmpty else { return payload }

        var windowsByID = payload.context.windowsByID
        for (windowID, context) in preservedContextsByID {
            windowsByID[windowID] = context
        }
        let candidate = AppSwitchCandidate(
            id: payload.candidate.id,
            displayName: payload.candidate.displayName,
            groupID: payload.candidate.groupID,
            lastActiveAt: payload.candidate.lastActiveAt,
            windows: payload.candidate.windows + preservedWindows
        )
        let summary = RuntimeHomeAppSummary(
            appID: payload.summary.appID,
            displayName: payload.summary.displayName,
            groupID: payload.summary.groupID,
            lastActiveAt: payload.summary.lastActiveAt,
            windowCount: candidate.windows.count,
            pid: payload.summary.pid,
            bundleIdentifier: payload.summary.bundleIdentifier,
            bundleURL: payload.summary.bundleURL
        )
        return RuntimeCurrentAppWindowPayload(
            summary: summary,
            candidate: candidate,
            context: RuntimeAppContext(
                appID: payload.context.appID,
                runningApp: payload.context.runningApp,
                windowsByID: windowsByID
            ),
            appDirectoryEntries: payload.appDirectoryEntries
        )
    }

    private func currentAppWindowPreservationSourcesLocked(
        for payload: RuntimeCurrentAppWindowPayload
    ) -> [(kind: CurrentAppWindowPreservationSourceKind, candidate: AppSwitchCandidate, context: RuntimeAppContext)] {
        var sources: [(kind: CurrentAppWindowPreservationSourceKind, candidate: AppSwitchCandidate, context: RuntimeAppContext)] = []
        if let priorPayload = currentAppWindowProjectionsByAppID[payload.summary.appID]?.currentAppWindowPayload,
           currentAppWindowPreservationSourceMatchesProcessLocked(
            sourcePID: priorPayload.summary.pid,
            sourceContext: priorPayload.context,
            payload: payload
           ) {
            sources.append((.currentAppProjection, priorPayload.candidate, priorPayload.context))
        }
        if let appSwitcherProjection,
           let appSwitcherCandidate = appSwitcherProjection.apps.first(where: { $0.id == payload.summary.appID }),
           let appSwitcherContext = appSwitcherProjection.contextsByID[payload.summary.appID],
           currentAppWindowPreservationSourceMatchesProcessLocked(
            sourcePID: appSwitcherContext.runningApp.processIdentifier,
            sourceContext: appSwitcherContext,
            payload: payload
           ) {
            sources.append((.appSwitcherProjection, appSwitcherCandidate, appSwitcherContext))
        }
        return sources
    }

    private func currentAppWindowPreservationAllowsActivationLocked(
        _ context: RuntimeWindowContext,
        from sourceKind: CurrentAppWindowPreservationSourceKind
    ) -> Bool {
        if sourceKind == .appSwitcherProjection {
            return context.bindingAllowedActions.contains(.useForAXActivation)
        }
        return context.bindingAllowedActions.contains(.useForAXActivation)
            || context.bindingAllowedActions.contains(.useForCGActivationFallback)
    }

    private func currentAppWindowPreservationSourceMatchesProcessLocked(
        sourcePID: pid_t,
        sourceContext: RuntimeAppContext,
        payload: RuntimeCurrentAppWindowPayload
    ) -> Bool {
        sourcePID == payload.summary.pid
            || sourcePID == payload.context.runningApp.processIdentifier
            || sourceContext.runningApp.processIdentifier == payload.summary.pid
            || sourceContext.runningApp.processIdentifier == payload.context.runningApp.processIdentifier
    }

    private func currentAppWindowProjectionPriorOrderLocked(
        for payload: RuntimeCurrentAppWindowPayload,
        excludingWindowID verifiedWindowID: String
    ) -> [String: Int] {
        guard let priorPayload = currentAppWindowProjectionsByAppID[payload.summary.appID]?.currentAppWindowPayload
        else {
            return [:]
        }
        guard priorPayload.summary.pid == payload.summary.pid
            || priorPayload.context.runningApp.processIdentifier == payload.context.runningApp.processIdentifier
        else {
            return [:]
        }

        let priorOrderByWindowID = Dictionary(
            uniqueKeysWithValues: priorPayload.candidate.windows.enumerated().map { index, window in
                (window.id, index)
            }
        )
        var priorOrderByCGWindowID: [CGWindowID: Int] = [:]
        for window in priorPayload.candidate.windows {
            guard let order = priorOrderByWindowID[window.id],
                  let cgWindowID = priorPayload.context.windowsByID[window.id]?.cgWindowID
            else {
                continue
            }
            priorOrderByCGWindowID[cgWindowID] = priorOrderByCGWindowID[cgWindowID] ?? order
        }
        var resolvedOrderByWindowID: [String: Int] = [:]
        for window in payload.candidate.windows where window.id != verifiedWindowID {
            if let order = priorOrderByWindowID[window.id] {
                resolvedOrderByWindowID[window.id] = order
                continue
            }
            if let cgWindowID = payload.context.windowsByID[window.id]?.cgWindowID,
               let order = priorOrderByCGWindowID[cgWindowID] {
                resolvedOrderByWindowID[window.id] = order
            }
        }
        return resolvedOrderByWindowID
    }

    private func isCurrentAppWindowProjectionScopeDirtyLocked(
        _ projection: RuntimeCurrentAppWindowProjection
    ) -> Bool {
        let payload = projection.currentAppWindowPayload
        if dirtyAppIDs.contains(payload.summary.appID)
            || dirtyPIDs.contains(payload.summary.pid)
            || pendingRepairScopes.contains(where: { $0.contains(payload.summary.appID) }) {
            return true
        }

        guard !dirtyCGWindowIDs.isEmpty else { return false }
        let projectedCGWindowIDs = currentAppProjectedCGWindowIDs(in: payload)
        return projectedCGWindowIDs.isEmpty
            || !dirtyCGWindowIDs.isDisjoint(with: projectedCGWindowIDs)
    }

    private func currentAppProjectedCGWindowIDs(
        in payload: RuntimeCurrentAppWindowPayload
    ) -> Set<CGWindowID> {
        Set(payload.context.windowsByID.values.compactMap(\.cgWindowID))
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
        let sortedEntries = Self.sortedAppDirectoryEntriesForProjection(
            selectedEntries,
            rankByPID: rankByPID
        )
        let apps = sortedEntries.enumerated().map { index, entry in
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
        let contextsByID = Dictionary(
            uniqueKeysWithValues: sortedEntries.compactMap { entry in
                entry.runningApplication.map { runningApp in
                    (
                        entry.appID,
                        RuntimeAppContext(
                            appID: entry.appID,
                            runningApp: runningApp,
                            windowsByID: [:]
                        )
                    )
                }
            }
        )
        return RuntimeAppSwitcherProjection(
            apps: apps,
            contextsByID: contextsByID,
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

}
