import AppKit
import Foundation

struct RuntimeAffectedWindowReconciliationTarget: Equatable {
    let pid: pid_t
    let appID: String
    let affectedCGWindowIDs: Set<CGWindowID>
}

struct RuntimeAppWindowReconciliationResult: Equatable {
    let pid: pid_t
    let affectedCGWindowIDs: Set<CGWindowID>
    let knownAffectedCGWindowIDs: Set<CGWindowID>
    let exactAffectedCGWindowIDs: Set<CGWindowID>
    let snapshotWasEmpty: Bool
    let isTransientEmptyAXSnapshot: Bool
}

extension RuntimeSnapshotProvider {
    @discardableResult
    func recordSpaceTopologySnapshot(
        _ snapshot: RuntimeSpaceTopologySnapshot,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> RuntimeSpaceTopologyDiff {
        reconciliationCoordinator.applySpaceTopologySnapshot(snapshot, now: now)
    }

    func appReconciliationTargets(
        affectedCGWindowIDs: Set<CGWindowID>,
        currentCGWindowsByPID: [pid_t: [CGWindowEntry]]
    ) -> [RuntimeAffectedWindowReconciliationTarget] {
        guard !affectedCGWindowIDs.isEmpty else { return [] }

        var affectedCGWindowIDsByPID: [pid_t: Set<CGWindowID>] = [:]
        for (pid, cgWindows) in currentCGWindowsByPID {
            let affected = Set(cgWindows.map(\.id)).intersection(affectedCGWindowIDs)
            if !affected.isEmpty {
                affectedCGWindowIDsByPID[pid, default: []].formUnion(affected)
            }
        }

        for (pid, mappingState) in windowMappingStateByPID {
            let affected = Set(mappingState.windowRecordsByCGWindowID.keys)
                .intersection(affectedCGWindowIDs)
            if !affected.isEmpty {
                affectedCGWindowIDsByPID[pid, default: []].formUnion(affected)
            }
        }

        let appIDsByPID = Dictionary(
            uniqueKeysWithValues: filteredRunningApplications().map { app in
                (app.processIdentifier, Self.baseAppID(for: app))
            }
        )
        return affectedCGWindowIDsByPID.keys.sorted().map { pid in
            RuntimeAffectedWindowReconciliationTarget(
                pid: pid,
                appID: appIDsByPID[pid]
                    ?? NSRunningApplication(processIdentifier: pid).map(Self.baseAppID(for:))
                    ?? "pid:\(pid)",
                affectedCGWindowIDs: affectedCGWindowIDsByPID[pid] ?? []
            )
        }
    }

    @discardableResult
    func reconcileAppWindows(
        processIdentifier pid: pid_t,
        affectedCGWindowIDs: Set<CGWindowID>
    ) -> RuntimeAppWindowReconciliationResult {
        let snapshot = focusedAppSnapshot(processIdentifier: pid)
        let snapshotWasEmpty = snapshot?.candidate.windows.isEmpty == true
        let mappingState = windowMappingStateByPID[pid]
        let knownAffectedCGWindowIDs = mappingState.map {
            affectedCGWindowIDs.intersection($0.windowRecordsByCGWindowID.keys)
        } ?? []
        let exactAffectedCGWindowIDs = knownAffectedCGWindowIDs.filter { cgWindowID in
            mappingState?.windowRecordsByCGWindowID[cgWindowID]?.bindingConfidence == .exact
        }
        return RuntimeAppWindowReconciliationResult(
            pid: pid,
            affectedCGWindowIDs: affectedCGWindowIDs,
            knownAffectedCGWindowIDs: knownAffectedCGWindowIDs,
            exactAffectedCGWindowIDs: exactAffectedCGWindowIDs,
            snapshotWasEmpty: snapshotWasEmpty,
            isTransientEmptyAXSnapshot: snapshotWasEmpty && isLikelyTransientAXRebuild(for: pid)
        )
    }
}
