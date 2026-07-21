import AppKit
import SwiftUI
import FlowTabCore

struct SwitcherPanelRootView: View {
    @ObservedObject var model: LiveSwitcherModel
    let pointerSelectionActions: SwitcherPointerSelectionActions
    @ObservedObject private var presentation = FlowPresentationState.shared
    @AppStorage(AppPreferenceKeys.searchEnabled)
    private var searchEnabled = SearchInteractionPreferencesStore.defaultIsEnabled
    @AppStorage(AppPreferenceKeys.searchDefaultScope)
    private var searchDefaultScopeRaw = SearchInteractionPreferencesStore.defaultScope.rawValue

    private var searchDefaultScope: SwitcherSearchScope {
        SwitcherSearchScope(rawValue: searchDefaultScopeRaw) ?? SearchInteractionPreferencesStore.defaultScope
    }

    var body: some View {
        ZStack {
            if let session = model.session {
                let windowPreviewItems = model.overlayStyle == .windowOnly
                    ? model.windowPreviewItems()
                    : []
                CommandTabOverlay(
                    session: session,
                    overlayStyle: model.overlayStyle,
                    isPreviewLayer: model.isPreviewLayerMode,
                    previewSectionHeight: model.previewSectionHeight,
                    windowPreviewItems: windowPreviewItems,
                    standardWindowPreviewSummary: model.windowPreviewPageSummary(),
                    standardWindowPreviewItemsForRange: { range in
                        model.windowPreviewItems(visibleRange: range)
                    },
                    searchState: model.searchViewState,
                    searchResultScrollRevision: model.searchResultScrollRevision,
                    searchLayoutMeasurements: model.searchLayoutMeasurements,
                    searchAppItems: model.searchAppItems(),
                    searchWindowItems: model.searchWindowItems(),
                    onSearchInputChanged: { query, cursorPosition in
                        model.synchronizeSearchInput(query: query, cursorPosition: cursorPosition)
                    },
                    onSearchMarkedTextChanged: { hasMarkedText in
                        model.updateSearchInputMarkedTextState(hasMarkedText)
                    },
                    onSearchLayoutMeasured: { measurements in
                        Task { @MainActor in
                            model.updateSearchLayoutMeasurements(measurements)
                        }
                    },
                    searchFeatureEnabled: searchEnabled,
                    searchDefaultScope: searchDefaultScope,
                    appLanguage: presentation.context.appLanguage,
                    selectedApp: model.selectedApp,
                    terminatingAppID: model.terminatingAppID,
                    appTileSize: model.appGridTileSize,
                    appTileSpacing: model.appGridSpacing,
                    onSearchResultScrollRequested: { resultID in
                        model.recordSearchResultScrollRequestForTesting(resultID)
                    },
                    pointerSelectionActions: pointerSelectionActions,
                    iconForApp: { app in
                        model.icon(for: app)
                    }
                )
                .onAppear {
                    Self.logContentTrace(
                        phase: "contentAppear",
                        session: session,
                        overlayStyle: model.overlayStyle,
                        windowPreviewItems: windowPreviewItems,
                        searchActive: model.searchViewState.isActive
                    )
                }
                .onChange(
                    of: Self.contentTraceSummary(
                        session: session,
                        overlayStyle: model.overlayStyle,
                        windowPreviewItems: windowPreviewItems,
                        searchActive: model.searchViewState.isActive
                    )
                ) { summary in
                    Self.logContentTrace(
                        phase: "contentUpdate",
                        overlayStyle: model.overlayStyle,
                        summary: summary
                    )
                }
                .padding(SwitcherPanelLayoutMetrics.rootPadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .preferredColorScheme(presentation.context.resolvedColorScheme)
        .animation(.none, value: presentation.context.resolvedColorScheme)
#if FLOWTAB_TESTING
        .overlay(alignment: .topLeading) {
            if FlowTabTestLaunchOptions.showsSwitcherDiagnostics, model.session != nil {
                switcherDiagnosticsSummary
            }
        }
#endif
        .id(presentation.context.appLanguage.rawValue)
    }

#if FLOWTAB_TESTING
    private var switcherDiagnosticsSummary: some View {
        let value = switcherDiagnosticsValue
        return Text(verbatim: value)
            .font(.system(size: 4))
            .lineLimit(1)
            .foregroundStyle(Color.black.opacity(0.015))
            .frame(minWidth: 16, minHeight: 8, alignment: .topLeading)
            .padding(.leading, 1)
            .padding(.top, 1)
            .allowsHitTesting(false)
            .accessibilityIdentifier(SwitcherAccessibilityIdentifiers.testingSummary)
            .accessibilityLabel(Text(verbatim: value))
            .accessibilityValue(Text(verbatim: value))
            .accessibilityHidden(false)
    }

    private var switcherDiagnosticsValue: String {
        guard FlowTabTestLaunchOptions.showsSwitcherDiagnostics,
              let session = model.session else { return "" }

        let appsSummary = session.apps
            .map { "\($0.id):\($0.windows.count)" }
            .joined(separator: "|")
        let previewItems: [WindowPreviewItem]
        let previewSummary: String
        if case .windowCycle(let appID) = session.mode {
            previewItems = model.windowPreviewItems()
            let titles = previewItems.map(\.title).joined(separator: "|")
            previewSummary = "\(appID)::\(titles)"
        } else {
            previewItems = []
            previewSummary = "inactive"
        }
        let selectedWindow = session.selectedWindow
        let searchIndexDiagnosticsFields = (
            model.lastSearchIndexReadDiagnostic?.searchTraceFields
                ?? [
                    "searchIndexReadiness=none",
                    "searchIndexResultState=none",
                    "searchIndexDegraded=0",
                    "searchIndexCoversCurrentGeneration=0",
                    "searchFreshnessBarrierRequested=0"
                ].joined(separator: " ")
        )
        .split(separator: " ")
        .map(String.init)

        return ([
            "apps=\(appsSummary)",
            "selected=\(session.selectedApp.id)",
            "mode=\(session.mode.debugName)",
            "selectedWindow=\(selectedWindow?.id ?? "none")",
            "selectedWindowTitle=\(selectedWindow?.title ?? "")",
            "preview=\(previewSummary)",
            "previewImages=\(previewItems.filter { $0.image != nil }.count)",
            "searchScope=\(model.searchViewState.isActive ? model.searchViewState.scope.rawValue : "inactive")",
            "searchSelectedResult=\(diagnosticsEscaped(model.searchViewState.selectedResult?.id ?? "none"))",
            "searchResults=\(searchResultsDiagnosticsSummary)"
        ] + searchIndexDiagnosticsFields).joined(separator: ";")
    }

    private var searchResultsDiagnosticsSummary: String {
        guard model.searchViewState.isActive else { return "inactive" }
        return model.searchViewState.results
            .map { result in
                let kindFields: [String]
                switch result.kind {
                case .app(let appID):
                    kindFields = ["app", diagnosticsEscaped(appID), ""]
                case .window(let appID, let windowID):
                    kindFields = ["window", diagnosticsEscaped(appID), diagnosticsEscaped(windowID)]
                }
                return ([
                    diagnosticsEscaped(result.id)
                ] + kindFields + [
                    diagnosticsEscaped(result.primaryText),
                    diagnosticsEscaped(result.secondaryText ?? "")
                ]).joined(separator: ",")
            }
            .joined(separator: "|")
    }

    private func diagnosticsEscaped(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: Self.diagnosticsAllowedCharacters) ?? ""
    }
#endif

    private static func logContentTrace(
        phase: String,
        session: SwitcherSession,
        overlayStyle: SwitcherOverlayStyle,
        windowPreviewItems: [WindowPreviewItem],
        searchActive: Bool
    ) {
        logContentTrace(
            phase: phase,
            overlayStyle: overlayStyle,
            summary: contentTraceSummary(
                session: session,
                overlayStyle: overlayStyle,
                windowPreviewItems: windowPreviewItems,
                searchActive: searchActive
            )
        )
    }

    private static func logContentTrace(
        phase: String,
        overlayStyle: SwitcherOverlayStyle,
        summary: String
    ) {
        let nowMs = formatContentTraceMilliseconds(ProcessInfo.processInfo.systemUptime * 1_000)
        RuntimeLog.debug(
            "InputTrace",
            "show kind=\(overlayStyle.contentTraceKind) phase=\(phase) nowMs=\(nowMs) \(summary)"
        )
    }

    private static func contentTraceSummary(
        session: SwitcherSession,
        overlayStyle: SwitcherOverlayStyle,
        windowPreviewItems: [WindowPreviewItem],
        searchActive: Bool
    ) -> String {
        let previewImageCount = windowPreviewItems.reduce(0) { count, item in
            count + (item.image == nil ? 0 : 1)
        }
        return [
            "overlay=\(overlayStyle.debugName)",
            "mode=\(session.mode.debugName)",
            "selectedAppID=\(session.selectedApp.id)",
            "selectedWindows=\(session.selectedApp.windows.count)",
            "selectedWindowID=\(session.selectedWindow?.id ?? "none")",
            "previewItems=\(windowPreviewItems.count)",
            "previewImages=\(previewImageCount)",
            "searchActive=\(searchActive ? 1 : 0)"
        ].joined(separator: " ")
    }

    private static func formatContentTraceMilliseconds(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

#if FLOWTAB_TESTING
    private static let diagnosticsAllowedCharacters: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }()
#endif
}

private struct CommandTabOverlay: View {
    let session: SwitcherSession
    let overlayStyle: SwitcherOverlayStyle
    let isPreviewLayer: Bool
    let previewSectionHeight: CGFloat
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

    private func switcherAppAccessibilityIdentifier(_ app: AppSwitchCandidate) -> String {
        SwitcherAccessibilityIdentifiers.app(id: app.id)
    }

    private func switcherAppAccessibilityValue(_ app: AppSwitchCandidate) -> String {
        "\(app.id), \(app.windows.count)w"
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
        let appIDs = session.apps.map(\.id)
        return HStack(alignment: .center, spacing: appTileSpacing) {
            ForEach(Array(session.apps.enumerated()), id: \.element.id) { index, app in
                AppTileView(
                    app: app,
                    isSelected: index == session.selectedAppIndex,
                    isTerminating: app.id == terminatingAppID,
                    size: appTileSize,
                    icon: iconForApp(app),
                    accessibilityIdentifier: switcherAppAccessibilityIdentifier(app),
                    accessibilityLabel: app.displayName,
                    accessibilityValue: switcherAppAccessibilityValue(app)
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(app.displayName))
                .accessibilityValue(Text(switcherAppAccessibilityValue(app)))
                .accessibilityIdentifier(switcherAppAccessibilityIdentifier(app))
                .transition(.appQuitRemoval)
            }
        }
        .animation(
            session.apps.count <= 16 ? .easeOut(duration: 0.14) : nil,
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
    }

    var body: some View {
        Group {
            if isWindowOnlyMode {
                windowOnlyOverlayBody
            } else if isSearchMode {
                searchOverlayBody
            } else {
                standardOverlayBody
            }
        }
        .onPreferenceChange(SearchLayoutMeasurementPreferenceKey.self) { measurement in
            guard let measurements = measurement.measurements else { return }
            onSearchLayoutMeasured(measurements)
        }
    }
}
