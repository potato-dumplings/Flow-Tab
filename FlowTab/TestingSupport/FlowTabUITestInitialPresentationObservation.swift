#if FLOWTAB_TESTING
import Foundation

@MainActor
final class FlowTabUITestInitialPresentationObservationOwner {
    private struct ActiveObservation {
        let generation: UInt64
        let watchdogInterval: TimeInterval
        let baseline:
            FlowTabUITestInitialPresentationSnapshot
        let attemptPresentation:
            FlowTabUITestInitialPresentationAttemptHandler
        let cancelPresentation: @MainActor () -> Void
        let onResolved:
            @MainActor (
                FlowTabUITestInitialPresentationEvidence
            ) -> Void
        let onWatchdog:
            @MainActor (
                FlowTabUITestInitialPresentationWatchdogFailure
            ) -> Void
        var lastEvidence:
            FlowTabUITestInitialPresentationEvidence?
        var lastAttemptedCandidate:
            FlowTabUITestInitialPresentationSnapshot?
        var isAttemptingPresentation: Bool
        var watchdogToken:
            (any FlowTabUITestInitialPresentationCancellable)?
    }

    private let notificationCenter: NotificationCenter
    private let notificationObject: AnyObject?
    private let notificationRoutes:
        [FlowTabUITestInitialPresentationNotificationRoute]
    private let scheduler:
        any FlowTabUITestInitialPresentationScheduling
    private let readback:
        FlowTabUITestInitialPresentationSnapshotProvider

    private var active: ActiveObservation?
    private var notificationTokens: [NSObjectProtocol] = []

    private(set) var observationGeneration: UInt64 = 0
    private(set) var lastEvidence:
        FlowTabUITestInitialPresentationEvidence?
    private(set) var lastResolution:
        FlowTabUITestInitialPresentationEvidence?
    private(set) var lastFailure:
        FlowTabUITestInitialPresentationWatchdogFailure?

    init(
        notificationRoutes:
            [FlowTabUITestInitialPresentationNotificationRoute],
        notificationObject: AnyObject?,
        notificationCenter: NotificationCenter = .default,
        scheduler:
            (any FlowTabUITestInitialPresentationScheduling)? = nil,
        readback:
            @escaping FlowTabUITestInitialPresentationSnapshotProvider
    ) {
        self.notificationRoutes = notificationRoutes
        self.notificationObject = notificationObject
        self.notificationCenter = notificationCenter
        self.scheduler = scheduler
            ?? FlowTabUITestInitialPresentationScheduler()
        self.readback = readback
    }

    var isObserving: Bool {
        active != nil
    }

    var hasPendingWatchdog: Bool {
        active?.watchdogToken != nil
    }

    @discardableResult
    func start(
        watchdogInterval: TimeInterval,
        triggerReadiness: @escaping @MainActor () -> Void,
        attemptPresentation:
            @escaping FlowTabUITestInitialPresentationAttemptHandler,
        cancelPresentation:
            @escaping @MainActor () -> Void,
        onResolved:
            @escaping @MainActor (
                FlowTabUITestInitialPresentationEvidence
            ) -> Void,
        onWatchdog:
            @escaping @MainActor (
                FlowTabUITestInitialPresentationWatchdogFailure
            ) -> Void
    ) -> UInt64 {
        precondition(
            watchdogInterval > 0
                && watchdogInterval.isFinite
        )
        cancel(invalidate: false)
        observationGeneration &+= 1
        let generation = observationGeneration
        lastEvidence = nil
        lastResolution = nil
        lastFailure = nil

        installObservers(generation: generation)
        let baseline = readback()
        active = ActiveObservation(
            generation: generation,
            watchdogInterval: watchdogInterval,
            baseline: baseline,
            attemptPresentation: attemptPresentation,
            cancelPresentation: cancelPresentation,
            onResolved: onResolved,
            onWatchdog: onWatchdog,
            lastEvidence: nil,
            lastAttemptedCandidate: nil,
            isAttemptingPresentation: false,
            watchdogToken: nil
        )

        _ = evaluate(
            candidate: baseline,
            source: .initialReadback,
            generation: generation
        )
        guard active?.generation == generation else {
            return generation
        }

        triggerReadiness()
        guard active?.generation == generation else {
            return generation
        }
        _ = evaluate(
            candidate: readback(),
            source: .readinessRequestReadback,
            generation: generation
        )
        guard active?.generation == generation else {
            return generation
        }

        let token = scheduler.schedule(
            after: watchdogInterval
        ) { [weak self] in
            self?.expireWatchdog(generation: generation)
        }
        guard var current = active,
              current.generation == generation
        else {
            token.cancel()
            return generation
        }
        current.watchdogToken = token
        active = current
        return generation
    }

    @discardableResult
    func observe(
        source:
            FlowTabUITestInitialPresentationEvidenceSource,
        observationGeneration: UInt64
    ) -> Bool {
        evaluate(
            candidate: readback(),
            source: source,
            generation: observationGeneration
        )
    }

    func cancel() {
        cancel(invalidate: true)
    }

