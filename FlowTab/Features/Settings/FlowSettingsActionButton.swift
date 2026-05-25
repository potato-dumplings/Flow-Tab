import AppKit

final class FlowSettingsActionButton: NSButton, FlowSettingsAppearanceRefreshable {
    private let gradientLayer = CAGradientLayer()
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovering = false
    private var hasFocus = false
    private var buttonTitle = ""
    private var style = FlowSettingsActionButtonStyle.preset(.secondaryAction)
    private var targetAppearance = FlowSettingsStyleResolver.defaultAppearance

    override var intrinsicContentSize: NSSize {
        let width = style.metrics.preferredWidth(
            for: [buttonTitle],
            font: style.states.value(for: .normal).text?.font ?? FlowTypography.appKit(.bodyStrong)
        )
        return NSSize(width: width, height: style.metrics.height)
    }

    override var isEnabled: Bool {
        didSet {
            if !isEnabled {
                isHovering = false
                hasFocus = false
            }
            refreshStyle()
        }
    }

    override var isHighlighted: Bool {
        didSet { refreshStyle() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy()
    }

    override func layout() {
        super.layout()
        gradientLayer.frame = bounds
        refreshLayerFrames()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshStyle()
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

    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled {
            addCursorRect(bounds, cursor: .pointingHand)
        }
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

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        hasFocus = became
        refreshStyle()
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        hasFocus = false
        refreshStyle()
        return resigned
    }

    func update(
        title: String,
        accessibilityLabel: String?,
        tooltip: String? = nil,
        symbolName: String? = nil,
        style: FlowSettingsActionButtonStyle
    ) {
        buttonTitle = title
        self.title = title
        self.style = style
        toolTip = tooltip
        setAccessibilityLabel(accessibilityLabel)
        image = symbolName.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: accessibilityLabel ?? title) }
        refreshStyle()
        invalidateIntrinsicContentSize()
    }

    func applySettingsAppearance(_ appearance: NSAppearance) {
        targetAppearance = appearance
        refreshStyle()
    }

    func refreshStyle() {
        wantsLayer = true
        let currentState = resolvedState()
        let stateStyle = style.states.value(for: currentState)
        let normalStyle = style.states.value(for: .normal)
        let pressedStyle = style.states.value(for: .pressed)
        let textToken = stateStyle.text ?? normalStyle.text

        if let textToken {
            attributedTitle = FlowSettingsStyleResolver.attributedString(
                buttonTitle,
                token: textToken,
                appearance: targetAppearance
            )
            attributedAlternateTitle = FlowSettingsStyleResolver.attributedString(
                buttonTitle,
                token: pressedStyle.text ?? textToken,
                appearance: targetAppearance
            )
            contentTintColor = FlowSettingsStyleResolver.color(textToken.color, appearance: targetAppearance)
        }

        guard let layer else { return }
        let surface = stateStyle.surface ?? normalStyle.surface
        if let surface {
            FlowSettingsStyleResolver.apply(surface: surface, to: layer, appearance: targetAppearance)
            layer.cornerRadius = bounds.height > 0 ? min(surface.cornerRadius, bounds.height / 2) : surface.cornerRadius
        }
        gradientLayer.isHidden = stateStyle.gradient == nil
        if let gradient = stateStyle.gradient ?? normalStyle.gradient {
            gradientLayer.colors = gradient.map { FlowSettingsStyleResolver.cgColor($0, appearance: targetAppearance) }
        }
        refreshLayerFrames()
    }

    private func buildViewHierarchy() {
        wantsLayer = true
        isBordered = false
        focusRingType = .none
        alignment = .center
        imagePosition = .imageLeading
        imageScaling = .scaleProportionallyDown
        setButtonType(.momentaryPushIn)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
        heightAnchor.constraint(greaterThanOrEqualToConstant: style.metrics.height).isActive = true

        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.addSublayer(gradientLayer)
        refreshStyle()
    }

    private func resolvedState() -> FlowSettingsActionButtonState {
        guard isEnabled else { return .disabled }
        if isHighlighted { return .pressed }
        if hasFocus && isHovering { return .focusedHovered }
        if isHovering { return .hovered }
        if hasFocus { return .focused }
        return .normal
    }

    private func refreshLayerFrames() {
        let radius = bounds.height > 0 ? min(style.metrics.height / 2, bounds.height / 2) : style.metrics.height / 2
        gradientLayer.frame = bounds
        gradientLayer.cornerRadius = radius
    }
}
