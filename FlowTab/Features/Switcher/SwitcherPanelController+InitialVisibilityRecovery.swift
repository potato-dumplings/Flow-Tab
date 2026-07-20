import Foundation

extension SwitcherPanelController {
    func prepareInitialWindowOnlyPanelReveal(kind: HotkeySessionKind) {
        initialWindowOnlyPreviewRevealTask?.cancel()
        initialWindowOnlyPreviewRevealTask = nil
        guard
            kind == .inAppWindowSwitcher,
            !model.isWindowOnlyPreviewPreparationComplete
        else {
            panel.alphaValue = 1
            return
        }

        panel.alphaValue = 0
        let generation = presentationSessionGeneration
        initialWindowOnlyPreviewRevealTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.initialWindowOnlyPreviewRevealTimeoutNs)
            guard !Task.isCancelled else { return }
            self.revealInitialWindowOnlyPanel(
                generation: generation,
                force: true,
                reason: "preview_timeout"
            )
        }
    }

    func revealInitialWindowOnlyPanelIfReady(reason: String) {
        revealInitialWindowOnlyPanel(
            generation: presentationSessionGeneration,
            force: false,
            reason: reason
        )
    }

    private func revealInitialWindowOnlyPanel(
        generation: Int,
        force: Bool,
        reason: String
    ) {
        guard generation == presentationSessionGeneration else { return }
        guard activeHotkeySessionKind == .inAppWindowSwitcher else { return }
        guard panel.alphaValue < 1 else { return }
        guard force || model.isWindowOnlyPreviewPreparationComplete else { return }

        initialWindowOnlyPreviewRevealTask?.cancel()
        initialWindowOnlyPreviewRevealTask = nil
        panel.alphaValue = 1
        RuntimeLog.debug(
            .preview,
            "initial window-only panel revealed reason=\(reason) previewsReady=\(model.isWindowOnlyPreviewPreparationComplete ? 1 : 0)"
        )
    }

    func cancelInitialWindowOnlyPanelReveal() {
        initialWindowOnlyPreviewRevealTask?.cancel()
        initialWindowOnlyPreviewRevealTask = nil
        panel.alphaValue = 1
    }

    @discardableResult
    func beginInitialPresentationVisibilityTracking(trigger: String) -> Int {
        initialPresentationVisibilityGeneration += 1
        let generation = initialPresentationVisibilityGeneration
        initialPresentationVisibilityDeadline = ProcessInfo.processInfo.systemUptime
            + initialPresentationVisibilityGraceWindow
        initialPresentationVisibilityTrigger = trigger
        panelVisibilityRecoveryState = .presenting(trigger: trigger, generation: generation)
        logSearchTrace(
            "presentationRecovery trigger=\(trigger) action=trackInitialVisibility generation=\(generation) graceMs=\(formatMilliseconds(initialPresentationVisibilityGraceWindow * 1_000)) \(searchTraceStateSummary())"
        )
        return generation
    }

    func clearInitialPresentationVisibilityTracking(invalidate: Bool = false) {
        if invalidate {
            initialPresentationVisibilityGeneration += 1
        }
        initialPresentationVisibilityDeadline = 0
        initialPresentationVisibilityTrigger = nil
    }

    func isInitialPresentationVisibilityGenerationCurrent(_ generation: Int) -> Bool {
        generation == initialPresentationVisibilityGeneration
    }

    func shouldDeferInitialPanelOcclusionInterruption(trigger: String) -> Bool {
        guard hasActivePresentationSession else { return false }
        guard initialPresentationVisibilityDeadline > 0 else { return false }
        guard ProcessInfo.processInfo.systemUptime < initialPresentationVisibilityDeadline else {
            return false
        }
        logSearchTrace(
            "systemInterruption trigger=\(trigger) action=ignored reason=initialPresentationPending generation=\(initialPresentationVisibilityGeneration) \(searchTraceStateSummary())"
        )
        return true
    }

    @discardableResult
    func completeInitialPresentationVisibilityIfVisible(
        trigger: String? = nil,
        generation: Int? = nil,
        reason: String,
        cancelRecoveryTask: Bool
    ) -> Bool {
        guard hasActivePresentationSession else { return false }
        guard initialPresentationVisibilityDeadline > 0 else { return false }
        if let generation {
            guard isInitialPresentationVisibilityGenerationCurrent(generation) else { return false }
        }
        guard isPanelVisibleToUser else { return false }

        let resolvedTrigger = trigger ?? initialPresentationVisibilityTrigger ?? "panel_visible"
        let completedGeneration = generation ?? initialPresentationVisibilityGeneration
        clearInitialPresentationVisibilityTracking()
        panelVisibilityRecoveryState = .visibleConfirmed(
            trigger: resolvedTrigger,
            generation: completedGeneration,
            reason: reason
        )
        if cancelRecoveryTask {
            cancelPanelPresentationRecoveryTask()
        }
        logSearchTrace(
            "presentationRecovery trigger=\(resolvedTrigger) action=complete reason=\(reason) \(searchTraceStateSummary())"
        )
        beginIgnoringActiveSpaceChanges(trigger: "\(resolvedTrigger)_visible")
        scheduleModifierReleaseConfirmationAfterRecoveredPresentationIfNeeded(trigger: resolvedTrigger)
        return true
    }

    func scheduleInitialPanelVisibilityRecovery(
        trigger: String,
        activateApplicationIfNeeded: Bool = false
    ) {
        let recoveryGeneration = beginPanelPresentationRecoveryTask()
        let generation = beginInitialPresentationVisibilityTracking(trigger: trigger)
        panelPresentationRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.isPanelPresentationRecoveryGenerationCurrent(recoveryGeneration) else { return }
            guard self.isInitialPresentationVisibilityGenerationCurrent(generation) else { return }

            if self.completeInitialPresentationVisibilityIfVisible(
                trigger: trigger,
                generation: generation,
                reason: "alreadyVisible",
                cancelRecoveryTask: false
            ) {
                self.clearPanelPresentationRecoveryTaskIfCurrent(recoveryGeneration)
                return
            }

            self.panelVisibilityRecoveryState = .suspectedHidden(
                trigger: trigger,
                generation: generation
            )
            self.logSearchTrace(
                "presentationRecovery trigger=\(trigger) action=softAttempt generation=\(generation) recoveryGeneration=\(recoveryGeneration) \(self.searchTraceStateSummary())"
            )
            self.panelVisibilityRecoveryState = .recovering(
                trigger: trigger,
                generation: generation,
                attempt: 1,
                totalAttempts: 1,
                mode: .softReorder
            )
            await self.performPanelVisibilityRecoveryAttempt(
                trigger: trigger,
                activateApplicationIfNeeded: activateApplicationIfNeeded,
                recoveryMode: .softReorder,
                generation: recoveryGeneration,
                attempt: 1,
                totalAttempts: 1
            )

            guard !Task.isCancelled else { return }
            guard self.isPanelPresentationRecoveryGenerationCurrent(recoveryGeneration) else { return }
            guard self.hasActivePresentationSession else {
                self.clearPanelPresentationRecoveryTaskIfCurrent(recoveryGeneration)
                return
            }
            guard self.isInitialPresentationVisibilityGenerationCurrent(generation) else {
                self.clearPanelPresentationRecoveryTaskIfCurrent(recoveryGeneration)
                return
            }

            if self.completeInitialPresentationVisibilityIfVisible(
                trigger: trigger,
                generation: generation,
                reason: "recovered",
                cancelRecoveryTask: false
            ) {
                self.clearPanelPresentationRecoveryTaskIfCurrent(recoveryGeneration)
                return
            }

            let remainingSeconds = max(
                0,
                self.initialPresentationVisibilityDeadline - ProcessInfo.processInfo.systemUptime
            )
            if remainingSeconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remainingSeconds * 1_000_000_000))
            }

            guard !Task.isCancelled else { return }
            guard self.isPanelPresentationRecoveryGenerationCurrent(recoveryGeneration) else { return }
            guard self.hasActivePresentationSession else {
                self.clearPanelPresentationRecoveryTaskIfCurrent(recoveryGeneration)
                return
            }
            guard self.isInitialPresentationVisibilityGenerationCurrent(generation) else {
                self.clearPanelPresentationRecoveryTaskIfCurrent(recoveryGeneration)
                return
            }

            if self.completeInitialPresentationVisibilityIfVisible(
                trigger: trigger,
                generation: generation,
                reason: "deadlineVisible",
                cancelRecoveryTask: false
            ) {
                self.clearPanelPresentationRecoveryTaskIfCurrent(recoveryGeneration)
                return
            }

            self.clearPanelPresentationRecoveryTaskIfCurrent(recoveryGeneration)
            self.clearInitialPresentationVisibilityTracking()
            self.panelVisibilityRecoveryState = .failed(
                trigger: trigger,
                generation: generation,
                reason: "visibilityDeadline"
            )
            self.logSearchTrace(
                "presentationRecovery trigger=\(trigger) action=failed reason=visibilityDeadline generation=\(generation) recoveryGeneration=\(recoveryGeneration) \(self.searchTraceStateSummary())"
            )
            self.handleRecoverableSystemInterruption(trigger: "\(trigger)_visibilityDeadline")
        }
    }
}
