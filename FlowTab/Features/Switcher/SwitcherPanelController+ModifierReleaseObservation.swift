import AppKit
import Carbon
import CoreGraphics
import FlowTabCore

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
                    self.isHotkeyHoldSetPressedInHardwareState(
                        for: sessionKind
                    )
                        || self.isSessionMainKeySetPressedInHardwareState(
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
                return self.isHotkeyHoldSetLikelyPressed()
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

    func isHotkeyHoldModifierFlagsEvent(_ event: NSEvent) -> Bool {
        let key = SwitcherHotkeyKey(keyCode: event.keyCode)
        return key.modifier != nil
            && activeHotkeyHoldKeys().contains(key)
    }

    func isHotkeyHoldSetPressedInHardwareState() -> Bool {
        isHotkeyHoldSetPressedInHardwareState(
            for: activeHotkeySessionKind ?? .globalAppSwitcher
        )
    }

    func isHotkeyHoldSetPressedInHardwareState(
        for sessionKind: HotkeySessionKind
    ) -> Bool {
        switch sessionKind {
        case .globalAppSwitcher:
            if let globalHotkeyHoldSetPressedOverride {
                return globalHotkeyHoldSetPressedOverride
            }
        case .inAppWindowSwitcher:
            if let inAppHotkeyHoldSetPressedOverride {
                return inAppHotkeyHoldSetPressedOverride
            }
        }

        return isHotkeyKeySetPressedInHardwareState(
            hotkeyHoldKeys(for: sessionKind)
        )
    }

    func isSessionMainKeySetPressedInHardwareState(
        for sessionKind: HotkeySessionKind
    ) -> Bool {
        switch sessionKind {
        case .globalAppSwitcher:
            if let globalMainKeySetPressedOverride {
                return globalMainKeySetPressedOverride
            }
        case .inAppWindowSwitcher:
            if let inAppMainKeySetPressedOverride {
                return inAppMainKeySetPressedOverride
            }
        }

        return isHotkeyKeySetPressedInHardwareState(
            hotkeyConfiguration(for: sessionKind).mainKeys
        )
    }

    func isHotkeyHoldSetLikelyPressed(event: NSEvent? = nil) -> Bool {
        if isHotkeyHoldSetPressedInHardwareState() {
            return true
        }
        guard let event else { return false }
        return isHotkeyKeySetPressedInHardwareState(
            activeHotkeyHoldKeys(),
            eventModifierFlags: event.modifierFlags
        )
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
            let configuration = hotkeyConfiguration(for: sessionKind)
            keyCodes.formUnion(
                configuration.mainShortcut.keys.physicalKeyCodes
            )
            keyCodes.formUnion(
                configuration.backwardShortcut.keys.physicalKeyCodes
            )
        }
    }

    func isHotkeyKeySetPressedInHardwareState(
        _ keys: SwitcherHotkeyKeySet,
        eventModifierFlags: NSEvent.ModifierFlags? = nil
    ) -> Bool {
        guard !keys.isEmpty else { return false }
        return keys.orderedKeys.allSatisfy { key in
            isHotkeyKeyPressedInHardwareState(
                key,
                eventModifierFlags: eventModifierFlags
            )
        }
    }

    func isAnyHotkeyKeyPressedInHardwareState(
        _ keys: SwitcherHotkeyKeySet,
        eventModifierFlags: NSEvent.ModifierFlags? = nil
    ) -> Bool {
        keys.orderedKeys.contains { key in
            isHotkeyKeyPressedInHardwareState(
                key,
                eventModifierFlags: eventModifierFlags
            )
        }
    }

    private func isHotkeyKeyPressedInHardwareState(
        _ key: SwitcherHotkeyKey,
        eventModifierFlags: NSEvent.ModifierFlags?
    ) -> Bool {
        if let modifier = key.modifier,
           let eventModifierFlags {
            let observed = KeyModifier(
                eventModifierFlags: eventModifierFlags.intersection(
                    .deviceIndependentFlagsMask
                )
            )
            return observed.contains(modifier)
        }
        return key.physicalKeyCodes.contains { keyCode in
            CGEventSource.keyState(
                .combinedSessionState,
                key: CGKeyCode(keyCode)
            )
        }
    }

}
