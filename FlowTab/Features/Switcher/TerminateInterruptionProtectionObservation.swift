import Foundation

@MainActor
final class TerminateInterruptionProtectionObservationOwner {
    private struct PreparedObservation {
        let generation: Int
        let trigger: String
        let presentationGeneration: Int
        let baseline: TerminateInterruptionProtectionBaseline
    }

    struct ActiveObservation {
        let generation: Int
        let trigger: String
        let presentationGeneration: Int
        let target: TerminateInterruptionTargetIdentity
        let baseline: TerminateInterruptionProtectionBaseline
        let readback:
            @MainActor () -> TerminateInterruptionProtectionSnapshot
        let onResolved:
            @MainActor (TerminateInterruptionProtectionEvidence) -> Void
        let onWatchdog:
            @MainActor (TerminateInterruptionProtectionWatchdogFailure) -> Void
        var matchingTerminationObserved: Bool
        var protectedSystemInterruptionObserved: Bool
        var terminationConditionObserved: Bool
        var lastEvidence: TerminateInterruptionProtectionEvidence
        var watchdogToken:
            (any TerminateInterruptionProtectionCancellable)?
    }

    private let scheduler: any TerminateInterruptionProtectionScheduling
    private var prepared: PreparedObservation?
    private var active: ActiveObservation?

    private(set) var generation = 0
    private(set) var lastFailure:
        TerminateInterruptionProtectionWatchdogFailure?

    init(
        scheduler:
            (any TerminateInterruptionProtectionScheduling)? = nil
    ) {
        self.scheduler = scheduler
            ?? TerminateInterruptionProtectionScheduler()
    }

    var isPrepared: Bool {
        prepared != nil
    }

    var isObserving: Bool {
        active != nil
    }

    var target: TerminateInterruptionTargetIdentity? {
        active?.target
    }

    var lastEvidence: TerminateInterruptionProtectionEvidence? {
        active?.lastEvidence
    }

    @discardableResult
    func prepareRequest(
        trigger: String,
        presentationGeneration: Int,
        baseline: TerminateInterruptionProtectionBaseline
    ) -> Int {
        cancel(invalidate: false)
        generation += 1
        lastFailure = nil
        prepared = PreparedObservation(
            generation: generation,
            trigger: trigger,
            presentationGeneration: presentationGeneration,
            baseline: baseline
        )
        return generation
    }

    @discardableResult
    func commitPreparedRequest(
        observationGeneration: Int,
        target: TerminateInterruptionTargetIdentity,
        watchdogInterval: TimeInterval,
        readback:
            @escaping @MainActor () -> TerminateInterruptionProtectionSnapshot,
        onResolved:
            @escaping @MainActor (TerminateInterruptionProtectionEvidence) -> Void,
        onWatchdog:
            @escaping @MainActor (TerminateInterruptionProtectionWatchdogFailure) -> Void
    ) -> Bool {
        guard let prepared,
              prepared.generation == observationGeneration,
              prepared.baseline.appID == target.appID
        else {
            return false
        }
        self.prepared = nil
        startActive(
            generation: prepared.generation,
            trigger: prepared.trigger,
            presentationGeneration: prepared.presentationGeneration,
            target: target,
            baseline: prepared.baseline,
            matchingTerminationObserved: false,
            initialSource: .requestReturnReadback,
            watchdogInterval: watchdogInterval,
            readback: readback,
            onResolved: onResolved,
            onWatchdog: onWatchdog
        )
        return true
    }

    @discardableResult
    func startObservedTermination(
        trigger: String,
        presentationGeneration: Int,
        target: TerminateInterruptionTargetIdentity,
        baseline: TerminateInterruptionProtectionBaseline,
        watchdogInterval: TimeInterval,
        readback:
            @escaping @MainActor () -> TerminateInterruptionProtectionSnapshot,
        onResolved:
            @escaping @MainActor (TerminateInterruptionProtectionEvidence) -> Void,
        onWatchdog:
            @escaping @MainActor (TerminateInterruptionProtectionWatchdogFailure) -> Void
    ) -> Int {
        cancel(invalidate: false)
        generation += 1
        lastFailure = nil
        startActive(
            generation: generation,
            trigger: trigger,
            presentationGeneration: presentationGeneration,
            target: target,
            baseline: baseline,
            matchingTerminationObserved: true,
            initialSource: .workspaceTerminationReadback,
            watchdogInterval: watchdogInterval,
            readback: readback,
            onResolved: onResolved,
            onWatchdog: onWatchdog
        )
        return generation
    }

    @discardableResult
    func observeWorkspaceTermination(
        appID: String,
        pid: pid_t,
        presentationGeneration: Int
    ) -> Bool {
        guard var active = matchingActive(
            presentationGeneration: presentationGeneration
        ) else {
            return false
        }
        if active.target.appID == appID && active.target.pid == pid {
            active.matchingTerminationObserved = true
        }
        self.active = active
        return observe(
            source: .workspaceTerminationReadback,
            presentationGeneration: presentationGeneration
        )
    }

    @discardableResult
    func observeProjectionUpdate(
        presentationGeneration: Int
    ) -> Bool {
        observe(
            source: .projectionUpdateReadback,
            presentationGeneration: presentationGeneration
        )
    }

    @discardableResult
    func observePresentationUpdate(
        source: TerminateInterruptionProtectionEvidenceSource,
        presentationGeneration: Int
    ) -> Bool {
        precondition(
            source == .activeSpaceTransitionReadback
                || source == .panelVisibilityReadback,
            "Presentation updates require a presentation evidence source."
        )
        return observe(
            source: source,
            presentationGeneration: presentationGeneration
        )
    }

