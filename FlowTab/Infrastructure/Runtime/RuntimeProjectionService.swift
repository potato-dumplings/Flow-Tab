import CoreGraphics
import Foundation
import FlowTabCore

let sharedRuntimeProjectionService = RuntimeProjectionService()

enum RuntimeProjectionMaintenanceReason: String, Sendable {
    case switcherSessionStarted
    case appLifecycleRefresh
    case homeProjectionMissing
    case searchFreshnessBarrier
}

protocol RuntimeProjectionServing: Sendable {
    func readAppSwitcherProjection() -> RuntimeAppSwitcherProjection?
    func readHomeSummaryProjection() -> RuntimeHomeSummaryProjection?
    func readCurrentAppWindowProjection(appID: String) -> RuntimeCurrentAppWindowProjection?
    func readCommittedSearchIndexForSearch() -> RuntimeSearchIndexRead
    func runtimeReadModelDiagnostics() -> RuntimeReadModelDiagnostics
    func requestAppSwitcherProjectionMaintenance(reason: RuntimeProjectionMaintenanceReason)
    func requestSearchIndexFreshnessBarrier(reason: RuntimeProjectionMaintenanceReason)
    func signalSpaceTopologyChanged()
    func signalAppLaunched(appID: String, pid: pid_t)
    func signalAppWindowsChanged(appID: String, pid: pid_t)
    func signalAXWindowDestroyed(appID: String, pid: pid_t, axWindowID: String)
    func signalAppTerminated(appID: String, pid: pid_t)
    func signalWindowFocusVerified(_ verification: RuntimeWindowFocusVerification)
    func signalWindowFocusVerified(appID: String, pid: pid_t)
    func isLikelyTransientAXRebuild(for pid: pid_t) -> Bool
}

final class RuntimeProjectionService: RuntimeProjectionServing, @unchecked Sendable {
    enum ReconciliationExecutionOutcome {
        case completed
        case completedWithRepairedCurrentAppWindowPayloads([RuntimeCurrentAppWindowPayload])
        case transientEmptyAXSnapshot

        var repairedCurrentAppWindowPayloads: [RuntimeCurrentAppWindowPayload] {
            switch self {
            case .completed:
                []
            case let .completedWithRepairedCurrentAppWindowPayloads(payloads):
                payloads
            case .transientEmptyAXSnapshot:
                []
            }
        }
    }

    private struct ReconciliationDrainResult {
        var startedRequests: [RuntimeReconciliationRequest] = []
        var completedCount = 0
        var deferredCount = 0
        var repairedCurrentAppWindowPayloads: [RuntimeCurrentAppWindowPayload] = []
    }

    typealias ReconciliationExecutor = (
        RuntimeReconciliationRequest,
        RuntimeSnapshotProvider
    ) -> ReconciliationExecutionOutcome

    private let maintenanceQueue: DispatchQueue
    private let snapshotProvider: RuntimeSnapshotProvider
    private let readModelStore: RuntimeReadModelStore
    private let reconciliationExecutor: ReconciliationExecutor

    init(
        label: String = "FlowTab.RuntimeProjectionService",
        snapshotProvider: RuntimeSnapshotProvider = RuntimeSnapshotProvider(),
        readModelStore: RuntimeReadModelStore = RuntimeReadModelStore(),
        reconciliationExecutor: @escaping ReconciliationExecutor = RuntimeProjectionService.defaultReconciliationExecutor
    ) {
        maintenanceQueue = DispatchQueue(label: label, qos: .utility)
        self.snapshotProvider = snapshotProvider
        self.readModelStore = readModelStore
        self.reconciliationExecutor = reconciliationExecutor
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

    func readCommittedSearchIndexForSearch() -> RuntimeSearchIndexRead {
        readModelStore.readCommittedSearchIndexForSearch()
    }

    func runtimeReadModelDiagnostics() -> RuntimeReadModelDiagnostics {
        readModelStore.diagnostics()
    }

    func requestAppSwitcherProjectionMaintenance(reason: RuntimeProjectionMaintenanceReason) {
        maintenanceQueue.async { [self] in
            let diagnostics = readModelStore.diagnostics()
            let drainResult = drainReadyReconciliationRequestsWithResultLocked(
                now: Date.timeIntervalSinceReferenceDate
            )
            commitRepairedCurrentAppWindowPayloadsLocked(drainResult.repairedCurrentAppWindowPayloads)
            RuntimeLog.debug(
                .projection,
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
                    "repairedApps=\(drainResult.repairedCurrentAppWindowPayloads.count)"
                ].joined(separator: " ")
            )
        }
    }

