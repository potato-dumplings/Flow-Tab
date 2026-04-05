import SwiftUI
import AppKit

struct AppKitPermissionSettingsCardContent: NSViewRepresentable {
    @Binding var showPermissionReminder: Bool
    let accessibilityTrusted: Bool
    let screenCaptureTrusted: Bool
    let onAccessibilityAction: () -> Void
    let onScreenCaptureAction: () -> Void

    final class Coordinator {
        var showPermissionReminder: Binding<Bool>
        var onAccessibilityAction: () -> Void
        var onScreenCaptureAction: () -> Void

        init(
            showPermissionReminder: Binding<Bool>,
            onAccessibilityAction: @escaping () -> Void,
            onScreenCaptureAction: @escaping () -> Void
        ) {
            self.showPermissionReminder = showPermissionReminder
            self.onAccessibilityAction = onAccessibilityAction
            self.onScreenCaptureAction = onScreenCaptureAction
        }

        func update(
            showPermissionReminder: Binding<Bool>,
            onAccessibilityAction: @escaping () -> Void,
            onScreenCaptureAction: @escaping () -> Void
        ) {
            self.showPermissionReminder = showPermissionReminder
            self.onAccessibilityAction = onAccessibilityAction
            self.onScreenCaptureAction = onScreenCaptureAction
        }

        func setShowPermissionReminder(_ value: Bool) {
            showPermissionReminder.wrappedValue = value
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
            onAccessibilityAction: onAccessibilityAction,
            onScreenCaptureAction: onScreenCaptureAction
        )
    }

    func makeNSView(context: Context) -> PermissionSettingsCardAppKitView {
        let view = PermissionSettingsCardAppKitView()
        connect(view, coordinator: context.coordinator)
        return view
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: PermissionSettingsCardAppKitView,
        context: Context
    ) -> CGSize? {
        nsView.preferredFittingSize(forWidth: proposal.width)
    }

    func updateNSView(_ nsView: PermissionSettingsCardAppKitView, context: Context) {
        context.coordinator.update(
            showPermissionReminder: $showPermissionReminder,
            onAccessibilityAction: onAccessibilityAction,
            onScreenCaptureAction: onScreenCaptureAction
        )
        connect(nsView, coordinator: context.coordinator)
        nsView.update(
            with: PermissionSettingsCardState(
                showPermissionReminder: showPermissionReminder,
                accessibilityTrusted: accessibilityTrusted,
                screenCaptureTrusted: screenCaptureTrusted
            )
        )
    }

    private func connect(_ view: PermissionSettingsCardAppKitView, coordinator: Coordinator) {
        view.onShowPermissionReminderChanged = { coordinator.setShowPermissionReminder($0) }
        view.onAccessibilityAction = { coordinator.triggerAccessibilityAction() }
        view.onScreenCaptureAction = { coordinator.triggerScreenCaptureAction() }
    }
}

struct PermissionSettingsCardState: Equatable {
    let showPermissionReminder: Bool
    let accessibilityTrusted: Bool
    let screenCaptureTrusted: Bool

    var accessibilityStatusText: String {
        accessibilityTrusted
            ? AppStrings.text(.permissionAccessibilityGranted)
            : AppStrings.text(.permissionAccessibilityDenied)
    }

    var accessibilityButtonTitle: String {
        accessibilityTrusted
            ? AppStrings.text(.permissionAccessibilityClose)
            : AppStrings.text(.permissionAccessibilityRequest)
    }

    var screenCaptureStatusText: String {
        screenCaptureTrusted
            ? AppStrings.text(.permissionScreenGranted)
            : AppStrings.text(.permissionScreenDenied)
    }

    var screenCaptureButtonTitle: String {
        screenCaptureTrusted
            ? AppStrings.text(.permissionScreenClose)
            : AppStrings.text(.permissionScreenRequest)
    }
}

private final class PermissionStatusActionRowView: NSView {
    let titleLabel = AppKitSettingsCardBaseView.makeStatusLabel()
    let detailLabel = AppKitSettingsCardBaseView.makeBodyLabel()
    let actionButton: FlowGradientActionButton
    private let stackView = NSStackView()
    private let textStack = NSStackView()

