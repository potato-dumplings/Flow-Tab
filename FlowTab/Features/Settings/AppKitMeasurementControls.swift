import AppKit

extension NSView {
    func preferredFittingSize(forWidth width: CGFloat?) -> CGSize {
        let widthConstraint: NSLayoutConstraint?
        let normalizedWidth = width.flatMap { proposedWidth -> CGFloat? in
            guard proposedWidth.isFinite, proposedWidth > 0 else { return nil }
            return proposedWidth
        }

        if let normalizedWidth {
            // SwiftUI may pass `.infinity`/`nan` during measurement; AppKit crashes if that becomes a constraint constant.
            widthConstraint = widthAnchor.constraint(equalToConstant: normalizedWidth)
            widthConstraint?.priority = .defaultHigh
            widthConstraint?.isActive = true
        } else {
            widthConstraint = nil
        }

        layoutSubtreeIfNeeded()
        let fitted = fittingSize
        widthConstraint?.isActive = false
        return fitted
    }
}

final class FlowCapsuleSegmentedControl: NSView {
    var onSelectionChanged: ((String) -> Void)?

    private var options: [(id: String, title: String)]
    private let stackView = NSStackView()
    private var buttonsByID: [String: NSButton] = [:]
    private var selectedID: String?

    init(options: [(id: String, title: String)]) {
        self.options = options
        super.init(frame: .zero)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        self.options = []
        super.init(coder: coder)
        buildViewHierarchy()
    }

    override var intrinsicContentSize: NSSize {
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let widestTitle = options
            .map { ($0.title as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        let segmentWidth = ceil(widestTitle) + 28
        let spacing = CGFloat(max(options.count - 1, 0)) * stackView.spacing
        let preferredWidth = segmentWidth * CGFloat(max(options.count, 1)) + spacing + 4
        return NSSize(width: max(240, preferredWidth), height: 32)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func updateSelection(id: String) {
        guard selectedID != id else { return }
        selectedID = id
        setAccessibilityValue(selectedID ?? "")
        updateAppearance()
    }

    func configure(options: [(id: String, title: String)]) {
        self.options = options
        let optionIDs = Set(options.map { $0.id })
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        buttonsByID.removeAll()
        if let selectedID, !optionIDs.contains(selectedID) {
            self.selectedID = options.first?.id
        }
        buildOptionButtons()
        setAccessibilityValue(selectedID ?? "")
        updateAppearance()
        invalidateIntrinsicContentSize()
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
            heightAnchor.constraint(equalToConstant: 32),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)
        ])

        buildOptionButtons()
        updateAppearance()
    }

    private func buildOptionButtons() {
        for option in options {
            let button = NSButton(title: option.title, target: self, action: #selector(handleButtonPressed(_:)))
            button.setFlowTabTestingIdentifier(option.id)
            button.setButtonType(.momentaryChange)
            button.isBordered = false
            button.focusRingType = .none
            button.translatesAutoresizingMaskIntoConstraints = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 9
            button.layer?.masksToBounds = true
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
            stackView.addArrangedSubview(button)
            buttonsByID[option.id] = button
        }
    }

    @objc private func handleButtonPressed(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        selectedID = id
        setAccessibilityValue(selectedID ?? "")
        updateAppearance()
        onSelectionChanged?(id)
    }

    private func updateAppearance() {
        guard let layer else { return }
        layer.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
        layer.cornerRadius = 12
        layer.borderWidth = 1
        layer.borderColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor

        for (id, button) in buttonsByID {
            let isSelected = id == selectedID
            button.layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor : NSColor.clear.cgColor
            let titleColor = isSelected ? NSColor.controlAccentColor : NSColor.labelColor
            button.attributedTitle = NSAttributedString(
                string: button.title,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: titleColor
                ]
            )
        }
    }
}

final class FlowGradientActionButton: NSButton {
    var tone: FlowActionButtonTone = .grayDominant {
        didSet { updateAppearance() }
    }

