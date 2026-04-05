import SwiftUI
import AppKit

struct AppKitWindowBehaviorSettingsCardContent: NSViewRepresentable {
    let windowLayerAutoEnterDelayText: String
    @Binding var autoRestoreMinimizedWindowOnSwitch: Bool
    @Binding var hideMinimizedAppsFromAppLayer: Bool
    let onWindowLayerAutoEnterDelayTextChanged: (String) -> Void
    let onWindowLayerAutoEnterDelayTextCommitted: () -> Void
    let onWindowLayerAutoEnterDelayEditingChanged: (Bool) -> Void

    final class Coordinator {
        var autoRestoreMinimizedWindowOnSwitch: Binding<Bool>
        var hideMinimizedAppsFromAppLayer: Binding<Bool>
        var onWindowLayerAutoEnterDelayTextChanged: (String) -> Void
        var onWindowLayerAutoEnterDelayTextCommitted: () -> Void
        var onWindowLayerAutoEnterDelayEditingChanged: (Bool) -> Void

        init(
            autoRestoreMinimizedWindowOnSwitch: Binding<Bool>,
            hideMinimizedAppsFromAppLayer: Binding<Bool>,
            onWindowLayerAutoEnterDelayTextChanged: @escaping (String) -> Void,
            onWindowLayerAutoEnterDelayTextCommitted: @escaping () -> Void,
            onWindowLayerAutoEnterDelayEditingChanged: @escaping (Bool) -> Void
        ) {
            self.autoRestoreMinimizedWindowOnSwitch = autoRestoreMinimizedWindowOnSwitch
            self.hideMinimizedAppsFromAppLayer = hideMinimizedAppsFromAppLayer
            self.onWindowLayerAutoEnterDelayTextChanged = onWindowLayerAutoEnterDelayTextChanged
            self.onWindowLayerAutoEnterDelayTextCommitted = onWindowLayerAutoEnterDelayTextCommitted
            self.onWindowLayerAutoEnterDelayEditingChanged = onWindowLayerAutoEnterDelayEditingChanged
        }

        func update(
            autoRestoreMinimizedWindowOnSwitch: Binding<Bool>,
            hideMinimizedAppsFromAppLayer: Binding<Bool>,
            onWindowLayerAutoEnterDelayTextChanged: @escaping (String) -> Void,
            onWindowLayerAutoEnterDelayTextCommitted: @escaping () -> Void,
            onWindowLayerAutoEnterDelayEditingChanged: @escaping (Bool) -> Void
        ) {
            self.autoRestoreMinimizedWindowOnSwitch = autoRestoreMinimizedWindowOnSwitch
            self.hideMinimizedAppsFromAppLayer = hideMinimizedAppsFromAppLayer
            self.onWindowLayerAutoEnterDelayTextChanged = onWindowLayerAutoEnterDelayTextChanged
            self.onWindowLayerAutoEnterDelayTextCommitted = onWindowLayerAutoEnterDelayTextCommitted
            self.onWindowLayerAutoEnterDelayEditingChanged = onWindowLayerAutoEnterDelayEditingChanged
        }

        func setAutoRestoreMinimizedWindowOnSwitch(_ value: Bool) {
            autoRestoreMinimizedWindowOnSwitch.wrappedValue = value
        }

        func setHideMinimizedAppsFromAppLayer(_ value: Bool) {
            hideMinimizedAppsFromAppLayer.wrappedValue = value
        }

        func changeDelayText(_ value: String) {
            onWindowLayerAutoEnterDelayTextChanged(value)
        }

        func commitDelayText() {
            onWindowLayerAutoEnterDelayTextCommitted()
        }

        func setDelayEditing(_ isEditing: Bool) {
            onWindowLayerAutoEnterDelayEditingChanged(isEditing)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            autoRestoreMinimizedWindowOnSwitch: $autoRestoreMinimizedWindowOnSwitch,
            hideMinimizedAppsFromAppLayer: $hideMinimizedAppsFromAppLayer,
            onWindowLayerAutoEnterDelayTextChanged: onWindowLayerAutoEnterDelayTextChanged,
            onWindowLayerAutoEnterDelayTextCommitted: onWindowLayerAutoEnterDelayTextCommitted,
            onWindowLayerAutoEnterDelayEditingChanged: onWindowLayerAutoEnterDelayEditingChanged
        )
    }

