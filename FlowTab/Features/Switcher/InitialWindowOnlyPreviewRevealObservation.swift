import Foundation

struct InitialWindowOnlyPreviewRevealPolicy: Equatable {
    let degradedRevealWatchdogInterval: TimeInterval

    static let `default` = InitialWindowOnlyPreviewRevealPolicy(
        degradedRevealWatchdogInterval: 0.25
    )
}

struct InitialWindowOnlyPreviewReadinessSnapshot: Equatable {
    let pendingCaptureCount: Int

    var previewsReady: Bool {
        pendingCaptureCount == 0
    }

    var logFields: String {
        "previewsReady=\(previewsReady ? 1 : 0) "
            + "pendingCaptureCount=\(pendingCaptureCount)"
    }
}

enum InitialWindowOnlyPreviewRevealEvidenceSource: String, Equatable {
    case initialReadback = "initial_readback"
    case previewBatchCompleted = "preview_batch_completed"
    case watchdogReadback = "watchdog_readback"
}

struct InitialWindowOnlyPreviewRevealEvidence: Equatable {
    let source: InitialWindowOnlyPreviewRevealEvidenceSource
    let observationGeneration: Int
    let presentationGeneration: Int
    let snapshot: InitialWindowOnlyPreviewReadinessSnapshot
}

struct InitialWindowOnlyPreviewRevealWatchdogFailure: Equatable {
    let observationGeneration: Int
    let presentationGeneration: Int
    let lastEventEvidence: InitialWindowOnlyPreviewRevealEvidence
    let finalEvidence: InitialWindowOnlyPreviewRevealEvidence

    var logFields: String {
        "condition=previewsReady "
            + "lastEventSource=\(lastEventEvidence.source.rawValue) "
            + "lastEvent{\(lastEventEvidence.snapshot.logFields)} "
            + "finalSource=\(finalEvidence.source.rawValue) "
            + "final{\(finalEvidence.snapshot.logFields)}"
    }
}

@MainActor
protocol InitialWindowOnlyPreviewRevealCancellable: AnyObject {
    func cancel()
}

@MainActor
protocol InitialWindowOnlyPreviewRevealScheduling: AnyObject {
    func scheduleWatchdog(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any InitialWindowOnlyPreviewRevealCancellable
}

@MainActor
private final class InitialWindowOnlyPreviewRevealToken:
    InitialWindowOnlyPreviewRevealCancellable
{
    private let task: Task<Void, Never>

    init(
        interval: TimeInterval,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        task = Task { @MainActor in
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(
                        (interval * 1_000_000_000).rounded()
                    )
                )
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
final class InitialWindowOnlyPreviewRevealScheduler:
    InitialWindowOnlyPreviewRevealScheduling
{
    func scheduleWatchdog(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any InitialWindowOnlyPreviewRevealCancellable {
        InitialWindowOnlyPreviewRevealToken(
            interval: interval,
            action: action
        )
    }
}

@MainActor
final class InitialWindowOnlyPreviewRevealObservationOwner {
    private struct PendingObservation {
        let generation: Int
        let presentationGeneration: Int
        let readback:
            @MainActor () -> InitialWindowOnlyPreviewReadinessSnapshot
        let onReady:
            @MainActor (InitialWindowOnlyPreviewRevealEvidence) -> Void
        let onWatchdog:
            @MainActor (
                InitialWindowOnlyPreviewRevealWatchdogFailure
            ) -> Void
        var lastEventEvidence:
            InitialWindowOnlyPreviewRevealEvidence?
        var watchdogToken:
            (any InitialWindowOnlyPreviewRevealCancellable)?
    }

    private let scheduler:
        any InitialWindowOnlyPreviewRevealScheduling
    private let policy: InitialWindowOnlyPreviewRevealPolicy
    private var pending: PendingObservation?

    private(set) var generation = 0
    private(set) var lastWatchdogFailure:
        InitialWindowOnlyPreviewRevealWatchdogFailure?

    init(
        scheduler:
            (any InitialWindowOnlyPreviewRevealScheduling)? = nil,
        policy: InitialWindowOnlyPreviewRevealPolicy = .default
    ) {
        self.scheduler = scheduler
            ?? InitialWindowOnlyPreviewRevealScheduler()
        self.policy = policy
    }

    var isObserving: Bool {
        pending != nil
    }

    var hasPendingWatchdog: Bool {
        pending?.watchdogToken != nil
    }

    @discardableResult
    func start(
        presentationGeneration: Int,
        readback:
            @escaping @MainActor
            () -> InitialWindowOnlyPreviewReadinessSnapshot,
        onReady:
            @escaping @MainActor
            (InitialWindowOnlyPreviewRevealEvidence) -> Void,
        onWatchdog:
            @escaping @MainActor
            (InitialWindowOnlyPreviewRevealWatchdogFailure) -> Void
    ) -> Int {
        precondition(
            policy.degradedRevealWatchdogInterval > 0
                && policy.degradedRevealWatchdogInterval.isFinite,
            "Initial preview reveal watchdog interval must be finite and positive."
        )
        cancel(invalidate: false)
        generation += 1
        let observationGeneration = generation
        lastWatchdogFailure = nil
        pending = PendingObservation(
            generation: observationGeneration,
            presentationGeneration: presentationGeneration,
            readback: readback,
            onReady: onReady,
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

        let token = scheduler.scheduleWatchdog(
            after: policy.degradedRevealWatchdogInterval
        ) { [weak self] in
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
        source: InitialWindowOnlyPreviewRevealEvidenceSource,
        observationGeneration: Int,
        presentationGeneration: Int
    ) -> Bool {
        guard var active = pending,
              active.generation == observationGeneration,
              active.presentationGeneration == presentationGeneration
        else {
            return false
        }
        let evidence = InitialWindowOnlyPreviewRevealEvidence(
            source: source,
            observationGeneration: observationGeneration,
            presentationGeneration: presentationGeneration,
            snapshot: active.readback()
        )
        active.lastEventEvidence = evidence
        pending = active
        guard evidence.snapshot.previewsReady else { return false }
        finishReady(
            evidence,
            observationGeneration: observationGeneration
        )
        return true
    }

    func cancel(invalidate: Bool = true) {
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
        let finalEvidence = InitialWindowOnlyPreviewRevealEvidence(
            source: .watchdogReadback,
            observationGeneration: observationGeneration,
            presentationGeneration: presentationGeneration,
            snapshot: active.readback()
        )
        active.lastEventEvidence = finalEvidence
        pending = active
        if finalEvidence.snapshot.previewsReady {
            finishReady(
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
        let failure = InitialWindowOnlyPreviewRevealWatchdogFailure(
            observationGeneration: observationGeneration,
            presentationGeneration: presentationGeneration,
            lastEventEvidence: previousEvidence ?? finalEvidence,
            finalEvidence: finalEvidence
        )
        lastWatchdogFailure = failure
        completed.onWatchdog(failure)
    }

    private func finishReady(
        _ evidence: InitialWindowOnlyPreviewRevealEvidence,
        observationGeneration: Int
    ) {
        guard let completed = takePending(
            observationGeneration: observationGeneration
        ) else {
            return
        }
        completed.onReady(evidence)
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
