import AppKit
import SwiftUI
import FlowTabCore

private enum SwitcherOverlayPresentationMode: Hashable {
    case standard
    case search
    case windowOnly
}

private struct ExclusiveSwitcherOverlayHost: NSViewRepresentable {
    let mode: SwitcherOverlayPresentationMode?
    let contentForMode: (SwitcherOverlayPresentationMode) -> AnyView

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        context.coordinator.present(
            mode: mode,
            contentForMode: contentForMode,
            in: container
        )
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        context.coordinator.present(
            mode: mode,
            contentForMode: contentForMode,
            in: container
        )
    }

    static func dismantleNSView(
        _ container: NSView,
        coordinator: Coordinator
    ) {
        coordinator.dismantle(from: container)
    }

    @MainActor
    final class Coordinator {
        private var hostingViews:
            [SwitcherOverlayPresentationMode: NSHostingView<AnyView>] = [:]
        private var activeMode: SwitcherOverlayPresentationMode?

        func present(
            mode: SwitcherOverlayPresentationMode?,
            contentForMode: (SwitcherOverlayPresentationMode) -> AnyView,
            in container: NSView
        ) {
            guard let mode else { return }
            let content = contentForMode(mode)
            let hostingView: NSHostingView<AnyView>
            if let cachedHostingView = hostingViews[mode] {
                hostingView = cachedHostingView
                hostingView.rootView = content
            } else {
                hostingView = NSHostingView(rootView: content)
                hostingView.translatesAutoresizingMaskIntoConstraints = false
                hostingView.sizingOptions = []
                hostingViews[mode] = hostingView
            }

            guard activeMode != mode || hostingView.superview !== container else {
                hostingView
                    .updateSwitcherOverlayPresentationSessionActivity(
                        true
                    )
                return
            }

            // Detaching inactive hosts keeps their SwiftUI state reusable without
            // allowing their intrinsic size to participate in panel layout.
            container.subviews.forEach {
                $0.updateSwitcherOverlayPresentationSessionActivity(false)
                $0.removeFromSuperview()
            }
            container.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: container.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
            hostingView
                .updateSwitcherOverlayPresentationSessionActivity(true)
            activeMode = mode
        }

        func dismantle(from container: NSView) {
            container.subviews.forEach {
                $0.updateSwitcherOverlayPresentationSessionActivity(false)
                $0.removeFromSuperview()
            }
            hostingViews.removeAll()
            activeMode = nil
        }
    }
}
struct CommandTabOverlay: View {
    let appRenderSnapshot: SwitcherAppLayerRenderSnapshot
    let overlayStyle: SwitcherOverlayStyle
    let isPresentationSessionActive: Bool
    let isPreviewLayer: Bool
    let previewSectionHeight: CGFloat
    let windowRenderGeneration: UInt64
    let windowPreviewItems: [WindowPreviewItem]
    let standardWindowPreviewSummary: WindowPreviewPageSummary
    let standardWindowPreviewItemsForRange: (Range<Int>) -> [WindowPreviewItem]
    let searchState: SwitcherSearchViewState
    let searchResultScrollRevision: UInt64
    let searchLayoutMeasurements: SwitcherSearchLayoutMeasurements
    let searchAppItems: [SearchAppResultItem]
    let searchWindowItems: [SearchWindowResultItem]
    let onSearchInputChanged: (String, Int) -> Void
    let onSearchMarkedTextChanged: (Bool) -> Void
    let onSearchLayoutMeasured: (SwitcherSearchLayoutMeasurements) -> Void
    let searchFeatureEnabled: Bool
    let searchDefaultScope: SwitcherSearchScope
    let appLanguage: AppLanguage
    let selectedApp: AppSwitchCandidate?
    let terminatingAppID: String?
    let appTileSize: CGFloat
    let appTileSpacing: CGFloat
    let onSearchResultScrollRequested: (String) -> Void
    let pointerSelectionActions: SwitcherPointerSelectionActions
    let onRenderPreparation:
        (SwitcherRenderMilestonePreparation) -> Void
    let onRenderMilestone: (SwitcherRenderMilestoneEvent) -> Void
    let iconForApp: (AppSwitchCandidate) -> NSImage?
    @Environment(\.colorScheme) private var colorScheme

    private struct SearchResultScrollRequest: Equatable {
        let revision: UInt64
        let resultID: String?
        let isInputFocused: Bool
    }

