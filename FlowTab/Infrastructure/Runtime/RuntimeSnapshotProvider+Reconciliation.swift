import Foundation

extension RuntimeSnapshotProvider {
    @discardableResult
    func recordSpaceTopologySnapshot(
        _ snapshot: RuntimeSpaceTopologySnapshot,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> RuntimeSpaceTopologyDiff {
        reconciliationCoordinator.applySpaceTopologySnapshot(snapshot, now: now)
    }
}
