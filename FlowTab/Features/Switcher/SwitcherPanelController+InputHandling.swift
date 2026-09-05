import AppKit
import Carbon
import CoreGraphics
import SwiftUI
import FlowTabCore

private enum SearchModeEntryOutcome {
    case entered
    case deferred
    case unavailable
}

extension SwitcherPanelController {
    func installEventMonitors() {
        panelEventMonitoring.installEventMonitors()
    }

    func removeEventMonitors() {
        panelEventMonitoring.removeEventMonitors()
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        if model.isSearchActive {
            return handleSearchModeKeyDown(event)
        }

        switch event.keyCode {
        case 49:
            return true
        case 36, 76:
            if case .unavailable = attemptSearchModeEntry() {
                finishSelection()
            }
            return true
        case 48:
            if activeHotkeySessionKind == .inAppWindowSwitcher {
                return true
            }
            if SwitcherHotkeyPreferencesStore.load().mainKeys.contains(.tab) {
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
            if case .unavailable = attemptSearchModeEntry() {
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
        guard allowsPointerSelection(
            of: .application(appID: appID),
            currentLocation: currentLocation
        ) else { return }
        cancelManualWindowLayerEntryObservation()
        guard model.selectAppFromPointer(appID: appID) else { return }
        updatePanelSize()
        scheduleDelayedWindowLayerEntryIfNeeded()
    }

    func selectSwitcherWindowByPointer(appID: String, windowID: String, currentLocation: CGPoint? = nil) {
        guard allowsPointerSelection(
            of: .window(appID: appID, windowID: windowID),
            currentLocation: currentLocation
        ) else { return }
        cancelManualWindowLayerEntryObservation()
        guard model.selectWindowFromPointer(appID: appID, windowID: windowID) else { return }
        updatePanelSize()
    }

    func selectSwitcherSearchResultByPointer(resultID: String, currentLocation: CGPoint? = nil) {
        guard allowsPointerSelection(
            of: .searchResult(resultID: resultID),
            currentLocation: currentLocation
        ) else { return }
        guard model.selectSearchResult(withID: resultID) else { return }
        updatePanelSize()
    }

    private func allowsPointerSelection(
        of target: SwitcherPointerSelectionTarget,
        currentLocation: CGPoint?
    ) -> Bool {
        let decision = pointerSelectionGate.evaluateSelection(
            of: target,
            at: currentLocation ?? NSEvent.mouseLocation
        )
        guard !decision.allowsSelection else {
            return true
        }
        if let evidence = decision.newBlockedEvidence {
            logInputTrace(
                "pointerSelectionGate outcome=blocked "
                    + "\(evidence.target.diagnosticSummary) "
                    + "preservedSelection="
                    + "\(SwitcherPointerSelectionTarget.escaped(pointerSelectionIdentity(for: target))) "
                    + "generation=\(evidence.generation)"
            )
        }
        return false
    }

    private func pointerSelectionIdentity(
        for target: SwitcherPointerSelectionTarget
    ) -> String {
        switch target {
        case .application:
            return model.session?.selectedApp.id ?? "none"
        case .window:
            return model.session?.selectedWindow?.id ?? "none"
        case .searchResult:
            return model.searchViewState.selectedResult?.id ?? "none"
        }
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
        if case .entered = attemptSearchModeEntry() {
            return true
        }
        return false
    }

    private func attemptSearchModeEntry() -> SearchModeEntryOutcome {
        logSearchTrace("enterSearchMode action=attempt \(searchTraceStateSummary())")
        guard searchFeatureEnabled else {
            logSearchTrace("enterSearchMode action=ignored reason=featureDisabled \(searchTraceStateSummary())")
            return .unavailable
        }
        guard model.enterSearchMode() else {
            if model.pendingSearchActivationAfterFreshnessBarrier {
                cancelPendingModifierReleaseConfirmation()
                clearDelayedWindowLayerEntryState()
                cancelManualWindowLayerEntryObservation()
                logSearchTrace(
                    "enterSearchMode action=deferred reason=awaitingCommittedSearchIndex \(searchTraceStateSummary())"
                )
                return .deferred
            }
            logSearchTrace("enterSearchMode action=ignored reason=modelRejected \(searchTraceStateSummary())")
            return .unavailable
        }
        cancelPendingModifierReleaseConfirmation()
        resetPointerSelectionGate()
        syncPanelAccessibilityAnchors()
        updatePanelSize()
        RuntimeLog.info(.session, "enter search mode")
        logSearchTrace("enterSearchMode action=entered \(searchTraceStateSummary())")
        return .entered
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
        syncPanelAccessibilityAnchors()
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
                syncPanelAccessibilityAnchors()
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
        if isTerminateSelectedAppShortcut(event) {
            terminateSelectedApp()
            return
        }
        let matchingSessionKinds =
            hotkeySessionKindsMatchingHoldModifierFlagsEvent(event)
        guard !matchingSessionKinds.isEmpty else { return }
        for sessionKind in matchingSessionKinds {
            updateHotkeyHoldSetPressedEvidence(
                isHotkeyKeySetPressedInHardwareState(
                    hotkeyHoldKeys(for: sessionKind),
                    eventModifierFlags: event.modifierFlags
                ),
                for: sessionKind
            )
        }
        if pendingFocusedWindowSessionPresentation != nil,
           matchingSessionKinds.contains(.inAppWindowSwitcher),
           !isHotkeyHoldSetPressed(for: .inAppWindowSwitcher)
        {
            cancelPendingFocusedWindowSessionPresentation(
                reason: "modifierReleased"
            )
            return
        }
        guard isPanelPresented,
              let activeHotkeySessionKind,
              matchingSessionKinds.contains(activeHotkeySessionKind)
        else {
            modifierReleaseObservationOwner.observeInputTransition()
            return
        }
        guard !hasActiveOrPendingSearchInteraction else { return }
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
        guard hasActiveOrPendingSearchInteraction else { return }
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
        guard !shouldDeferPanelVisibilityRecoveryInterruption(
            trigger: "applicationDidResignActive"
        ) else { return }
        logSearchTrace("systemInterruption trigger=applicationDidResignActive \(searchTraceStateSummary())")
        handleRecoverableSystemInterruption(trigger: "applicationDidResignActive")
    }

    func handleActiveSpaceDidChange() {
        guard hasActivePresentationSession else {
            model.signalSpaceTopologyChanged()
            return
        }
        beginActiveSpaceTransitionObservation(
            trigger: "activeSpaceDidChange"
        )
    }

    func handlePanelOcclusionStateDidChange() {
        guard isPanelPresented else { return }
        _ = observeInitialPresentationVisibility(
            source: .panelOcclusionChanged
        )
        observePanelVisibilityRecovery(
            source: .panelOcclusionChanged
        )
        observeTerminateInterruptionProtectionPresentationUpdate(
            source: .panelVisibilityReadback
        )
        if resolvedPanelOcclusionState.contains(.visible) {
            return
        }
        if hasPendingPanelVisibilityRecoveryObservation {
            logSearchTrace(
                "systemInterruption trigger=panelOccluded action=deferred reason=visibilityRecoveryObserved \(searchTraceStateSummary())"
            )
            return
        }
        guard !shouldDeferInitialPanelOcclusionInterruption(trigger: "panelOccluded") else {
            return
        }
        logSearchTrace("systemInterruption trigger=panelOccluded \(searchTraceStateSummary())")
        handleRecoverableSystemInterruption(trigger: "panelOccluded")
    }

    func handlePanelDidBecomeKey() {
        guard isPanelPresented else { return }
        _ = observeInitialPresentationVisibility(
            source: .panelBecameKey
        )
        observePanelVisibilityRecovery(
            source: .panelBecameKey
        )
        observeTerminateInterruptionProtectionPresentationUpdate(
            source: .panelVisibilityReadback
        )
    }

    func handlePanelDidExpose() {
        guard isPanelPresented else { return }
        _ = observeInitialPresentationVisibility(
            source: .panelExposed
        )
        observePanelVisibilityRecovery(
            source: .panelExposed
        )
        observeTerminateInterruptionProtectionPresentationUpdate(
            source: .panelVisibilityReadback
        )
    }

    func handlePanelDidResignKey() {
        guard isPanelPresented else { return }
        guard !isAppCurrentlyActive else { return }
        guard !shouldDeferPanelVisibilityRecoveryInterruption(
            trigger: "panelDidResignKey"
        ) else { return }
        logSearchTrace("systemInterruption trigger=panelDidResignKey \(searchTraceStateSummary())")
        handleRecoverableSystemInterruption(trigger: "panelDidResignKey")
    }

    func handleWorkspaceApplicationTerminated(appID: String, pid: pid_t) {
        let protectionBaseline =
            captureTerminateInterruptionProtectionBaseline(appID: appID)
        let refreshed = model.handleApplicationTerminated(appID: appID, pid: pid)
        observeWorkspaceTerminationForInterruptionProtection(
            appID: appID,
            pid: pid,
            baseline: protectionBaseline,
            refreshedSession: refreshed
        )
    }

    @discardableResult
    func handleAppSwitcherProjectionDidUpdate() -> Bool {
        observeActiveSpaceTransitionProjectionUpdate()
        guard isPanelPresented else {
            observeTerminateInterruptionProtectionProjectionUpdate()
            return false
        }
        let updated = model.handleAppSwitcherProjectionDidUpdate()
        observeTerminateInterruptionProtectionProjectionUpdate()
        guard updated else { return false }
        observeDelayedWindowLayerProjectionUpdate(
            source: .appSwitcherProjectionUpdated
        )
        scheduleDelayedWindowLayerEntryIfNeeded(preservingDeadline: true)
        return true
    }

    @discardableResult
    func handleCurrentAppWindowProjectionDidUpdate(
        appID: String?,
        evidence: RuntimeCurrentAppWindowProjectionUpdateEvidence? = nil
    ) -> Bool {
        if resolvePendingFocusedWindowSessionPresentation(
            appID: appID,
            evidence: evidence
        ) {
            return true
        }
        guard isPanelPresented else { return false }
        let manualEntrySettled =
            observeManualWindowLayerProjectionUpdate(
                appID: appID,
                evidence: evidence
            )
        let projectionApplied =
            model.handleCurrentAppWindowProjectionDidUpdate(
                appID: appID
            )
        guard manualEntrySettled || projectionApplied else {
            return false
        }
        observeDelayedWindowLayerProjectionUpdate(
            source: .currentAppWindowProjectionUpdated,
            appID: appID
        )
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
        let shouldKeepSessionVisible = hasActiveOrPendingSearchInteraction
            || isHotkeyHoldSetPressed(for: sessionKind)
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
            cancelSessionOnFailure: true
        )
    }

    func handleProtectedTerminateSystemInterruption(trigger: String) -> Bool {
        guard shouldProtectTerminateSystemInterruption() else { return false }
        logSearchTrace(
            "systemInterruption trigger=\(trigger) action=recover reason=terminateInFlight \(searchTraceStateSummary())"
        )
        if trigger != "activeSpaceDidChange" {
            activateApplicationForPanelPresentationIfNeeded()
        }
        schedulePanelVisibilityRecovery(
            trigger: "\(trigger)_terminate",
            cancelSessionOnFailure: false,
            activateApplicationIfNeeded: trigger != "activeSpaceDidChange"
        )
        observeProtectedTerminateSystemInterruption()
        return true
    }

    func cancelSelectionForSystemInterruption(trigger: String) {
        guard isPanelPresented || hasActivePresentationSession else { return }
        logSearchTrace("cancelSelectionForSystemInterruption trigger=\(trigger) action=begin \(searchTraceStateSummary())")
        logInputTrace(
            "\(trigger) action=cancelSelection nowMs=\(formatMilliseconds(monotonicMilliseconds()))"
        )
        cancelSelection(trigger: "system_interruption:\(trigger)")
        logSearchTrace("cancelSelectionForSystemInterruption trigger=\(trigger) action=finished \(searchTraceStateSummary())")
    }

}
