import Foundation

@MainActor
final class InitialAppContentRevealObservationOwner {
    private struct PendingObservation {
        let target: InitialAppContentRevealTarget
        let onDraw: @MainActor (InitialAppContentRevealEvidence) -> Void
        let onWatchdog:
            @MainActor (InitialAppContentRevealWatchdogFailure) -> Void
        var lastEvent: SwitcherRenderMilestoneEvent?
        var matchingDrawEvent: SwitcherRenderMilestoneEvent?
        var preparation: SwitcherRenderMilestonePreparation?
        var isPanelOrdered: Bool
        var didAttemptRenderPass: Bool
        var renderPassToken:
            (any InitialAppContentRevealCancellable)?
        var watchdogToken: (any InitialAppContentRevealCancellable)?
    }

    private let scheduler: any InitialAppContentRevealScheduling
    private let policy: InitialAppContentRevealPolicy
    private var pending: PendingObservation?
    private var cachedPreparation: SwitcherRenderMilestonePreparation?

    private(set) var generation = 0
    private(set) var lastRenderPassEvidence:
        InitialAppContentRenderPassEvidence?
    private(set) var lastWatchdogFailure:
        InitialAppContentRevealWatchdogFailure?

    init(
        scheduler: (any InitialAppContentRevealScheduling)? = nil,
        policy: InitialAppContentRevealPolicy = .default
    ) {
        self.scheduler = scheduler ?? InitialAppContentRevealScheduler()
        self.policy = policy
    }

    var isObserving: Bool {
        pending != nil
    }

    var target: InitialAppContentRevealTarget? {
        pending?.target
    }

    @discardableResult
    func start(
        presentationGeneration: Int,
        renderGeneration: UInt64,
        onDraw:
            @escaping @MainActor
            (InitialAppContentRevealEvidence) -> Void,
        onWatchdog:
            @escaping @MainActor
            (InitialAppContentRevealWatchdogFailure) -> Void
    ) -> Int {
        precondition(
            policy.watchdogInterval > 0
                && policy.watchdogInterval.isFinite,
            "Initial app-content reveal watchdog must be finite and positive."
        )
        let reusablePreparation = cachedPreparation
        cancelPending()
        cachedPreparation = nil
        generation += 1
        let target = InitialAppContentRevealTarget(
            observationGeneration: generation,
            presentationGeneration: presentationGeneration,
            milestone: .appContent,
            renderGeneration: renderGeneration
        )
        lastRenderPassEvidence = nil
        lastWatchdogFailure = nil
        let preparation = reusablePreparation.flatMap { preparation in
            preparation.milestone == target.milestone
                && preparation.renderGeneration == target.renderGeneration
                ? preparation
                : nil
        }
        pending = PendingObservation(
            target: target,
            onDraw: onDraw,
            onWatchdog: onWatchdog,
            lastEvent: nil,
            matchingDrawEvent: nil,
            preparation: preparation,
            isPanelOrdered: false,
            didAttemptRenderPass: false,
            renderPassToken: nil,
            watchdogToken: nil
        )

        let token = scheduler.scheduleWatchdog(
            after: policy.watchdogInterval
        ) { [weak self] in
            self?.expireWatchdog(target: target)
        }
        guard var active = pending,
              active.target == target
        else {
            token.cancel()
            return target.observationGeneration
        }
        active.watchdogToken = token
        pending = active
        scheduleRenderPassIfReady(target: target)
        return target.observationGeneration
    }

    @discardableResult
    func observePreparation(
        _ preparation: SwitcherRenderMilestonePreparation,
        presentationGeneration: Int
    ) -> Bool {
        guard preparation.milestone == .appContent else {
            return false
        }
        guard var active = pending else {
            cachedPreparation = preparation
            return true
        }
        guard active.target.presentationGeneration
                == presentationGeneration,
              preparation.milestone == active.target.milestone,
              preparation.renderGeneration
                == active.target.renderGeneration
        else {
            cachedPreparation = preparation
            return false
        }
        guard !active.didAttemptRenderPass else { return true }
        active.preparation = preparation
        pending = active
        scheduleRenderPassIfReady(target: active.target)
        return true
    }

