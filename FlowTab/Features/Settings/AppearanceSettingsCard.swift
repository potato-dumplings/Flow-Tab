import SwiftUI
import AppKit
import FlowTabCore

struct AppKitAppearanceSettingsCardContent: AppKitSettingsCardRepresentable {
    typealias NSViewType = AppearanceSettingsCardAppKitView

    @Binding var showInCommandTab: Bool
    @Binding var themeModeRaw: String
    @Binding var appLanguageRaw: String

    final class Coordinator {
        var showInCommandTab: Binding<Bool>
        var themeModeRaw: Binding<String>
        var appLanguageRaw: Binding<String>

        init(
            showInCommandTab: Binding<Bool>,
            themeModeRaw: Binding<String>,
            appLanguageRaw: Binding<String>
        ) {
            self.showInCommandTab = showInCommandTab
            self.themeModeRaw = themeModeRaw
            self.appLanguageRaw = appLanguageRaw
        }

        func update(
            showInCommandTab: Binding<Bool>,
            themeModeRaw: Binding<String>,
            appLanguageRaw: Binding<String>
        ) {
            self.showInCommandTab = showInCommandTab
            self.themeModeRaw = themeModeRaw
            self.appLanguageRaw = appLanguageRaw
        }

        func setShowInCommandTab(_ value: Bool) {
            showInCommandTab.wrappedValue = value
        }

        func setThemeMode(rawValue: String) {
            themeModeRaw.wrappedValue = rawValue
        }

        func setAppLanguage(rawValue: String) {
            appLanguageRaw.wrappedValue = rawValue
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            showInCommandTab: $showInCommandTab,
            themeModeRaw: $themeModeRaw,
            appLanguageRaw: $appLanguageRaw
        )
    }

    func makeCardView(context _: Context) -> AppearanceSettingsCardAppKitView {
        AppearanceSettingsCardAppKitView()
    }

    func updateCoordinator(_ coordinator: Coordinator) {
        coordinator.update(
            showInCommandTab: $showInCommandTab,
            themeModeRaw: $themeModeRaw,
            appLanguageRaw: $appLanguageRaw
        )
    }

    func connect(_ view: AppearanceSettingsCardAppKitView, coordinator: Coordinator) {
        view.onShowInCommandTabChanged = { coordinator.setShowInCommandTab($0) }
        view.onThemeModeChanged = { coordinator.setThemeMode(rawValue: $0) }
        view.onAppLanguageChanged = { coordinator.setAppLanguage(rawValue: $0) }
    }

    func makeState() -> AppearanceSettingsCardState {
        AppearanceSettingsCardState(
            showInCommandTab: showInCommandTab,
            themeModeRaw: themeModeRaw,
            appLanguageRaw: appLanguageRaw
        )
    }
}

struct AppearanceSettingsCardState: Equatable {
    let showInCommandTab: Bool
    let themeModeRaw: String
    let appLanguageRaw: String

    var resolvedThemeMode: ThemeMode {
        ThemePreferencesStore.resolve(rawValue: themeModeRaw)
    }

    var resolvedAppLanguage: AppLanguage {
        AppLanguagePreferencesStore.resolve(rawValue: appLanguageRaw)
    }
}

final class AppearanceSettingsCardAppKitView: AppKitSettingsCardBaseView, AppKitSettingsCardStateView {
    var onShowInCommandTabChanged: ((Bool) -> Void)?
    var onThemeModeChanged: ((String) -> Void)?
    var onAppLanguageChanged: ((String) -> Void)?

    private let showInCommandTabSwitch = NSSwitch()
    private let themeModeControl = FlowSettingsSegmentedControl(
        options: AppearanceSettingsCardAppKitView.themeOptions(
            language: AppLanguagePreferencesStore.load()
        )
    )
    private let appLanguageSelect = FlowSettingsSelectControl(frame: .zero)
    private let descriptionLabel = AppKitSettingsCardBaseView.makeBodyLabel()
    private lazy var showInCommandTabRow = AppKitSettingsCardBaseView.makeControlRow(
        title: "",
        control: showInCommandTabSwitch
    )
    private lazy var languageRow = AppKitSettingsCardBaseView.makeControlRow(
        title: "",
        control: appLanguageSelect
    )
    private lazy var themeModeRow = AppKitSettingsCardBaseView.makeControlRow(
        title: "",
        control: themeModeControl
    )
    private var isApplyingState = false
    private var currentState: AppearanceSettingsCardState?

