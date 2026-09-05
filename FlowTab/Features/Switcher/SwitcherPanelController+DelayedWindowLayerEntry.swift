import Foundation

extension SwitcherPanelController {
    func scheduleDelayedWindowLayerEntryIfNeeded(
        preservingDeadline: Bool = false,
        prewarmsPreviews: Bool = true,
        requestsProjection: Bool = true
    ) {
        panelDelayedOperations.scheduleDelayedWindowLayerEntryIfNeeded(preservingDeadline: preservingDeadline, prewarmsPreviews: prewarmsPreviews, requestsProjection: requestsProjection)
    }

    func observeDelayedWindowLayerProjectionUpdate(
        source: DelayedWindowLayerEntryEvidenceSource,
        appID: String? = nil
    ) {
        panelDelayedOperations.observeDelayedWindowLayerProjectionUpdate(source: source, appID: appID)
    }

    func clearDelayedWindowLayerEntryState() {
        panelDelayedOperations.clearDelayedWindowLayerEntryState()
    }

    func prewarmSelectedAppWindowPreviewPage() -> Int {
        panelDelayedOperations.prewarmSelectedAppWindowPreviewPage()
    }

}
