import Foundation

extension SwitcherPanelController {
    @discardableResult
    func beginInitialPresentationVisibilityTracking(trigger: String) -> Int {
        initialPresentationVisibilityGeneration += 1
        let generation = initialPresentationVisibilityGeneration
        initialPresentationVisibilityDeadline = ProcessInfo.processInfo.systemUptime
            + initialPresentationVisibilityGraceWindow
        initialPresentationVisibilityTrigger = trigger
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
        clearInitialPresentationVisibilityTracking()
        if cancelRecoveryTask {
            panelPresentationRecoveryTask?.cancel()
            panelPresentationRecoveryTask = nil
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
        panelPresentationRecoveryTask?.cancel()
        let generation = beginInitialPresentationVisibilityTracking(trigger: trigger)
        panelPresentationRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.isInitialPresentationVisibilityGenerationCurrent(generation) else { return }

            if self.completeInitialPresentationVisibilityIfVisible(
                trigger: trigger,
                generation: generation,
                reason: "alreadyVisible",
                cancelRecoveryTask: false
            ) {
                self.panelPresentationRecoveryTask = nil
                return
            }

            self.logSearchTrace(
                "presentationRecovery trigger=\(trigger) action=softAttempt generation=\(generation) \(self.searchTraceStateSummary())"
            )
            await self.performPanelVisibilityRecoveryAttempt(
                trigger: trigger,
                activateApplicationIfNeeded: activateApplicationIfNeeded,
                recoveryMode: .softReorder
            )

            guard !Task.isCancelled else { return }
            guard self.hasActivePresentationSession else {
                self.panelPresentationRecoveryTask = nil
                return
            }
            guard self.isInitialPresentationVisibilityGenerationCurrent(generation) else {
                self.panelPresentationRecoveryTask = nil
                return
            }

            if self.completeInitialPresentationVisibilityIfVisible(
                trigger: trigger,
                generation: generation,
                reason: "recovered",
                cancelRecoveryTask: false
            ) {
                self.panelPresentationRecoveryTask = nil
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
            guard self.hasActivePresentationSession else {
                self.panelPresentationRecoveryTask = nil
                return
            }
            guard self.isInitialPresentationVisibilityGenerationCurrent(generation) else {
                self.panelPresentationRecoveryTask = nil
                return
            }

            if self.completeInitialPresentationVisibilityIfVisible(
                trigger: trigger,
                generation: generation,
                reason: "deadlineVisible",
                cancelRecoveryTask: false
            ) {
                self.panelPresentationRecoveryTask = nil
                return
            }

            self.panelPresentationRecoveryTask = nil
            self.clearInitialPresentationVisibilityTracking()
            self.logSearchTrace(
                "presentationRecovery trigger=\(trigger) action=failed reason=visibilityDeadline generation=\(generation) \(self.searchTraceStateSummary())"
            )
            self.handleRecoverableSystemInterruption(trigger: "\(trigger)_visibilityDeadline")
        }
    }
}
