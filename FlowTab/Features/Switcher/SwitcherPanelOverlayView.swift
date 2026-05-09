import AppKit
import SwiftUI
import FlowTabCore

struct SwitcherPanelRootView: View {
    @ObservedObject var model: LiveSwitcherModel
    @ObservedObject private var systemTheme = SystemThemeState.shared
    @AppStorage(AppPreferenceKeys.themeMode)
    private var themeModeRaw = ThemePreferencesStore.defaultMode.rawValue
    @AppStorage(AppPreferenceKeys.searchEnabled)
    private var searchEnabled = SearchInteractionPreferencesStore.defaultIsEnabled
    @AppStorage(AppPreferenceKeys.searchDefaultScope)
    private var searchDefaultScopeRaw = SearchInteractionPreferencesStore.defaultScope.rawValue
    @AppStorage(AppPreferenceKeys.appLanguage)
    private var appLanguageRaw = AppLanguagePreferencesStore.defaultLanguage.rawValue

    private var themeMode: ThemeMode {
        ThemePreferencesStore.resolve(rawValue: themeModeRaw)
    }

    private var resolvedColorScheme: ColorScheme {
        themeMode.resolvedColorScheme(systemColorScheme: systemTheme.colorScheme)
    }

    private var searchDefaultScope: SwitcherSearchScope {
        SwitcherSearchScope(rawValue: searchDefaultScopeRaw) ?? SearchInteractionPreferencesStore.defaultScope
    }

    var body: some View {
        ZStack {
            if let session = model.session {
                let windowPreviewItems = model.windowPreviewItems()
                CommandTabOverlay(
                    session: session,
                    overlayStyle: model.overlayStyle,
                    isPreviewLayer: model.isPreviewLayerMode,
                    previewSectionHeight: model.previewSectionHeight,
                    windowPreviewItems: windowPreviewItems,
                    searchState: model.searchViewState,
                    searchResultScrollRevision: model.searchResultScrollRevision,
                    searchAppItems: model.searchAppItems(),
                    searchWindowItems: model.searchWindowItems(),
                    onSearchInputChanged: { query, cursorPosition in
                        model.synchronizeSearchInput(query: query, cursorPosition: cursorPosition)
                    },
                    onSearchMarkedTextChanged: { hasMarkedText in
                        model.updateSearchInputMarkedTextState(hasMarkedText)
                    },
                    searchFeatureEnabled: searchEnabled,
                    searchDefaultScope: searchDefaultScope,
                    selectedApp: model.selectedApp,
                    terminatingAppID: model.terminatingAppID,
                    appTileSize: model.appGridTileSize,
                    appTileSpacing: model.appGridSpacing,
                    onSearchResultScrollRequested: { resultID in
                        model.recordSearchResultScrollRequestForTesting(resultID)
                    },
                    iconForApp: { app in
                        model.icon(for: app)
                    }
                )
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .preferredColorScheme(resolvedColorScheme)
        .animation(.none, value: resolvedColorScheme)
        .overlay(alignment: .topLeading) {
            if FlowTabTestLaunchOptions.showsSwitcherDiagnostics, model.session != nil {
                switcherDiagnosticsSummary
            }
        }
        .id(appLanguageRaw)
    }

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
        let previewSummary: String
        if case .windowCycle(let appID) = session.mode {
            let titles = model.windowPreviewItems().map(\.title).joined(separator: "|")
            previewSummary = "\(appID)::\(titles)"
        } else {
            previewSummary = "inactive"
        }
        let selectedWindow = session.selectedWindow

        return [
            "apps=\(appsSummary)",
            "selected=\(session.selectedApp.id)",
            "mode=\(session.mode.debugName)",
            "selectedWindow=\(selectedWindow?.id ?? "none")",
            "selectedWindowTitle=\(selectedWindow?.title ?? "")",
            "preview=\(previewSummary)"
        ].joined(separator: ";")
    }
}

private struct CommandTabOverlay: View {
    let session: SwitcherSession
    let overlayStyle: SwitcherOverlayStyle
    let isPreviewLayer: Bool
    let previewSectionHeight: CGFloat
    let windowPreviewItems: [WindowPreviewItem]
    let searchState: SwitcherSearchViewState
    let searchResultScrollRevision: UInt64
    let searchAppItems: [SearchAppResultItem]
    let searchWindowItems: [SearchWindowResultItem]
    let onSearchInputChanged: (String, Int) -> Void
    let onSearchMarkedTextChanged: (Bool) -> Void
    let searchFeatureEnabled: Bool
    let searchDefaultScope: SwitcherSearchScope
    let selectedApp: AppSwitchCandidate?
    let terminatingAppID: String?
    let appTileSize: CGFloat
    let appTileSpacing: CGFloat
    let onSearchResultScrollRequested: (String) -> Void
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

