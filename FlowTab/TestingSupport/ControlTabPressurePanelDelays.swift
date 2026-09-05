#if FLOWTAB_TESTING
import AppKit

@MainActor
final class ControlTabPressurePanelDelays: SwitcherPanelDelayedOperating {
    let base: any SwitcherPanelDelayedOperating
    let context: ControlTabPressurePanelMeasurement
    init(base: any SwitcherPanelDelayedOperating, context: ControlTabPressurePanelMeasurement) {
        self.base = base; self.context = context
    }
    func scheduleDelayedWindowLayerEntryIfNeeded(preservingDeadline: Bool, prewarmsPreviews: Bool, requestsProjection: Bool) {
        context.measure(.delayedEntryScheduling) {
            base.scheduleDelayedWindowLayerEntryIfNeeded(preservingDeadline: preservingDeadline,
                prewarmsPreviews: prewarmsPreviews, requestsProjection: requestsProjection)
        }
    }
    func observeDelayedWindowLayerProjectionUpdate(source: DelayedWindowLayerEntryEvidenceSource, appID: String?) {
        base.observeDelayedWindowLayerProjectionUpdate(source: source, appID: appID)
    }
    func clearDelayedWindowLayerEntryState() { base.clearDelayedWindowLayerEntryState() }
    func prewarmSelectedAppWindowPreviewPage() -> Int { base.prewarmSelectedAppWindowPreviewPage() }
    func beginInitialVisibilityTracking(trigger: String) -> Int {
        context.measure(.initialVisibilityTracking) { base.beginInitialVisibilityTracking(trigger: trigger) }
    }
    func scheduleInitialVisibilityRecovery(trigger: String, initialVisibilityGeneration: Int) {
        context.measure(.presentationReadback) {
            base.scheduleInitialVisibilityRecovery(trigger: trigger, initialVisibilityGeneration: initialVisibilityGeneration)
        }
    }
    func cancelPresentationWork() { context.measure(.delayedTaskCancellation, parent: .panelTeardown) { base.cancelPresentationWork() } }
    func prewarmWindowOnlySessionPreviews() -> Int {
        let started = LiveSwitcherModel.monotonicMilliseconds()
        let result = base.prewarmWindowOnlySessionPreviews()
        context.controller?.recordFocusedWindowPreviewPrewarm(
            durationMilliseconds: LiveSwitcherModel.monotonicMilliseconds() - started)
        return result
    }
}
#endif
