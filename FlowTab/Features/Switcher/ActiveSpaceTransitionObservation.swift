import CoreGraphics
import Foundation

struct ActiveSpaceTransitionPolicy: Equatable {
    var topologyReadbackWatchdogInterval: TimeInterval

    static let `default` = ActiveSpaceTransitionPolicy(
        topologyReadbackWatchdogInterval: 1.0
    )
}

struct ActiveSpaceDisplayIdentity: Equatable {
    let displayID: CGDirectDisplayID?
    let currentSpaceID: Int?
}

struct ActiveSpaceTransitionSnapshot: Equatable {
    let spaceGeneration: UInt64
    let currentSpaceIdentity: [ActiveSpaceDisplayIdentity]?
    let panelVisibility: PanelVisibilitySnapshot

    var logFields: String {
        let identity = currentSpaceIdentity?.map { display in
            let displayID = display.displayID.map(String.init) ?? "nil"
            let spaceID = display.currentSpaceID.map(String.init) ?? "nil"
            return "\(displayID):\(spaceID)"
        }.joined(separator: ",") ?? "unavailable"
        return "spaceGeneration=\(spaceGeneration) "
            + "currentSpaces=\(identity) "
            + "panel{\(panelVisibility.logFields)}"
    }
}

enum ActiveSpaceTransitionEvidenceSource: String, Equatable {
    case baselineReadback
    case requestReturnReadback
    case projectionUpdateReadback
    case watchdogReadback
}

struct ActiveSpaceTransitionEvidence: Equatable {
    let source: ActiveSpaceTransitionEvidenceSource
    let observationGeneration: Int
    let presentationGeneration: Int
    let baseline: ActiveSpaceTransitionSnapshot
    let snapshot: ActiveSpaceTransitionSnapshot

    var currentSpaceIdentityChanged: Bool? {
        guard let baselineIdentity = baseline.currentSpaceIdentity,
              let currentIdentity = snapshot.currentSpaceIdentity
        else {
            return nil
        }
        return baselineIdentity != currentIdentity
    }
}

struct ActiveSpaceTransitionWatchdogFailure: Equatable {
    let trigger: String
    let observationGeneration: Int
    let presentationGeneration: Int
    let baseline: ActiveSpaceTransitionSnapshot
    let lastEvidence: ActiveSpaceTransitionEvidence
    let finalEvidence: ActiveSpaceTransitionEvidence

    var logFields: String {
        "condition=spaceGenerationAdvanced "
            + "baseline{\(baseline.logFields)} "
            + "lastSource=\(lastEvidence.source.rawValue) "
            + "last{\(lastEvidence.snapshot.logFields)} "
            + "final{\(finalEvidence.snapshot.logFields)}"
    }
}

@MainActor
protocol ActiveSpaceTransitionObservationCancellable: AnyObject {
    func cancel()
}

