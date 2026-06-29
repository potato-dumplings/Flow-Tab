import CoreGraphics
import Foundation
import FlowTabCore

let sharedRuntimeProjectionService = RuntimeProjectionService()

final class RuntimeProjectionService: RuntimeProjectionServing, @unchecked Sendable {
    private let maintenanceQueue: DispatchQueue
    private let maintenanceQueueSpecificKey = DispatchSpecificKey<Void>()
    private let repairProvider: RuntimeProjectionRepairProviding
    private let mainTableProjectionBuilder: RuntimeMainTableProjectionBuilding
    private let readModelStore: RuntimeReadModelStore
    private let appDirectoryProvider: RuntimeAppDirectoryProviding?
    private let reconciliationDrainer: RuntimeProjectionReconciliationDrainer

    init(
        label: String = "FlowTab.RuntimeProjectionService",
        repairProvider: RuntimeProjectionRepairProviding? = nil,
        mainTableProjectionBuilder: RuntimeMainTableProjectionBuilding? = nil,
        appDirectoryProvider: RuntimeAppDirectoryProviding? = nil,
        readModelStore: RuntimeReadModelStore = RuntimeReadModelStore(),
        reconciliationExecutor: @escaping RuntimeProjectionReconciliationExecutor =
            runtimeProjectionDefaultReconciliationExecutor
    ) {
        maintenanceQueue = DispatchQueue(label: label, qos: .utility)
        maintenanceQueue.setSpecific(key: maintenanceQueueSpecificKey, value: ())
        if let repairProvider {
            self.repairProvider = repairProvider
            self.mainTableProjectionBuilder = mainTableProjectionBuilder
                ?? RuntimeUnavailableMainTableProjectionBuilder()
        } else {
            let windowRecordStore = RuntimeWindowRecordStore()
            let reconciliationCoordinator = RuntimeReconciliationCoordinator()
            self.repairProvider = RuntimeProjectionRepairProvider(
                windowRecordStore: windowRecordStore,
                reconciliationCoordinator: reconciliationCoordinator
            )
            self.mainTableProjectionBuilder = mainTableProjectionBuilder
                ?? RuntimeMainTableProjectionBuilder(windowRecordStore: windowRecordStore)
        }
        if let appDirectoryProvider {
            self.appDirectoryProvider = appDirectoryProvider
        } else {
            self.appDirectoryProvider = repairProvider == nil ? RuntimeWorkspaceAppDirectoryProvider() : nil
        }
        self.readModelStore = readModelStore
        reconciliationDrainer = RuntimeProjectionReconciliationDrainer(
            repairProvider: self.repairProvider,
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

    func readFocusedCurrentAppWindowProjection() -> RuntimeFocusedCurrentAppWindowProjectionRead? {
        readModelStore.readFocusedCurrentAppWindowProjection()
    }

    func readActivationTargetProjection() -> RuntimeActivationTargetProjection? {
        readModelStore.readActivationTargetProjection()
    }

    func readSpaceTopologyProjection() -> RuntimeSpaceTopologyProjection? {
        readModelStore.readSpaceTopologyProjection()
    }

    func readCommittedSearchIndexForSearch() -> RuntimeSearchIndexRead {
        readModelStore.readCommittedSearchIndexForSearch()
    }

    func runtimeReadModelDiagnostics() -> RuntimeReadModelDiagnostics {
        readModelStore.diagnostics()
    }

    func requestAppSwitcherProjectionMaintenance(reason: RuntimeProjectionMaintenanceReason) {
        maintenanceQueue.async { [self] in
            let now = Date.timeIntervalSinceReferenceDate
            let appDirectoryProviderEvidenceCount = commitAppDirectoryProviderEvidenceLocked(generatedAt: now)
            var mainTableProjectionCommitted = commitMainTableAppSwitcherProjectionLocked(
                generatedAt: now,
                requiresExistingProjectionCoverage: true
            )
            let diagnostics = readModelStore.diagnostics()
            if !diagnostics.hasCompleteAppSwitcherProjection
                && !repairProvider.hasPendingReconciliationRequests() {
                repairProvider.scheduleFullRepairFallback(now: now)
            }
            let drainResult = reconciliationDrainer.drainReadyRequests(
                now: now
            )
            let fullRepairProjectionCommitSummary = commitFullRepairEvidenceLocked(
                drainResult.fullRepairEvidence,
                generatedAt: now
            )
            commitCurrentAppRepairEvidenceLocked(
                drainResult.currentAppRepairEvidence,
                generatedAt: now
            )
            if !drainResult.completedSpaceTopologyAffectedCGWindowIDs.isEmpty {
                mainTableProjectionCommitted = commitMainTableAppSwitcherProjectionLocked(
                    generatedAt: now,
                    requiresExistingProjectionCoverage: true,
                    clearsDirtyCGWindowIDs: drainResult.completedSpaceTopologyAffectedCGWindowIDs
                ) || mainTableProjectionCommitted
            }
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
                    "appDirectoryProviderEvidence=\(appDirectoryProviderEvidenceCount)",
                    "startedRequests=\(drainResult.startedRequests.count)",
                    "completedRequests=\(drainResult.completedCount)",
                    "fullRepairEvidence=\(drainResult.fullRepairEvidence.count)",
                    "fullRepairColdStartCommits=\(fullRepairProjectionCommitSummary.coldStartCommittedCount)",
                    "fullRepairDegradedCommits=\(fullRepairProjectionCommitSummary.degradedCommittedCount)",
                    "mainTableProjectionCommitted=\(mainTableProjectionCommitted ? 1 : 0)",
                    "currentAppRepairEvidence=\(drainResult.currentAppRepairEvidence.count)"
                ].joined(separator: " ")
            )
        }
    }

