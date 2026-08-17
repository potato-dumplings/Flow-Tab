import AppKit

final class FlowDropdownControl: NSView {
    var onSelectionChanged: ((String) -> Void)?
    var onInteraction: (() -> Void)?

    var isEnabled = true {
        didSet {
            if !isEnabled {
                closeMenu()
                isHovering = false
            }
            refreshStyle()
        }
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let chevronImageView = NSImageView()
    private var hoverTrackingArea: NSTrackingArea?
    private var options: [FlowDropdownOption] = []
    private var selectedID: String?
    private var presentation = FlowDropdownPresentation.form(
        targetAppearance: NSAppearance(named: .aqua) ?? NSApp.effectiveAppearance
    )
    private var menuWindowController: FlowDropdownMenuWindowController?
    private weak var menuView: FlowDropdownMenuView?
    private var isHovering = false
    private var hasFocus = false
    private var isExpanded = false

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: presentation.metrics.preferredWidth(for: options.map(\.title), font: presentation.font),
            height: presentation.metrics.height
        )
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildViewHierarchy()
    }

    override var acceptsFirstResponder: Bool { true }

    func configure(
        options: [FlowDropdownOption],
        selectedID: String?,
        presentation: FlowDropdownPresentation
    ) {
        self.options = options
        self.presentation = presentation
        self.selectedID = resolvedSelectionID(for: selectedID)
        appearance = presentation.targetAppearance
        updateDisplay()
        refreshStyle()
        updateMenuIfNeeded()
        invalidateIntrinsicContentSize()
    }

    func updateSelection(id: String) {
        guard options.contains(where: { $0.id == id }) else { return }
        selectedID = id
        updateDisplay()
        refreshStyle()
        updateMenuIfNeeded()
    }

    var selectedIdentifierForTesting: String? { selectedID }
    var selectedTitleForTesting: String { selectedOption?.title ?? "" }
    var titleFrameForTesting: NSRect { titleLabel.frame }
    var chevronFrameForTesting: NSRect { chevronImageView.frame }
    var titleAlignmentForTesting: NSTextAlignment { titleLabel.alignment }
    var textColorForTesting: NSColor? { titleLabel.textColor }

    func selectOptionForTesting(_ id: String) {
        commitSelection(id)
    }

    override func layout() {
        super.layout()
        let iconSide = FlowDropdownMetrics.controlChevronSide
        chevronImageView.frame = NSRect(
            x: bounds.maxX - presentation.metrics.horizontalPadding - iconSide,
            y: floor((bounds.height - iconSide) / 2),
            width: iconSide,
            height: iconSide
        )
        titleLabel.frame = NSRect(
            x: presentation.metrics.horizontalPadding,
            y: centeredTextY(),
            width: max(
                0,
                chevronImageView.frame.minX
                    - presentation.metrics.horizontalPadding
                    - FlowDropdownMetrics.controlTitleChevronSpacing
            ),
            height: centeredTextHeight()
        )
        updateShadowPath()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
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

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        onInteraction?()
        window?.makeFirstResponder(self)
        toggleMenu()
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        onInteraction?()
        window?.makeFirstResponder(self)
        toggleMenu()
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled else {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 36, 49, 125:
            onInteraction?()
            showMenu()
        case 53:
            closeMenu()
        default:
            super.keyDown(with: event)
        }
    }

    override func becomeFirstResponder() -> Bool {
        hasFocus = true
        refreshStyle()
        return true
    }

    override func resignFirstResponder() -> Bool {
        hasFocus = false
        refreshStyle()
        return true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            closeMenu()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    private var selectedOption: FlowDropdownOption? {
        options.first { $0.id == selectedID } ?? options.first
    }

    private func buildViewHierarchy() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)

        setAccessibilityElement(true)
        setAccessibilityRole(.popUpButton)

        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = true
        addSubview(titleLabel)

        chevronImageView.image = NSImage(
            systemSymbolName: "chevron.up.chevron.down",
            accessibilityDescription: nil
        )
        chevronImageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        chevronImageView.imageScaling = .scaleProportionallyDown
        chevronImageView.translatesAutoresizingMaskIntoConstraints = true
        addSubview(chevronImageView)

        updateDisplay()
        refreshStyle()
    }

    private func resolvedSelectionID(for candidate: String?) -> String? {
        if let candidate, options.contains(where: { $0.id == candidate }) {
            return candidate
        }
        return options.first?.id
    }

    private func updateDisplay() {
        let title = selectedOption?.title ?? ""
        titleLabel.stringValue = title
        titleLabel.font = presentation.font
        setAccessibilityValue(selectedID ?? "")
        setAccessibilityLabel(title)
        if let rawIdentifier = identifier?.rawValue {
            setAccessibilityIdentifier(rawIdentifier)
        }
        needsLayout = true
    }

    private func refreshStyle() {
        wantsLayer = true
        guard let layer else { return }
        let style = presentation.style(for: resolvedState())
        layer.backgroundColor = style.backgroundColor.cgColor
        layer.borderColor = style.borderColor.cgColor
        layer.borderWidth = style.borderWidth
        layer.cornerRadius = presentation.cornerRadius
        layer.shadowColor = style.shadowColor.cgColor
        layer.shadowOpacity = style.shadowOpacity
        layer.shadowRadius = style.shadowRadius
        layer.shadowOffset = style.shadowOffset
        updateShadowPath()
        titleLabel.textColor = style.textColor
        chevronImageView.contentTintColor = style.chevronColor
        alphaValue = isEnabled ? 1 : 0.62
    }

    private func updateShadowPath() {
        guard let layer else { return }
        layer.shadowPath = CGPath(
            roundedRect: bounds,
            cornerWidth: presentation.cornerRadius,
            cornerHeight: presentation.cornerRadius,
            transform: nil
        )
    }

    private func centeredTextHeight() -> CGFloat {
        ceil(titleLabel.intrinsicContentSize.height)
    }

    private func centeredTextY() -> CGFloat {
        floor((bounds.height - centeredTextHeight()) / 2)
    }

    private func resolvedState() -> FlowDropdownControlState {
        guard isEnabled else { return .disabled }
        if isExpanded { return .expanded }
        if hasFocus { return .focused }
        if isHovering { return .hovered }
        return .normal
    }

    private func toggleMenu() {
        isExpanded ? closeMenu() : showMenu()
    }

    private func showMenu() {
        guard isEnabled, !options.isEmpty, menuWindowController == nil else { return }
        guard let layout = makeMenuLayoutForCurrentGeometry() else { return }
        let menuView = FlowDropdownMenuView(
            frame: NSRect(origin: .zero, size: layout.contentSize),
            options: options,
            selectedID: selectedID,
            controlIdentifier: identifier?.rawValue,
            presentation: presentation,
            direction: layout.direction,
            visibleRowCount: layout.visibleRowCount,
            arrowAnchor: layout.arrowAnchor
        )
        menuView.onSelect = { [weak self] id in
            self?.commitSelection(id)
        }
        menuView.frame = NSRect(origin: .zero, size: layout.contentSize)
        menuView.layoutSubtreeIfNeeded()
        self.menuView = menuView
        let menuWindowController = FlowDropdownMenuWindowController(
            control: self,
            menuView: menuView,
            layout: layout
        )
        menuWindowController.onClose = { [weak self] in
            self?.menuDidClose()
        }
        self.menuWindowController = menuWindowController
        isExpanded = true
        refreshStyle()
        menuWindowController.show()
    }

    private func closeMenu() {
        menuWindowController?.close()
    }

    private func updateMenuIfNeeded() {
        guard let menuWindowController, let menuView else { return }
        guard let layout = makeMenuLayoutForCurrentGeometry() else {
            closeMenu()
            return
        }
        menuWindowController.update(layout: layout)
        menuView.configure(
            options: options,
            selectedID: selectedID,
            controlIdentifier: identifier?.rawValue,
            presentation: presentation,
            direction: layout.direction,
            visibleRowCount: layout.visibleRowCount,
            arrowAnchor: layout.arrowAnchor
        )
    }

    func makeMenuLayoutForCurrentGeometry() -> FlowDropdownMenuLayout? {
        guard let parentWindow = window else { return nil }
        let controlScreenFrame = parentWindow.convertToScreen(convert(bounds, to: nil))
        let contentScreenFrame = contentScreenFrame(in: parentWindow)
        let screenVisibleFrame = parentWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? contentScreenFrame
        return FlowDropdownMenuLayoutResolver.resolve(
            optionCount: options.count,
            metrics: presentation.metrics,
            menuBodyWidth: max(bounds.width, intrinsicContentSize.width),
            controlFrame: controlScreenFrame,
            contentFrame: contentScreenFrame,
            screenVisibleFrame: screenVisibleFrame,
            preference: presentation.placementPreference
        )
    }

    private func contentScreenFrame(in parentWindow: NSWindow) -> NSRect {
        guard let contentView = parentWindow.contentView else {
            return parentWindow.frame
        }
        return parentWindow.convertToScreen(contentView.convert(contentView.bounds, to: nil))
    }

    private func commitSelection(_ id: String) {
        guard options.contains(where: { $0.id == id }) else { return }
        let didChange = selectedID != id
        selectedID = id
        updateDisplay()
        closeMenu()
        if didChange {
            onSelectionChanged?(id)
        }
    }

    private func menuDidClose() {
        menuWindowController = nil
        menuView = nil
        isExpanded = false
        refreshStyle()
    }
}
