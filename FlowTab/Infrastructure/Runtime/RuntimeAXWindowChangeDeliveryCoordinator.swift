import Foundation

struct RuntimeAXWindowInitialReadbackEvidence: Equatable, Sendable {
    enum State: String, Equatable, Sendable {
        case matchesBaseline
        case changedSinceBaseline
        case unavailable
    }

    let state: State
    let expectedWindowCount: Int
    let knownSwitchableWindowCount: Int
    let observedSwitchableWindowCount: Int?
    let exactKnownWindowCount: Int
    let fetchErrorRawValue: Int32
    let rawValueTypeDescription: String

    var requiresReconciliation: Bool {
        state != .matchesBaseline
    }

    static func evaluate(
        expectedWindowCount: Int,
        knownSwitchableWindowCount: Int,
        observedSwitchableWindowCount: Int?,
        exactKnownWindowCount: Int,
        fetchErrorRawValue: Int32,
        rawValueTypeDescription: String
    ) -> RuntimeAXWindowInitialReadbackEvidence {
        guard let observedSwitchableWindowCount else {
            return RuntimeAXWindowInitialReadbackEvidence(
                state: .unavailable,
                expectedWindowCount: expectedWindowCount,
                knownSwitchableWindowCount: knownSwitchableWindowCount,
                observedSwitchableWindowCount: nil,
                exactKnownWindowCount: exactKnownWindowCount,
                fetchErrorRawValue: fetchErrorRawValue,
                rawValueTypeDescription: rawValueTypeDescription
            )
        }

        // Application-level AX windows can be a strict subset of the exact
        // elements retained by the registry, particularly for remote AX
        // recovery. A baseline changes only when its known count moves or the
        // public readback introduces an identity absent from that baseline.
        let matchesBaseline =
            knownSwitchableWindowCount == expectedWindowCount
            && exactKnownWindowCount == observedSwitchableWindowCount
        return RuntimeAXWindowInitialReadbackEvidence(
            state: matchesBaseline ? .matchesBaseline : .changedSinceBaseline,
            expectedWindowCount: expectedWindowCount,
            knownSwitchableWindowCount: knownSwitchableWindowCount,
            observedSwitchableWindowCount: observedSwitchableWindowCount,
            exactKnownWindowCount: exactKnownWindowCount,
            fetchErrorRawValue: fetchErrorRawValue,
            rawValueTypeDescription: rawValueTypeDescription
        )
    }
}

struct RuntimeAXWindowChangeEvidence: Equatable, Sendable {
    enum Source: String, Equatable, Sendable {
        case initialReadback
        case observedTransition
        case trailingReadback
    }

    let appID: String
    let pid: pid_t
    let generation: UInt64
    let source: Source
    let observedTransitionCount: Int
    let initialReadback: RuntimeAXWindowInitialReadbackEvidence?

    var requiresReconciliation: Bool {
        initialReadback?.requiresReconciliation ?? true
    }
}

struct RuntimeAXWindowChangeDeliveryPolicy: Equatable {
    let coalescingInterval: TimeInterval

    static let standardCoalesced = RuntimeAXWindowChangeDeliveryPolicy(
        coalescingInterval: 0.16
    )

    init(coalescingInterval: TimeInterval) {
        precondition(
            coalescingInterval > 0,
            "AX window change coalescing interval must be positive."
        )
        self.coalescingInterval = coalescingInterval
    }
}

@MainActor
protocol RuntimeAXWindowChangeDeliveryCancellable: AnyObject {
    func cancel()
}

