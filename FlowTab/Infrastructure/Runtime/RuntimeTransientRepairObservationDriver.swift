import Foundation

struct RuntimeTransientRepairObservationPolicy: Equatable {
    let intervals: [TimeInterval]
    let watchdogInterval: TimeInterval

    static let standard = RuntimeTransientRepairObservationPolicy(
        intervals: [0.1, 0.3, 0.8],
        watchdogInterval: 30
    )

    init(intervals: [TimeInterval], watchdogInterval: TimeInterval = 30) {
        precondition(
            !intervals.isEmpty && intervals.allSatisfy { $0 >= 0 },
            "Transient repair observation intervals must be non-empty and non-negative."
        )
        precondition(
            watchdogInterval > 0,
            "Transient repair observation watchdog interval must be positive."
        )
        self.intervals = intervals
        self.watchdogInterval = watchdogInterval
    }

    func interval(forAttempt attempt: Int) -> TimeInterval {
        let index = max(0, attempt - 1)
        return intervals[min(index, intervals.count - 1)]
    }
}

protocol RuntimeTransientRepairObservationCancellable: AnyObject {
    func cancel()
}

protocol RuntimeTransientRepairObservationScheduling: AnyObject {
    func schedule(
        after interval: TimeInterval,
        on queue: DispatchQueue,
        _ action: @escaping @Sendable () -> Void
    ) -> any RuntimeTransientRepairObservationCancellable
}

private final class RuntimeTransientRepairObservationToken:
    RuntimeTransientRepairObservationCancellable
{
    private let workItem: DispatchWorkItem

    init(workItem: DispatchWorkItem) {
        self.workItem = workItem
    }

    func cancel() {
        workItem.cancel()
    }
}

final class RuntimeTransientRepairObservationScheduler:
    RuntimeTransientRepairObservationScheduling
{
    func schedule(
        after interval: TimeInterval,
        on queue: DispatchQueue,
        _ action: @escaping @Sendable () -> Void
    ) -> any RuntimeTransientRepairObservationCancellable {
        let workItem = DispatchWorkItem(block: action)
        queue.asyncAfter(deadline: .now() + interval, execute: workItem)
        return RuntimeTransientRepairObservationToken(workItem: workItem)
    }
}

final class RuntimeTransientRepairObservationDriver {
    private struct PendingObservation {
        var request: RuntimeReconciliationRequest
        var interval: TimeInterval
        var readbackToken: (any RuntimeTransientRepairObservationCancellable)?
        let watchdogToken: any RuntimeTransientRepairObservationCancellable
    }

    private let ownerQueue: DispatchQueue
    private let scheduler: any RuntimeTransientRepairObservationScheduling
    private let policy: RuntimeTransientRepairObservationPolicy
    private var pendingByTarget:
        [RuntimeReconciliationTarget: PendingObservation] = [:]

    init(
        ownerQueue: DispatchQueue,
        scheduler: any RuntimeTransientRepairObservationScheduling,
        policy: RuntimeTransientRepairObservationPolicy = .standard
    ) {
        self.ownerQueue = ownerQueue
        self.scheduler = scheduler
        self.policy = policy
    }

    deinit {
        for pending in pendingByTarget.values {
            pending.readbackToken?.cancel()
            pending.watchdogToken.cancel()
        }
    }

    func schedule(
        _ request: RuntimeReconciliationRequest,
        onReadbackRequested: @escaping @Sendable (UInt64, Int) -> Void,
        onWatchdogExpired: @escaping @Sendable (RuntimeReconciliationRequest) -> Void
    ) {
        guard request.state == .waitingForEvidence else { return }

        let interval = policy.interval(forAttempt: request.attempt)
        if var pending = pendingByTarget[request.target],
           pending.request.id == request.id {
            pending.readbackToken?.cancel()
            pending.request = request
            pending.interval = interval
            pending.readbackToken = scheduleReadback(
                request: request,
                interval: interval,
                onReadbackRequested: onReadbackRequested
            )
            pendingByTarget[request.target] = pending
        } else {
            cancel(target: request.target, reason: "superseded")
            let watchdogToken = scheduler.schedule(
                after: policy.watchdogInterval,
                on: ownerQueue
            ) { [weak self] in
                self?.expireWatchdog(
                    target: request.target,
                    requestID: request.id,
                    onWatchdogExpired: onWatchdogExpired
                )
            }
            pendingByTarget[request.target] = PendingObservation(
                request: request,
                interval: interval,
                readbackToken: scheduleReadback(
                    request: request,
                    interval: interval,
                    onReadbackRequested: onReadbackRequested
                ),
                watchdogToken: watchdogToken
            )
        }
        RuntimeLog.debug(
            .projection,
            [
                "transientRepairObservation",
                "state=scheduled",
                "requestID=\(request.id)",
                "target=\(request.target.logValue)",
                "attempt=\(request.attempt)",
                "cadenceSeconds=\(interval)",
                "watchdogSeconds=\(policy.watchdogInterval)",
                "unmetConditions=\(request.evidenceRequirements.logValue)",
                "lastObservedAt=\(request.lastObservedAt)"
            ].joined(separator: " ")
        )
    }

