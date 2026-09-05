import AppKit
import FlowTabCore

extension SwitcherPanelPresentationCoordinator {
    func presentStartedHotkeySession(
        kind: HotkeySessionKind,
        trigger: String,
        logKind: String,
        showStartMs: Double,
        startLogMessage: String
    ) {

        let sessionReadyMs = controller.monotonicMilliseconds()
        controller.beginPresentationSession(kind: kind, trigger: trigger)
        let preparesStandardAppRevealBeforeLayout =
            kind == .globalAppSwitcher
                && !controller.model.isSearchActive
        if preparesStandardAppRevealBeforeLayout {
            controller.prepareInitialPanelReveal(kind: kind)
        }
        RuntimeLog.info(.session, startLogMessage)

        let targetScreen = controller.resolveActivePresentationScreen()
        let screenReadyMs = controller.monotonicMilliseconds()
        controller.activePresentationScreen = targetScreen
        controller.updatePanelSize(for: targetScreen)
        controller.activePresentationInitialContentSize = controller.panel.contentRect(
            forFrameRect: controller.panel.frame
        ).size
        let sizeReadyMs = controller.monotonicMilliseconds()
        controller.centerPanelOnActiveScreen(preferredScreen: targetScreen)
        let centerReadyMs = controller.monotonicMilliseconds()
        controller.syncPanelAccessibilityAnchors()
        let accessibilityReadyMs = controller.monotonicMilliseconds()
        controller.updatePanelPresentationLevel(trigger: trigger)
        if !preparesStandardAppRevealBeforeLayout {
            controller.prepareInitialPanelReveal(kind: kind)
        }
        let levelReadyMs = controller.monotonicMilliseconds()

        let initialVisibilityTrackingStartMs = controller.monotonicMilliseconds()
        let initialVisibilityGeneration =
            controller.panelDelayedOperations.beginInitialVisibilityTracking(trigger: trigger)
        let initialVisibilityTrackingMs =
            controller.monotonicMilliseconds() - initialVisibilityTrackingStartMs

        if controller.model.isSearchActive {
            controller.activateApplicationForPanelPresentationIfNeeded()
        }

        let panelWasAlreadyOrdered = controller.panel.isVisible
        var stageStartMs = controller.monotonicMilliseconds()
        controller.panelWindowOperations.makeKey(wasAlreadyOrdered: panelWasAlreadyOrdered)
        let firstMakeKeyMs = controller.monotonicMilliseconds() - stageStartMs
        stageStartMs = controller.monotonicMilliseconds()
        controller.panelWindowOperations.orderFront()
        let firstOrderRegardlessMs =
            controller.monotonicMilliseconds() - stageStartMs

        controller.requestInitialAppContentRenderPassIfNeeded()

        stageStartMs = controller.monotonicMilliseconds()
        controller.hideNonPanelWindowsIfNeeded()
        let hideMs = controller.monotonicMilliseconds() - stageStartMs

        let secondMakeKeyMs = 0.0
        let secondOrderRegardlessMs = 0.0

        stageStartMs = controller.monotonicMilliseconds()
        controller.panelDelayedOperations.scheduleInitialVisibilityRecovery(
            trigger: trigger,
            initialVisibilityGeneration: initialVisibilityGeneration
        )
        let presentationReadbackMs =
            controller.monotonicMilliseconds() - stageStartMs

        stageStartMs = controller.monotonicMilliseconds()
        controller.installEventMonitors()
        let monitorMs = controller.monotonicMilliseconds() - stageStartMs

        stageStartMs = controller.monotonicMilliseconds()
        if !controller.model.isSearchActive && !controller.model.isWindowOnlyOverlay {
            _ = controller.model.scheduleSelectedAppWindowProjectionIfNeeded()
        }
        controller.scheduleDelayedWindowLayerEntryIfNeeded(
            prewarmsPreviews: false
        )
        let presentedMs = controller.monotonicMilliseconds()
        let autoEnterMs = presentedMs - stageStartMs
        controller.logPanelPresentationBreakdown(
            kind: logKind,
            showStartMs: showStartMs,
            sessionReadyMs: sessionReadyMs,
            screenReadyMs: screenReadyMs,
            sizeReadyMs: sizeReadyMs,
            centerReadyMs: centerReadyMs,
            accessibilityReadyMs: accessibilityReadyMs,
            levelReadyMs: levelReadyMs,
            hideMs: hideMs,
            initialVisibilityTrackingMs: initialVisibilityTrackingMs,
            monitorMs: monitorMs,
            firstMakeKeyMs: firstMakeKeyMs,
            firstOrderRegardlessMs: firstOrderRegardlessMs,
            secondMakeKeyMs: secondMakeKeyMs,
            secondOrderRegardlessMs: secondOrderRegardlessMs,
            presentationReadbackMs: presentationReadbackMs,
            autoEnterMs: autoEnterMs
        )
        controller.logInputTrace(
            "show kind=\(logKind) result=presented sessionMs=\(controller.formatMilliseconds(sessionReadyMs - showStartMs)) totalMs=\(controller.formatMilliseconds(presentedMs - showStartMs)) \(controller.searchTraceStateSummary())"
        )
        controller.schedulePanelVisibilityProbe(
            kind: logKind,
            showStartMs: showStartMs,
            presentedMs: presentedMs
        )
    }
}
