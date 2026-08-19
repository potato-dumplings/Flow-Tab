import AppKit
import Carbon
import CoreGraphics
import SwiftUI
import FlowTabCore

extension SwitcherPanelController {
    func registerHotkeyInputSource(
        _ sourceID: HotkeyInputSourceID,
        for sessionKind: HotkeySessionKind
    ) {
        let route = hotkeyInputRoute(for: sessionKind)
        let registrationGeneration = hotkeyInputOwner.register(
            sourceID: sourceID,
            for: route
        )
        logInputTrace(
            "hotkeyInputSource route=\(route.rawValue) action=register source=\(sourceID.rawValue.uuidString) registrationGeneration=\(registrationGeneration)"
        )
    }

    func unregisterHotkeyInputSource(for sessionKind: HotkeySessionKind) {
        let route = hotkeyInputRoute(for: sessionKind)
        hotkeyInputOwner.unregister(route: route)
        logInputTrace(
            "hotkeyInputSource route=\(route.rawValue) action=unregister"
        )
    }

    func handleGlobalHotkeyInput(_ event: HotkeyInputEvent) {
        guard let receipt = acceptHotkeyInput(
            event,
            route: .globalAppSwitcher
        ) else {
            return
        }
        switch event.phase {
        case .pressed:
            handleGlobalHotkeyPressed(receipt)
        case .released:
            handleGlobalHotkeyReleased(receipt)
        }
    }

    func handleInAppWindowHotkeyInput(_ event: HotkeyInputEvent) {
        guard let receipt = acceptHotkeyInput(
            event,
            route: .inAppWindowSwitcher
        ) else {
            return
        }
        switch event.phase {
        case .pressed:
            handleInAppWindowHotkeyPressed(receipt)
        case .released:
            handleInAppWindowHotkeyReleased(receipt)
        }
    }

    private func handleGlobalHotkeyPressed(
        _ receipt: SwitcherHotkeyInputReceipt
    ) {
        let isBackward = receipt.event.isBackward
        let nowMs = monotonicMilliseconds()
        let directionText = isBackward ? "backward" : "forward"
        if suppressHotkeyReplayUntilRelease {
            modifierReleaseObservationOwner.observeInputTransition()
            logInputTrace(
                "hotkeyPressed dir=\(directionText) dropped=awaitingHotkeyRelease \(hotkeyInputEvidenceFields(receipt)) nowMs=\(formatMilliseconds(nowMs))"
            )
            return
        }
        if isPanelPresented {
            guard activeHotkeySessionKind == .globalAppSwitcher else { return }
            guard !model.isSearchActive else {
                logInputTrace(
                    "hotkeyPressed dir=\(directionText) panelVisible=1 action=ignoredSearchMode nowMs=\(formatMilliseconds(nowMs))"
                )
                return
            }
            guard isHotkeyHoldSetPressed(receipt) else {
                logInputTrace(
                    "hotkeyPressed dir=\(directionText) panelVisible=1 modifierPressed=0 action=scheduleReleaseConfirm nowMs=\(formatMilliseconds(nowMs))"
                )
                scheduleModifierReleaseConfirmation(trigger: "pressed_without_modifier")
                return
            }
            logInputTrace(
                "hotkeyPressed dir=\(directionText) panelVisible=1 modifierPressed=1 action=advance nowMs=\(formatMilliseconds(nowMs))"
            )
            // Main switch hotkey is registered globally, so repeated key presses should keep
            // advancing while the panel is visible.
            advance(isBackward ? .tabBackward : .tabForward)
            return
        }
        logInputTrace(
            "hotkeyPressed dir=\(directionText) panelVisible=0 action=show nowMs=\(formatMilliseconds(nowMs))"
        )
        let direction: CycleDirection = isBackward ? .backward : .forward
        show(direction: direction)
    }

    private func handleGlobalHotkeyReleased(
        _ receipt: SwitcherHotkeyInputReceipt
    ) {
        if suppressHotkeyReplayUntilRelease {
            modifierReleaseObservationOwner.observeInputTransition()
            return
        }
        guard isPanelPresented else { return }
        guard activeHotkeySessionKind == .globalAppSwitcher else { return }
        guard !model.isSearchActive else { return }
        // Carbon hotkey "released" also fires when the main key (for example Tab) is released
        // while the modifier is still held. Ignore those events to avoid repeatedly spinning up
        // release-confirmation work during rapid cycling.
        guard !isHotkeyHoldSetPressed(receipt) else { return }
        let nowMs = monotonicMilliseconds()
        logInputTrace(
            "hotkeyReleased panelVisible=1 action=scheduleReleaseConfirm \(hotkeyInputEvidenceFields(receipt)) nowMs=\(formatMilliseconds(nowMs))"
        )
        scheduleModifierReleaseConfirmation(
            trigger: "hotkey_released",
            holdSetPressedEvidence: receipt.event.holdSetPressedEvidence
        )
    }

