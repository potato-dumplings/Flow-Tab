#if FLOWTAB_TESTING
import AppKit
import SwiftUI

@MainActor
struct ControlTabPressureContentBuilder: SwitcherPanelContentBuilding {
    func makeContent(context: SwitcherPanelContentContext) -> NSView {
        let measuresPressure = ControlTabPressureBootstrap.run != nil
        guard measuresPressure || FlowTabTestLaunchOptions.showsSwitcherDiagnostics else {
            return SwitcherPanelContentBuilder().makeContent(context: context)
        }
        return NSHostingView(rootView:
            SwitcherPanelContentBuilder.rootView(context: context)
                .overlay(alignment: .topLeading) {
                    if FlowTabTestLaunchOptions.showsSwitcherDiagnostics {
                        SwitcherTestingDiagnosticsSummary(model: context.model)
                    }
                }
                .background {
                    if measuresPressure {
                        DrawObservation(model: context.model)
                    }
                })
    }

    private struct DrawObservation: View {
        @ObservedObject var model: LiveSwitcherModel

        var body: some View {
            if model.isWindowOnlyOverlay, model.controlTabPressureDiagnostics.onRender != nil {
                ControlTabPressureRenderProbe(
                    generation: model.windowContentRenderGeneration,
                    identity: ControlTabPressureDrawIdentity(
                        presentationGeneration: model.controlTabPressureDiagnostics.presentationGeneration,
                        selectedWindowID: model.session?.selectedWindow?.id,
                        previewVersion: model.windowContentRenderGeneration),
                    onDraw: model.controlTabPressureDiagnostics.onRender)
            }
        }
    }
}
#endif
