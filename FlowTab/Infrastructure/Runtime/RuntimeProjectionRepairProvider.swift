import CoreGraphics
import Foundation
import FlowTabCore

struct RuntimeAppWindowReconciliationResult {
    let pid: pid_t
    let affectedCGWindowIDs: Set<CGWindowID>
    let knownAffectedCGWindowIDs: Set<CGWindowID>
    let exactAffectedCGWindowIDs: Set<CGWindowID>
    let currentAppWindowPayload: RuntimeCurrentAppWindowPayload?
    let currentAppWindowPayloadWasEmpty: Bool
    let isTransientEmptyCurrentAppWindowPayload: Bool
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
    func recordSpaceTopologyChanged(now: TimeInterval) -> RuntimeSpaceTopologySignalFacts
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
    func promoteSearchFreshnessBarrierRequests(now: TimeInterval) -> [RuntimeReconciliationRequest]
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
    private let runtimeFactProvider: RuntimeSnapshotProvider
    let repairFactSource: RuntimeProjectionRepairFactSource

    init(runtimeFactProvider: RuntimeSnapshotProvider = RuntimeSnapshotProvider()) {
        self.runtimeFactProvider = runtimeFactProvider
        self.repairFactSource = RuntimeProjectionRepairFactSource(runtimeFactProvider: runtimeFactProvider)
    }
}

extension RuntimeProjectionRepairProvider {
    func signalAXWindowDestroyed(
        appID: String,
        processIdentifier pid: pid_t,
        axWindowID: String,
        now: TimeInterval
    ) -> CGWindowID? {
        let affectedCGWindowID = runtimeFactProvider.windowRecordStore.clearDestroyedAXAttachment(
            processIdentifier: pid,
            axWindowID: axWindowID,
            now: now
        )
        runtimeFactProvider.reconciliationCoordinator.markAppDirty(
            appID: appID,
            pid: pid,
            reason: .axNotification,
            affectedCGWindowIDs: affectedCGWindowID.map { Set([$0]) } ?? [],
            now: now
        )
        return affectedCGWindowID
    }

    func recordAppTerminated(processIdentifier pid: pid_t) {
        runtimeFactProvider.reconciliationCoordinator.cancelAppRequests(pid: pid)
        runtimeFactProvider.windowRecordStore.removeState(for: pid)
        AXLiveWindowRegistry.shared.remove(pid: pid)
    }

    func recordWindowFocusVerification(
        _ verification: RuntimeWindowFocusVerification,
        now: TimeInterval
    ) -> Set<CGWindowID> {
        runtimeFactProvider.windowRecordStore.recordWindowFocusVerification(
            verification,
            now: now
        )
        runtimeFactProvider.reconciliationCoordinator.markWindowFocusVerified(verification, now: now)
        return verification.affectedCGWindowIDs
    }

    func hasPendingReconciliationRequests() -> Bool {
        runtimeFactProvider.reconciliationCoordinator.hasPendingRequests()
    }

    func scheduleFullRepairFallback(now: TimeInterval) {
        runtimeFactProvider.reconciliationCoordinator.scheduleFullRepairFallback(now: now)
    }

    func promoteSearchFreshnessBarrierRequests(now: TimeInterval) -> [RuntimeReconciliationRequest] {
        runtimeFactProvider.reconciliationCoordinator.promotePendingRequests(
            reason: .searchFreshnessBarrier,
            now: now
        )
    }

    func recordAppLaunched(appID: String, pid: pid_t, now: TimeInterval) {
        runtimeFactProvider.reconciliationCoordinator.markAppDirty(
            appID: appID,
            pid: pid,
            reason: .appLaunched,
            now: now
        )
    }

    func recordAppWindowsChanged(appID: String, pid: pid_t, now: TimeInterval) {
        runtimeFactProvider.reconciliationCoordinator.markAppDirty(
            appID: appID,
            pid: pid,
            reason: .axNotification,
            now: now
        )
    }

    func recordSelectedCurrentAppWindowsChanged(appID: String, pid: pid_t, now: TimeInterval) {
        runtimeFactProvider.reconciliationCoordinator.markAppDirty(
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
        runtimeFactProvider.reconciliationCoordinator.readyRequests(
            now: now,
            includeFullRepair: includeFullRepair
        )
    }

    func startReconciliationRequest(id: UInt64) -> RuntimeReconciliationRequest? {
        runtimeFactProvider.reconciliationCoordinator.startRequest(id: id)
    }

    func completeReconciliationRequest(id: UInt64) {
        runtimeFactProvider.reconciliationCoordinator.completeRequest(id: id)
    }

    func deferReconciliationRequestAfterTransientEmptyCurrentAppWindowPayload(
        id: UInt64,
        now: TimeInterval
    ) {
        runtimeFactProvider.reconciliationCoordinator.scheduleRetryAfterTransientEmptyCurrentAppWindowPayload(
            id: id,
            now: now
        )
    }

    func recordSpaceTopologyChanged(now: TimeInterval) -> RuntimeSpaceTopologySignalFacts {
        repairFactSource.collectSpaceTopologySignalFacts(now: now)
    }

    func reconcileAppWindows(
        processIdentifier pid: pid_t,
        affectedCGWindowIDs: Set<CGWindowID>
    ) -> RuntimeAppWindowReconciliationResult {
        let currentAppWindowPayload = focusedCurrentAppWindowPayload(processIdentifier: pid)
        let currentAppWindowPayloadWasEmpty = currentAppWindowPayload?.candidate.windows.isEmpty == true
        let mappingState = runtimeFactProvider.windowRecordStore.state(for: pid)
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