    private func previewCardWidth(availableWidth: CGFloat, itemCount: Int) -> CGFloat {
        let count = max(itemCount, 1)
        let spacing: CGFloat = 12
        let totalSpacing = spacing * CGFloat(max(count - 1, 0))
        let rawWidth = (availableWidth - totalSpacing) / CGFloat(count)
        return max(120, min(360, rawWidth))
    }

    private func previewCardHeight(for cardWidth: CGFloat) -> CGFloat {
        let maxHeight: CGFloat = showsAppStrip ? 220 : 248
        return max(130, min(maxHeight, cardWidth * 0.62))
    }

    private struct WindowOnlyGridLayout {
        let columns: Int
        let rows: Int
        let cardWidth: CGFloat
        let cardHeight: CGFloat
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let columnSpacing: CGFloat
        let rowSpacing: CGFloat
    }

    private func windowOnlyGridLayout(
        availableSize: CGSize,
        itemCount: Int
    ) -> WindowOnlyGridLayout {
        let count = max(itemCount, 1)
        let maxColumns = min(8, count)
        let minCardWidth: CGFloat = 120
        let titleBarHeight: CGFloat = 30
        let minPreviewHeight: CGFloat = 74
        let minCardHeight: CGFloat = titleBarHeight + minPreviewHeight
        let maxCardWidth: CGFloat = 460
        let previewAspectRatio: CGFloat = 1.58
        let columnSpacing: CGFloat = 24
        let rowSpacing: CGFloat = 28
        let horizontalPadding: CGFloat = max(14, min(64, availableSize.width * 0.04))
        let verticalPadding: CGFloat = max(12, min(52, availableSize.height * 0.05))
        let usableWidth = max(220, availableSize.width - horizontalPadding * 2)
        let usableHeight = max(160, availableSize.height - verticalPadding * 2)

        var bestLayout: (columns: Int, rows: Int, cardWidth: CGFloat, cardHeight: CGFloat, score: CGFloat)?

        for columns in 1...maxColumns {
            let rows = Int(ceil(Double(count) / Double(columns)))
            let totalColumnSpacing = CGFloat(max(columns - 1, 0)) * columnSpacing
            let totalRowSpacing = CGFloat(max(rows - 1, 0)) * rowSpacing
            let cellWidth = (usableWidth - totalColumnSpacing) / CGFloat(columns)
            let cellHeight = (usableHeight - totalRowSpacing) / CGFloat(rows)
            guard cellWidth > 0, cellHeight > 0 else { continue }

            var cardWidth = min(maxCardWidth, cellWidth)
            var cardHeight = cardWidth / previewAspectRatio + titleBarHeight

            if cardHeight > cellHeight {
                cardHeight = cellHeight
                cardWidth = max(1, (cardHeight - titleBarHeight) * previewAspectRatio)
            }
            guard cardWidth > 0, cardHeight > 0 else { continue }
            if cardWidth < minCardWidth || cardHeight < minCardHeight {
                continue
            }

            let score = cardWidth * cardHeight
            if let bestLayout, bestLayout.score >= score {
                continue
            }
            bestLayout = (columns, rows, cardWidth, cardHeight, score)
        }

        let resolved = bestLayout ?? {
            let columns = min(maxColumns, max(1, Int(round(sqrt(Double(count))))))
            let rows = Int(ceil(Double(count) / Double(columns)))
            let totalColumnSpacing = CGFloat(max(columns - 1, 0)) * columnSpacing
            let totalRowSpacing = CGFloat(max(rows - 1, 0)) * rowSpacing
            let cellWidth = max(1, (usableWidth - totalColumnSpacing) / CGFloat(columns))
            let cellHeight = max(1, (usableHeight - totalRowSpacing) / CGFloat(rows))
            let cardWidth = min(maxCardWidth, cellWidth)
            let cardHeight = min(cellHeight, cardWidth / previewAspectRatio + titleBarHeight)
            return (columns, rows, cardWidth, cardHeight, cardWidth * cardHeight)
        }()

        return WindowOnlyGridLayout(
            columns: resolved.columns,
            rows: resolved.rows,
            cardWidth: resolved.cardWidth,
            cardHeight: resolved.cardHeight,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            columnSpacing: columnSpacing,
            rowSpacing: rowSpacing
        )
    }

