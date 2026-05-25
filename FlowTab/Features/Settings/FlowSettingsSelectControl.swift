import AppKit

final class FlowSettingsSelectControl: NSView, FlowSettingsAppearanceRefreshable {
    var onSelectionChanged: ((String) -> Void)?

    var isEnabled = true {
        didSet {
            dropdownControl.isEnabled = isEnabled
            refreshStyle()
        }
    }

    private let dropdownControl = FlowDropdownControl(frame: .zero)
    private var options: [(id: String, title: String)] = []
    private var selectedID: String?
    private var targetAppearance = FlowSettingsStyleResolver.defaultAppearance
    private var style = FlowSettingsSelectStyle.preset(.formSelect)
    private var heightConstraint: NSLayoutConstraint?

    override var intrinsicContentSize: NSSize {
        NSSize(width: preferredControlWidth, height: style.metrics.height)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy()
    }

    func configure(options: [(id: String, title: String)], style: FlowSettingsSelectStyle = .preset(.formSelect)) {
        self.options = options
        self.style = style
        if options.contains(where: { $0.id == selectedID }) == false {
            selectedID = options.first?.id
        }
        refreshStyle()
        invalidateIntrinsicContentSize()
    }

    func updateSelection(id: String) {
        guard options.contains(where: { $0.id == id }) else { return }
        selectedID = id
        dropdownControl.updateSelection(id: id)
        setAccessibilityValue(id)
        invalidateIntrinsicContentSize()
    }

    func applySettingsAppearance(_ appearance: NSAppearance) {
        targetAppearance = appearance
        self.appearance = appearance
        dropdownControl.appearance = appearance
        refreshStyle()
    }

    func refreshStyle() {
        heightConstraint?.constant = style.metrics.height
        synchronizeTestingIdentifier()
        dropdownControl.isEnabled = isEnabled
        dropdownControl.configure(
            options: options.map { FlowDropdownOption(id: $0.id, title: $0.title) },
            selectedID: selectedID,
            presentation: dropdownPresentation()
        )
        setAccessibilityElement(true)
        setAccessibilityRole(.popUpButton)
        setAccessibilityValue(selectedID ?? "")
        needsLayout = true
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        return dropdownControl.accessibilityPerformPress()
    }

    private var preferredControlWidth: CGFloat {
        let font = style.states.value(for: .normal).text?.font ?? .systemFont(ofSize: 13)
        return style.metrics.preferredWidth(for: options.map(\.title), font: font)
    }

    private func buildViewHierarchy() {
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)

        dropdownControl.translatesAutoresizingMaskIntoConstraints = false
        dropdownControl.onSelectionChanged = { [weak self] id in
            self?.commitSelection(id)
        }
        addSubview(dropdownControl)

        let heightConstraint = heightAnchor.constraint(equalToConstant: style.metrics.height)
        self.heightConstraint = heightConstraint
        NSLayoutConstraint.activate([
            heightConstraint,
            dropdownControl.leadingAnchor.constraint(equalTo: leadingAnchor),
            dropdownControl.topAnchor.constraint(equalTo: topAnchor),
            dropdownControl.trailingAnchor.constraint(equalTo: trailingAnchor),
            dropdownControl.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        refreshStyle()
    }

    private func commitSelection(_ id: String) {
        guard options.contains(where: { $0.id == id }) else { return }
        let didChange = selectedID != id
        selectedID = id
        setAccessibilityValue(id)
        if didChange {
            onSelectionChanged?(id)
        }
    }

    private func synchronizeTestingIdentifier() {
        let rawIdentifier = identifier?.rawValue ?? accessibilityIdentifier()
        if !rawIdentifier.isEmpty {
            dropdownControl.identifier = NSUserInterfaceItemIdentifier(rawIdentifier)
            dropdownControl.setAccessibilityIdentifier(rawIdentifier)
        }
    }

    private func dropdownPresentation() -> FlowDropdownPresentation {
        let base = FlowDropdownPresentation.form(targetAppearance: targetAppearance)
        let metrics = FlowDropdownMetrics(
            height: style.metrics.height,
            minimumWidth: style.metrics.minimumWidth,
            horizontalPadding: style.metrics.horizontalPadding,
            iconSpacing: max(style.metrics.iconSpacing, 24),
            menuRowHeight: 42,
            menuVerticalPadding: 8,
            menuHorizontalInset: 8,
            menuArrowHeight: 10,
            maximumVisibleRows: 8
        )
        let normalText = style.states.value(for: .normal).text
        return FlowDropdownPresentation(
            targetAppearance: targetAppearance,
            metrics: metrics,
            font: normalText?.font ?? base.font,
            cornerRadius: style.states.value(for: .normal).surface?.cornerRadius ?? base.cornerRadius,
            controlStyles: [
                .normal: controlStyle(for: .normal, fallback: base.style(for: .normal)),
                .hovered: controlStyle(for: .hovered, fallback: base.style(for: .hovered)),
                .focused: controlStyle(for: .focused, fallback: base.style(for: .focused)),
                .expanded: controlStyle(for: .expanded, fallback: base.style(for: .expanded)),
                .disabled: controlStyle(for: .disabled, fallback: base.style(for: .disabled))
            ],
            menuStyle: base.menuStyle
        )
    }

    private func controlStyle(
        for state: FlowSettingsSelectState,
        fallback: FlowDropdownControlStyle
    ) -> FlowDropdownControlStyle {
        let resolved = style.states.value(for: state)
        guard let surface = resolved.surface else { return fallback }
        let text = resolved.text ?? style.states.value(for: .normal).text
        return FlowDropdownControlStyle(
            backgroundColor: resolvedBackgroundColor(for: surface) ?? fallback.backgroundColor,
            borderColor: FlowSettingsStyleResolver.color(surface.borderColor, appearance: targetAppearance),
            borderWidth: surface.borderWidth,
            textColor: text.map { FlowSettingsStyleResolver.color($0.color, appearance: targetAppearance) }
                ?? fallback.textColor,
            chevronColor: fallback.chevronColor,
            shadowColor: surface.shadow.map { FlowSettingsStyleResolver.color($0.color, appearance: targetAppearance) }
                ?? fallback.shadowColor,
            shadowOpacity: surface.shadow?.opacity ?? fallback.shadowOpacity,
            shadowRadius: surface.shadow?.radius ?? fallback.shadowRadius,
            shadowOffset: surface.shadow?.offset ?? fallback.shadowOffset
        )
    }

    private func resolvedBackgroundColor(for surface: FlowSettingsSurfaceToken) -> NSColor? {
        switch surface.fill {
        case let .color(colorToken):
            return FlowSettingsStyleResolver.color(colorToken, appearance: targetAppearance)
        case let .gradient(tokens):
            return tokens.first.map { FlowSettingsStyleResolver.color($0, appearance: targetAppearance) }
        }
    }
}
