import AppKit
import Foundation

extension SwitcherPanelController {
    func schedulePanelVisibilityRecovery(
        trigger: String,
        maximumAttemptCount: Int? = nil,
        cancelSessionOnFailure: Bool = false,
        activateApplicationIfNeeded: Bool = true,
        recoveryMode: PanelVisibilityRecoveryMode = .hardReorder
    ) {
        let recoveryGeneration = beginPanelPresentationRecovery()
        let presentationGeneration = presentationSessionGeneration
        let resolvedMaximumAttemptCount =
            maximumAttemptCount
            ?? interruptionPresentationRecoveryMaximumAttemptCount
        panelVisibilityRecoveryState = .suspectedHidden(
            trigger: trigger,
            generation: recoveryGeneration
        )
        _ = panelVisibilityRecoveryObservationOwner.start(
            trigger: trigger,
            recoveryGeneration: recoveryGeneration,
            presentationGeneration: presentationGeneration,
            mode: recoveryMode,
            maximumAttemptCount: resolvedMaximumAttemptCount,
            conditionReadbackInterval:
                interruptionPresentationRecoveryConditionReadbackInterval,
            watchdogInterval:
                interruptionPresentationRecoveryWatchdogInterval,
            readback: { [unowned self] in
                self.panelVisibilitySnapshot()
            },
            actions: .init(
                performSoftReorder: {
                    [weak self] attempt, totalAttempts in
                    self?.performSoftPanelVisibilityRecoveryAction(
                        trigger: trigger,
                        recoveryGeneration: recoveryGeneration,
                        attempt: attempt,
                        totalAttempts: totalAttempts
                    )
                },
                performOrderOut: {
                    [weak self] attempt, totalAttempts in
                    self?.performHardPanelVisibilityRecoveryOrderOut(
                        trigger: trigger,
                        activateApplicationIfNeeded:
                            activateApplicationIfNeeded,
                        recoveryGeneration: recoveryGeneration,
                        attempt: attempt,
                        totalAttempts: totalAttempts
                    )
                },
                performOrderFront: {
                    [weak self] attempt, totalAttempts in
                    self?.performHardPanelVisibilityRecoveryOrderFront(
                        trigger: trigger,
                        recoveryGeneration: recoveryGeneration,
                        attempt: attempt,
                        totalAttempts: totalAttempts
                    )
                }
            ),
            callbacks: .init(
                onAttempt: { [weak self] attempt, totalAttempts in
                    self?.recordPanelVisibilityRecoveryAttempt(
                        trigger: trigger,
                        recoveryGeneration: recoveryGeneration,
                        presentationGeneration: presentationGeneration,
                        mode: recoveryMode,
                        attempt: attempt,
                        totalAttempts: totalAttempts
                    )
                },
                onVisible: { [weak self] evidence in
                    self?.completePanelVisibilityRecovery(
                        trigger: trigger,
                        mode: recoveryMode,
                        evidence: evidence
                    )
                },
                onWatchdog: { [weak self] failure in
                    self?.handlePanelVisibilityRecoveryWatchdog(
                        failure,
                        cancelSessionOnFailure: cancelSessionOnFailure
                    )
                }
            )
        )
    }

    @discardableResult
    func beginPanelPresentationRecovery() -> Int {
        panelVisibilityRecoveryObservationOwner.cancel()
        panelPresentationRecoveryGeneration += 1
        return panelPresentationRecoveryGeneration
    }

    func cancelPanelPresentationRecovery() {
        panelVisibilityRecoveryObservationOwner.cancel()
        panelPresentationRecoveryGeneration += 1
    }

    func isPanelPresentationRecoveryGenerationCurrent(
        _ generation: Int
    ) -> Bool {
        generation == panelPresentationRecoveryGeneration
    }

    func observePanelVisibilityRecovery(
        source: PanelVisibilityRecoveryEvidenceSource
    ) {
        _ = panelVisibilityRecoveryObservationOwner.observe(
            source: source,
            recoveryGeneration: panelPresentationRecoveryGeneration,
            presentationGeneration: presentationSessionGeneration
        )
    }

