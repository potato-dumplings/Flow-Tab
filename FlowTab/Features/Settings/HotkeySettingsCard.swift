import SwiftUI
import AppKit
import FlowTabCore

struct AppKitHotkeySettingsCardContent: NSViewRepresentable {
    @Binding var hotkeyPrimaryModifierRaw: String
    @Binding var hotkeyMainKeyRaw: String
    @Binding var hotkeyQuitKeyRaw: String
    @Binding var inAppWindowHotkeyPrimaryModifierRaw: String
    @Binding var inAppWindowHotkeyMainKeyRaw: String
    let commandTabTakeoverActive: Bool
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

    func makeNSView(context: Context) -> HotkeySettingsCardAppKitView {
        let view = HotkeySettingsCardAppKitView()
        connect(view, coordinator: context.coordinator)
        return view
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: HotkeySettingsCardAppKitView,
        context: Context
    ) -> CGSize? {
        nsView.preferredFittingSize(forWidth: proposal.width)
    }

    func updateNSView(_ nsView: HotkeySettingsCardAppKitView, context: Context) {
        context.coordinator.update(
            hotkeyPrimaryModifierRaw: $hotkeyPrimaryModifierRaw,
            hotkeyMainKeyRaw: $hotkeyMainKeyRaw,
            hotkeyQuitKeyRaw: $hotkeyQuitKeyRaw,
            inAppWindowHotkeyPrimaryModifierRaw: $inAppWindowHotkeyPrimaryModifierRaw,
            inAppWindowHotkeyMainKeyRaw: $inAppWindowHotkeyMainKeyRaw
        )
        connect(nsView, coordinator: context.coordinator)
        nsView.update(
            with: HotkeySettingsCardState(
                hotkeyPrimaryModifierRaw: hotkeyPrimaryModifierRaw,
                hotkeyMainKeyRaw: hotkeyMainKeyRaw,
                hotkeyQuitKeyRaw: hotkeyQuitKeyRaw,
                inAppWindowHotkeyPrimaryModifierRaw: inAppWindowHotkeyPrimaryModifierRaw,
                inAppWindowHotkeyMainKeyRaw: inAppWindowHotkeyMainKeyRaw,
                commandTabTakeoverActive: commandTabTakeoverActive,
                accessibilityTrusted: accessibilityTrusted
            )
        )
    }

    private func connect(_ view: HotkeySettingsCardAppKitView, coordinator: Coordinator) {
        view.onHotkeyPrimaryModifierChanged = { coordinator.setHotkeyPrimaryModifier($0) }
        view.onHotkeyMainKeyChanged = { coordinator.setHotkeyMainKey($0) }
        view.onHotkeyQuitKeyChanged = { coordinator.setHotkeyQuitKey($0) }
        view.onInAppWindowPrimaryModifierChanged = { coordinator.setInAppWindowPrimaryModifier($0) }
        view.onInAppWindowMainKeyChanged = { coordinator.setInAppWindowMainKey($0) }
    }
}

struct HotkeySettingsCardState: Equatable {
    let hotkeyPrimaryModifierRaw: String
    let hotkeyMainKeyRaw: String
    let hotkeyQuitKeyRaw: String
    let inAppWindowHotkeyPrimaryModifierRaw: String
    let inAppWindowHotkeyMainKeyRaw: String
    let commandTabTakeoverActive: Bool
    let accessibilityTrusted: Bool

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

    var commandTabTakeoverStatusText: String {
        commandTabTakeoverActive
            ? AppStrings.text(.hotkeyCommandTabTakeoverActive)
            : AppStrings.text(.hotkeyCommandTabTakeoverInactive)
    }

    var mainSummaryText: String {
        AppStrings.text(
            .hotkeyMainSummary,
            replacements: [
                "main": hotkeyConfiguration.mainShortcutText,
                "reverseLabel": AppStrings.text(.hotkeySummaryReverseLabel),
                "reverse": hotkeyConfiguration.backwardShortcutText,
                "quitLabel": AppStrings.text(.hotkeySummaryQuitLabel),
                "quit": hotkeyConfiguration.quitShortcutText
            ]
        )
    }

    var inAppSummaryText: String {
        AppStrings.text(
            .hotkeyInAppSummary,
            replacements: [
                "inAppLabel": AppStrings.text(.hotkeySummaryInAppLabel),
                "main": inAppWindowHotkeyConfiguration.mainShortcutText,
                "reverseLabel": AppStrings.text(.hotkeySummaryReverseLabel),
                "reverse": inAppWindowHotkeyConfiguration.backwardShortcutText
            ]
        )
    }
}