    private struct SearchResultScrollProxy: @unchecked Sendable {
        let proxy: ScrollViewProxy
    }

    private var isWindowOnlyMode: Bool {
        overlayStyle == .windowOnly
    }

    private var showsAppStrip: Bool {
        overlayStyle == .appAndWindow
    }

    private var isSearchMode: Bool {
        searchState.isActive
    }

    private var showsSearchHeaderInStandardOverlay: Bool {
        searchFeatureEnabled && !isPreviewLayer
    }

    private func previewCardHeight(for cardWidth: CGFloat) -> CGFloat {
        let maxHeight: CGFloat = showsAppStrip ? 220 : 248
        return max(130, min(maxHeight, cardWidth * 0.62))
    }

    private var selectedSearchResultID: String? {
        guard !searchState.results.isEmpty else { return nil }
        let index = min(max(searchState.selectedResultIndex, 0), searchState.results.count - 1)
        return searchState.results[index].id
    }

    private var searchResultScrollRequest: SearchResultScrollRequest {
        SearchResultScrollRequest(
            revision: searchResultScrollRevision,
            resultID: selectedSearchResultID,
            isInputFocused: searchState.isInputFocused
        )
    }

    private var searchResultViewportHeight: CGFloat {
        let visibleRows = SwitcherPanelLayoutMetrics.Search.visibleRowCount(
            for: searchState.results.count
        )
        return SwitcherPanelLayoutMetrics.Search.resultListHeight(
            visibleRowCount: visibleRows,
            resultRowHeight: searchLayoutMeasurements.resultRowHeight
        )
    }

    private var searchHeaderHighlightItem: SearchHeaderHighlightItem? {
        guard isSearchMode else { return nil }
        switch searchState.scope {
        case .app:
            guard !searchAppItems.isEmpty else { return nil }
            let index = min(max(searchState.selectedResultIndex, 0), searchAppItems.count - 1)
            let item = searchAppItems[index]
            return SearchHeaderHighlightItem(
                title: item.app.displayName,
                icon: iconForApp(item.app)
            )
        case .window:
            guard !searchWindowItems.isEmpty else { return nil }
            let index = min(max(searchState.selectedResultIndex, 0), searchWindowItems.count - 1)
            let item = searchWindowItems[index]
            return SearchHeaderHighlightItem(
                title: item.appName,
                icon: item.icon
            )
        }
    }

    private func switcherAppAccessibilityIdentifier(
        _ item: SwitcherAppRenderItem
    ) -> String {
        SwitcherAccessibilityIdentifiers.app(id: item.id)
    }

    private func switcherAppAccessibilityValue(
        _ item: SwitcherAppRenderItem
    ) -> String {
        "\(item.id), \(item.windowCount)w"
    }

    private func switcherWindowAccessibilityIdentifier(_ preview: WindowPreviewItem) -> String {
        SwitcherAccessibilityIdentifiers.window(id: preview.id)
    }

    private func switcherWindowPreviewImageAccessibilityIdentifier(_ preview: WindowPreviewItem) -> String {
        SwitcherAccessibilityIdentifiers.windowPreviewImage(id: preview.id)
    }

    private func switcherWindowAccessibilityValue(_ preview: WindowPreviewItem) -> String {
        let imageState = preview.image == nil ? "preview=fallback" : "preview=image"
        guard let appName = selectedApp?.displayName, !appName.isEmpty else {
            return imageState
        }
        return "\(appName), \(imageState)"
    }

    @ViewBuilder
    private func windowPreviewImageMarker(for preview: WindowPreviewItem) -> some View {
        if preview.image != nil {
            Rectangle()
                .fill(Color.primary.opacity(0.001))
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Preview image"))
                .accessibilityIdentifier(switcherWindowPreviewImageAccessibilityIdentifier(preview))
        }
    }

