import SwiftUI
import AppKit
import FlowTabCore

struct AppKitAppearanceSettingsCardContent: NSViewRepresentable {
    @Binding var showShortcutHint: Bool
    @Binding var showInCommandTab: Bool
    @Binding var themeModeRaw: String
    @Binding var appLanguageRaw: String

    final class Coordinator {
        var showShortcutHint: Binding<Bool>
        var showInCommandTab: Binding<Bool>
        var themeModeRaw: Binding<String>
        var appLanguageRaw: Binding<String>

        init(
            showShortcutHint: Binding<Bool>,
            showInCommandTab: Binding<Bool>,
            themeModeRaw: Binding<String>,
            appLanguageRaw: Binding<String>
        ) {
            self.showShortcutHint = showShortcutHint
            self.showInCommandTab = showInCommandTab
            self.themeModeRaw = themeModeRaw
            self.appLanguageRaw = appLanguageRaw
        }

        func update(
            showShortcutHint: Binding<Bool>,
            showInCommandTab: Binding<Bool>,
            themeModeRaw: Binding<String>,
            appLanguageRaw: Binding<String>
        ) {
            self.showShortcutHint = showShortcutHint
            self.showInCommandTab = showInCommandTab
            self.themeModeRaw = themeModeRaw
            self.appLanguageRaw = appLanguageRaw
        }

        func setShowShortcutHint(_ value: Bool) {
            showShortcutHint.wrappedValue = value
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
            showShortcutHint: $showShortcutHint,
            showInCommandTab: $showInCommandTab,
            themeModeRaw: $themeModeRaw,
            appLanguageRaw: $appLanguageRaw
        )
    }

    func makeNSView(context: Context) -> AppearanceSettingsCardAppKitView {
        let view = AppearanceSettingsCardAppKitView()
        connect(view, coordinator: context.coordinator)
        return view
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: AppearanceSettingsCardAppKitView,
        context: Context
    ) -> CGSize? {
        nsView.preferredFittingSize(forWidth: proposal.width)
    }

    func updateNSView(_ nsView: AppearanceSettingsCardAppKitView, context: Context) {
        context.coordinator.update(
            showShortcutHint: $showShortcutHint,
            showInCommandTab: $showInCommandTab,
            themeModeRaw: $themeModeRaw,
            appLanguageRaw: $appLanguageRaw
        )
        connect(nsView, coordinator: context.coordinator)
        nsView.update(
            with: AppearanceSettingsCardState(
                showShortcutHint: showShortcutHint,
                showInCommandTab: showInCommandTab,
                themeModeRaw: themeModeRaw,
                appLanguageRaw: appLanguageRaw
            )
        )
    }

    private func connect(_ view: AppearanceSettingsCardAppKitView, coordinator: Coordinator) {
        view.onShowShortcutHintChanged = { coordinator.setShowShortcutHint($0) }
        view.onShowInCommandTabChanged = { coordinator.setShowInCommandTab($0) }
        view.onThemeModeChanged = { coordinator.setThemeMode(rawValue: $0) }
        view.onAppLanguageChanged = { coordinator.setAppLanguage(rawValue: $0) }
    }
}

struct AppearanceSettingsCardState: Equatable {
    let showShortcutHint: Bool
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

final class AppearanceSettingsCardAppKitView: AppKitSettingsCardBaseView {
    var onShowShortcutHintChanged: ((Bool) -> Void)?
    var onShowInCommandTabChanged: ((Bool) -> Void)?
    var onThemeModeChanged: ((String) -> Void)?
    var onAppLanguageChanged: ((String) -> Void)?

    private let showShortcutHintSwitch = NSSwitch()
    private let showInCommandTabSwitch = NSSwitch()
    private let themeModeControl = FlowCapsuleSegmentedControl(
        options: AppearanceSettingsCardAppKitView.themeOptions()
    )
    private let appLanguageSelect = FlowFormSelectControl(frame: .zero)
    private let descriptionLabel = AppKitSettingsCardBaseView.makeBodyLabel()
    private var isApplyingState = false
    private var currentState: AppearanceSettingsCardState?

    private static func themeOptions() -> [(id: String, title: String)] {
        ThemeMode.allCases.map { (id: $0.rawValue, title: $0.displayName) }
    }

    private static func languageOptions() -> [(id: String, title: String)] {
        AppLanguage.allCases.map { (id: $0.rawValue, title: $0.displayName) }
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

        isApplyingState = true
        showShortcutHintSwitch.state = state.showShortcutHint ? .on : .off
        showInCommandTabSwitch.state = state.showInCommandTab ? .on : .off
        themeModeControl.updateSelection(id: state.resolvedThemeMode.rawValue)
        AppKitSettingsCardBaseView.selectItem(in: appLanguageSelect, rawValue: state.resolvedAppLanguage.rawValue)
        isApplyingState = false

        descriptionLabel.stringValue = AppStrings.text(.appearanceDescription)
        invalidateIntrinsicContentSize()
    }

    private func buildViewHierarchy() {
        showShortcutHintSwitch.target = self
        showShortcutHintSwitch.action = #selector(handleShowShortcutHintChanged)
        showInCommandTabSwitch.target = self
        showInCommandTabSwitch.action = #selector(handleShowInCommandTabChanged)
        showShortcutHintSwitch.setFlowTabTestingIdentifier("flowtab.settings.appearance.show-shortcut-hint")
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
            options: Self.languageOptions(),
            width: 96
        )

        addFullWidthArrangedSubview(
            AppKitSettingsCardBaseView.makeControlRow(
                title: AppStrings.text(.appearanceShowShortcutHint),
                control: showShortcutHintSwitch
            )
        )
        addFullWidthArrangedSubview(
            AppKitSettingsCardBaseView.makeControlRow(
                title: AppStrings.text(.appearanceShowAppWindow),
                control: showInCommandTabSwitch
            )
        )
        addFullWidthArrangedSubview(descriptionLabel)
        addFullWidthArrangedSubview(
            AppKitSettingsCardBaseView.makeControlRow(
                title: AppStrings.text(.appearanceLanguage),
                control: appLanguageSelect
            )
        )
        addFullWidthArrangedSubview(
            AppKitSettingsCardBaseView.makeControlRow(
                title: AppStrings.text(.appearanceThemeMode),
                control: themeModeControl
            )
        )
    }

    @objc private func handleShowShortcutHintChanged(_ sender: NSSwitch) {
        guard !isApplyingState else { return }
        onShowShortcutHintChanged?(sender.state == .on)
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
