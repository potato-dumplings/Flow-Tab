import Foundation

@MainActor
final class SpaceFixtureDesktopRefocusOwner {
    private struct PendingRefocus {
        let generation: Int
        let windowPlanIndex: Int
        let window: any SpaceFixtureWindowing
        let watchdogMilliseconds: Int
        let retryIntervalMilliseconds: Int
        let trigger: @MainActor () -> Void
        let onResolved:
            @MainActor (SpaceFixtureDesktopPresentationEvidence) -> Void
        let onWatchdog:
            @MainActor (SpaceFixtureDesktopRefocusWatchdogFailure) -> Void
        var lastEvidence:
            SpaceFixtureDesktopPresentationEvidence?
        var observationToken: (any SpaceFixtureCancellable)?
        var watchdogToken: (any SpaceFixtureCancellable)?
        var retryToken: (any SpaceFixtureCancellable)?
    }

    private let scheduler: any SpaceFixtureScheduling
    private var pending: PendingRefocus?

    private(set) var generation = 0
    private(set) var lastEvidence:
        SpaceFixtureDesktopPresentationEvidence?
    private(set) var lastFailure:
        SpaceFixtureDesktopRefocusWatchdogFailure?

    init(scheduler: (any SpaceFixtureScheduling)? = nil) {
        self.scheduler = scheduler ?? SpaceFixtureScheduler()
    }

    var isObserving: Bool {
        pending != nil
    }

    @discardableResult
    func start(
        window: any SpaceFixtureWindowing,
        watchdogMilliseconds: Int,
        retryIntervalMilliseconds: Int,
        trigger: @escaping @MainActor () -> Void,
        onResolved:
            @escaping @MainActor (
                SpaceFixtureDesktopPresentationEvidence
            ) -> Void,
        onWatchdog:
            @escaping @MainActor (
                SpaceFixtureDesktopRefocusWatchdogFailure
            ) -> Void
    ) -> Int {
        precondition(
            watchdogMilliseconds > 0,
            "Desktop refocus watchdog must be positive."
        )
        precondition(
            retryIntervalMilliseconds > 0,
            "Desktop refocus retry interval must be positive."
        )
        cancel(invalidate: false)
        generation += 1
        lastEvidence = nil
        lastFailure = nil
        let observationGeneration = generation
        let windowPlanIndex = window.plan.index
        pending = PendingRefocus(
            generation: observationGeneration,
            windowPlanIndex: windowPlanIndex,
            window: window,
            watchdogMilliseconds: watchdogMilliseconds,
            retryIntervalMilliseconds:
                retryIntervalMilliseconds,
            trigger: trigger,
            onResolved: onResolved,
            onWatchdog: onWatchdog,
            lastEvidence: nil,
            observationToken: nil,
            watchdogToken: nil,
            retryToken: nil
        )

        let observationToken =
            window.observeDesktopPresentationChanges {
                [weak self] source in
                self?.observe(
                    source: source,
                    observationGeneration: observationGeneration,
                    windowPlanIndex: windowPlanIndex
                )
            }
        guard var observing = matchingPending(
            observationGeneration: observationGeneration,
            windowPlanIndex: windowPlanIndex
        ) else {
            observationToken.cancel()
            return observationGeneration
        }
        observing.observationToken = observationToken
        pending = observing

        if observe(
            source: .initialReadback,
            observationGeneration: observationGeneration,
            windowPlanIndex: windowPlanIndex
        ) {
            return observationGeneration
        }

        let watchdogToken = scheduler.schedule(
            afterMilliseconds: watchdogMilliseconds
        ) { [weak self] in
            self?.expireWatchdog(
                observationGeneration: observationGeneration,
                windowPlanIndex: windowPlanIndex
            )
        }
        guard var armed = matchingPending(
            observationGeneration: observationGeneration,
            windowPlanIndex: windowPlanIndex
        ) else {
            watchdogToken.cancel()
            return observationGeneration
        }
        armed.watchdogToken = watchdogToken
        pending = armed

        trigger()
        if observe(
            source: .triggerReturnReadback,
            observationGeneration: observationGeneration,
            windowPlanIndex: windowPlanIndex
        ) {
            return observationGeneration
        }
        scheduleRetry(
            observationGeneration: observationGeneration,
            windowPlanIndex: windowPlanIndex
        )
        return observationGeneration
    }