    deinit {
        for token in notificationTokens {
            notificationCenter.removeObserver(token)
        }
    }

    private func installObservers(generation: UInt64) {
        notificationTokens = notificationRoutes.map {
            route in
            notificationCenter.addObserver(
                forName: route.name,
                object: notificationObject,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    _ = self?.observe(
                        source: route.source,
                        observationGeneration: generation
                    )
                }
            }
        }
    }

    @discardableResult
    private func evaluate(
        candidate:
            FlowTabUITestInitialPresentationSnapshot,
        source:
            FlowTabUITestInitialPresentationEvidenceSource,
        generation: UInt64
    ) -> Bool {
        guard var current = active,
              current.generation == generation,
              !current.isAttemptingPresentation
        else {
            return false
        }
        precondition(
            candidate.mode == current.baseline.mode
        )
        let progressed = source == .initialReadback
            || candidate.hasProgressed(
                from: current.baseline
            )

        if progressed && candidate.isTerminalNoContent {
            let evidence = makeEvidence(
                current: current,
                source: source,
                candidate: candidate,
                resolution: .noContent
            )
            finishResolved(evidence)
            return true
        }

        guard progressed,
              candidate.isReadyForPresentation,
              current.lastAttemptedCandidate
                != candidate
        else {
            recordPending(
                current: current,
                source: source,
                candidate: candidate
            )
            return false
        }

        current.isAttemptingPresentation = true
        current.lastAttemptedCandidate = candidate
        active = current
        let attempt = current.attemptPresentation(
            candidate
        )
        guard var resumed = active,
              resumed.generation == generation
        else {
            return false
        }
        let postPresentationReadback = readback()
        let resolved = attempt.didPresent
            && attempt.sessionItemIDs == candidate.itemIDs
            && postPresentationReadback
                .isCompatibleAfterPresenting(candidate)
        let evidence =
            FlowTabUITestInitialPresentationEvidence(
                observationGeneration: generation,
                baseline: current.baseline,
                source: source,
                candidate: candidate,
                attempt: attempt,
                postPresentationReadback:
                    postPresentationReadback,
                resolution:
                    resolved ? .presented : nil
            )
        resumed.isAttemptingPresentation = false
        resumed.lastEvidence = evidence
        active = resumed
        lastEvidence = evidence
        if resolved {
            finishResolved(evidence)
            return true
        }
        resumed.cancelPresentation()
        return false
    }

    private func recordPending(
        current: ActiveObservation,
        source:
            FlowTabUITestInitialPresentationEvidenceSource,
        candidate:
            FlowTabUITestInitialPresentationSnapshot
    ) {
        var current = current
        let evidence = makeEvidence(
            current: current,
            source: source,
            candidate: candidate,
            resolution: nil
        )
        current.lastEvidence = evidence
        active = current
        lastEvidence = evidence
    }

    private func makeEvidence(
        current: ActiveObservation,
        source:
            FlowTabUITestInitialPresentationEvidenceSource,
        candidate:
            FlowTabUITestInitialPresentationSnapshot,
        resolution:
            FlowTabUITestInitialPresentationResolution?
    ) -> FlowTabUITestInitialPresentationEvidence {
        FlowTabUITestInitialPresentationEvidence(
            observationGeneration: current.generation,
            baseline: current.baseline,
            source: source,
            candidate: candidate,
            attempt: nil,
            postPresentationReadback: nil,
            resolution: resolution
        )
    }

    private func finishResolved(
        _ evidence:
            FlowTabUITestInitialPresentationEvidence
    ) {
        guard let completed = takeActive() else {
            return
        }
        lastEvidence = evidence
        lastResolution = evidence
        completed.onResolved(evidence)
    }

    private func expireWatchdog(generation: UInt64) {
        guard let current = active,
              current.generation == generation
        else {
            return
        }
        let lastEventEvidence = current.lastEvidence
        if evaluate(
            candidate: readback(),
            source: .watchdogReadback,
            generation: generation
        ) {
            return
        }
        guard let completed = takeActive() else {
            return
        }
        let finalEvidence = completed.lastEvidence
            ?? makeEvidence(
                current: completed,
                source: .watchdogReadback,
                candidate: readback(),
                resolution: nil
            )
        let failure =
            FlowTabUITestInitialPresentationWatchdogFailure(
                watchdogInterval:
                    completed.watchdogInterval,
                lastEvidence:
                    lastEventEvidence
                    ?? finalEvidence,
                finalEvidence: finalEvidence
            )
        lastEvidence = finalEvidence
        lastFailure = failure
        completed.onWatchdog(failure)
    }

    private func cancel(invalidate: Bool) {
        let hadActive = active != nil
        _ = takeActive()
        if invalidate && hadActive {
            observationGeneration &+= 1
        }
    }

    private func takeActive() -> ActiveObservation? {
        guard let active else { return nil }
        self.active = nil
        active.watchdogToken?.cancel()
        removeObservers()
        return active
    }

    private func removeObservers() {
        for token in notificationTokens {
            notificationCenter.removeObserver(token)
        }
        notificationTokens.removeAll()
    }
}
#endif
