import AppKit
import FlowTabCore

typealias SwitcherSynchronousPreviewCapture = (CGWindowID?, pid_t, String?, Bool)
    -> (image: NSImage, resolvedWindowID: CGWindowID, titleBarStyle: WindowTitleBarStyleGuess?)?

struct SwitcherPreviewPlanningContext {
    let session: SwitcherSession?
    let overlayStyle: SwitcherOverlayStyle
    let titleBarStyleInferenceEnabled: Bool
    let previewCaptureOverride: SwitcherSynchronousPreviewCapture?
}

struct ResolvedPreviewData {
    let preview: (image: NSImage?, titleBarStyle: WindowTitleBarStyleGuess?)
    let pendingCapture: PendingPreviewCapture?
}

struct SwitcherPreviewPlan {
    let appID: String
    let selectedIndex: Int
    let items: [WindowPreviewItem]
    let pendingCaptures: [PendingPreviewCapture]
}

@MainActor
protocol SwitcherPreviewPlanning {
    func plan(context: SwitcherPreviewPlanningContext, visibleRange: Range<Int>?) -> SwitcherPreviewPlan?
    func resolve(context: SwitcherPreviewPlanningContext, appID: String,
                 window: WindowCandidate, pinForSession: Bool) -> ResolvedPreviewData
}

@MainActor
struct SwitcherPreviewPlanner: SwitcherPreviewPlanning {
    let state: SwitcherPreviewStorage
    let contexts: SwitcherRuntimeContextStore
    let previewSession: any SwitcherPreviewSessionOperating

    func plan(context: SwitcherPreviewPlanningContext, visibleRange: Range<Int>?) -> SwitcherPreviewPlan? {
        Operation(state: state, contexts: contexts, previewSession: previewSession, context: context)
            .plan(visibleRange: visibleRange)
    }

    func resolve(context: SwitcherPreviewPlanningContext, appID: String,
                 window: WindowCandidate, pinForSession: Bool) -> ResolvedPreviewData {
        Operation(state: state, contexts: contexts, previewSession: previewSession, context: context)
            .resolvePreviewData(for: appID, window: window, pinForSession: pinForSession)
    }

    @MainActor
    struct Operation {
        let state: SwitcherPreviewStorage
        let contexts: SwitcherRuntimeContextStore
        let previewSession: any SwitcherPreviewSessionOperating
        let context: SwitcherPreviewPlanningContext

        var session: SwitcherSession? { context.session }
        var overlayStyle: SwitcherOverlayStyle { context.overlayStyle }
        var titleBarStyleInferenceEnabled: Bool { context.titleBarStyleInferenceEnabled }
        var previewCaptureOverride: SwitcherSynchronousPreviewCapture? { context.previewCaptureOverride }
    }
}