    @discardableResult
    func observeProtectedSystemInterruption(
        presentationGeneration: Int
    ) -> Bool {
        guard var active = matchingActive(
            presentationGeneration: presentationGeneration
        ) else {
            return false
        }
        active.protectedSystemInterruptionObserved = true
        self.active = active
        return observe(
            source: .systemInterruptionReadback,
            presentationGeneration: presentationGeneration
        )
    }

    func cancelPreparedRequest(observationGeneration: Int) {
        guard prepared?.generation == observationGeneration else { return }
        prepared = nil
    }

    func cancel(invalidate: Bool = true) {
        active?.watchdogToken?.cancel()
        prepared = nil
        active = nil
        if invalidate {
            generation += 1
        }
    }

    private func startActive(
        generation: Int,
        trigger: String,
        presentationGeneration: Int,
        target: TerminateInterruptionTargetIdentity,
        baseline: TerminateInterruptionProtectionBaseline,
        matchingTerminationObserved: Bool,
        initialSource: TerminateInterruptionProtectionEvidenceSource,
        watchdogInterval: TimeInterval,
        readback:
            @escaping @MainActor () -> TerminateInterruptionProtectionSnapshot,
        onResolved:
            @escaping @MainActor (TerminateInterruptionProtectionEvidence) -> Void,
        onWatchdog:
            @escaping @MainActor (TerminateInterruptionProtectionWatchdogFailure) -> Void
    ) {
        precondition(
            watchdogInterval > 0 && watchdogInterval.isFinite,
            "Terminate interruption watchdog must be finite and positive."
        )
        let initialSnapshot = readback()
        let initialEvidence = TerminateInterruptionProtectionEvidence(
            source: initialSource,
            observationGeneration: generation,
            presentationGeneration: presentationGeneration,
            target: target,
            baseline: baseline,
            matchingTerminationObserved: matchingTerminationObserved,
            protectedSystemInterruptionObserved: false,
            snapshot: initialSnapshot
        )
        active = ActiveObservation(
            generation: generation,
            trigger: trigger,
            presentationGeneration: presentationGeneration,
            target: target,
            baseline: baseline,
            readback: readback,
            onResolved: onResolved,
            onWatchdog: onWatchdog,
            matchingTerminationObserved: matchingTerminationObserved,
            protectedSystemInterruptionObserved: false,
            terminationConditionObserved: false,
            lastEvidence: initialEvidence
        )
        if recordEvidenceAndResolve(initialEvidence) {
            return
        }
        if active?.terminationConditionObserved == true {
            return
        }
        let token = scheduler.scheduleWatchdog(
            after: watchdogInterval
        ) { [weak self] in
            self?.expireWatchdog(
                observationGeneration: generation,
                presentationGeneration: presentationGeneration
            )
        }
        guard var current = matchingActive(
            observationGeneration: generation,
            presentationGeneration: presentationGeneration
        ) else {
            token.cancel()
            return
        }
        current.watchdogToken = token
        active = current
    }

    @discardableResult
    private func observe(
        source: TerminateInterruptionProtectionEvidenceSource,
        presentationGeneration: Int
    ) -> Bool {
        guard let current = matchingActive(
            presentationGeneration: presentationGeneration
        ) else {
            return false
        }
        let evidence = makeEvidence(source: source, active: current)
        return recordEvidenceAndResolve(evidence)
    }

    private func expireWatchdog(
        observationGeneration: Int,
        presentationGeneration: Int
    ) {
        guard let current = matchingActive(
            observationGeneration: observationGeneration,
            presentationGeneration: presentationGeneration
        ) else {
            return
        }
        let finalEvidence = makeEvidence(
            source: .watchdogReadback,
            active: current
        )
        let previousEvidence = current.lastEvidence
        if recordEvidenceAndResolve(finalEvidence) {
            return
        }
        if active?.terminationConditionObserved == true {
            return
        }
        guard let completed = takeActive() else { return }
        let failure = TerminateInterruptionProtectionWatchdogFailure(
            trigger: completed.trigger,
            observationGeneration: completed.generation,
            presentationGeneration: completed.presentationGeneration,
            target: completed.target,
            baseline: completed.baseline,
            lastEvidence: previousEvidence,
            finalEvidence: finalEvidence
        )
        lastFailure = failure
        completed.onWatchdog(failure)
    }

    private func recordEvidenceAndResolve(
        _ evidence: TerminateInterruptionProtectionEvidence
    ) -> Bool {
        guard var current = matchingActive(
            observationGeneration: evidence.observationGeneration,
            presentationGeneration: evidence.presentationGeneration
        ) else {
            return false
        }
        current.lastEvidence = evidence
        if terminationConditionSatisfied(evidence) {
            current.terminationConditionObserved = true
            current.watchdogToken?.cancel()
            current.watchdogToken = nil
        }
        active = current
        guard current.terminationConditionObserved else {
            return false
        }
        return resolveFromPersistedTerminationCondition(evidence)
    }

    private func resolveFromPersistedTerminationCondition(
        _ evidence: TerminateInterruptionProtectionEvidence
    ) -> Bool {
        guard presentationConditionSatisfied(evidence) else {
            return false
        }
        guard let completed = takeActive() else { return false }
        completed.onResolved(evidence)
        return true
    }

    private func takeActive() -> ActiveObservation? {
        guard let active else { return nil }
        active.watchdogToken?.cancel()
        self.active = nil
        return active
    }

    private func matchingActive(
        observationGeneration: Int? = nil,
        presentationGeneration: Int
    ) -> ActiveObservation? {
        guard let active,
              observationGeneration == nil
                || active.generation == observationGeneration,
              active.presentationGeneration == presentationGeneration
        else {
            return nil
        }
        return active
    }
}
