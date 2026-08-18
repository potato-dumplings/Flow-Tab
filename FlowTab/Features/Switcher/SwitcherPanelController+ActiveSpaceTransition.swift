import Foundation

struct ActiveSpaceApplicationActivationSuppression: Equatable {
    let observationGeneration: Int
    let presentationGeneration: Int
}

extension SwitcherPanelController {
    func beginActiveSpaceTransitionObservation(trigger: String) {
        let presentationGeneration = presentationSessionGeneration
        let observationGeneration =
            activeSpaceTransitionObservationOwner.start(
                trigger: trigger,
                presentationGeneration: presentationGeneration,
                watchdogInterval:
                    activeSpaceTransitionWatchdogInterval,
                readback: { [unowned self] in
                    self.activeSpaceTransitionSnapshot()
                },
                onResolved: { [weak self] evidence in
                    self?.handleResolvedActiveSpaceTransition(
                        trigger: trigger,
                        evidence: evidence
                    )
                },
                onWatchdog: { [weak self] failure in
                    self?.handleActiveSpaceTransitionWatchdog(failure)
                }
            )
        activeSpaceApplicationActivationSuppression =
            ActiveSpaceApplicationActivationSuppression(
                observationGeneration: observationGeneration,
                presentationGeneration: presentationGeneration
            )
        logSearchTrace(
            "activeSpaceTransition trigger=\(trigger) action=observe generation=\(observationGeneration) presentationGeneration=\(presentationGeneration) baseline{\(activeSpaceTransitionObservationOwner.lastEvidence?.baseline.logFields ?? "none")} \(searchTraceStateSummary())"
        )

        model.signalSpaceTopologyChanged()
        _ = activeSpaceTransitionObservationOwner.observe(
            source: .requestReturnReadback,
            observationGeneration: observationGeneration,
            presentationGeneration: presentationGeneration
        )
    }

    func observeActiveSpaceTransitionProjectionUpdate() {
        guard activeSpaceTransitionObservationOwner.isObserving else {
            return
        }
        _ = activeSpaceTransitionObservationOwner.observe(
            source: .projectionUpdateReadback,
            observationGeneration:
                activeSpaceTransitionObservationOwner.generation,
            presentationGeneration: presentationSessionGeneration
        )
    }

    func cancelActiveSpaceTransitionObservation() {
        activeSpaceTransitionObservationOwner.cancel()
        activeSpaceApplicationActivationSuppression = nil
    }

    var isApplicationActivationSuppressedForActiveSpaceTransition: Bool {
        guard let suppression =
            activeSpaceApplicationActivationSuppression
        else {
            return false
        }
        return suppression.presentationGeneration
            == presentationSessionGeneration
    }

    func completeActiveSpaceMigrationIfNeeded(
        presentationGeneration: Int,
        reason: String
    ) {
        guard let suppression =
            activeSpaceApplicationActivationSuppression,
              suppression.presentationGeneration == presentationGeneration
        else {
            return
        }
        activeSpaceApplicationActivationSuppression = nil
        logSearchTrace(
            "activeSpaceTransition action=activationSuppressionEnded reason=\(reason) generation=\(suppression.observationGeneration) presentationGeneration=\(presentationGeneration) \(searchTraceStateSummary())"
        )
        observeTerminateInterruptionProtectionPresentationUpdate(
            source: .activeSpaceTransitionReadback
        )
    }

    private func activeSpaceTransitionSnapshot()
        -> ActiveSpaceTransitionSnapshot
    {
        let runtimeService = model.runtimeProjectionService
        let projection = runtimeService.readSpaceTopologyProjection()
        let spaceGeneration =
            projection?.freshness.sourceGeneration.space
            ?? runtimeService.runtimeReadModelDiagnostics()
                .generation.space
        let identity = projection.map { projection in
            projection.signature.displays.map { display in
                ActiveSpaceDisplayIdentity(
                    displayID: display.displayID,
                    currentSpaceID: display.currentSpaceID
                )
            }
        }
        return ActiveSpaceTransitionSnapshot(
            spaceGeneration: spaceGeneration,
            currentSpaceIdentity: identity,
            panelVisibility: panelVisibilitySnapshot()
        )
    }

