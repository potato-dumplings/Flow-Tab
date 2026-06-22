import CoreGraphics
import Foundation
import FlowTabCore

let sharedRuntimeProjectionService = RuntimeProjectionService()
let runtimeSearchFreshnessBarrierMaxReadyRepairs = 4

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
    func signalAppLaunched(
        appID: String,
        pid: pid_t,
        appDirectoryEntry: RuntimeAppDirectoryEntry?
    )
    func signalAppWindowsChanged(appID: String, pid: pid_t)
    func signalSelectedCurrentAppWindowsChanged(appID: String, pid: pid_t)
    func signalAXWindowDestroyed(appID: String, pid: pid_t, axWindowID: String)
    func signalAppTerminated(appID: String, pid: pid_t)
    func signalWindowFocusVerified(_ verification: RuntimeWindowFocusVerification)
    func signalWindowFocusVerified(appID: String, pid: pid_t)
}

protocol RuntimeProjectionRepairProviding: AnyObject {
    func reconcileAppWindows(
        processIdentifier pid: pid_t,
        affectedCGWindowIDs: Set<CGWindowID>
    ) -> RuntimeAppWindowReconciliationResult
    func reconcileSpaceTopology(
        affectedCGWindowIDs: Set<CGWindowID>
    ) -> [RuntimeAppWindowReconciliationResult]
    func fullRepairProjectionPayload() -> RuntimeFullRepairProjectionPayload
    func recordSpaceTopologyChanged(now: TimeInterval) -> Set<CGWindowID>
    func signalAXWindowDestroyed(
        appID: String,
        processIdentifier pid: pid_t,
        axWindowID: String,
        now: TimeInterval
    ) -> CGWindowID?
    func recordAppTerminated(processIdentifier pid: pid_t)
    func recordWindowFocusVerification(
        _ verification: RuntimeWindowFocusVerification,
        now: TimeInterval
    ) -> Set<CGWindowID>
    func recordAppLaunched(appID: String, pid: pid_t, now: TimeInterval)
    func recordAppWindowsChanged(appID: String, pid: pid_t, now: TimeInterval)
    func recordSelectedCurrentAppWindowsChanged(appID: String, pid: pid_t, now: TimeInterval)
    func hasPendingReconciliationRequests() -> Bool
    func scheduleFullRepairFallback(now: TimeInterval)
    func promotePendingReconciliationRequests(
        reason: RuntimeReconciliationReason,
        now: TimeInterval
    ) -> [RuntimeReconciliationRequest]
    func readyReconciliationRequests(
        now: TimeInterval,
        includeFullRepair: Bool
    ) -> [RuntimeReconciliationRequest]
    func startReconciliationRequest(id: UInt64) -> RuntimeReconciliationRequest?
    func completeReconciliationRequest(id: UInt64)
    func deferReconciliationRequestAfterTransientEmptyCurrentAppWindowPayload(
        id: UInt64,
        now: TimeInterval
    )
}

final class RuntimeProjectionRepairProvider: RuntimeProjectionRepairProviding {
    let snapshotProvider: RuntimeSnapshotProvider

    init(snapshotProvider: RuntimeSnapshotProvider = RuntimeSnapshotProvider()) {
        self.snapshotProvider = snapshotProvider
    }

    private var reconciliationCoordinator: RuntimeReconciliationCoordinator {
        snapshotProvider.reconciliationCoordinator
    }

    func signalAXWindowDestroyed(
        appID: String,
        processIdentifier pid: pid_t,
        axWindowID: String,
        now: TimeInterval
    ) -> CGWindowID? {
        let affectedCGWindowID = snapshotProvider.signalAXWindowDestroyed(
            processIdentifier: pid,
            axWindowID: axWindowID,
            now: now
        )
        reconciliationCoordinator.markAppDirty(
            appID: appID,
            pid: pid,
            reason: .axNotification,
            affectedCGWindowIDs: affectedCGWindowID.map { Set([$0]) } ?? [],
            now: now
        )
        return affectedCGWindowID
    }

    func recordAppTerminated(processIdentifier pid: pid_t) {
        reconciliationCoordinator.cancelAppRequests(pid: pid)
        snapshotProvider.removeWindowMappingState(forTerminatedPID: pid)
        AXLiveWindowRegistry.shared.remove(pid: pid)
    }

