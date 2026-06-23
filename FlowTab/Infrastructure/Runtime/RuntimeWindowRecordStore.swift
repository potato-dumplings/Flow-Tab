import AppKit
import Foundation

final class RuntimeWindowRecordStore {
    private var mappingStatesByPID: [pid_t: RuntimeWindowMappingState]

    init(mappingStatesByPID: [pid_t: RuntimeWindowMappingState] = [:]) {
        self.mappingStatesByPID = mappingStatesByPID
    }

    func state(for pid: pid_t) -> RuntimeWindowMappingState? {
        mappingStatesByPID[pid]
    }

    func setState(_ state: RuntimeWindowMappingState, for pid: pid_t) {
        mappingStatesByPID[pid] = state
    }

    func commitState(_ state: RuntimeWindowMappingState, for pid: pid_t) {
        if state.isEmpty {
            removeState(for: pid)
        } else {
            setState(state, for: pid)
        }
    }

    func removeState(for pid: pid_t) {
        mappingStatesByPID.removeValue(forKey: pid)
    }

    @discardableResult
    func recordSpaceTopologySnapshot(
        _ snapshot: RuntimeSpaceTopologySnapshot,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime,
        reconciliationCoordinator: RuntimeReconciliationCoordinator
    ) -> RuntimeSpaceTopologyDiff {
        RuntimeWindowRecordEvidence.recordSpaceTopologySnapshot(
            snapshot,
            now: now,
            reconciliationCoordinator: reconciliationCoordinator,
            mappingStatesByPID: &mappingStatesByPID
        )
    }

    func affectedCGWindowIDsByPID(
        affectedCGWindowIDs: Set<CGWindowID>,
        currentCGWindowsByPID: [pid_t: [RuntimeCGWindowEntry]]
    ) -> [pid_t: Set<CGWindowID>] {
        RuntimeWindowMappingState.affectedCGWindowIDsByPID(
            affectedCGWindowIDs: affectedCGWindowIDs,
            currentCGWindowsByPID: currentCGWindowsByPID,
            mappingStatesByPID: mappingStatesByPID
        )
    }

    func recordWindowFocusVerification(
        _ verification: RuntimeWindowFocusVerification,
        now: TimeInterval
    ) {
        RuntimeWindowRecordEvidence.recordWindowFocusVerification(
            verification,
            now: now,
            mappingStatesByPID: &mappingStatesByPID
        )
    }

    @discardableResult
    func clearDestroyedAXAttachment(
        processIdentifier pid: pid_t,
        axWindowID: String,
        now: TimeInterval
    ) -> CGWindowID? {
        RuntimeWindowRecordEvidence.clearDestroyedAXAttachment(
            processIdentifier: pid,
            axWindowID: axWindowID,
            now: now,
            mappingStatesByPID: &mappingStatesByPID
        )
    }

    func cleanup(keepingRunningApps runningApps: [NSRunningApplication]) {
        let runningPIDs = Set(runningApps.map(\.processIdentifier))
        mappingStatesByPID = mappingStatesByPID.filter { runningPIDs.contains($0.key) }
    }
}