    private var selectedWindowPreviewID: String? {
        windowPreviewItems.first(where: \.isSelected)?.id
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
    private func scrollToSelectedPreview(using proxy: ScrollViewProxy) {
        guard let selectedWindowPreviewID else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo(selectedWindowPreviewID, anchor: .center)
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
                hintText: AppStrings.text(.panelHintEnterToSearch)
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
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var standardOverlayPreviewSection: some View {
        if isPreviewLayer {
            GeometryReader { proxy in
                let cardWidth = previewCardWidth(
                    availableWidth: max(0, proxy.size.width - 4),
                    itemCount: windowPreviewItems.count
                )
                let cardHeight = previewCardHeight(for: cardWidth)

                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(windowPreviewItems) { preview in
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
                                .accessibilityValue(Text(selectedApp?.displayName ?? ""))
                                .accessibilityIdentifier(switcherWindowAccessibilityIdentifier(preview))
                                .id(preview.id)
                            }
                        }
                        .padding(.horizontal, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onAppear {
                        scrollToSelectedPreview(using: scrollProxy)
                    }
                    .onChange(of: selectedWindowPreviewID) { _ in
                        scrollToSelectedPreview(using: scrollProxy)
                    }
                }
            }
            .frame(height: previewSectionHeight)
        }
    }

    @ViewBuilder
    private var standardOverlayBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            standardOverlaySearchHeader
            standardOverlayAppStrip
            standardOverlayPreviewSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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
        VStack(alignment: .leading, spacing: 12) {
            SearchPresentationHeader(
                query: searchState.query,
                cursorPosition: searchState.queryCursorPosition,
                scope: searchState.scope,
                isInputFocused: searchState.isInputFocused,
                highlightedItem: searchHeaderHighlightItem,
                isSearchActive: searchState.isActive,
                onSearchInputChanged: onSearchInputChanged,
                onSearchMarkedTextChanged: onSearchMarkedTextChanged
            )
            .accessibilityIdentifier("flowtab.switcher.search")

            if searchState.scope == .app {
                if searchAppItems.isEmpty {
                    SearchEmptyState(scope: .app)
                } else {
                    ScrollViewReader { scrollProxy in
                        let searchScrollProxy = SearchResultScrollProxy(proxy: scrollProxy)
                        let scrollRequest = searchResultScrollRequest
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(searchAppItems) { item in
                                    SearchAppRow(
                                        item: item,
                                        icon: iconForApp(item.app)
                                    )
                                    .id(item.id)
                                }
                            }
                            .padding(.horizontal, 2)
                            .padding(.vertical, 2)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .task(id: scrollRequest) { @MainActor in
                            scrollToSearchResult(scrollRequest, using: searchScrollProxy)
                        }
                    }
                }
            } else {
                if searchWindowItems.isEmpty {
                    SearchEmptyState(scope: .window)
                } else {
                    ScrollViewReader { scrollProxy in
                        let searchScrollProxy = SearchResultScrollProxy(proxy: scrollProxy)
                        let scrollRequest = searchResultScrollRequest
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(searchWindowItems) { item in
                                    SearchWindowRow(item: item)
                                        .id(item.id)
                                }
                            }
                            .padding(.horizontal, 2)
                            .padding(.vertical, 2)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .task(id: scrollRequest) { @MainActor in
                            scrollToSearchResult(scrollRequest, using: searchScrollProxy)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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
            let layout = windowOnlyGridLayout(
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
                        .accessibilityValue(Text(selectedApp?.displayName ?? ""))
                        .accessibilityIdentifier(switcherWindowAccessibilityIdentifier(preview))
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
    }
}
