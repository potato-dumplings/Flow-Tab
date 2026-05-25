import AppKit

final class FlowSettingsSelectControl: NSView, FlowSettingsAppearanceRefreshable {
    var onSelectionChanged: ((String) -> Void)?

    var isEnabled = true {
        didSet {
            popUpButton.isEnabled = isEnabled
            if !isEnabled {
                isHovering = false
            }
            refreshStyle()
        }
    }

    private let popUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private var hoverTrackingArea: NSTrackingArea?
    private var options: [(id: String, title: String)] = []
    private var selectedID: String?
    private var isHovering = false
    private var isExpanded = false
    private var hasFocus = false
    private var targetAppearance = FlowSettingsStyleResolver.defaultAppearance
    private var style = FlowSettingsSelectStyle.preset(.formSelect)

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

    override func layout() {
        super.layout()
        layer?.frame = bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshStyle()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            isExpanded = false
        }
        super.viewWillMove(toWindow: newWindow)
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

    func configure(options: [(id: String, title: String)], style: FlowSettingsSelectStyle = .preset(.formSelect)) {
        self.options = options
        self.style = style
        if options.contains(where: { $0.id == selectedID }) == false {
            selectedID = options.first?.id
        }
        rebuildMenu()
        updateDisplaySelection()
        refreshStyle()
        invalidateIntrinsicContentSize()
    }

    func updateSelection(id: String) {
        guard options.contains(where: { $0.id == id }) else { return }
        selectedID = id
        updateDisplaySelection()
        refreshStyle()
        invalidateIntrinsicContentSize()
    }

    func applySettingsAppearance(_ appearance: NSAppearance) {
        targetAppearance = appearance
        popUpButton.appearance = appearance
        popUpButton.menu?.appearance = appearance
        refreshStyle()
    }

    func refreshStyle() {
        wantsLayer = true
        guard let layer else { return }
        let resolvedStyle = style.states.value(for: resolvedState())
        if let surface = resolvedStyle.surface {
            FlowSettingsStyleResolver.apply(surface: surface, to: layer, appearance: targetAppearance)
        }
        let textToken = resolvedStyle.text ?? style.states.value(for: .normal).text
        if let textToken {
            popUpButton.contentTintColor = FlowSettingsStyleResolver.color(textToken.color, appearance: targetAppearance)
            popUpButton.font = textToken.font
        }
        popUpButton.isEnabled = isEnabled
        setAccessibilityValue(selectedID ?? "")
        setNeedsDisplay(bounds)
    }

    private var preferredControlWidth: CGFloat {
        let font = style.states.value(for: .normal).text?.font ?? .systemFont(ofSize: 13)
        return style.metrics.preferredWidth(for: options.map(\.title), font: font)
    }

    private func buildViewHierarchy() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
        heightAnchor.constraint(equalToConstant: style.metrics.height).isActive = true

        setAccessibilityElement(true)
        setAccessibilityRole(.popUpButton)
        setAccessibilityValue(selectedID ?? "")

        popUpButton.isBordered = false
        popUpButton.bezelStyle = .regularSquare
        popUpButton.target = self
        popUpButton.action = #selector(handleSelectionChanged(_:))
        popUpButton.translatesAutoresizingMaskIntoConstraints = false
        popUpButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        popUpButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(popUpButton)

        NSLayoutConstraint.activate([
            popUpButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            popUpButton.topAnchor.constraint(equalTo: topAnchor),
            popUpButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            popUpButton.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        refreshStyle()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.appearance = targetAppearance
        for option in options {
            let item = NSMenuItem(title: option.title, action: #selector(handleMenuItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.id
            item.identifier = NSUserInterfaceItemIdentifier(option.id)
            item.setAccessibilityIdentifier(option.id)
            item.state = option.id == selectedID ? .on : .off
            menu.addItem(item)
        }
        popUpButton.menu = menu
        updateDisplaySelection()
    }

    private func updateDisplaySelection() {
        let selectedIndex = options.firstIndex { $0.id == selectedID } ?? 0
        if popUpButton.numberOfItems > selectedIndex {
            popUpButton.selectItem(at: selectedIndex)
        }
        popUpButton.setAccessibilityIdentifier(identifier?.rawValue)
        popUpButton.setAccessibilityValue(selectedID ?? "")
        setAccessibilityValue(selectedID ?? "")
        for item in popUpButton.itemArray {
            item.state = item.representedObject as? String == selectedID ? .on : .off
        }
    }

    @objc private func handleSelectionChanged(_ sender: NSPopUpButton) {
        guard let id = sender.selectedItem?.representedObject as? String else { return }
        commitSelection(id)
    }

    @objc private func handleMenuItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        commitSelection(id)
    }

    private func commitSelection(_ id: String) {
        let hasChanged = selectedID != id
        selectedID = id
        isExpanded = false
        updateDisplaySelection()
        refreshStyle()
        if hasChanged {
            onSelectionChanged?(id)
        }
    }

    private func optionTestingIdentifier(for optionID: String) -> String {
        guard let rawIdentifier = identifier?.rawValue, !rawIdentifier.isEmpty else {
            return optionID
        }
        return "\(rawIdentifier).option.\(optionID)"
    }

    private func resolvedState() -> FlowSettingsSelectState {
        guard isEnabled else { return .disabled }
        if isExpanded { return .expanded }
        if hasFocus { return .focused }
        if isHovering { return .hovered }
        return .normal
    }
}
