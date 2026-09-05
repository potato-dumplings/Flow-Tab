import AppKit
import SwiftUI
import FlowTabCore

struct SwitcherPanelRootView: View {
    @ObservedObject var model: LiveSwitcherModel
    let pointerSelectionActions: SwitcherPointerSelectionActions
    let onRenderPreparation:
        (SwitcherRenderMilestonePreparation) -> Void
    let onRenderMilestone: (SwitcherRenderMilestoneEvent) -> Void
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
            if let renderSnapshot = model.appLayerRenderSnapshot {
                let session = model.session
                let windowPreviewItems = model.overlayStyle == .windowOnly
                    ? model.windowPreviewItems()
                    : []
                CommandTabOverlay(
                    appRenderSnapshot: renderSnapshot,
                    overlayStyle: model.overlayStyle,
                    isPresentationSessionActive: session != nil,
                    isPreviewLayer: model.isPreviewLayerMode,
                    previewSectionHeight: model.previewSectionHeight,
                    windowRenderGeneration:
                        model.selectedAppWindowProjectionGeneration,
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
                    onRenderPreparation: onRenderPreparation,
                    onRenderMilestone: onRenderMilestone,
                    iconForApp: { app in
                        model.icon(for: app)
                    }
                )
                .onAppear {
                    if let session {
                        Self.logContentTrace(
                            phase: "contentAppear",
                            session: session,
                            overlayStyle: model.overlayStyle,
                            windowPreviewItems: windowPreviewItems,
                            searchActive: model.searchViewState.isActive
                        )
                    }
                }
                .padding(SwitcherPanelLayoutMetrics.rootPadding)
                .opacity(session == nil ? 0 : 1)
                .allowsHitTesting(session != nil)
                .accessibilityHidden(session == nil)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .preferredColorScheme(presentation.context.resolvedColorScheme)
        .animation(.none, value: presentation.context.resolvedColorScheme)
        .id(presentation.context.appLanguage.rawValue)
    }


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

}
