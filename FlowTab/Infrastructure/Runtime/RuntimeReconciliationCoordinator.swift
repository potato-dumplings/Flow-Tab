import CoreGraphics
import Foundation

enum RuntimeReconciliationReason: String, Hashable {
    case axNotification
    case activationVerified
    case appLaunched
    case spaceTopologyChanged
    case manualRefresh

    var schedulerPriority: RuntimeReconciliationPriority {
        switch self {
        case .activationVerified, .appLaunched:
            .high
        case .axNotification, .spaceTopologyChanged:
            .normal
        case .manualRefresh:
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

enum RuntimeReconciliationTarget: Hashable {
    case app(pid_t)
    case spaceTopology
}

enum RuntimeReconciliationState: String, Equatable {
    case pending
    case inFlight
    case waitingRetry
}

struct RuntimeReconciliationRetryPolicy: Equatable {
    let delays: [TimeInterval]

    static let axEmptySnapshot = RuntimeReconciliationRetryPolicy(
        delays: [0.1, 0.3, 0.8]
    )

    func delay(forAttempt attempt: Int) -> TimeInterval? {
        guard attempt >= 0, attempt < delays.count else { return nil }
        return delays[attempt]
    }
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
    var notBefore: TimeInterval
}

final class RuntimeReconciliationCoordinator {
    private var nextRequestID: UInt64 = 1
    private var requestsByTarget: [RuntimeReconciliationTarget: RuntimeReconciliationRequest] = [:]
    private var currentSpaceTopologySnapshot: RuntimeSpaceTopologySnapshot?
    private let retryPolicy: RuntimeReconciliationRetryPolicy

    init(retryPolicy: RuntimeReconciliationRetryPolicy = .axEmptySnapshot) {
        self.retryPolicy = retryPolicy
    }

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
        updateRequest(
            target: .spaceTopology,
            appID: nil,
            reasons: [.spaceTopologyChanged],
            affectedCGWindowIDs: diff.affectedCGWindowIDs,
            now: now
        )
        return diff
    }

    func readyRequests(now: TimeInterval) -> [RuntimeReconciliationRequest] {
        requestsByTarget.values
            .filter { $0.notBefore <= now && $0.state != .inFlight }
            .sorted {
                if $0.priority == $1.priority {
                    return $0.id < $1.id
                }
                return $0.priority > $1.priority
            }
    }

    @discardableResult
    func startRequest(id: UInt64) -> RuntimeReconciliationRequest? {
        guard let target = target(for: id) else { return nil }
        requestsByTarget[target]?.state = .inFlight
        return requestsByTarget[target]
    }

    @discardableResult
    func scheduleRetryAfterTransientEmptyAXSnapshot(
        id: UInt64,
        now: TimeInterval
    ) -> RuntimeReconciliationRequest? {
        guard let target = target(for: id), var request = requestsByTarget[target] else {
            return nil
        }
        guard let delay = retryPolicy.delay(forAttempt: request.attempt) else {
            requestsByTarget.removeValue(forKey: target)
            return nil
        }
        request.attempt += 1
        request.notBefore = now + delay
        request.state = .waitingRetry
        requestsByTarget[target] = request
        return request
    }

    func completeRequest(id: UInt64) {
        guard let target = target(for: id) else { return }
        requestsByTarget.removeValue(forKey: target)
    }

    func cancelAppRequests(pid: pid_t) {
        requestsByTarget.removeValue(forKey: .app(pid))
    }

    private func updateRequest(
        target: RuntimeReconciliationTarget,
        appID: String?,
        reasons: Set<RuntimeReconciliationReason>,
        affectedCGWindowIDs: Set<CGWindowID>,
        now: TimeInterval
    ) -> RuntimeReconciliationRequest {
        var request = requestsByTarget[target] ?? RuntimeReconciliationRequest(
            id: nextRequestID,
            target: target,
            appID: appID,
            reasons: [],
            priority: reasons.schedulerPriority,
            affectedCGWindowIDs: [],
            state: .pending,
            attempt: 0,
            notBefore: now
        )
        if requestsByTarget[target] == nil {
            nextRequestID += 1
        }
        let incomingPriority = reasons.schedulerPriority
        let promoted = incomingPriority > request.priority
        request.appID = request.appID ?? appID
        request.reasons.formUnion(reasons)
        request.priority = max(request.priority, incomingPriority)
        request.affectedCGWindowIDs.formUnion(affectedCGWindowIDs)
        request.state = .pending
        if promoted {
            request.attempt = 0
            request.notBefore = now
        } else {
            request.notBefore = min(request.notBefore, now)
        }
        requestsByTarget[target] = request
        return request
    }

    private func target(for id: UInt64) -> RuntimeReconciliationTarget? {
        requestsByTarget.first { $0.value.id == id }?.key
    }
}

private extension Set where Element == RuntimeReconciliationReason {
    var schedulerPriority: RuntimeReconciliationPriority {
        map(\.schedulerPriority).max() ?? .normal
    }
}
