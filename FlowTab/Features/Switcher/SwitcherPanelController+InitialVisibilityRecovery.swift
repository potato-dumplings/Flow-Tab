import Foundation

extension SwitcherPanelController {
    func prepareInitialWindowOnlyPanelReveal(kind: HotkeySessionKind) {
        initialWindowOnlyPreviewRevealObservationOwner.cancel()
        guard kind == .inAppWindowSwitcher else {
            panel.alphaValue = 1
            return
        }

        panel.alphaValue = 0
        initialWindowOnlyPreviewRevealObservationOwner.start(
            presentationGeneration: presentationSessionGeneration,
            readback: { [unowned self] in
                initialWindowOnlyPreviewReadinessSnapshot()
            },
            onReady: { [weak self] evidence in
                self?.revealInitialWindowOnlyPanel(evidence: evidence)
            },
            onWatchdog: { [weak self] failure in
                self?.revealInitialWindowOnlyPanelAfterWatchdog(failure)
            }
        )
    }

    func observeInitialWindowOnlyPreviewReadiness(
        source: InitialWindowOnlyPreviewRevealEvidenceSource
    ) {
        _ = initialWindowOnlyPreviewRevealObservationOwner.observe(
            source: source,
            observationGeneration:
                initialWindowOnlyPreviewRevealObservationOwner.generation,
            presentationGeneration: presentationSessionGeneration
        )
    }

    private func revealInitialWindowOnlyPanel(
        evidence: InitialWindowOnlyPreviewRevealEvidence
    ) {
        guard
            evidence.presentationGeneration
                == presentationSessionGeneration
        else {
            return
        }
        guard activeHotkeySessionKind == .inAppWindowSwitcher else { return }
        guard panel.alphaValue < 1 else { return }
        guard evidence.snapshot.previewsReady else { return }

        panel.alphaValue = 1
        RuntimeLog.debug(
            .preview,
            "initial window-only panel revealed reason=\(evidence.source.rawValue) \(evidence.snapshot.logFields)"
        )
    }

    private func revealInitialWindowOnlyPanelAfterWatchdog(
        _ failure: InitialWindowOnlyPreviewRevealWatchdogFailure
    ) {
        guard
            failure.presentationGeneration
                == presentationSessionGeneration
        else {
            return
        }
        guard activeHotkeySessionKind == .inAppWindowSwitcher else { return }
        guard panel.alphaValue < 1 else { return }

        panel.alphaValue = 1
        RuntimeLog.warning(
            .preview,
            "initial window-only panel degraded reveal reason=preview_watchdog \(failure.logFields)"
        )
    }

    func cancelInitialWindowOnlyPanelReveal() {
        initialWindowOnlyPreviewRevealObservationOwner.cancel()
        panel.alphaValue = 1
    }

    private func initialWindowOnlyPreviewReadinessSnapshot()
        -> InitialWindowOnlyPreviewReadinessSnapshot
    {
        InitialWindowOnlyPreviewReadinessSnapshot(
            pendingCaptureCount:
                model.windowOnlyPreviewCaptureInFlightCount
        )
    }

    @discardableResult
    func beginInitialPresentationVisibilityTracking(trigger: String) -> Int {
        let presentationGeneration = presentationSessionGeneration
        let generation = initialPanelVisibilityObservationOwner.start(
            trigger: trigger,
            presentationGeneration: presentationGeneration,
            watchdogInterval: initialPresentationVisibilityWatchdogInterval,
            readback: { [unowned self] in
                self.panelVisibilitySnapshot()
            },
            onVisible: { [weak self] evidence in
                self?.completeInitialPresentationVisibility(
                    trigger: trigger,
                    evidence: evidence
                )
            },
            onWatchdog: { [weak self] failure in
                self?.handleInitialPresentationVisibilityWatchdog(
                    failure
                )
            }
        )
        if initialPanelVisibilityObservationOwner.isObserving(
            observationGeneration: generation,
            presentationGeneration: presentationGeneration
        ) {
            panelVisibilityRecoveryState = .presenting(
                trigger: trigger,
                generation: generation
            )
        }
        logSearchTrace(
            "presentationRecovery trigger=\(trigger) action=trackInitialVisibility generation=\(generation) presentationGeneration=\(presentationGeneration) watchdogMs=\(formatMilliseconds(initialPresentationVisibilityWatchdogInterval * 1_000)) \(searchTraceStateSummary())"
        )
        return generation
    }

    func clearInitialPresentationVisibilityTracking(invalidate: Bool = false) {
        initialPanelVisibilityObservationOwner.cancel(
            invalidate: invalidate
        )
    }

    func isInitialPresentationVisibilityGenerationCurrent(_ generation: Int) -> Bool {
        generation == initialPresentationVisibilityGeneration
    }

