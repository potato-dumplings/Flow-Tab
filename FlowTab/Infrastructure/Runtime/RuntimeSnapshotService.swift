import CoreGraphics
import Foundation
import FlowTabCore

let sharedRuntimeSnapshotService = RuntimeSnapshotService()

enum RuntimeProjectionMaintenanceReason: String, Sendable {
    case switcherSessionStarted
    case searchFreshnessBarrier
}

protocol RuntimeSnapshotServing: Sendable {
    func fallbackRuntimeSnapshot() -> RuntimeSnapshot
    func lightweightAppSnapshot() -> RuntimeSnapshot
    func homeAppSummaries() async -> [RuntimeHomeAppSummary]
    func homeAppSummary(for appID: String) async -> RuntimeHomeAppSummary?
    func homeAppSnapshot(for appID: String) async -> RuntimeHomeAppSnapshot?
    func readAppSwitcherProjection() -> RuntimeAppSwitcherProjection?
    func readHomeSummaryProjection() -> RuntimeHomeSummaryProjection?
    func readCurrentAppWindowProjection(appID: String) -> RuntimeCurrentAppWindowProjection?
    func readCommittedSearchIndexProjection() -> RuntimeSearchIndexProjection?
    func readCommittedSearchIndexForSearch() -> RuntimeSearchIndexRead
    func runtimeReadModelDiagnostics() -> RuntimeReadModelDiagnostics
    func requestAppSwitcherProjectionMaintenance(reason: RuntimeProjectionMaintenanceReason)
    func requestSearchIndexFreshnessBarrier(reason: RuntimeProjectionMaintenanceReason)
    func currentCGWindowsByPID() -> [pid_t: [RuntimeSnapshotProvider.CGWindowEntry]]
    func signalSpaceTopologyChanged()
    func signalAppLaunched(appID: String, pid: pid_t)
    func signalAppWindowsChanged(appID: String, pid: pid_t)
    func signalAXWindowDestroyed(appID: String, pid: pid_t, axWindowID: String)
    func signalAppTerminated(appID: String, pid: pid_t)
    func signalWindowFocusVerified(_ verification: RuntimeWindowFocusVerification)
    func signalWindowFocusVerified(appID: String, pid: pid_t)
    func isLikelyTransientAXRebuild(for pid: pid_t) -> Bool
}

final class RuntimeSnapshotService: RuntimeSnapshotServing, @unchecked Sendable {
    enum ReconciliationExecutionOutcome {
        case completed
        case completedWithRepairedSnapshots([RuntimeHomeAppSnapshot])
        case transientEmptyAXSnapshot

        var repairedSnapshots: [RuntimeHomeAppSnapshot] {
            switch self {
            case .completed:
                []
            case let .completedWithRepairedSnapshots(snapshots):
                snapshots
            case .transientEmptyAXSnapshot:
                []
            }
        }
    }

    private struct ReconciliationDrainResult {
        var startedRequests: [RuntimeReconciliationRequest] = []
        var completedCount = 0
        var deferredCount = 0
        var repairedSnapshots: [RuntimeHomeAppSnapshot] = []
    }

    typealias ReconciliationExecutor = (
        RuntimeReconciliationRequest,
        RuntimeSnapshotProvider
    ) -> ReconciliationExecutionOutcome

    private let snapshotQueue: DispatchQueue
    private let snapshotProvider: RuntimeSnapshotProvider
    private let windowRecencyTracker: RuntimeWindowRecencyTracker
    private let readModelStore: RuntimeReadModelStore
    private let reconciliationExecutor: ReconciliationExecutor

    init(
        label: String = "FlowTab.RuntimeSnapshotService",
        snapshotProvider: RuntimeSnapshotProvider = RuntimeSnapshotProvider(),
        windowRecencyTracker: RuntimeWindowRecencyTracker = .shared,
        readModelStore: RuntimeReadModelStore = RuntimeReadModelStore(),
        reconciliationExecutor: @escaping ReconciliationExecutor = RuntimeSnapshotService.defaultReconciliationExecutor
    ) {
        snapshotQueue = DispatchQueue(label: label, qos: .utility)
        self.snapshotProvider = snapshotProvider
        self.windowRecencyTracker = windowRecencyTracker
        self.readModelStore = readModelStore
        self.reconciliationExecutor = reconciliationExecutor
    }

    func fallbackRuntimeSnapshot() -> RuntimeSnapshot {
        snapshotQueue.sync { [self] in
            let snapshot = snapshotProvider.snapshot()
            readModelStore.commitAppSwitcherSnapshot(snapshot)
            return snapshot
        }
    }

