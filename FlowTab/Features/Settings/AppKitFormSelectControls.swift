import AppKit

private enum FlowFormSelectStyle {
    static func primaryTextColor(isDark: Bool, isEnabled: Bool) -> NSColor {
        guard isEnabled else {
            return secondaryTextColor(isDark: isDark, isEnabled: false)
        }
        return (isDark ? NSColor.white : NSColor.black)
            .withAlphaComponent(isDark ? 0.92 : 0.78)
    }

    static func secondaryTextColor(isDark: Bool, isEnabled: Bool) -> NSColor {
        if isDark {
            return NSColor.white.withAlphaComponent(isEnabled ? 0.68 : 0.42)
        }
        return NSColor.black.withAlphaComponent(isEnabled ? 0.56 : 0.36)
    }
}

private final class FlowFormSelectOptionButton: NSButton {
    var optionID = ""
    var isOptionSelected = false {
        didSet { updateAppearance() }
    }

    private var optionTitle = ""
    private var isHovering = false
    private var hoverTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy()
    }

    override var isEnabled: Bool {
        didSet {
            if !isEnabled {
                isHovering = false
            }
            updateAppearance()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
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
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovering = false
        updateAppearance()
    }

    func update(title: String, isSelected: Bool) {
        optionTitle = title
        self.title = title
        isOptionSelected = isSelected
        updateAppearance()
    }

    private func buildViewHierarchy() {
        wantsLayer = true
        isBordered = false
        focusRingType = .none
        alignment = .center
        imagePosition = .noImage
        setButtonType(.momentaryChange)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
        heightAnchor.constraint(equalToConstant: 30).isActive = true
        layer?.cornerRadius = 0
        updateAppearance()
    }

    private func updateAppearance() {
        guard let layer else { return }
        let isDark = effectiveAppearance.isFlowTabDarkInterface
        let hoverColor = NSColor.controlAccentColor.withAlphaComponent(isDark ? 0.18 : 0.10)
        layer.backgroundColor = (!isOptionSelected && isHovering && isEnabled) ? hoverColor.cgColor : NSColor.clear.cgColor
        layer.borderWidth = 0
        layer.borderColor = NSColor.clear.cgColor

        let titleColor: NSColor
        if !isEnabled {
            titleColor = FlowFormSelectStyle.secondaryTextColor(isDark: isDark, isEnabled: false)
        } else if isOptionSelected {
            titleColor = .controlAccentColor
        } else {
            titleColor = FlowFormSelectStyle.primaryTextColor(isDark: isDark, isEnabled: true)
        }

        let styledTitle = NSAttributedString(
            string: optionTitle,
            attributes: [
                .paragraphStyle: {
                    let style = NSMutableParagraphStyle()
                    style.alignment = .center
                    return style
                }(),
                .font: NSFont.systemFont(ofSize: 12.5, weight: isOptionSelected ? .semibold : .regular),
                .foregroundColor: titleColor
            ]
        )
        attributedTitle = styledTitle
        attributedAlternateTitle = styledTitle
    }
}

private final class FlowFormSelectMenuView: NSView {
    var onSelectionChanged: ((String) -> Void)?

