import AppKit
import Carbon
import CoreGraphics

extension SwitcherPanelController {
    func beginHotkeyReplaySuppressionUntilRelease(
        for sessionKind: HotkeySessionKind,
        trigger: String
    ) {
        beginHotkeyReplaySuppressionUntilRelease(
            monitoring: [sessionKind],
            trigger: trigger
        )
    }

    func beginHotkeyReplaySuppressionUntilReleaseForKnownSessionKinds(
        trigger: String
    ) {
        beginHotkeyReplaySuppressionUntilRelease(
            monitoring: [.globalAppSwitcher, .inAppWindowSwitcher],
            trigger: trigger
        )
    }

    func beginHotkeyReplaySuppressionUntilRelease(
        monitoring sessionKinds: [HotkeySessionKind],
        trigger: String
    ) {
        suppressHotkeyReplayUntilRelease = true
        modifierReleaseObservationOwner.start(
            kind: .replaySuppression,
            relevantKeyCodes: modifierReleaseRelevantKeyCodes(
                for: sessionKinds
            ),
            sampleInterval: modifierReleaseConfirmationSampleInterval,
            requiredReleasedSampleCount: 1,
            readback: { [weak self] _, _ in
                guard let self else { return nil }
                return sessionKinds.contains { sessionKind in
                    self.isPrimaryModifierPressedInHardwareState(
                        for: sessionKind
                    )
                        || self.isSessionMainKeyPressedInHardwareState(
                            for: sessionKind
                        )
                }
            },
            onStarted: { [weak self] generation in
                guard let self else { return }
                self.modifierReleaseState = .replaySuppression(
                    trigger: trigger,
                    generation: generation,
                    releasedSamples: 0
                )
                self.logInputTrace(
                    "hotkeyReplaySuppression start trigger=\(trigger) generation=\(generation) nowMs=\(self.formatMilliseconds(self.monotonicMilliseconds()))"
                )
            },
            onSample: { [weak self] sample in
                self?.modifierReleaseState = .replaySuppression(
                    trigger: trigger,
                    generation: sample.generation,
                    releasedSamples: sample.releasedSamples
                )
            },
            onComplete: { [weak self] generation in
                guard let self else { return }
                self.suppressHotkeyReplayUntilRelease = false
                self.modifierReleaseState = .replaySuppressionEnded(
                    trigger: trigger,
                    generation: generation
                )
                self.logInputTrace(
                    "hotkeyReplaySuppression end trigger=\(trigger) generation=\(generation) nowMs=\(self.formatMilliseconds(self.monotonicMilliseconds()))"
                )
            }
        )
    }

