import SwiftUI
import AppKit

struct AppKitPermissionSettingsCardContent: AppKitSettingsCardRepresentable {
    typealias NSViewType = PermissionSettingsCardAppKitView

    @Binding var showPermissionReminder: Bool
    @Binding var allowLaunchAtLogin: Bool
    @Binding var terminalContentPreviewsEnabled: Bool
    let accessibilityTrusted: Bool
    let screenCaptureTrusted: Bool
    let onLaunchAtLoginChanged: (Bool) -> Void
    let onAccessibilityAction: () -> Void
    let onScreenCaptureAction: () -> Void

    final class Coordinator {
        var showPermissionReminder: Binding<Bool>
        var allowLaunchAtLogin: Binding<Bool>
        var terminalContentPreviewsEnabled: Binding<Bool>
        var onLaunchAtLoginChanged: (Bool) -> Void
        var onAccessibilityAction: () -> Void
        var onScreenCaptureAction: () -> Void

        init(
            showPermissionReminder: Binding<Bool>,
            allowLaunchAtLogin: Binding<Bool>,
            terminalContentPreviewsEnabled: Binding<Bool>,
            onLaunchAtLoginChanged: @escaping (Bool) -> Void,
            onAccessibilityAction: @escaping () -> Void,
            onScreenCaptureAction: @escaping () -> Void
        ) {
            self.showPermissionReminder = showPermissionReminder
            self.allowLaunchAtLogin = allowLaunchAtLogin
            self.terminalContentPreviewsEnabled = terminalContentPreviewsEnabled
            self.onLaunchAtLoginChanged = onLaunchAtLoginChanged
            self.onAccessibilityAction = onAccessibilityAction
            self.onScreenCaptureAction = onScreenCaptureAction
        }

        func update(
            showPermissionReminder: Binding<Bool>,
            allowLaunchAtLogin: Binding<Bool>,
            terminalContentPreviewsEnabled: Binding<Bool>,
            onLaunchAtLoginChanged: @escaping (Bool) -> Void,
            onAccessibilityAction: @escaping () -> Void,
            onScreenCaptureAction: @escaping () -> Void
        ) {
            self.showPermissionReminder = showPermissionReminder
            self.allowLaunchAtLogin = allowLaunchAtLogin
            self.terminalContentPreviewsEnabled = terminalContentPreviewsEnabled
            self.onLaunchAtLoginChanged = onLaunchAtLoginChanged
            self.onAccessibilityAction = onAccessibilityAction
            self.onScreenCaptureAction = onScreenCaptureAction
        }

        func setShowPermissionReminder(_ value: Bool) {
            showPermissionReminder.wrappedValue = value
        }

        func setAllowLaunchAtLogin(_ value: Bool) {
            allowLaunchAtLogin.wrappedValue = value
            onLaunchAtLoginChanged(value)
        }

        func setTerminalContentPreviewsEnabled(_ value: Bool) {
            terminalContentPreviewsEnabled.wrappedValue = value
        }

        func triggerAccessibilityAction() {
            onAccessibilityAction()
        }

        func triggerScreenCaptureAction() {
            onScreenCaptureAction()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            showPermissionReminder: $showPermissionReminder,
            allowLaunchAtLogin: $allowLaunchAtLogin,
            terminalContentPreviewsEnabled: $terminalContentPreviewsEnabled,
            onLaunchAtLoginChanged: onLaunchAtLoginChanged,
            onAccessibilityAction: onAccessibilityAction,
            onScreenCaptureAction: onScreenCaptureAction
        )
    }

    func makeCardView(context _: Context) -> PermissionSettingsCardAppKitView {
        PermissionSettingsCardAppKitView()
    }

    func updateCoordinator(_ coordinator: Coordinator) {
        coordinator.update(
            showPermissionReminder: $showPermissionReminder,
            allowLaunchAtLogin: $allowLaunchAtLogin,
            terminalContentPreviewsEnabled: $terminalContentPreviewsEnabled,
            onLaunchAtLoginChanged: onLaunchAtLoginChanged,
            onAccessibilityAction: onAccessibilityAction,
            onScreenCaptureAction: onScreenCaptureAction
        )
    }

    func connect(_ view: PermissionSettingsCardAppKitView, coordinator: Coordinator) {
        view.onShowPermissionReminderChanged = { coordinator.setShowPermissionReminder($0) }
        view.onAllowLaunchAtLoginChanged = { coordinator.setAllowLaunchAtLogin($0) }
        view.onTerminalContentPreviewsChanged = {
            coordinator.setTerminalContentPreviewsEnabled($0)
        }
        view.onAccessibilityAction = { coordinator.triggerAccessibilityAction() }
        view.onScreenCaptureAction = { coordinator.triggerScreenCaptureAction() }
    }

