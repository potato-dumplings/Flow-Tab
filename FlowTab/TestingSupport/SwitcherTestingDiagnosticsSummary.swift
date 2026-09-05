#if FLOWTAB_TESTING
import AppKit
import SwiftUI
import FlowTabCore

@MainActor
struct SwitcherTestingDiagnosticsSummary: View {
    @ObservedObject var model: LiveSwitcherModel
    var body: some View {
        if model.session != nil {
            summary
        }
    }

    private var summary: some View {
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
            "searchResultsScope=\(model.searchViewState.resultsScope?.rawValue ?? "none")",
            "searchResultsQuery=\(diagnosticsEscaped(model.searchViewState.resultsQuery ?? ""))",
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
    private static let diagnosticsAllowedCharacters: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }()
}
#endif
