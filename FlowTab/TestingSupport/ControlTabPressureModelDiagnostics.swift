#if FLOWTAB_TESTING
import AppKit
import Foundation
import FlowTabCore

@MainActor
final class ControlTabPressureModelDiagnostics {
    weak var sink: (any SwitcherInteractionDiagnosticSink)?
    var renderGeneration: UInt64 = 0
    var presentationGeneration: Int = 0
    var onRender: ((ControlTabPressureRenderEvent) -> Void)?
    var lastFocusedStart: FocusedWindowSessionStartDiagnostic?
    var startedAt: Double = 0
    var projectionStartedAt: Double = 0
    var projectionReadMilliseconds: Double = 0
    var freshnessStartedAt: Double?
    var freshnessMilliseconds: Double = 0
    var sessionBuildMilliseconds: Double = 0
    var sessionPublishMilliseconds: Double = 0
    var recencyStartedAt: Double = 0
    var recencyCompletedAt: Double = 0
    var reconciliationSpan: SwitcherInteractionSpanToken?
    var previewMeasurements: ControlTabPressurePreviewMeasurements?
    private var batchGeneration: UInt64?

    var measurementSink: (any SwitcherInteractionDiagnosticSink)? {
        if let batchGeneration, previewMeasurements?.isCurrent(batchGeneration) != true { return nil }
        return sink
    }

    func measuringBatch<T>(_ id: UUID, operation: () -> T) -> T {
        let previous = batchGeneration
        if let previewMeasurements { batchGeneration = previewMeasurements.takeGeneration(for: id) ?? 0 }
        defer { batchGeneration = previous }
        return operation()
    }

    func beginFocusedSession(startedAt: Double) {
        self.startedAt = startedAt
        projectionReadMilliseconds = 0
        freshnessStartedAt = nil
        freshnessMilliseconds = 0
        sessionBuildMilliseconds = 0
        sessionPublishMilliseconds = 0
        recencyStartedAt = 0
        recencyCompletedAt = 0
    }

    func finishReconciliation(
        outcome: SwitcherInteractionSpanOutcome,
        waitCompletedAt: Double? = nil
    ) {
        sink?.endComponent(reconciliationSpan, outcome: outcome)
        reconciliationSpan = nil
        if let freshnessStartedAt {
            freshnessMilliseconds = max(
                0, (waitCompletedAt ?? LiveSwitcherModel.monotonicMilliseconds()) - freshnessStartedAt
            )
        }
        freshnessStartedAt = nil
    }
    func recordPreviewReuse(workUnits: Int) {
        sink?.recordUnexecutedComponent(
            .previewCapture, parent: .previewPlanning, outcome: .cacheHit, workUnits: workUnits
        )
        sink?.recordUnexecutedComponent(
            .previewImageProcessCache, parent: .previewPlanning, outcome: .cacheHit, workUnits: workUnits
        )
        for stage in RuntimeWindowPreviewCaptureDiagnosticStage.allCases {
            guard let component = SwitcherInteractionComponent(rawValue: stage.rawValue) else { continue }
            sink?.recordUnexecutedComponent(
                component, parent: .previewCapture, outcome: .cacheHit, workUnits: workUnits
            )
        }
        sink?.recordUnexecutedComponent(
            .previewBatchPublication, parent: .previewPlanning, outcome: .cacheHit, workUnits: workUnits
        )
        sink?.recordUnexecutedComponent(
            .previewResultDiscard, parent: .previewPlanning, outcome: .notRequired, workUnits: workUnits
        )
    }
}

extension LiveSwitcherModel {
    var interactionDiagnosticSink: (any SwitcherInteractionDiagnosticSink)? {
        get { controlTabPressureDiagnostics.sink }
        set {
            controlTabPressureDiagnostics.sink = newValue
            guard newValue != nil else { return }
            if !(sessionResources is ControlTabPressureSessionResources) {
                sessionResources = ControlTabPressureSessionResources(
                    base: sessionResources, contexts: runtimeContextStore, diagnostics: controlTabPressureDiagnostics)
            }
            if !(focusedWindowSession is ControlTabPressureFocusedSession) {
                focusedWindowSession = ControlTabPressureFocusedSession(
                    base: focusedWindowSession, model: self, diagnostics: controlTabPressureDiagnostics)
            }
            if !(sessionState is ControlTabPressureSessionState) {
                sessionState = ControlTabPressureSessionState(
                    base: sessionState, diagnostics: controlTabPressureDiagnostics
                )
            }
            if !(previewSession is ControlTabPressurePreviewSession) {
                previewSession = ControlTabPressurePreviewSession(
                    base: previewSession, diagnostics: controlTabPressureDiagnostics
                )
            }
            if !(previewPlanner is ControlTabPressurePreviewPlanner) {
                let base: any SwitcherPreviewPlanning
                if let planner = previewPlanner as? SwitcherPreviewPlanner {
                    base = SwitcherPreviewPlanner(state: planner.state, contexts: planner.contexts,
                                                  previewSession: previewSession)
                } else {
                    base = previewPlanner
                }
                previewPlanner = ControlTabPressurePreviewPlanner(base: base, diagnostics: controlTabPressureDiagnostics)
            }
        }
    }

    var windowContentRenderGeneration: UInt64 {
        get { controlTabPressureDiagnostics.renderGeneration }
        set { controlTabPressureDiagnostics.renderGeneration = newValue }
    }

    var lastFocusedWindowSessionStartDiagnostic: FocusedWindowSessionStartDiagnostic? {
        controlTabPressureDiagnostics.lastFocusedStart
    }

    var windowOnlyPreviewPreparationSucceeded: Bool {
        guard overlayStyle == .windowOnly, session != nil,
              !previewSessionPinnedKeys.isEmpty,
              previewCaptureInFlightKeys.isEmpty else { return false }
        return previewSessionPinnedKeys.allSatisfy { key in
            guard case .succeeded = previewCaptureStatesByKey[key] else { return false }
            return true
        }
    }

    func pressureRecordFocusedStart(
        result: String,
        appID: String?,
        projectionReadMs: Double,
        recencyAppliedMs: Double,
        completeMs: Double,
        windowCount: Int
    ) {
        let state = controlTabPressureDiagnostics
        state.lastFocusedStart = FocusedWindowSessionStartDiagnostic(
            result: result,
            appID: appID,
            windowCount: windowCount,
            startedAtMilliseconds: state.startedAt,
            completedAtMilliseconds: completeMs,
            partitions: [
                "invalidation_ms": max(0, state.projectionStartedAt - state.startedAt),
                "projection_read_ms": state.projectionReadMilliseconds,
                "freshness_wait_ms": state.freshnessMilliseconds,
                "recency_ms": max(0, recencyAppliedMs - projectionReadMs),
                "session_build_ms": state.sessionBuildMilliseconds,
                "session_publish_ms": state.sessionPublishMilliseconds
            ]
        )
    }

}
#endif