    private let stackView = NSStackView()
    private var widthConstraint: NSLayoutConstraint?
    private var selectedID: String?
    private var optionIdentifierPrefix: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy()
    }

    override var intrinsicContentSize: NSSize {
        layoutSubtreeIfNeeded()
        return NSSize(
            width: widthConstraint?.constant ?? 120,
            height: stackView.fittingSize.height + 12
        )
    }

    override func layout() {
        super.layout()
        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func update(
        options: [(id: String, title: String)],
        selectedID: String?,
        preferredWidth: CGFloat,
        optionIdentifierPrefix: String?
    ) {
        self.selectedID = selectedID
        self.optionIdentifierPrefix = optionIdentifierPrefix

        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for option in options {
            let button = FlowFormSelectOptionButton(frame: .zero)
            button.optionID = option.id
            button.setFlowTabTestingIdentifier(optionTestingIdentifier(for: option.id))
            button.target = self
            button.action = #selector(handleOptionPressed(_:))
            button.update(title: option.title, isSelected: option.id == selectedID)
            stackView.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
        }

        widthConstraint?.constant = max(preferredWidth, 68)
        invalidateIntrinsicContentSize()
        needsLayout = true
        layoutSubtreeIfNeeded()
        updateAppearance()
    }

    private func buildViewHierarchy() {
        wantsLayer = true
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.distribution = .fillEqually
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        widthConstraint = widthAnchor.constraint(equalToConstant: 120)
        widthConstraint?.priority = .defaultHigh
        widthConstraint?.isActive = true

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        updateAppearance()
    }

    @objc private func handleOptionPressed(_ sender: NSButton) {
        guard let button = sender as? FlowFormSelectOptionButton else { return }
        onSelectionChanged?(button.optionID)
    }

    private func optionTestingIdentifier(for optionID: String) -> String {
        guard let optionIdentifierPrefix, !optionIdentifierPrefix.isEmpty else {
            return optionID
        }
        return "\(optionIdentifierPrefix).option.\(optionID)"
    }

    private func updateAppearance() {
        guard let layer else { return }
        if effectiveAppearance.isFlowTabDarkInterface {
            layer.backgroundColor = NSColor(
                red: 0.16,
                green: 0.16,
                blue: 0.18,
                alpha: 0.98
            ).cgColor
            layer.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
            layer.shadowOpacity = 0
        } else {
            layer.backgroundColor = NSColor.white.withAlphaComponent(0.99).cgColor
            layer.borderColor = NSColor.black.withAlphaComponent(0.12).cgColor
            layer.shadowColor = NSColor.black.withAlphaComponent(0.10).cgColor
            layer.shadowOpacity = 1
            layer.shadowRadius = 8
            layer.shadowOffset = CGSize(width: 0, height: 4)
        }
        layer.cornerRadius = 0
        layer.borderWidth = 1
    }
}

private final class FlowFormSelectMenuViewController: NSViewController {
    let menuView = FlowFormSelectMenuView(frame: .zero)
    var optionIdentifierPrefix: String?

    var onSelectionChanged: ((String) -> Void)? {
        didSet { menuView.onSelectionChanged = onSelectionChanged }
    }

    override func loadView() {
        view = menuView
    }

    func update(options: [(id: String, title: String)], selectedID: String?, preferredWidth: CGFloat) {
        menuView.update(
            options: options,
            selectedID: selectedID,
            preferredWidth: preferredWidth,
            optionIdentifierPrefix: optionIdentifierPrefix
        )
        preferredContentSize = menuView.intrinsicContentSize
    }
}

final class FlowFormSelectControl: NSView, NSPopoverDelegate {
    var onSelectionChanged: ((String) -> Void)?

