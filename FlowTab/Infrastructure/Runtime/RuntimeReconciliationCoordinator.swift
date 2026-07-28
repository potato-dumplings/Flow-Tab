import CoreGraphics
import Foundation

enum RuntimeReconciliationReason: String, Hashable {
    case axNotification
    case activationReadbackMismatch
    case activationVerified
    case appLaunched
    case searchFreshnessBarrier
    case selectedCurrentAppWindows
    case spaceTopologyChanged
    case fullRepairFallback
    case manualRefresh

    var schedulerPriority: RuntimeReconciliationPriority {
        switch self {
        case .activationReadbackMismatch,
             .activationVerified,
             .appLaunched,
             .searchFreshnessBarrier,
             .selectedCurrentAppWindows:
            .high
        case .axNotification, .spaceTopologyChanged:
            .normal
        case .fullRepairFallback, .manualRefresh:
            .low
        }
    }
}

enum RuntimeReconciliationPriority: Int, Comparable {
    case low = 0
    case normal = 10
    case high = 20

    static func < (lhs: RuntimeReconciliationPriority, rhs: RuntimeReconciliationPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum RuntimeReconciliationTarget: Hashable, Sendable {
    case app(pid_t)
    case spaceTopology
    case fullRepair
}

enum RuntimeReconciliationState: String, Equatable {
    case pending
    case inFlight
    case waitingForEvidence
}

struct RuntimeReconciliationRequest: Equatable, Identifiable {
    let id: UInt64
    let target: RuntimeReconciliationTarget
    var appID: String?
    var reasons: Set<RuntimeReconciliationReason>
    var priority: RuntimeReconciliationPriority
    var affectedCGWindowIDs: Set<CGWindowID>
    var state: RuntimeReconciliationState
    var attempt: Int
    var lastObservedAt: TimeInterval
}

final class RuntimeReconciliationCoordinator {
    private var nextRequestID: UInt64 = 1
    private var requestsByTarget: [RuntimeReconciliationTarget: RuntimeReconciliationRequest] = [:]
    private var currentSpaceTopologySnapshot: RuntimeSpaceTopologySnapshot?

    @discardableResult
    func markAppDirty(
        appID: String,
        pid: pid_t,
        reason: RuntimeReconciliationReason,
        affectedCGWindowIDs: Set<CGWindowID> = [],
        now: TimeInterval
    ) -> RuntimeReconciliationRequest {
        updateRequest(
            target: .app(pid),
            appID: appID,
            reasons: [reason],
            affectedCGWindowIDs: affectedCGWindowIDs,
            now: now
        )
    }

    @discardableResult
    func markWindowFocusVerified(
        _ verification: RuntimeWindowFocusVerification,
        now: TimeInterval
    ) -> RuntimeReconciliationRequest {
        updateRequest(
            target: .app(verification.ownerPID),
            appID: verification.appID,
            reasons: [.activationVerified],
            affectedCGWindowIDs: verification.affectedCGWindowIDs,
            now: now
        )
    }

    @discardableResult
    func applySpaceTopologySnapshot(
        _ snapshot: RuntimeSpaceTopologySnapshot,
        now: TimeInterval
    ) -> RuntimeSpaceTopologyDiff {
        let diff = snapshot.diff(from: currentSpaceTopologySnapshot)
        currentSpaceTopologySnapshot = snapshot
        guard !diff.affectedCGWindowIDs.isEmpty else { return diff }
        _ = updateRequest(
            target: .spaceTopology,
            appID: nil,
            reasons: [.spaceTopologyChanged],
            affectedCGWindowIDs: diff.affectedCGWindowIDs,
            now: now
        )
        return diff
    }

    @discardableResult
    func markSpaceTopologyDirty(
        affectedCGWindowIDs: Set<CGWindowID>,
        now: TimeInterval
    ) -> RuntimeReconciliationRequest {
        updateRequest(
            target: .spaceTopology,
            appID: nil,
            reasons: [.spaceTopologyChanged],
            affectedCGWindowIDs: affectedCGWindowIDs,
            now: now
        )
    }

    @discardableResult
    func scheduleFullRepairFallback(now: TimeInterval) -> RuntimeReconciliationRequest {
        updateRequest(
            target: .fullRepair,
            appID: nil,
            reasons: [.fullRepairFallback],
            affectedCGWindowIDs: [],
            now: now
        )
    }

    func readyRequests(includeFullRepair: Bool = true) -> [RuntimeReconciliationRequest] {
        let hasScopedRequests = requestsByTarget.values.contains { $0.target != .fullRepair }
        return requestsByTarget.values
            .filter {
                $0.state == .pending
                    && (includeFullRepair || $0.target != .fullRepair)
                    && !(includeFullRepair && $0.target == .fullRepair && hasScopedRequests)
            }
            .sorted {
                if $0.priority == $1.priority {
                    return $0.id < $1.id
                }
                return $0.priority > $1.priority
            }
    }

    func hasPendingRequests(includeFullRepair: Bool = true) -> Bool {
        requestsByTarget.values.contains {
            includeFullRepair || $0.target != .fullRepair
        }
    }

    func pendingScopedAffectedCGWindowIDs() -> Set<CGWindowID> {
        requestsByTarget.values.reduce(into: Set<CGWindowID>()) { result, request in
            guard request.target != .fullRepair else { return }
            result.formUnion(request.affectedCGWindowIDs)
        }
    }

    @discardableResult
    func promotePendingRequests(
        reason: RuntimeReconciliationReason,
        now: TimeInterval,
        includeFullRepair: Bool = false
    ) -> [RuntimeReconciliationRequest] {
        requestsByTarget.values
            .filter {
                $0.state != .inFlight
                    && (includeFullRepair || $0.target != .fullRepair)
            }
            .sorted { $0.id < $1.id }
            .map { request in
                updateRequest(
                    target: request.target,
                    appID: request.appID,
                    reasons: [reason],
                    affectedCGWindowIDs: request.affectedCGWindowIDs,
                    now: now
                )
            }
    }

    @discardableResult
    func startRequest(id: UInt64) -> RuntimeReconciliationRequest? {
        guard let target = target(for: id),
              requestsByTarget[target]?.state == .pending
        else {
            return nil
        }
        requestsByTarget[target]?.state = .inFlight
        return requestsByTarget[target]
    }

    @discardableResult
    func deferRequestAfterTransientEmptyCurrentAppWindowPayload(
        id: UInt64,
        now: TimeInterval
    ) -> RuntimeReconciliationRequest? {
        guard let target = target(for: id),
              var request = requestsByTarget[target],
              request.state == .inFlight
        else {
            return nil
        }
        request.attempt += 1
        request.lastObservedAt = now
        request.state = .waitingForEvidence
        requestsByTarget[target] = request
        return request
    }

    @discardableResult
    func resumeDeferredRequestForConditionReadback(
        id: UInt64,
        attempt: Int,
        now: TimeInterval
    ) -> RuntimeReconciliationRequest? {
        guard let target = target(for: id),
              var request = requestsByTarget[target],
              request.state == .waitingForEvidence,
              request.attempt == attempt
        else {
            return nil
        }
        request.state = .pending
        request.lastObservedAt = now
        requestsByTarget[target] = request
        return request
    }

    @discardableResult
    func failDeferredRequestAfterObservationWatchdog(
        id: UInt64,
        attempt: Int
    ) -> RuntimeReconciliationRequest? {
        guard let target = target(for: id),
              let request = requestsByTarget[target],
              request.state == .waitingForEvidence,
              request.attempt == attempt
        else {
            return nil
        }
        requestsByTarget.removeValue(forKey: target)
        return request
    }

    func completeRequest(id: UInt64) {
        guard let target = target(for: id) else { return }
        requestsByTarget.removeValue(forKey: target)
    }

    func pendingAppID(pid: pid_t) -> String? {
        requestsByTarget[.app(pid)]?.appID
    }

    func cancelAppRequests(appID: String, pid: pid_t) {
        guard requestsByTarget[.app(pid)]?.appID == appID else { return }
        requestsByTarget.removeValue(forKey: .app(pid))
    }

    private func updateRequest(
        target: RuntimeReconciliationTarget,
        appID: String?,
        reasons: Set<RuntimeReconciliationReason>,
        affectedCGWindowIDs: Set<CGWindowID>,
        now: TimeInterval
    ) -> RuntimeReconciliationRequest {
        let existingRequest = requestsByTarget[target]
        let replacesAppInstance: Bool
        if case .app = target,
           let existingAppID = existingRequest?.appID,
           let appID {
            replacesAppInstance = existingAppID != appID
        } else {
            replacesAppInstance = false
        }
        var request: RuntimeReconciliationRequest
        if let existingRequest, !replacesAppInstance {
            request = existingRequest
        } else {
            request = RuntimeReconciliationRequest(
                id: nextRequestID,
                target: target,
                appID: appID,
                reasons: [],
                priority: reasons.schedulerPriority,
                affectedCGWindowIDs: [],
                state: .pending,
                attempt: 0,
                lastObservedAt: now
            )
            nextRequestID += 1
        }
        let incomingPriority = reasons.schedulerPriority
        let promoted = incomingPriority > request.priority
        request.appID = request.appID ?? appID
        request.reasons.formUnion(reasons)
        request.priority = max(request.priority, incomingPriority)
        request.affectedCGWindowIDs.formUnion(affectedCGWindowIDs)
        request.lastObservedAt = now
        if promoted {
            request.attempt = 0
        }
        request.state = .pending
        requestsByTarget[target] = request
        cancelPendingFullRepairForHigherPriorityScopedRepair(
            target: target,
            incomingPriority: incomingPriority
        )
        return request
    }

    private func target(for id: UInt64) -> RuntimeReconciliationTarget? {
        requestsByTarget.first { $0.value.id == id }?.key
    }

    private func cancelPendingFullRepairForHigherPriorityScopedRepair(
        target: RuntimeReconciliationTarget,
        incomingPriority: RuntimeReconciliationPriority
    ) {
        guard target != .fullRepair else { return }
        guard let fullRepair = requestsByTarget[.fullRepair] else { return }
        guard fullRepair.state != .inFlight, incomingPriority > fullRepair.priority else { return }
        requestsByTarget.removeValue(forKey: .fullRepair)
    }
}

private extension Set where Element == RuntimeReconciliationReason {
    var schedulerPriority: RuntimeReconciliationPriority {
        map(\.schedulerPriority).max() ?? .normal
    }
}
