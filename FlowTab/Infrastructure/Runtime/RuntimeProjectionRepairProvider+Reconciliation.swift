import CoreGraphics
import Foundation
import FlowTabCore

extension RuntimeProjectionRepairProvider {
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
        snapshotProvider.reconciliationCoordinator.markAppDirty(
            appID: appID,
            pid: pid,
            reason: .axNotification,
            affectedCGWindowIDs: affectedCGWindowID.map { Set([$0]) } ?? [],
            now: now
        )
        return affectedCGWindowID
    }

    func recordAppTerminated(processIdentifier pid: pid_t) {
        snapshotProvider.reconciliationCoordinator.cancelAppRequests(pid: pid)
        snapshotProvider.removeWindowMappingState(forTerminatedPID: pid)
        AXLiveWindowRegistry.shared.remove(pid: pid)
    }

    func recordWindowFocusVerification(
        _ verification: RuntimeWindowFocusVerification,
        now: TimeInterval
    ) -> Set<CGWindowID> {
        snapshotProvider.recordWindowFocusVerification(verification, now: now)
        snapshotProvider.reconciliationCoordinator.markWindowFocusVerified(verification, now: now)
        return verification.affectedCGWindowIDs
    }

    func hasPendingReconciliationRequests() -> Bool {
        snapshotProvider.reconciliationCoordinator.hasPendingRequests()
    }

    func scheduleFullRepairFallback(now: TimeInterval) {
        snapshotProvider.reconciliationCoordinator.scheduleFullRepairFallback(now: now)
    }

    func promoteSearchFreshnessBarrierRequests(now: TimeInterval) -> [RuntimeReconciliationRequest] {
        snapshotProvider.reconciliationCoordinator.promotePendingRequests(
            reason: .searchFreshnessBarrier,
            now: now
        )
    }

    func recordAppLaunched(appID: String, pid: pid_t, now: TimeInterval) {
        snapshotProvider.reconciliationCoordinator.markAppDirty(
            appID: appID,
            pid: pid,
            reason: .appLaunched,
            now: now
        )
    }

    func recordAppWindowsChanged(appID: String, pid: pid_t, now: TimeInterval) {
        snapshotProvider.reconciliationCoordinator.markAppDirty(
            appID: appID,
            pid: pid,
            reason: .axNotification,
            now: now
        )
    }

    func recordSelectedCurrentAppWindowsChanged(appID: String, pid: pid_t, now: TimeInterval) {
        snapshotProvider.reconciliationCoordinator.markAppDirty(
            appID: appID,
            pid: pid,
            reason: .selectedCurrentAppWindows,
            now: now
        )
    }

    func readyReconciliationRequests(
        now: TimeInterval,
        includeFullRepair: Bool
    ) -> [RuntimeReconciliationRequest] {
        snapshotProvider.reconciliationCoordinator.readyRequests(
            now: now,
            includeFullRepair: includeFullRepair
        )
    }

    func startReconciliationRequest(id: UInt64) -> RuntimeReconciliationRequest? {
        snapshotProvider.reconciliationCoordinator.startRequest(id: id)
    }

    func completeReconciliationRequest(id: UInt64) {
        snapshotProvider.reconciliationCoordinator.completeRequest(id: id)
    }

    func deferReconciliationRequestAfterTransientEmptyCurrentAppWindowPayload(
        id: UInt64,
        now: TimeInterval
    ) {
        snapshotProvider.reconciliationCoordinator.scheduleRetryAfterTransientEmptyCurrentAppWindowPayload(
            id: id,
            now: now
        )
    }

    func recordSpaceTopologyChanged(now: TimeInterval) -> Set<CGWindowID> {
        repairFactSource.collectSpaceTopologySignalFacts(now: now).affectedCGWindowIDs
    }

    func reconcileAppWindows(
        processIdentifier pid: pid_t,
        affectedCGWindowIDs: Set<CGWindowID>
    ) -> RuntimeAppWindowReconciliationResult {
        let currentAppWindowPayload = focusedCurrentAppWindowPayload(processIdentifier: pid)
        let currentAppWindowPayloadWasEmpty = currentAppWindowPayload?.candidate.windows.isEmpty == true
        let mappingState = snapshotProvider.windowMappingStateByPID[pid]
        let affectedWindowEvidence = mappingState?.affectedWindowEvidence(
            for: affectedCGWindowIDs
        ) ?? .empty
        return RuntimeAppWindowReconciliationResult(
            pid: pid,
            affectedCGWindowIDs: affectedCGWindowIDs,
            knownAffectedCGWindowIDs: affectedWindowEvidence.knownAffectedCGWindowIDs,
            exactAffectedCGWindowIDs: affectedWindowEvidence.exactAffectedCGWindowIDs,
            currentAppWindowPayload: currentAppWindowPayload,
            currentAppWindowPayloadWasEmpty: currentAppWindowPayloadWasEmpty,
            isTransientEmptyCurrentAppWindowPayload: mappingState?
                .isTransientEmptyCurrentAppWindowPayload(
                    currentAppWindowPayloadWasEmpty: currentAppWindowPayloadWasEmpty
                ) == true
        )
    }

    func reconcileSpaceTopology(
        affectedCGWindowIDs: Set<CGWindowID>
    ) -> [RuntimeAppWindowReconciliationResult] {
        let affectedTargets = repairFactSource.collectSpaceTopologyReconciliationTargets(
            affectedCGWindowIDs: affectedCGWindowIDs
        )
        return affectedTargets.map { target in
            reconcileAppWindows(
                processIdentifier: target.pid,
                affectedCGWindowIDs: target.affectedCGWindowIDs
            )
        }
    }
}