    func makeNSView(context: Context) -> WindowBehaviorSettingsCardAppKitView {
        let view = WindowBehaviorSettingsCardAppKitView()
        connect(view, coordinator: context.coordinator)
        return view
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: WindowBehaviorSettingsCardAppKitView,
        context: Context
    ) -> CGSize? {
        nsView.preferredFittingSize(forWidth: proposal.width)
    }

    func updateNSView(_ nsView: WindowBehaviorSettingsCardAppKitView, context: Context) {
        context.coordinator.update(
            autoRestoreMinimizedWindowOnSwitch: $autoRestoreMinimizedWindowOnSwitch,
            hideMinimizedAppsFromAppLayer: $hideMinimizedAppsFromAppLayer,
            onWindowLayerAutoEnterDelayTextChanged: onWindowLayerAutoEnterDelayTextChanged,
            onWindowLayerAutoEnterDelayTextCommitted: onWindowLayerAutoEnterDelayTextCommitted,
            onWindowLayerAutoEnterDelayEditingChanged: onWindowLayerAutoEnterDelayEditingChanged
        )
        connect(nsView, coordinator: context.coordinator)
        nsView.update(
            with: WindowBehaviorSettingsCardState(
                windowLayerAutoEnterDelayText: windowLayerAutoEnterDelayText,
                autoRestoreMinimizedWindowOnSwitch: autoRestoreMinimizedWindowOnSwitch,
                hideMinimizedAppsFromAppLayer: hideMinimizedAppsFromAppLayer
            )
        )
    }

    private func connect(_ view: WindowBehaviorSettingsCardAppKitView, coordinator: Coordinator) {
        view.onWindowLayerAutoEnterDelayTextChanged = { coordinator.changeDelayText($0) }
        view.onWindowLayerAutoEnterDelayTextCommitted = { coordinator.commitDelayText() }
        view.onWindowLayerAutoEnterDelayEditingChanged = { coordinator.setDelayEditing($0) }
        view.onAutoRestoreMinimizedWindowOnSwitchChanged = {
            coordinator.setAutoRestoreMinimizedWindowOnSwitch($0)
        }
        view.onHideMinimizedAppsFromAppLayerChanged = {
            coordinator.setHideMinimizedAppsFromAppLayer($0)
        }
    }
}

struct WindowBehaviorSettingsCardState: Equatable {
    let windowLayerAutoEnterDelayText: String
    let autoRestoreMinimizedWindowOnSwitch: Bool
    let hideMinimizedAppsFromAppLayer: Bool
}

final class WindowBehaviorSettingsCardAppKitView: AppKitSettingsCardBaseView, NSTextFieldDelegate {
    var onWindowLayerAutoEnterDelayTextChanged: ((String) -> Void)?
    var onWindowLayerAutoEnterDelayTextCommitted: (() -> Void)?
    var onWindowLayerAutoEnterDelayEditingChanged: ((Bool) -> Void)?
    var onAutoRestoreMinimizedWindowOnSwitchChanged: ((Bool) -> Void)?
    var onHideMinimizedAppsFromAppLayerChanged: ((Bool) -> Void)?

