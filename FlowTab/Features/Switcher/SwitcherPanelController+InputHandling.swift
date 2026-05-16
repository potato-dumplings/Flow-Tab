import AppKit
import Carbon
import CoreGraphics
import SwiftUI
import FlowTabCore

extension SwitcherPanelController {
    func installEventMonitors() {
        removeEventMonitors()

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return handleKeyDown(event) ? nil : event
        }

        localFlagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return nil
        }

        globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleGlobalKeyDown(event)
            }
        }

        globalFlagsChangedMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleGlobalMouseDown(event)
            }
        }
    }

    func removeEventMonitors() {
        terminateSelectedAppTask?.cancel()
        terminateSelectedAppTask = nil
        model.clearTerminateSelectedAppAnimation()
        cancelPendingModifierReleaseConfirmation()
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
        if let localFlagsChangedMonitor {
            NSEvent.removeMonitor(localFlagsChangedMonitor)
            self.localFlagsChangedMonitor = nil
        }
        if let globalKeyDownMonitor {
            NSEvent.removeMonitor(globalKeyDownMonitor)
            self.globalKeyDownMonitor = nil
        }
        if let globalFlagsChangedMonitor {
            NSEvent.removeMonitor(globalFlagsChangedMonitor)
            self.globalFlagsChangedMonitor = nil
        }
        if let globalMouseDownMonitor {
            NSEvent.removeMonitor(globalMouseDownMonitor)
            self.globalMouseDownMonitor = nil
        }
        if let delayedWindowLayerTimer {
            delayedWindowLayerTimer.invalidate()
            self.delayedWindowLayerTimer = nil
        }
        delayedWindowLayerDeadlineMs = nil
        delayedWindowLayerAppID = nil
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        if model.isSearchActive {
            return handleSearchModeKeyDown(event)
        }

        switch event.keyCode {
        case 49:
            return true
        case 36, 76:
            if !enterSearchModeIfPossible() {
                finishSelection()
            }
            return true
        case 48:
            if activeHotkeySessionKind == .inAppWindowSwitcher {
                return true
            }
            if SwitcherHotkeyPreferencesStore.load().mainKey == .tab {
                return true
            }
            advance(event.modifierFlags.contains(.shift) ? .tabBackward : .tabForward)
            return true
        case 123:
            advance(.leftArrow)
            return true
        case 124:
            advance(.rightArrow)
            return true
        case 125:
            advance(.downArrow)
            return true
        case 126:
            if !enterSearchModeIfPossible() {
                advance(.upArrow)
            }
            return true
        case 53:
            if model.shouldClearSearchOnEscape {
                _ = model.handleSearchEscape()
                updatePanelSize()
            } else {
                cancelSelection()
            }
            return true
        default:
            if isTerminateSelectedAppShortcut(event) {
                terminateSelectedApp()
                return true
            }
            return false
        }
    }

    @discardableResult
    func enterSearchModeIfPossible() -> Bool {
        logSearchTrace("enterSearchMode action=attempt \(searchTraceStateSummary())")
        guard searchFeatureEnabled else {
            logSearchTrace("enterSearchMode action=ignored reason=featureDisabled \(searchTraceStateSummary())")
            return false
        }
        guard model.enterSearchMode() else {
            logSearchTrace("enterSearchMode action=ignored reason=modelRejected \(searchTraceStateSummary())")
            return false
        }
        cancelPendingModifierReleaseConfirmation()
        updatePanelSize()
        RuntimeLog.info(.session, "enter search mode")
        logSearchTrace("enterSearchMode action=entered \(searchTraceStateSummary())")
        return true
    }

    func handleSearchModeKeyDown(_ event: NSEvent) -> Bool {
        let isComposingMarkedText = model.hasMarkedSearchText
        switch event.keyCode {
        case 48:
            guard !isComposingMarkedText else { return false }
            if model.toggleSearchScope() {
                updatePanelSize()
            }
            return true
        case 125:
            guard !isComposingMarkedText else { return false }
            _ = model.stepSearchSelectionDown()
            return true
        case 126:
            guard !isComposingMarkedText else { return false }
            _ = model.stepSearchSelectionUp()
            return true
        case 123:
            guard !isComposingMarkedText else { return false }
            guard !model.isSearchInputFocused else { return false }
            _ = model.moveSearchSelection(by: -1)
            return true
        case 124:
            guard !isComposingMarkedText else { return false }
            guard !model.isSearchInputFocused else { return false }
            _ = model.moveSearchSelection(by: +1)
            return true
        case 36, 76:
            guard !isComposingMarkedText else { return false }
            guard model.applySelectedSearchResultToSession() else {
                NSSound.beep()
                return true
            }
            finishSelection()
            return true
        case 53:
            guard !isComposingMarkedText else { return false }
            if !model.isSearchInputFocused {
                if model.focusSearchInput() {
                    updatePanelSize()
                }
                return true
            }
            if model.handleSearchEscape() != .ignored {
                updatePanelSize()
            }
            return true
        case 51:
            if model.searchViewState.query.isEmpty {
                return true
            }
            return false
        default:
            return false
        }
    }

    func handleFlagsChanged(_ event: NSEvent) {
        let isPrimaryEvent = isPrimaryModifierFlagsEvent(event)
        guard isPrimaryEvent else { return }
        guard isPanelPresented else { return }
        guard !model.isSearchActive else { return }
        logInputTrace(
            "flagsChanged keyCode=\(event.keyCode) action=scheduleReleaseConfirm nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
        )
        scheduleModifierReleaseConfirmation(trigger: "flags_changed")
    }

    func handleGlobalMouseDown(_ event: NSEvent) {
        handleGlobalMouseDown(at: event.locationInWindow)
    }

    func handleGlobalMouseDown(at location: NSPoint) {
        guard isPanelPresented else { return }
        guard model.isSearchActive else { return }
        let isInsidePanel = panelContainsPointOverride?(location) ?? panel.frame.contains(location)
        guard !isInsidePanel else { return }
        logInputTrace(
            "globalMouseDownOutsidePanel action=cancelSelection nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
        )
        cancelSelection()
    }

    func handleGlobalKeyDown(_ event: NSEvent) {
        guard isPanelPresented else { return }
        guard !isAppCurrentlyActive else { return }
        guard event.keyCode == 53 else { return }
        logInputTrace(
            "globalEscWhileAppInactive action=cancelSelection nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
        )
        cancelSelection()
    }

    func handleApplicationDidResignActive() {
        guard isPanelPresented else { return }
        logSearchTrace("systemInterruption trigger=applicationDidResignActive \(searchTraceStateSummary())")
        handleRecoverableSystemInterruption(trigger: "applicationDidResignActive")
    }

    func handleActiveSpaceDidChange() {
        guard isPanelPresented else { return }
        if shouldIgnoreActiveSpaceDidChange() {
            logSearchTrace("systemInterruption trigger=activeSpaceDidChange action=ignored reason=graceWindow \(searchTraceStateSummary())")
            return
        }
        guard let sessionKind = activeHotkeySessionKind else {
            cancelSelectionForSystemInterruption(trigger: "activeSpaceDidChange")
            return
        }
        let shouldKeepSessionVisible = model.isSearchActive
            || isPrimaryModifierPressedInHardwareState(for: sessionKind)
        guard shouldKeepSessionVisible else {
            logSearchTrace(
                "systemInterruption trigger=activeSpaceDidChange action=cancel reason=modifierReleased \(searchTraceStateSummary())"
            )
            cancelSelectionForSystemInterruption(trigger: "activeSpaceDidChange")
            return
        }
        logSearchTrace(
            "systemInterruption trigger=activeSpaceDidChange action=migrate reason=spaceChanged \(searchTraceStateSummary())"
        )
        suppressApplicationActivationUntil = ProcessInfo.processInfo.systemUptime
            + activeSpaceMigrationActivationSuppressionWindow
        schedulePanelVisibilityRecovery(
            trigger: "activeSpaceDidChange",
            attemptDelaysNanoseconds: interruptionPresentationRecoveryAttemptDelaysNs,
            cancelSessionOnFailure: true,
            activateApplicationIfNeeded: false
        )
    }

    func handlePanelOcclusionStateDidChange() {
        guard isPanelPresented else { return }
        guard !resolvedPanelOcclusionState.contains(.visible) else { return }
        logSearchTrace("systemInterruption trigger=panelOccluded \(searchTraceStateSummary())")
        handleRecoverableSystemInterruption(trigger: "panelOccluded")
    }

    func handlePanelDidResignKey() {
        guard isPanelPresented else { return }
        guard !isAppCurrentlyActive else { return }
        logSearchTrace("systemInterruption trigger=panelDidResignKey \(searchTraceStateSummary())")
        handleRecoverableSystemInterruption(trigger: "panelDidResignKey")
    }

    func handleRecoverableSystemInterruption(trigger: String) {
        guard let sessionKind = activeHotkeySessionKind else {
            cancelSelectionForSystemInterruption(trigger: trigger)
            return
        }
        let shouldKeepSessionVisible = model.isSearchActive
            || isPrimaryModifierPressedInHardwareState(for: sessionKind)
        guard shouldKeepSessionVisible else {
            logSearchTrace(
                "systemInterruption trigger=\(trigger) action=cancel reason=modifierReleased \(searchTraceStateSummary())"
            )
            cancelSelectionForSystemInterruption(trigger: trigger)
            return
        }
        logSearchTrace(
            "systemInterruption trigger=\(trigger) action=recover \(searchTraceStateSummary())"
        )
        schedulePanelVisibilityRecovery(
            trigger: trigger,
            attemptDelaysNanoseconds: interruptionPresentationRecoveryAttemptDelaysNs,
            cancelSessionOnFailure: true
        )
    }

    func cancelSelectionForSystemInterruption(trigger: String) {
        guard isPanelPresented || hasActivePresentationSession else { return }
        let sessionKind = activeHotkeySessionKind
        logSearchTrace("cancelSelectionForSystemInterruption trigger=\(trigger) action=begin \(searchTraceStateSummary())")
        logInputTrace(
            "\(trigger) action=cancelSelection nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
        )
        cancelSelection()
        logSearchTrace("cancelSelectionForSystemInterruption trigger=\(trigger) action=finished \(searchTraceStateSummary())")
        if let sessionKind {
            beginHotkeyReplaySuppressionUntilRelease(for: sessionKind, trigger: trigger)
        } else {
            beginHotkeyReplaySuppressionUntilReleaseForKnownSessionKinds(trigger: trigger)
        }
    }

    func beginHotkeyReplaySuppressionUntilRelease(
        for sessionKind: HotkeySessionKind,
        trigger: String
    ) {
        beginHotkeyReplaySuppressionUntilRelease(
            monitoring: [sessionKind],
            trigger: trigger
        )
    }

    func beginHotkeyReplaySuppressionUntilReleaseForKnownSessionKinds(trigger: String) {
        beginHotkeyReplaySuppressionUntilRelease(
            monitoring: [.globalAppSwitcher, .inAppWindowSwitcher],
            trigger: trigger
        )
    }

    func beginHotkeyReplaySuppressionUntilRelease(
        monitoring sessionKinds: [HotkeySessionKind],
        trigger: String
    ) {
        suppressHotkeyReplayTask?.cancel()
        suppressHotkeyReplayUntilRelease = true
        logInputTrace(
            "hotkeyReplaySuppression start trigger=\(trigger) nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
        )
        suppressHotkeyReplayTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var releasedSampleCount = 0
            while true {
                try? await Task.sleep(nanoseconds: self.modifierReleaseConfirmationSampleIntervalNs)
                guard !Task.isCancelled else { return }
                let hasPressedHotkeyInputs = sessionKinds.contains { sessionKind in
                    self.isPrimaryModifierPressedInHardwareState(for: sessionKind)
                        || self.isSessionMainKeyPressedInHardwareState(for: sessionKind)
                }
                if hasPressedHotkeyInputs {
                    releasedSampleCount = 0
                    continue
                }
                releasedSampleCount += 1
                if releasedSampleCount < self.modifierReleaseConfirmationSampleCount {
                    continue
                }
                self.suppressHotkeyReplayUntilRelease = false
                self.suppressHotkeyReplayTask = nil
                self.logInputTrace(
                    "hotkeyReplaySuppression end trigger=\(trigger) nowMs=\(self.formatMilliseconds(self.monotonicMilliseconds()))"
                )
                return
            }
        }
    }

    func scheduleModifierReleaseConfirmation(trigger: String) {
        guard !suppressModifierReleaseConfirmationForTesting else {
            logInputTrace(
                "releaseConfirm suppressed trigger=\(trigger) nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
            )
            return
        }
        if pendingModifierReleaseConfirmationTask != nil {
            logInputTrace(
                "releaseConfirm alreadyRunning trigger=\(trigger) nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
            )
            return
        }
        logInputTrace(
            "releaseConfirm start trigger=\(trigger) nowMs=\(formatMilliseconds(monotonicMilliseconds())) intervalMs=\(formatMilliseconds(Double(modifierReleaseConfirmationSampleIntervalNs) / 1_000_000)) samples=\(modifierReleaseConfirmationSampleCount)"
        )

        pendingModifierReleaseConfirmationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var releasedSampleCount = 0

            while true {
                try? await Task.sleep(nanoseconds: self.modifierReleaseConfirmationSampleIntervalNs)
                guard !Task.isCancelled else { return }
                guard self.isPanelPresented else {
                    self.logInputTrace(
                        "releaseConfirm stop trigger=\(trigger) reason=panelHidden nowMs=\(self.formatMilliseconds(self.monotonicMilliseconds()))"
                    )
                    self.pendingModifierReleaseConfirmationTask = nil
                    return
                }
                guard !self.model.isSearchActive else {
                    self.logInputTrace(
                        "releaseConfirm stop trigger=\(trigger) reason=searchActive nowMs=\(self.formatMilliseconds(self.monotonicMilliseconds()))"
                    )
                    self.logSearchTrace(
                        "releaseConfirm trigger=\(trigger) action=stop reason=searchActive \(self.searchTraceStateSummary())"
                    )
                    self.pendingModifierReleaseConfirmationTask = nil
                    return
                }

                if self.isPrimaryModifierLikelyPressed() {
                    if releasedSampleCount > 0 {
                        self.logInputTrace(
                            "releaseConfirm reset trigger=\(trigger) releasedSamples=\(releasedSampleCount) nowMs=\(self.formatMilliseconds(self.monotonicMilliseconds()))"
                        )
                    }
                    releasedSampleCount = 0
                    continue
                }
                releasedSampleCount += 1
                self.logInputTrace(
                    "releaseConfirm sample trigger=\(trigger) releasedSamples=\(releasedSampleCount)/\(self.modifierReleaseConfirmationSampleCount) nowMs=\(self.formatMilliseconds(self.monotonicMilliseconds()))"
                )
                if releasedSampleCount < self.modifierReleaseConfirmationSampleCount {
                    continue
                }

                self.pendingModifierReleaseConfirmationTask = nil
                self.logInputTrace(
                    "releaseConfirm confirmed trigger=\(trigger) action=finishSelection nowMs=\(self.formatMilliseconds(self.monotonicMilliseconds()))"
                )
                self.logSearchTrace(
                    "releaseConfirm trigger=\(trigger) action=confirmed \(self.searchTraceStateSummary())"
                )
                self.finishSelection()
                return
            }
        }
    }

    func cancelPendingModifierReleaseConfirmation() {
        guard let pendingModifierReleaseConfirmationTask else { return }
        logInputTrace(
            "releaseConfirm canceled nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
        )
        pendingModifierReleaseConfirmationTask.cancel()
        self.pendingModifierReleaseConfirmationTask = nil
    }

    func isPrimaryModifierFlagsEvent(_ event: NSEvent) -> Bool {
        switch activePrimaryModifier() {
        case .option:
            return event.keyCode == UInt16(kVK_Option) || event.keyCode == UInt16(kVK_RightOption)
        case .control:
            return event.keyCode == UInt16(kVK_Control) || event.keyCode == UInt16(kVK_RightControl)
        case .command:
            return event.keyCode == UInt16(kVK_Command) || event.keyCode == UInt16(kVK_RightCommand)
        }
    }

    func isPrimaryModifierPressedInHardwareState() -> Bool {
        isPrimaryModifierPressedInHardwareState(for: activeHotkeySessionKind ?? .globalAppSwitcher)
    }

    func isPrimaryModifierPressedInHardwareState(for sessionKind: HotkeySessionKind) -> Bool {
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

        switch primaryModifier(for: sessionKind) {
        case .option:
            return CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Option))
                || CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_RightOption))
        case .control:
            return CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Control))
                || CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_RightControl))
        case .command:
            return CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Command))
                || CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_RightCommand))
        }
    }

    func isSessionMainKeyPressedInHardwareState(for sessionKind: HotkeySessionKind) -> Bool {
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
            keyCode = CGKeyCode(SwitcherHotkeyPreferencesStore.load().mainKey.keyCode)
        case .inAppWindowSwitcher:
            keyCode = CGKeyCode(InAppWindowHotkeyPreferencesStore.load().mainKey.keyCode)
        }
        return CGEventSource.keyState(.combinedSessionState, key: keyCode)
    }

    func isPrimaryModifierLikelyPressed(event: NSEvent? = nil) -> Bool {
        if isPrimaryModifierPressedInHardwareState() {
            return true
        }
        guard let event else { return false }
        let eventFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return eventFlags.contains(activePrimaryModifierFlag())
    }

}
