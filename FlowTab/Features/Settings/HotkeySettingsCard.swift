import SwiftUI
import AppKit
import FlowTabCore

struct AppKitHotkeySettingsCardContent: AppKitSettingsCardRepresentable {
    typealias NSViewType = HotkeySettingsCardAppKitView

    @Binding var hotkeyPrimaryModifierRaw: String
    @Binding var hotkeyMainKeyRaw: String
    @Binding var hotkeyQuitKeyRaw: String
    @Binding var inAppWindowHotkeyPrimaryModifierRaw: String
    @Binding var inAppWindowHotkeyMainKeyRaw: String
    let commandTabTakeoverRegistrationState: CommandTabTakeoverRegistrationState
    let accessibilityTrusted: Bool

    final class Coordinator {
        var hotkeyPrimaryModifierRaw: Binding<String>
        var hotkeyMainKeyRaw: Binding<String>
        var hotkeyQuitKeyRaw: Binding<String>
        var inAppWindowHotkeyPrimaryModifierRaw: Binding<String>
        var inAppWindowHotkeyMainKeyRaw: Binding<String>

        init(
            hotkeyPrimaryModifierRaw: Binding<String>,
            hotkeyMainKeyRaw: Binding<String>,
            hotkeyQuitKeyRaw: Binding<String>,
            inAppWindowHotkeyPrimaryModifierRaw: Binding<String>,
            inAppWindowHotkeyMainKeyRaw: Binding<String>
        ) {
            self.hotkeyPrimaryModifierRaw = hotkeyPrimaryModifierRaw
            self.hotkeyMainKeyRaw = hotkeyMainKeyRaw
            self.hotkeyQuitKeyRaw = hotkeyQuitKeyRaw
            self.inAppWindowHotkeyPrimaryModifierRaw = inAppWindowHotkeyPrimaryModifierRaw
            self.inAppWindowHotkeyMainKeyRaw = inAppWindowHotkeyMainKeyRaw
        }

        func update(
            hotkeyPrimaryModifierRaw: Binding<String>,
            hotkeyMainKeyRaw: Binding<String>,
            hotkeyQuitKeyRaw: Binding<String>,
            inAppWindowHotkeyPrimaryModifierRaw: Binding<String>,
            inAppWindowHotkeyMainKeyRaw: Binding<String>
        ) {
            self.hotkeyPrimaryModifierRaw = hotkeyPrimaryModifierRaw
            self.hotkeyMainKeyRaw = hotkeyMainKeyRaw
            self.hotkeyQuitKeyRaw = hotkeyQuitKeyRaw
            self.inAppWindowHotkeyPrimaryModifierRaw = inAppWindowHotkeyPrimaryModifierRaw
            self.inAppWindowHotkeyMainKeyRaw = inAppWindowHotkeyMainKeyRaw
        }

        func setHotkeyPrimaryModifier(_ rawValue: String) {
            hotkeyPrimaryModifierRaw.wrappedValue = rawValue
        }

        func setHotkeyMainKey(_ rawValue: String) {
            hotkeyMainKeyRaw.wrappedValue = rawValue
        }

        func setHotkeyQuitKey(_ rawValue: String) {
            hotkeyQuitKeyRaw.wrappedValue = rawValue
        }

        func setInAppWindowPrimaryModifier(_ rawValue: String) {
            inAppWindowHotkeyPrimaryModifierRaw.wrappedValue = rawValue
        }

        func setInAppWindowMainKey(_ rawValue: String) {
            inAppWindowHotkeyMainKeyRaw.wrappedValue = rawValue
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            hotkeyPrimaryModifierRaw: $hotkeyPrimaryModifierRaw,
            hotkeyMainKeyRaw: $hotkeyMainKeyRaw,
            hotkeyQuitKeyRaw: $hotkeyQuitKeyRaw,
            inAppWindowHotkeyPrimaryModifierRaw: $inAppWindowHotkeyPrimaryModifierRaw,
            inAppWindowHotkeyMainKeyRaw: $inAppWindowHotkeyMainKeyRaw
        )
    }

