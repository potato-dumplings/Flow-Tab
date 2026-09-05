#if FLOWTAB_TESTING
import AppKit

@MainActor
final class ControlTabPressurePreviewSession: SwitcherPreviewSessionOperating {
    let base: any SwitcherPreviewSessionOperating
    let diagnostics: ControlTabPressureModelDiagnostics

    init(base: any SwitcherPreviewSessionOperating, diagnostics: ControlTabPressureModelDiagnostics) {
        self.base = base
        self.diagnostics = diagnostics
        if let session = base as? SwitcherPreviewSession {
            session.publication = ControlTabPressurePreviewPublication(
                base: session.publication, diagnostics: diagnostics
            )
        }
    }

    func clear() {
        base.clear()
    }

    func applyPreviewCapture(
        _ capture: (image: NSImage, resolvedWindowID: CGWindowID?, titleBarStyle: WindowTitleBarStyleGuess?),
        appID: String, windowID: String, ownerPID: pid_t, initialCacheKey: String
    ) {
        diagnostics.renderGeneration &+= 1
        let token = diagnostics.measurementSink?.beginComponent(.previewImageProcessCache, parent: .previewPlanning, workUnits: 1)
        defer { diagnostics.measurementSink?.endComponent(token) }
        base.applyPreviewCapture(capture, appID: appID, windowID: windowID,
            ownerPID: ownerPID, initialCacheKey: initialCacheKey)
    }

    func completeBatch(_ outcomes: [WindowPreviewResult], pendingCaptures: [PendingPreviewCapture],
                       batchID: UUID, cancellation: WindowPreviewCaptureCancellation,
                       generation: UInt64, startMs: Double, completeMs: Double) -> PreviewBatchApplication {
        diagnostics.measuringBatch(batchID) {
            let token = diagnostics.measurementSink?.beginComponent(.previewImageProcessCache,
                parent: .previewPlanning, workUnits: pendingCaptures.count)
            let result = base.completeBatch(outcomes, pendingCaptures: pendingCaptures,
                batchID: batchID, cancellation: cancellation, generation: generation,
                startMs: startMs, completeMs: completeMs)
            let outcome: SwitcherInteractionSpanOutcome
            switch result {
            case .cancelled: outcome = .cancelled
            case .stale: outcome = .staleGeneration
            case .applied: outcome = .notRequired
            }
            diagnostics.measurementSink?.recordUnexecutedComponent(.previewResultDiscard,
                parent: .previewPlanning, outcome: outcome, workUnits: pendingCaptures.count)
            diagnostics.measurementSink?.endComponent(token)
            return result
        }
    }
}

@MainActor
struct ControlTabPressurePreviewPublication: SwitcherPreviewPublishing {
    let base: any SwitcherPreviewPublishing
    let diagnostics: ControlTabPressureModelDiagnostics

    func publish(completedCount: Int) {
        let token = diagnostics.measurementSink?.beginComponent(.previewBatchPublication,
            parent: .previewImageProcessCache, workUnits: completedCount)
        defer { diagnostics.measurementSink?.endComponent(token) }
        if completedCount > 0 { diagnostics.renderGeneration &+= 1 }
        base.publish(completedCount: completedCount)
    }
}
#endif
