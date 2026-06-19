import AppKit
import CoreGraphics
import Foundation
import FlowTabCore

extension RuntimeProjectionRepairProvider {
    func appReconciliationTargets(
        affectedCGWindowIDs: Set<CGWindowID>,
        currentCGWindowsByPID: [pid_t: [RuntimeCGWindowEntry]]
    ) -> [RuntimeAffectedWindowReconciliationTarget] {
        guard !affectedCGWindowIDs.isEmpty else { return [] }

        var affectedCGWindowIDsByPID: [pid_t: Set<CGWindowID>] = [:]
        for (pid, cgWindows) in currentCGWindowsByPID {
            let affected = Set(cgWindows.map(\.id)).intersection(affectedCGWindowIDs)
            if !affected.isEmpty {
                affectedCGWindowIDsByPID[pid, default: []].formUnion(affected)
            }
        }

        for (pid, mappingState) in snapshotProvider.windowMappingStateByPID {
            let affected = Set(mappingState.windowRecordsByCGWindowID.keys)
                .intersection(affectedCGWindowIDs)
            if !affected.isEmpty {
                affectedCGWindowIDsByPID[pid, default: []].formUnion(affected)
            }
        }

        let appIDsByPID = Dictionary(
            uniqueKeysWithValues: filteredRunningApplications().map { app in
                (app.processIdentifier, RuntimeAppIdentity.appID(for: app))
            }
        )
        return affectedCGWindowIDsByPID.keys.sorted().map { pid in
            RuntimeAffectedWindowReconciliationTarget(
                pid: pid,
                appID: appIDsByPID[pid]
                    ?? NSRunningApplication(processIdentifier: pid).map(RuntimeAppIdentity.appID(for:))
                    ?? "pid:\(pid)",
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
            currentAppWindowPayload: currentAppWindowPayload,
            currentAppWindowPayloadWasEmpty: currentAppWindowPayloadWasEmpty,
            isTransientEmptyCurrentAppWindowPayload: currentAppWindowPayloadWasEmpty
                && snapshotProvider.isLikelyTransientAXRebuild(for: pid)
        )
    }
}
