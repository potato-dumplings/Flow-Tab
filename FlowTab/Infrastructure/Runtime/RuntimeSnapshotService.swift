import CoreGraphics
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
    func signalSpaceTopologyChanged()
    func signalAppWindowsChanged(appID: String, pid: pid_t)
    func signalWindowFocusVerified(_ verification: RuntimeWindowFocusVerification)
    func signalWindowFocusVerified(appID: String, pid: pid_t)
    func isLikelyTransientAXRebuild(for pid: pid_t) -> Bool
}

final class RuntimeSnapshotService: RuntimeSnapshotServing, @unchecked Sendable {
    enum ReconciliationExecutionOutcome {
        case completed
        case transientEmptyAXSnapshot
    }

    typealias ReconciliationExecutor = (
        RuntimeReconciliationRequest,
        RuntimeSnapshotProvider
    ) -> ReconciliationExecutionOutcome

    private let snapshotQueue: DispatchQueue
    private let snapshotProvider: RuntimeSnapshotProvider
    private let windowRecencyTracker: RuntimeWindowRecencyTracker
    private let reconciliationExecutor: ReconciliationExecutor

    init(
        label: String = "FlowTab.RuntimeSnapshotService",
        snapshotProvider: RuntimeSnapshotProvider = RuntimeSnapshotProvider(),
        windowRecencyTracker: RuntimeWindowRecencyTracker = .shared,
        reconciliationExecutor: @escaping ReconciliationExecutor = RuntimeSnapshotService.defaultReconciliationExecutor
    ) {
        snapshotQueue = DispatchQueue(label: label, qos: .utility)
        self.snapshotProvider = snapshotProvider
        self.windowRecencyTracker = windowRecencyTracker
        self.reconciliationExecutor = reconciliationExecutor
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

    func signalSpaceTopologyChanged() {
        snapshotQueue.async { [self] in
            _ = snapshotProvider.collectCGWindowsByPID(options: [.excludeDesktopElements])
            drainReadyReconciliationRequestsLocked(now: Date.timeIntervalSinceReferenceDate)
        }
    }

    func signalAppWindowsChanged(appID: String, pid: pid_t) {
        snapshotQueue.async { [self] in
            let now = Date.timeIntervalSinceReferenceDate
            snapshotProvider.reconciliationCoordinator.markAppDirty(
                appID: appID,
                pid: pid,
                reason: .axNotification,
                now: now
            )
            drainReadyReconciliationRequestsLocked(now: now)
        }
    }

    func signalWindowFocusVerified(_ verification: RuntimeWindowFocusVerification) {
        snapshotQueue.async { [self] in
            let now = Date.timeIntervalSinceReferenceDate
            snapshotProvider.reconciliationCoordinator.markWindowFocusVerified(
                verification,
                now: now
            )
            drainReadyReconciliationRequestsLocked(now: now)
        }
    }

    func signalWindowFocusVerified(appID: String, pid: pid_t) {
        signalWindowFocusVerified(
            RuntimeWindowFocusVerification(
                appID: appID,
                windowID: "",
                ownerPID: pid,
                targetCGWindowID: nil,
                focusedCGWindowID: nil,
                title: "",
                frame: nil,
                allowedActions: []
            )
        )
    }

    func isLikelyTransientAXRebuild(for pid: pid_t) -> Bool {
        snapshotQueue.sync {
            snapshotProvider.isLikelyTransientAXRebuild(for: pid)
        }
    }

    @discardableResult
    func drainReadyReconciliationRequestsSynchronouslyForTesting(
        now: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) -> [RuntimeReconciliationRequest] {
        snapshotQueue.sync {
            drainReadyReconciliationRequestsLocked(now: now)
        }
    }

    @discardableResult
    private func drainReadyReconciliationRequestsLocked(now: TimeInterval) -> [RuntimeReconciliationRequest] {
        let coordinator = snapshotProvider.reconciliationCoordinator
        let requests = coordinator.readyRequests(now: now)
        var startedRequests: [RuntimeReconciliationRequest] = []
        startedRequests.reserveCapacity(requests.count)

        for request in requests {
            guard let startedRequest = coordinator.startRequest(id: request.id) else { continue }
            startedRequests.append(startedRequest)
            switch reconciliationExecutor(startedRequest, snapshotProvider) {
            case .completed:
                coordinator.completeRequest(id: startedRequest.id)
            case .transientEmptyAXSnapshot:
                _ = coordinator.scheduleRetryAfterTransientEmptyAXSnapshot(
                    id: startedRequest.id,
                    now: now
                )
            }
        }
        return startedRequests
    }

    private static func defaultReconciliationExecutor(
        request: RuntimeReconciliationRequest,
        snapshotProvider: RuntimeSnapshotProvider
    ) -> ReconciliationExecutionOutcome {
        switch request.target {
        case let .app(pid):
            let result = snapshotProvider.reconcileAppWindows(
                processIdentifier: pid,
                affectedCGWindowIDs: request.affectedCGWindowIDs
            )
            if result.isTransientEmptyAXSnapshot {
                return .transientEmptyAXSnapshot
            }
            return .completed
        case .spaceTopology:
            let cgWindowsByPID = snapshotProvider.collectCGWindowsByPID(options: [.excludeDesktopElements])
            let affectedTargets = snapshotProvider.appReconciliationTargets(
                affectedCGWindowIDs: request.affectedCGWindowIDs,
                currentCGWindowsByPID: cgWindowsByPID
            )
            for target in affectedTargets {
                let result = snapshotProvider.reconcileAppWindows(
                    processIdentifier: target.pid,
                    affectedCGWindowIDs: target.affectedCGWindowIDs
                )
                if result.isTransientEmptyAXSnapshot {
                    return .transientEmptyAXSnapshot
                }
            }
            return .completed
        }
    }
}