    func makeCardView(context _: Context) -> HotkeySettingsCardAppKitView {
        HotkeySettingsCardAppKitView()
    }

    func updateCoordinator(_ coordinator: Coordinator) {
        coordinator.update(
            hotkeyPrimaryModifierRaw: $hotkeyPrimaryModifierRaw,
            hotkeyMainKeyRaw: $hotkeyMainKeyRaw,
            hotkeyQuitKeyRaw: $hotkeyQuitKeyRaw,
            inAppWindowHotkeyPrimaryModifierRaw: $inAppWindowHotkeyPrimaryModifierRaw,
            inAppWindowHotkeyMainKeyRaw: $inAppWindowHotkeyMainKeyRaw
        )
    }

    func connect(_ view: HotkeySettingsCardAppKitView, coordinator: Coordinator) {
        view.onHotkeyPrimaryModifierChanged = { coordinator.setHotkeyPrimaryModifier($0) }
        view.onHotkeyMainKeyChanged = { coordinator.setHotkeyMainKey($0) }
        view.onHotkeyQuitKeyChanged = { coordinator.setHotkeyQuitKey($0) }
        view.onInAppWindowPrimaryModifierChanged = { coordinator.setInAppWindowPrimaryModifier($0) }
        view.onInAppWindowMainKeyChanged = { coordinator.setInAppWindowMainKey($0) }
    }

    func makeState() -> HotkeySettingsCardState {
        HotkeySettingsCardState(
            hotkeyPrimaryModifierRaw: hotkeyPrimaryModifierRaw,
            hotkeyMainKeyRaw: hotkeyMainKeyRaw,
            hotkeyQuitKeyRaw: hotkeyQuitKeyRaw,
            inAppWindowHotkeyPrimaryModifierRaw: inAppWindowHotkeyPrimaryModifierRaw,
            inAppWindowHotkeyMainKeyRaw: inAppWindowHotkeyMainKeyRaw,
            commandTabTakeoverRegistrationState: commandTabTakeoverRegistrationState,
            accessibilityTrusted: accessibilityTrusted,
            appLanguageRaw: AppLanguagePreferencesStore.load().rawValue
        )
    }
}

struct HotkeySettingsCardState: Equatable {
    let hotkeyPrimaryModifierRaw: String
    let hotkeyMainKeyRaw: String
    let hotkeyQuitKeyRaw: String
    let inAppWindowHotkeyPrimaryModifierRaw: String
    let inAppWindowHotkeyMainKeyRaw: String
    let commandTabTakeoverRegistrationState: CommandTabTakeoverRegistrationState
    let accessibilityTrusted: Bool
    let appLanguageRaw: String
    var hotkeyConflict: HotkeySettingsConflictPresentation? = nil

    var language: AppLanguage {
        AppLanguagePreferencesStore.resolve(rawValue: appLanguageRaw)
    }

    var hotkeyConfiguration: SwitcherHotkeyConfiguration {
        SwitcherHotkeyPreferencesStore.resolve(
            primaryModifierRaw: hotkeyPrimaryModifierRaw,
            mainKeyRaw: hotkeyMainKeyRaw,
            quitKeyRaw: hotkeyQuitKeyRaw
        )
    }

    var inAppWindowHotkeyConfiguration: SwitcherHotkeyConfiguration {
        let resolved = InAppWindowHotkeyPreferencesStore.resolve(
            primaryModifierRaw: inAppWindowHotkeyPrimaryModifierRaw,
            mainKeyRaw: inAppWindowHotkeyMainKeyRaw
        )
        return SwitcherHotkeyConfiguration(
            primaryModifier: resolved.primaryModifier,
            mainKey: resolved.mainKey,
            quitKey: .q
        )
    }

    var mainUsesCommandTab: Bool {
        hotkeyConfiguration.primaryModifier == .command && hotkeyConfiguration.mainKey == .tab
    }

    var inAppUsesCommandTab: Bool {
        inAppWindowHotkeyConfiguration.primaryModifier == .command
            && inAppWindowHotkeyConfiguration.mainKey == .tab
    }