    private func scheduleReadback(
        request: RuntimeReconciliationRequest,
        interval: TimeInterval,
        onReadbackRequested: @escaping @Sendable (UInt64, Int) -> Void
    ) -> any RuntimeTransientRepairObservationCancellable {
        scheduler.schedule(after: interval, on: ownerQueue) {
            [weak self] in
            self?.fire(
                target: request.target,
                requestID: request.id,
                attempt: request.attempt,
                onReadbackRequested: onReadbackRequested
            )
        }
    }

    func cancel(target: RuntimeReconciliationTarget, reason: String) {
        guard let pending = pendingByTarget.removeValue(forKey: target) else {
            return
        }
        pending.readbackToken?.cancel()
        pending.watchdogToken.cancel()
        RuntimeLog.debug(
            .projection,
            [
                "transientRepairObservation",
                "state=cancelled",
                "requestID=\(pending.request.id)",
                "target=\(target.logValue)",
                "attempt=\(pending.request.attempt)",
                "cadenceSeconds=\(pending.interval)",
                "unmetConditions=\(pending.request.evidenceRequirements.logValue)",
                "reason=\(reason)",
                "lastObservedAt=\(pending.request.lastObservedAt)"
            ].joined(separator: " ")
        )
    }

    func cancelApp(appID: String, pid: pid_t, reason: String) {
        let target = RuntimeReconciliationTarget.app(pid)
        guard pendingByTarget[target]?.request.appID == appID else { return }
        cancel(target: target, reason: reason)
    }

    func cancelScoped(reason: String) {
        for target in Array(pendingByTarget.keys) where target != .fullRepair {
            cancel(target: target, reason: reason)
        }
    }

    func cancelAll(reason: String) {
        for target in Array(pendingByTarget.keys) {
            cancel(target: target, reason: reason)
        }
    }

    private func fire(
        target: RuntimeReconciliationTarget,
        requestID: UInt64,
        attempt: Int,
        onReadbackRequested: @escaping @Sendable (UInt64, Int) -> Void
    ) {
        guard let pending = pendingByTarget[target],
              pending.request.id == requestID,
              pending.request.attempt == attempt
        else {
            return
        }
        var awaitingReadback = pending
        awaitingReadback.readbackToken = nil
        pendingByTarget[target] = awaitingReadback
        RuntimeLog.debug(
            .projection,
            [
                "transientRepairObservation",
                "state=readbackRequested",
                "requestID=\(requestID)",
                "target=\(target.logValue)",
                "attempt=\(attempt)",
                "unmetConditions=\(pending.request.evidenceRequirements.logValue)",
                "lastObservedAt=\(pending.request.lastObservedAt)"
            ].joined(separator: " ")
        )
        onReadbackRequested(requestID, attempt)
        if let current = pendingByTarget[target],
           current.request.id == requestID,
           current.request.attempt == attempt,
           current.readbackToken == nil {
            cancel(target: target, reason: "readbackFinished")
        }
    }

    private func expireWatchdog(
        target: RuntimeReconciliationTarget,
        requestID: UInt64,
        onWatchdogExpired: @escaping @Sendable (RuntimeReconciliationRequest) -> Void
    ) {
        guard let pending = pendingByTarget[target],
              pending.request.id == requestID
        else {
            return
        }
        pendingByTarget.removeValue(forKey: target)
        pending.readbackToken?.cancel()
        pending.watchdogToken.cancel()
        RuntimeLog.warning(
            .projection,
            [
                "transientRepairObservation",
                "state=watchdogExpired",
                "unmetConditions=\(pending.request.evidenceRequirements.logValue)",
                "requestID=\(requestID)",
                "target=\(target.logValue)",
                "appID=\(pending.request.appID ?? "nil")",
                "attempt=\(pending.request.attempt)",
                "watchdogSeconds=\(policy.watchdogInterval)",
                "lastObservedAt=\(pending.request.lastObservedAt)"
            ].joined(separator: " ")
        )
        onWatchdogExpired(pending.request)
    }
}

private extension Set
where Element == RuntimeReconciliationEvidenceRequirement {
    var logValue: String {
        map(\.rawValue).sorted().joined(separator: ",")
    }
}

private extension RuntimeReconciliationTarget {
    var logValue: String {
        switch self {
        case let .app(pid):
            "app:\(pid)"
        case .spaceTopology:
            "spaceTopology"
        case .fullRepair:
            "fullRepair"
        }
    }
}
