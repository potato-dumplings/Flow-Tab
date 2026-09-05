#if FLOWTAB_TESTING
import AppKit

@MainActor
struct ControlTabPressurePanelWindow: SwitcherPanelWindowOperating {
    let base: any SwitcherPanelWindowOperating
    let context: ControlTabPressurePanelMeasurement
    func updatePanelPresentationLevel(trigger: String, behaviorMode: SwitcherPanelWindowConfiguration.PresentationBehaviorMode) {
        context.measure(.panelLevel) { base.updatePanelPresentationLevel(trigger: trigger, behaviorMode: behaviorMode) }
    }
    func hideNonPanelWindowsIfNeeded() { context.measure(.panelHide) { base.hideNonPanelWindowsIfNeeded() } }
    func hideNonPanelWindows() { base.hideNonPanelWindows() }
    func makeKey(wasAlreadyOrdered: Bool) { context.measure(.makeKey) { base.makeKey(wasAlreadyOrdered: wasAlreadyOrdered) } }
    func orderFront() { context.measure(.orderFront) { base.orderFront() } }
    func hidePanel() {
        base.hidePanel()
        context.controller?.recordPanelHiddenMilestone()
    }
}

@MainActor
struct ControlTabPressurePanelAccessibility: SwitcherPanelAccessibilityOperating {
    let base: any SwitcherPanelAccessibilityOperating
    let context: ControlTabPressurePanelMeasurement
    func syncPanelAccessibilityAnchors() {
        context.measure(.panelAccessibility) { base.syncPanelAccessibilityAnchors() }
    }
}

@MainActor
final class ControlTabPressurePanelEvents: SwitcherPanelEventMonitoring {
    let base: any SwitcherPanelEventMonitoring
    let context: ControlTabPressurePanelMeasurement
    init(base: any SwitcherPanelEventMonitoring, context: ControlTabPressurePanelMeasurement) {
        self.base = base; self.context = context
    }
    func installEventMonitors() { context.measure(.eventMonitorInstall) { base.installEventMonitors() } }
    func removeEventMonitors() { context.measure(.observerRemoval, parent: .panelTeardown) { base.removeEventMonitors() } }
}

@MainActor
final class ControlTabPressurePanelShell: SwitcherReusablePanelShellPreparing {
    let base: any SwitcherReusablePanelShellPreparing
    let context: ControlTabPressurePanelMeasurement
    init(base: any SwitcherReusablePanelShellPreparing, context: ControlTabPressurePanelMeasurement) {
        self.base = base; self.context = context
    }
    func prepare(contentSize: NSSize?, completion: @escaping (SwitcherReusablePanelShellResult) -> Void) {
        let controller = context.controller
        controller?.reusableShellPreparationGeneration &+= 1
        let generation = controller?.reusableShellPreparationGeneration
        let sink = context.diagnostics.measurementSink
        let token = sink?.beginComponent(.reusableShellPrepare, parent: .panelTeardown, workUnits: 1)
        base.prepare(contentSize: contentSize) { [context, weak controller] result in
            let outcome: SwitcherInteractionSpanOutcome
            switch result {
            case .prepared: outcome = .completed
            case .notRequired: outcome = .notRequired
            case .superseded: outcome = .cancelled
            }
            sink?.endComponent(token, outcome: outcome)
            if context.isActive, let controller, let generation,
               controller.reusableShellPreparationGeneration == generation {
                controller.completedReusableShellPreparationGeneration = generation
                if result != .superseded, !controller.panelPresentationActive {
                    controller.recordCleanupCompleteMilestone()
                }
            }
            completion(result)
        }
    }
    func cancel() { base.cancel() }
}
#endif
