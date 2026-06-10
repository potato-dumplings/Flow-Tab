import AppKit
import Foundation

struct RuntimeAffectedWindowReconciliationTarget: Equatable {
    let pid: pid_t
    let appID: String
    let affectedCGWindowIDs: Set<CGWindowID>
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
}
