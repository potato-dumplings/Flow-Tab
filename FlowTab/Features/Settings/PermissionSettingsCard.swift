import SwiftUI
import AppKit

struct AppKitPermissionSettingsCardContent: AppKitSettingsCardRepresentable {
    typealias NSViewType = PermissionSettingsCardAppKitView

    @Binding var showPermissionReminder: Bool
    @Binding var allowLaunchAtLogin: Bool
    let accessibilityTrusted: Bool
    let screenCaptureTrusted: Bool
    let onLaunchAtLoginChanged: (Bool) -> Void
    let onAccessibilityAction: () -> Void
    let onScreenCaptureAction: () -> Void

    final class Coordinator {
        var showPermissionReminder: Binding<Bool>
        var allowLaunchAtLogin: Binding<Bool>
        var onLaunchAtLoginChanged: (Bool) -> Void
        var onAccessibilityAction: () -> Void
        var onScreenCaptureAction: () -> Void

        init(
            showPermissionReminder: Binding<Bool>,
            allowLaunchAtLogin: Binding<Bool>,
            onLaunchAtLoginChanged: @escaping (Bool) -> Void,
            onAccessibilityAction: @escaping () -> Void,
            onScreenCaptureAction: @escaping () -> Void
        ) {
            self.showPermissionReminder = showPermissionReminder
            self.allowLaunchAtLogin = allowLaunchAtLogin
            self.onLaunchAtLoginChanged = onLaunchAtLoginChanged
            self.onAccessibilityAction = onAccessibilityAction
            self.onScreenCaptureAction = onScreenCaptureAction
        }

        func update(
            showPermissionReminder: Binding<Bool>,
            allowLaunchAtLogin: Binding<Bool>,
            onLaunchAtLoginChanged: @escaping (Bool) -> Void,
            onAccessibilityAction: @escaping () -> Void,
            onScreenCaptureAction: @escaping () -> Void
        ) {
            self.showPermissionReminder = showPermissionReminder
            self.allowLaunchAtLogin = allowLaunchAtLogin
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
            onLaunchAtLoginChanged: onLaunchAtLoginChanged,
            onAccessibilityAction: onAccessibilityAction,
            onScreenCaptureAction: onScreenCaptureAction
        )
    }

    func connect(_ view: PermissionSettingsCardAppKitView, coordinator: Coordinator) {
        view.onShowPermissionReminderChanged = { coordinator.setShowPermissionReminder($0) }
        view.onAllowLaunchAtLoginChanged = { coordinator.setAllowLaunchAtLogin($0) }
        view.onAccessibilityAction = { coordinator.triggerAccessibilityAction() }
        view.onScreenCaptureAction = { coordinator.triggerScreenCaptureAction() }
    }

    func makeState() -> PermissionSettingsCardState {
        PermissionSettingsCardState(
            showPermissionReminder: showPermissionReminder,
            allowLaunchAtLogin: allowLaunchAtLogin,
            accessibilityTrusted: accessibilityTrusted,
            screenCaptureTrusted: screenCaptureTrusted,
            appLanguageRaw: AppLanguagePreferencesStore.load().rawValue
        )
    }
}

struct PermissionSettingsCardState: Equatable {
    let showPermissionReminder: Bool
    let allowLaunchAtLogin: Bool
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
            ? AppStrings.text(.permissionAccessibilityClose, language: language)
            : AppStrings.text(.permissionAccessibilityRequest, language: language)
    }

    var screenCaptureStatusText: String {
        screenCaptureTrusted
            ? AppStrings.text(.permissionScreenGranted, language: language)
            : AppStrings.text(.permissionScreenDenied, language: language)
    }

    var screenCaptureButtonTitle: String {
        screenCaptureTrusted
            ? AppStrings.text(.permissionScreenClose, language: language)
            : AppStrings.text(.permissionScreenRequest, language: language)
    }

}

final class PermissionStatusControlRowView<Control: NSView>: NSView {
    let titleLabel = AppKitSettingsCardBaseView.makeStatusLabel()
    let detailLabel = AppKitSettingsCardBaseView.makeBodyLabel()
    let control: Control
    private let stackView = NSStackView()
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
        layoutSubtreeIfNeeded()
        return NSSize(width: NSView.noIntrinsicMetric, height: stackView.fittingSize.height)
    }

    private func buildViewHierarchy() {
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.detachesHiddenViews = true
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.setContentHuggingPriority(.required, for: .vertical)
        textStack.setContentCompressionResistancePriority(.required, for: .vertical)
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(detailLabel)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 10
        stackView.detachesHiddenViews = true
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.setContentHuggingPriority(.required, for: .vertical)
        stackView.setContentCompressionResistancePriority(.required, for: .vertical)
        addSubview(stackView)
        stackView.addArrangedSubview(textStack)
        stackView.addArrangedSubview(spacer)
        stackView.addArrangedSubview(control)
        if let controlWidth {
            AppKitSettingsCardBaseView.applyPreferredControlWidth(control, width: controlWidth)
        }

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func update(text: String, detail: String, statusColor: NSColor) {
        titleLabel.stringValue = text
        titleLabel.textColor = statusColor
        detailLabel.stringValue = detail
    }
}