    @discardableResult
    func observe(
        source: SpaceFixtureDesktopPresentationEvidenceSource,
        observationGeneration: Int,
        windowPlanIndex: Int
    ) -> Bool {
        guard var active = matchingPending(
            observationGeneration: observationGeneration,
            windowPlanIndex: windowPlanIndex
        ) else {
            return false
        }
        let evidence = makeEvidence(
            source: source,
            pending: active
        )
        active.lastEvidence = evidence
        lastEvidence = evidence
        pending = active
        guard evidence.snapshot.windowPlanIndex
                == active.windowPlanIndex,
              evidence.snapshot.isPresented
        else {
            return false
        }
        finishResolved(evidence)
        return true
    }

    func cancel(invalidate: Bool = true) {
        pending?.observationToken?.cancel()
        pending?.watchdogToken?.cancel()
        pending?.retryToken?.cancel()
        pending = nil
        if invalidate {
            generation += 1
        }
    }

    private func expireWatchdog(
        observationGeneration: Int,
        windowPlanIndex: Int
    ) {
        guard var active = matchingPending(
            observationGeneration: observationGeneration,
            windowPlanIndex: windowPlanIndex
        ) else {
            return
        }
        let finalEvidence = makeEvidence(
            source: .watchdogReadback,
            pending: active
        )
        lastEvidence = finalEvidence
        if finalEvidence.snapshot.windowPlanIndex
                == active.windowPlanIndex,
           finalEvidence.snapshot.isPresented
        {
            active.lastEvidence = finalEvidence
            pending = active
            finishResolved(finalEvidence)
            return
        }
        guard let completed = takePending() else { return }
        let failure = SpaceFixtureDesktopRefocusWatchdogFailure(
            observationGeneration: observationGeneration,
            expectedWindowPlanIndex:
                completed.windowPlanIndex,
            watchdogMilliseconds:
                completed.watchdogMilliseconds,
            lastEvidence:
                completed.lastEvidence ?? finalEvidence,
            finalEvidence: finalEvidence
        )
        lastFailure = failure
        completed.onWatchdog(failure)
    }

    private func scheduleRetry(
        observationGeneration: Int,
        windowPlanIndex: Int
    ) {
        guard let active = matchingPending(
            observationGeneration: observationGeneration,
            windowPlanIndex: windowPlanIndex
        ) else {
            return
        }
        let retryToken = scheduler.schedule(
            afterMilliseconds:
                active.retryIntervalMilliseconds
        ) { [weak self] in
            self?.retry(
                observationGeneration: observationGeneration,
                windowPlanIndex: windowPlanIndex
            )
        }
        guard var armed = matchingPending(
            observationGeneration: observationGeneration,
            windowPlanIndex: windowPlanIndex
        ) else {
            retryToken.cancel()
            return
        }
        armed.retryToken?.cancel()
        armed.retryToken = retryToken
        pending = armed
    }

    private func retry(
        observationGeneration: Int,
        windowPlanIndex: Int
    ) {
        guard var active = matchingPending(
            observationGeneration: observationGeneration,
            windowPlanIndex: windowPlanIndex
        ) else {
            return
        }
        active.retryToken = nil
        pending = active
        if observe(
            source: .retryReadback,
            observationGeneration: observationGeneration,
            windowPlanIndex: windowPlanIndex
        ) {
            return
        }
        guard let waiting = matchingPending(
            observationGeneration: observationGeneration,
            windowPlanIndex: windowPlanIndex
        ) else {
            return
        }
        waiting.trigger()
        if observe(
            source: .retryTriggerReturnReadback,
            observationGeneration: observationGeneration,
            windowPlanIndex: windowPlanIndex
        ) {
            return
        }
        scheduleRetry(
            observationGeneration: observationGeneration,
            windowPlanIndex: windowPlanIndex
        )
    }

    private func makeEvidence(
        source: SpaceFixtureDesktopPresentationEvidenceSource,
        pending: PendingRefocus
    ) -> SpaceFixtureDesktopPresentationEvidence {
        SpaceFixtureDesktopPresentationEvidence(
            source: source,
            observationGeneration: pending.generation,
            snapshot:
                pending.window.desktopPresentationSnapshot()
        )
    }

    private func finishResolved(
        _ evidence: SpaceFixtureDesktopPresentationEvidence
    ) {
        guard let completed = takePending() else { return }
        completed.onResolved(evidence)
    }

    private func takePending() -> PendingRefocus? {
        guard let active = pending else { return nil }
        active.observationToken?.cancel()
        active.watchdogToken?.cancel()
        active.retryToken?.cancel()
        pending = nil
        return active
    }

    private func matchingPending(
        observationGeneration: Int,
        windowPlanIndex: Int
    ) -> PendingRefocus? {
        guard let active = pending,
              active.generation == observationGeneration,
              active.windowPlanIndex == windowPlanIndex
        else {
            return nil
        }
        return active
    }
}
