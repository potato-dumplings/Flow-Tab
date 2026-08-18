import SwiftUI
import AppKit
import FlowTabCore

struct HotkeySettingsCardState: Equatable {
    let hotkeyPrimaryModifierRaw: String
    var hotkeyReverseModifiersRaw =
        SwitcherHotkeyPreferencesStore.defaultReverseKeys.rawValue
    let hotkeyMainKeyRaw: String
    let hotkeyQuitKeyRaw: String
    let inAppWindowHotkeyShortcutKeysRaw: String
    var inAppWindowHotkeyReverseKeysRaw =
        InAppWindowHotkeyPreferencesStore.defaultReverseKeys.rawValue
    let commandTabTakeoverRegistrationState: CommandTabTakeoverRegistrationState
    let accessibilityTrusted: Bool
    let appLanguageRaw: String
    var hotkeyConflict: HotkeySettingsConflictPresentation? = nil
    var hotkeyPermissionRequirement:
        HotkeySettingsPermissionPresentation? = nil

    var language: AppLanguage {
        AppLanguagePreferencesStore.resolve(rawValue: appLanguageRaw)
    }

    var hotkeyConfiguration: SwitcherHotkeyConfiguration {
        SwitcherHotkeyPreferencesStore.resolve(
            baseKeysRaw: hotkeyPrimaryModifierRaw,
            reverseKeysRaw: hotkeyReverseModifiersRaw,
            mainKeysRaw: hotkeyMainKeyRaw,
            quitKeysRaw: hotkeyQuitKeyRaw
        )
    }

    var inAppWindowHotkeyConfiguration: SwitcherHotkeyConfiguration {
        let resolved = InAppWindowHotkeyPreferencesStore.resolve(
            shortcutKeysRaw: inAppWindowHotkeyShortcutKeysRaw,
            reverseKeysRaw: inAppWindowHotkeyReverseKeysRaw
        )
        return resolved.configuration
    }

    var mainUsesCommandTab: Bool {
        hotkeyConfiguration.usesCommandTab
    }

    var inAppUsesCommandTab: Bool {
        inAppWindowHotkeyConfiguration.usesCommandTab
    }