@MainActor
protocol RuntimeAXWindowChangeDeliveryScheduling: AnyObject {
    func schedule(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any RuntimeAXWindowChangeDeliveryCancellable
}

@MainActor
private final class RuntimeAXWindowChangeDeliveryToken:
    RuntimeAXWindowChangeDeliveryCancellable
{
    private var task: Task<Void, Never>?

    init(
        interval: TimeInterval,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        let nanoseconds = UInt64((interval * 1_000_000_000).rounded())
        task = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            task = nil
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

@MainActor
final class RuntimeAXWindowChangeDeliveryScheduler:
    RuntimeAXWindowChangeDeliveryScheduling
{
    func schedule(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any RuntimeAXWindowChangeDeliveryCancellable {
        RuntimeAXWindowChangeDeliveryToken(
            interval: interval,
            action: action
        )
    }
}

@MainActor
final class RuntimeAXWindowChangeDeliveryCoordinator {
    private struct Binding {
        let appID: String
        let generation: UInt64
    }

    private struct PendingTrailingReadback {
        let bindingGeneration: UInt64
        var latestEvidenceGeneration: UInt64
        var observedTransitionCount: Int
        var token: any RuntimeAXWindowChangeDeliveryCancellable
    }

    var onEvidence: ((RuntimeAXWindowChangeEvidence) -> Void)?

    private let policy: RuntimeAXWindowChangeDeliveryPolicy
    private let scheduler: any RuntimeAXWindowChangeDeliveryScheduling
    private var nextBindingGeneration: UInt64 = 1
    private var bindingsByPID: [pid_t: Binding] = [:]
    private var nextEvidenceGenerationByPID: [pid_t: UInt64] = [:]
    private var pendingByPID: [pid_t: PendingTrailingReadback] = [:]

    init(
        policy: RuntimeAXWindowChangeDeliveryPolicy,
        scheduler: (any RuntimeAXWindowChangeDeliveryScheduling)? = nil
    ) {
        self.policy = policy
        self.scheduler =
            scheduler ?? RuntimeAXWindowChangeDeliveryScheduler()
    }

    @discardableResult
    func bind(appID: String, pid: pid_t) -> UInt64 {
        unbind(pid: pid)
        let generation = nextBindingGeneration
        nextBindingGeneration &+= 1
        bindingsByPID[pid] = Binding(
            appID: appID,
            generation: generation
        )
        if nextEvidenceGenerationByPID[pid] == nil {
            nextEvidenceGenerationByPID[pid] = 1
        }
        return generation
    }

    func publishInitialReadback(
        pid: pid_t,
        bindingGeneration: UInt64,
        readback: RuntimeAXWindowInitialReadbackEvidence
    ) {
        guard let evidence = makeEvidence(
            pid: pid,
            bindingGeneration: bindingGeneration,
            source: .initialReadback,
            observedTransitionCount: 0,
            initialReadback: readback
        ) else {
            return
        }
        publish(evidence)
    }

    func recordObservedTransition(pid: pid_t, bindingGeneration: UInt64) {
        guard let evidence = makeEvidence(
            pid: pid,
            bindingGeneration: bindingGeneration,
            source: .observedTransition,
            observedTransitionCount: 1,
            initialReadback: nil
        ) else {
            return
        }

        if var pending = pendingByPID[pid],
           pending.bindingGeneration == bindingGeneration {
            pending.token.cancel()
            pending.latestEvidenceGeneration = evidence.generation
            pending.observedTransitionCount += 1
            pending.token = scheduleTrailingReadback(
                pid: pid,
                bindingGeneration: bindingGeneration,
                latestEvidenceGeneration: evidence.generation
            )
            pendingByPID[pid] = pending
            return
        }

        pendingByPID[pid] = PendingTrailingReadback(
            bindingGeneration: bindingGeneration,
            latestEvidenceGeneration: evidence.generation,
            observedTransitionCount: 1,
            token: scheduleTrailingReadback(
                pid: pid,
                bindingGeneration: bindingGeneration,
                latestEvidenceGeneration: evidence.generation
            )
        )
    }

    func unbind(pid: pid_t, bindingGeneration: UInt64? = nil) {
        if let bindingGeneration,
           bindingsByPID[pid]?.generation != bindingGeneration {
            return
        }
        cancelPendingReadback(pid: pid)
        bindingsByPID.removeValue(forKey: pid)
    }

    func stop() {
        for pid in Array(pendingByPID.keys) {
            cancelPendingReadback(pid: pid)
        }
        bindingsByPID.removeAll()
    }

    private func makeEvidence(
        pid: pid_t,
        bindingGeneration: UInt64,
        source: RuntimeAXWindowChangeEvidence.Source,
        observedTransitionCount: Int,
        initialReadback: RuntimeAXWindowInitialReadbackEvidence?
    ) -> RuntimeAXWindowChangeEvidence? {
        guard let binding = bindingsByPID[pid],
              binding.generation == bindingGeneration
        else {
            return nil
        }
        let generation = nextEvidenceGenerationByPID[pid] ?? 1
        let evidence = RuntimeAXWindowChangeEvidence(
            appID: binding.appID,
            pid: pid,
            generation: generation,
            source: source,
            observedTransitionCount: observedTransitionCount,
            initialReadback: initialReadback
        )
        nextEvidenceGenerationByPID[pid] = generation &+ 1
        return evidence
    }

    private func publishTrailingReadback(
        pid: pid_t,
        bindingGeneration: UInt64,
        latestEvidenceGeneration: UInt64
    ) {
        guard let pending = pendingByPID[pid],
              pending.bindingGeneration == bindingGeneration,
              pending.latestEvidenceGeneration == latestEvidenceGeneration
        else {
            return
        }
        pendingByPID.removeValue(forKey: pid)
        guard let binding = bindingsByPID[pid],
              binding.generation == bindingGeneration
        else {
            return
        }
        publish(
            RuntimeAXWindowChangeEvidence(
                appID: binding.appID,
                pid: pid,
                generation: pending.latestEvidenceGeneration,
                source: .trailingReadback,
                observedTransitionCount: pending.observedTransitionCount,
                initialReadback: nil
            )
        )
    }

    private func scheduleTrailingReadback(
        pid: pid_t,
        bindingGeneration: UInt64,
        latestEvidenceGeneration: UInt64
    ) -> any RuntimeAXWindowChangeDeliveryCancellable {
        scheduler.schedule(after: policy.coalescingInterval) {
            [weak self] in
            self?.publishTrailingReadback(
                pid: pid,
                bindingGeneration: bindingGeneration,
                latestEvidenceGeneration: latestEvidenceGeneration
            )
        }
    }

    private func cancelPendingReadback(pid: pid_t) {
        pendingByPID.removeValue(forKey: pid)?.token.cancel()
    }

    private func publish(_ evidence: RuntimeAXWindowChangeEvidence) {
        RuntimeLog.debug(
            .axObserver,
            [
                "runtimeAXWindowEvidence",
                "appID=\(evidence.appID)",
                "pid=\(evidence.pid)",
                "generation=\(evidence.generation)",
                "source=\(evidence.source.rawValue)",
                "observedTransitions=\(evidence.observedTransitionCount)",
                "requiresReconciliation=\(evidence.requiresReconciliation ? 1 : 0)",
                initialReadbackLogDetails(evidence.initialReadback)
            ].joined(separator: " ")
        )
        onEvidence?(evidence)
    }

    private func initialReadbackLogDetails(
        _ readback: RuntimeAXWindowInitialReadbackEvidence?
    ) -> String {
        guard let readback else { return "initialReadback=none" }
        return [
            "initialReadback=\(readback.state.rawValue)",
            "expectedWindows=\(readback.expectedWindowCount)",
            "knownWindows=\(readback.knownSwitchableWindowCount)",
            "observedWindows=\(readback.observedSwitchableWindowCount.map(String.init) ?? "unavailable")",
            "exactKnownWindows=\(readback.exactKnownWindowCount)",
            "fetchError=\(readback.fetchErrorRawValue)",
            "rawValueType=\(readback.rawValueTypeDescription)"
        ].joined(separator: " ")
    }
}
