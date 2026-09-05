#if FLOWTAB_TESTING
import AppKit

@MainActor
struct ControlTabPressurePanelGeometry: SwitcherPanelGeometryOperating {
    let base: any SwitcherPanelGeometryOperating
    let context: ControlTabPressurePanelMeasurement
    func centerPanelOnActiveScreen(preferredScreen: NSScreen?) {
        context.measure(.panelCenter) { base.centerPanelOnActiveScreen(preferredScreen: preferredScreen) }
    }
    func resolveActivePresentationScreen() -> NSScreen? {
        context.measure(.screenGeometry) { base.resolveActivePresentationScreen() }
    }
    func resolveSizingScreen(preferredScreen: NSScreen?) -> NSScreen? {
        base.resolveSizingScreen(preferredScreen: preferredScreen)
    }
    func updatePanelSize(for preferredScreen: NSScreen?) {
        context.measure(context.isPresenting ? .panelSize : .panelGeometryUpdate,
                        parent: context.isPresenting ? .appKitPanelPresentation : .inputRouting,
                        workUnits: context.isPresenting ? 1 : (context.controller?.model.previewWindowCount ?? 0)) {
            base.updatePanelSize(for: preferredScreen)
        }
    }
    func updatePanelSize(forVisibleFrame visibleFrame: CGRect) {
        base.updatePanelSize(forVisibleFrame: visibleFrame)
    }
    func setPanelContentSize(_ targetSize: NSSize, recenterScreen: NSScreen?) {
        base.setPanelContentSize(targetSize, recenterScreen: recenterScreen)
    }
    func resolvedStandardPreviewSectionHeight(panelWidth: CGFloat, itemCount: Int) -> CGFloat {
        base.resolvedStandardPreviewSectionHeight(panelWidth: panelWidth, itemCount: itemCount)
    }
    func preferredAppStripWidth(appCount: Int, maxTileSize: CGFloat) -> CGFloat {
        base.preferredAppStripWidth(appCount: appCount, maxTileSize: maxTileSize)
    }
    func resolvedAppLayerPanelWidth(preferredWidth: CGFloat, visibleFrameWidth: CGFloat) -> CGFloat {
        base.resolvedAppLayerPanelWidth(preferredWidth: preferredWidth, visibleFrameWidth: visibleFrameWidth)
    }
    func preferredPreviewLayerWidth(appCount: Int, windowCount: Int, maxPanelWidth: CGFloat) -> CGFloat {
        base.preferredPreviewLayerWidth(appCount: appCount, windowCount: windowCount, maxPanelWidth: maxPanelWidth)
    }
    func resolveAppGridLayout(appCount: Int, availableWidth: CGFloat, maxTileSize: CGFloat) -> AppGridLayout {
        base.resolveAppGridLayout(appCount: appCount, availableWidth: availableWidth, maxTileSize: maxTileSize)
    }
}
#endif
