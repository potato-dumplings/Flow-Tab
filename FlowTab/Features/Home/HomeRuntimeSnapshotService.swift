import Foundation
import FlowTabCore

let homeRuntimeSnapshotService = HomeRuntimeSnapshotService()

// RuntimeSnapshotProvider keeps mutable window-mapping state, so Home serializes access to one reusable instance.
final class HomeRuntimeSnapshotService: @unchecked Sendable {
    private let snapshotQueue = DispatchQueue(
        label: "FlowTab.HomeRuntimeSnapshotService",
        qos: .utility
    )
    private let snapshotProvider = RuntimeSnapshotProvider()

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
                continuation.resume(returning: snapshotProvider.homeAppSnapshot(for: appID))
            }
        }
    }

    func isLikelyTransientAXRebuild(for pid: pid_t) -> Bool {
        snapshotQueue.sync {
            snapshotProvider.isLikelyTransientAXRebuild(for: pid)
        }
    }
}