    var isEnabled = true {
        didSet {
            if !isEnabled {
                popover.performClose(nil)
            }
            updateAppearance()
        }
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let chevronImageView = NSImageView()
    private let popover = NSPopover()
    private let menuViewController = FlowFormSelectMenuViewController()
    private let chevronSymbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
    private var options: [(id: String, title: String)] = []
    private var selectedID: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 120, height: 32)
    }

    override func layout() {
        super.layout()
        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            popover.performClose(nil)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        if popover.isShown {
            popover.performClose(nil)
            updateAppearance()
            return
        }

        menuViewController.onSelectionChanged = { [weak self] id in
            self?.handleSelectionChanged(id)
        }
        menuViewController.optionIdentifierPrefix = identifier?.rawValue
        menuViewController.update(
            options: options,
            selectedID: selectedID,
            preferredWidth: max(bounds.width, 68)
        )
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = effectiveAppearance
        popover.contentViewController = menuViewController
        popover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
        updateAppearance()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    func configure(options: [(id: String, title: String)]) {
        self.options = options
        if options.contains(where: { $0.id == selectedID }) == false {
            selectedID = options.first?.id
        }
        updateDisplayTitle()
        menuViewController.update(
            options: options,
            selectedID: selectedID,
            preferredWidth: max(bounds.width, intrinsicContentSize.width)
        )
    }

    func updateSelection(id: String) {
        guard options.contains(where: { $0.id == id }) else { return }
        guard selectedID != id else {
            updateAppearance()
            return
        }
        selectedID = id
        updateDisplayTitle()
        menuViewController.update(
            options: options,
            selectedID: selectedID,
            preferredWidth: max(bounds.width, intrinsicContentSize.width)
        )
        updateAppearance()
    }

    private func buildViewHierarchy() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
        heightAnchor.constraint(equalToConstant: 32).isActive = true
        popover.delegate = self
        setAccessibilityElement(true)
        setAccessibilityRole(.popUpButton)
        setAccessibilityValue(selectedID ?? "")

        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(titleLabel)

        chevronImageView.imageScaling = .scaleProportionallyDown
        chevronImageView.translatesAutoresizingMaskIntoConstraints = false
        chevronImageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(chevronImageView)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevronImageView.leadingAnchor, constant: -8),
            chevronImageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            chevronImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronImageView.widthAnchor.constraint(equalToConstant: 10),
            chevronImageView.heightAnchor.constraint(equalToConstant: 10)
        ])

        updateAppearance()
    }

    private func handleSelectionChanged(_ id: String) {
        let hasChanged = selectedID != id
        selectedID = id
        updateDisplayTitle()
        popover.performClose(nil)
        updateAppearance()

        if hasChanged {
            onSelectionChanged?(id)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        updateAppearance()
    }

    private func updateDisplayTitle() {
        titleLabel.stringValue = options.first(where: { $0.id == selectedID })?.title ?? ""
        setAccessibilityValue(selectedID ?? "")
    }

    private func updateAppearance() {
        guard let layer else { return }

        let isDark = effectiveAppearance.isFlowTabDarkInterface
        let isExpanded = popover.isShown
        let borderColor: NSColor
        let backgroundColor: NSColor

        if isDark {
            borderColor = isExpanded
                ? .controlAccentColor.withAlphaComponent(0.45)
                : NSColor.white.withAlphaComponent(isEnabled ? 0.14 : 0.08)
            backgroundColor = NSColor.white.withAlphaComponent(isEnabled ? (isExpanded ? 0.12 : 0.08) : 0.05)
            layer.shadowOpacity = 0
        } else {
            borderColor = isExpanded
                ? .controlAccentColor.withAlphaComponent(0.28)
                : NSColor.black.withAlphaComponent(isEnabled ? 0.14 : 0.08)
            backgroundColor = NSColor.white.withAlphaComponent(isEnabled ? 0.99 : 0.92)
            layer.shadowColor = NSColor.black.withAlphaComponent(isExpanded ? 0.08 : 0.04).cgColor
            layer.shadowOpacity = 1
            layer.shadowRadius = isExpanded ? 6 : 4
            layer.shadowOffset = CGSize(width: 0, height: 1)
        }

        layer.cornerRadius = 10
        layer.borderWidth = 1
        layer.borderColor = borderColor.cgColor
        layer.backgroundColor = backgroundColor.cgColor

        titleLabel.textColor = FlowFormSelectStyle.primaryTextColor(isDark: isDark, isEnabled: isEnabled)
        chevronImageView.contentTintColor = FlowFormSelectStyle.secondaryTextColor(
            isDark: isDark,
            isEnabled: isEnabled
        )
        chevronImageView.image = NSImage(
            systemSymbolName: isExpanded ? "chevron.up" : "chevron.down",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(chevronSymbolConfiguration)
    }
}