    func scheduleModifierReleaseConfirmation(trigger: String) {
        guard !suppressModifierReleaseConfirmationForTesting else {
            modifierReleaseState = .canceled(
                reason: .suppressedForTesting,
                generation: modifierReleaseConfirmationGeneration
            )
            logInputTrace(
                "releaseConfirm suppressed trigger=\(trigger) nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
            )
            return
        }
        if hasPendingModifierReleaseConfirmation {
            logInputTrace(
                "releaseConfirm alreadyRunning trigger=\(trigger) action=readback nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
            )
            modifierReleaseObservationOwner.observeInputTransition()
            return
        }
        logInputTrace(
            "releaseConfirm start trigger=\(trigger) nowMs=\(formatMilliseconds(monotonicMilliseconds())) intervalMs=\(formatMilliseconds(modifierReleaseConfirmationSampleInterval * 1_000)) samples=\(modifierReleaseConfirmationSampleCount)"
        )

        let sessionGeneration = presentationSessionGeneration
        modifierReleaseObservationOwner.start(
            kind: .selectionConfirmation,
            relevantKeyCodes: modifierReleaseRelevantKeyCodes(
                for: [activeHotkeySessionKind ?? .globalAppSwitcher]
            ),
            sampleInterval: modifierReleaseConfirmationSampleInterval,
            requiredReleasedSampleCount:
                modifierReleaseConfirmationSampleCount,
            readback: { [weak self] generation, _ in
                guard let self else { return nil }
                guard self.isPresentationSessionGenerationCurrent(
                    sessionGeneration
                ) else {
                    self.recordModifierReleaseCancellation(
                        .sessionChanged,
                        trigger: trigger,
                        generation: generation,
                        sessionGeneration: sessionGeneration
                    )
                    return nil
                }
                guard self.isPanelPresented else {
                    self.recordModifierReleaseCancellation(
                        .panelHidden,
                        trigger: trigger,
                        generation: generation,
                        sessionGeneration: sessionGeneration
                    )
                    return nil
                }
                guard !self.model.isSearchActive else {
                    self.recordModifierReleaseCancellation(
                        .searchActive,
                        trigger: trigger,
                        generation: generation,
                        sessionGeneration: sessionGeneration
                    )
                    return nil
                }
                return self.isPrimaryModifierLikelyPressed()
            },
            onStarted: { [weak self] generation in
                self?.modifierReleaseState = .releaseObserved(
                    trigger: trigger,
                    generation: generation
                )
            },
            onSample: { [weak self] sample in
                self?.recordModifierReleaseSample(
                    sample,
                    trigger: trigger
                )
            },
            onComplete: { [weak self] generation in
                guard let self else { return }
                guard self.isPresentationSessionGenerationCurrent(
                    sessionGeneration
                ) else {
                    self.recordModifierReleaseCancellation(
                        .sessionChanged,
                        trigger: trigger,
                        generation: generation,
                        sessionGeneration: sessionGeneration
                    )
                    return
                }
                self.modifierReleaseState = .confirmed(
                    trigger: trigger,
                    generation: generation
                )
                self.logInputTrace(
                    "releaseConfirm confirmed trigger=\(trigger) action=finishSelection generation=\(generation) sessionGeneration=\(sessionGeneration) nowMs=\(self.formatMilliseconds(self.monotonicMilliseconds()))"
                )
                self.logSearchTrace(
                    "releaseConfirm trigger=\(trigger) action=confirmed generation=\(generation) sessionGeneration=\(sessionGeneration) \(self.searchTraceStateSummary())"
                )
                self.finishSelection()
            }
        )
    }

    func cancelPendingModifierReleaseConfirmation() {
        guard let canceledGeneration =
                modifierReleaseObservationOwner.cancel(
                    kind: .selectionConfirmation
                )
        else {
            return
        }
        logInputTrace(
            "releaseConfirm canceled generation=\(canceledGeneration) nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
        )
        modifierReleaseState = .canceled(
            reason: .explicitCancel,
            generation: canceledGeneration
        )
    }

    func isModifierReleaseConfirmationGenerationCurrent(
        _ generation: Int
    ) -> Bool {
        modifierReleaseObservationOwner.isGenerationCurrent(generation)
    }

    func isPrimaryModifierFlagsEvent(_ event: NSEvent) -> Bool {
        modifierKeyCodes(for: activePrimaryModifier()).contains(event.keyCode)
    }

    func isPrimaryModifierPressedInHardwareState() -> Bool {
        isPrimaryModifierPressedInHardwareState(
            for: activeHotkeySessionKind ?? .globalAppSwitcher
        )
    }

    func isPrimaryModifierPressedInHardwareState(
        for sessionKind: HotkeySessionKind
    ) -> Bool {
        switch sessionKind {
        case .globalAppSwitcher:
            if let globalPrimaryModifierPressedOverride {
                return globalPrimaryModifierPressedOverride
            }
        case .inAppWindowSwitcher:
            if let inAppPrimaryModifierPressedOverride {
                return inAppPrimaryModifierPressedOverride
            }
        }

        return modifierKeyCodes(
            for: primaryModifier(for: sessionKind)
        ).contains { keyCode in
            CGEventSource.keyState(
                .combinedSessionState,
                key: CGKeyCode(keyCode)
            )
        }
    }

