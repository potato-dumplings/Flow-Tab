import Foundation
import FlowTabCore

let sharedRuntimeProjectionService = RuntimeProjectionService()

final class RuntimeProjectionService: RuntimeProjectionServing, @unchecked Sendable {
    private let maintenanceQueue: DispatchQueue
    private let repairProvider: RuntimeProjectionRepairProviding
    private let readModelStore: RuntimeReadModelStore
    private let reconciliationDrainer: RuntimeProjectionReconciliationDrainer

    init(
        label: String = "FlowTab.RuntimeProjectionService",
        repairProvider: RuntimeProjectionRepairProviding = RuntimeProjectionRepairProvider(),
        readModelStore: RuntimeReadModelStore = RuntimeReadModelStore(),
        reconciliationExecutor: @escaping RuntimeProjectionReconciliationExecutor =
            runtimeProjectionDefaultReconciliationExecutor
    ) {
        maintenanceQueue = DispatchQueue(label: label, qos: .utility)
        self.repairProvider = repairProvider
        self.readModelStore = readModelStore
        reconciliationDrainer = RuntimeProjectionReconciliationDrainer(
            repairProvider: repairProvider,
            reconciliationExecutor: reconciliationExecutor
        )
    }

    func readAppSwitcherProjection() -> RuntimeAppSwitcherProjection? {
        readModelStore.readAppSwitcherProjection()
    }

    func readHomeSummaryProjection() -> RuntimeHomeSummaryProjection? {
        readModelStore.readHomeSummaryProjection()
    }

    func readHomeAppDetailProjection(appID: String) -> RuntimeHomeAppDetailProjection? {
        readModelStore.readHomeAppDetailProjection(appID: appID)
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
            let mainTableProjectionCommitted = commitMainTableAppSwitcherProjectionLocked(
                generatedAt: now
            )
            if !diagnostics.hasAppSwitcherProjection
                && !repairProvider.hasPendingReconciliationRequests() {
                repairProvider.scheduleFullRepairFallback(now: now)
            }
            let drainResult = reconciliationDrainer.drainReadyRequests(
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
                    "mainTableProjectionCommitted=\(mainTableProjectionCommitted ? 1 : 0)",
                    "repairedApps=\(drainResult.repairedCurrentAppWindowPayloads.count)"
                ].joined(separator: " ")
            )
        }
    }

    func requestSearchIndexFreshnessBarrier(reason: RuntimeProjectionMaintenanceReason) {
        maintenanceQueue.async { [self] in
            let diagnostics = readModelStore.diagnostics()
            let now = Date.timeIntervalSinceReferenceDate
            let promotedRequests = repairProvider.promoteSearchFreshnessBarrierRequests(now: now)
            let drainResult = reconciliationDrainer.drainReadyRequests(
                now: now,
                maxRequests: runtimeSearchFreshnessBarrierMaxReadyRepairs,
                includeFullRepair: false
            )
            commitRepairedCurrentAppWindowPayloadsLocked(drainResult.repairedCurrentAppWindowPayloads)
            let hasPendingRequests = repairProvider.hasPendingReconciliationRequests()
            let searchCommitResult = readModelStore.commitSearchFreshnessBarrierPayloads(
                drainResult.repairedCurrentAppWindowPayloads,
                deferredRequestCount: drainResult.deferredCount,
                hasPendingRequests: hasPendingRequests,
                generatedAt: now
            )
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
                    "stagedSearchIndex=\(searchCommitResult.stagedNewPayload ? 1 : 0)",
                    "committedSearchIndex=\(searchCommitResult.committedNewGeneration ? 1 : 0)"
                ].joined(separator: " ")
            )
        }
    }

    func signalSpaceTopologyChanged() {
        maintenanceQueue.async { [self] in
            let now = Date.timeIntervalSinceReferenceDate
            let signalFacts = repairProvider.recordSpaceTopologyChanged(now: now)
            readModelStore.markSpaceTopologyDirty(
                affectedCGWindowIDs: signalFacts.affectedCGWindowIDs,
                signatureSummary: signalFacts.signatureSummary,
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
            let appDirectoryEntries = readModelStore
                .readAppDirectoryProjection()?
                .entries(forAppID: appID) ?? []
            if let payload = repairProvider.currentAppWindowPayloadFromMainTables(
                appID: appID,
                pid: pid,
                appDirectoryEntries: appDirectoryEntries,
                generatedAt: now
            ) {
                readModelStore.commitCurrentAppWindowProjection(
                    payload,
                    clearsDirtyState: false,
                    generatedAt: now
                )
            }
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
        let result = reconciliationDrainer.drainReadyRequests(now: now)
        commitFullRepairProjectionPayloadsLocked(result.fullRepairProjectionPayloads)
        commitRepairedCurrentAppWindowPayloadsLocked(result.repairedCurrentAppWindowPayloads)
        return result.startedRequests
    }

    @discardableResult
    private func commitFullRepairProjectionPayloadsLocked(
        _ payloads: [RuntimeFullRepairProjectionPayload]
    ) -> RuntimeFullRepairProjectionCommitSummary {
        var summary = RuntimeFullRepairProjectionCommitSummary()
        for payload in payloads {
            let payloadSummary = readModelStore.commitFullRepairProjectionPayload(payload)
            summary.coldStartCommittedCount += payloadSummary.coldStartCommittedCount
            summary.degradedCommittedCount += payloadSummary.degradedCommittedCount
        }
        return summary
    }

    @discardableResult
    private func commitMainTableAppSwitcherProjectionLocked(
        generatedAt: TimeInterval
    ) -> Bool {
        guard
            let appDirectoryEntries = readModelStore.readAppDirectoryProjection()?.entries,
            let payload = repairProvider.fullAppSwitcherProjectionPayloadFromMainTables(
                appDirectoryEntries: appDirectoryEntries,
                generatedAt: generatedAt
            )
        else {
            return false
        }
        readModelStore.commitFullRepairProjectionPayload(payload, generatedAt: generatedAt)
        return true
    }

    private func commitRepairedCurrentAppWindowPayloadsLocked(
        _ payloads: [RuntimeCurrentAppWindowPayload]
    ) {
        for payload in payloads {
            readModelStore.commitCurrentAppWindowProjection(payload)
        }
    }

}