    func recordWindowFocusVerification(
        _ verification: RuntimeWindowFocusVerification,
        now: TimeInterval
    ) -> Set<CGWindowID> {
        snapshotProvider.recordWindowFocusVerification(verification, now: now)
        reconciliationCoordinator.markWindowFocusVerified(verification, now: now)
        return verification.affectedCGWindowIDs
    }
}

final class RuntimeProjectionService: RuntimeProjectionServing, @unchecked Sendable {
    enum ReconciliationExecutionOutcome {
        case completed
        case completedWithFullRepairProjection(RuntimeFullRepairProjectionPayload)
        case completedWithRepairedCurrentAppWindowPayloads([RuntimeCurrentAppWindowPayload])
        case transientEmptyCurrentAppWindowPayload

        var repairedCurrentAppWindowPayloads: [RuntimeCurrentAppWindowPayload] {
            switch self {
            case .completed, .completedWithFullRepairProjection:
                []
            case let .completedWithRepairedCurrentAppWindowPayloads(payloads):
                payloads
            case .transientEmptyCurrentAppWindowPayload:
                []
            }
        }
    }

    private struct ReconciliationDrainResult {
        var startedRequests: [RuntimeReconciliationRequest] = []
        var completedCount = 0
        var deferredCount = 0
        var fullRepairProjectionPayloads: [RuntimeFullRepairProjectionPayload] = []
        var repairedCurrentAppWindowPayloads: [RuntimeCurrentAppWindowPayload] = []
    }

    private struct FullRepairProjectionCommitSummary {
        var coldStartCommittedCount = 0
        var degradedCommittedCount = 0
    }

    typealias ReconciliationExecutor = (
        RuntimeReconciliationRequest,
        RuntimeProjectionRepairProviding
    ) -> ReconciliationExecutionOutcome

    private let maintenanceQueue: DispatchQueue
    private let repairProvider: RuntimeProjectionRepairProviding
    private let readModelStore: RuntimeReadModelStore
    private let reconciliationExecutor: ReconciliationExecutor

