import Foundation
import FlowTabCore

let sharedRuntimeSnapshotService = RuntimeSnapshotService()

protocol RuntimeSnapshotServing: Sendable {
    func snapshot() -> RuntimeSnapshot
    func lightweightAppSnapshot() -> RuntimeSnapshot
    func homeAppSummaries() async -> [RuntimeHomeAppSummary]
    func homeAppSummary(for appID: String) async -> RuntimeHomeAppSummary?
    func homeAppSnapshot(for appID: String) async -> RuntimeHomeAppSnapshot?
    func homeAppSnapshotSynchronously(for appID: String) -> RuntimeHomeAppSnapshot?
    func focusedAppSnapshot(processIdentifier pid: pid_t) -> RuntimeHomeAppSnapshot?
    func currentCGWindowsByPID() -> [pid_t: [RuntimeSnapshotProvider.CGWindowEntry]]
    func isLikelyTransientAXRebuild(for pid: pid_t) -> Bool
}

final class RuntimeSnapshotService: RuntimeSnapshotServing, @unchecked Sendable {
    private let snapshotQueue: DispatchQueue
    private let snapshotProvider: RuntimeSnapshotProvider
    private let windowRecencyTracker: RuntimeWindowRecencyTracker

    init(
        label: String = "FlowTab.RuntimeSnapshotService",
        snapshotProvider: RuntimeSnapshotProvider = RuntimeSnapshotProvider(),
        windowRecencyTracker: RuntimeWindowRecencyTracker = .shared
    ) {
        snapshotQueue = DispatchQueue(label: label, qos: .utility)
        self.snapshotProvider = snapshotProvider
        self.windowRecencyTracker = windowRecencyTracker
    }

    func snapshot() -> RuntimeSnapshot {
        snapshotQueue.sync {
            snapshotProvider.snapshot()
        }
    }

    func lightweightAppSnapshot() -> RuntimeSnapshot {
        snapshotQueue.sync {
            snapshotProvider.lightweightAppSnapshot()
        }
    }

    func homeAppSummaries() async -> [RuntimeHomeAppSummary] {
        await withCheckedContinuation { continuation in
            snapshotQueue.async { [self] in
                continuation.resume(returning: snapshotProvider.homeAppSummaries())
            }
        }
    }

    func homeAppSummary(for appID: String) async -> RuntimeHomeAppSummary? {
        await withCheckedContinuation { continuation in
            snapshotQueue.async { [self] in
                continuation.resume(returning: snapshotProvider.homeAppSummary(for: appID))
            }
        }
    }

    func homeAppSnapshot(for appID: String) async -> RuntimeHomeAppSnapshot? {
        await withCheckedContinuation { continuation in
            snapshotQueue.async { [self] in
                let snapshot = snapshotProvider.homeAppSnapshot(for: appID)
                continuation.resume(
                    returning: snapshot.map(windowRecencyTracker.homeSnapshotWithRecencyApplied)
                )
            }
        }
    }

    func homeAppSnapshotSynchronously(for appID: String) -> RuntimeHomeAppSnapshot? {
        snapshotQueue.sync { [self] in
            let snapshot = snapshotProvider.homeAppSnapshot(for: appID)
            return snapshot.map(windowRecencyTracker.homeSnapshotWithRecencyApplied)
        }
    }

    func focusedAppSnapshot(processIdentifier pid: pid_t) -> RuntimeHomeAppSnapshot? {
        snapshotQueue.sync { [self] in
            let snapshot = snapshotProvider.focusedAppSnapshot(processIdentifier: pid)
            return snapshot.map(windowRecencyTracker.homeSnapshotWithRecencyApplied)
        }
    }

    func currentCGWindowsByPID() -> [pid_t: [RuntimeSnapshotProvider.CGWindowEntry]] {
        snapshotQueue.sync {
            snapshotProvider.collectCGWindowsByPID()
        }
    }

    func isLikelyTransientAXRebuild(for pid: pid_t) -> Bool {
        snapshotQueue.sync {
            snapshotProvider.isLikelyTransientAXRebuild(for: pid)
        }
    }
}