    private let delayInputField = FlowSoftTextField()
    private let autoRestoreMinimizedWindowSwitch = NSSwitch()
    private let hideMinimizedAppsSwitch = NSSwitch()
    private let noteLabel = AppKitSettingsCardBaseView.makeBodyLabel()
    private var isApplyingState = false
    private var currentState: WindowBehaviorSettingsCardState?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy()
    }

    func containsDelayInputDescendant(_ view: NSView?) -> Bool {
        guard let view else { return false }
        return view.isDescendant(of: delayInputField)
    }

    func ownsDelayInputFirstResponder(_ responder: NSResponder?) -> Bool {
        if let view = responder as? NSView {
            return view.isDescendant(of: delayInputField)
        }

        if let editor = responder as? NSTextView,
            let editedView = editor.delegate as? NSView
        {
            return editedView.isDescendant(of: delayInputField)
        }

        return false
    }

    func update(with state: WindowBehaviorSettingsCardState) {
        guard currentState != state else { return }
        currentState = state

        isApplyingState = true
        if delayInputField.textField.stringValue != state.windowLayerAutoEnterDelayText {
            delayInputField.textField.stringValue = state.windowLayerAutoEnterDelayText
        }
        autoRestoreMinimizedWindowSwitch.state = state.autoRestoreMinimizedWindowOnSwitch ? .on : .off
        hideMinimizedAppsSwitch.state = state.hideMinimizedAppsFromAppLayer ? .on : .off
        isApplyingState = false

        noteLabel.stringValue = AppStrings.text(.windowBehaviorNote)
        invalidateIntrinsicContentSize()
    }

    private func buildViewHierarchy() {
        delayInputField.setFlowTabTestingIdentifier("flowtab.settings.window.auto-enter-delay")
        autoRestoreMinimizedWindowSwitch.setFlowTabTestingIdentifier(
            "flowtab.settings.window.auto-restore-minimized"
        )
        hideMinimizedAppsSwitch.setFlowTabTestingIdentifier(
            "flowtab.settings.window.hide-minimized-apps"
        )
        let delayTextField = delayInputField.textField
        delayTextField.setFlowTabTestingIdentifier("flowtab.settings.window.auto-enter-delay.input")
        delayTextField.delegate = self

        let delayUnitLabel = NSTextField(labelWithString: AppStrings.text(.windowBehaviorSecondUnit))
        delayUnitLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        delayUnitLabel.textColor = .secondaryLabelColor

        let delayControl = NSStackView(views: [delayInputField, delayUnitLabel])
        delayControl.orientation = .horizontal
        delayControl.alignment = .centerY
        delayControl.spacing = 8
        delayControl.translatesAutoresizingMaskIntoConstraints = false
        delayControl.setContentHuggingPriority(.required, for: .vertical)
        delayControl.setContentCompressionResistancePriority(.required, for: .vertical)

        autoRestoreMinimizedWindowSwitch.target = self
        autoRestoreMinimizedWindowSwitch.action = #selector(handleAutoRestoreMinimizedWindowSwitchChanged)
        hideMinimizedAppsSwitch.target = self
        hideMinimizedAppsSwitch.action = #selector(handleHideMinimizedAppsSwitchChanged)

        addFullWidthArrangedSubview(
            AppKitSettingsCardBaseView.makeControlRow(
                title: AppStrings.text(.windowBehaviorAutoEnterDelay),
                control: delayControl
            )
        )
        addFullWidthArrangedSubview(
            AppKitSettingsCardBaseView.makeControlRow(
                title: AppStrings.text(.windowBehaviorAutoRestoreMinimized),
                control: autoRestoreMinimizedWindowSwitch
            )
        )
        addFullWidthArrangedSubview(
            AppKitSettingsCardBaseView.makeControlRow(
                title: AppStrings.text(.windowBehaviorHideMinimizedApps),
                control: hideMinimizedAppsSwitch
            )
        )
        addFullWidthArrangedSubview(noteLabel)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard !isApplyingState else { return }
        guard notification.object as? NSTextField === delayInputField.textField else { return }
        let rawText = delayInputField.textField.stringValue
        let sanitizedText = WindowLayerPreferencesStore.sanitizeAutoEnterDelayText(rawText)
        if sanitizedText != rawText {
            isApplyingState = true
            delayInputField.textField.stringValue = sanitizedText
            isApplyingState = false
        }
        onWindowLayerAutoEnterDelayTextChanged?(sanitizedText)
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        guard notification.object as? NSTextField === delayInputField.textField else { return }
        delayInputField.setEditing(true)
        onWindowLayerAutoEnterDelayEditingChanged?(true)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard notification.object as? NSTextField === delayInputField.textField else { return }
        delayInputField.setEditing(false)
        onWindowLayerAutoEnterDelayEditingChanged?(false)
        onWindowLayerAutoEnterDelayTextCommitted?()
    }

    @objc private func handleAutoRestoreMinimizedWindowSwitchChanged(_ sender: NSSwitch) {
        guard !isApplyingState else { return }
        onAutoRestoreMinimizedWindowOnSwitchChanged?(sender.state == .on)
    }

    @objc private func handleHideMinimizedAppsSwitchChanged(_ sender: NSSwitch) {
        guard !isApplyingState else { return }
        onHideMinimizedAppsFromAppLayerChanged?(sender.state == .on)
    }
}

