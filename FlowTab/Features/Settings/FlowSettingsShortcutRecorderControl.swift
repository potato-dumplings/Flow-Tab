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
    private let editIndicator = NSImageView()
    private let style = FlowSettingsSelectStyle.preset(.formSelect)
    private var recordingPrompt = ""
    private var keyRequiredPrompt = ""
    private var pressedKeys = SwitcherHotkeyKeySet()
    private var pendingKeys = SwitcherHotkeyKeySet()
    private var recordingEventMonitor: Any?
    private var windowResignKeyObserver: NSObjectProtocol?
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovering = false
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
                isHovering = false
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
        removeRecordingObservers()
    }

    func update(
        keys: SwitcherHotkeyKeySet,
        recordingPrompt: String,
        keyRequiredPrompt: String,
        accessibilityLabel: String,
        editHint: String = ""
    ) {
        recordedKeys = keys
        self.recordingPrompt = recordingPrompt
        self.keyRequiredPrompt = keyRequiredPrompt
        toolTip = editHint
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
        editIndicator.appearance = appearance
        refreshStyle()
    }

    func refreshStyle() {
        guard let layer else { return }
        let state: FlowSettingsSelectState
        if !isEnabled {
            state = .disabled
        } else if isRecording || window?.firstResponder === self {
            state = .focused
        } else if isHovering {
            state = .hovered
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
        let indicatorColor: FlowSettingsColorToken
        switch state {
        case .hovered, .focused, .expanded:
            indicatorColor = .controlAccent(alpha: 0.92)
        case .normal, .disabled:
            indicatorColor = .semantic(.secondaryLabel, alpha: 0.72)
        }
        editIndicator.contentTintColor = FlowSettingsStyleResolver.color(
            indicatorColor,
            appearance: targetAppearance
        )
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
        super.resetCursorRects()
        addCursorRect(bounds, cursor: isEnabled ? .pointingHand : .arrow)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        guard isEnabled else { return }
        isHovering = true
        refreshStyle()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovering = false
        refreshStyle()
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
        valueLabel.setAccessibilityElement(false)
        addSubview(valueLabel)

        editIndicator.translatesAutoresizingMaskIntoConstraints = false
        editIndicator.image = NSImage(
            systemSymbolName: "pencil",
            accessibilityDescription: nil
        )
        editIndicator.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 11,
            weight: .medium
        )
        editIndicator.imageScaling = .scaleProportionallyDown
        editIndicator.setAccessibilityElement(false)
        addSubview(editIndicator)

        let heightConstraint = heightAnchor.constraint(
            equalToConstant: style.metrics.height
        )
        self.heightConstraint = heightConstraint
        NSLayoutConstraint.activate([
            heightConstraint,
            valueLabel.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: style.metrics.horizontalPadding
                    + style.metrics.iconSpacing
            ),
            valueLabel.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -style.metrics.horizontalPadding
                    - style.metrics.iconSpacing
            ),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            editIndicator.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -style.metrics.horizontalPadding
            ),
            editIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            editIndicator.widthAnchor.constraint(equalToConstant: 12),
            editIndicator.heightAnchor.constraint(equalToConstant: 12)
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
        installRecordingObservers()
        updateDisplayedValue(recordingPrompt)
        refreshStyle()
    }

    private func endRecording() {
        removeRecordingObservers()
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

    private func installRecordingObservers() {
        removeRecordingObservers()
        recordingEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [
                .keyDown,
                .keyUp,
                .flagsChanged,
                .leftMouseDown,
                .rightMouseDown,
                .otherMouseDown
            ]
        ) { [weak self] event in
            guard let self, self.isRecording else { return event }
            switch event.type {
            case .keyDown:
                self.recordKeyDown(event)
            case .keyUp:
                self.recordKeyUp(event)
            case .flagsChanged:
                self.recordFlagsChanged(event)
            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                if !self.containsMouseEvent(event) {
                    self.cancelRecording()
                }
                return event
            default:
                break
            }
            return nil
        }
        if let window {
            windowResignKeyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.cancelRecording()
            }
        }
    }

    private func removeRecordingObservers() {
        if let recordingEventMonitor {
            NSEvent.removeMonitor(recordingEventMonitor)
            self.recordingEventMonitor = nil
        }
        if let windowResignKeyObserver {
            NotificationCenter.default.removeObserver(windowResignKeyObserver)
            self.windowResignKeyObserver = nil
        }
    }

    private func containsMouseEvent(_ event: NSEvent) -> Bool {
        guard event.window === window else { return false }
        return bounds.contains(convert(event.locationInWindow, from: nil))
    }

    private func cancelRecording() {
        guard isRecording else { return }
        if window?.firstResponder === self,
            window?.makeFirstResponder(nil) == true
        {
            return
        }
        endRecording()
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
        removeRecordingObservers()
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
