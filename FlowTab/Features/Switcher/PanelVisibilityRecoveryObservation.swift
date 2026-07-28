import Foundation

@MainActor
final class PanelVisibilityRecoveryObservationOwner {
    private let scheduler: any PanelVisibilityRecoveryObservationScheduling
    private var pending: PanelVisibilityRecoveryPendingObservation?

    private(set) var lastFailure:
        PanelVisibilityRecoveryWatchdogFailure?

    init(
        scheduler:
            (any PanelVisibilityRecoveryObservationScheduling)? = nil
    ) {
        self.scheduler = scheduler
            ?? PanelVisibilityRecoveryObservationScheduler()
    }

    var isObserving: Bool {
        pending != nil
    }

    var lastEvidence: PanelVisibilityRecoveryEvidence? {
        pending?.lastEvidence
    }

    @discardableResult
    func start(
        trigger: String,
        recoveryGeneration: Int,
        presentationGeneration: Int,
        mode: SwitcherPanelController.PanelVisibilityRecoveryMode,
        maximumAttemptCount: Int,
        conditionReadbackInterval: TimeInterval,
        watchdogInterval: TimeInterval,
        readback: @escaping @MainActor () -> PanelVisibilitySnapshot,
        actions: PanelVisibilityRecoveryActions,
        callbacks: PanelVisibilityRecoveryCallbacks
    ) -> Bool {
        precondition(
            maximumAttemptCount > 0,
            "Panel visibility recovery requires at least one attempt."
        )
        precondition(
            conditionReadbackInterval > 0
                && conditionReadbackInterval.isFinite,
            "Panel visibility condition cadence must be finite and positive."
        )
        precondition(
            watchdogInterval > 0 && watchdogInterval.isFinite,
            "Panel visibility recovery watchdog must be finite and positive."
        )
        cancel()
        lastFailure = nil
        pending = PanelVisibilityRecoveryPendingObservation(
            trigger: trigger,
            recoveryGeneration: recoveryGeneration,
            presentationGeneration: presentationGeneration,
            mode: mode,
            maximumAttemptCount: maximumAttemptCount,
            conditionReadbackInterval: conditionReadbackInterval,
            readback: readback,
            actions: actions,
            callbacks: callbacks
        )

        if recordEvidence(.initialReadback)?.snapshot.userVisible == true {
            finishVisible()
            return false
        }

        let watchdogToken = scheduler.scheduleWatchdog(
            after: watchdogInterval
        ) { [weak self] in
            self?.expireWatchdog(
                recoveryGeneration: recoveryGeneration,
                presentationGeneration: presentationGeneration
            )
        }
        guard var active = matchingPending(
            recoveryGeneration: recoveryGeneration,
            presentationGeneration: presentationGeneration
        ) else {
            watchdogToken.cancel()
            return false
        }
        active.watchdogToken = watchdogToken
        pending = active
        beginNextAttempt(
            recoveryGeneration: recoveryGeneration,
            presentationGeneration: presentationGeneration
        )
        return isObserving
    }

    @discardableResult
    func observe(
        source: PanelVisibilityRecoveryEvidenceSource,
        recoveryGeneration: Int,
        presentationGeneration: Int
    ) -> Bool {
        guard matchingPending(
            recoveryGeneration: recoveryGeneration,
            presentationGeneration: presentationGeneration
        ) != nil else {
            return false
        }
        guard let evidence = recordEvidence(source) else { return false }
        if pending?.phase == .awaitingOrderOut {
            guard !evidence.snapshot.panelPresented else {
                return false
            }
            performOrderFront(
                recoveryGeneration: recoveryGeneration,
                presentationGeneration: presentationGeneration
            )
            return false
        }
        if evidence.snapshot.userVisible {
            finishVisible()
            return true
        }
        return false
    }

    func cancel() {
        pending?.conditionReadbackToken?.cancel()
        pending?.watchdogToken?.cancel()
        pending = nil
    }

    private func beginNextAttempt(
        recoveryGeneration: Int,
        presentationGeneration: Int
    ) {
        guard var active = matchingPending(
            recoveryGeneration: recoveryGeneration,
            presentationGeneration: presentationGeneration
        ), active.attempt < active.maximumAttemptCount else {
            return
        }
        active.conditionReadbackToken?.cancel()
        active.conditionReadbackToken = nil
        active.attempt += 1
        active.phase = active.mode == .hardReorder
            ? .awaitingOrderOut
            : .awaitingVisibility
        pending = active
        active.callbacks.onAttempt(
            active.attempt,
            active.maximumAttemptCount
        )
        guard let current = matchingPending(
            recoveryGeneration: recoveryGeneration,
            presentationGeneration: presentationGeneration
        ), current.attempt == active.attempt else {
            return
        }
        active = current

        if active.mode == .softReorder {
            active.actions.performSoftReorder(
                active.attempt,
                active.maximumAttemptCount
            )
            if recordEvidence(.softActionReadback)?.snapshot.userVisible
                == true
            {
                finishVisible()
                return
            }
            scheduleConditionReadback(
                recoveryGeneration: recoveryGeneration,
                presentationGeneration: presentationGeneration
            )
            return
        }

        active.actions.performOrderOut(
            active.attempt,
            active.maximumAttemptCount
        )
        guard let evidence = recordEvidence(.orderOutActionReadback) else {
            return
        }
        if !evidence.snapshot.panelPresented {
            performOrderFront(
                recoveryGeneration: recoveryGeneration,
                presentationGeneration: presentationGeneration
            )
        } else {
            scheduleConditionReadback(
                recoveryGeneration: recoveryGeneration,
                presentationGeneration: presentationGeneration
            )
        }
    }