    var mainSummaryText: String {
        AppStrings.text(
            .hotkeyMainSummary,
            replacements: [
                "main": hotkeyConfiguration.mainShortcutText,
                "reverseLabel": AppStrings.text(.hotkeySummaryReverseLabel, language: language),
                "reverse": hotkeyConfiguration.backwardShortcutText,
                "quitLabel": AppStrings.text(.hotkeySummaryQuitLabel, language: language),
                "quit": hotkeyConfiguration.quitShortcutText
            ],
            language: language
        )
    }

    var inAppSummaryText: String {
        AppStrings.text(
            .hotkeyInAppSummary,
            replacements: [
                "inAppLabel": AppStrings.text(.hotkeySummaryInAppLabel, language: language),
                "main": inAppWindowHotkeyConfiguration.mainShortcutText,
                "reverseLabel": AppStrings.text(.hotkeySummaryReverseLabel, language: language),
                "reverse": inAppWindowHotkeyConfiguration.backwardShortcutText
            ],
            language: language
        )
    }
}

final class HotkeySettingsCardAppKitView: NSView, AppKitSettingsCardStateView {
    var onHotkeyPrimaryModifierChanged: ((String) -> Void)?
    var onHotkeyMainKeyChanged: ((String) -> Void)?
    var onHotkeyQuitKeyChanged: ((String) -> Void)?
    var onInAppWindowPrimaryModifierChanged: ((String) -> Void)?
    var onInAppWindowMainKeyChanged: ((String) -> Void)?
    var onInteraction: (() -> Void)?

