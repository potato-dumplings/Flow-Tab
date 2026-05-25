import AppKit

final class FlowSettingsSegmentedControl: NSView, FlowSettingsAppearanceRefreshable {
    var onSelectionChanged: ((String) -> Void)?

    private var options: [(id: String, title: String)]
    private let stackView = NSStackView()
    private var buttonsByID: [String: SegmentButton] = [:]
    private var selectedID: String?
    private var targetAppearance = FlowSettingsStyleResolver.defaultAppearance
    private let metrics = FlowSettingsControlMetrics(height: 32, minimumWidth: 240, horizontalPadding: 14, iconSpacing: 0)

    init(options: [(id: String, title: String)]) {
        self.options = options
        super.init(frame: .zero)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        options = []
        super.init(coder: coder)
        buildViewHierarchy()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: metrics.preferredWidth(
                for: options.map(\.title),
                font: FlowTypography.appKit(.bodyEmphasized),
                segmentCount: options.count
            ),
            height: metrics.height
        )
    }

    override func layout() {
        super.layout()
        layer?.frame = bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshStyle()
    }

    func updateSelection(id: String) {
        guard selectedID != id else {
            refreshStyle()
            return
        }
        selectedID = id
        setAccessibilityValue(selectedID ?? "")
        refreshStyle()
    }

    func configure(options: [(id: String, title: String)]) {
        self.options = options
        let ids = Set(options.map(\.id))
        if let selectedID, !ids.contains(selectedID) {
            self.selectedID = options.first?.id
        }
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        buttonsByID.removeAll()
        buildOptionButtons()
        setAccessibilityValue(selectedID ?? "")
        refreshStyle()
        invalidateIntrinsicContentSize()
    }

    func applySettingsAppearance(_ appearance: NSAppearance) {
        targetAppearance = appearance
        refreshStyle()
    }

    func refreshStyle() {
        wantsLayer = true
        guard let layer else { return }
        let containerSurface = FlowSettingsSurfaceToken(
            fill: .color(.semantic(.label, alpha: 0.05)),
            borderColor: .semantic(.label, alpha: 0.12),
            borderWidth: 1,
            cornerRadius: 12,
            shadow: nil
        )
        FlowSettingsStyleResolver.apply(surface: containerSurface, to: layer, appearance: targetAppearance)
        for (id, button) in buttonsByID {
            let selected = id == selectedID
            button.applySettingsAppearance(targetAppearance)
            button.updateStyle(selected: selected)
        }
    }

    private func buildViewHierarchy() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
        setAccessibilityValue(selectedID ?? "")

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fillEqually
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: metrics.height),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)
        ])

        buildOptionButtons()
        refreshStyle()
    }

    private func buildOptionButtons() {
        for option in options {
            let button = SegmentButton(title: option.title, target: self, action: #selector(handleButtonPressed(_:)))
            button.optionID = option.id
            button.setFlowTabTestingIdentifier(option.id)
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
            stackView.addArrangedSubview(button)
            buttonsByID[option.id] = button
        }
    }

    @objc private func handleButtonPressed(_ sender: SegmentButton) {
        selectedID = sender.optionID
        setAccessibilityValue(selectedID ?? "")
        refreshStyle()
        onSelectionChanged?(sender.optionID)
    }
}

private final class SegmentButton: NSButton, FlowSettingsAppearanceRefreshable {
    var optionID = ""
    private var targetAppearance = FlowSettingsStyleResolver.defaultAppearance
    private var selected = false
    private var hovering = false

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

    func updateStyle(selected: Bool) {
        self.selected = selected
        refreshStyle()
    }

    func applySettingsAppearance(_ appearance: NSAppearance) {
        targetAppearance = appearance
        refreshStyle()
    }

    func refreshStyle() {
        wantsLayer = true
        let state: FlowSettingsSegmentState
        if !isEnabled {
            state = .disabled
        } else if selected && isHighlighted {
            state = .selectedPressed
        } else if selected && hovering {
            state = .selectedHovered
        } else if selected {
            state = .selected
        } else if isHighlighted {
            state = .pressed
        } else if hovering {
            state = .hovered
        } else {
            state = .normal
        }

        let selectedLike = state == .selected || state == .selectedHovered || state == .selectedPressed
        layer?.backgroundColor = selectedLike
            ? FlowSettingsStyleResolver.cgColor(.controlAccent(alpha: 0.18), appearance: targetAppearance)
            : NSColor.clear.cgColor
        layer?.cornerRadius = 9
        layer?.masksToBounds = true
        let titleColor: FlowSettingsColorToken = selectedLike ? .controlAccent(alpha: 1) : .semantic(.label, alpha: 1)
        attributedTitle = FlowSettingsStyleResolver.attributedString(
            title,
            token: FlowSettingsTextToken(
                font: FlowTypography.appKit(.bodyEmphasized),
                color: titleColor,
                alignment: .center,
                lineBreakMode: .byClipping
            ),
            appearance: targetAppearance
        )
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        hovering = true
        refreshStyle()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hovering = false
        refreshStyle()
    }

    private func buildViewHierarchy() {
        isBordered = false
        focusRingType = .none
        setButtonType(.momentaryChange)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        refreshStyle()
    }
}