    private func performOrderFront(
        recoveryGeneration: Int,
        presentationGeneration: Int
    ) {
        guard var active = matchingPending(
            recoveryGeneration: recoveryGeneration,
            presentationGeneration: presentationGeneration
        ), active.phase == .awaitingOrderOut else {
            return
        }
        active.conditionReadbackToken?.cancel()
        active.conditionReadbackToken = nil
        active.phase = .awaitingVisibility
        pending = active
        active.actions.performOrderFront(
            active.attempt,
            active.maximumAttemptCount
        )
        if recordEvidence(.orderFrontActionReadback)?.snapshot.userVisible
            == true
        {
            finishVisible()
            return
        }
        scheduleConditionReadback(
            recoveryGeneration: recoveryGeneration,
            presentationGeneration: presentationGeneration
        )
    }

    private func scheduleConditionReadback(
        recoveryGeneration: Int,
        presentationGeneration: Int
    ) {
        guard var active = matchingPending(
            recoveryGeneration: recoveryGeneration,
            presentationGeneration: presentationGeneration
        ), active.conditionReadbackToken == nil else {
            return
        }
        let token = scheduler.scheduleConditionReadback(
            after: active.conditionReadbackInterval
        ) { [weak self] in
            self?.handleConditionReadback(
                recoveryGeneration: recoveryGeneration,
                presentationGeneration: presentationGeneration
            )
        }
        active.conditionReadbackToken = token
        pending = active
    }

    private func handleConditionReadback(
        recoveryGeneration: Int,
        presentationGeneration: Int
    ) {
        guard var active = matchingPending(
            recoveryGeneration: recoveryGeneration,
            presentationGeneration: presentationGeneration
        ) else {
            return
        }
        active.conditionReadbackToken = nil
        pending = active
        guard let evidence = recordEvidence(.conditionReadback) else {
            return
        }
        if active.phase == .awaitingOrderOut {
            if !evidence.snapshot.panelPresented {
                performOrderFront(
                    recoveryGeneration: recoveryGeneration,
                    presentationGeneration: presentationGeneration
                )
                return
            }
            scheduleConditionReadback(
                recoveryGeneration: recoveryGeneration,
                presentationGeneration: presentationGeneration
            )
            return
        }
        if evidence.snapshot.userVisible {
            finishVisible()
            return
        }
        beginNextAttempt(
            recoveryGeneration: recoveryGeneration,
            presentationGeneration: presentationGeneration
        )
    }

    private func expireWatchdog(
        recoveryGeneration: Int,
        presentationGeneration: Int
    ) {
        guard let active = matchingPending(
            recoveryGeneration: recoveryGeneration,
            presentationGeneration: presentationGeneration
        ) else {
            return
        }
        let previousEvidence = active.lastEvidence
        guard var finalEvidence = recordEvidence(.watchdogReadback) else {
            return
        }
        if active.phase == .awaitingOrderOut {
            if !finalEvidence.snapshot.panelPresented {
                performOrderFront(
                    recoveryGeneration: recoveryGeneration,
                    presentationGeneration: presentationGeneration
                )
                guard matchingPending(
                    recoveryGeneration: recoveryGeneration,
                    presentationGeneration: presentationGeneration
                ) != nil else {
                    return
                }
                guard let postActionEvidence = recordEvidence(
                    .watchdogReadback
                ) else {
                    return
                }
                finalEvidence = postActionEvidence
                if finalEvidence.snapshot.userVisible {
                    finishVisible()
                    return
                }
            }
        } else if finalEvidence.snapshot.userVisible {
            finishVisible()
            return
        }
        guard let completed = takePending() else { return }
        let failure = PanelVisibilityRecoveryWatchdogFailure(
            trigger: completed.trigger,
            recoveryGeneration: recoveryGeneration,
            presentationGeneration: presentationGeneration,
            mode: completed.mode,
            completedAttemptCount: completed.attempt,
            lastEvidence: previousEvidence ?? finalEvidence,
            finalEvidence: finalEvidence
        )
        lastFailure = failure
        completed.callbacks.onWatchdog(failure)
    }

    private func recordEvidence(
        _ source: PanelVisibilityRecoveryEvidenceSource
    ) -> PanelVisibilityRecoveryEvidence? {
        guard var active = pending else { return nil }
        let evidence = PanelVisibilityRecoveryEvidence(
            source: source,
            recoveryGeneration: active.recoveryGeneration,
            presentationGeneration: active.presentationGeneration,
            attempt: active.attempt,
            snapshot: active.readback()
        )
        active.lastEvidence = evidence
        pending = active
        return evidence
    }

    private func finishVisible() {
        guard let completed = takePending(),
              let evidence = completed.lastEvidence
        else {
            return
        }
        completed.callbacks.onVisible(evidence)
    }

    private func takePending()
        -> PanelVisibilityRecoveryPendingObservation?
    {
        guard let active = pending else { return nil }
        active.conditionReadbackToken?.cancel()
        active.watchdogToken?.cancel()
        pending = nil
        return active
    }

    private func matchingPending(
        recoveryGeneration: Int,
        presentationGeneration: Int
    ) -> PanelVisibilityRecoveryPendingObservation? {
        guard let active = pending,
              active.recoveryGeneration == recoveryGeneration,
              active.presentationGeneration == presentationGeneration
        else {
            return nil
        }
        return active
    }
}
