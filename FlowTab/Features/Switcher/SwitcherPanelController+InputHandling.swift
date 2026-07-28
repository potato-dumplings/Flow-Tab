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
        clearDelayedWindowLayerEntryState()
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
                cancelSelection(trigger: "escape_key")
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

    func commitSwitcherAppByPointerClick(appID: String) {
        guard isPanelPresented else { return }
        guard model.selectAppFromPointer(appID: appID) else { return }
        logInputTrace(
            "pointerClickCommit target=app appID=\(appID) nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
        )
        finishSelection()
    }

    func commitSwitcherWindowByPointerClick(appID: String, windowID: String) {
        guard isPanelPresented else { return }
        guard model.selectWindowFromPointer(appID: appID, windowID: windowID) else { return }
        logInputTrace(
            "pointerClickCommit target=window appID=\(appID) windowID=\(windowID) nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
        )
        finishSelection()
    }

    func commitSwitcherSearchResultByPointerClick(resultID: String) {
        guard isPanelPresented else { return }
        guard model.isSearchActive else { return }
        _ = model.selectSearchResult(withID: resultID)
        guard model.applySelectedSearchResultToSession() else {
            NSSound.beep()
            return
        }
        logInputTrace(
            "pointerClickCommit target=searchResult resultID=\(resultID) nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
        )
        finishSelection()
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

    @discardableResult
    func handleCommittedSearchIndexDidUpdate() -> Bool {
        logSearchTrace("committedSearchIndexDidUpdate action=attempt \(searchTraceStateSummary())")
        guard model.handleCommittedSearchIndexDidUpdate() else {
            logSearchTrace("committedSearchIndexDidUpdate action=ignored reason=modelRejected \(searchTraceStateSummary())")
            return false
        }
        cancelPendingModifierReleaseConfirmation()
        resetPointerSelectionGate()
        if isPanelPresented {
            updatePanelSize()
        } else {
            let showStartMs = monotonicMilliseconds()
            presentStartedHotkeySession(
                kind: .globalAppSwitcher,
                trigger: "search_freshness_ready",
                logKind: "search",
                showStartMs: showStartMs,
                startLogMessage: "start search after committed index \(model.debugSelectionSummary())"
            )
        }
        RuntimeLog.info(.session, "enter search mode")
        logSearchTrace("committedSearchIndexDidUpdate action=entered \(searchTraceStateSummary())")
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
        cancelSelection(trigger: "global_mouse_down_outside_panel")
    }

    func handleGlobalKeyDown(_ event: NSEvent) {
        guard isPanelPresented else { return }
        guard !isAppCurrentlyActive else { return }
        guard event.keyCode == 53 else { return }
        logInputTrace(
            "globalEscWhileAppInactive action=cancelSelection nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
        )
        cancelSelection(trigger: "global_escape_while_inactive")
    }

    func handleApplicationDidResignActive() {
        guard isPanelPresented else { return }
        logSearchTrace("systemInterruption trigger=applicationDidResignActive \(searchTraceStateSummary())")
        handleRecoverableSystemInterruption(trigger: "applicationDidResignActive")
    }

    func handleActiveSpaceDidChange() {
        model.signalSpaceTopologyChanged()
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
            extendExisting: true
        )
        beginIgnoringActiveSpaceChanges(trigger: "terminate_refresh")
    }

    @discardableResult
    func handleAppSwitcherProjectionDidUpdate() -> Bool {
        guard isPanelPresented else { return false }
        guard model.handleAppSwitcherProjectionDidUpdate() else { return false }
        resetPointerSelectionGate()
        updatePanelSize()
        scheduleDelayedWindowLayerEntryIfNeeded(preservingDeadline: true)
        return true
    }

    @discardableResult
    func handleCurrentAppWindowProjectionDidUpdate(appID: String?) -> Bool {
        guard isPanelPresented else { return false }
        guard model.handleCurrentAppWindowProjectionDidUpdate(appID: appID) else { return false }
        resetPointerSelectionGate()
        updatePanelSize()
        scheduleDelayedWindowLayerEntryIfNeeded(preservingDeadline: true)
        return true
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
        cancelSelection(trigger: "system_interruption:\(trigger)")
        logSearchTrace("cancelSelectionForSystemInterruption trigger=\(trigger) action=finished \(searchTraceStateSummary())")
        if let sessionKind {
            beginHotkeyReplaySuppressionUntilRelease(for: sessionKind, trigger: trigger)
        } else {
            beginHotkeyReplaySuppressionUntilReleaseForKnownSessionKinds(trigger: trigger)
        }
    }

}
