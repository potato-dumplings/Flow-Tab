import AppKit
import FlowTabCore

@MainActor
protocol SwitcherPanelGeometryOperating {
    typealias AppGridLayout = SwitcherPanelController.AppGridLayout
    func centerPanelOnActiveScreen(preferredScreen: NSScreen?)
    func resolveActivePresentationScreen() -> NSScreen?
    func resolveSizingScreen(preferredScreen: NSScreen?) -> NSScreen?
    func updatePanelSize(for preferredScreen: NSScreen?)
    func updatePanelSize(forVisibleFrame visibleFrame: CGRect)
    func resolvedStandardPreviewSectionHeight(panelWidth: CGFloat, itemCount: Int) -> CGFloat
    func preferredAppStripWidth(appCount: Int, maxTileSize: CGFloat) -> CGFloat
    func resolvedAppLayerPanelWidth(
        preferredWidth: CGFloat,
        visibleFrameWidth: CGFloat
    ) -> CGFloat
    func preferredPreviewLayerWidth(
        appCount: Int,
        windowCount: Int,
        maxPanelWidth: CGFloat
    ) -> CGFloat
    func resolveAppGridLayout(
        appCount: Int,
        availableWidth: CGFloat,
        maxTileSize: CGFloat
    ) -> AppGridLayout
    func setPanelContentSize(_ targetSize: NSSize, recenterScreen: NSScreen?)
}

@MainActor
final class SwitcherPanelGeometry: SwitcherPanelGeometryOperating {
    typealias AppGridLayout = SwitcherPanelController.AppGridLayout
    unowned let controller: SwitcherPanelController
    init(controller: SwitcherPanelController) { self.controller = controller }
    func centerPanelOnActiveScreen(preferredScreen: NSScreen? = nil) {
        let targetScreen = preferredScreen
            ?? resolveActivePresentationScreen()
            ?? controller.activePresentationScreen
            ?? controller.panel.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
        controller.activePresentationScreen = targetScreen
        guard let targetScreen else {
            controller.panel.center()
            return
        }

        let frame = targetScreen.frame
        let panelSize = controller.panel.frame.size
        let origin = NSPoint(
            x: frame.midX - panelSize.width / 2,
            y: frame.midY - panelSize.height / 2
        )
        guard controller.panel.frame.origin != origin else { return }
        controller.panel.setFrameOrigin(origin)
    }