    func makeState() -> PermissionSettingsCardState {
        PermissionSettingsCardState(
            showPermissionReminder: showPermissionReminder,
            allowLaunchAtLogin: allowLaunchAtLogin,
            terminalContentPreviewsEnabled: terminalContentPreviewsEnabled,
            accessibilityTrusted: accessibilityTrusted,
            screenCaptureTrusted: screenCaptureTrusted,
            appLanguageRaw: AppLanguagePreferencesStore.load().rawValue
        )
    }
}

struct PermissionSettingsCardState: Equatable {
    let showPermissionReminder: Bool
    let allowLaunchAtLogin: Bool
    let terminalContentPreviewsEnabled: Bool
    let accessibilityTrusted: Bool
    let screenCaptureTrusted: Bool
    let appLanguageRaw: String

    var language: AppLanguage {
        AppLanguagePreferencesStore.resolve(rawValue: appLanguageRaw)
    }

    var accessibilityStatusText: String {
        accessibilityTrusted
            ? AppStrings.text(.permissionAccessibilityGranted, language: language)
            : AppStrings.text(.permissionAccessibilityDenied, language: language)
    }

    var accessibilityButtonTitle: String {
        accessibilityTrusted
            ? AppStrings.text(.permissionAccessibilityManage, language: language)
            : AppStrings.text(.permissionAccessibilityRequest, language: language)
    }

    var accessibilityPermissionActionLabel: String {
        accessibilityTrusted
            ? AppStrings.text(.permissionAccessibilityManageActionLabel, language: language)
            : AppStrings.text(.permissionAccessibilityRequestActionLabel, language: language)
    }

    var screenCaptureStatusText: String {
        screenCaptureTrusted
            ? AppStrings.text(.permissionScreenGranted, language: language)
            : AppStrings.text(.permissionScreenDenied, language: language)
    }

    var screenCaptureButtonTitle: String {
        screenCaptureTrusted
            ? AppStrings.text(.permissionScreenManage, language: language)
            : AppStrings.text(.permissionScreenRequest, language: language)
    }

    var screenCapturePermissionActionLabel: String {
        screenCaptureTrusted
            ? AppStrings.text(.permissionScreenManageActionLabel, language: language)
            : AppStrings.text(.permissionScreenRequestActionLabel, language: language)
    }

}

final class PermissionStatusControlRowView<Control: NSView>: NSView {
    let titleLabel = AppKitSettingsCardBaseView.makeStatusLabel()
    let detailLabel = AppKitSettingsCardBaseView.makeBodyLabel()
    let control: Control
    private let textStack = NSStackView()
    private let controlWidth: CGFloat?

    init(control: Control, controlWidth: CGFloat? = nil) {
        self.control = control
        self.controlWidth = controlWidth
        super.init(frame: .zero)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(
            width: NSView.noIntrinsicMetric,
            height: preferredLayoutHeight()
        )
    }

    override func layout() {
        let needsSecondLayoutPass = updatePreferredLabelWidths()
        super.layout()
        if updatePreferredLabelWidths() || needsSecondLayoutPass {
            super.layout()
        }
    }

    func preferredLayoutHeight() -> CGFloat {
        updatePreferredLabelWidths()
        return ceil(max(preferredTextHeight(), control.fittingSize.height))
    }

