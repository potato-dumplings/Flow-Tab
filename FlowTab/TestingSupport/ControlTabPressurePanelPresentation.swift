#if FLOWTAB_TESTING
import AppKit
import FlowTabCore

@MainActor
final class ControlTabPressurePanelPresentation: SwitcherPanelPresenting {
    let base: any SwitcherPanelPresenting
    let context: ControlTabPressurePanelMeasurement

    init(base: any SwitcherPanelPresenting, context: ControlTabPressurePanelMeasurement) {
        self.base = base
        self.context = context
    }

    func showInAppWindowSwitcher(direction: CycleDirection, initialKeyInput: KeyInput?) {
        context.controller?.beginFocusedWindowSessionDiagnostic(
            showStartMilliseconds: LiveSwitcherModel.monotonicMilliseconds())
        base.showInAppWindowSwitcher(direction: direction, initialKeyInput: initialKeyInput)
        context.controller?.recordFocusedWindowSessionStartDiagnostic()
    }
    func resolvePendingFocusedWindowSessionPresentation(appID: String?, evidence: RuntimeCurrentAppWindowProjectionUpdateEvidence?) -> Bool {
        base.resolvePendingFocusedWindowSessionPresentation(appID: appID, evidence: evidence)
    }
    func cancelPendingFocusedWindowSessionPresentation(reason: String, resetsModel: Bool) {
        guard let controller = context.controller,
              controller.pendingFocusedWindowSessionPresentation != nil else {
            base.cancelPendingFocusedWindowSessionPresentation(reason: reason, resetsModel: resetsModel)
            return
        }
        context.measure(.delayedTaskCancellation, parent: .panelTeardown) {
            base.cancelPendingFocusedWindowSessionPresentation(reason: reason, resetsModel: resetsModel)
        }
        context.diagnostics.finishReconciliation(outcome: .cancelled)
        if !controller.isPanelPresented, !controller.hasActivePresentationSession {
            for component in [SwitcherInteractionComponent.panelTeardown, .observerRemoval, .reusableShellPrepare] {
                context.diagnostics.measurementSink?.recordUnexecutedComponent(component, outcome: .notRequired)
            }
            controller.reusableShellPreparationGeneration &+= 1
            controller.completedReusableShellPreparationGeneration = controller.reusableShellPreparationGeneration
            controller.recordPanelHiddenMilestone()
            controller.recordCleanupCompleteMilestone()
        }
    }
    func presentStartedHotkeySession(kind: HotkeySessionKind, trigger: String, logKind: String,
                                    showStartMs: Double, startLogMessage: String) {
        if kind == .inAppWindowSwitcher { context.controller?.recordFocusedWindowSessionStartDiagnostic() }
        context.presentationDepth += 1
        defer { context.presentationDepth -= 1 }
        context.measure(.appKitPanelPresentation, parent: .inputRouting,
                        workUnits: context.controller?.model.previewWindowCount ?? 0) {
            base.presentStartedHotkeySession(kind: kind, trigger: trigger, logKind: logKind,
                showStartMs: showStartMs, startLogMessage: startLogMessage)
        }
        if kind == .inAppWindowSwitcher, let controller = context.controller,
           let diagnostic = controller.lastPanelPresentationBreakdownDiagnostic {
            controller.recordFocusedWindowPanelPresentation(diagnostic,
                presentedAtMilliseconds: showStartMs + diagnostic.totalMs)
            controller.deliverPressureRenderMilestoneIfVisible()
        }
    }
    func endPresentationSession() {
        guard let controller = context.controller,
              controller.isPanelPresented || controller.hasActivePresentationSession else {
            base.endPresentationSession()
            return
        }
        context.measure(.panelTeardown, parent: nil) { base.endPresentationSession() }
    }
    func beginPresentationSession(kind: HotkeySessionKind, trigger: String) {
        base.beginPresentationSession(kind: kind, trigger: trigger)
        context.diagnostics.presentationGeneration = context.controller?.presentationSessionGeneration ?? 0
    }
    func invalidatePresentationSessionGeneration(trigger: String) {
        base.invalidatePresentationSessionGeneration(trigger: trigger)
        context.diagnostics.presentationGeneration = context.controller?.presentationSessionGeneration ?? 0
    }
}
#endif
