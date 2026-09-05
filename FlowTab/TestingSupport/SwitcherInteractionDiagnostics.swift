#if FLOWTAB_TESTING
import Foundation

enum SwitcherInteractionComponent: String, CaseIterable, Sendable {
    case inputRouting = "input_routing"
    case projectionRead = "projection_read"
    case axCGSpaceReconciliation = "ax_cg_space_reconciliation"
    case onScreenCGRead = "on_screen_cg_read"
    case allCGRead = "all_cg_read"
    case axRead = "ax_read"
    case mappingSpaceFilter = "mapping_space_filter"
    case sessionBuild = "session_build"
    case sessionPublish = "session_publish"
    case previewPlanning = "preview_planning"
    case previewCapture = "preview_capture"
    case previewShareableContentLookup =
        "preview_shareable_content_lookup"
    case previewScreenshotManagerCapture =
        "preview_screenshot_manager_capture"
    case previewCoreGraphicsCapture =
        "preview_core_graphics_capture"
    case previewTransparentTrim = "preview_transparent_trim"
    case previewImageScale = "preview_image_scale"
    case previewImageMaterialization =
        "preview_image_materialization"
    case previewTitleBarInference = "preview_title_bar_inference"
    case previewImageProcessCache = "preview_image_process_cache"
    case previewBatchPublication = "preview_batch_publication"
    case previewResultDiscard = "preview_result_discard"
    case appKitPanelPresentation = "appkit_panel_presentation"
    case screenGeometry = "screen_geometry"
    case panelSize = "panel_size"
    case panelCenter = "panel_center"
    case panelAccessibility = "panel_accessibility"
    case panelLevel = "panel_level"
    case initialVisibilityTracking = "initial_visibility_tracking"
    case makeKey = "make_key"
    case orderFront = "order_front"
    case panelHide = "panel_hide"
    case presentationReadback = "presentation_readback"
    case eventMonitorInstall = "event_monitor_install"
    case delayedEntryScheduling = "delayed_entry_scheduling"
    case swiftUILayoutFirstDraw = "swiftui_layout_first_draw"
    case visibilityReadback = "visibility_readback"
    case selectionMutation = "selection_mutation"
    case panelGeometryUpdate = "panel_geometry_update"
    case swiftUIDiffLayoutDraw = "swiftui_diff_layout_draw"
    case selectionReadback = "selection_readback"
    case targetResolution = "target_resolution"
    case activationDispatch = "activation_dispatch"
    case exactWindowActivation = "exact_window_activation"
    case focusReadback = "focus_readback"
    case panelTeardown = "panel_teardown"
    case observerRemoval = "observer_removal"
    case delayedTaskCancellation = "delayed_task_cancellation"
    case cacheSessionCleanup = "cache_session_cleanup"
    case reusableShellPrepare = "reusable_shell_prepare"
    case closedStateReadback = "closed_state_readback"
}

enum SwitcherInteractionSpanOutcome: String, Sendable {
    case completed
    case cacheHit = "cache_hit"
    case pendingEvidence = "pending_evidence"
    case notRequested = "not_requested"
    case notRequired = "not_required"
    case cancelled
    case timedOut = "timed_out"
    case staleGeneration = "stale_generation"
    case failed
    case incomplete
}

struct SwitcherInteractionSpanToken: Hashable, Sendable {
    let rawValue: UInt64
    let generation: UInt64

    init(rawValue: UInt64, generation: UInt64 = 0) {
        self.rawValue = rawValue
        self.generation = generation
    }
}

struct SwitcherInteractionPremeasuredComponentSpan: Sendable {
    let component: SwitcherInteractionComponent
    let parent: SwitcherInteractionComponent?
    let startedAtNanoseconds: UInt64
    let completedAtNanoseconds: UInt64
    let startedCPUUserNanoseconds: UInt64
    let startedCPUSystemNanoseconds: UInt64
    let startedCPUIsValid: Bool
    let completedCPUUserNanoseconds: UInt64
    let completedCPUSystemNanoseconds: UInt64
    let completedCPUIsValid: Bool
    let outcome: SwitcherInteractionSpanOutcome
    let workUnits: Int
}

@MainActor
protocol SwitcherInteractionDiagnosticSink: AnyObject {
    func beginComponent(
        _ component: SwitcherInteractionComponent,
        parent: SwitcherInteractionComponent?,
        workUnits: Int
    ) -> SwitcherInteractionSpanToken?

    func endComponent(
        _ token: SwitcherInteractionSpanToken?,
        outcome: SwitcherInteractionSpanOutcome,
        workUnits: Int?
    )

    func recordUnexecutedComponent(
        _ component: SwitcherInteractionComponent,
        parent: SwitcherInteractionComponent?,
        outcome: SwitcherInteractionSpanOutcome,
        workUnits: Int
    )

    func recordPremeasuredComponent(
        _ span: SwitcherInteractionPremeasuredComponentSpan
    )
}

extension SwitcherInteractionDiagnosticSink {
    func beginComponent(
        _ component: SwitcherInteractionComponent,
        parent: SwitcherInteractionComponent? = nil,
        workUnits: Int = 0
    ) -> SwitcherInteractionSpanToken? {
        beginComponent(component, parent: parent, workUnits: workUnits)
    }

    func endComponent(
        _ token: SwitcherInteractionSpanToken?,
        outcome: SwitcherInteractionSpanOutcome = .completed,
        workUnits: Int? = nil
    ) {
        endComponent(token, outcome: outcome, workUnits: workUnits)
    }

    func recordUnexecutedComponent(
        _ component: SwitcherInteractionComponent,
        parent: SwitcherInteractionComponent? = nil,
        outcome: SwitcherInteractionSpanOutcome,
        workUnits: Int = 0
    ) {
        recordUnexecutedComponent(
            component,
            parent: parent,
            outcome: outcome,
            workUnits: workUnits
        )
    }
}
#endif