    func lightweightAppSnapshot() -> RuntimeSnapshot {
        snapshotQueue.sync { [self] in
            let snapshot = snapshotProvider.lightweightAppSnapshot()
            readModelStore.commitAppSwitcherSnapshot(snapshot, clearsDirtyState: false)
            return snapshot
        }
    }

    func homeAppSummaries() async -> [RuntimeHomeAppSummary] {
        await withCheckedContinuation { continuation in
            snapshotQueue.async { [self] in
                let summaries = snapshotProvider.homeAppSummaries()
                readModelStore.commitHomeSummaries(summaries)
                continuation.resume(returning: summaries)
            }
        }
    }

    func homeAppSummary(for appID: String) async -> RuntimeHomeAppSummary? {
        await withCheckedContinuation { continuation in
            snapshotQueue.async { [self] in
                let summary = snapshotProvider.homeAppSummary(for: appID)
                if let summary {
                    readModelStore.commitHomeSummary(summary)
                }
                continuation.resume(returning: summary)
            }
        }
    }

    func homeAppSnapshot(for appID: String) async -> RuntimeHomeAppSnapshot? {
        await withCheckedContinuation { continuation in
            snapshotQueue.async { [self] in
                let snapshot = snapshotProvider.homeAppSnapshot(for: appID)
                    .map(windowRecencyTracker.homeSnapshotWithRecencyApplied)
                if let snapshot {
                    readModelStore.commitCurrentAppWindowSnapshot(snapshot)
                }
                continuation.resume(
                    returning: snapshot
                )
            }
        }
    }

    func readAppSwitcherProjection() -> RuntimeAppSwitcherProjection? {
        readModelStore.readAppSwitcherProjection()
    }

    func readHomeSummaryProjection() -> RuntimeHomeSummaryProjection? {
        readModelStore.readHomeSummaryProjection()
    }

    func readCurrentAppWindowProjection(appID: String) -> RuntimeCurrentAppWindowProjection? {
        readModelStore.readCurrentAppWindowProjection(appID: appID)
    }

    func readCommittedSearchIndexProjection() -> RuntimeSearchIndexProjection? {
        readModelStore.readCommittedSearchIndexProjection()
    }

    func readCommittedSearchIndexForSearch() -> RuntimeSearchIndexRead {
        readModelStore.readCommittedSearchIndexForSearch()
    }

    func runtimeReadModelDiagnostics() -> RuntimeReadModelDiagnostics {
        readModelStore.diagnostics()
    }

    func requestAppSwitcherProjectionMaintenance(reason: RuntimeProjectionMaintenanceReason) {
        snapshotQueue.async { [self] in
            let diagnostics = readModelStore.diagnostics()
            let drainResult = drainReadyReconciliationRequestsWithResultLocked(
                now: Date.timeIntervalSinceReferenceDate
            )
            commitRepairedSnapshotsLocked(drainResult.repairedSnapshots)
            RuntimeLog.debug(
                .snapshot,
                [
                    "runtimeMaintenance",
                    "scope=appSwitcherProjection",
                    "reason=\(reason.rawValue)",
                    "dirtyApps=\(diagnostics.dirtyAppIDs.count)",
                    "dirtyPIDs=\(diagnostics.dirtyPIDs.count)",
                    "dirtyCGWindowIDs=\(diagnostics.dirtyCGWindowIDs.count)",
                    "pendingScopes=\(diagnostics.pendingRepairScopes.count)",
                    "startedRequests=\(drainResult.startedRequests.count)",
                    "completedRequests=\(drainResult.completedCount)",
                    "repairedApps=\(drainResult.repairedSnapshots.count)"
                ].joined(separator: " ")
            )
        }
    }

    func requestSearchIndexFreshnessBarrier(reason: RuntimeProjectionMaintenanceReason) {
        snapshotQueue.async { [self] in
            let diagnostics = readModelStore.diagnostics()
            let drainResult = drainReadyReconciliationRequestsWithResultLocked(
                now: Date.timeIntervalSinceReferenceDate
            )
            commitRepairedSnapshotsLocked(drainResult.repairedSnapshots)
            for snapshot in drainResult.repairedSnapshots {
                readModelStore.stageSearchIndexAppSnapshot(snapshot)
            }
            let hasPendingRequests = snapshotProvider.reconciliationCoordinator.hasPendingRequests()
            let shouldCommitStagedSearchIndex = drainResult.completedCount > 0
                && drainResult.deferredCount == 0
                && !hasPendingRequests
            let committedSearchIndex = shouldCommitStagedSearchIndex
                ? readModelStore.commitStagedSearchIndex()
                : nil
            RuntimeLog.debug(
                .snapshot,
                [
                    "runtimeMaintenance",
                    "scope=searchIndex",
                    "reason=\(reason.rawValue)",
                    "dirtyApps=\(diagnostics.dirtyAppIDs.count)",
                    "dirtyPIDs=\(diagnostics.dirtyPIDs.count)",
                    "dirtyCGWindowIDs=\(diagnostics.dirtyCGWindowIDs.count)",
                    "pendingScopes=\(diagnostics.pendingRepairScopes.count)",
                    "startedRequests=\(drainResult.startedRequests.count)",
                    "completedRequests=\(drainResult.completedCount)",
                    "deferredRequests=\(drainResult.deferredCount)",
                    "pendingRequests=\(hasPendingRequests ? 1 : 0)",
                    "repairedSearchApps=\(drainResult.repairedSnapshots.count)",
                    "committedSearchIndex=\(committedSearchIndex == nil ? 0 : 1)"
                ].joined(separator: " ")
            )
        }
    }

