#if FLOWTAB_TESTING
import AppKit

@MainActor
final class ControlTabPressurePanelAssembly {
    let context: ControlTabPressurePanelMeasurement
    private let restoreOperations: () -> Void
    private let visibility: ControlTabPressurePanelVisibilityObservation

    init(controller: SwitcherPanelController) {
        let context = ControlTabPressurePanelMeasurement(controller: controller)
        self.context = context
        let presentation = controller.presentationCoordinator
        let geometry = controller.panelGeometry
        let window = controller.panelWindowOperations
        let accessibility = controller.panelAccessibility
        let events = controller.panelEventMonitoring
        let delays = controller.panelDelayedOperations
        let shell = controller.reusablePanelShell
        controller.presentationCoordinator = ControlTabPressurePanelPresentation(base: presentation, context: context)
        controller.panelGeometry = ControlTabPressurePanelGeometry(base: geometry, context: context)
        controller.panelWindowOperations = ControlTabPressurePanelWindow(base: window, context: context)
        controller.panelAccessibility = ControlTabPressurePanelAccessibility(base: accessibility, context: context)
        controller.panelEventMonitoring = ControlTabPressurePanelEvents(base: events, context: context)
        controller.panelDelayedOperations = ControlTabPressurePanelDelays(base: delays, context: context)
        controller.reusablePanelShell = ControlTabPressurePanelShell(base: shell, context: context)
        visibility = ControlTabPressurePanelVisibilityObservation(controller: controller)
        restoreOperations = { [weak controller] in
            guard let controller else { return }
            controller.presentationCoordinator = presentation
            controller.panelGeometry = geometry
            controller.panelWindowOperations = window
            controller.panelAccessibility = accessibility
            controller.panelEventMonitoring = events
            controller.panelDelayedOperations = delays
            controller.reusablePanelShell = shell
        }
    }

    func cancel() {
        guard context.isActive else { return }
        context.controller?.reusablePanelShell.cancel()
        context.isActive = false
        visibility.cancel()
        restoreOperations()
    }

    deinit { MainActor.assumeIsolated { cancel() } }
}

@MainActor
final class ControlTabPressurePanelMeasurement {
    weak var controller: SwitcherPanelController?
    let diagnostics: ControlTabPressureModelDiagnostics
    var presentationDepth = 0
    var isActive = true
    init(controller: SwitcherPanelController) {
        self.controller = controller
        self.diagnostics = controller.model.controlTabPressureDiagnostics
    }
    var isPresenting: Bool { presentationDepth > 0 }
    func measure<T>(_ component: SwitcherInteractionComponent,
                    parent: SwitcherInteractionComponent? = .appKitPanelPresentation,
                    workUnits: Int = 1, operation: () -> T) -> T {
        let sink = isActive ? diagnostics.measurementSink : nil
        let token = sink?.beginComponent(component, parent: parent, workUnits: workUnits)
        defer { sink?.endComponent(token) }
        return operation()
    }
}
#endif