    private func handleInAppWindowHotkeyPressed(
        _ receipt: SwitcherHotkeyInputReceipt
    ) {
        let isBackward = receipt.event.isBackward
        let nowMs = monotonicMilliseconds()
        let directionText = isBackward ? "backward" : "forward"
        if suppressHotkeyReplayUntilRelease {
            modifierReleaseObservationOwner.observeInputTransition()
            logInputTrace(
                "inAppHotkeyPressed dir=\(directionText) dropped=awaitingHotkeyRelease \(hotkeyInputEvidenceFields(receipt)) nowMs=\(formatMilliseconds(nowMs))"
            )
            return
        }
        if isPanelPresented {
            guard activeHotkeySessionKind == .inAppWindowSwitcher else { return }
            guard isHotkeyHoldSetPressed(receipt) else {
                logInputTrace(
                    "inAppHotkeyPressed dir=\(directionText) panelVisible=1 modifierPressed=0 action=scheduleReleaseConfirm nowMs=\(formatMilliseconds(nowMs))"
                )
                scheduleModifierReleaseConfirmation(trigger: "in_app_pressed_without_modifier")
                return
            }
            logInputTrace(
                "inAppHotkeyPressed dir=\(directionText) panelVisible=1 modifierPressed=1 action=advance nowMs=\(formatMilliseconds(nowMs))"
            )
            let previousWindowID =
                model.session?.selectedWindow?.id
            advance(isBackward ? .tabBackward : .tabForward)
            if let evidence =
                InAppHotkeyAdvanceApplicationEvidence(
                    receipt: receipt,
                    previousWindowID: previousWindowID,
                    selectedWindowID:
                        model.session?.selectedWindow?.id
                )
            {
                logInputTrace(evidence.logMessage)
            }
            return
        }
        logInputTrace(
            "inAppHotkeyPressed dir=\(directionText) panelVisible=0 action=show nowMs=\(formatMilliseconds(nowMs))"
        )
        let direction: CycleDirection = isBackward ? .backward : .forward
        showInAppWindowSwitcher(
            direction: direction,
            initialKeyInput: isBackward ? .tabBackward : .tabForward
        )
    }

    private func handleInAppWindowHotkeyReleased(
        _ receipt: SwitcherHotkeyInputReceipt
    ) {
        if suppressHotkeyReplayUntilRelease {
            modifierReleaseObservationOwner.observeInputTransition()
            return
        }
        guard isPanelPresented else { return }
        guard activeHotkeySessionKind == .inAppWindowSwitcher else { return }
        guard !isHotkeyHoldSetPressed(receipt) else { return }
        let nowMs = monotonicMilliseconds()
        logInputTrace(
            "inAppHotkeyReleased panelVisible=1 action=scheduleReleaseConfirm \(hotkeyInputEvidenceFields(receipt)) nowMs=\(formatMilliseconds(nowMs))"
        )
        scheduleModifierReleaseConfirmation(
            trigger: "in_app_hotkey_released",
            holdSetPressedEvidence: receipt.event.holdSetPressedEvidence
        )
    }

    private func acceptHotkeyInput(
        _ event: HotkeyInputEvent,
        route: SwitcherHotkeyInputRoute
    ) -> SwitcherHotkeyInputReceipt? {
        let observation = hotkeyInputOwner.observe(
            event,
            route: route,
            presentationSessionGeneration: presentationSessionGeneration
        )
        switch observation {
        case .accepted(let receipt):
            logInputTrace(
                "hotkeyInput route=\(route.rawValue) phase=\(event.phase) action=accepted \(hotkeyInputEvidenceFields(receipt))"
            )
            return receipt
        case .rejected(let rejection):
            logInputTrace(
                "hotkeyInput route=\(route.rawValue) phase=\(event.phase) source=\(event.identity.sourceID.rawValue.uuidString) sequence=\(event.identity.sequence) action=rejected reason=\(rejection)"
            )
            return nil
        }
    }

    private func hotkeyInputRoute(for sessionKind: HotkeySessionKind) -> SwitcherHotkeyInputRoute {
        switch sessionKind {
        case .globalAppSwitcher:
            return .globalAppSwitcher
        case .inAppWindowSwitcher:
            return .inAppWindowSwitcher
        }
    }

    private func hotkeyInputEvidenceFields(
        _ receipt: SwitcherHotkeyInputReceipt
    ) -> String {
        "source=\(receipt.event.identity.sourceID.rawValue.uuidString) sequence=\(receipt.event.identity.sequence) inputGeneration=\(receipt.inputGeneration) sourceRegistrationGeneration=\(receipt.sourceRegistrationGeneration) sessionGeneration=\(receipt.presentationSessionGeneration)"
    }