    private let gradientLayer = CAGradientLayer()
    private let borderLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy()
    }

    override var intrinsicContentSize: NSSize {
        let titleWidth = attributedTitle.size().width
        return NSSize(width: max(96, ceil(titleWidth) + 32), height: 30)
    }

    override func layout() {
        super.layout()
        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func update(title: String, symbolName: String? = nil, tone: FlowActionButtonTone) {
        self.title = title
        self.tone = tone
        if let symbolName {
            image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        } else {
            image = nil
        }
        updateAppearance()
        invalidateIntrinsicContentSize()
    }

    private func buildViewHierarchy() {
        wantsLayer = true
        isBordered = false
        focusRingType = .none
        setButtonType(.momentaryPushIn)
        imagePosition = .imageLeading
        imageScaling = .scaleProportionallyDown
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
        heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true

        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.addSublayer(gradientLayer)
        layer?.addSublayer(borderLayer)
        updateAppearance()
    }

    private func updateAppearance() {
        wantsLayer = true
        let appearance = effectiveAppearance
        let cornerRadius = bounds.height / 2
        gradientLayer.frame = bounds
        gradientLayer.cornerRadius = cornerRadius
        gradientLayer.colors = gradientColors(for: tone, appearance: appearance)

        borderLayer.frame = bounds
        borderLayer.path = CGPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.lineWidth = 1
        borderLayer.strokeColor = borderColor(for: tone, appearance: appearance)

        layer?.cornerRadius = cornerRadius
        layer?.shadowColor = shadowColor(for: tone, appearance: appearance)
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: 2)

        let titleColor = appearance.flowTabResolvedColor {
            tone == .blueDominant
                ? NSColor.white
                : NSColor.labelColor.withAlphaComponent(0.78)
        }
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: titleColor
            ]
        )
        contentTintColor = titleColor
    }

    private func gradientColors(for tone: FlowActionButtonTone, appearance: NSAppearance) -> [CGColor] {
        switch tone {
        case .grayDominant:
            return [
                appearance.flowTabResolvedCGColor { NSColor.labelColor.withAlphaComponent(0.12) },
                appearance.flowTabResolvedCGColor { NSColor.labelColor.withAlphaComponent(0.09) },
                appearance.flowTabResolvedCGColor { NSColor.controlAccentColor.withAlphaComponent(0.26) }
            ]
        case .blueDominant:
            return [
                appearance.flowTabResolvedCGColor { NSColor.controlAccentColor.withAlphaComponent(0.94) },
                appearance.flowTabResolvedCGColor { NSColor.controlAccentColor.withAlphaComponent(0.76) },
                appearance.flowTabResolvedCGColor { NSColor.labelColor.withAlphaComponent(0.18) }
            ]
        }
    }

    private func borderColor(for tone: FlowActionButtonTone, appearance: NSAppearance) -> CGColor {
        switch tone {
        case .grayDominant:
            return appearance.flowTabResolvedCGColor { NSColor.labelColor.withAlphaComponent(0.24) }
        case .blueDominant:
            return appearance.flowTabResolvedCGColor { NSColor.controlAccentColor.withAlphaComponent(0.55) }
        }
    }

    private func shadowColor(for tone: FlowActionButtonTone, appearance: NSAppearance) -> CGColor {
        switch tone {
        case .grayDominant:
            return appearance.flowTabResolvedCGColor { NSColor.labelColor.withAlphaComponent(0.08) }
        case .blueDominant:
            return appearance.flowTabResolvedCGColor { NSColor.controlAccentColor.withAlphaComponent(0.20) }
        }
    }
}

final class FlowSoftTextField: NSView {
    let textField = NSTextField(string: "")

    private var isEditing = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 72, height: 28)
    }

    override func layout() {
        super.layout()
        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func setEditing(_ editing: Bool) {
        guard isEditing != editing else { return }
        isEditing = editing
        updateAppearance()
    }

    private func buildViewHierarchy() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
        widthAnchor.constraint(equalToConstant: 72).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.isBezeled = false
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.placeholderString = "0.75"
        textField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textField.alignment = .center
        textField.setContentHuggingPriority(.required, for: .vertical)
        textField.setContentCompressionResistancePriority(.required, for: .vertical)
        addSubview(textField)

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
            textField.heightAnchor.constraint(equalToConstant: 16)
        ])

        updateAppearance()
    }

    private func updateAppearance() {
        guard let layer else { return }

        let isDark = effectiveAppearance.isFlowTabDarkInterface
        let borderColor: NSColor
        let backgroundColor: NSColor

        if isEditing {
            borderColor = .controlAccentColor.withAlphaComponent(isDark ? 0.55 : 0.35)
            backgroundColor = isDark
                ? NSColor.white.withAlphaComponent(0.10)
                : NSColor.white.withAlphaComponent(0.98)
            layer.shadowColor = NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
            layer.shadowOpacity = 1
            layer.shadowRadius = 5
            layer.shadowOffset = .zero
        } else {
            borderColor = isDark
                ? NSColor.white.withAlphaComponent(0.10)
                : NSColor.black.withAlphaComponent(0.08)
            backgroundColor = isDark
                ? NSColor.white.withAlphaComponent(0.05)
                : NSColor.white.withAlphaComponent(0.84)
            layer.shadowOpacity = 0
        }

        layer.cornerRadius = 9
        layer.borderWidth = 1
        layer.borderColor = borderColor.cgColor
        layer.backgroundColor = backgroundColor.cgColor
    }
}
