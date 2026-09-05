import AppKit
import FlowTabCore

extension SwitcherPanelPresentationCoordinator {
    func endPresentationSession() {
        guard controller.isPanelPresented || controller.hasActivePresentationSession else { return }
        let reusableShellContentSize = controller.activePresentationInitialContentSize
        controller.panelDelayedOperations.cancelPresentationWork()
        controller.removeEventMonitors()
        controller.cancelInitialPanelReveal()
        controller.panelWindowOperations.hidePanel()
        controller.panel.updateSwitcherAccessibilityApps([], tileSize: 1, spacing: 0, appStripHeaderOffset: 0)
        controller.panel.level = SwitcherPanelWindowConfiguration.level
        controller.panel.collectionBehavior = SwitcherPanelWindowConfiguration.presentationCollectionBehavior()
        controller.activeHotkeySessionKind = nil
        controller.activePresentationInitialContentSize = nil
        controller.activePresentationScreen = nil
        controller.lastSearchLayoutSizingLogSummary = nil
        controller.panelVisibilityRecoveryState = .idle
        if controller.panelVisibilityOverride != nil {
            controller.panelVisibilityOverride = false
        }
        controller.panel.orderFrontRegardless()
        controller.reusablePanelShell.prepare(contentSize: reusableShellContentSize, completion: { _ in })
    }

    func beginPresentationSession(kind: HotkeySessionKind, trigger: String) {
        controller.reusablePanelShell.cancel()
        controller.cancelPanelVisibilityProbe()
        controller.presentationSessionGeneration += 1
        controller.activeHotkeySessionKind = kind
        controller.activePresentationInitialContentSize = nil
        controller.panelPresentationActive = true
        controller.panel.ignoresMouseEvents = false
        controller.beginInitialVisibleFrameTracking()
        controller.resetPointerSelectionGate()
        controller.logInputTrace(
            "presentationSession trigger=\(trigger) action=begin kind=\(kind) generation=\(controller.presentationSessionGeneration)"
        )
    }

    func invalidatePresentationSessionGeneration(trigger: String) {
        controller.cancelPanelVisibilityProbe()
        controller.presentationSessionGeneration += 1
        controller.clearInitialVisibleFrameTracking()
        controller.logInputTrace(
            "presentationSession trigger=\(trigger) action=invalidate generation=\(controller.presentationSessionGeneration)"
        )
    }
}
