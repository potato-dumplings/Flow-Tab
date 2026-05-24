import SwiftUI
import AppKit
import FlowTabCore

struct AppKitSearchSettingsCardContent: AppKitSettingsCardRepresentable {
    typealias NSViewType = SearchSettingsCardAppKitView

    @Binding var searchEnabled: Bool
    @Binding var searchDefaultScopeRaw: String
    let accessibilityTrusted: Bool

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
            searchDefaultScopeRaw: searchDefaultScopeRaw,
            appLanguageRaw: AppLanguagePreferencesStore.load().rawValue,
            accessibilityTrusted: accessibilityTrusted
        )
    }
}

struct SearchSettingsCardState: Equatable {
    let searchEnabled: Bool
    let searchDefaultScopeRaw: String
    let appLanguageRaw: String
    let accessibilityTrusted: Bool

    var language: AppLanguage {
        AppLanguagePreferencesStore.resolve(rawValue: appLanguageRaw)
    }

    var availableScopes: [SwitcherSearchScope] {
        SearchInteractionPreferencesStore.availableScopes(accessibilityTrusted: accessibilityTrusted)
    }

    var resolvedScope: SwitcherSearchScope {
        SearchInteractionPreferencesStore.effectiveDefaultScope(
            rawValue: searchDefaultScopeRaw,
            accessibilityTrusted: accessibilityTrusted
        )
    }

    var isScopeSelectEnabled: Bool {
        searchEnabled && availableScopes.count > 1
    }

    var summaryText: String {
        guard searchEnabled else {
            return AppStrings.text(.searchSummaryDisabled, language: language)
        }
        guard accessibilityTrusted else {
            return AppStrings.text(.searchSummaryAccessibilityRequired, language: language)
        }
        return AppStrings.text(.searchSummaryEnabled, language: language)
    }
}

final class SearchSettingsCardAppKitView: AppKitSettingsCardBaseView, AppKitSettingsCardStateView {
    var onSearchEnabledChanged: ((Bool) -> Void)?
    var onSearchDefaultScopeChanged: ((String) -> Void)?

    private let searchEnabledSwitch = NSSwitch()
    private let searchDefaultScopeSelect = FlowFormSelectControl(frame: .zero)
    private let scopeRowContainer = NSStackView()
    private lazy var searchEnabledRow = AppKitSettingsCardBaseView.makeControlRow(
        title: "",
        control: searchEnabledSwitch
    )
    private lazy var scopeRow = AppKitSettingsCardBaseView.makeControlRow(
        title: "",
        control: searchDefaultScopeSelect
    )
    private let summaryLabel = AppKitSettingsCardBaseView.makeBodyLabel()
    private var isApplyingState = false
    private var currentState: SearchSettingsCardState?

    private static func scopeOptions(
        scopes: [SwitcherSearchScope],
        language: AppLanguage
    ) -> [(id: String, title: String)] {
        scopes.map { scope in
            switch scope {
            case .app:
                return (id: scope.rawValue, title: AppStrings.text(.searchScopeApp, language: language))
            case .window:
                return (id: scope.rawValue, title: AppStrings.text(.searchScopeWindow, language: language))
            }
        }
    }

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
        searchDefaultScopeSelect.configure(
            options: Self.scopeOptions(scopes: state.availableScopes, language: state.language)
        )
        AppKitSettingsCardBaseView.selectItem(in: searchDefaultScopeSelect, rawValue: state.resolvedScope.rawValue)
        isApplyingState = false

        searchEnabledRow.updateTitle(AppStrings.text(.searchEnable, language: state.language))
        scopeRow.updateTitle(AppStrings.text(.searchDefaultScope, language: state.language))
        searchDefaultScopeSelect.isEnabled = state.isScopeSelectEnabled
        scopeRowContainer.alphaValue = state.isScopeSelectEnabled ? 1 : 0.5
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
            options: Self.scopeOptions(
                scopes: SwitcherSearchScope.allCases,
                language: AppLanguagePreferencesStore.load()
            ),
            width: 68
        )

        scopeRowContainer.orientation = .vertical
        scopeRowContainer.alignment = .leading
        scopeRowContainer.spacing = 0
        scopeRowContainer.detachesHiddenViews = true
        scopeRowContainer.translatesAutoresizingMaskIntoConstraints = false
        scopeRowContainer.setContentHuggingPriority(.required, for: .vertical)
        scopeRowContainer.setContentCompressionResistancePriority(.required, for: .vertical)
        scopeRowContainer.addArrangedSubview(scopeRow)
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