    func isSessionMainKeyPressedInHardwareState(
        for sessionKind: HotkeySessionKind
    ) -> Bool {
        switch sessionKind {
        case .globalAppSwitcher:
            if let globalMainKeyPressedOverride {
                return globalMainKeyPressedOverride
            }
        case .inAppWindowSwitcher:
            if let inAppMainKeyPressedOverride {
                return inAppMainKeyPressedOverride
            }
        }

        let keyCode: CGKeyCode
        switch sessionKind {
        case .globalAppSwitcher:
            keyCode = CGKeyCode(
                SwitcherHotkeyPreferencesStore.load().mainKey.keyCode
            )
        case .inAppWindowSwitcher:
            keyCode = CGKeyCode(
                InAppWindowHotkeyPreferencesStore.load().mainKey.keyCode
            )
        }
        return CGEventSource.keyState(
            .combinedSessionState,
            key: keyCode
        )
    }

    func isPrimaryModifierLikelyPressed(event: NSEvent? = nil) -> Bool {
        if isPrimaryModifierPressedInHardwareState() {
            return true
        }
        guard let event else { return false }
        let eventFlags = event.modifierFlags.intersection(
            .deviceIndependentFlagsMask
        )
        return eventFlags.contains(activePrimaryModifierFlag())
    }

    private var modifierReleaseConfirmationSampleInterval: TimeInterval {
        Double(modifierReleaseConfirmationSampleIntervalNs) / 1_000_000_000
    }

    private func recordModifierReleaseSample(
        _ sample: ModifierReleaseObservationSample,
        trigger: String
    ) {
        if sample.inputPressed {
            if case .confirming(
                _,
                _,
                let previousReleasedSamples
            ) = modifierReleaseState, previousReleasedSamples > 0 {
                logInputTrace(
                    "releaseConfirm reset trigger=\(trigger) generation=\(sample.generation) releasedSamples=\(previousReleasedSamples) nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
                )
            }
            modifierReleaseState = .pressed(generation: sample.generation)
            return
        }

        modifierReleaseState = .confirming(
            trigger: trigger,
            generation: sample.generation,
            releasedSamples: sample.releasedSamples
        )
        logInputTrace(
            "releaseConfirm sample trigger=\(trigger) generation=\(sample.generation) source=\(sample.source) releasedSamples=\(sample.releasedSamples)/\(modifierReleaseConfirmationSampleCount) nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
        )
    }

    private func recordModifierReleaseCancellation(
        _ reason: ModifierReleaseCancellationReason,
        trigger: String,
        generation: Int,
        sessionGeneration: Int
    ) {
        modifierReleaseState = .canceled(
            reason: reason,
            generation: generation
        )
        logInputTrace(
            "releaseConfirm stop trigger=\(trigger) reason=\(reason.rawValue) generation=\(generation) sessionGeneration=\(sessionGeneration) currentSessionGeneration=\(presentationSessionGeneration) nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
        )
        if reason == .searchActive {
            logSearchTrace(
                "releaseConfirm trigger=\(trigger) action=stop reason=searchActive generation=\(generation) \(searchTraceStateSummary())"
            )
        }
    }

    private func modifierReleaseRelevantKeyCodes(
        for sessionKinds: [HotkeySessionKind]
    ) -> Set<UInt16> {
        sessionKinds.reduce(into: Set<UInt16>()) { keyCodes, sessionKind in
            keyCodes.formUnion(
                modifierKeyCodes(for: primaryModifier(for: sessionKind))
            )
            switch sessionKind {
            case .globalAppSwitcher:
                keyCodes.insert(
                    SwitcherHotkeyPreferencesStore.load().mainKey.keyCode
                )
            case .inAppWindowSwitcher:
                keyCodes.insert(
                    InAppWindowHotkeyPreferencesStore.load().mainKey.keyCode
                )
            }
        }
    }

    private func modifierKeyCodes(
        for modifier: SwitcherPrimaryModifier
    ) -> Set<UInt16> {
        switch modifier {
        case .option:
            return [UInt16(kVK_Option), UInt16(kVK_RightOption)]
        case .control:
            return [UInt16(kVK_Control), UInt16(kVK_RightControl)]
        case .command:
            return [UInt16(kVK_Command), UInt16(kVK_RightCommand)]
        }
    }
}