    func advance(_ keyInput: KeyInput) {
        guard !model.isSearchActive else {
            logInputTrace(
                "advance key=\(keyInput.debugName) dropped=searchActive nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
            )
            return
        }
        if keyInput == .tabForward || keyInput == .tabBackward {
            guard isHotkeyHoldSetLikelyPressed() else {
                logInputTrace(
                    "advance key=\(keyInput.debugName) dropped=modifierNotPressed action=scheduleReleaseConfirm nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
                )
                scheduleModifierReleaseConfirmation(trigger: "advance_without_modifier")
                return
            }
            logInputTrace(
                "advance key=\(keyInput.debugName) accepted nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
            )
        }

        cancelPendingModifierReleaseConfirmation()
        if keyInput == .downArrow,
           beginManualWindowLayerEntryIfNeeded() {
            return
        }
        cancelManualWindowLayerEntryObservation()
        model.handle(keyInput)
        resetPointerSelectionGate()
        RuntimeLog.debug(.session, "advance key=\(keyInput.debugName) \(self.model.debugSelectionSummary())")
        updatePanelSize()
        scheduleDelayedWindowLayerEntryIfNeeded()
    }

    func terminateSelectedApp() {
        guard !terminatePressFeedbackCompletionOwner.isPending else {
            return
        }
        let shouldAnimatePress = model.prepareTerminateSelectedAppAnimation()

        guard shouldAnimatePress else {
            completeTerminateSelectedApp()
            return
        }

        terminatePressFeedbackCompletionOwner.start(
            after: terminatePressFeedbackPolicy.completionInterval
        ) { [weak self] completion in
            guard let self else { return }
            RuntimeLog.debug(
                .session,
                "terminate press feedback completed generation=\(completion.generation) intervalMs=\(completion.interval * 1_000)"
            )
            self.completeTerminateSelectedApp()
        }
    }

    private func completeTerminateSelectedApp() {
        let protectionGeneration = model.selectedApp.map {
            prepareTerminateInterruptionProtection(
                trigger: "terminate_selected_app",
                appID: $0.id
            )
        }
        switch model.terminateSelectedApp() {
        case .notHandled:
            if let protectionGeneration {
                cancelPreparedTerminateInterruptionProtection(
                    observationGeneration: protectionGeneration
                )
            }
            model.clearTerminateSelectedAppAnimation()
            RuntimeLog.info(.session, "terminate selected app ignored")
            NSSound.beep()
        case .updatedSession:
            guard
                let protectionGeneration,
                let request = model.pendingTerminateRequest
            else {
                cancelTerminateInterruptionProtection()
                RuntimeLog.error(
                    .session,
                    "terminate selected app missing observation identity"
                )
                return
            }
            commitTerminateInterruptionProtection(
                observationGeneration: protectionGeneration,
                request: request
            )
            RuntimeLog.info(
                .session,
                "terminate selected app \(model.debugSelectionSummary())"
            )
            updatePanelSize()
            scheduleDelayedWindowLayerEntryIfNeeded()
        case .sessionEnded:
            if let protectionGeneration {
                cancelPreparedTerminateInterruptionProtection(
                    observationGeneration: protectionGeneration
                )
            }
            model.clearTerminateSelectedAppAnimation()
            RuntimeLog.info(.session, "terminate selected app ended session")
            endPresentationSession()
        }
    }

    func activeHotkeyHoldKeys() -> SwitcherHotkeyKeySet {
        hotkeyHoldKeys(
            for: activeHotkeySessionKind ?? .globalAppSwitcher
        )
    }

    func hotkeyHoldKeys(
        for sessionKind: HotkeySessionKind
    ) -> SwitcherHotkeyKeySet {
        hotkeyConfiguration(for: sessionKind).baseKeys
    }

    func hotkeyConfiguration(
        for sessionKind: HotkeySessionKind
    ) -> SwitcherHotkeyConfiguration {
        if sessionKind == .inAppWindowSwitcher {
            return InAppWindowHotkeyPreferencesStore.load()
        }
        return SwitcherHotkeyPreferencesStore.load()
    }

    func isTerminateSelectedAppShortcut(_ event: NSEvent) -> Bool {
        guard activeHotkeySessionKind != .inAppWindowSwitcher else { return false }
        let hotkeyConfiguration = SwitcherHotkeyPreferencesStore.load()
        let eventKey = SwitcherHotkeyKey(keyCode: event.keyCode)
        guard hotkeyConfiguration.quitKeys.contains(eventKey) else {
            return false
        }
        if event.type == .keyDown, event.isARepeat {
            return false
        }
        if let modifier = eventKey.modifier {
            let pressedModifiers = KeyModifier(
                eventModifierFlags: event.modifierFlags.intersection(
                    .deviceIndependentFlagsMask
                )
            )
            guard pressedModifiers.contains(modifier) else { return false }
        }
        let remainingKeys = hotkeyConfiguration.quitShortcut.keys
            .subtracting([eventKey])
        guard remainingKeys.isEmpty
            || isHotkeyKeySetPressedInHardwareState(
                remainingKeys,
                eventModifierFlags: event.modifierFlags
            )
        else {
            return false
        }
        let otherActionKeys = hotkeyConfiguration.reverseKeys.union(
            hotkeyConfiguration.mainKeys
        )
        return !isAnyHotkeyKeyPressedInHardwareState(
            otherActionKeys,
            eventModifierFlags: event.modifierFlags
        )
    }
}
