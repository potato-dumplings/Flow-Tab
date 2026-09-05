import AppKit
import SwiftUI

@MainActor
struct SwitcherPanelContentContext {
    let model: LiveSwitcherModel
    let pointerSelectionActions: SwitcherPointerSelectionActions
    let onRenderPreparation: (SwitcherRenderMilestonePreparation) -> Void
    let onRenderMilestone: (SwitcherRenderMilestoneEvent) -> Void
}

@MainActor
protocol SwitcherPanelContentBuilding {
    func makeContent(context: SwitcherPanelContentContext) -> NSView
}

@MainActor
struct SwitcherPanelContentBuilder: SwitcherPanelContentBuilding {
    func makeContent(context: SwitcherPanelContentContext) -> NSView {
        NSHostingView(rootView: Self.rootView(context: context))
    }

    static func rootView(context: SwitcherPanelContentContext) -> SwitcherPanelRootView {
        SwitcherPanelRootView(model: context.model,
            pointerSelectionActions: context.pointerSelectionActions,
            onRenderPreparation: context.onRenderPreparation,
            onRenderMilestone: context.onRenderMilestone)
    }
}
