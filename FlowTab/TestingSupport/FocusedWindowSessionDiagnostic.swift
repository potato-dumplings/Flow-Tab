#if FLOWTAB_TESTING
import Foundation

struct FocusedWindowSessionStartDiagnostic: Equatable {
    let result: String
    let appID: String?
    let windowCount: Int
    let startedAtMilliseconds: Double
    let completedAtMilliseconds: Double
    let partitions: [String: Double]

    var totalMilliseconds: Double {
        max(0, completedAtMilliseconds - startedAtMilliseconds)
    }
}

struct FocusedWindowSessionDiagnostic: Equatable {
    enum PartitionKey {
        static let invalidation = "invalidation_ms"
        static let projectionRead = "projection_read_ms"
        static let freshnessWait = "freshness_wait_ms"
        static let recency = "recency_ms"
        static let sessionBuild = "session_build_ms"
        static let sessionPublish = "session_publish_ms"
        static let previewPrewarm = "preview_prewarm_ms"
        static let screenResolve = "screen_resolve_ms"
        static let panelSize = "panel_size_ms"
        static let panelCenter = "panel_center_ms"
        static let accessibility = "accessibility_ms"
        static let panelPresentation = "panel_presentation_ms"
        static let unattributed = "unattributed_ms"

        static let required: Set<String> = [
            invalidation,
            projectionRead,
            freshnessWait,
            recency,
            sessionBuild,
            sessionPublish,
            previewPrewarm,
            screenResolve,
            panelSize,
            panelCenter,
            accessibility,
            panelPresentation,
            unattributed
        ]
    }

    enum MilestoneKey {
        static let sessionReady = "session_ready_ms"
        static let panelPresented = "panel_presented_ms"
        static let firstWindowContentDraw =
            "first_window_content_draw_ms"
        static let visibilityReadback = "visibility_readback_ms"
        static let firstVisibleFrame = "first_visible_frame_ms"
        static let cachedFirstFrame = "cached_first_frame_ms"
        static let cachedFirstFrameCPUTime =
            "cached_first_frame_cpu_time_ms"
        static let freshVisiblePreviewsComplete =
            "fresh_visible_previews_complete_ms"
        static let freshVisiblePreviewsCompleteCPUTime =
            "fresh_visible_previews_complete_cpu_time_ms"
    }

    let generation: Int
    let startedAtMilliseconds: Double
    var presentationSessionGeneration: Int?
    var result: String
    var appID: String?
    var windowCount: Int
    var partitions: [String: Double]
    var milestones: [String: Double]

    var partitionTotalMilliseconds: Double {
        partitions.values.reduce(0, +)
    }

    var reconciles: Bool {
        let tolerance = 0.5
        guard Set(partitions.keys).isSuperset(
                of: PartitionKey.required
              ),
              partitions.values.allSatisfy({
                $0.isFinite && $0 >= 0
              }),
              milestones.values.allSatisfy({
                $0.isFinite && $0 >= 0
              }),
              let panelPresented = milestones[
                MilestoneKey.panelPresented
              ],
              let firstDraw = milestones[
                MilestoneKey.firstWindowContentDraw
              ],
              let visibilityReadback = milestones[
                MilestoneKey.visibilityReadback
              ],
              let firstVisibleFrame = milestones[
                MilestoneKey.firstVisibleFrame
              ]
        else {
            return false
        }
        return abs(partitionTotalMilliseconds - panelPresented)
                <= tolerance
            && abs(
                firstVisibleFrame
                    - max(firstDraw, visibilityReadback)
            ) <= tolerance
    }
}

extension SwitcherPanelController {
    func beginFocusedWindowSessionDiagnostic(
        showStartMilliseconds: Double
    ) {
        controlTabPressureDiagnostics.pendingRenderEvent = nil
        focusedWindowSessionDiagnosticGeneration += 1
        lastFocusedWindowSessionDiagnostic =
            FocusedWindowSessionDiagnostic(
                generation:
                    focusedWindowSessionDiagnosticGeneration,
                startedAtMilliseconds: showStartMilliseconds,
                presentationSessionGeneration: nil,
                result: "starting",
                appID: nil,
                windowCount: 0,
                partitions: [:],
                milestones: [:]
            )
    }

    func recordFocusedWindowSessionStartDiagnostic() {
        guard var diagnostic =
                lastFocusedWindowSessionDiagnostic,
              let startDiagnostic = model
                .lastFocusedWindowSessionStartDiagnostic
        else {
            return
        }
        diagnostic.result = startDiagnostic.result
        diagnostic.appID = startDiagnostic.appID
        diagnostic.windowCount = startDiagnostic.windowCount
        diagnostic.partitions.merge(
            startDiagnostic.partitions,
            uniquingKeysWith: { _, latest in latest }
        )
        diagnostic.milestones[
            FocusedWindowSessionDiagnostic.MilestoneKey
                .sessionReady
        ] = max(
            0,
            startDiagnostic.completedAtMilliseconds
                - diagnostic.startedAtMilliseconds
        )
        lastFocusedWindowSessionDiagnostic = diagnostic
    }

    func recordFocusedWindowPreviewPrewarm(
        durationMilliseconds: Double
    ) {
        guard var diagnostic =
                lastFocusedWindowSessionDiagnostic
        else {
            return
        }
        diagnostic.partitions[
            FocusedWindowSessionDiagnostic.PartitionKey
                .previewPrewarm
        ] = max(0, durationMilliseconds)
        lastFocusedWindowSessionDiagnostic = diagnostic
    }

