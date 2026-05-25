import SwiftUI
import AppKit

struct AppKitWindowBehaviorSettingsCardContent: AppKitSettingsCardRepresentable {
    typealias NSViewType = WindowBehaviorSettingsCardAppKitView

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

    func makeCardView(context _: Context) -> WindowBehaviorSettingsCardAppKitView {
        WindowBehaviorSettingsCardAppKitView()
    }

    func updateCoordinator(_ coordinator: Coordinator) {
        coordinator.update(
            autoRestoreMinimizedWindowOnSwitch: $autoRestoreMinimizedWindowOnSwitch,
            hideMinimizedAppsFromAppLayer: $hideMinimizedAppsFromAppLayer,
            onWindowLayerAutoEnterDelayTextChanged: onWindowLayerAutoEnterDelayTextChanged,
            onWindowLayerAutoEnterDelayTextCommitted: onWindowLayerAutoEnterDelayTextCommitted,
            onWindowLayerAutoEnterDelayEditingChanged: onWindowLayerAutoEnterDelayEditingChanged
        )
    }

    func connect(_ view: WindowBehaviorSettingsCardAppKitView, coordinator: Coordinator) {
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

    func makeState() -> WindowBehaviorSettingsCardState {
        WindowBehaviorSettingsCardState(
            windowLayerAutoEnterDelayText: windowLayerAutoEnterDelayText,
            autoRestoreMinimizedWindowOnSwitch: autoRestoreMinimizedWindowOnSwitch,
            hideMinimizedAppsFromAppLayer: hideMinimizedAppsFromAppLayer,
            appLanguageRaw: AppLanguagePreferencesStore.load().rawValue
        )
    }
}

struct WindowBehaviorSettingsCardState: Equatable {
    let windowLayerAutoEnterDelayText: String
    let autoRestoreMinimizedWindowOnSwitch: Bool
    let hideMinimizedAppsFromAppLayer: Bool
    let appLanguageRaw: String

    var language: AppLanguage {
        AppLanguagePreferencesStore.resolve(rawValue: appLanguageRaw)
    }
}

final class WindowBehaviorSettingsCardAppKitView: AppKitSettingsCardBaseView, AppKitSettingsCardStateView,
    NSTextFieldDelegate {
    var onWindowLayerAutoEnterDelayTextChanged: ((String) -> Void)?
    var onWindowLayerAutoEnterDelayTextCommitted: (() -> Void)?
    var onWindowLayerAutoEnterDelayEditingChanged: ((Bool) -> Void)?
    var onAutoRestoreMinimizedWindowOnSwitchChanged: ((Bool) -> Void)?
    var onHideMinimizedAppsFromAppLayerChanged: ((Bool) -> Void)?

    private let delayInputField = FlowSoftTextField()
    private let autoRestoreMinimizedWindowSwitch = NSSwitch()
    private let hideMinimizedAppsSwitch = NSSwitch()
    private let noteLabel = AppKitSettingsCardBaseView.makeBodyLabel()
    private let delayUnitLabel = NSTextField(labelWithString: "")
    private lazy var delayRow = AppKitSettingsCardBaseView.makeControlRow(
        title: "",
        control: delayControl
    )
    private lazy var autoRestoreMinimizedWindowRow = AppKitSettingsCardBaseView.makeControlRow(
        title: "",
        control: autoRestoreMinimizedWindowSwitch
    )
    private lazy var hideMinimizedAppsRow = AppKitSettingsCardBaseView.makeControlRow(
        title: "",
        control: hideMinimizedAppsSwitch
    )
    private lazy var delayControl: NSStackView = {
        let stack = NSStackView(views: [delayInputField, delayUnitLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setContentHuggingPriority(.required, for: .vertical)
        stack.setContentCompressionResistancePriority(.required, for: .vertical)
        return stack
    }()
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

        let language = state.language
        delayUnitLabel.stringValue = AppStrings.text(.windowBehaviorSecondUnit, language: language)
        delayRow.updateTitle(AppStrings.text(.windowBehaviorAutoEnterDelay, language: language))
        autoRestoreMinimizedWindowRow.updateTitle(
            AppStrings.text(.windowBehaviorAutoRestoreMinimized, language: language)
        )
        hideMinimizedAppsRow.updateTitle(
            AppStrings.text(.windowBehaviorHideMinimizedApps, language: language)
        )
        noteLabel.stringValue = AppStrings.text(.windowBehaviorNote, language: language)
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

        delayUnitLabel.font = FlowTypography.appKit(.bodyMonospaced)
        delayUnitLabel.textColor = .secondaryLabelColor

        autoRestoreMinimizedWindowSwitch.target = self
        autoRestoreMinimizedWindowSwitch.action = #selector(handleAutoRestoreMinimizedWindowSwitchChanged)
        hideMinimizedAppsSwitch.target = self
        hideMinimizedAppsSwitch.action = #selector(handleHideMinimizedAppsSwitchChanged)

        addFullWidthArrangedSubview(delayRow)
        addFullWidthArrangedSubview(autoRestoreMinimizedWindowRow)
        addFullWidthArrangedSubview(hideMinimizedAppsRow)
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