    func requestSearchIndexFreshnessBarrier(reason: RuntimeProjectionMaintenanceReason) {
        maintenanceQueue.async { [self] in
            let diagnostics = readModelStore.diagnostics()
            let drainResult = drainReadyReconciliationRequestsWithResultLocked(
                now: Date.timeIntervalSinceReferenceDate
            )
            commitRepairedCurrentAppWindowPayloadsLocked(drainResult.repairedCurrentAppWindowPayloads)
            for payload in drainResult.repairedCurrentAppWindowPayloads {
                readModelStore.stageSearchIndexApp(payload.candidate)
            }
            let hasPendingRequests = snapshotProvider.reconciliationCoordinator.hasPendingRequests()
            let shouldCommitStagedSearchIndex = drainResult.completedCount > 0
                && drainResult.deferredCount == 0
                && !hasPendingRequests
            let committedSearchIndex = shouldCommitStagedSearchIndex
                ? readModelStore.commitStagedSearchIndex()
                : nil
            RuntimeLog.debug(
                .projection,
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
                    "repairedSearchApps=\(drainResult.repairedCurrentAppWindowPayloads.count)",
                    "committedSearchIndex=\(committedSearchIndex == nil ? 0 : 1)"
                ].joined(separator: " ")
            )
        }
    }

    func signalSpaceTopologyChanged() {
        maintenanceQueue.async { [self] in
            let collection = snapshotProvider.collectCGWindowsWithSpaceTopologyDiff(
                options: [.excludeDesktopElements]
            )
            readModelStore.markSpaceTopologyDirty(
                affectedCGWindowIDs: collection.spaceTopologyDiff?.affectedCGWindowIDs ?? [],
                pendingScope: "spaceTopology"
            )
            drainReadyReconciliationRequestsLocked(now: Date.timeIntervalSinceReferenceDate)
        }
    }

    func signalAppLaunched(appID: String, pid: pid_t) {
        maintenanceQueue.async { [self] in
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
            RuntimeLog.debug(.projection, "runtimeLifecycle appLaunched appID=\(appID) pid=\(pid)")
            drainReadyReconciliationRequestsLocked(now: now)
        }
    }

    func signalAppWindowsChanged(appID: String, pid: pid_t) {
        maintenanceQueue.async { [self] in
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
        maintenanceQueue.async { [self] in
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
                .projection,
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
        readModelStore.markAppTerminated(appID: appID, pid: pid)
        maintenanceQueue.async { [self] in
            snapshotProvider.reconciliationCoordinator.cancelAppRequests(pid: pid)
            snapshotProvider.clearWindowMappingState(for: pid)
            AXLiveWindowRegistry.shared.remove(pid: pid)
            RuntimeLog.debug(.projection, "runtimeLifecycle appTerminated appID=\(appID) pid=\(pid)")
        }
    }

    func signalWindowFocusVerified(_ verification: RuntimeWindowFocusVerification) {
        maintenanceQueue.async { [self] in
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
        maintenanceQueue.sync {
            snapshotProvider.isLikelyTransientAXRebuild(for: pid)
        }
    }

    @discardableResult
    func drainReadyReconciliationRequestsSynchronouslyForTesting(
        now: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) -> [RuntimeReconciliationRequest] {
        maintenanceQueue.sync {
            drainReadyReconciliationRequestsLocked(now: now)
        }
    }

    @discardableResult
    private func drainReadyReconciliationRequestsLocked(now: TimeInterval) -> [RuntimeReconciliationRequest] {
        let result = drainReadyReconciliationRequestsWithResultLocked(now: now)
        commitRepairedCurrentAppWindowPayloadsLocked(result.repairedCurrentAppWindowPayloads)
        return result.startedRequests
    }

    private func commitRepairedCurrentAppWindowPayloadsLocked(
        _ payloads: [RuntimeCurrentAppWindowPayload]
    ) {
        for payload in payloads {
            readModelStore.commitCurrentAppWindowProjection(payload)
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
            case .completed, .completedWithRepairedCurrentAppWindowPayloads:
                coordinator.completeRequest(id: startedRequest.id)
                result.completedCount += 1
                result.repairedCurrentAppWindowPayloads.append(
                    contentsOf: outcome.repairedCurrentAppWindowPayloads
                )
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
            if result.isTransientEmptyAXRepairPayload {
                return .transientEmptyAXSnapshot
            }
            if let repairPayload = result.repairPayload {
                return .completedWithRepairedCurrentAppWindowPayloads([
                    RuntimeCurrentAppWindowPayload(repairPayload: repairPayload)
                ])
            }
            return .completed
        case .spaceTopology:
            let cgWindowsByPID = snapshotProvider.collectCGWindowsWithSpaceTopologyDiff(
                options: [.excludeDesktopElements]
            ).windowsByPID
            let affectedTargets = snapshotProvider.appReconciliationTargets(
                affectedCGWindowIDs: request.affectedCGWindowIDs,
                currentCGWindowsByPID: cgWindowsByPID
            )
            var repairedCurrentAppWindowPayloads: [RuntimeCurrentAppWindowPayload] = []
            for target in affectedTargets {
                let result = snapshotProvider.reconcileAppWindows(
                    processIdentifier: target.pid,
                    affectedCGWindowIDs: target.affectedCGWindowIDs
                )
                if result.isTransientEmptyAXRepairPayload {
                    return .transientEmptyAXSnapshot
                }
                if let repairPayload = result.repairPayload {
                    repairedCurrentAppWindowPayloads.append(
                        RuntimeCurrentAppWindowPayload(repairPayload: repairPayload)
                    )
                }
            }
            if !repairedCurrentAppWindowPayloads.isEmpty {
                return .completedWithRepairedCurrentAppWindowPayloads(
                    repairedCurrentAppWindowPayloads
                )
            }
            return .completed
        }
    }
}