    func recordFocusedWindowPanelPresentation(
        _ presentation: PanelPresentationBreakdownDiagnostic,
        presentedAtMilliseconds: Double
    ) {
        guard var diagnostic =
                lastFocusedWindowSessionDiagnostic
        else {
            return
        }
        diagnostic.partitions[
            FocusedWindowSessionDiagnostic.PartitionKey
                .screenResolve
        ] = max(0, presentation.screenMs)
        diagnostic.partitions[
            FocusedWindowSessionDiagnostic.PartitionKey.panelSize
        ] = max(0, presentation.sizeMs)
        diagnostic.partitions[
            FocusedWindowSessionDiagnostic.PartitionKey.panelCenter
        ] = max(0, presentation.centerMs)
        diagnostic.partitions[
            FocusedWindowSessionDiagnostic.PartitionKey
                .accessibility
        ] = max(0, presentation.accessibilityMs)
        diagnostic.partitions[
            FocusedWindowSessionDiagnostic.PartitionKey
                .panelPresentation
        ] = max(
            0,
            presentation.levelMs
                + presentation.hideMs
                + presentation.initialVisibilityTrackingMs
                + presentation.monitorMs
                + presentation.makeKeyMs
                + presentation.orderRegardlessMs
                + presentation.presentationReadbackMs
                + presentation.autoEnterMs
        )
        diagnostic.milestones[
            FocusedWindowSessionDiagnostic.MilestoneKey
                .panelPresented
        ] = max(
            0,
            presentedAtMilliseconds
                - diagnostic.startedAtMilliseconds
        )
        let panelPresented = diagnostic.milestones[
            FocusedWindowSessionDiagnostic.MilestoneKey
                .panelPresented
        ] ?? 0
        let attributed = diagnostic.partitions.reduce(0) {
            partial, item in
            item.key == FocusedWindowSessionDiagnostic
                .PartitionKey.unattributed
                ? partial
                : partial + item.value
        }
        diagnostic.partitions[
            FocusedWindowSessionDiagnostic.PartitionKey.unattributed
        ] = max(0, panelPresented - attributed)
        lastFocusedWindowSessionDiagnostic = diagnostic
    }

    func recordFocusedWindowFirstVisibleFrame(
        renderEvent: ControlTabPressureRenderEvent,
        visibleAtMilliseconds: Double
    ) {
        guard renderEvent.milestone == .windowContent,
              var diagnostic =
                lastFocusedWindowSessionDiagnostic
        else {
            return
        }
        let drawElapsed = max(
            0,
            renderEvent.drawnAtMilliseconds
                - diagnostic.startedAtMilliseconds
        )
        let visibilityElapsed = max(
            0,
            visibleAtMilliseconds
                - diagnostic.startedAtMilliseconds
        )
        diagnostic.milestones[
            FocusedWindowSessionDiagnostic.MilestoneKey
                .firstWindowContentDraw
        ] = drawElapsed
        diagnostic.milestones[
            FocusedWindowSessionDiagnostic.MilestoneKey
                .visibilityReadback
        ] = visibilityElapsed
        diagnostic.milestones[
            FocusedWindowSessionDiagnostic.MilestoneKey
                .firstVisibleFrame
        ] = max(drawElapsed, visibilityElapsed)
        diagnostic.milestones[
            FocusedWindowSessionDiagnostic.MilestoneKey
                .cachedFirstFrame
        ] = max(drawElapsed, visibilityElapsed)
        diagnostic.presentationSessionGeneration =
            presentationSessionGeneration
        lastFocusedWindowSessionDiagnostic = diagnostic
        for observer in
            focusedWindowFirstVisibleFrameObservers.values
        {
            observer(diagnostic)
        }
    }

    func recordFreshVisiblePreviewsComplete(
        renderEvent: ControlTabPressureRenderEvent
    ) {
        guard renderEvent.milestone == .windowContent,
              model.windowOnlyPreviewPreparationSucceeded,
              var diagnostic = lastFocusedWindowSessionDiagnostic,
              diagnostic.milestones[
                FocusedWindowSessionDiagnostic.MilestoneKey
                    .freshVisiblePreviewsComplete
              ] == nil
        else {
            return
        }
        diagnostic.milestones[
            FocusedWindowSessionDiagnostic.MilestoneKey
                .freshVisiblePreviewsComplete
        ] = max(
            diagnostic.milestones[
                FocusedWindowSessionDiagnostic.MilestoneKey.firstVisibleFrame
            ] ?? 0,
            renderEvent.drawnAtMilliseconds
                - diagnostic.startedAtMilliseconds
        )
        lastFocusedWindowSessionDiagnostic = diagnostic
    }

    func addFocusedWindowFirstVisibleFrameObserver(
        _ observer: @escaping (
            FocusedWindowSessionDiagnostic
        ) -> Void
    ) -> UUID {
        let id = UUID()
        focusedWindowFirstVisibleFrameObservers[id] = observer
        return id
    }

    func removeFocusedWindowFirstVisibleFrameObserver(
        _ id: UUID
    ) {
        focusedWindowFirstVisibleFrameObservers[id] = nil
    }
}
#endif