    @MainActor
    private func scrollToSearchResult(
        _ request: SearchResultScrollRequest,
        using scrollProxy: SearchResultScrollProxy
    ) {
        guard !request.isInputFocused else { return }
        guard let resultID = request.resultID else { return }
        onSearchResultScrollRequested(resultID)
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scrollProxy.proxy.scrollTo(resultID, anchor: .center)
        }
    }

    @ViewBuilder
    private var standardOverlaySearchHeader: some View {
        if showsSearchHeaderInStandardOverlay {
            SearchInputHeader(
                query: "",
                scope: searchDefaultScope,
                isInputFocused: false,
                hintText: AppStrings.text(.panelHintEnterToSearch, language: appLanguage),
                language: appLanguage
            )
        }
    }

    private var standardOverlayAppStrip: some View {
        let appIDs = appRenderSnapshot.items.map(\.id)
        let removalAnimationDuration =
            SwitcherAppRemovalAnimationPolicy.default
                .animationDuration(
                    appCount: appRenderSnapshot.items.count,
                    listChange: appRenderSnapshot.listChange
                )
        return HStack(alignment: .center, spacing: appTileSpacing) {
            ForEach(appRenderSnapshot.items) { item in
                AppTileView(
                    displayName: item.displayName,
                    isSelected:
                        item.id == appRenderSnapshot.selectedAppID,
                    isTerminating: item.id == terminatingAppID,
                    size: appTileSize,
                    icon: item.icon,
                    accessibilityIdentifier:
                        switcherAppAccessibilityIdentifier(item),
                    accessibilityLabel: item.displayName,
                    accessibilityValue:
                        switcherAppAccessibilityValue(item)
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(item.displayName))
                .accessibilityValue(
                    Text(switcherAppAccessibilityValue(item))
                )
                .accessibilityIdentifier(
                    switcherAppAccessibilityIdentifier(item)
                )
                .transition(.appQuitRemoval)
            }
        }
        .animation(
            removalAnimationDuration.map {
                Animation.easeOut(duration: $0)
            },
            value: appIDs
        )
        .frame(maxWidth: .infinity, alignment: .center)
        .overlay {
            GeometryReader { proxy in
                Color.clear
                    .switcherPointerTracking { location in
                        guard let appID = SwitcherPointerAppStripHitTest.appID(
                            at: location,
                            in: proxy.frame(in: .global),
                            appIDs: appIDs,
                            tileSize: appTileSize,
                            spacing: appTileSpacing
                        ) else { return }
                        pointerSelectionActions.selectApp(appID)
                    }
                    .simultaneousGesture(
                        SpatialTapGesture(coordinateSpace: .global)
                            .onEnded { value in
                                guard let appID = SwitcherPointerAppStripHitTest.appID(
                                    at: value.location,
                                    in: proxy.frame(in: .global),
                                    appIDs: appIDs,
                                    tileSize: appTileSize,
                                    spacing: appTileSpacing
                                ) else { return }
                                pointerSelectionActions.commitApp(appID)
                            }
                    )
            }
        }
        .padding(.horizontal, 2)
        .background(
            SwitcherRenderMilestoneProbe(
                milestone: .appContent,
                renderGeneration: appRenderSnapshot.generation,
                onPreparation: onRenderPreparation,
                onDraw: onRenderMilestone
            )
        )
    }

    @ViewBuilder
    private var standardOverlayPreviewSection: some View {
        if isPreviewLayer {
            GeometryReader { proxy in
                let page = SwitcherWindowPreviewPaging.page(
                    itemCount: standardWindowPreviewSummary.itemCount,
                    selectedIndex: standardWindowPreviewSummary.selectedIndex,
                    availableWidth: max(0, proxy.size.width - 4)
                )
                let pageItems = standardWindowPreviewItemsForRange(page.visibleRange)
                let cardWidth = SwitcherWindowPreviewPaging.cardWidth(
                    cardAreaWidth: page.cardAreaWidth,
                    visibleCount: pageItems.count
                )
                let cardHeight = previewCardHeight(for: cardWidth)

                HStack(spacing: SwitcherWindowPreviewPaging.indicatorSpacing) {
                    if page.showsNavigationIndicators {
                        WindowPreviewPageIndicator(direction: .previous, isVisible: page.hasPreviousPage)
                    }

                    HStack(spacing: SwitcherWindowPreviewPaging.itemSpacing) {
                        ForEach(pageItems) { preview in
                            ZStack(alignment: .topLeading) {
                                WindowPreviewCard(
                                    image: preview.image,
                                    title: preview.title,
                                    appIcon: selectedApp.flatMap(iconForApp),
                                    isSelected: preview.isSelected,
                                    width: cardWidth,
                                    height: cardHeight
                                )
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(Text(preview.title))
                                .accessibilityValue(Text(switcherWindowAccessibilityValue(preview)))
                                .accessibilityIdentifier(switcherWindowAccessibilityIdentifier(preview))
                                .switcherPointerSelection(
                                    isEnabled: selectedApp != nil,
                                    onClick: {
                                        if let appID = selectedApp?.id {
                                            pointerSelectionActions.commitWindow(appID, preview.id)
                                        }
                                    }
                                ) {
                                    if let appID = selectedApp?.id {
                                        pointerSelectionActions.selectWindow(appID, preview.id)
                                    }
                                }
                                windowPreviewImageMarker(for: preview)
                            }
                            .id(preview.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)

                    if page.showsNavigationIndicators {
                        WindowPreviewPageIndicator(direction: .next, isVisible: page.hasNextPage)
                    }
                }
                .padding(.horizontal, 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .frame(height: previewSectionHeight)
            .background(
                SwitcherRenderMilestoneProbe(
                    milestone: .windowContent,
                    renderGeneration: windowRenderGeneration,
                    onDraw: onRenderMilestone
                )
            )
        }
    }

    @ViewBuilder
    private var standardOverlayBody: some View {
        VStack(alignment: .leading, spacing: SwitcherPanelLayoutMetrics.bodySpacing) {
            standardOverlaySearchHeader
            standardOverlayAppStrip
            standardOverlayPreviewSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SwitcherPanelLayoutMetrics.bodyHorizontalPadding)
        .padding(.vertical, SwitcherPanelLayoutMetrics.bodyVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(colorScheme == .dark ? Color.black : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }

    @ViewBuilder
    private var searchOverlayBody: some View {
        VStack(alignment: .leading, spacing: SwitcherPanelLayoutMetrics.bodySpacing) {
            SearchPresentationHeader(
                query: searchState.query,
                cursorPosition: searchState.queryCursorPosition,
                scope: searchState.scope,
                isInputFocused: searchState.isInputFocused,
                highlightedItem: searchHeaderHighlightItem,
                isSearchActive: searchState.isActive,
                language: appLanguage,
                onSearchInputChanged: onSearchInputChanged,
                onSearchMarkedTextChanged: onSearchMarkedTextChanged
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("flowtab.switcher.search")
            .background(SearchLayoutSizeReader(target: .header))
            .background(
                SwitcherRenderMilestoneProbe(
                    milestone: .searchShell,
                    renderGeneration: searchResultScrollRevision,
                    onDraw: onRenderMilestone
                )
            )

            if searchState.scope == .app {
                if searchAppItems.isEmpty {
                    SearchEmptyState(scope: .app, language: appLanguage)
                        .frame(height: searchResultViewportHeight)
                } else {
                    ScrollViewReader { scrollProxy in
                        let searchScrollProxy = SearchResultScrollProxy(proxy: scrollProxy)
                        let scrollRequest = searchResultScrollRequest
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(alignment: .leading, spacing: SwitcherPanelLayoutMetrics.Search.resultRowSpacing) {
                                ForEach(searchAppItems) { item in
                                    SearchAppRow(
                                        item: item,
                                        icon: iconForApp(item.app)
                                    )
                                    .id(item.id)
                                    .switcherPointerSelection(
                                        onClick: {
                                            pointerSelectionActions.commitSearchResult(item.id)
                                        }
                                    ) {
                                        pointerSelectionActions.selectSearchResult(item.id)
                                    }
                                    .background(SearchLayoutSizeReader(target: .row))
                                    .background {
                                        if item.id == searchAppItems.first?.id {
                                            SwitcherRenderMilestoneProbe(
                                                milestone: .searchFirstRow,
                                                renderGeneration:
                                                    searchResultScrollRevision,
                                                onDraw: onRenderMilestone
                                            )
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 2)
                            .padding(.vertical, SwitcherPanelLayoutMetrics.Search.resultListPadding)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .task(id: scrollRequest) { @MainActor in
                            scrollToSearchResult(scrollRequest, using: searchScrollProxy)
                        }
                    }
                    .frame(height: searchResultViewportHeight)
                }
            } else {
                if searchWindowItems.isEmpty {
                    SearchEmptyState(scope: .window, language: appLanguage)
                        .frame(height: searchResultViewportHeight)
                } else {
                    ScrollViewReader { scrollProxy in
                        let searchScrollProxy = SearchResultScrollProxy(proxy: scrollProxy)
                        let scrollRequest = searchResultScrollRequest
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(alignment: .leading, spacing: SwitcherPanelLayoutMetrics.Search.resultRowSpacing) {
                                ForEach(searchWindowItems) { item in
                                    SearchWindowRow(item: item)
                                        .id(item.id)
                                        .switcherPointerSelection(
                                            onClick: {
                                                pointerSelectionActions.commitSearchResult(item.id)
                                            }
                                        ) {
                                            pointerSelectionActions.selectSearchResult(item.id)
                                        }
                                        .background(SearchLayoutSizeReader(target: .row))
                                        .background {
                                            if item.id == searchWindowItems.first?.id {
                                                SwitcherRenderMilestoneProbe(
                                                    milestone: .searchFirstRow,
                                                    renderGeneration:
                                                        searchResultScrollRevision,
                                                    onDraw: onRenderMilestone
                                                )
                                            }
                                        }
                                }
                            }
                            .padding(.horizontal, 2)
                            .padding(.vertical, SwitcherPanelLayoutMetrics.Search.resultListPadding)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .task(id: scrollRequest) { @MainActor in
                            scrollToSearchResult(scrollRequest, using: searchScrollProxy)
                        }
                    }
                    .frame(height: searchResultViewportHeight)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, SwitcherPanelLayoutMetrics.bodyHorizontalPadding)
        .padding(.vertical, SwitcherPanelLayoutMetrics.bodyVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(colorScheme == .dark ? Color.black : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }

    @ViewBuilder
    private var windowOnlyOverlayBody: some View {
        GeometryReader { proxy in
            let layout = WindowOnlyGridLayout.resolve(
                availableSize: proxy.size,
                itemCount: windowPreviewItems.count
            )
            let selectedAppIcon = selectedApp.flatMap(iconForApp)
            let columns = Array(
                repeating: GridItem(
                    .fixed(layout.cardWidth),
                    spacing: layout.columnSpacing,
                    alignment: .top
                ),
                count: layout.columns
            )

            VStack(spacing: 0) {
                Spacer(minLength: layout.verticalPadding)
                LazyVGrid(
                    columns: columns,
                    alignment: .center,
                    spacing: layout.rowSpacing
                ) {
                    ForEach(windowPreviewItems) { preview in
                        ZStack(alignment: .topLeading) {
                            WindowOnlyPreviewCard(
                                image: preview.image,
                                title: preview.title,
                                appIcon: selectedAppIcon,
                                titleBarStyle: preview.titleBarStyle,
                                isSelected: preview.isSelected,
                                width: layout.cardWidth,
                                height: layout.cardHeight
                            )
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(preview.title))
                            .accessibilityValue(Text(switcherWindowAccessibilityValue(preview)))
                            .accessibilityIdentifier(switcherWindowAccessibilityIdentifier(preview))
                            .switcherPointerSelection(
                                isEnabled: selectedApp != nil,
                                onClick: {
                                    if let appID = selectedApp?.id {
                                        pointerSelectionActions.commitWindow(appID, preview.id)
                                    }
                                }
                            ) {
                                if let appID = selectedApp?.id {
                                    pointerSelectionActions.selectWindow(appID, preview.id)
                                }
                            }
                            windowPreviewImageMarker(for: preview)
                        }
                        .id(preview.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, layout.horizontalPadding)
                Spacer(minLength: layout.verticalPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .background(
            SwitcherRenderMilestoneProbe(
                milestone: .windowContent,
                renderGeneration: windowRenderGeneration,
                onDraw: onRenderMilestone
            )
        )
    }

    var body: some View {
        ExclusiveSwitcherOverlayHost(
            mode: activePresentationMode,
            contentForMode: overlayBody(for:)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var activePresentationMode: SwitcherOverlayPresentationMode? {
        guard isPresentationSessionActive else { return nil }
        if isWindowOnlyMode {
            return .windowOnly
        }
        if isSearchMode {
            return .search
        }
        return .standard
    }

    private func overlayBody(
        for mode: SwitcherOverlayPresentationMode
    ) -> AnyView {
        switch mode {
        case .windowOnly:
            return AnyView(windowOnlyOverlayBody)
        case .search:
            return AnyView(
                searchOverlayBody
                    .onPreferenceChange(
                        SearchLayoutMeasurementPreferenceKey.self
                    ) { measurement in
                        guard let measurements = measurement.measurements else {
                            return
                        }
                        onSearchLayoutMeasured(measurements)
                    }
            )
        case .standard:
            return AnyView(standardOverlayBody)
        }
    }
}