    func requestSearchIndexFreshnessBarrier(reason: RuntimeProjectionMaintenanceReason) {
        maintenanceQueue.async { [self] in
            let now = Date.timeIntervalSinceReferenceDate
            let appDirectoryProviderEvidenceCount = commitAppDirectoryProviderEvidenceLocked(generatedAt: now)
            let promotedRequests = repairProvider.promoteSearchFreshnessBarrierRequests(now: now)
            let drainResult = reconciliationDrainer.drainReadyRequests(
                now: now,
                maxRequests: runtimeSearchFreshnessBarrierMaxReadyRepairs,
                includeFullRepair: false
            )
            commitCurrentAppRepairEvidenceLocked(
                drainResult.currentAppRepairEvidence,
                generatedAt: now
            )
            let mainTableProjectionCommitted = commitMainTableAppSwitcherProjectionLocked(
                generatedAt: now,
                requiresExistingProjectionCoverage: true,
                clearsDirtyCGWindowIDs: drainResult.completedSpaceTopologyAffectedCGWindowIDs
            )
            let hasPendingRequests = repairProvider.hasPendingReconciliationRequests()
            let diagnostics = readModelStore.diagnostics()
            let mainTableSearchCommit = commitSearchIndexFromMainTablesLocked(
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
                    "appDirectoryProviderEvidence=\(appDirectoryProviderEvidenceCount)",
                    "promotedRequests=\(promotedRequests.count)",
                    "startedRequests=\(drainResult.startedRequests.count)",
                    "maxReadyRepairs=\(runtimeSearchFreshnessBarrierMaxReadyRepairs)",
                    "completedRequests=\(drainResult.completedCount)",
                    "deferredRequests=\(drainResult.deferredCount)",
                    "pendingRequests=\(hasPendingRequests ? 1 : 0)",
                    "currentAppRepairEvidence=\(drainResult.currentAppRepairEvidence.count)",
                    "mainTableProjectionCommitted=\(mainTableProjectionCommitted ? 1 : 0)",
                    "committedSearchIndex=\(mainTableSearchCommit != nil ? 1 : 0)",
                    "mainTableSearchCommit=\(mainTableSearchCommit != nil ? 1 : 0)"
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
                signature: signalFacts.signature,
                signatureSummary: signalFacts.signatureSummary,
                pendingScope: "spaceTopology",
                generatedAt: now
            )
            commitAppDirectoryProviderEvidenceLocked(generatedAt: now)
            commitMainTableAppSwitcherProjectionLocked(
                generatedAt: now,
                requiresExistingProjectionCoverage: true
            )
            let drainResult = drainReadyReconciliationRequestResultLocked(now: now)
            if !drainResult.completedSpaceTopologyAffectedCGWindowIDs.isEmpty {
                commitMainTableAppSwitcherProjectionLocked(
                    generatedAt: now,
                    requiresExistingProjectionCoverage: true,
                    clearsDirtyCGWindowIDs: drainResult.completedSpaceTopologyAffectedCGWindowIDs
                )
            }
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
            commitAppDirectoryProviderEvidenceLocked(generatedAt: now)
            commitMainTableAppSwitcherProjectionLocked(
                generatedAt: now,
                requiresExistingProjectionCoverage: true
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
            commitAppDirectoryProviderEvidenceLocked(generatedAt: now)
            commitMainTableCurrentAppProjectionLocked(
                appID: appID,
                pid: pid,
                clearsDirtyState: false,
                generatedAt: now
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
            commitAppDirectoryProviderEvidenceLocked(generatedAt: now)
            commitMainTableCurrentAppProjectionLocked(
                appID: appID,
                pid: pid,
                clearsDirtyState: false,
                generatedAt: now
            )
            repairProvider.recordSelectedCurrentAppWindowsChanged(appID: appID, pid: pid, now: now)
            drainReadyReconciliationRequestsLocked(now: now)
        }
    }

    func signalFocusedCurrentAppWindowsChanged() {
        maintenanceQueue.async { [self] in
            var focusedRead = readModelStore.readFocusedCurrentAppWindowProjection()
            let now = Date.timeIntervalSinceReferenceDate
            if focusedRead == nil {
                commitAppDirectoryProviderEvidenceLocked(generatedAt: now)
                focusedRead = readModelStore.readFocusedCurrentAppWindowProjection()
            }
            guard let focusedRead else {
                RuntimeLog.debug(
                    .projection,
                    "selectedAppWindowProjection result=missingFocusedAppDirectoryEntry"
                )
                return
            }
            readModelStore.markAppWindowsDirty(
                appID: focusedRead.appID,
                pid: focusedRead.pid,
                pendingScope: "selectedCurrentAppWindows:\(focusedRead.appID)"
            )
            commitAppDirectoryProviderEvidenceLocked(generatedAt: now)
            commitMainTableCurrentAppProjectionLocked(
                appID: focusedRead.appID,
                pid: focusedRead.pid,
                clearsDirtyState: false,
                generatedAt: now
            )
            repairProvider.recordSelectedCurrentAppWindowsChanged(
                appID: focusedRead.appID,
                pid: focusedRead.pid,
                now: now
            )
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
            commitAppDirectoryProviderEvidenceLocked(generatedAt: now)
            commitMainTableCurrentAppProjectionLocked(
                appID: appID,
                pid: pid,
                clearsDirtyState: false,
                generatedAt: now
            )
            RuntimeLog.debug(
                .projection,
                "runtimeAXDestroyed appID=\(appID) pid=\(pid) axWindowID=\(axWindowID) affectedCGWindowID=\(affectedCGWindowID.map(String.init) ?? "none")"
            )
            drainReadyReconciliationRequestsLocked(now: now)
        }
    }

    func signalAppTerminated(appID: String, pid: pid_t) {
        performMaintenanceSynchronously { [self] in
            let now = Date.timeIntervalSinceReferenceDate
            readModelStore.markAppTerminatedForMainTableProjection(appID: appID, pid: pid)
            repairProvider.recordAppTerminated(processIdentifier: pid)
            commitAppDirectoryProviderEvidenceLocked(generatedAt: now)
            commitMainTableAppSwitcherProjectionLocked(
                generatedAt: now,
                requiresExistingProjectionCoverage: true,
                permittedMissingAppIDs: [appID],
                clearsDirtyForAppID: appID,
                clearsDirtyForPID: pid
            )
            RuntimeLog.debug(.projection, "runtimeLifecycle appTerminated appID=\(appID) pid=\(pid)")
        }
    }

    func signalWindowFocusVerified(_ verification: RuntimeWindowFocusVerification) {
        maintenanceQueue.async { [self] in
            let now = Date.timeIntervalSinceReferenceDate
            let affectedCGWindowIDs = repairProvider.recordWindowFocusVerification(verification, now: now)
            readModelStore.markWindowFocusVerified(
                verification,
                affectedCGWindowIDs: affectedCGWindowIDs,
                generatedAt: now
            )
            commitAppDirectoryProviderEvidenceLocked(generatedAt: now)
            commitMainTableCurrentAppProjectionLocked(
                appID: verification.appID,
                pid: verification.ownerPID,
                clearsDirtyState: false,
                generatedAt: now
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
        drainReadyReconciliationRequestResultLocked(now: now).startedRequests
    }

    @discardableResult
    private func drainReadyReconciliationRequestResultLocked(
        now: TimeInterval
    ) -> RuntimeProjectionReconciliationDrainResult {
        let result = reconciliationDrainer.drainReadyRequests(now: now)
        commitFullRepairEvidenceLocked(
            result.fullRepairEvidence,
            generatedAt: now
        )
        commitCurrentAppRepairEvidenceLocked(
            result.currentAppRepairEvidence,
            generatedAt: now
        )
        return result
    }

    @discardableResult
    private func commitFullRepairEvidenceLocked(
        _ evidenceBatch: [RuntimeFullRepairEvidence],
        generatedAt: TimeInterval
    ) -> RuntimeAppSwitcherProjectionCommitSummary {
        var summary = RuntimeAppSwitcherProjectionCommitSummary()
        for evidence in evidenceBatch {
            let diagnostics = readModelStore.diagnostics()
            readModelStore.commitFullRepairAppDirectoryEvidence(
                evidence.appDirectoryEntries,
                generatedAt: generatedAt
            )
            guard commitMainTableAppSwitcherProjectionLocked(
                generatedAt: generatedAt,
                requiresExistingProjectionCoverage: false
            ) else {
                continue
            }
            if diagnostics.hasAppSwitcherProjection || diagnostics.hasDirtyState {
                summary.degradedCommittedCount += 1
            } else {
                summary.coldStartCommittedCount += 1
            }
        }
        return summary
    }

    @discardableResult
    private func commitMainTableAppSwitcherProjectionLocked(
        generatedAt: TimeInterval,
        requiresExistingProjectionCoverage: Bool,
        permittedMissingAppIDs: Set<String> = [],
        clearsDirtyForAppID: String? = nil,
        clearsDirtyForPID: pid_t? = nil,
        clearsDirtyCGWindowIDs: Set<CGWindowID> = []
    ) -> Bool {
        guard
            let appDirectoryEntries = readModelStore.readAppDirectoryProjection()?.entries,
            let payload = mainTableProjectionBuilder.appSwitcherProjectionPayloadFromMainTables(
                appDirectoryEntries: appDirectoryEntries,
                generatedAt: generatedAt
            )
        else {
            return false
        }
        if requiresExistingProjectionCoverage,
           let existingProjection = readModelStore.readCommittedAppSwitcherProjectionCacheForMaintenance() {
            let payloadAppIDs = Set(payload.apps.map(\.id))
            let requiredExistingAppIDs = Set(existingProjection.apps.map(\.id))
                .subtracting(permittedMissingAppIDs)
            guard requiredExistingAppIDs.isSubset(of: payloadAppIDs) else {
                return false
            }
        }
        readModelStore.commitMainTableAppSwitcherProjectionPayload(
            payload,
            clearsDirtyForAppID: clearsDirtyForAppID,
            clearsDirtyForPID: clearsDirtyForPID,
            clearsDirtyCGWindowIDs: clearsDirtyCGWindowIDs,
            generatedAt: generatedAt
        )
        return true
    }

    @discardableResult
    private func commitAppDirectoryProviderEvidenceLocked(generatedAt: TimeInterval) -> Int {
        guard let entries = appDirectoryProvider?.appDirectoryEntriesForRuntimeMaintenance() else {
            return 0
        }
        readModelStore.commitAppDirectoryProviderEvidence(entries, generatedAt: generatedAt)
        return entries.count
    }

    private func commitCurrentAppRepairEvidenceLocked(
        _ repairEvidence: [RuntimeCurrentAppRepairEvidence],
        generatedAt: TimeInterval
    ) {
        for evidence in repairEvidence {
            readModelStore.commitCurrentAppRepairAppDirectoryEvidence(
                evidence.appDirectoryEntries,
                generatedAt: generatedAt
            )
            commitMainTableCurrentAppProjectionLocked(
                appID: evidence.appID,
                pid: evidence.pid,
                clearsDirtyState: true,
                generatedAt: generatedAt
            )
        }
    }

    @discardableResult
    private func commitMainTableCurrentAppProjectionLocked(
        appID: String,
        pid: pid_t,
        clearsDirtyState: Bool,
        generatedAt: TimeInterval
    ) -> Bool {
        let appDirectoryEntries = readModelStore
            .readAppDirectoryProjection()?
            .entries(forAppID: appID) ?? []
        guard let mainTablePayload = mainTableProjectionBuilder.currentAppWindowPayloadFromMainTables(
            appID: appID,
            pid: pid,
            appDirectoryEntries: appDirectoryEntries,
            generatedAt: generatedAt
        ) else {
            return false
        }
        readModelStore.commitCurrentAppWindowProjection(
            mainTablePayload,
            clearsDirtyState: clearsDirtyState,
            generatedAt: generatedAt
        )
        return true
    }

    @discardableResult
    private func commitSearchIndexFromMainTablesLocked(
        deferredRequestCount: Int,
        hasPendingRequests: Bool,
        generatedAt: TimeInterval
    ) -> RuntimeSearchIndexProjection? {
        guard
            let appDirectoryEntries = readModelStore.readAppDirectoryProjection()?.entries,
            let payload = mainTableProjectionBuilder.searchIndexPayloadFromMainTables(
                appDirectoryEntries: appDirectoryEntries,
                generatedAt: generatedAt
            )
        else {
            return nil
        }
        return readModelStore.commitSearchFreshnessBarrierFromMainTablePayload(
            payload,
            deferredRequestCount: deferredRequestCount,
            hasPendingRequests: hasPendingRequests,
            generatedAt: generatedAt
        )
    }

    private func performMaintenanceSynchronously(_ work: () -> Void) {
        if DispatchQueue.getSpecific(key: maintenanceQueueSpecificKey) != nil {
            work()
            return
        }
        maintenanceQueue.sync(execute: work)
    }

}
