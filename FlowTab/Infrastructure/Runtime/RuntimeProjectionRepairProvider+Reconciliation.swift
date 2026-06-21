import AppKit
import CoreGraphics
import Foundation
import FlowTabCore

struct RuntimeAffectedWindowReconciliationTarget: Equatable {
    let pid: pid_t
    let appID: String
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
            uniqueKeysWithValues: RuntimeAppDirectoryFactSource.currentAppLayerRunningApplications(
                includeCurrentProcessInAppLayer: AppVisibilityPreferencesStore.loadShowInCommandTab()
            ).map { app in
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
            isTransientEmptyCurrentAppWindowPayload: currentAppWindowPayloadWasEmpty
                && snapshotProvider.isLikelyTransientAXRebuild(for: pid)
        )
    }
}