    private let stackView = NSStackView()
    private let mainPrimaryModifierSelect = FlowSettingsSelectControl(frame: .zero)
    private let mainKeySelect = FlowSettingsSelectControl(frame: .zero)
    private let quitKeySelect = FlowSettingsSelectControl(frame: .zero)
    private let inAppPrimaryModifierSelect = FlowSettingsSelectControl(frame: .zero)
    private let inAppMainKeySelect = FlowSettingsSelectControl(frame: .zero)
    private let mainSummaryLabel = HotkeySettingsCardAppKitView.makeSecondaryLabel()
    private let mainTakeoverStatusLabel = HotkeySettingsCardAppKitView.makeStatusLabel()
    private let divider = NSBox()
    private let inAppRowsContainer = NSStackView()
    private let inAppSummaryLabel = HotkeySettingsCardAppKitView.makeSecondaryLabel()
    private let inAppTakeoverStatusLabel = HotkeySettingsCardAppKitView.makeStatusLabel()
    private lazy var mainPrimaryModifierRow = AppKitSettingsCardBaseView.makeControlRow(
        title: "",
        control: mainPrimaryModifierSelect,
        validationIdentifier: HotkeySettingsField.mainModifier.conflictTestingIdentifier
    )
    private lazy var mainKeyRow = AppKitSettingsCardBaseView.makeControlRow(
        title: "",
        control: mainKeySelect,
        validationIdentifier: HotkeySettingsField.mainKey.conflictTestingIdentifier
    )
    private lazy var quitKeyRow = AppKitSettingsCardBaseView.makeControlRow(
        title: "",
        control: quitKeySelect,
        validationIdentifier: HotkeySettingsField.quitKey.conflictTestingIdentifier
    )
    private lazy var inAppPrimaryModifierRow = AppKitSettingsCardBaseView.makeControlRow(
        title: "",
        control: inAppPrimaryModifierSelect,
        validationIdentifier: HotkeySettingsField.inAppModifier.conflictTestingIdentifier
    )
    private lazy var inAppMainKeyRow = AppKitSettingsCardBaseView.makeControlRow(
        title: "",
        control: inAppMainKeySelect,
        validationIdentifier: HotkeySettingsField.inAppKey.conflictTestingIdentifier
    )
    private var isApplyingState = false
    private var currentState: HotkeySettingsCardState?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: preferredLayoutHeight())
    }

    override func layout() {
        let needsSecondLayoutPass = updateWrappingLabelWidths()
        super.layout()
        if needsSecondLayoutPass {
            super.layout()
        }
    }

    func preferredLayoutHeight() -> CGFloat {
        updateWrappingLabelWidths()
        return FlowSettingsLayoutMetrics.preferredStackHeight(stackView)
    }

    func update(with state: HotkeySettingsCardState) {
        let selectionProjection = selectionProjection(for: state)
        guard
            currentState != state
                || selectionProjection.contains(where: { $0.control.selectionID != $0.rawValue })
        else {
            return
        }
        currentState = state

        isApplyingState = true
        for selection in selectionProjection {
            selectItem(in: selection.control, rawValue: selection.rawValue)
        }
        isApplyingState = false

        mainSummaryLabel.stringValue = state.mainSummaryText
        updateMainTakeoverStatus(with: state)
        updateConflictStatus(with: state)

        inAppRowsContainer.alphaValue = state.accessibilityTrusted ? 1 : 0.55
        inAppPrimaryModifierSelect.isEnabled = state.accessibilityTrusted
        inAppMainKeySelect.isEnabled = state.accessibilityTrusted
        inAppSummaryLabel.stringValue = state.inAppSummaryText
        updateInAppTakeoverStatus(with: state)
        updateLocalizedRows(language: state.language)

        invalidateIntrinsicContentSize()
    }

    private func buildViewHierarchy() {
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 10
        stackView.detachesHiddenViews = true
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.setContentHuggingPriority(.required, for: .vertical)
        stackView.setContentCompressionResistancePriority(.required, for: .vertical)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])

        configure(
            selectControl: mainPrimaryModifierSelect,
            options: SwitcherPrimaryModifier.allCases.map { (id: $0.rawValue, title: $0.displayName) },
            onSelectionChanged: { [weak self] rawValue in
                self?.handleMainPrimaryModifierChanged(rawValue)
            }
        )
        configure(
            selectControl: mainKeySelect,
            options: SwitcherHotkeyKey.allCases.map { (id: $0.rawValue, title: $0.displayName) },
            placementPreference: .preferRight,
            onSelectionChanged: { [weak self] rawValue in
                self?.handleMainKeyChanged(rawValue)
            }
        )
        configure(
            selectControl: quitKeySelect,
            options: SwitcherHotkeyKey.allCases.map { (id: $0.rawValue, title: $0.displayName) },
            placementPreference: .preferRight,
            onSelectionChanged: { [weak self] rawValue in
                self?.handleQuitKeyChanged(rawValue)
            }
        )
        configure(
            selectControl: inAppPrimaryModifierSelect,
            options: SwitcherPrimaryModifier.allCases.map { (id: $0.rawValue, title: $0.displayName) },
            onSelectionChanged: { [weak self] rawValue in
                self?.handleInAppPrimaryModifierChanged(rawValue)
            }
        )
        configure(
            selectControl: inAppMainKeySelect,
            options: SwitcherHotkeyKey.allCases.map { (id: $0.rawValue, title: $0.displayName) },
            placementPreference: .preferRight,
            onSelectionChanged: { [weak self] rawValue in
                self?.handleInAppMainKeyChanged(rawValue)
            }
        )
        mainPrimaryModifierSelect.setFlowTabTestingIdentifier(
            HotkeySettingsField.mainModifier.controlTestingIdentifier
        )
        mainKeySelect.setFlowTabTestingIdentifier(
            HotkeySettingsField.mainKey.controlTestingIdentifier
        )
        quitKeySelect.setFlowTabTestingIdentifier(
            HotkeySettingsField.quitKey.controlTestingIdentifier
        )
        inAppPrimaryModifierSelect.setFlowTabTestingIdentifier(
            HotkeySettingsField.inAppModifier.controlTestingIdentifier
        )
        inAppMainKeySelect.setFlowTabTestingIdentifier(
            HotkeySettingsField.inAppKey.controlTestingIdentifier
        )
        mainSummaryLabel.setFlowTabTestingIdentifier("flowtab.settings.hotkey.main-summary")
        inAppSummaryLabel.setFlowTabTestingIdentifier("flowtab.settings.hotkey.in-app-summary")
        mainTakeoverStatusLabel.setFlowTabTestingIdentifier("flowtab.settings.hotkey.main-takeover-status")
        inAppTakeoverStatusLabel.setFlowTabTestingIdentifier("flowtab.settings.hotkey.in-app-takeover-status")

        stackView.addArrangedSubview(mainPrimaryModifierRow)
        stackView.addArrangedSubview(mainKeyRow)
        stackView.addArrangedSubview(quitKeyRow)
        mainPrimaryModifierRow.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
        mainKeyRow.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
        quitKeyRow.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
        stackView.addArrangedSubview(mainSummaryLabel)
        stackView.addArrangedSubview(mainTakeoverStatusLabel)

        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(divider)
        divider.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

        inAppRowsContainer.orientation = .vertical
        inAppRowsContainer.alignment = .leading
        inAppRowsContainer.spacing = 10
        inAppRowsContainer.detachesHiddenViews = true
        inAppRowsContainer.translatesAutoresizingMaskIntoConstraints = false
        inAppRowsContainer.setContentHuggingPriority(.required, for: .vertical)
        inAppRowsContainer.setContentCompressionResistancePriority(.required, for: .vertical)
        inAppRowsContainer.addArrangedSubview(inAppPrimaryModifierRow)
        inAppRowsContainer.addArrangedSubview(inAppMainKeyRow)
        inAppPrimaryModifierRow.widthAnchor.constraint(equalTo: inAppRowsContainer.widthAnchor).isActive = true
        inAppMainKeyRow.widthAnchor.constraint(equalTo: inAppRowsContainer.widthAnchor).isActive = true

        stackView.addArrangedSubview(inAppRowsContainer)
        stackView.addArrangedSubview(inAppSummaryLabel)
        stackView.addArrangedSubview(inAppTakeoverStatusLabel)
    }

    private func configure(
        selectControl: FlowSettingsSelectControl,
        options: [(id: String, title: String)],
        placementPreference: FlowDropdownPlacementPreference = .defaultBelow,
        onSelectionChanged: @escaping (String) -> Void
    ) {
        selectControl.onSelectionChanged = onSelectionChanged
        selectControl.onInteraction = { [weak self] in
            self?.onInteraction?()
        }
        AppKitSettingsCardBaseView.configure(
            selectControl: selectControl,
            options: options,
            placementPreference: placementPreference
        )
    }

    private func selectItem(in selectControl: FlowSettingsSelectControl, rawValue: String) {
        AppKitSettingsCardBaseView.selectItem(in: selectControl, rawValue: rawValue)
    }

    private func selectionProjection(
        for state: HotkeySettingsCardState
    ) -> [(control: FlowSettingsSelectControl, rawValue: String)] {
        [
            (mainPrimaryModifierSelect, state.hotkeyConfiguration.primaryModifier.rawValue),
            (mainKeySelect, state.hotkeyConfiguration.mainKey.rawValue),
            (quitKeySelect, state.hotkeyConfiguration.quitKey.rawValue),
            (
                inAppPrimaryModifierSelect,
                state.inAppWindowHotkeyConfiguration.primaryModifier.rawValue
            ),
            (inAppMainKeySelect, state.inAppWindowHotkeyConfiguration.mainKey.rawValue)
        ]
    }

    private func handleMainPrimaryModifierChanged(_ rawValue: String) {
        guard !isApplyingState else { return }
        onHotkeyPrimaryModifierChanged?(rawValue)
    }

    private func handleMainKeyChanged(_ rawValue: String) {
        guard !isApplyingState else { return }
        onHotkeyMainKeyChanged?(rawValue)
    }

    private func handleQuitKeyChanged(_ rawValue: String) {
        guard !isApplyingState else { return }
        onHotkeyQuitKeyChanged?(rawValue)
    }

    private func handleInAppPrimaryModifierChanged(_ rawValue: String) {
        guard !isApplyingState else { return }
        onInAppWindowPrimaryModifierChanged?(rawValue)
    }

    private func handleInAppMainKeyChanged(_ rawValue: String) {
        guard !isApplyingState else { return }
        onInAppWindowMainKeyChanged?(rawValue)
    }

    private func updateMainTakeoverStatus(with state: HotkeySettingsCardState) {
        updateTakeoverStatus(
            label: mainTakeoverStatusLabel,
            usesCommandTab: state.mainUsesCommandTab,
            registrationState: state.commandTabTakeoverRegistrationState,
            language: state.language
        )
    }

    private func updateConflictStatus(with state: HotkeySettingsCardState) {
        let message = AppStrings.text(.hotkeyConflict, language: state.language)
        for field in HotkeySettingsField.allCases {
            row(for: field).updateValidationMessage(
                state.hotkeyConflict?.field == field ? message : nil
            )
        }
    }

    private func row(for field: HotkeySettingsField) -> AppKitSettingsControlRow {
        switch field {
        case .mainModifier:
            return mainPrimaryModifierRow
        case .mainKey:
            return mainKeyRow
        case .quitKey:
            return quitKeyRow
        case .inAppModifier:
            return inAppPrimaryModifierRow
        case .inAppKey:
            return inAppMainKeyRow
        }
    }

    private func updateInAppTakeoverStatus(with state: HotkeySettingsCardState) {
        updateTakeoverStatus(
            label: inAppTakeoverStatusLabel,
            usesCommandTab: state.inAppUsesCommandTab,
            registrationState: state.commandTabTakeoverRegistrationState,
            language: state.language
        )
    }

    private func updateTakeoverStatus(
        label: NSTextField,
        usesCommandTab: Bool,
        registrationState: CommandTabTakeoverRegistrationState,
        language: AppLanguage
    ) {
        guard usesCommandTab else {
            label.isHidden = true
            return
        }

        switch registrationState {
        case .pending:
            label.isHidden = true
        case .active:
            label.stringValue = AppStrings.text(.hotkeyCommandTabTakeoverActive, language: language)
            label.textColor = .systemGreen
            label.isHidden = false
        case .inactive:
            label.stringValue = AppStrings.text(
                .hotkeyCommandTabTakeoverInactive,
                language: language
            )
            label.textColor = .systemRed
            label.isHidden = false
        }
    }

    private func updateLocalizedRows(language: AppLanguage) {
        mainPrimaryModifierRow.updateTitle(AppStrings.text(.hotkeyRowMainModifier, language: language))
        mainKeyRow.updateTitle(AppStrings.text(.hotkeyRowMainKey, language: language))
        quitKeyRow.updateTitle(AppStrings.text(.hotkeyRowQuitKey, language: language))
        inAppPrimaryModifierRow.updateTitle(AppStrings.text(.hotkeyRowInAppModifier, language: language))
        inAppMainKeyRow.updateTitle(AppStrings.text(.hotkeyRowInAppKey, language: language))
    }

    private static func makeSecondaryLabel() -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = FlowTypography.appKit(.body)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        return label
    }

    private static func makeStatusLabel() -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = FlowTypography.appKit(.body)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.isHidden = true
        return label
    }

    @discardableResult
    private func updateWrappingLabelWidths() -> Bool {
        let availableWidth = stackView.bounds.width > 0 ? stackView.bounds.width : bounds.width
        guard availableWidth > 0 else { return false }

        var didUpdate = false
        for label in [
            mainSummaryLabel,
            mainTakeoverStatusLabel,
            inAppSummaryLabel,
            inAppTakeoverStatusLabel
        ] {
            let preferredWidth = floor(availableWidth)
            guard abs(label.preferredMaxLayoutWidth - preferredWidth) > 0.5 else { continue }
            label.preferredMaxLayoutWidth = preferredWidth
            label.invalidateIntrinsicContentSize()
            didUpdate = true
        }
        return didUpdate
    }
}

private extension HotkeySettingsField {
    var controlTestingIdentifier: String {
        switch self {
        case .mainModifier:
            return "flowtab.settings.hotkey.main-modifier"
        case .mainKey:
            return "flowtab.settings.hotkey.main-key"
        case .quitKey:
            return "flowtab.settings.hotkey.quit-key"
        case .inAppModifier:
            return "flowtab.settings.hotkey.in-app-modifier"
        case .inAppKey:
            return "flowtab.settings.hotkey.in-app-key"
        }
    }

    var conflictTestingIdentifier: String {
        "\(controlTestingIdentifier).conflict-status"
    }
}
