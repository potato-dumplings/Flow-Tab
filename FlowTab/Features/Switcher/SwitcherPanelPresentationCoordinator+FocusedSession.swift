import AppKit
import FlowTabCore

extension SwitcherPanelPresentationCoordinator {
    func showInAppWindowSwitcher(
        direction: CycleDirection,
        initialKeyInput: KeyInput? = nil
    ) {
        let showStartMs = controller.monotonicMilliseconds()
        switch controller.model.startFocusedAppWindowSession(
            triggerDirection: direction
        ) {
        case .ready:
            presentReadyInAppWindowSwitcher(
                direction: direction,
                initialKeyInput: initialKeyInput,
                showStartMilliseconds: showStartMs,
                trigger: "in_app_show"
            )
        case .awaitingFreshProjection(let request):
            beginPendingFocusedWindowSessionPresentation(
                request: request,
                initialKeyInput: initialKeyInput,
                showStartMilliseconds: showStartMs
            )
            let failedMs = controller.monotonicMilliseconds() - showStartMs
            controller.logInputTrace(
                "show kind=inApp result=awaitingFreshProjection durationMs=\(controller.formatMilliseconds(failedMs)) appID=\(request.appID) pid=\(request.pid)"
            )
        case .unavailable:
            let failedMs = controller.monotonicMilliseconds() - showStartMs
            controller.logInputTrace(
                "show kind=inApp result=failed durationMs=\(controller.formatMilliseconds(failedMs))"
            )
            RuntimeLog.info(
                .session,
                "start in-app window switch failed: no windows"
            )
            NSSound.beep()
        }
    }

    func presentReadyInAppWindowSwitcher(
        direction: CycleDirection,
        initialKeyInput: KeyInput?,
        showStartMilliseconds: Double,
        trigger: String
    ) {
        if let initialKeyInput {
            controller.model.handle(initialKeyInput)
            controller.logInputTrace(
                "show kind=inApp action=initialAdvance key=\(initialKeyInput.debugName) nowMs=\(controller.formatMilliseconds(controller.monotonicMilliseconds()))"
            )
        }
        _ = controller.panelDelayedOperations.prewarmWindowOnlySessionPreviews()
        controller.presentStartedHotkeySession(
            kind: .inAppWindowSwitcher,
            trigger: trigger,
            logKind: "inApp",
            showStartMs: showStartMilliseconds,
            startLogMessage: "start in-app direction=\(direction.debugName) \(controller.model.debugSelectionSummary())"
        )
    }

    func beginPendingFocusedWindowSessionPresentation(
        request: PendingFocusedAppWindowSession,
        initialKeyInput: KeyInput?,
        showStartMilliseconds: Double
    ) {
        controller.cancelPendingFocusedWindowSessionPresentation(
            reason: "replaced",
            resetsModel: false
        )
        let observationGeneration =
            controller.focusedWindowSessionFreshnessObservationOwner.start {
                [weak self] expiredGeneration in
                self?.handleFocusedWindowSessionFreshnessWatchdog(
                    generation: expiredGeneration
                )
            }
        controller.pendingFocusedWindowSessionPresentation =
            SwitcherPanelController.PendingFocusedWindowSessionPresentation(
                request: request,
                initialKeyInput: initialKeyInput,
                showStartMilliseconds: showStartMilliseconds,
                observationGeneration: observationGeneration
            )
    }

    func resolvePendingFocusedWindowSessionPresentation(
        appID: String?,
        evidence: RuntimeCurrentAppWindowProjectionUpdateEvidence?
    ) -> Bool {
        guard let pending = controller.pendingFocusedWindowSessionPresentation,
              appID == pending.request.appID,
              let evidence,
              evidence.appID == pending.request.appID,
              evidence.processIdentifier == pending.request.pid,
              evidence.isCompleteForScope,
              controller.isHotkeyHoldSetPressed(for: .inAppWindowSwitcher)
        else {
            return false
        }
        guard controller.model.completePendingFocusedAppWindowSession(
            pending.request
        ) else {
            return false
        }
        guard controller.focusedWindowSessionFreshnessObservationOwner.resolve(
            generation: pending.observationGeneration
        ) else {
            controller.model.resetSessionState()
            return false
        }
        controller.pendingFocusedWindowSessionPresentation = nil
        presentReadyInAppWindowSwitcher(
            direction: pending.request.triggerDirection,
            initialKeyInput: pending.initialKeyInput,
            showStartMilliseconds: pending.showStartMilliseconds,
            trigger: "in_app_fresh_projection_ready"
        )
        return true
    }

    func cancelPendingFocusedWindowSessionPresentation(
        reason: String,
        resetsModel: Bool = true
    ) {
        guard controller.pendingFocusedWindowSessionPresentation != nil else {
            return
        }
        controller.focusedWindowSessionFreshnessObservationOwner.cancel()
        controller.pendingFocusedWindowSessionPresentation = nil
        if resetsModel {
            controller.model.resetSessionState()
        }
        controller.logInputTrace(
            "show kind=inApp result=cancelled reason=\(reason)"
        )
    }

    func handleFocusedWindowSessionFreshnessWatchdog(
        generation: Int
    ) {
        guard let pending = controller.pendingFocusedWindowSessionPresentation,
              pending.observationGeneration == generation
        else {
            return
        }
        controller.pendingFocusedWindowSessionPresentation = nil
        controller.model.resetSessionState()
        controller.logInputTrace(
            "show kind=inApp result=freshnessWatchdogExpired generation=\(generation) appID=\(pending.request.appID) pid=\(pending.request.pid) panelVisible=0"
        )
    }
}
