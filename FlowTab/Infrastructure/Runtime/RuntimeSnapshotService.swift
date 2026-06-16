import CoreGraphics
import Foundation
import FlowTabCore

let sharedRuntimeSnapshotService = RuntimeSnapshotService()

enum RuntimeProjectionMaintenanceReason: String, Sendable {
    case switcherSessionStarted
    case searchFreshnessBarrier
}

protocol RuntimeSnapshotServing: Sendable {
    func snapshot() -> RuntimeSnapshot
    func lightweightAppSnapshot() -> RuntimeSnapshot
    func homeAppSummaries() async -> [RuntimeHomeAppSummary]
    func homeAppSummary(for appID: String) async -> RuntimeHomeAppSummary?
    func homeAppSnapshot(for appID: String) async -> RuntimeHomeAppSnapshot?
    func homeAppSnapshotSynchronously(for appID: String) -> RuntimeHomeAppSnapshot?
    func focusedAppSnapshot(processIdentifier pid: pid_t) -> RuntimeHomeAppSnapshot?
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
        case transientEmptyAXSnapshot
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

    func snapshot() -> RuntimeSnapshot {
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

    func homeAppSnapshotSynchronously(for appID: String) -> RuntimeHomeAppSnapshot? {
        snapshotQueue.sync { [self] in
            let snapshot = snapshotProvider.homeAppSnapshot(for: appID)
                .map(windowRecencyTracker.homeSnapshotWithRecencyApplied)
            if let snapshot {
                readModelStore.commitCurrentAppWindowSnapshot(snapshot)
            }
            return snapshot
        }
    }

    func focusedAppSnapshot(processIdentifier pid: pid_t) -> RuntimeHomeAppSnapshot? {
        snapshotQueue.sync { [self] in
            let snapshot = snapshotProvider.focusedAppSnapshot(processIdentifier: pid)
                .map(windowRecencyTracker.homeSnapshotWithRecencyApplied)
            if let snapshot {
                readModelStore.commitCurrentAppWindowSnapshot(snapshot)
            }
            return snapshot
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
            let startedRequests = drainReadyReconciliationRequestsLocked(
                now: Date.timeIntervalSinceReferenceDate
            )
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
                    "startedRequests=\(startedRequests.count)"
                ].joined(separator: " ")
            )
        }
    }

    func requestSearchIndexFreshnessBarrier(reason: RuntimeProjectionMaintenanceReason) {
        snapshotQueue.async { [self] in
            let diagnostics = readModelStore.diagnostics()
            let startedRequests = drainReadyReconciliationRequestsLocked(
                now: Date.timeIntervalSinceReferenceDate
            )
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
                    "startedRequests=\(startedRequests.count)"
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
        let coordinator = snapshotProvider.reconciliationCoordinator
        let requests = coordinator.readyRequests(now: now)
        var startedRequests: [RuntimeReconciliationRequest] = []
        startedRequests.reserveCapacity(requests.count)

        for request in requests {
            guard let startedRequest = coordinator.startRequest(id: request.id) else { continue }
            startedRequests.append(startedRequest)
            switch reconciliationExecutor(startedRequest, snapshotProvider) {
            case .completed:
                coordinator.completeRequest(id: startedRequest.id)
            case .transientEmptyAXSnapshot:
                _ = coordinator.scheduleRetryAfterTransientEmptyAXSnapshot(
                    id: startedRequest.id,
                    now: now
                )
            }
        }
        return startedRequests
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
            return .completed
        case .spaceTopology:
            let cgWindowsByPID = snapshotProvider.collectCGWindowsByPID(options: [.excludeDesktopElements])
            let affectedTargets = snapshotProvider.appReconciliationTargets(
                affectedCGWindowIDs: request.affectedCGWindowIDs,
                currentCGWindowsByPID: cgWindowsByPID
            )
            for target in affectedTargets {
                let result = snapshotProvider.reconcileAppWindows(
                    processIdentifier: target.pid,
                    affectedCGWindowIDs: target.affectedCGWindowIDs
                )
                if result.isTransientEmptyAXSnapshot {
                    return .transientEmptyAXSnapshot
                }
            }
            return .completed
        }
    }
}
