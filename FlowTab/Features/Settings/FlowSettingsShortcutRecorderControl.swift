import AppKit
import Carbon
import FlowTabCore

final class FlowSettingsShortcutRecorderControl:
    NSControl,
    FlowSettingsAppearanceRefreshable
{
    var onKeysChanged: ((SwitcherHotkeyKeySet) -> Void)?
    var onInteraction: (() -> Void)?

    private(set) var recordedKeys: SwitcherHotkeyKeySet = [.option]
    private(set) var isRecording = false

    private let valueLabel = NSTextField(labelWithString: "")
    private let style = FlowSettingsSelectStyle.preset(.formSelect)
    private var recordingPrompt = ""
    private var keyRequiredPrompt = ""
    private var pressedKeys = SwitcherHotkeyKeySet()
    private var pendingKeys = SwitcherHotkeyKeySet()
    private var recordingEventMonitor: Any?
    private var targetAppearance =
        FlowSettingsStyleResolver.defaultAppearance
    private var heightConstraint: NSLayoutConstraint?

    override var acceptsFirstResponder: Bool { isEnabled }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 220, height: style.metrics.height)
    }

    override var isEnabled: Bool {
        didSet {
            if !isEnabled {
                endRecording()
            }
            refreshStyle()
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

    deinit {
        removeRecordingEventMonitor()
    }

    func update(
        keys: SwitcherHotkeyKeySet,
        recordingPrompt: String,
        keyRequiredPrompt: String,
        accessibilityLabel: String
    ) {
        recordedKeys = keys
        self.recordingPrompt = recordingPrompt
        self.keyRequiredPrompt = keyRequiredPrompt
        setAccessibilityLabel(accessibilityLabel)
        if !isRecording {
            updateDisplayedValue(currentDisplayValue)
        }
        refreshStyle()
    }

    func applySettingsAppearance(_ appearance: NSAppearance) {
        targetAppearance = appearance
        self.appearance = appearance
        valueLabel.appearance = appearance
        refreshStyle()
    }

    func refreshStyle() {
        guard let layer else { return }
        let state: FlowSettingsSelectState
        if !isEnabled {
            state = .disabled
        } else if isRecording || window?.firstResponder === self {
            state = .focused
        } else {
            state = .normal
        }
        let resolved = style.states.value(for: state)
        if let surface = resolved.surface {
            FlowSettingsStyleResolver.apply(
                surface: surface,
                to: layer,
                appearance: targetAppearance
            )
        }
        if let text = resolved.text {
            valueLabel.font = text.font
            valueLabel.textColor = FlowSettingsStyleResolver.color(
                text.color,
                appearance: targetAppearance
            )
            valueLabel.alignment = text.alignment
            valueLabel.lineBreakMode = text.lineBreakMode
        }
        alphaValue = isEnabled ? 1 : 0.55
        heightConstraint?.constant = style.metrics.height
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let layer else { return }
        layer.shadowPath = CGPath(
            roundedRect: layer.bounds,
            cornerWidth: layer.cornerRadius,
            cornerHeight: layer.cornerRadius,
            transform: nil
        )
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: isEnabled ? .pointingHand : .arrow)
    }

    override func mouseDown(with _: NSEvent) {
        guard isEnabled else { return }
        beginRecording()
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled else {
            super.keyDown(with: event)
            return
        }
        guard isRecording else {
            if event.keyCode == UInt16(kVK_Return)
                || event.keyCode == UInt16(kVK_Space)
            {
                beginRecording()
                return
            }
            super.keyDown(with: event)
            return
        }
        recordKeyDown(event)
    }

    override func keyUp(with event: NSEvent) {
        guard isRecording else {
            super.keyUp(with: event)
            return
        }
        recordKeyUp(event)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }
        recordFlagsChanged(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.type {
        case .keyDown:
            recordKeyDown(event)
            return true
        case .keyUp:
            recordKeyUp(event)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        refreshStyle()
        return becameFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        endRecording()
        return resigned
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        beginRecording()
        return true
    }

    private func buildViewHierarchy() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        focusRingType = .exterior
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)

        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.maximumNumberOfLines = 1
        addSubview(valueLabel)

        let heightConstraint = heightAnchor.constraint(
            equalToConstant: style.metrics.height
        )
        self.heightConstraint = heightConstraint
        NSLayoutConstraint.activate([
            heightConstraint,
            valueLabel.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: style.metrics.horizontalPadding
            ),
            valueLabel.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -style.metrics.horizontalPadding
            ),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        updateDisplayedValue(currentDisplayValue)
        refreshStyle()
    }

    private func beginRecording() {
        onInteraction?()
        window?.makeFirstResponder(self)
        isRecording = true
        pressedKeys = SwitcherHotkeyKeySet()
        pendingKeys = SwitcherHotkeyKeySet()
        installRecordingEventMonitor()
        updateDisplayedValue(recordingPrompt)
        refreshStyle()
    }

    private func endRecording() {
        removeRecordingEventMonitor()
        guard isRecording else { return }
        isRecording = false
        pressedKeys = SwitcherHotkeyKeySet()
        pendingKeys = SwitcherHotkeyKeySet()
        updateDisplayedValue(currentDisplayValue)
        refreshStyle()
    }

    private func recordKeyDown(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        pressedKeys.replaceModifiers(
            with: KeyModifier(eventModifierFlags: event.modifierFlags)
        )
        let key = SwitcherHotkeyKey(keyCode: event.keyCode)
        if key.modifier == nil {
            pressedKeys.insert(key)
        }
        observeCurrentPressedKeys()
    }

    private func recordKeyUp(_ event: NSEvent) {
        pressedKeys.replaceModifiers(
            with: KeyModifier(eventModifierFlags: event.modifierFlags)
        )
        let key = SwitcherHotkeyKey(keyCode: event.keyCode)
        if key.modifier == nil {
            pressedKeys.remove(key)
        }
        observeCurrentPressedKeys()
    }

    private func recordFlagsChanged(_ event: NSEvent) {
        pressedKeys.replaceModifiers(
            with: KeyModifier(eventModifierFlags: event.modifierFlags)
        )
        observeCurrentPressedKeys()
    }

    private func installRecordingEventMonitor() {
        removeRecordingEventMonitor()
        recordingEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp, .flagsChanged]
        ) { [weak self] event in
            guard let self, self.isRecording else { return event }
            switch event.type {
            case .keyDown:
                self.recordKeyDown(event)
            case .keyUp:
                self.recordKeyUp(event)
            case .flagsChanged:
                self.recordFlagsChanged(event)
            default:
                break
            }
            return nil
        }
    }

    private func removeRecordingEventMonitor() {
        guard let recordingEventMonitor else { return }
        NSEvent.removeMonitor(recordingEventMonitor)
        self.recordingEventMonitor = nil
    }

    private func observeCurrentPressedKeys() {
        pendingKeys = pendingKeys.union(pressedKeys)
        if !pressedKeys.isEmpty {
            updateDisplayedValue(pendingKeys.displayName)
            return
        }
        guard !pendingKeys.isEmpty else {
            updateDisplayedValue(keyRequiredPrompt)
            return
        }
        commit(keys: pendingKeys)
    }

    private func commit(keys: SwitcherHotkeyKeySet) {
        removeRecordingEventMonitor()
        recordedKeys = keys
        isRecording = false
        pressedKeys = SwitcherHotkeyKeySet()
        pendingKeys = SwitcherHotkeyKeySet()
        updateDisplayedValue(currentDisplayValue)
        refreshStyle()

        onKeysChanged?(keys)
    }

    private var currentDisplayValue: String {
        recordedKeys.displayName
    }

    private func updateDisplayedValue(_ value: String) {
        valueLabel.stringValue = value
        setAccessibilityValue(value)
    }
}