    init(
        label: String = "FlowTab.RuntimeProjectionService",
        repairProvider: RuntimeProjectionRepairProviding = RuntimeProjectionRepairProvider(),
        readModelStore: RuntimeReadModelStore = RuntimeReadModelStore(),
        reconciliationExecutor: @escaping ReconciliationExecutor = RuntimeProjectionService.defaultReconciliationExecutor
    ) {
        maintenanceQueue = DispatchQueue(label: label, qos: .utility)
        self.repairProvider = repairProvider
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
            let now = Date.timeIntervalSinceReferenceDate
            if !diagnostics.hasAppSwitcherProjection
                && !repairProvider.hasPendingReconciliationRequests() {
                repairProvider.scheduleFullRepairFallback(now: now)
            }
            let drainResult = drainReadyReconciliationRequestsWithResultLocked(
                now: now
            )
            let fullRepairCommitSummary = commitFullRepairProjectionPayloadsLocked(
                drainResult.fullRepairProjectionPayloads
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
                    "fullRepairProjectionPayloads=\(drainResult.fullRepairProjectionPayloads.count)",
                    "fullRepairColdStartCommits=\(fullRepairCommitSummary.coldStartCommittedCount)",
                    "fullRepairDegradedCommits=\(fullRepairCommitSummary.degradedCommittedCount)",
                    "repairedApps=\(drainResult.repairedCurrentAppWindowPayloads.count)"
                ].joined(separator: " ")
            )
        }
    }

    func requestSearchIndexFreshnessBarrier(reason: RuntimeProjectionMaintenanceReason) {
        maintenanceQueue.async { [self] in
            let diagnostics = readModelStore.diagnostics()
            let now = Date.timeIntervalSinceReferenceDate
            let promotedRequests = repairProvider.promotePendingReconciliationRequests(
                reason: .searchFreshnessBarrier,
                now: now
            )
            let drainResult = drainReadyReconciliationRequestsWithResultLocked(
                now: now,
                maxRequests: runtimeSearchFreshnessBarrierMaxReadyRepairs,
                includeFullRepair: false
            )
            commitRepairedCurrentAppWindowPayloadsLocked(drainResult.repairedCurrentAppWindowPayloads)
            let stagedSearchIndex = readModelStore.stageSearchIndexCurrentAppWindowPayloads(
                drainResult.repairedCurrentAppWindowPayloads
            )
            let hasPendingRequests = repairProvider.hasPendingReconciliationRequests()
            let shouldCommitStagedSearchIndex = stagedSearchIndex != nil
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
                    "promotedRequests=\(promotedRequests.count)",
                    "startedRequests=\(drainResult.startedRequests.count)",
                    "maxReadyRepairs=\(runtimeSearchFreshnessBarrierMaxReadyRepairs)",
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
            let now = Date.timeIntervalSinceReferenceDate
            let affectedCGWindowIDs = repairProvider.recordSpaceTopologyChanged(now: now)
            readModelStore.markSpaceTopologyDirty(
                affectedCGWindowIDs: affectedCGWindowIDs,
                pendingScope: "spaceTopology"
            )
            drainReadyReconciliationRequestsLocked(now: now)
        }
    }

    func signalAppLaunched(
        appID: String,
        pid: pid_t,
        appDirectoryEntry: RuntimeAppDirectoryEntry? = nil
    ) {
        maintenanceQueue.async { [self] in
            let now = Date.timeIntervalSinceReferenceDate
            readModelStore.markAppLifecycleDirty(
                appID: appID,
                pid: pid,
                pendingScope: "appLaunched:\(appID)",
                appDirectoryEntry: appDirectoryEntry,
                generatedAt: now
            )
            repairProvider.recordAppLaunched(appID: appID, pid: pid, now: now)
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
            repairProvider.recordAppWindowsChanged(appID: appID, pid: pid, now: now)
            drainReadyReconciliationRequestsLocked(now: now)
        }
    }

    func signalSelectedCurrentAppWindowsChanged(appID: String, pid: pid_t) {
        maintenanceQueue.async { [self] in
            let now = Date.timeIntervalSinceReferenceDate
            readModelStore.markAppWindowsDirty(
                appID: appID,
                pid: pid,
                pendingScope: "selectedCurrentAppWindows:\(appID)"
            )
            repairProvider.recordSelectedCurrentAppWindowsChanged(appID: appID, pid: pid, now: now)
            drainReadyReconciliationRequestsLocked(now: now)
        }
    }

    func signalAXWindowDestroyed(appID: String, pid: pid_t, axWindowID: String) {
        maintenanceQueue.async { [self] in
            let now = Date.timeIntervalSinceReferenceDate
            let affectedCGWindowID = repairProvider.signalAXWindowDestroyed(
                appID: appID,
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
            drainReadyReconciliationRequestsLocked(now: now)
        }
    }

    func signalAppTerminated(appID: String, pid: pid_t) {
        readModelStore.markAppTerminated(appID: appID, pid: pid)
        maintenanceQueue.async { [self] in
            repairProvider.recordAppTerminated(processIdentifier: pid)
            RuntimeLog.debug(.projection, "runtimeLifecycle appTerminated appID=\(appID) pid=\(pid)")
        }
    }

    func signalWindowFocusVerified(_ verification: RuntimeWindowFocusVerification) {
        maintenanceQueue.async { [self] in
            let now = Date.timeIntervalSinceReferenceDate
            let affectedCGWindowIDs = repairProvider.recordWindowFocusVerification(verification, now: now)
            readModelStore.markWindowFocusVerified(
                appID: verification.appID,
                pid: verification.ownerPID,
                affectedCGWindowIDs: affectedCGWindowIDs
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

    @discardableResult
    func drainReadyReconciliationRequestsSynchronouslyForTesting(
        now: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) -> [RuntimeReconciliationRequest] {
        maintenanceQueue.sync {
            drainReadyReconciliationRequestsLocked(now: now)
        }
    }

    func waitForMaintenanceQueueForTesting() {
        maintenanceQueue.sync {}
    }

    @discardableResult
    private func drainReadyReconciliationRequestsLocked(now: TimeInterval) -> [RuntimeReconciliationRequest] {
        let result = drainReadyReconciliationRequestsWithResultLocked(now: now)
        commitFullRepairProjectionPayloadsLocked(result.fullRepairProjectionPayloads)
        commitRepairedCurrentAppWindowPayloadsLocked(result.repairedCurrentAppWindowPayloads)
        return result.startedRequests
    }

    @discardableResult
    private func commitFullRepairProjectionPayloadsLocked(
        _ payloads: [RuntimeFullRepairProjectionPayload]
    ) -> FullRepairProjectionCommitSummary {
        var summary = FullRepairProjectionCommitSummary()
        for payload in payloads {
            let diagnostics = readModelStore.diagnostics()
            let clearsDirtyState = !diagnostics.hasAppSwitcherProjection
                && !diagnostics.hasDirtyState
            readModelStore.commitAppSwitcherProjection(
                apps: payload.apps,
                contextsByID: payload.contextsByID,
                appDirectoryEntries: payload.appDirectoryEntries,
                clearsDirtyState: clearsDirtyState
            )
            if clearsDirtyState {
                summary.coldStartCommittedCount += 1
            } else {
                summary.degradedCommittedCount += 1
            }
        }
        return summary
    }

    private func commitRepairedCurrentAppWindowPayloadsLocked(
        _ payloads: [RuntimeCurrentAppWindowPayload]
    ) {
        for payload in payloads {
            readModelStore.commitCurrentAppWindowProjection(payload)
        }
    }

    private func drainReadyReconciliationRequestsWithResultLocked(
        now: TimeInterval,
        maxRequests: Int? = nil,
        includeFullRepair: Bool = true
    ) -> ReconciliationDrainResult {
        let readyRequests = repairProvider.readyReconciliationRequests(
            now: now,
            includeFullRepair: includeFullRepair
        )
        let requests = maxRequests.map { Array(readyRequests.prefix($0)) } ?? readyRequests
        var result = ReconciliationDrainResult()
        result.startedRequests.reserveCapacity(requests.count)

        for request in requests {
            guard let startedRequest = repairProvider.startReconciliationRequest(id: request.id) else {
                continue
            }
            result.startedRequests.append(startedRequest)
            let outcome = reconciliationExecutor(startedRequest, repairProvider)
            switch outcome {
            case .completed, .completedWithFullRepairProjection, .completedWithRepairedCurrentAppWindowPayloads:
                repairProvider.completeReconciliationRequest(id: startedRequest.id)
                result.completedCount += 1
                if case let .completedWithFullRepairProjection(payload) = outcome {
                    result.fullRepairProjectionPayloads.append(payload)
                }
                result.repairedCurrentAppWindowPayloads.append(
                    contentsOf: outcome.repairedCurrentAppWindowPayloads
                )
            case .transientEmptyCurrentAppWindowPayload:
                repairProvider.deferReconciliationRequestAfterTransientEmptyCurrentAppWindowPayload(
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
        repairProvider: RuntimeProjectionRepairProviding
    ) -> ReconciliationExecutionOutcome {
        switch request.target {
        case let .app(pid):
            let result = repairProvider.reconcileAppWindows(
                processIdentifier: pid,
                affectedCGWindowIDs: request.affectedCGWindowIDs
            )
            if result.isTransientEmptyCurrentAppWindowPayload {
                return .transientEmptyCurrentAppWindowPayload
            }
            if let payload = result.currentAppWindowPayload {
                return .completedWithRepairedCurrentAppWindowPayloads([payload])
            }
            return .completed
        case .fullRepair:
            return .completedWithFullRepairProjection(repairProvider.fullRepairProjectionPayload())
        case .spaceTopology:
            let results = repairProvider.reconcileSpaceTopology(
                affectedCGWindowIDs: request.affectedCGWindowIDs
            )
            var repairedCurrentAppWindowPayloads: [RuntimeCurrentAppWindowPayload] = []
            for result in results {
                if result.isTransientEmptyCurrentAppWindowPayload {
                    return .transientEmptyCurrentAppWindowPayload
                }
                if let payload = result.currentAppWindowPayload {
                    repairedCurrentAppWindowPayloads.append(payload)
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
