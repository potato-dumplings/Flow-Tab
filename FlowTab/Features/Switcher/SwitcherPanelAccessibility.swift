import AppKit

@MainActor
protocol SwitcherPanelAccessibilityOperating {
    func syncPanelAccessibilityAnchors()
}

@MainActor
struct SwitcherPanelAccessibility: SwitcherPanelAccessibilityOperating {
    unowned let controller: SwitcherPanelController
    func syncPanelAccessibilityAnchors() {
        if controller.model.isSearchActive {
            guard !controller.panel.registeredSwitcherAccessibilityAppIDs.isEmpty else {
                return
            }
            controller.panel.updateSwitcherAccessibilityApps(
                [],
                tileSize: 1,
                spacing: 0,
                appStripHeaderOffset: 0
            )
            return
        }
        let appStripHeaderOffset =
            controller.searchFeatureEnabled && !controller.model.isPreviewLayerMode
            ? controller.appLayerSearchHeaderExtraHeight
            : 0
        controller.panel.updateSwitcherAccessibilityApps(
            controller.model.session?.apps ?? [],
            tileSize: controller.model.appGridTileSize,
            spacing: controller.model.appGridSpacing,
            appStripHeaderOffset: appStripHeaderOffset
        )
    }
}