    override init(frame frameRect: NSRect) {
        actionButton = FlowGradientActionButton()
        super.init(frame: .zero)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        actionButton = FlowGradientActionButton()
        super.init(coder: coder)
        buildViewHierarchy()
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
        stackView.addArrangedSubview(actionButton)
        actionButton.widthAnchor.constraint(equalToConstant: 166).isActive = true

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
    }

    func update(text: String, detail: String, isGranted: Bool, buttonTitle: String) {
        titleLabel.stringValue = text
        titleLabel.textColor = isGranted ? .systemGreen : .systemOrange
        detailLabel.stringValue = detail
        actionButton.update(
            title: buttonTitle,
            tone: isGranted ? .blueDominant : .grayDominant
        )
    }
}

final class PermissionSettingsCardAppKitView: AppKitSettingsCardBaseView {
    var onShowPermissionReminderChanged: ((Bool) -> Void)?
    var onAccessibilityAction: (() -> Void)?
    var onScreenCaptureAction: (() -> Void)?

    private let showPermissionReminderSwitch = NSSwitch()
    private let accessibilityRow: PermissionStatusActionRowView
    private let screenCaptureRow: PermissionStatusActionRowView
    private var isApplyingState = false
    private var currentState: PermissionSettingsCardState?

    override init(frame frameRect: NSRect) {
        accessibilityRow = PermissionStatusActionRowView()
        screenCaptureRow = PermissionStatusActionRowView()
        super.init(frame: frameRect)
        accessibilityRow.actionButton.target = self
        accessibilityRow.actionButton.action = #selector(handleAccessibilityAction)
        screenCaptureRow.actionButton.target = self
        screenCaptureRow.actionButton.action = #selector(handleScreenCaptureAction)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        accessibilityRow = PermissionStatusActionRowView()
        screenCaptureRow = PermissionStatusActionRowView()
        super.init(coder: coder)
        accessibilityRow.actionButton.target = self
        accessibilityRow.actionButton.action = #selector(handleAccessibilityAction)
        screenCaptureRow.actionButton.target = self
        screenCaptureRow.actionButton.action = #selector(handleScreenCaptureAction)
        buildViewHierarchy()
    }

    func update(with state: PermissionSettingsCardState) {
        guard currentState != state else { return }
        currentState = state

        isApplyingState = true
        showPermissionReminderSwitch.state = state.showPermissionReminder ? .on : .off
        isApplyingState = false

        accessibilityRow.update(
            text: state.accessibilityStatusText,
            detail: AppStrings.text(.permissionAccessibilityDetail),
            isGranted: state.accessibilityTrusted,
            buttonTitle: state.accessibilityButtonTitle
        )
        screenCaptureRow.update(
            text: state.screenCaptureStatusText,
            detail: AppStrings.text(.permissionScreenDetail),
            isGranted: state.screenCaptureTrusted,
            buttonTitle: state.screenCaptureButtonTitle
        )
        invalidateIntrinsicContentSize()
    }

    private func buildViewHierarchy() {
        showPermissionReminderSwitch.target = self
        showPermissionReminderSwitch.action = #selector(handleShowPermissionReminderChanged)
        showPermissionReminderSwitch.setFlowTabTestingIdentifier(
            "flowtab.settings.permission.reminder"
        )
        accessibilityRow.actionButton.setFlowTabTestingIdentifier(
            "flowtab.settings.permission.accessibility-action"
        )
        screenCaptureRow.actionButton.setFlowTabTestingIdentifier(
            "flowtab.settings.permission.screen-capture-action"
        )

        addFullWidthArrangedSubview(
            AppKitSettingsCardBaseView.makeControlRow(
                title: AppStrings.text(.permissionHomeReminderToggle),
                control: showPermissionReminderSwitch
            )
        )
        addFullWidthArrangedSubview(accessibilityRow)
        addFullWidthArrangedSubview(screenCaptureRow)
    }

    @objc private func handleShowPermissionReminderChanged(_ sender: NSSwitch) {
        guard !isApplyingState else { return }
        onShowPermissionReminderChanged?(sender.state == .on)
    }

    @objc private func handleAccessibilityAction() {
        onAccessibilityAction?()
    }

    @objc private func handleScreenCaptureAction() {
        onScreenCaptureAction?()
    }
}

