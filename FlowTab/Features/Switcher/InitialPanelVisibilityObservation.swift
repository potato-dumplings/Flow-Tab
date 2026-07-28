import Foundation

enum InitialPanelVisibilityEvidenceSource: String, Equatable {
    case initialReadback
    case presentationActionReadback
    case panelOcclusionChanged
    case panelBecameKey
    case panelExposed
    case recoveryReadback
    case watchdogReadback
}

struct InitialPanelVisibilityEvidence: Equatable {
    let source: InitialPanelVisibilityEvidenceSource
    let observationGeneration: Int
    let presentationGeneration: Int
    let snapshot: PanelVisibilitySnapshot
}

struct InitialPanelVisibilityWatchdogFailure: Equatable {
    let trigger: String
    let observationGeneration: Int
    let presentationGeneration: Int
    let lastEventEvidence: InitialPanelVisibilityEvidence
    let finalEvidence: InitialPanelVisibilityEvidence

    var logFields: String {
        "condition=userVisible "
            + "lastEventSource=\(lastEventEvidence.source.rawValue) "
            + "lastEvent{\(lastEventEvidence.snapshot.logFields)} "
            + "finalSource=\(finalEvidence.source.rawValue) "
            + "final{\(finalEvidence.snapshot.logFields)}"
    }
}

@MainActor
protocol InitialPanelVisibilityObservationCancellable: AnyObject {
    func cancel()
}