final class HotkeySettingsCardAppKitView: NSView {
    var onHotkeyPrimaryModifierChanged: ((String) -> Void)?
    var onHotkeyMainKeyChanged: ((String) -> Void)?
    var onHotkeyQuitKeyChanged: ((String) -> Void)?
    var onInAppWindowPrimaryModifierChanged: ((String) -> Void)?
    var onInAppWindowMainKeyChanged: ((String) -> Void)?

    private let stackView = NSStackView()
    private let mainPrimaryModifierSelect = FlowFormSelectControl(frame: .zero)
    private let mainKeySelect = FlowFormSelectControl(frame: .zero)
    private let quitKeySelect = FlowFormSelectControl(frame: .zero)
    private let inAppPrimaryModifierSelect = FlowFormSelectControl(frame: .zero)
    private let inAppMainKeySelect = FlowFormSelectControl(frame: .zero)
    private let mainSummaryLabel = HotkeySettingsCardAppKitView.makeSecondaryLabel()
    private let mainTakeoverStatusLabel = HotkeySettingsCardAppKitView.makeStatusLabel()
    private let divider = NSBox()
    private let inAppRowsContainer = NSStackView()
    private let inAppSummaryLabel = HotkeySettingsCardAppKitView.makeSecondaryLabel()
    private let inAppTakeoverStatusLabel = HotkeySettingsCardAppKitView.makeStatusLabel()
    private let takeoverInactiveDisplayDelay: TimeInterval = 0.25
    private var isApplyingState = false
    private var mainInactiveStatusWorkItem: DispatchWorkItem?
    private var inAppInactiveStatusWorkItem: DispatchWorkItem?
    private var currentState: HotkeySettingsCardState?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy()
    }

    deinit {
        mainInactiveStatusWorkItem?.cancel()
        inAppInactiveStatusWorkItem?.cancel()
    }

    override var intrinsicContentSize: NSSize {
        layoutSubtreeIfNeeded()
        return NSSize(width: NSView.noIntrinsicMetric, height: stackView.fittingSize.height)
    }

    func update(with state: HotkeySettingsCardState) {
        guard currentState != state else { return }
        currentState = state

        isApplyingState = true
        selectItem(in: mainPrimaryModifierSelect, rawValue: state.hotkeyConfiguration.primaryModifier.rawValue)
        selectItem(in: mainKeySelect, rawValue: state.hotkeyConfiguration.mainKey.rawValue)
        selectItem(in: quitKeySelect, rawValue: state.hotkeyConfiguration.quitKey.rawValue)
        selectItem(
            in: inAppPrimaryModifierSelect,
            rawValue: state.inAppWindowHotkeyConfiguration.primaryModifier.rawValue
        )
        selectItem(
            in: inAppMainKeySelect,
            rawValue: state.inAppWindowHotkeyConfiguration.mainKey.rawValue
        )
        isApplyingState = false

        mainSummaryLabel.stringValue = state.mainSummaryText
        updateMainTakeoverStatus(with: state)

        inAppRowsContainer.alphaValue = state.accessibilityTrusted ? 1 : 0.55
        inAppPrimaryModifierSelect.isEnabled = state.accessibilityTrusted
        inAppMainKeySelect.isEnabled = state.accessibilityTrusted
        inAppSummaryLabel.stringValue = state.inAppSummaryText
        updateInAppTakeoverStatus(with: state)

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
            onSelectionChanged: { [weak self] rawValue in
                self?.handleMainKeyChanged(rawValue)
            }
        )
        configure(
            selectControl: quitKeySelect,
            options: SwitcherHotkeyKey.allCases.map { (id: $0.rawValue, title: $0.displayName) },
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
            onSelectionChanged: { [weak self] rawValue in
                self?.handleInAppMainKeyChanged(rawValue)
            }
        )
        mainPrimaryModifierSelect.setFlowTabTestingIdentifier("flowtab.settings.hotkey.main-modifier")
        mainKeySelect.setFlowTabTestingIdentifier("flowtab.settings.hotkey.main-key")
        quitKeySelect.setFlowTabTestingIdentifier("flowtab.settings.hotkey.quit-key")
        inAppPrimaryModifierSelect.setFlowTabTestingIdentifier("flowtab.settings.hotkey.in-app-modifier")
        inAppMainKeySelect.setFlowTabTestingIdentifier("flowtab.settings.hotkey.in-app-key")
        mainSummaryLabel.setFlowTabTestingIdentifier("flowtab.settings.hotkey.main-summary")
        inAppSummaryLabel.setFlowTabTestingIdentifier("flowtab.settings.hotkey.in-app-summary")
        mainTakeoverStatusLabel.setFlowTabTestingIdentifier("flowtab.settings.hotkey.main-takeover-status")
        inAppTakeoverStatusLabel.setFlowTabTestingIdentifier("flowtab.settings.hotkey.in-app-takeover-status")

        let mainPrimaryRow = makeControlRow(title: AppStrings.text(.hotkeyRowMainModifier), control: mainPrimaryModifierSelect)
        let mainKeyRow = makeControlRow(title: AppStrings.text(.hotkeyRowMainKey), control: mainKeySelect)
        let quitKeyRow = makeControlRow(title: AppStrings.text(.hotkeyRowQuitKey), control: quitKeySelect)
        stackView.addArrangedSubview(mainPrimaryRow)
        stackView.addArrangedSubview(mainKeyRow)
        stackView.addArrangedSubview(quitKeyRow)
        mainPrimaryRow.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
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
        let inAppPrimaryRow = makeControlRow(title: AppStrings.text(.hotkeyRowInAppModifier), control: inAppPrimaryModifierSelect)
        let inAppMainKeyRow = makeControlRow(title: AppStrings.text(.hotkeyRowInAppKey), control: inAppMainKeySelect)
        inAppRowsContainer.addArrangedSubview(inAppPrimaryRow)
        inAppRowsContainer.addArrangedSubview(inAppMainKeyRow)
        inAppPrimaryRow.widthAnchor.constraint(equalTo: inAppRowsContainer.widthAnchor).isActive = true
        inAppMainKeyRow.widthAnchor.constraint(equalTo: inAppRowsContainer.widthAnchor).isActive = true

        stackView.addArrangedSubview(inAppRowsContainer)
        stackView.addArrangedSubview(inAppSummaryLabel)
        stackView.addArrangedSubview(inAppTakeoverStatusLabel)
    }

    private func makeControlRow(title: String, control: NSView) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [titleLabel, spacer, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        row.detachesHiddenViews = true
        return row
    }

    private func configure(
        selectControl: FlowFormSelectControl,
        options: [(id: String, title: String)],
        onSelectionChanged: @escaping (String) -> Void
    ) {
        selectControl.onSelectionChanged = onSelectionChanged
        AppKitSettingsCardBaseView.configure(selectControl: selectControl, options: options, width: 160)
    }

    private func selectItem(in selectControl: FlowFormSelectControl, rawValue: String) {
        AppKitSettingsCardBaseView.selectItem(in: selectControl, rawValue: rawValue)
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
            takeoverActive: state.commandTabTakeoverActive,
            workItem: &mainInactiveStatusWorkItem
        )
    }

    private func updateInAppTakeoverStatus(with state: HotkeySettingsCardState) {
        updateTakeoverStatus(
            label: inAppTakeoverStatusLabel,
            usesCommandTab: state.inAppUsesCommandTab,
            takeoverActive: state.commandTabTakeoverActive,
            workItem: &inAppInactiveStatusWorkItem
        )
    }

    private func updateTakeoverStatus(
        label: NSTextField,
        usesCommandTab: Bool,
        takeoverActive: Bool,
        workItem: inout DispatchWorkItem?
    ) {
        workItem?.cancel()
        workItem = nil

        guard usesCommandTab else {
            label.isHidden = true
            return
        }

        if takeoverActive {
            label.stringValue = AppStrings.text(.hotkeyCommandTabTakeoverActive)
            label.textColor = .systemGreen
            label.isHidden = false
            return
        }

        // Treat fresh Command+Tab updates as pending; only show inactive text after confirmation delay.
        label.isHidden = true
        let pendingWorkItem = DispatchWorkItem { [weak self, weak label] in
            guard let self, let label else { return }
            guard let latestState = self.currentState else { return }

            let latestUsesCommandTab = label === self.mainTakeoverStatusLabel
                ? latestState.mainUsesCommandTab
                : latestState.inAppUsesCommandTab

            guard latestUsesCommandTab, !latestState.commandTabTakeoverActive else { return }
            label.stringValue = AppStrings.text(.hotkeyCommandTabTakeoverInactive)
            label.textColor = .systemRed
            label.isHidden = false
        }
        workItem = pendingWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + takeoverInactiveDisplayDelay, execute: pendingWorkItem)
    }

    private static func makeSecondaryLabel() -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        return label
    }

    private static func makeStatusLabel() -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.isHidden = true
        return label
    }
}