    func shouldDeferPanelVisibilityRecoveryInterruption(
        trigger: String
    ) -> Bool {
        guard panelVisibilityRecoveryObservationOwner.isObserving else {
            return false
        }
        let evidence =
            panelVisibilityRecoveryObservationOwner.lastEvidence
        logSearchTrace(
            "systemInterruption trigger=\(trigger) action=deferred reason=visibilityRecoveryObserved generation=\(panelPresentationRecoveryGeneration) lastEvidence=\(evidence?.source.rawValue ?? "none") lastSnapshot{\(evidence?.snapshot.logFields ?? "none")} \(searchTraceStateSummary())"
        )
        return true
    }

    private func recordPanelVisibilityRecoveryAttempt(
        trigger: String,
        recoveryGeneration: Int,
        presentationGeneration: Int,
        mode: PanelVisibilityRecoveryMode,
        attempt: Int,
        totalAttempts: Int
    ) {
        guard isPanelPresentationRecoveryGenerationCurrent(
            recoveryGeneration
        ) else { return }
        guard isPresentationSessionGenerationCurrent(
            presentationGeneration
        ) else { return }
        panelVisibilityRecoveryState = .recovering(
            trigger: trigger,
            generation: recoveryGeneration,
            attempt: attempt,
            totalAttempts: totalAttempts,
            mode: mode
        )
        logSearchTrace(
            "presentationRecovery trigger=\(trigger) action=attempt generation=\(recoveryGeneration) presentationGeneration=\(presentationGeneration) mode=\(mode.debugName) index=\(attempt)/\(totalAttempts) \(searchTraceStateSummary())"
        )
    }

    private func completePanelVisibilityRecovery(
        trigger: String,
        mode: PanelVisibilityRecoveryMode,
        evidence: PanelVisibilityRecoveryEvidence
    ) {
        guard isPanelPresentationRecoveryGenerationCurrent(
            evidence.recoveryGeneration
        ) else { return }
        guard isPresentationSessionGenerationCurrent(
            evidence.presentationGeneration
        ) else { return }
        guard hasActivePresentationSession else { return }
        clearInitialPresentationVisibilityTracking()
        completeActiveSpaceMigrationIfNeeded(
            presentationGeneration: evidence.presentationGeneration,
            reason: "panelVisible:\(evidence.source.rawValue)"
        )
        panelVisibilityRecoveryState = .visibleConfirmed(
            trigger: trigger,
            generation: evidence.recoveryGeneration,
            reason: evidence.source.rawValue
        )
        if mode == .hardReorder {
            updatePanelPresentationLevel(
                trigger: "\(trigger)_steady",
                behaviorMode: .allSpaces
            )
        }
        logSearchTrace(
            "presentationRecovery trigger=\(trigger) action=complete reason=\(evidence.source.rawValue) generation=\(evidence.recoveryGeneration) presentationGeneration=\(evidence.presentationGeneration) attempt=\(evidence.attempt) snapshot{\(evidence.snapshot.logFields)} \(searchTraceStateSummary())"
        )
        observeTerminateInterruptionProtectionPresentationUpdate(
            source: .panelVisibilityReadback
        )
        scheduleModifierReleaseConfirmationAfterRecoveredPresentationIfNeeded(
            trigger: trigger
        )
    }