    var fieldsRequiringAccessibility: Set<HotkeySettingsField> {
        guard !accessibilityTrusted else { return [] }
        return HotkeySettingsPermissionlessFieldPolicy
            .fieldsRequiringAccessibility(in: hotkeyConfiguration)
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
    var onMainModifiersChanged: ((SwitcherHotkeyKeySet) -> Void)?
    var onMainReverseModifiersChanged: ((SwitcherHotkeyKeySet) -> Void)?
    var onMainKeyChanged: ((SwitcherHotkeyKeySet) -> Void)?
    var onQuitKeyChanged: ((SwitcherHotkeyKeySet) -> Void)?
    var onInAppShortcutChanged: ((SwitcherHotkeyKeySet) -> Void)?
    var onInAppReverseModifiersChanged: ((SwitcherHotkeyKeySet) -> Void)?
    var onInteraction: (() -> Void)?

    private let stackView = NSStackView()
    private let mainModifiersRecorder = FlowSettingsShortcutRecorderControl(frame: .zero)
    private let mainReverseModifiersRecorder =
        FlowSettingsShortcutRecorderControl(frame: .zero)
    private let mainKeyRecorder = FlowSettingsShortcutRecorderControl(frame: .zero)
    private let quitKeyRecorder = FlowSettingsShortcutRecorderControl(frame: .zero)
    private let inAppShortcutRecorder = FlowSettingsShortcutRecorderControl(frame: .zero)
    private let inAppReverseModifiersRecorder =
        FlowSettingsShortcutRecorderControl(frame: .zero)
    private let mainSummaryLabel = HotkeySettingsCardAppKitView.makeSecondaryLabel()
    private let mainTakeoverStatusLabel = HotkeySettingsCardAppKitView.makeStatusLabel()
    private let divider = NSBox()
    private let inAppRowsContainer = NSStackView()
    private let inAppSummaryLabel = HotkeySettingsCardAppKitView.makeSecondaryLabel()
    private let inAppTakeoverStatusLabel = HotkeySettingsCardAppKitView.makeStatusLabel()

    private lazy var mainModifiersRow = makeControlRow(
        control: mainModifiersRecorder,
        field: .mainModifiers
    )
    private lazy var mainReverseModifiersRow = makeControlRow(
        control: mainReverseModifiersRecorder,
        field: .mainReverseModifiers
    )
    private lazy var mainKeyRow = makeControlRow(
        control: mainKeyRecorder,
        field: .mainKey
    )
    private lazy var quitKeyRow = makeControlRow(
        control: quitKeyRecorder,
        field: .quitKey
    )
    private lazy var inAppShortcutRow = makeControlRow(
        control: inAppShortcutRecorder,
        field: .inAppShortcut
    )
    private lazy var inAppReverseModifiersRow = makeControlRow(
        control: inAppReverseModifiersRecorder,
        field: .inAppReverseModifiers
    )
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
        let mainConfiguration = state.hotkeyConfiguration
        let inAppConfiguration = state.inAppWindowHotkeyConfiguration
        guard
            currentState != state
                || mainModifiersRecorder.recordedKeys
                    != mainConfiguration.baseKeys
                || mainReverseModifiersRecorder.recordedKeys
                    != mainConfiguration.reverseKeys
                || mainKeyRecorder.recordedKeys
                    != mainConfiguration.mainKeys
                || quitKeyRecorder.recordedKeys
                    != mainConfiguration.quitKeys
                || inAppShortcutRecorder.recordedKeys
                    != inAppConfiguration.baseKeys
                || inAppReverseModifiersRecorder.recordedKeys
                    != inAppConfiguration.reverseKeys
                || inAppShortcutRecorder.isEnabled != state.accessibilityTrusted
        else {
            return
        }
        currentState = state

        let recordingPrompt = AppStrings.text(.hotkeyRecorderPrompt, language: state.language)
        let modifierRequiredPrompt = AppStrings.text(
            .hotkeyRecorderModifierRequired,
            language: state.language
        )

        mainModifiersRecorder.update(
            keys: mainConfiguration.baseKeys,
            recordingPrompt: recordingPrompt,
            keyRequiredPrompt: modifierRequiredPrompt,
            accessibilityLabel: AppStrings.text(
                .hotkeyRowMainModifiers,
                language: state.language
            )
        )
        mainReverseModifiersRecorder.update(
            keys: mainConfiguration.reverseKeys,
            recordingPrompt: recordingPrompt,
            keyRequiredPrompt: modifierRequiredPrompt,
            accessibilityLabel: AppStrings.text(
                .hotkeyRowMainReverseModifiers,
                language: state.language
            )
        )
        mainKeyRecorder.update(
            keys: mainConfiguration.mainKeys,
            recordingPrompt: recordingPrompt,
            keyRequiredPrompt: modifierRequiredPrompt,
            accessibilityLabel: AppStrings.text(
                .hotkeyRowMainKey,
                language: state.language
            )
        )
        quitKeyRecorder.update(
            keys: mainConfiguration.quitKeys,
            recordingPrompt: recordingPrompt,
            keyRequiredPrompt: modifierRequiredPrompt,
            accessibilityLabel: AppStrings.text(
                .hotkeyRowQuitKey,
                language: state.language
            )
        )
        inAppShortcutRecorder.update(
            keys: inAppConfiguration.baseKeys,
            recordingPrompt: recordingPrompt,
            keyRequiredPrompt: modifierRequiredPrompt,
            accessibilityLabel: AppStrings.text(
                .hotkeyRowInAppShortcut,
                language: state.language
            )
        )
        inAppReverseModifiersRecorder.update(
            keys: inAppConfiguration.reverseKeys,
            recordingPrompt: recordingPrompt,
            keyRequiredPrompt: modifierRequiredPrompt,
            accessibilityLabel: AppStrings.text(
                .hotkeyRowInAppReverseModifiers,
                language: state.language
            )
        )

        mainSummaryLabel.stringValue = state.mainSummaryText
        updateMainTakeoverStatus(with: state)
        updateValidationStatus(with: state)

        inAppRowsContainer.alphaValue = state.accessibilityTrusted ? 1 : 0.55
        inAppShortcutRecorder.isEnabled = state.accessibilityTrusted
        inAppReverseModifiersRecorder.isEnabled = state.accessibilityTrusted
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

        configureKeyRecorder(mainModifiersRecorder) { [weak self] keys in
            self?.onMainModifiersChanged?(keys)
        }
        configureKeyRecorder(mainReverseModifiersRecorder) { [weak self] keys in
            self?.onMainReverseModifiersChanged?(keys)
        }
        configureKeyRecorder(mainKeyRecorder) { [weak self] keys in
            self?.onMainKeyChanged?(keys)
        }
        configureKeyRecorder(quitKeyRecorder) { [weak self] keys in
            self?.onQuitKeyChanged?(keys)
        }
        configureKeyRecorder(inAppShortcutRecorder) { [weak self] keys in
            self?.onInAppShortcutChanged?(keys)
        }
        configureKeyRecorder(inAppReverseModifiersRecorder) { [weak self] keys in
            self?.onInAppReverseModifiersChanged?(keys)
        }

        for field in HotkeySettingsField.allCases {
            recorder(for: field).setFlowTabTestingIdentifier(
                field.controlTestingIdentifier
            )
        }
        mainSummaryLabel.setFlowTabTestingIdentifier("flowtab.settings.hotkey.main-summary")
        inAppSummaryLabel.setFlowTabTestingIdentifier("flowtab.settings.hotkey.in-app-summary")
        mainTakeoverStatusLabel.setFlowTabTestingIdentifier(
            "flowtab.settings.hotkey.main-takeover-status"
        )
        inAppTakeoverStatusLabel.setFlowTabTestingIdentifier(
            "flowtab.settings.hotkey.in-app-takeover-status"
        )

        for row in [
            mainModifiersRow,
            mainReverseModifiersRow,
            mainKeyRow,
            quitKeyRow
        ] {
            addFullWidthArrangedSubview(row, to: stackView)
        }
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
        addFullWidthArrangedSubview(inAppShortcutRow, to: inAppRowsContainer)
        addFullWidthArrangedSubview(
            inAppReverseModifiersRow,
            to: inAppRowsContainer
        )

        stackView.addArrangedSubview(inAppRowsContainer)
        stackView.addArrangedSubview(inAppSummaryLabel)
        stackView.addArrangedSubview(inAppTakeoverStatusLabel)
    }