final class PermissionSettingsCardAppKitView: AppKitSettingsCardBaseView, AppKitSettingsCardStateView {
    var onShowPermissionReminderChanged: ((Bool) -> Void)?
    var onAllowLaunchAtLoginChanged: ((Bool) -> Void)?
    var onAccessibilityAction: (() -> Void)?
    var onScreenCaptureAction: (() -> Void)?

    private let showPermissionReminderSwitch = NSSwitch()
    private let allowLaunchAtLoginSwitch = NSSwitch()
    private let accessibilityRow: PermissionStatusControlRowView<FlowGradientActionButton>
    private let screenCaptureRow: PermissionStatusControlRowView<FlowGradientActionButton>
    private lazy var allowLaunchAtLoginRow = AppKitSettingsCardBaseView.makeControlRow(
        title: "",
        control: allowLaunchAtLoginSwitch
    )
    private lazy var permissionReminderRow = AppKitSettingsCardBaseView.makeControlRow(
        title: "",
        control: showPermissionReminderSwitch
    )
    private var isApplyingState = false
    private var currentState: PermissionSettingsCardState?

    override init(frame frameRect: NSRect) {
        accessibilityRow = PermissionStatusControlRowView(
            control: FlowGradientActionButton(),
            controlWidth: 166
        )
        screenCaptureRow = PermissionStatusControlRowView(
            control: FlowGradientActionButton(),
            controlWidth: 166
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
            control: FlowGradientActionButton(),
            controlWidth: 166
        )
        screenCaptureRow = PermissionStatusControlRowView(
            control: FlowGradientActionButton(),
            controlWidth: 166
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
        isApplyingState = false

        let language = state.language
        allowLaunchAtLoginRow.updateTitle(
            AppStrings.text(.permissionLaunchAtLoginToggle, language: language)
        )
        permissionReminderRow.updateTitle(
            AppStrings.text(.permissionHomeReminderToggle, language: language)
        )
        accessibilityRow.update(
            text: state.accessibilityStatusText,
            detail: AppStrings.text(.permissionAccessibilityDetail, language: language),
            statusColor: state.accessibilityTrusted ? .systemGreen : .systemOrange
        )
        accessibilityRow.control.update(
            title: state.accessibilityButtonTitle,
            tone: state.accessibilityTrusted ? .blueDominant : .grayDominant
        )
        screenCaptureRow.update(
            text: state.screenCaptureStatusText,
            detail: AppStrings.text(.permissionScreenDetail, language: language),
            statusColor: state.screenCaptureTrusted ? .systemGreen : .systemOrange
        )
        screenCaptureRow.control.update(
            title: state.screenCaptureButtonTitle,
            tone: state.screenCaptureTrusted ? .blueDominant : .grayDominant
        )
        invalidateIntrinsicContentSize()
    }

    private func buildViewHierarchy() {
        showPermissionReminderSwitch.target = self
        showPermissionReminderSwitch.action = #selector(handleShowPermissionReminderChanged)
        allowLaunchAtLoginSwitch.target = self
        allowLaunchAtLoginSwitch.action = #selector(handleAllowLaunchAtLoginChanged)
        allowLaunchAtLoginSwitch.setFlowTabTestingIdentifier(
            "flowtab.settings.permission.launch-at-login"
        )
        showPermissionReminderSwitch.setFlowTabTestingIdentifier(
            "flowtab.settings.permission.reminder"
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
    }

    @objc private func handleShowPermissionReminderChanged(_ sender: NSSwitch) {
        guard !isApplyingState else { return }
        onShowPermissionReminderChanged?(sender.state == .on)
    }

    @objc private func handleAllowLaunchAtLoginChanged(_ sender: NSSwitch) {
        guard !isApplyingState else { return }
        onAllowLaunchAtLoginChanged?(sender.state == .on)
    }

    @objc private func handleAccessibilityAction() {
        onAccessibilityAction?()
    }

    @objc private func handleScreenCaptureAction() {
        onScreenCaptureAction?()
    }
}