    private func handlePanelVisibilityRecoveryWatchdog(
        _ failure: PanelVisibilityRecoveryWatchdogFailure,
        cancelSessionOnFailure: Bool
    ) {
        guard isPanelPresentationRecoveryGenerationCurrent(
            failure.recoveryGeneration
        ) else { return }
        guard isPresentationSessionGenerationCurrent(
            failure.presentationGeneration
        ) else { return }
        guard hasActivePresentationSession else { return }
        completeActiveSpaceMigrationIfNeeded(
            presentationGeneration: failure.presentationGeneration,
            reason: "visibilityWatchdog"
        )
        panelVisibilityRecoveryState = .failed(
            trigger: failure.trigger,
            generation: failure.recoveryGeneration,
            reason: "visibilityWatchdog"
        )
        logSearchTrace(
            "presentationRecovery trigger=\(failure.trigger) action=failed reason=visibilityWatchdog generation=\(failure.recoveryGeneration) presentationGeneration=\(failure.presentationGeneration) \(failure.logFields) \(searchTraceStateSummary())"
        )
        if cancelSessionOnFailure {
            cancelSelectionForSystemInterruption(
                trigger: failure.trigger
            )
        }
    }

    func performSoftPanelVisibilityRecoveryAction(
        trigger: String,
        recoveryGeneration: Int,
        attempt: Int? = nil,
        totalAttempts: Int? = nil
    ) {
        let beforeSnapshot = panelVisibilitySnapshot()
        defer {
            recordPanelVisibilityRecoveryDiagnostic(
                trigger: trigger,
                generation: recoveryGeneration,
                attempt: attempt,
                totalAttempts: totalAttempts,
                mode: .softReorder,
                before: beforeSnapshot,
                after: panelVisibilitySnapshot()
            )
        }
        updatePanelPresentationLevel(
            trigger: "\(trigger)_soft_recovery",
            behaviorMode: .allSpaces
        )
        centerPanelOnActiveScreen(
            preferredScreen: resolveActivePresentationScreen()
        )
        guard hasActivePresentationSession else { return }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    private func performHardPanelVisibilityRecoveryOrderOut(
        trigger: String,
        activateApplicationIfNeeded: Bool,
        recoveryGeneration: Int,
        attempt: Int,
        totalAttempts: Int
    ) {
        let beforeSnapshot = panelVisibilitySnapshot()
        if activateApplicationIfNeeded {
            activateApplicationForPanelPresentationIfNeeded()
        }
        panel.orderOut(nil)
        recordPanelVisibilityRecoveryDiagnostic(
            trigger: trigger,
            generation: recoveryGeneration,
            attempt: attempt,
            totalAttempts: totalAttempts,
            mode: .hardReorder,
            before: beforeSnapshot,
            after: panelVisibilitySnapshot()
        )
    }

    private func performHardPanelVisibilityRecoveryOrderFront(
        trigger: String,
        recoveryGeneration: Int,
        attempt: Int,
        totalAttempts: Int
    ) {
        let beforeSnapshot = panelVisibilitySnapshot()
        updatePanelPresentationLevel(
            trigger: "\(trigger)_recovery",
            behaviorMode: .activeSpaceMove
        )
        centerPanelOnActiveScreen(
            preferredScreen: resolveActivePresentationScreen()
        )
        guard hasActivePresentationSession else { return }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        recordPanelVisibilityRecoveryDiagnostic(
            trigger: trigger,
            generation: recoveryGeneration,
            attempt: attempt,
            totalAttempts: totalAttempts,
            mode: .hardReorder,
            before: beforeSnapshot,
            after: panelVisibilitySnapshot()
        )
    }

    func activateApplicationForPanelPresentationIfNeeded() {
        guard !isAppCurrentlyActive else { return }
        guard !isApplicationActivationSuppressedForActiveSpaceTransition else {
            return
        }
        if let activateApplicationIgnoringOtherAppsOverride {
            activateApplicationIgnoringOtherAppsOverride()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func scheduleModifierReleaseConfirmationAfterRecoveredPresentationIfNeeded(
        trigger: String
    ) {
        guard let sessionKind = activeHotkeySessionKind else { return }
        guard !model.isSearchActive else { return }
        guard !isHotkeyHoldSetPressedInHardwareState(
            for: sessionKind
        ) else { return }
        logInputTrace(
            "presentationRecovery trigger=\(trigger) action=scheduleReleaseConfirm nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
        )
        scheduleModifierReleaseConfirmation(
            trigger: "presentation_recovered"
        )
    }
}
