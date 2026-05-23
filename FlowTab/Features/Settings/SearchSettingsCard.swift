import SwiftUI
import AppKit
import FlowTabCore

struct AppKitSearchSettingsCardContent: AppKitSettingsCardRepresentable {
    typealias NSViewType = SearchSettingsCardAppKitView

    @Binding var searchEnabled: Bool
    @Binding var searchDefaultScopeRaw: String

    final class Coordinator {
        var searchEnabled: Binding<Bool>
        var searchDefaultScopeRaw: Binding<String>

        init(searchEnabled: Binding<Bool>, searchDefaultScopeRaw: Binding<String>) {
            self.searchEnabled = searchEnabled
            self.searchDefaultScopeRaw = searchDefaultScopeRaw
        }

        func update(searchEnabled: Binding<Bool>, searchDefaultScopeRaw: Binding<String>) {
            self.searchEnabled = searchEnabled
            self.searchDefaultScopeRaw = searchDefaultScopeRaw
        }

        func setSearchEnabled(_ value: Bool) {
            searchEnabled.wrappedValue = value
        }

        func setSearchDefaultScope(rawValue: String) {
            searchDefaultScopeRaw.wrappedValue = rawValue
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(searchEnabled: $searchEnabled, searchDefaultScopeRaw: $searchDefaultScopeRaw)
    }

    func makeCardView(context _: Context) -> SearchSettingsCardAppKitView {
        SearchSettingsCardAppKitView()
    }

    func updateCoordinator(_ coordinator: Coordinator) {
        coordinator.update(searchEnabled: $searchEnabled, searchDefaultScopeRaw: $searchDefaultScopeRaw)
    }

    func connect(_ view: SearchSettingsCardAppKitView, coordinator: Coordinator) {
        view.onSearchEnabledChanged = { coordinator.setSearchEnabled($0) }
        view.onSearchDefaultScopeChanged = { coordinator.setSearchDefaultScope(rawValue: $0) }
    }

    func makeState() -> SearchSettingsCardState {
        SearchSettingsCardState(
            searchEnabled: searchEnabled,
            searchDefaultScopeRaw: searchDefaultScopeRaw
        )
    }
}

struct SearchSettingsCardState: Equatable {
    let searchEnabled: Bool
    let searchDefaultScopeRaw: String

    var resolvedScope: SwitcherSearchScope {
        SwitcherSearchScope(rawValue: searchDefaultScopeRaw) ?? SearchInteractionPreferencesStore.defaultScope
    }

    var summaryText: String {
        searchEnabled
            ? AppStrings.text(.searchSummaryEnabled)
            : AppStrings.text(.searchSummaryDisabled)
    }
}

final class SearchSettingsCardAppKitView: AppKitSettingsCardBaseView, AppKitSettingsCardStateView {
    var onSearchEnabledChanged: ((Bool) -> Void)?
    var onSearchDefaultScopeChanged: ((String) -> Void)?

    private let searchEnabledSwitch = NSSwitch()
    private let searchDefaultScopeSelect = FlowFormSelectControl(frame: .zero)
    private let scopeRowContainer = NSStackView()
    private let summaryLabel = AppKitSettingsCardBaseView.makeBodyLabel()
    private var isApplyingState = false
    private var currentState: SearchSettingsCardState?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy()
    }

    func update(with state: SearchSettingsCardState) {
        guard currentState != state else { return }
        currentState = state

        isApplyingState = true
        searchEnabledSwitch.state = state.searchEnabled ? .on : .off
        AppKitSettingsCardBaseView.selectItem(in: searchDefaultScopeSelect, rawValue: state.resolvedScope.rawValue)
        isApplyingState = false

        searchDefaultScopeSelect.isEnabled = state.searchEnabled
        scopeRowContainer.alphaValue = state.searchEnabled ? 1 : 0.5
        summaryLabel.stringValue = state.summaryText
        invalidateIntrinsicContentSize()
    }

    private func buildViewHierarchy() {
        searchEnabledSwitch.target = self
        searchEnabledSwitch.action = #selector(handleSearchEnabledChanged)
        searchEnabledSwitch.setFlowTabTestingIdentifier("flowtab.settings.search.enabled")
        searchDefaultScopeSelect.setFlowTabTestingIdentifier("flowtab.settings.search.default-scope")
        searchDefaultScopeSelect.onSelectionChanged = { [weak self] rawValue in
            self?.handleSearchDefaultScopeChanged(rawValue)
        }
        AppKitSettingsCardBaseView.configure(
            selectControl: searchDefaultScopeSelect,
            options: SwitcherSearchScope.allCases.map { (id: $0.rawValue, title: $0.label) },
            width: 68
        )

        let searchEnabledRow = AppKitSettingsCardBaseView.makeControlRow(
            title: AppStrings.text(.searchEnable),
            control: searchEnabledSwitch
        )
        scopeRowContainer.orientation = .vertical
        scopeRowContainer.alignment = .leading
        scopeRowContainer.spacing = 0
        scopeRowContainer.detachesHiddenViews = true
        scopeRowContainer.translatesAutoresizingMaskIntoConstraints = false
        scopeRowContainer.setContentHuggingPriority(.required, for: .vertical)
        scopeRowContainer.setContentCompressionResistancePriority(.required, for: .vertical)
        scopeRowContainer.addArrangedSubview(
            AppKitSettingsCardBaseView.makeControlRow(
                title: AppStrings.text(.searchDefaultScope),
                control: searchDefaultScopeSelect
            )
        )
        if let scopeRow = scopeRowContainer.arrangedSubviews.first {
            scopeRow.widthAnchor.constraint(equalTo: scopeRowContainer.widthAnchor).isActive = true
        }

        addFullWidthArrangedSubview(searchEnabledRow)
        addFullWidthArrangedSubview(scopeRowContainer)
        addFullWidthArrangedSubview(summaryLabel)
    }

    @objc private func handleSearchEnabledChanged(_ sender: NSSwitch) {
        guard !isApplyingState else { return }
        onSearchEnabledChanged?(sender.state == .on)
    }

    private func handleSearchDefaultScopeChanged(_ rawValue: String) {
        guard !isApplyingState else { return }
        onSearchDefaultScopeChanged?(rawValue)
    }
}