    func shouldDeferInitialPanelOcclusionInterruption(trigger: String) -> Bool {
        guard hasActivePresentationSession else { return false }
        guard initialPanelVisibilityObservationOwner.isObserving(
            observationGeneration: initialPresentationVisibilityGeneration,
            presentationGeneration: presentationSessionGeneration
        ) else { return false }
        let lastEvidence =
            initialPanelVisibilityObservationOwner.lastEvidence
        logSearchTrace(
            "systemInterruption trigger=\(trigger) action=deferred reason=initialVisibilityObserved generation=\(initialPresentationVisibilityGeneration) lastEvidence=\(lastEvidence?.source.rawValue ?? "none") lastSnapshot{\(lastEvidence?.snapshot.logFields ?? "none")} \(searchTraceStateSummary())"
        )
        return true
    }

    @discardableResult
    func observeInitialPresentationVisibility(
        source: InitialPanelVisibilityEvidenceSource,
        generation: Int? = nil,
        presentationGeneration: Int? = nil
    ) -> Bool {
        initialPanelVisibilityObservationOwner.observe(
            source: source,
            observationGeneration:
                generation ?? initialPresentationVisibilityGeneration,
            presentationGeneration:
                presentationGeneration ?? presentationSessionGeneration
        )
    }

    private func completeInitialPresentationVisibility(
        trigger: String,
        evidence: InitialPanelVisibilityEvidence
    ) {
        guard hasActivePresentationSession else { return }
        guard isPresentationSessionGenerationCurrent(
            evidence.presentationGeneration
        ) else { return }
        panelVisibilityRecoveryState = .visibleConfirmed(
            trigger: trigger,
            generation: evidence.observationGeneration,
            reason: evidence.source.rawValue
        )
        logSearchTrace(
            "presentationRecovery trigger=\(trigger) action=complete reason=\(evidence.source.rawValue) generation=\(evidence.observationGeneration) presentationGeneration=\(evidence.presentationGeneration) snapshot{\(evidence.snapshot.logFields)} \(searchTraceStateSummary())"
        )
        scheduleModifierReleaseConfirmationAfterRecoveredPresentationIfNeeded(
            trigger: trigger
        )
    }

    private func handleInitialPresentationVisibilityWatchdog(
        _ failure: InitialPanelVisibilityWatchdogFailure
    ) {
        guard hasActivePresentationSession else { return }
        guard isPresentationSessionGenerationCurrent(
            failure.presentationGeneration
        ) else { return }
        panelVisibilityRecoveryState = .failed(
            trigger: failure.trigger,
            generation: failure.observationGeneration,
            reason: "visibilityWatchdog"
        )
        logSearchTrace(
            "presentationRecovery trigger=\(failure.trigger) action=failed reason=visibilityWatchdog generation=\(failure.observationGeneration) presentationGeneration=\(failure.presentationGeneration) \(failure.logFields) \(searchTraceStateSummary())"
        )
        handleRecoverableSystemInterruption(
            trigger: "\(failure.trigger)_visibilityWatchdog"
        )
    }

    func scheduleInitialPanelVisibilityRecovery(
        trigger: String,
        initialVisibilityGeneration: Int? = nil
    ) {
        let generation =
            initialVisibilityGeneration
            ?? initialPresentationVisibilityGeneration
        let presentationGeneration = presentationSessionGeneration
        guard initialPanelVisibilityObservationOwner.isObserving(
            observationGeneration: generation,
            presentationGeneration: presentationGeneration
        ) else { return }
        if observeInitialPresentationVisibility(
            source: .presentationActionReadback,
            generation: generation,
            presentationGeneration: presentationGeneration
        ) {
            return
        }

        let recoveryGeneration = beginPanelPresentationRecovery()
        panelVisibilityRecoveryState = .suspectedHidden(
            trigger: trigger,
            generation: generation
        )
        guard isPanelPresentationRecoveryGenerationCurrent(
            recoveryGeneration
        ) else { return }
        guard isInitialPresentationVisibilityGenerationCurrent(
            generation
        ) else { return }
        guard isPresentationSessionGenerationCurrent(
            presentationGeneration
        ) else { return }
        logSearchTrace(
            "presentationRecovery trigger=\(trigger) action=softAttempt generation=\(generation) presentationGeneration=\(presentationGeneration) recoveryGeneration=\(recoveryGeneration) \(searchTraceStateSummary())"
        )
        panelVisibilityRecoveryState = .recovering(
            trigger: trigger,
            generation: generation,
            attempt: 1,
            totalAttempts: 1,
            mode: .softReorder
        )
        performSoftPanelVisibilityRecoveryAction(
            trigger: trigger,
            recoveryGeneration: recoveryGeneration,
            attempt: 1,
            totalAttempts: 1
        )
        guard hasActivePresentationSession else { return }
        guard isInitialPresentationVisibilityGenerationCurrent(
            generation
        ) else { return }
        _ = observeInitialPresentationVisibility(
            source: .recoveryReadback,
            generation: generation,
            presentationGeneration: presentationGeneration
        )
    }
}
