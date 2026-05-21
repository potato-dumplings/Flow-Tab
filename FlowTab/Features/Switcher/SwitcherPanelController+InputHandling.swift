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

        localMouseMovedMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handlePointerMoved()
            return event
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

        globalMouseMovedMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handlePointerMoved()
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
        if let localMouseMovedMonitor {
            NSEvent.removeMonitor(localMouseMovedMonitor)
            self.localMouseMovedMonitor = nil
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
        if let globalMouseMovedMonitor {
            NSEvent.removeMonitor(globalMouseMovedMonitor)
            self.globalMouseMovedMonitor = nil
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

    func resetPointerSelectionGate() {
        pointerSelectionGate.reset(currentLocation: NSEvent.mouseLocation)
    }

    func handlePointerMoved() {
        guard isPanelPresented else { return }
        pointerSelectionGate.recordPointerMoved(to: NSEvent.mouseLocation)
    }

    func selectSwitcherAppByPointer(appID: String, currentLocation: CGPoint? = nil) {
        pointerSelectionGate.recordPointerMoved(to: currentLocation ?? NSEvent.mouseLocation)
        guard pointerSelectionGate.isArmed else { return }
        guard model.selectAppFromPointer(appID: appID) else { return }
        updatePanelSize()
        scheduleDelayedWindowLayerEntryIfNeeded()
    }

    func selectSwitcherWindowByPointer(appID: String, windowID: String, currentLocation: CGPoint? = nil) {
        pointerSelectionGate.recordPointerMoved(to: currentLocation ?? NSEvent.mouseLocation)
        guard pointerSelectionGate.isArmed else { return }
        guard model.selectWindowFromPointer(appID: appID, windowID: windowID) else { return }
        updatePanelSize()
    }

    func selectSwitcherSearchResultByPointer(resultID: String, currentLocation: CGPoint? = nil) {
        pointerSelectionGate.recordPointerMoved(to: currentLocation ?? NSEvent.mouseLocation)
        guard pointerSelectionGate.isArmed else { return }
        guard model.selectSearchResult(withID: resultID) else { return }
        updatePanelSize()
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
        resetPointerSelectionGate()
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
                resetPointerSelectionGate()
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
                resetPointerSelectionGate()
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
        if handleProtectedTerminateSystemInterruption(trigger: "activeSpaceDidChange") {
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
        if resolvedPanelOcclusionState.contains(.visible) {
            _ = completeInitialPresentationVisibilityIfVisible(
                reason: "occlusionVisible",
                cancelRecoveryTask: true
            )
            return
        }
        guard !shouldDeferInitialPanelOcclusionInterruption(trigger: "panelOccluded") else {
            return
        }
        logSearchTrace("systemInterruption trigger=panelOccluded \(searchTraceStateSummary())")
        handleRecoverableSystemInterruption(trigger: "panelOccluded")
    }

    func handlePanelDidResignKey() {
        guard isPanelPresented else { return }
        guard !isAppCurrentlyActive else { return }
        logSearchTrace("systemInterruption trigger=panelDidResignKey \(searchTraceStateSummary())")
        handleRecoverableSystemInterruption(trigger: "panelDidResignKey")
    }

    func handleWorkspaceApplicationTerminated(appID: String, pid: pid_t) {
        let refreshed = model.handleApplicationTerminated(appID: appID, pid: pid)
        guard refreshed else { return }
        beginTerminateInterruptionProtection(
            trigger: "terminate_refresh",
            duration: postTerminateRefreshInterruptionProtectionWindow,
            extendExisting: false
        )
        beginIgnoringActiveSpaceChanges(trigger: "terminate_refresh")
    }

    func handleRecoverableSystemInterruption(trigger: String) {
        if handleProtectedTerminateSystemInterruption(trigger: trigger) {
            return
        }
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

    func handleProtectedTerminateSystemInterruption(trigger: String) -> Bool {
        guard shouldProtectTerminateSystemInterruption() else { return false }
        logSearchTrace(
            "systemInterruption trigger=\(trigger) action=recover reason=terminateInFlight \(searchTraceStateSummary())"
        )
        schedulePanelVisibilityRecovery(
            trigger: "\(trigger)_terminate",
            attemptDelaysNanoseconds: interruptionPresentationRecoveryAttemptDelaysNs,
            cancelSessionOnFailure: false,
            activateApplicationIfNeeded: trigger != "activeSpaceDidChange"
        )
        return true
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
        modifierReleaseConfirmationGeneration += 1
        let generation = modifierReleaseConfirmationGeneration
        suppressHotkeyReplayUntilRelease = true
        modifierReleaseState = .replaySuppression(
            trigger: trigger,
            generation: generation,
            releasedSamples: 0
        )
        logInputTrace(
            "hotkeyReplaySuppression start trigger=\(trigger) generation=\(generation) nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
        )
        suppressHotkeyReplayTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.isModifierReleaseConfirmationGenerationCurrent(generation) else { return }
            var releasedSampleCount = 0
            while true {
                try? await Task.sleep(nanoseconds: self.modifierReleaseConfirmationSampleIntervalNs)
                guard !Task.isCancelled else { return }
                guard self.isModifierReleaseConfirmationGenerationCurrent(generation) else { return }
                let hasPressedHotkeyInputs = sessionKinds.contains { sessionKind in
                    self.isPrimaryModifierPressedInHardwareState(for: sessionKind)
                        || self.isSessionMainKeyPressedInHardwareState(for: sessionKind)
                }
                if hasPressedHotkeyInputs {
                    releasedSampleCount = 0
                    self.modifierReleaseState = .replaySuppression(
                        trigger: trigger,
                        generation: generation,
                        releasedSamples: 0
                    )
                    continue
                }
                releasedSampleCount += 1
                self.modifierReleaseState = .replaySuppression(
                    trigger: trigger,
                    generation: generation,
                    releasedSamples: releasedSampleCount
                )
                if releasedSampleCount < self.modifierReleaseConfirmationSampleCount {
                    continue
                }
                guard self.isModifierReleaseConfirmationGenerationCurrent(generation) else { return }
                self.suppressHotkeyReplayUntilRelease = false
                self.clearHotkeyReplaySuppressionTaskIfCurrent(generation)
                self.modifierReleaseState = .replaySuppressionEnded(
                    trigger: trigger,
                    generation: generation
                )
                self.logInputTrace(
                    "hotkeyReplaySuppression end trigger=\(trigger) generation=\(generation) nowMs=\(self.formatMilliseconds(self.monotonicMilliseconds()))"
                )
                return
            }
        }
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
        if pendingModifierReleaseConfirmationTask != nil {
            logInputTrace(
                "releaseConfirm alreadyRunning trigger=\(trigger) nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
            )
            return
        }
        logInputTrace(
            "releaseConfirm start trigger=\(trigger) nowMs=\(formatMilliseconds(monotonicMilliseconds())) intervalMs=\(formatMilliseconds(Double(modifierReleaseConfirmationSampleIntervalNs) / 1_000_000)) samples=\(modifierReleaseConfirmationSampleCount)"
        )

        modifierReleaseConfirmationGeneration += 1
        let generation = modifierReleaseConfirmationGeneration
        let sessionGeneration = presentationSessionGeneration
        modifierReleaseState = .releaseObserved(trigger: trigger, generation: generation)
        pendingModifierReleaseConfirmationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.isModifierReleaseConfirmationGenerationCurrent(generation) else { return }
            guard self.isPresentationSessionGenerationCurrent(sessionGeneration) else {
                self.modifierReleaseState = .canceled(reason: .sessionChanged, generation: generation)
                self.logInputTrace(
                    "releaseConfirm stop trigger=\(trigger) reason=sessionChanged generation=\(generation) sessionGeneration=\(sessionGeneration) currentSessionGeneration=\(self.presentationSessionGeneration) nowMs=\(self.formatMilliseconds(self.monotonicMilliseconds()))"
                )
                self.clearPendingModifierReleaseConfirmationTaskIfCurrent(generation)
                return
            }
            var releasedSampleCount = 0

            while true {
                try? await Task.sleep(nanoseconds: self.modifierReleaseConfirmationSampleIntervalNs)
                guard !Task.isCancelled else { return }
                guard self.isModifierReleaseConfirmationGenerationCurrent(generation) else { return }
                guard self.isPresentationSessionGenerationCurrent(sessionGeneration) else {
                    self.modifierReleaseState = .canceled(reason: .sessionChanged, generation: generation)
                    self.logInputTrace(
                        "releaseConfirm stop trigger=\(trigger) reason=sessionChanged generation=\(generation) sessionGeneration=\(sessionGeneration) currentSessionGeneration=\(self.presentationSessionGeneration) nowMs=\(self.formatMilliseconds(self.monotonicMilliseconds()))"
                    )
                    self.clearPendingModifierReleaseConfirmationTaskIfCurrent(generation)
                    return
                }
                guard self.isPanelPresented else {
                    self.modifierReleaseState = .canceled(reason: .panelHidden, generation: generation)
                    self.logInputTrace(
                        "releaseConfirm stop trigger=\(trigger) reason=panelHidden generation=\(generation) nowMs=\(self.formatMilliseconds(self.monotonicMilliseconds()))"
                    )
                    self.clearPendingModifierReleaseConfirmationTaskIfCurrent(generation)
                    return
                }
                guard !self.model.isSearchActive else {
                    self.modifierReleaseState = .canceled(reason: .searchActive, generation: generation)
                    self.logInputTrace(
                        "releaseConfirm stop trigger=\(trigger) reason=searchActive generation=\(generation) nowMs=\(self.formatMilliseconds(self.monotonicMilliseconds()))"
                    )
                    self.logSearchTrace(
                        "releaseConfirm trigger=\(trigger) action=stop reason=searchActive generation=\(generation) \(self.searchTraceStateSummary())"
                    )
                    self.clearPendingModifierReleaseConfirmationTaskIfCurrent(generation)
                    return
                }

                if self.isPrimaryModifierLikelyPressed() {
                    if releasedSampleCount > 0 {
                        self.logInputTrace(
                            "releaseConfirm reset trigger=\(trigger) generation=\(generation) releasedSamples=\(releasedSampleCount) nowMs=\(self.formatMilliseconds(self.monotonicMilliseconds()))"
                        )
                    }
                    releasedSampleCount = 0
                    self.modifierReleaseState = .pressed(generation: generation)
                    continue
                }
                releasedSampleCount += 1
                self.modifierReleaseState = .confirming(
                    trigger: trigger,
                    generation: generation,
                    releasedSamples: releasedSampleCount
                )
                self.logInputTrace(
                    "releaseConfirm sample trigger=\(trigger) generation=\(generation) releasedSamples=\(releasedSampleCount)/\(self.modifierReleaseConfirmationSampleCount) nowMs=\(self.formatMilliseconds(self.monotonicMilliseconds()))"
                )
                if releasedSampleCount < self.modifierReleaseConfirmationSampleCount {
                    continue
                }

                guard self.isModifierReleaseConfirmationGenerationCurrent(generation) else { return }
                guard self.isPresentationSessionGenerationCurrent(sessionGeneration) else {
                    self.modifierReleaseState = .canceled(reason: .sessionChanged, generation: generation)
                    self.logInputTrace(
                        "releaseConfirm stop trigger=\(trigger) reason=sessionChanged generation=\(generation) sessionGeneration=\(sessionGeneration) currentSessionGeneration=\(self.presentationSessionGeneration) nowMs=\(self.formatMilliseconds(self.monotonicMilliseconds()))"
                    )
                    self.clearPendingModifierReleaseConfirmationTaskIfCurrent(generation)
                    return
                }
                self.clearPendingModifierReleaseConfirmationTaskIfCurrent(generation)
                self.modifierReleaseState = .confirmed(trigger: trigger, generation: generation)
                self.logInputTrace(
                    "releaseConfirm confirmed trigger=\(trigger) action=finishSelection generation=\(generation) sessionGeneration=\(sessionGeneration) nowMs=\(self.formatMilliseconds(self.monotonicMilliseconds()))"
                )
                self.logSearchTrace(
                    "releaseConfirm trigger=\(trigger) action=confirmed generation=\(generation) sessionGeneration=\(sessionGeneration) \(self.searchTraceStateSummary())"
                )
                self.finishSelection()
                return
            }
        }
    }

    func cancelPendingModifierReleaseConfirmation() {
        guard let pendingModifierReleaseConfirmationTask else { return }
        logInputTrace(
            "releaseConfirm canceled generation=\(modifierReleaseConfirmationGeneration) nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
        )
        pendingModifierReleaseConfirmationTask.cancel()
        modifierReleaseState = .canceled(
            reason: .explicitCancel,
            generation: modifierReleaseConfirmationGeneration
        )
        modifierReleaseConfirmationGeneration += 1
        self.pendingModifierReleaseConfirmationTask = nil
    }

    func clearPendingModifierReleaseConfirmationTaskIfCurrent(_ generation: Int) {
        guard isModifierReleaseConfirmationGenerationCurrent(generation) else { return }
        pendingModifierReleaseConfirmationTask = nil
    }

    func clearHotkeyReplaySuppressionTaskIfCurrent(_ generation: Int) {
        guard isModifierReleaseConfirmationGenerationCurrent(generation) else { return }
        suppressHotkeyReplayTask = nil
    }

    func isModifierReleaseConfirmationGenerationCurrent(_ generation: Int) -> Bool {
        generation == modifierReleaseConfirmationGeneration
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