    func currentCGWindowsByPID() -> [pid_t: [RuntimeSnapshotProvider.CGWindowEntry]] {
        snapshotQueue.sync {
            snapshotProvider.collectCGWindowsByPID()
        }
    }

    func signalSpaceTopologyChanged() {
        snapshotQueue.async { [self] in
            _ = snapshotProvider.collectCGWindowsByPID(options: [.excludeDesktopElements])
            readModelStore.markSpaceTopologyDirty(
                affectedCGWindowIDs: [],
                pendingScope: "spaceTopology"
            )
            drainReadyReconciliationRequestsLocked(now: Date.timeIntervalSinceReferenceDate)
        }
    }

    func signalAppLaunched(appID: String, pid: pid_t) {
        snapshotQueue.async { [self] in
            let now = Date.timeIntervalSinceReferenceDate
            readModelStore.markAppLifecycleDirty(
                appID: appID,
                pid: pid,
                pendingScope: "appLaunched:\(appID)"
            )
            snapshotProvider.reconciliationCoordinator.markAppDirty(
                appID: appID,
                pid: pid,
                reason: .appLaunched,
                now: now
            )
            RuntimeLog.debug(.snapshot, "runtimeLifecycle appLaunched appID=\(appID) pid=\(pid)")
            drainReadyReconciliationRequestsLocked(now: now)
        }
    }

    func signalAppWindowsChanged(appID: String, pid: pid_t) {
        snapshotQueue.async { [self] in
            let now = Date.timeIntervalSinceReferenceDate
            readModelStore.markAppWindowsDirty(
                appID: appID,
                pid: pid,
                pendingScope: "appWindows:\(appID)"
            )
            snapshotProvider.reconciliationCoordinator.markAppDirty(
                appID: appID,
                pid: pid,
                reason: .axNotification,
                now: now
            )
            drainReadyReconciliationRequestsLocked(now: now)
        }
    }

    func signalAXWindowDestroyed(appID: String, pid: pid_t, axWindowID: String) {
        snapshotQueue.async { [self] in
            let now = Date.timeIntervalSinceReferenceDate
            let affectedCGWindowID = snapshotProvider.signalAXWindowDestroyed(
                processIdentifier: pid,
                axWindowID: axWindowID,
                now: now
            )
            readModelStore.markAppWindowsDirty(
                appID: appID,
                pid: pid,
                pendingScope: "axWindowDestroyed:\(appID)"
            )
            RuntimeLog.debug(
                .snapshot,
                "runtimeAXDestroyed appID=\(appID) pid=\(pid) axWindowID=\(axWindowID) affectedCGWindowID=\(affectedCGWindowID.map(String.init) ?? "none")"
            )
            snapshotProvider.reconciliationCoordinator.markAppDirty(
                appID: appID,
                pid: pid,
                reason: .axNotification,
                affectedCGWindowIDs: affectedCGWindowID.map { Set([$0]) } ?? [],
                now: now
            )
            drainReadyReconciliationRequestsLocked(now: now)
        }
    }

    func signalAppTerminated(appID: String, pid: pid_t) {
        snapshotQueue.async { [self] in
            snapshotProvider.reconciliationCoordinator.cancelAppRequests(pid: pid)
            snapshotProvider.clearWindowMappingState(for: pid)
            AXLiveWindowRegistry.shared.remove(pid: pid)
            readModelStore.markAppTerminated(appID: appID, pid: pid)
            RuntimeLog.debug(.snapshot, "runtimeLifecycle appTerminated appID=\(appID) pid=\(pid)")
        }
    }