@MainActor
protocol InitialPanelVisibilityObservationScheduling: AnyObject {
    func schedule(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any InitialPanelVisibilityObservationCancellable
}

@MainActor
private final class InitialPanelVisibilityObservationToken:
    InitialPanelVisibilityObservationCancellable
{
    private let task: Task<Void, Never>

    init(
        interval: TimeInterval,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        let nanoseconds = UInt64((interval * 1_000_000_000).rounded())
        task = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        task.cancel()
    }

    deinit {
        task.cancel()
    }
}

@MainActor
final class InitialPanelVisibilityObservationScheduler:
    InitialPanelVisibilityObservationScheduling
{
    func schedule(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any InitialPanelVisibilityObservationCancellable {
        InitialPanelVisibilityObservationToken(
            interval: interval,
            action: action
        )
    }
}

@MainActor
final class InitialPanelVisibilityObservationOwner {
    private struct PendingObservation {
        let generation: Int
        let trigger: String
        let presentationGeneration: Int
        let readback: @MainActor () -> PanelVisibilitySnapshot
        let onVisible: @MainActor (InitialPanelVisibilityEvidence) -> Void
        let onWatchdog:
            @MainActor (InitialPanelVisibilityWatchdogFailure) -> Void
        var lastEventEvidence: InitialPanelVisibilityEvidence?
        var watchdogToken:
            (any InitialPanelVisibilityObservationCancellable)?
    }

    private let scheduler: any InitialPanelVisibilityObservationScheduling
    private var pending: PendingObservation?

    private(set) var generation = 0
    private(set) var lastFailure: InitialPanelVisibilityWatchdogFailure?

    init(
        scheduler:
            (any InitialPanelVisibilityObservationScheduling)? = nil
    ) {
        self.scheduler = scheduler
            ?? InitialPanelVisibilityObservationScheduler()
    }

    var currentTrigger: String? {
        pending?.trigger
    }

    var currentPresentationGeneration: Int? {
        pending?.presentationGeneration
    }

    var lastEvidence: InitialPanelVisibilityEvidence? {
        pending?.lastEventEvidence
    }

    var hasPendingWatchdog: Bool {
        pending?.watchdogToken != nil
    }

    @discardableResult
    func start(
        trigger: String,
        presentationGeneration: Int,
        watchdogInterval: TimeInterval,
        readback: @escaping @MainActor () -> PanelVisibilitySnapshot,
        onVisible:
            @escaping @MainActor (InitialPanelVisibilityEvidence) -> Void,
        onWatchdog:
            @escaping @MainActor (InitialPanelVisibilityWatchdogFailure) -> Void
    ) -> Int {
        precondition(
            watchdogInterval > 0 && watchdogInterval.isFinite,
            "Initial panel visibility watchdog interval must be finite and positive."
        )
        cancel(invalidate: false)
        generation += 1
        let observationGeneration = generation
        lastFailure = nil
        pending = PendingObservation(
            generation: observationGeneration,
            trigger: trigger,
            presentationGeneration: presentationGeneration,
            readback: readback,
            onVisible: onVisible,
            onWatchdog: onWatchdog,
            lastEventEvidence: nil,
            watchdogToken: nil
        )

        if observe(
            source: .initialReadback,
            observationGeneration: observationGeneration,
            presentationGeneration: presentationGeneration
        ) {
            return observationGeneration
        }

        let token = scheduler.schedule(after: watchdogInterval) {
            [weak self] in
            self?.expireWatchdog(
                observationGeneration: observationGeneration,
                presentationGeneration: presentationGeneration
            )
        }
        guard var active = pending,
              active.generation == observationGeneration
        else {
            token.cancel()
            return observationGeneration
        }
        active.watchdogToken = token
        pending = active
        return observationGeneration
    }

    @discardableResult
    func observe(
        source: InitialPanelVisibilityEvidenceSource,
        observationGeneration: Int,
        presentationGeneration: Int
    ) -> Bool {
        guard var active = pending,
              active.generation == observationGeneration,
              active.presentationGeneration == presentationGeneration
        else {
            return false
        }
        let evidence = InitialPanelVisibilityEvidence(
            source: source,
            observationGeneration: observationGeneration,
            presentationGeneration: presentationGeneration,
            snapshot: active.readback()
        )
        active.lastEventEvidence = evidence
        pending = active
        guard evidence.snapshot.userVisible else { return false }
        finishVisible(
            evidence,
            observationGeneration: observationGeneration
        )
        return true
    }

    func cancel(invalidate: Bool) {
        pending?.watchdogToken?.cancel()
        pending = nil
        if invalidate {
            generation += 1
        }
    }

    func isObserving(
        observationGeneration: Int,
        presentationGeneration: Int
    ) -> Bool {
        pending?.generation == observationGeneration
            && pending?.presentationGeneration == presentationGeneration
    }

    private func expireWatchdog(
        observationGeneration: Int,
        presentationGeneration: Int
    ) {
        guard var active = pending,
              active.generation == observationGeneration,
              active.presentationGeneration == presentationGeneration
        else {
            return
        }
        let previousEvidence = active.lastEventEvidence
        let finalEvidence = InitialPanelVisibilityEvidence(
            source: .watchdogReadback,
            observationGeneration: observationGeneration,
            presentationGeneration: presentationGeneration,
            snapshot: active.readback()
        )
        active.lastEventEvidence = finalEvidence
        pending = active
        if finalEvidence.snapshot.userVisible {
            finishVisible(
                finalEvidence,
                observationGeneration: observationGeneration
            )
            return
        }

        guard let completed = takePending(
            observationGeneration: observationGeneration
        ) else {
            return
        }
        let failure = InitialPanelVisibilityWatchdogFailure(
            trigger: completed.trigger,
            observationGeneration: observationGeneration,
            presentationGeneration: presentationGeneration,
            lastEventEvidence: previousEvidence ?? finalEvidence,
            finalEvidence: finalEvidence
        )
        lastFailure = failure
        completed.onWatchdog(failure)
    }

    private func finishVisible(
        _ evidence: InitialPanelVisibilityEvidence,
        observationGeneration: Int
    ) {
        guard let completed = takePending(
            observationGeneration: observationGeneration
        ) else {
            return
        }
        completed.onVisible(evidence)
    }

    private func takePending(
        observationGeneration: Int
    ) -> PendingObservation? {
        guard let active = pending,
              active.generation == observationGeneration
        else {
            return nil
        }
        active.watchdogToken?.cancel()
        pending = nil
        return active
    }
}