    private func makeControlRow(
        control: NSView,
        field: HotkeySettingsField
    ) -> AppKitSettingsControlRow {
        AppKitSettingsCardBaseView.makeControlRow(
            title: "",
            control: control,
            validationIdentifier: field.conflictTestingIdentifier
        )
    }

    private func configureKeyRecorder(
        _ recorder: FlowSettingsShortcutRecorderControl,
        onKeysChanged: @escaping (SwitcherHotkeyKeySet) -> Void
    ) {
        recorder.onKeysChanged = onKeysChanged
        recorder.onInteraction = { [weak self] in
            self?.onInteraction?()
        }
    }

    private func addFullWidthArrangedSubview(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func updateMainTakeoverStatus(with state: HotkeySettingsCardState) {
        updateTakeoverStatus(
            label: mainTakeoverStatusLabel,
            usesCommandTab: state.mainUsesCommandTab,
            registrationState: state.commandTabTakeoverRegistrationState,
            language: state.language
        )
    }

    private func updateValidationStatus(with state: HotkeySettingsCardState) {
        let conflictMessage = AppStrings.text(
            .hotkeyConflict,
            language: state.language
        )
        for field in HotkeySettingsField.allCases {
            let message: String?
            if state.hotkeyConflict?.field == field {
                message = conflictMessage
            } else if state.hotkeyPermissionRequirement?.field == field
                || state.fieldsRequiringAccessibility.contains(field)
            {
                message = permissionMessage(
                    for: field,
                    language: state.language
                )
            } else {
                message = nil
            }
            row(for: field).updateValidationMessage(
                message
            )
        }
    }

    private func permissionMessage(
        for field: HotkeySettingsField,
        language: AppLanguage
    ) -> String? {
        switch field {
        case .mainModifiers, .mainReverseModifiers:
            return AppStrings.text(
                .hotkeyModifierPermissionlessRequirement,
                language: language
            )
        case .mainKey:
            return AppStrings.text(
                .hotkeyMainKeyPermissionlessRequirement,
                language: language
            )
        case .quitKey, .inAppShortcut, .inAppReverseModifiers:
            return nil
        }
    }

    private func row(for field: HotkeySettingsField) -> AppKitSettingsControlRow {
        switch field {
        case .mainModifiers:
            return mainModifiersRow
        case .mainReverseModifiers:
            return mainReverseModifiersRow
        case .mainKey:
            return mainKeyRow
        case .quitKey:
            return quitKeyRow
        case .inAppShortcut:
            return inAppShortcutRow
        case .inAppReverseModifiers:
            return inAppReverseModifiersRow
        }
    }

    private func recorder(
        for field: HotkeySettingsField
    ) -> FlowSettingsShortcutRecorderControl {
        switch field {
        case .mainModifiers:
            return mainModifiersRecorder
        case .mainReverseModifiers:
            return mainReverseModifiersRecorder
        case .mainKey:
            return mainKeyRecorder
        case .quitKey:
            return quitKeyRecorder
        case .inAppShortcut:
            return inAppShortcutRecorder
        case .inAppReverseModifiers:
            return inAppReverseModifiersRecorder
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
        mainModifiersRow.updateTitle(
            AppStrings.text(.hotkeyRowMainModifiers, language: language)
        )
        mainReverseModifiersRow.updateTitle(
            AppStrings.text(.hotkeyRowMainReverseModifiers, language: language)
        )
        mainKeyRow.updateTitle(
            AppStrings.text(.hotkeyRowMainKey, language: language)
        )
        quitKeyRow.updateTitle(
            AppStrings.text(.hotkeyRowQuitKey, language: language)
        )
        inAppShortcutRow.updateTitle(
            AppStrings.text(.hotkeyRowInAppShortcut, language: language)
        )
        inAppReverseModifiersRow.updateTitle(
            AppStrings.text(.hotkeyRowInAppReverseModifiers, language: language)
        )
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
        case .mainModifiers:
            return "flowtab.settings.hotkey.main-modifiers"
        case .mainReverseModifiers:
            return "flowtab.settings.hotkey.main-reverse-modifiers"
        case .mainKey:
            return "flowtab.settings.hotkey.main-key"
        case .quitKey:
            return "flowtab.settings.hotkey.quit-key"
        case .inAppShortcut:
            return "flowtab.settings.hotkey.in-app-shortcut"
        case .inAppReverseModifiers:
            return "flowtab.settings.hotkey.in-app-reverse-modifiers"
        }
    }

    var conflictTestingIdentifier: String {
        "\(controlTestingIdentifier).conflict-status"
    }
}
