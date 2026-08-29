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
            recoveryEscalationInterval:
                initialPresentationVisibilityRecoveryEscalationInterval,
            readback: { [unowned self] in
                self.panelVisibilitySnapshot()
            },
            onVisible: { [weak self] evidence in
                self?.completeInitialPresentationVisibility(
                    trigger: trigger,
                    evidence: evidence
                )
            },
            onRecoveryEscalation: { [weak self] escalation in
                self?.handleInitialPresentationVisibilityRecoveryEscalation(
                    escalation
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
            "presentationRecovery trigger=\(trigger) action=trackInitialVisibility generation=\(generation) presentationGeneration=\(presentationGeneration) recoveryEscalationMs=\(formatMilliseconds(initialPresentationVisibilityRecoveryEscalationInterval * 1_000)) \(searchTraceStateSummary())"
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
        if hasPendingPanelVisibilityRecoveryObservation {
            cancelPanelPresentationRecovery()
        }
        panelVisibilityRecoveryState = .visibleConfirmed(
            trigger: trigger,
            generation: evidence.observationGeneration,
            reason: evidence.source.rawValue
        )
        recordInitialOcclusionVisibility(
            atMilliseconds: monotonicMilliseconds()
        )
        logSearchTrace(
            "presentationRecovery trigger=\(trigger) action=complete reason=\(evidence.source.rawValue) generation=\(evidence.observationGeneration) presentationGeneration=\(evidence.presentationGeneration) snapshot{\(evidence.snapshot.logFields)} \(searchTraceStateSummary())"
        )
        scheduleModifierReleaseConfirmationAfterRecoveredPresentationIfNeeded(
            trigger: trigger
        )
    }

    func beginInitialVisibleFrameTracking() {
        cancelDeferredSelectedAppPreviewPrewarm()
        initialRenderMilestoneEvent = nil
        initialOcclusionVisibleAtMilliseconds = nil
        didCompleteInitialVisibleFrameWork = false
        if model.isWindowOnlyOverlay {
            expectedInitialRenderMilestone = .windowContent
            expectedInitialRenderGeneration =
                model.selectedAppWindowProjectionGeneration
        } else if model.isSearchActive {
            expectedInitialRenderMilestone = .searchShell
            expectedInitialRenderGeneration =
                model.searchResultScrollRevision
        } else {
            expectedInitialRenderMilestone = .appContent
            expectedInitialRenderGeneration =
                model.appLayerRenderSnapshot?.generation
        }
    }

    func handleSwitcherRenderMilestone(
        _ event: SwitcherRenderMilestoneEvent
    ) {
        for observer in renderMilestoneObservers.values {
            observer(event)
        }
        guard !didCompleteInitialVisibleFrameWork,
              event.milestone == expectedInitialRenderMilestone,
              event.renderGeneration
                == expectedInitialRenderGeneration
        else {
            return
        }
        initialRenderMilestoneEvent = event
        completeInitialVisibleFrameWorkIfReady()
    }

    func addRenderMilestoneObserver(
        _ observer: @escaping (SwitcherRenderMilestoneEvent) -> Void
    ) -> UUID {
        let id = UUID()
        renderMilestoneObservers[id] = observer
        return id
    }

    func removeRenderMilestoneObserver(_ id: UUID) {
        renderMilestoneObservers[id] = nil
    }

    func clearInitialVisibleFrameTracking() {
        cancelDeferredSelectedAppPreviewPrewarm()
        expectedInitialRenderMilestone = nil
        expectedInitialRenderGeneration = nil
        initialRenderMilestoneEvent = nil
        initialOcclusionVisibleAtMilliseconds = nil
        didCompleteInitialVisibleFrameWork = false
    }

    private func recordInitialOcclusionVisibility(
        atMilliseconds timestamp: Double
    ) {
        guard !didCompleteInitialVisibleFrameWork else { return }
        initialOcclusionVisibleAtMilliseconds = timestamp
        completeInitialVisibleFrameWorkIfReady()
    }

    private func completeInitialVisibleFrameWorkIfReady() {
        guard !didCompleteInitialVisibleFrameWork,
              let renderEvent = initialRenderMilestoneEvent,
              let visibleAtMilliseconds =
                initialOcclusionVisibleAtMilliseconds
        else {
            return
        }
        didCompleteInitialVisibleFrameWork = true
        RuntimeLog.debug(
            .switcherLayout,
            "firstVisibleFrame milestone=\(renderEvent.milestone.rawValue) renderGeneration=\(renderEvent.renderGeneration) drawMs=\(formatMilliseconds(renderEvent.drawnAtMilliseconds)) occlusionMs=\(formatMilliseconds(visibleAtMilliseconds))"
        )
        guard activeHotkeySessionKind == .globalAppSwitcher else {
            return
        }
        if !model.isSearchActive, !model.isWindowOnlyOverlay {
            scheduleDeferredSelectedAppPreviewPrewarm()
        }
        _ = model.performDeferredRuntimeProjectionMaintenance()
    }

    private func scheduleDeferredSelectedAppPreviewPrewarm() {
        cancelDeferredSelectedAppPreviewPrewarm()
        let generation = presentationSessionGeneration
        deferredSelectedAppPreviewPrewarmTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled,
                  let self,
                  presentationSessionGeneration == generation,
                  hasActivePresentationSession,
                  activeHotkeySessionKind == .globalAppSwitcher,
                  !model.isSearchActive,
                  !model.isWindowOnlyOverlay
            else {
                return
            }
            deferredSelectedAppPreviewPrewarmTask = nil
            _ = prewarmSelectedAppWindowPreviewPage()
        }
    }

    private func cancelDeferredSelectedAppPreviewPrewarm() {
        deferredSelectedAppPreviewPrewarmTask?.cancel()
        deferredSelectedAppPreviewPrewarmTask = nil
    }

    private func handleInitialPresentationVisibilityRecoveryEscalation(
        _ escalation: InitialPanelVisibilityRecoveryEscalation
    ) {
        guard hasActivePresentationSession else { return }
        guard isPresentationSessionGenerationCurrent(
            escalation.presentationGeneration
        ) else { return }
        guard initialPanelVisibilityObservationOwner.isObserving(
            observationGeneration: escalation.observationGeneration,
            presentationGeneration: escalation.presentationGeneration
        ) else { return }
        logSearchTrace(
            "presentationRecovery trigger=\(escalation.trigger) action=recoveryEscalated generation=\(escalation.observationGeneration) presentationGeneration=\(escalation.presentationGeneration) \(escalation.logFields) \(searchTraceStateSummary())"
        )
        schedulePanelVisibilityRecovery(
            trigger: "\(escalation.trigger)_initialVisibilityEscalation",
            cancelSessionOnFailure: false
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
