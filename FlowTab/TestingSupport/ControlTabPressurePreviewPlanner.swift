#if FLOWTAB_TESTING
import AppKit
import FlowTabCore

@MainActor
struct ControlTabPressurePreviewPlanner: SwitcherPreviewPlanning {
    let base: any SwitcherPreviewPlanning
    let diagnostics: ControlTabPressureModelDiagnostics

    func plan(context: SwitcherPreviewPlanningContext, visibleRange: Range<Int>?) -> SwitcherPreviewPlan? {
        let token = diagnostics.measurementSink?.beginComponent(.previewPlanning, parent: .inputRouting,
            workUnits: context.session?.selectedApp.windows.count ?? 0)
        defer { diagnostics.measurementSink?.endComponent(token) }
        let plan = base.plan(context: observingCapture(in: context), visibleRange: visibleRange)
        if let plan, plan.pendingCaptures.isEmpty {
            diagnostics.recordPreviewReuse(workUnits: plan.items.count)
        }
        return plan
    }

    func resolve(context: SwitcherPreviewPlanningContext, appID: String,
                 window: WindowCandidate, pinForSession: Bool) -> ResolvedPreviewData {
        base.resolve(context: observingCapture(in: context), appID: appID,
                     window: window, pinForSession: pinForSession)
    }

    private func observingCapture(in context: SwitcherPreviewPlanningContext) -> SwitcherPreviewPlanningContext {
        guard let capture = context.previewCaptureOverride else { return context }
        return SwitcherPreviewPlanningContext(session: context.session, overlayStyle: context.overlayStyle,
            titleBarStyleInferenceEnabled: context.titleBarStyleInferenceEnabled,
            previewCaptureOverride: { id, pid, title, inference in
                let token = diagnostics.measurementSink?.beginComponent(.previewCapture, parent: .previewPlanning, workUnits: 1)
                defer { diagnostics.measurementSink?.endComponent(token) }
                return capture(id, pid, title, inference)
            })
    }
}
#endif