    private func buildViewHierarchy() {
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
        configureTextLabelPriorities()

        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.detachesHiddenViews = true
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.setContentHuggingPriority(.required, for: .vertical)
        textStack.setContentCompressionResistancePriority(.required, for: .vertical)
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(detailLabel)

        control.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textStack)
        addSubview(control)
        if let controlWidth {
            AppKitSettingsCardBaseView.applyPreferredControlWidth(control, width: controlWidth)
        }

        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            textStack.topAnchor.constraint(equalTo: topAnchor),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -10),

            control.trailingAnchor.constraint(equalTo: trailingAnchor),
            control.centerYAnchor.constraint(equalTo: textStack.centerYAnchor),
            control.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            control.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
    }

    func update(text: String, detail: String, statusColor: NSColor) {
        titleLabel.stringValue = text
        titleLabel.textColor = statusColor
        titleLabel.isHidden = text.isEmpty
        detailLabel.stringValue = detail
        detailLabel.isHidden = detail.isEmpty
        titleLabel.invalidateIntrinsicContentSize()
        detailLabel.invalidateIntrinsicContentSize()
        textStack.invalidateIntrinsicContentSize()
        invalidateIntrinsicContentSize()
        needsLayout = true
        superview?.invalidateIntrinsicContentSize()
        superview?.needsLayout = true
    }

    private func configureTextLabelPriorities() {
        [titleLabel, detailLabel].forEach { label in
            label.setContentHuggingPriority(.required, for: .vertical)
            label.setContentCompressionResistancePriority(.required, for: .vertical)
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
    }

    @discardableResult
    private func updatePreferredLabelWidths() -> Bool {
        let rowWidth = bounds.width > 0 ? bounds.width : superview?.bounds.width ?? 0
        guard rowWidth > 0 else { return false }
        let controlWidth = max(control.fittingSize.width, control.intrinsicContentSize.width)
        let textWidth = max(0, rowWidth - controlWidth - 10)
        let preferredWidth = floor(textWidth)
        guard abs(detailLabel.preferredMaxLayoutWidth - preferredWidth) > 0.5
            || abs(titleLabel.preferredMaxLayoutWidth - preferredWidth) > 0.5
        else {
            return false
        }
        titleLabel.preferredMaxLayoutWidth = preferredWidth
        detailLabel.preferredMaxLayoutWidth = preferredWidth
        titleLabel.invalidateIntrinsicContentSize()
        detailLabel.invalidateIntrinsicContentSize()
        textStack.invalidateIntrinsicContentSize()
        invalidateIntrinsicContentSize()
        superview?.invalidateIntrinsicContentSize()
        superview?.superview?.invalidateIntrinsicContentSize()
        return true
    }

    private func preferredTextHeight() -> CGFloat {
        let labels = [titleLabel, detailLabel].filter { !$0.isHidden && !$0.stringValue.isEmpty }
        guard !labels.isEmpty else { return 0 }
        let textHeight = labels
            .map { preferredHeight(for: $0) }
            .reduce(0, +)
        return textHeight + textStack.spacing * CGFloat(max(labels.count - 1, 0))
    }

    private func preferredHeight(for label: NSTextField) -> CGFloat {
        let font = label.font ?? FlowTypography.appKit(.body)
        let width = label.preferredMaxLayoutWidth > 0
            ? label.preferredMaxLayoutWidth
            : max(bounds.width, superview?.bounds.width ?? 0)
        guard width > 0 else {
            return ceil(font.ascender - font.descender + font.leading)
        }
        let rect = (label.stringValue as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return ceil(rect.height)
    }
}

final class PermissionSettingsCardAppKitView: AppKitSettingsCardBaseView, AppKitSettingsCardStateView {
    var onShowPermissionReminderChanged: ((Bool) -> Void)?
    var onAllowLaunchAtLoginChanged: ((Bool) -> Void)?
    var onTerminalContentPreviewsChanged: ((Bool) -> Void)?
    var onAccessibilityAction: (() -> Void)?
    var onScreenCaptureAction: (() -> Void)?

    private let showPermissionReminderSwitch = NSSwitch()
    private let allowLaunchAtLoginSwitch = NSSwitch()
    private let terminalContentPreviewsSwitch = NSSwitch()
    private let accessibilityRow: PermissionStatusControlRowView<FlowSettingsActionButton>
    private let screenCaptureRow: PermissionStatusControlRowView<FlowSettingsActionButton>
    private lazy var allowLaunchAtLoginRow = AppKitSettingsCardBaseView.makeControlRow(
        title: "",
        control: allowLaunchAtLoginSwitch
    )
    private lazy var permissionReminderRow = AppKitSettingsCardBaseView.makeControlRow(
        title: "",
        control: showPermissionReminderSwitch
    )
    private lazy var terminalContentPreviewsRow = PermissionStatusControlRowView(
        control: terminalContentPreviewsSwitch
    )
    private var isApplyingState = false
    private var currentState: PermissionSettingsCardState?

    override init(frame frameRect: NSRect) {
        accessibilityRow = PermissionStatusControlRowView(
            control: FlowSettingsActionButton(),
            controlWidth: 96
        )
        screenCaptureRow = PermissionStatusControlRowView(
            control: FlowSettingsActionButton(),
            controlWidth: 96
        )
        super.init(frame: frameRect)
        accessibilityRow.control.target = self
        accessibilityRow.control.action = #selector(handleAccessibilityAction)
        screenCaptureRow.control.target = self
        screenCaptureRow.control.action = #selector(handleScreenCaptureAction)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        accessibilityRow = PermissionStatusControlRowView(
            control: FlowSettingsActionButton(),
            controlWidth: 96
        )
        screenCaptureRow = PermissionStatusControlRowView(
            control: FlowSettingsActionButton(),
            controlWidth: 96
        )
        super.init(coder: coder)
        accessibilityRow.control.target = self
        accessibilityRow.control.action = #selector(handleAccessibilityAction)
        screenCaptureRow.control.target = self
        screenCaptureRow.control.action = #selector(handleScreenCaptureAction)
        buildViewHierarchy()
    }

    func update(with state: PermissionSettingsCardState) {
        guard currentState != state else { return }
        currentState = state

        isApplyingState = true
        showPermissionReminderSwitch.state = state.showPermissionReminder ? .on : .off
        allowLaunchAtLoginSwitch.state = state.allowLaunchAtLogin ? .on : .off
        terminalContentPreviewsSwitch.state = state.terminalContentPreviewsEnabled ? .on : .off
        isApplyingState = false

        let language = state.language
        allowLaunchAtLoginRow.updateTitle(
            AppStrings.text(.permissionLaunchAtLoginToggle, language: language)
        )
        permissionReminderRow.updateTitle(
            AppStrings.text(.permissionHomeReminderToggle, language: language)
        )
        accessibilityRow.control.update(
            title: state.accessibilityButtonTitle,
            accessibilityLabel: state.accessibilityPermissionActionLabel,
            tooltip: state.accessibilityPermissionActionLabel,
            style: .preset(state.accessibilityTrusted ? .primaryAction : .secondaryAction)
        )
        accessibilityRow.update(
            text: state.accessibilityStatusText,
            detail: AppStrings.text(.permissionAccessibilityDetail, language: language),
            statusColor: state.accessibilityTrusted ? .systemGreen : .systemOrange
        )
        screenCaptureRow.control.update(
            title: state.screenCaptureButtonTitle,
            accessibilityLabel: state.screenCapturePermissionActionLabel,
            tooltip: state.screenCapturePermissionActionLabel,
            style: .preset(state.screenCaptureTrusted ? .primaryAction : .secondaryAction)
        )
        screenCaptureRow.update(
            text: state.screenCaptureStatusText,
            detail: AppStrings.text(.permissionScreenDetail, language: language),
            statusColor: state.screenCaptureTrusted ? .systemGreen : .systemOrange
        )
        terminalContentPreviewsRow.update(
            text: AppStrings.text(.permissionTerminalContentPreviewToggle, language: language),
            detail: AppStrings.text(.permissionTerminalContentPreviewDetail, language: language),
            statusColor: .labelColor
        )
        invalidateIntrinsicContentSize()
    }

    private func buildViewHierarchy() {
        showPermissionReminderSwitch.target = self
        showPermissionReminderSwitch.action = #selector(handleShowPermissionReminderChanged)
        allowLaunchAtLoginSwitch.target = self
        allowLaunchAtLoginSwitch.action = #selector(handleAllowLaunchAtLoginChanged)
        terminalContentPreviewsSwitch.target = self
        terminalContentPreviewsSwitch.action = #selector(handleTerminalContentPreviewsChanged)
        allowLaunchAtLoginSwitch.setFlowTabTestingIdentifier(
            "flowtab.settings.permission.launch-at-login"
        )
        showPermissionReminderSwitch.setFlowTabTestingIdentifier(
            "flowtab.settings.permission.reminder"
        )
        terminalContentPreviewsSwitch.setFlowTabTestingIdentifier(
            "flowtab.settings.permission.terminal-content-previews"
        )
        accessibilityRow.control.setFlowTabTestingIdentifier(
            "flowtab.settings.permission.accessibility-action"
        )
        screenCaptureRow.control.setFlowTabTestingIdentifier(
            "flowtab.settings.permission.screen-capture-action"
        )

        addFullWidthArrangedSubview(allowLaunchAtLoginRow)
        addFullWidthArrangedSubview(permissionReminderRow)
        addFullWidthArrangedSubview(accessibilityRow)
        addFullWidthArrangedSubview(screenCaptureRow)
        addFullWidthArrangedSubview(terminalContentPreviewsRow)
    }

    @objc private func handleShowPermissionReminderChanged(_ sender: NSSwitch) {
        guard !isApplyingState else { return }
        onShowPermissionReminderChanged?(sender.state == .on)
    }

    @objc private func handleAllowLaunchAtLoginChanged(_ sender: NSSwitch) {
        guard !isApplyingState else { return }
        onAllowLaunchAtLoginChanged?(sender.state == .on)
    }

    @objc private func handleTerminalContentPreviewsChanged(_ sender: NSSwitch) {
        guard !isApplyingState else { return }
        onTerminalContentPreviewsChanged?(sender.state == .on)
    }

    @objc private func handleAccessibilityAction() {
        onAccessibilityAction?()
    }

    @objc private func handleScreenCaptureAction() {
        onScreenCaptureAction?()
    }
}