    func signalWindowFocusVerified(_ verification: RuntimeWindowFocusVerification) {
        snapshotQueue.async { [self] in
            let now = Date.timeIntervalSinceReferenceDate
            snapshotProvider.recordWindowFocusVerification(verification, now: now)
            readModelStore.markWindowFocusVerified(
                appID: verification.appID,
                pid: verification.ownerPID,
                affectedCGWindowIDs: Set([verification.targetCGWindowID, verification.focusedCGWindowID].compactMap { $0 })
            )
            snapshotProvider.reconciliationCoordinator.markWindowFocusVerified(
                verification,
                now: now
            )
            drainReadyReconciliationRequestsLocked(now: now)
        }
    }

    func signalWindowFocusVerified(appID: String, pid: pid_t) {
        signalWindowFocusVerified(
            RuntimeWindowFocusVerification(
                appID: appID,
                windowID: "",
                ownerPID: pid,
                targetCGWindowID: nil,
                focusedCGWindowID: nil,
                focusedAXWindow: nil,
                title: "",
                frame: nil,
                allowedActions: []
            )
        )
    }

    func isLikelyTransientAXRebuild(for pid: pid_t) -> Bool {
        snapshotQueue.sync {
            snapshotProvider.isLikelyTransientAXRebuild(for: pid)
        }
    }

    @discardableResult
    func drainReadyReconciliationRequestsSynchronouslyForTesting(
        now: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) -> [RuntimeReconciliationRequest] {
        snapshotQueue.sync {
            drainReadyReconciliationRequestsLocked(now: now)
        }
    }

    @discardableResult
    private func drainReadyReconciliationRequestsLocked(now: TimeInterval) -> [RuntimeReconciliationRequest] {
        let result = drainReadyReconciliationRequestsWithResultLocked(now: now)
        commitRepairedSnapshotsLocked(result.repairedSnapshots)
        return result.startedRequests
    }

    private func commitRepairedSnapshotsLocked(_ snapshots: [RuntimeHomeAppSnapshot]) {
        for snapshot in snapshots {
            readModelStore.commitCurrentAppWindowSnapshot(snapshot)
        }
    }

    private func drainReadyReconciliationRequestsWithResultLocked(now: TimeInterval) -> ReconciliationDrainResult {
        let coordinator = snapshotProvider.reconciliationCoordinator
        let requests = coordinator.readyRequests(now: now)
        var result = ReconciliationDrainResult()
        result.startedRequests.reserveCapacity(requests.count)

        for request in requests {
            guard let startedRequest = coordinator.startRequest(id: request.id) else { continue }
            result.startedRequests.append(startedRequest)
            let outcome = reconciliationExecutor(startedRequest, snapshotProvider)
            switch outcome {
            case .completed, .completedWithRepairedSnapshots:
                coordinator.completeRequest(id: startedRequest.id)
                result.completedCount += 1
                result.repairedSnapshots.append(contentsOf: outcome.repairedSnapshots)
            case .transientEmptyAXSnapshot:
                _ = coordinator.scheduleRetryAfterTransientEmptyAXSnapshot(
                    id: startedRequest.id,
                    now: now
                )
                result.deferredCount += 1
            }
        }
        return result
    }

    private static func defaultReconciliationExecutor(
        request: RuntimeReconciliationRequest,
        snapshotProvider: RuntimeSnapshotProvider
    ) -> ReconciliationExecutionOutcome {
        switch request.target {
        case let .app(pid):
            let result = snapshotProvider.reconcileAppWindows(
                processIdentifier: pid,
                affectedCGWindowIDs: request.affectedCGWindowIDs
            )
            if result.isTransientEmptyAXSnapshot {
                return .transientEmptyAXSnapshot
            }
            if let snapshot = result.snapshot {
                return .completedWithRepairedSnapshots([snapshot])
            }
            return .completed
        case .spaceTopology:
            let cgWindowsByPID = snapshotProvider.collectCGWindowsByPID(options: [.excludeDesktopElements])
            let affectedTargets = snapshotProvider.appReconciliationTargets(
                affectedCGWindowIDs: request.affectedCGWindowIDs,
                currentCGWindowsByPID: cgWindowsByPID
            )
            var repairedSnapshots: [RuntimeHomeAppSnapshot] = []
            for target in affectedTargets {
                let result = snapshotProvider.reconcileAppWindows(
                    processIdentifier: target.pid,
                    affectedCGWindowIDs: target.affectedCGWindowIDs
                )
                if result.isTransientEmptyAXSnapshot {
                    return .transientEmptyAXSnapshot
                }
                if let snapshot = result.snapshot {
                    repairedSnapshots.append(snapshot)
                }
            }
            if !repairedSnapshots.isEmpty {
                return .completedWithRepairedSnapshots(repairedSnapshots)
            }
            return .completed
        }
    }
}