    func resolveActivePresentationScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return mouseScreen
        }
        return controller.panel.screen
            ?? controller.activePresentationScreen
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    func resolveSizingScreen(preferredScreen: NSScreen? = nil) -> NSScreen? {
        preferredScreen
            ?? controller.activePresentationScreen
            ?? controller.panel.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    func updatePanelSize(for preferredScreen: NSScreen? = nil) {
        let sizingScreen = resolveSizingScreen(preferredScreen: preferredScreen)
        let visibleFrame = sizingScreen?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        updatePanelSize(forVisibleFrame: visibleFrame, recenterScreen: sizingScreen)
    }

    func updatePanelSize(forVisibleFrame visibleFrame: CGRect) {
        updatePanelSize(forVisibleFrame: visibleFrame, recenterScreen: nil)
    }

    func updatePanelSize(forVisibleFrame visibleFrame: CGRect, recenterScreen: NSScreen?) {
        if controller.model.isWindowOnlyOverlay {
            let targetSize = SwitcherWindowOnlyPanelSizing.preferredSize(
                visibleFrameSize: visibleFrame.size,
                itemCount: controller.model.previewWindowCount
            )
            setPanelContentSize(targetSize, recenterScreen: recenterScreen)
            return
        }

        let maxWidth = max(controller.appLayerMinimumWidth, visibleFrame.width - controller.panelScreenMargin)
        let maxHeight = max(controller.minimumPanelHeight, visibleFrame.height - controller.panelScreenMargin)
        let appStripPreferredWidth = preferredAppStripWidth(
            appCount: controller.model.appCount,
            maxTileSize: controller.appLayerMaxAdaptiveTileSize
        )
        let preferredWidth: CGFloat
        if controller.model.isPreviewLayerMode {
            preferredWidth = preferredPreviewLayerWidth(
                appCount: controller.model.appCount,
                windowCount: controller.model.previewWindowCount,
                maxPanelWidth: maxWidth
            )
        } else {
            preferredWidth = appStripPreferredWidth
        }
        let width = resolvedAppLayerPanelWidth(
            preferredWidth: preferredWidth,
            visibleFrameWidth: visibleFrame.width
        )
        let height: CGFloat

        if controller.model.isSearchActive {
            let visibleRows = SwitcherPanelLayoutMetrics.Search.visibleRowCount(
                for: controller.model.searchResultCount
            )
            let listHeight = SwitcherPanelLayoutMetrics.Search.resultListHeight(
                visibleRowCount: visibleRows,
                resultRowHeight: controller.model.searchLayoutMeasurements.resultRowHeight
            )
            let desiredHeight = SwitcherPanelLayoutMetrics.Search.panelHeight(
                visibleRowCount: visibleRows,
                measurements: controller.model.searchLayoutMeasurements
            )
            height = min(maxHeight, max(controller.minimumPanelHeight, desiredHeight))
            controller.logSearchLayoutSizing(
                resultCount: controller.model.searchResultCount,
                visibleRows: visibleRows,
                measurements: controller.model.searchLayoutMeasurements,
                listHeight: listHeight,
                neededPanelHeight: desiredHeight,
                finalPanelHeight: height,
                maxHeight: maxHeight,
                visibleFrameWidth: visibleFrame.width,
                preferredAppStripWidth: appStripPreferredWidth,
                finalPanelWidth: width
            )
            let targetSize = NSSize(width: width, height: height)
            setPanelContentSize(targetSize, recenterScreen: recenterScreen)
            return
        }

        if controller.model.isPreviewLayerMode {
            let gridLayout = resolveAppGridLayout(
                appCount: controller.model.appCount,
                availableWidth: max(1, width - SwitcherPanelLayoutMetrics.horizontalInset),
                maxTileSize: controller.previewLayerAppTileSize
            )
            let previewSectionHeight = resolvedStandardPreviewSectionHeight(
                panelWidth: width,
                itemCount: controller.model.previewWindowCount
            )
            let desiredHeight =
                SwitcherPanelLayoutMetrics.rootPadding * 2
                + SwitcherPanelLayoutMetrics.bodyVerticalPadding * 2
                + gridLayout.gridHeight
                + SwitcherPanelLayoutMetrics.bodySpacing
                + previewSectionHeight
            height = min(maxHeight, max(controller.minimumPanelHeight, desiredHeight))
            controller.model.updateAppGridLayout(
                tileSize: gridLayout.tileSize,
                spacing: gridLayout.spacing
            )
            controller.model.updatePreviewSectionHeight(previewSectionHeight)
        } else {
            let gridLayout = resolveAppGridLayout(
                appCount: controller.model.appCount,
                availableWidth: max(1, width - SwitcherPanelLayoutMetrics.horizontalInset),
                maxTileSize: controller.appLayerMaxAdaptiveTileSize
            )
            let searchHeaderHeight = controller.searchFeatureEnabled ? controller.appLayerSearchHeaderExtraHeight : 0
            let desiredHeight = controller.appLayerStaticHeight + searchHeaderHeight + gridLayout.gridHeight

            height = min(maxHeight, max(controller.minimumPanelHeight, desiredHeight))
            controller.model.updateAppGridLayout(
                tileSize: gridLayout.tileSize,
                spacing: gridLayout.spacing
            )
        }

        let targetSize = NSSize(width: width, height: height)
        setPanelContentSize(targetSize, recenterScreen: recenterScreen)
    }

    func setPanelContentSize(_ targetSize: NSSize, recenterScreen _: NSScreen?) {
        let oldFrame = controller.panel.frame
        let currentSize = controller.panel.contentRect(forFrameRect: controller.panel.frame).size
        guard currentSize != targetSize else { return }

        controller.panel.setContentSize(targetSize)

        guard controller.isPanelPresented else { return }
        let newFrame = controller.panel.frame
        controller.panel.setFrameOrigin(
            NSPoint(
                x: oldFrame.midX - newFrame.width / 2,
                y: oldFrame.maxY - newFrame.height
            )
        )
    }

    func resolvedStandardPreviewSectionHeight(panelWidth: CGFloat, itemCount: Int) -> CGFloat {
        let availableWidth = max(
            1,
            panelWidth - SwitcherPanelLayoutMetrics.horizontalInset - controller.standardPreviewWidthAdjustment
        )
        let page = SwitcherWindowPreviewPaging.page(
            itemCount: itemCount,
            selectedIndex: 0,
            availableWidth: availableWidth
        )
        let count = max(page.visibleRange.count, 1)
        let cardWidth = SwitcherWindowPreviewPaging.cardWidth(
            cardAreaWidth: page.cardAreaWidth,
            visibleCount: count
        )
        let cardHeight = max(
            controller.standardPreviewSectionMinimumHeight,
            min(controller.standardPreviewSectionMaximumHeight, cardWidth * controller.standardPreviewHeightRatio)
        )
        return cardHeight
    }

    func preferredAppStripWidth(appCount: Int, maxTileSize: CGFloat) -> CGFloat {
        let count = max(appCount, 1)
        let spacing = count > 1 ? controller.maxAppTileSpacing : 0
        let stripWidth =
            CGFloat(count) * maxTileSize
            + CGFloat(max(count - 1, 0)) * spacing
        return max(controller.appLayerMinimumWidth, stripWidth + SwitcherPanelLayoutMetrics.horizontalInset)
    }

    func resolvedAppLayerPanelWidth(
        preferredWidth: CGFloat,
        visibleFrameWidth: CGFloat
    ) -> CGFloat {
        min(
            preferredWidth,
            max(controller.appLayerMinimumWidth, visibleFrameWidth - controller.panelScreenMargin)
        )
    }

    func preferredPreviewLayerWidth(
        appCount: Int,
        windowCount: Int,
        maxPanelWidth: CGFloat
    ) -> CGFloat {
        let appStripWidth = preferredAppStripWidth(
            appCount: appCount,
            maxTileSize: controller.previewLayerAppTileSize
        )
        let maximumPreviewAvailableWidth = max(
            1,
            maxPanelWidth - SwitcherPanelLayoutMetrics.horizontalInset - controller.standardPreviewWidthAdjustment
        )
        let previewAvailableWidth = SwitcherWindowPreviewPaging.preferredAvailableWidth(
            itemCount: windowCount,
            maximumAvailableWidth: maximumPreviewAvailableWidth
        )
        let previewPanelWidth =
            previewAvailableWidth
            + SwitcherPanelLayoutMetrics.horizontalInset
            + controller.standardPreviewWidthAdjustment
        return max(appStripWidth, previewPanelWidth)
    }

    func resolveAppGridLayout(
        appCount: Int,
        availableWidth: CGFloat,
        maxTileSize: CGFloat
    ) -> AppGridLayout {
        let count = max(appCount, 1)
        let safeWidth = max(1, availableWidth)
        let spacing = count > 1 ? controller.maxAppTileSpacing : 0
        let totalSpacing = CGFloat(max(count - 1, 0)) * spacing
        let tileSize = max(
            controller.minAppTileSize,
            min(
                maxTileSize,
                (safeWidth - totalSpacing) / CGFloat(count)
            )
        )

        return AppGridLayout(
            tileSize: tileSize,
            spacing: spacing,
            columns: count,
            rows: 1
        )
    }
}