    private func handleResolvedActiveSpaceTransition(
        trigger: String,
        evidence: ActiveSpaceTransitionEvidence
    ) {
        guard isPresentationSessionGenerationCurrent(
            evidence.presentationGeneration
        ) else {
            return
        }
        guard activeSpaceApplicationActivationSuppression
            == ActiveSpaceApplicationActivationSuppression(
                observationGeneration: evidence.observationGeneration,
                presentationGeneration: evidence.presentationGeneration
            )
        else {
            return
        }
        let identityChanged =
            evidence.currentSpaceIdentityChanged == true
        if !identityChanged
            && evidence.snapshot.panelVisibility.userVisible
        {
            logSearchTrace(
                "activeSpaceTransition trigger=\(trigger) action=ignored reason=stableCurrentSpaceVisible generation=\(evidence.observationGeneration) presentationGeneration=\(evidence.presentationGeneration) source=\(evidence.source.rawValue) evidence{\(evidence.snapshot.logFields)} \(searchTraceStateSummary())"
            )
            completeActiveSpaceMigrationIfNeeded(
                presentationGeneration: evidence.presentationGeneration,
                reason: "stableCurrentSpaceVisible"
            )
            return
        }
        handleObservedActiveSpaceTransition(
            trigger: trigger,
            observationGeneration: evidence.observationGeneration,
            presentationGeneration: evidence.presentationGeneration,
            reason: identityChanged
                ? "currentSpaceIdentityChanged"
                : "spaceGenerationAdvancedPanelHidden",
            source: evidence.source.rawValue,
            snapshot: evidence.snapshot
        )
    }

    private func handleActiveSpaceTransitionWatchdog(
        _ failure: ActiveSpaceTransitionWatchdogFailure
    ) {
        guard isPresentationSessionGenerationCurrent(
            failure.presentationGeneration
        ) else {
            return
        }
        guard activeSpaceApplicationActivationSuppression
            == ActiveSpaceApplicationActivationSuppression(
                observationGeneration: failure.observationGeneration,
                presentationGeneration: failure.presentationGeneration
            )
        else {
            return
        }
        logSearchTrace(
            "activeSpaceTransition trigger=\(failure.trigger) action=watchdog generation=\(failure.observationGeneration) presentationGeneration=\(failure.presentationGeneration) \(failure.logFields) \(searchTraceStateSummary())"
        )
        if failure.finalEvidence.snapshot.panelVisibility.userVisible {
            completeActiveSpaceMigrationIfNeeded(
                presentationGeneration: failure.presentationGeneration,
                reason: "watchdogPanelVisible"
            )
            return
        }
        handleObservedActiveSpaceTransition(
            trigger: failure.trigger,
            observationGeneration: failure.observationGeneration,
            presentationGeneration: failure.presentationGeneration,
            reason: "topologyWatchdogPanelHidden",
            source: failure.finalEvidence.source.rawValue,
            snapshot: failure.finalEvidence.snapshot
        )
    }

    private func handleObservedActiveSpaceTransition(
        trigger: String,
        observationGeneration: Int,
        presentationGeneration: Int,
        reason: String,
        source: String,
        snapshot: ActiveSpaceTransitionSnapshot
    ) {
        guard isPresentationSessionGenerationCurrent(
            presentationGeneration
        ) else {
            return
        }
        if handleProtectedTerminateSystemInterruption(trigger: trigger) {
            return
        }
        guard let sessionKind = activeHotkeySessionKind else {
            cancelSelectionForSystemInterruption(trigger: trigger)
            return
        }
        let shouldKeepSessionVisible = model.isSearchActive
            || isHotkeyHoldSetPressedInHardwareState(for: sessionKind)
        guard shouldKeepSessionVisible else {
            logSearchTrace(
                "systemInterruption trigger=\(trigger) action=cancel reason=modifierReleased transitionReason=\(reason) generation=\(observationGeneration) presentationGeneration=\(presentationGeneration) source=\(source) evidence{\(snapshot.logFields)} \(searchTraceStateSummary())"
            )
            cancelSelectionForSystemInterruption(trigger: trigger)
            return
        }
        logSearchTrace(
            "systemInterruption trigger=\(trigger) action=migrate reason=\(reason) generation=\(observationGeneration) presentationGeneration=\(presentationGeneration) source=\(source) evidence{\(snapshot.logFields)} \(searchTraceStateSummary())"
        )
        schedulePanelVisibilityRecovery(
            trigger: trigger,
            cancelSessionOnFailure: true,
            activateApplicationIfNeeded: false
        )
    }
}