    private static func themeOptions(language: AppLanguage) -> [(id: String, title: String)] {
        ThemeMode.allCases.map { mode in
            let key: AppStringKey
            switch mode {
            case .followSystem:
                key = .themeFollowSystem
            case .light:
                key = .themeLight
            case .dark:
                key = .themeDark
            }
            return (id: mode.rawValue, title: AppStrings.text(key, language: language))
        }
    }

    private static func languageOptions(language: AppLanguage) -> [(id: String, title: String)] {
        AppLanguage.allCases.map { languageOption in
            let key: AppStringKey
            switch languageOption {
            case .simplifiedChinese:
                key = .languageSimplifiedChinese
            case .english:
                key = .languageEnglish
            }
            return (id: languageOption.rawValue, title: AppStrings.text(key, language: language))
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

    func update(with state: AppearanceSettingsCardState) {
        guard currentState != state else { return }
        currentState = state
        let language = state.resolvedAppLanguage

        isApplyingState = true
        showInCommandTabSwitch.state = state.showInCommandTab ? .on : .off
        themeModeControl.configure(options: Self.themeOptions(language: language))
        appLanguageSelect.configure(options: Self.languageOptions(language: language))
        themeModeControl.updateSelection(id: state.resolvedThemeMode.rawValue)
        AppKitSettingsCardBaseView.selectItem(in: appLanguageSelect, rawValue: state.resolvedAppLanguage.rawValue)
        isApplyingState = false

        showInCommandTabRow.updateTitle(AppStrings.text(.appearanceShowAppWindow, language: language))
        languageRow.updateTitle(AppStrings.text(.appearanceLanguage, language: language))
        themeModeRow.updateTitle(AppStrings.text(.appearanceThemeMode, language: language))
        descriptionLabel.stringValue = AppStrings.text(.appearanceDescription, language: language)
        invalidateIntrinsicContentSize()
    }

    private func buildViewHierarchy() {
        showInCommandTabSwitch.target = self
        showInCommandTabSwitch.action = #selector(handleShowInCommandTabChanged)
        showInCommandTabSwitch.setFlowTabTestingIdentifier("flowtab.settings.appearance.show-in-command-tab")
        themeModeControl.setFlowTabTestingIdentifier("flowtab.settings.appearance.theme-mode")
        appLanguageSelect.setFlowTabTestingIdentifier("flowtab.settings.appearance.app-language")
        themeModeControl.translatesAutoresizingMaskIntoConstraints = false
        themeModeControl.onSelectionChanged = { [weak self] rawValue in
            self?.handleThemeModeChanged(rawValue)
        }
        AppKitSettingsCardBaseView.applyPreferredControlWidth(themeModeControl, width: 300)
        appLanguageSelect.onSelectionChanged = { [weak self] rawValue in
            self?.handleAppLanguageChanged(rawValue)
        }
        AppKitSettingsCardBaseView.configure(
            selectControl: appLanguageSelect,
            options: Self.languageOptions(language: AppLanguagePreferencesStore.load())
        )

        addFullWidthArrangedSubview(showInCommandTabRow)
        addFullWidthArrangedSubview(descriptionLabel)
        addFullWidthArrangedSubview(languageRow)
        addFullWidthArrangedSubview(themeModeRow)
    }

    @objc private func handleShowInCommandTabChanged(_ sender: NSSwitch) {
        guard !isApplyingState else { return }
        onShowInCommandTabChanged?(sender.state == .on)
    }

    private func handleThemeModeChanged(_ rawValue: String) {
        guard !isApplyingState else { return }
        onThemeModeChanged?(rawValue)
    }

    private func handleAppLanguageChanged(_ rawValue: String) {
        guard !isApplyingState else { return }
        onAppLanguageChanged?(rawValue)
    }
}
