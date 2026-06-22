import CoreGraphics
import Foundation
import FlowTabCore

private struct RuntimeAffectedWindowReconciliationTarget: Equatable {
    let pid: pid_t
    let affectedCGWindowIDs: Set<CGWindowID>
}

struct RuntimeAppWindowReconciliationResult {
    let pid: pid_t
    let affectedCGWindowIDs: Set<CGWindowID>
    let knownAffectedCGWindowIDs: Set<CGWindowID>
    let exactAffectedCGWindowIDs: Set<CGWindowID>
    let currentAppWindowPayload: RuntimeCurrentAppWindowPayload?
    let currentAppWindowPayloadWasEmpty: Bool
    let isTransientEmptyCurrentAppWindowPayload: Bool
}

extension RuntimeProjectionRepairProvider {
    func recordSpaceTopologyChanged(now: TimeInterval) -> Set<CGWindowID> {
        snapshotProvider.collectCGWindowsWithSpaceTopologyDiff(
            options: [.excludeDesktopElements],
            now: now
        ).spaceTopologyDiff?.affectedCGWindowIDs ?? []
    }

    private func appReconciliationTargets(
        affectedCGWindowIDs: Set<CGWindowID>,
        currentCGWindowsByPID: [pid_t: [RuntimeCGWindowEntry]]
    ) -> [RuntimeAffectedWindowReconciliationTarget] {
        let affectedCGWindowIDsByPID = RuntimeWindowMappingState.affectedCGWindowIDsByPID(
            affectedCGWindowIDs: affectedCGWindowIDs,
            currentCGWindowsByPID: currentCGWindowsByPID,
            mappingStatesByPID: snapshotProvider.windowMappingStateByPID
        )
        guard !affectedCGWindowIDsByPID.isEmpty else { return [] }

        return affectedCGWindowIDsByPID.keys.sorted().map { pid in
            RuntimeAffectedWindowReconciliationTarget(
                pid: pid,
                affectedCGWindowIDs: affectedCGWindowIDsByPID[pid] ?? []
            )
        }
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
        let cgWindowsByPID = snapshotProvider.collectCGWindowsWithSpaceTopologyDiff(
            options: [.excludeDesktopElements]
        ).windowsByPID
        let affectedTargets = appReconciliationTargets(
            affectedCGWindowIDs: affectedCGWindowIDs,
            currentCGWindowsByPID: cgWindowsByPID
        )
        return affectedTargets.map { target in
            reconcileAppWindows(
                processIdentifier: target.pid,
                affectedCGWindowIDs: target.affectedCGWindowIDs
            )
        }
    }
}