    @discardableResult
    func markPanelOrdered(
        observationGeneration: Int,
        presentationGeneration: Int
    ) -> Bool {
        guard var active = pending,
              active.target.observationGeneration
                == observationGeneration,
              active.target.presentationGeneration
                == presentationGeneration
        else {
            return false
        }
        active.isPanelOrdered = true
        pending = active
        if completeDrawIfReady(target: active.target) {
            return true
        }
        scheduleRenderPassIfReady(target: active.target)
        return true
    }

    @discardableResult
    func observe(
        _ event: SwitcherRenderMilestoneEvent,
        observationGeneration: Int,
        presentationGeneration: Int
    ) -> Bool {
        guard var active = pending,
              active.target.observationGeneration
                == observationGeneration,
              active.target.presentationGeneration
                == presentationGeneration
        else {
            return false
        }
        active.lastEvent = event
        pending = active
        guard event.milestone == active.target.milestone,
              event.renderGeneration
                == active.target.renderGeneration
        else {
            return false
        }
        active.matchingDrawEvent = event
        pending = active
        _ = completeDrawIfReady(target: active.target)
        return true
    }

    func cancel() {
        cancelPending()
        cachedPreparation = nil
        generation += 1
    }

    private func expireWatchdog(
        target: InitialAppContentRevealTarget
    ) {
        guard let completed = takePending(target: target) else {
            return
        }
        let failure = InitialAppContentRevealWatchdogFailure(
            target: completed.target,
            lastEvent: completed.lastEvent
        )
        lastWatchdogFailure = failure
        completed.onWatchdog(failure)
    }

    private func scheduleRenderPassIfReady(
        target: InitialAppContentRevealTarget
    ) {
        guard let active = pending,
              active.target == target,
              active.isPanelOrdered,
              active.preparation != nil,
              !active.didAttemptRenderPass,
              active.renderPassToken == nil
        else {
            return
        }
        let token = scheduler.scheduleRenderPass { [weak self] in
            self?.performRenderPass(target: target)
        }
        guard var current = pending,
              current.target == target,
              !current.didAttemptRenderPass,
              current.renderPassToken == nil
        else {
            token.cancel()
            return
        }
        current.renderPassToken = token
        pending = current
    }

    @discardableResult
    private func completeDrawIfReady(
        target: InitialAppContentRevealTarget
    ) -> Bool {
        guard let active = pending,
              active.target == target,
              active.isPanelOrdered,
              let event = active.matchingDrawEvent,
              let completed = takePending(target: target)
        else {
            return false
        }
        let evidence = InitialAppContentRevealEvidence(
            target: completed.target,
            event: event
        )
        completed.onDraw(evidence)
        return true
    }

    private func performRenderPass(
        target: InitialAppContentRevealTarget
    ) {
        guard let active = pending,
              active.target == target,
              active.isPanelOrdered
        else {
            return
        }
        if completeDrawIfReady(target: target) {
            return
        }
        guard var current = pending,
              current.target == target,
              current.isPanelOrdered,
              !current.didAttemptRenderPass,
              let preparation = current.preparation,
              preparation.milestone == target.milestone,
              preparation.renderGeneration
                == target.renderGeneration
        else {
            return
        }
        current.renderPassToken = nil
        current.didAttemptRenderPass = true
        pending = current
        guard let displayEvidence =
                preparation.displayPreparedRegion(),
              displayEvidence.milestone == target.milestone,
              displayEvidence.renderGeneration
                == target.renderGeneration
        else {
            return
        }
        lastRenderPassEvidence = InitialAppContentRenderPassEvidence(
            target: target,
            durationMilliseconds:
                displayEvidence.durationMilliseconds,
            completedAtMilliseconds:
                displayEvidence.completedAtMilliseconds
        )
    }

    private func takePending(
        target: InitialAppContentRevealTarget
    ) -> PendingObservation? {
        guard let active = pending,
              active.target == target
        else {
            return nil
        }
        active.renderPassToken?.cancel()
        active.watchdogToken?.cancel()
        pending = nil
        return active
    }

    private func cancelPending() {
        pending?.renderPassToken?.cancel()
        pending?.watchdogToken?.cancel()
        pending = nil
    }
}