@MainActor
protocol ActiveSpaceTransitionObservationScheduling: AnyObject {
    func scheduleWatchdog(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any ActiveSpaceTransitionObservationCancellable
}

@MainActor
private final class ActiveSpaceTransitionObservationToken:
    ActiveSpaceTransitionObservationCancellable
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
final class ActiveSpaceTransitionObservationScheduler:
    ActiveSpaceTransitionObservationScheduling
{
    func scheduleWatchdog(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any ActiveSpaceTransitionObservationCancellable {
        ActiveSpaceTransitionObservationToken(
            interval: interval,
            action: action
        )
    }
}

@MainActor
final class ActiveSpaceTransitionObservationOwner {
    private struct PendingObservation {
        let generation: Int
        let trigger: String
        let presentationGeneration: Int
        let baseline: ActiveSpaceTransitionSnapshot
        let readback: @MainActor () -> ActiveSpaceTransitionSnapshot
        let onResolved:
            @MainActor (ActiveSpaceTransitionEvidence) -> Void
        let onWatchdog:
            @MainActor (ActiveSpaceTransitionWatchdogFailure) -> Void
        var lastEvidence: ActiveSpaceTransitionEvidence
        var watchdogToken:
            (any ActiveSpaceTransitionObservationCancellable)?
    }

    private let scheduler: any ActiveSpaceTransitionObservationScheduling
    private var pending: PendingObservation?

    private(set) var generation = 0
    private(set) var lastFailure:
        ActiveSpaceTransitionWatchdogFailure?

    init(
        scheduler:
            (any ActiveSpaceTransitionObservationScheduling)? = nil
    ) {
        self.scheduler = scheduler
            ?? ActiveSpaceTransitionObservationScheduler()
    }

    var isObserving: Bool {
        pending != nil
    }

    var lastEvidence: ActiveSpaceTransitionEvidence? {
        pending?.lastEvidence
    }

    @discardableResult
    func start(
        trigger: String,
        presentationGeneration: Int,
        watchdogInterval: TimeInterval,
        readback:
            @escaping @MainActor () -> ActiveSpaceTransitionSnapshot,
        onResolved:
            @escaping @MainActor (ActiveSpaceTransitionEvidence) -> Void,
        onWatchdog:
            @escaping @MainActor (ActiveSpaceTransitionWatchdogFailure) -> Void
    ) -> Int {
        precondition(
            watchdogInterval > 0 && watchdogInterval.isFinite,
            "Active Space transition watchdog must be finite and positive."
        )
        cancel(invalidate: false)
        generation += 1
        lastFailure = nil
        let observationGeneration = generation
        let baseline = readback()
        let baselineEvidence = ActiveSpaceTransitionEvidence(
            source: .baselineReadback,
            observationGeneration: observationGeneration,
            presentationGeneration: presentationGeneration,
            baseline: baseline,
            snapshot: baseline
        )
        pending = PendingObservation(
            generation: observationGeneration,
            trigger: trigger,
            presentationGeneration: presentationGeneration,
            baseline: baseline,
            readback: readback,
            onResolved: onResolved,
            onWatchdog: onWatchdog,
            lastEvidence: baselineEvidence
        )

        let token = scheduler.scheduleWatchdog(
            after: watchdogInterval
        ) { [weak self] in
            self?.expireWatchdog(
                observationGeneration: observationGeneration,
                presentationGeneration: presentationGeneration
            )
        }
        guard var active = matchingPending(
            observationGeneration: observationGeneration,
            presentationGeneration: presentationGeneration
        ) else {
            token.cancel()
            return observationGeneration
        }
        active.watchdogToken = token
        pending = active
        return observationGeneration
    }

    @discardableResult
    func observe(
        source: ActiveSpaceTransitionEvidenceSource,
        observationGeneration: Int,
        presentationGeneration: Int
    ) -> Bool {
        guard var active = matchingPending(
            observationGeneration: observationGeneration,
            presentationGeneration: presentationGeneration
        ) else {
            return false
        }
        let evidence = makeEvidence(source: source, pending: active)
        active.lastEvidence = evidence
        pending = active
        guard evidence.snapshot.spaceGeneration
            > evidence.baseline.spaceGeneration
        else {
            return false
        }
        finishResolved(evidence)
        return true
    }

    func cancel(invalidate: Bool = true) {
        pending?.watchdogToken?.cancel()
        pending = nil
        if invalidate {
            generation += 1
        }
    }

    private func expireWatchdog(
        observationGeneration: Int,
        presentationGeneration: Int
    ) {
        guard var active = matchingPending(
            observationGeneration: observationGeneration,
            presentationGeneration: presentationGeneration
        ) else {
            return
        }
        let finalEvidence = makeEvidence(
            source: .watchdogReadback,
            pending: active
        )
        if finalEvidence.snapshot.spaceGeneration
            > finalEvidence.baseline.spaceGeneration
        {
            active.lastEvidence = finalEvidence
            pending = active
            finishResolved(finalEvidence)
            return
        }
        guard let completed = takePending() else { return }
        let failure = ActiveSpaceTransitionWatchdogFailure(
            trigger: completed.trigger,
            observationGeneration: observationGeneration,
            presentationGeneration: presentationGeneration,
            baseline: completed.baseline,
            lastEvidence: completed.lastEvidence,
            finalEvidence: finalEvidence
        )
        lastFailure = failure
        completed.onWatchdog(failure)
    }

    private func makeEvidence(
        source: ActiveSpaceTransitionEvidenceSource,
        pending: PendingObservation
    ) -> ActiveSpaceTransitionEvidence {
        ActiveSpaceTransitionEvidence(
            source: source,
            observationGeneration: pending.generation,
            presentationGeneration: pending.presentationGeneration,
            baseline: pending.baseline,
            snapshot: pending.readback()
        )
    }

    private func finishResolved(
        _ evidence: ActiveSpaceTransitionEvidence
    ) {
        guard let completed = takePending() else { return }
        completed.onResolved(evidence)
    }

    private func takePending() -> PendingObservation? {
        guard let active = pending else { return nil }
        active.watchdogToken?.cancel()
        pending = nil
        return active
    }

    private func matchingPending(
        observationGeneration: Int,
        presentationGeneration: Int
    ) -> PendingObservation? {
        guard let active = pending,
              active.generation == observationGeneration,
              active.presentationGeneration == presentationGeneration
        else {
            return nil
        }
        return active
    }
}
