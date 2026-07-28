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
            guard isPrimaryModifierLikelyPressed() else {
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
        guard !isPrimaryModifierPressedInHardwareState() else { return }
        let nowMs = monotonicMilliseconds()
        logInputTrace(
            "hotkeyReleased panelVisible=1 action=scheduleReleaseConfirm \(hotkeyInputEvidenceFields(receipt)) nowMs=\(formatMilliseconds(nowMs))"
        )
        scheduleModifierReleaseConfirmation(trigger: "hotkey_released")
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
            guard isPrimaryModifierLikelyPressed() else {
                logInputTrace(
                    "inAppHotkeyPressed dir=\(directionText) panelVisible=1 modifierPressed=0 action=scheduleReleaseConfirm nowMs=\(formatMilliseconds(nowMs))"
                )
                scheduleModifierReleaseConfirmation(trigger: "in_app_pressed_without_modifier")
                return
            }
            logInputTrace(
                "inAppHotkeyPressed dir=\(directionText) panelVisible=1 modifierPressed=1 action=advance nowMs=\(formatMilliseconds(nowMs))"
            )
            advance(isBackward ? .tabBackward : .tabForward)
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
        guard !isPrimaryModifierPressedInHardwareState() else { return }
        let nowMs = monotonicMilliseconds()
        logInputTrace(
            "inAppHotkeyReleased panelVisible=1 action=scheduleReleaseConfirm \(hotkeyInputEvidenceFields(receipt)) nowMs=\(formatMilliseconds(nowMs))"
        )
        scheduleModifierReleaseConfirmation(trigger: "in_app_hotkey_released")
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

    private func hotkeyInputRoute(
        for sessionKind: HotkeySessionKind
    ) -> SwitcherHotkeyInputRoute {
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
            guard isPrimaryModifierLikelyPressed() else {
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
        model.handle(keyInput)
        resetPointerSelectionGate()
        RuntimeLog.debug(.session, "advance key=\(keyInput.debugName) \(self.model.debugSelectionSummary())")
        updatePanelSize()
        scheduleDelayedWindowLayerEntryIfNeeded()
    }

    func scheduleDelayedWindowLayerEntryIfNeeded(preservingDeadline: Bool = false) {
        cancelDelayedWindowLayerTimer()
        let schedulingGeneration = delayedWindowLayerTimerGeneration
        guard autoEnterWindowLayerEnabled else {
            clearDelayedWindowLayerEntryState()
            return
        }
        guard !model.isSearchActive else {
            clearDelayedWindowLayerEntryState()
            RuntimeLog.debug(.autoEnter, "skip searchActive")
            return
        }

        guard isPanelPresented else {
            clearDelayedWindowLayerEntryState()
            RuntimeLog.debug(.autoEnter, "skip panelHidden")
            return
        }
        guard let session = model.session, case .appCycle = session.mode else {
            clearDelayedWindowLayerEntryState()
            return
        }

        let selectedAppID = session.selectedApp.id
        let nowMs = monotonicMilliseconds()
        if
            !preservingDeadline
                || delayedWindowLayerAppID != selectedAppID
                || delayedWindowLayerDeadlineMs == nil
        {
            delayedWindowLayerAppID = selectedAppID
            delayedWindowLayerDeadlineMs = nowMs + windowLayerPresentationDelay * 1_000
        }

        let deadlineMs = delayedWindowLayerDeadlineMs ?? nowMs
        let requestedProjection = model.scheduleSelectedAppWindowProjectionIfNeeded(for: selectedAppID)
        guard schedulingGeneration == delayedWindowLayerTimerGeneration else {
            RuntimeLog.debug(
                .autoEnter,
                "schedule superseded appID=\(selectedAppID) generation=\(schedulingGeneration) currentGeneration=\(delayedWindowLayerTimerGeneration)"
            )
            return
        }
        let prewarmedPreviewCount = prewarmSelectedAppWindowPreviewPage()
        let remainingDelay = max(0, (deadlineMs - nowMs) / 1_000)
        let hasManualWindowLayerEntry = model.pendingManualWindowLayerEntryAppID == selectedAppID
        guard model.canAutoEnterWindowLayer else {
            RuntimeLog.debug(
                .autoEnter,
                "pending appID=\(selectedAppID) requestedProjection=\(requestedProjection) prewarmed=\(prewarmedPreviewCount) deadlineMs=\(formatMilliseconds(deadlineMs)) \(self.model.debugSelectionSummary())"
            )
            if requestedProjection {
                let projectionApplyDelay = hasManualWindowLayerEntry
                    ? min(remainingDelay, manualWindowLayerProjectionApplyDelay)
                    : remainingDelay
                RuntimeLog.debug(
                    .autoEnter,
                    "schedule projectionApplyDelay=\(projectionApplyDelay)s manual=\(hasManualWindowLayerEntry) \(self.model.debugSelectionSummary())"
                )
                scheduleDelayedWindowLayerTimer(
                    remainingDelay: projectionApplyDelay,
                    generation: schedulingGeneration
                )
            }
            return
        }
        RuntimeLog.debug(
            .autoEnter,
            "schedule delay=\(remainingDelay)s prewarmed=\(prewarmedPreviewCount) deadlineMs=\(formatMilliseconds(deadlineMs)) \(self.model.debugSelectionSummary())"
        )

        scheduleDelayedWindowLayerTimer(
            remainingDelay: remainingDelay,
            generation: schedulingGeneration
        )
    }

    func prewarmSelectedAppWindowPreviewPage() -> Int {
        guard let selectedApp = model.selectedApp, !selectedApp.windows.isEmpty else { return 0 }
        let sizingScreen = resolveSizingScreen(preferredScreen: activePresentationScreen)
        let visibleFrameSize = sizingScreen?.visibleFrame.size
            ?? CGSize(width: 1_440, height: 900)
        let maximumPanelWidth = max(
            appLayerMinimumWidth,
            visibleFrameSize.width - panelScreenMargin
        )
        let previewPanelWidth = min(
            maximumPanelWidth,
            preferredPreviewLayerWidth(
                appCount: model.appCount,
                windowCount: selectedApp.windows.count,
                maxPanelWidth: maximumPanelWidth
            )
        )
        let previewAvailableWidth = max(
            1,
            previewPanelWidth
                - SwitcherPanelLayoutMetrics.horizontalInset
                - standardPreviewWidthAdjustment
        )
        return model.prewarmSelectedAppWindowPreviews(availableWidth: previewAvailableWidth)
    }

    func scheduleDelayedWindowLayerTimer(
        remainingDelay: TimeInterval,
        generation: Int
    ) {
        guard generation == delayedWindowLayerTimerGeneration else { return }
        guard remainingDelay > 0 else {
            enterDelayedWindowLayerIfReady(reason: "deadlineElapsed", generation: generation)
            return
        }

        RuntimeLog.debug(
            .autoEnter,
            "schedule timer delay=\(remainingDelay)s generation=\(generation)"
        )
        let timer = Timer(timeInterval: remainingDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.enterDelayedWindowLayerIfReady(reason: "timer", generation: generation)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        delayedWindowLayerTimer = timer
    }

    func enterDelayedWindowLayerIfReady(reason: String, generation: Int) {
        guard generation == delayedWindowLayerTimerGeneration else {
            RuntimeLog.debug(
                .autoEnter,
                "timer stale reason=\(reason) generation=\(generation) currentGeneration=\(delayedWindowLayerTimerGeneration)"
            )
            return
        }
        guard isPanelPresented else {
            clearDelayedWindowLayerEntryState()
            return
        }
        let nowMs = monotonicMilliseconds()
        let deadlineMs = delayedWindowLayerDeadlineMs ?? nowMs
        let overshootMs = max(0, nowMs - deadlineMs)
        if !model.canAutoEnterWindowLayer {
            _ = model.applySelectedAppWindowProjectionIfReady(for: delayedWindowLayerAppID)
        }
        if model.autoEnterWindowLayerIfPossible() {
            RuntimeLog.debug(
                .autoEnter,
                "entered reason=\(reason) overshootMs=\(formatMilliseconds(overshootMs)) \(self.model.debugSelectionSummary())"
            )
            if overshootMs > 10 {
                RuntimeLog.warning(
                    .autoEnter,
                    "deadline overshootMs=\(formatMilliseconds(overshootMs)) \(self.model.debugSelectionSummary())"
                )
            }
            clearDelayedWindowLayerEntryState()
            updatePanelSize()
        } else {
            RuntimeLog.debug(
                .autoEnter,
                "timer fired but stay app layer reason=\(reason) \(self.model.debugSelectionSummary())"
            )
        }
    }

    func clearDelayedWindowLayerEntryState() {
        cancelDelayedWindowLayerTimer()
        delayedWindowLayerDeadlineMs = nil
        delayedWindowLayerAppID = nil
    }

    func cancelDelayedWindowLayerTimer() {
        delayedWindowLayerTimer?.invalidate()
        delayedWindowLayerTimer = nil
        delayedWindowLayerTimerGeneration &+= 1
    }

    func terminateSelectedApp() {
        guard terminateSelectedAppTask == nil else { return }
        let shouldAnimatePress = model.prepareTerminateSelectedAppAnimation()

        terminateSelectedAppTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.terminateSelectedAppTask = nil
            }

            if shouldAnimatePress {
                try? await Task.sleep(nanoseconds: 80_000_000)
                guard !Task.isCancelled else { return }
            }

            switch self.model.terminateSelectedApp() {
            case .notHandled:
                self.model.clearTerminateSelectedAppAnimation()
                RuntimeLog.info(.session, "terminate selected app ignored")
                NSSound.beep()
            case .updatedSession:
                self.beginTerminateInterruptionProtection(trigger: "terminate_selected_app")
                RuntimeLog.info(.session, "terminate selected app \(self.model.debugSelectionSummary())")
                self.updatePanelSize()
                self.scheduleDelayedWindowLayerEntryIfNeeded()
            case .sessionEnded:
                self.model.clearTerminateSelectedAppAnimation()
                RuntimeLog.info(.session, "terminate selected app ended session")
                self.endPresentationSession()
            }
        }
    }

    func activePrimaryModifier() -> SwitcherPrimaryModifier {
        primaryModifier(for: activeHotkeySessionKind ?? .globalAppSwitcher)
    }

    func primaryModifier(for sessionKind: HotkeySessionKind) -> SwitcherPrimaryModifier {
        if sessionKind == .inAppWindowSwitcher {
            return InAppWindowHotkeyPreferencesStore.load().primaryModifier
        }
        return SwitcherHotkeyPreferencesStore.load().primaryModifier
    }

    func activePrimaryModifierFlag() -> NSEvent.ModifierFlags {
        activePrimaryModifier().eventModifierFlag
    }

    func isTerminateSelectedAppShortcut(_ event: NSEvent) -> Bool {
        guard activeHotkeySessionKind != .inAppWindowSwitcher else { return false }
        let hotkeyConfiguration = SwitcherHotkeyPreferencesStore.load()
        guard event.keyCode == hotkeyConfiguration.quitKeyCode else { return false }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(hotkeyConfiguration.primaryModifier.eventModifierFlag) else { return false }
        guard !flags.contains(.shift) else { return false }

        switch hotkeyConfiguration.primaryModifier {
        case .option:
            return !flags.contains(.command) && !flags.contains(.control)
        case .control:
            return !flags.contains(.command) && !flags.contains(.option)
        case .command:
            return !flags.contains(.control) && !flags.contains(.option)
        }
    }
}
