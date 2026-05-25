import AppKit

final class FlowDropdownMenuView: NSView {
    var onSelect: ((String) -> Void)?

    private let scrollView = NSScrollView()
    private let contentView = FlowDropdownMenuContentView()
    private var presentation: FlowDropdownPresentation
    private var rows: [FlowDropdownOptionRowView] = []
    private var usesScrollView = false

    init(
        frame frameRect: NSRect = .zero,
        options: [FlowDropdownOption],
        selectedID: String?,
        controlIdentifier: String?,
        presentation: FlowDropdownPresentation
    ) {
        self.presentation = presentation
        super.init(frame: frameRect)
        buildViewHierarchy()
        configure(
            options: options,
            selectedID: selectedID,
            controlIdentifier: controlIdentifier,
            presentation: presentation
        )
    }

    required init?(coder: NSCoder) {
        presentation = .form(targetAppearance: NSAppearance(named: .aqua) ?? NSApp.effectiveAppearance)
        super.init(coder: coder)
        buildViewHierarchy()
    }

    var rowsForTesting: [FlowDropdownOptionRowView] { rows }

    override func layout() {
        super.layout()
        let metrics = presentation.metrics
        let contentHeight = metrics.menuVerticalPadding * 2 + CGFloat(rows.count) * metrics.menuRowHeight
        let bodyRect = menuBodyRect()
        if usesScrollView {
            scrollView.frame = bodyRect
            contentView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: contentHeight)
        } else {
            contentView.frame = bodyRect
        }
        for (index, row) in rows.enumerated() {
            row.frame = NSRect(
                x: metrics.menuHorizontalInset,
                y: metrics.menuVerticalPadding + CGFloat(index) * metrics.menuRowHeight,
                width: bounds.width - metrics.menuHorizontalInset * 2,
                height: metrics.menuRowHeight
            )
            row.needsDisplay = true
        }
        needsDisplay = true
    }

    func configure(
        options: [FlowDropdownOption],
        selectedID: String?,
        controlIdentifier: String?,
        presentation: FlowDropdownPresentation
    ) {
        self.presentation = presentation
        appearance = presentation.targetAppearance
        usesScrollView = options.count > presentation.metrics.maximumVisibleRows
        updateContentContainer()
        scrollView.hasVerticalScroller = usesScrollView
        if let controlIdentifier, !controlIdentifier.isEmpty {
            scrollView.setAccessibilityIdentifier("\(controlIdentifier).options")
        } else {
            scrollView.setAccessibilityIdentifier(nil)
        }
        rows.forEach { $0.removeFromSuperview() }
        rows = options.map { option in
            let row = FlowDropdownOptionRowView(
                option: option,
                isSelected: option.id == selectedID,
                presentation: presentation,
                accessibilityIdentifier: optionAccessibilityIdentifier(
                    controlIdentifier: controlIdentifier,
                    optionID: option.id
                )
            )
            row.onSelect = { [weak self] id in
                self?.onSelect?(id)
            }
            contentView.addSubview(row)
            return row
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
        if usesScrollView {
            scrollToTop()
        }
    }

    private func buildViewHierarchy() {
        wantsLayer = false
        translatesAutoresizingMaskIntoConstraints = true
        addSubview(contentView)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.contentView.drawsBackground = false
        scrollView.verticalScrollElasticity = .none
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 0, bounds.height > 0 else { return }
        let style = presentation.menuStyle
        let bodyPath = NSBezierPath(
            roundedRect: menuBodyRect(),
            xRadius: presentation.cornerRadius + 2,
            yRadius: presentation.cornerRadius + 2
        )
        resolvedColor(style.backgroundColor).setFill()
        bodyPath.fill()
        menuArrowPath().fill()

        resolvedColor(style.borderColor).setStroke()
        bodyPath.lineWidth = style.borderWidth
        bodyPath.stroke()
        menuArrowStrokePath().stroke()
    }

    private func updateContentContainer() {
        if usesScrollView {
            if contentView.superview !== scrollView.contentView {
                contentView.removeFromSuperview()
                scrollView.documentView = contentView
            }
            if scrollView.superview !== self {
                addSubview(scrollView)
            }
        } else {
            scrollView.documentView = nil
            if contentView.superview !== self {
                contentView.removeFromSuperview()
                addSubview(contentView)
            }
            if scrollView.superview === self {
                scrollView.removeFromSuperview()
            }
        }
    }

    private func menuBodyRect() -> NSRect {
        let arrowHeight = min(presentation.metrics.menuArrowHeight, max(0, bounds.height))
        return NSRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: max(0, bounds.height - arrowHeight)
        )
    }

    private func menuArrowPath() -> NSBezierPath {
        guard bounds.width > 0, bounds.height > 0 else { return NSBezierPath() }
        let arrowHeight = min(presentation.metrics.menuArrowHeight, max(0, bounds.height))
        let bodyMaxY = menuBodyRect().maxY
        let halfWidth = min(CGFloat(14), max(0, bounds.width / 2 - presentation.cornerRadius))
        let path = NSBezierPath()
        path.move(to: NSPoint(x: bounds.midX - halfWidth, y: bodyMaxY - 0.5))
        path.line(to: NSPoint(x: bounds.midX, y: bodyMaxY + arrowHeight))
        path.line(to: NSPoint(x: bounds.midX + halfWidth, y: bodyMaxY - 0.5))
        path.close()
        return path
    }

    private func menuArrowStrokePath() -> NSBezierPath {
        guard bounds.width > 0, bounds.height > 0 else { return NSBezierPath() }
        let arrowHeight = min(presentation.metrics.menuArrowHeight, max(0, bounds.height))
        let bodyMaxY = menuBodyRect().maxY
        let halfWidth = min(CGFloat(14), max(0, bounds.width / 2 - presentation.cornerRadius))
        let path = NSBezierPath()
        path.lineWidth = presentation.menuStyle.borderWidth
        path.move(to: NSPoint(x: bounds.midX - halfWidth, y: bodyMaxY))
        path.line(to: NSPoint(x: bounds.midX, y: bodyMaxY + arrowHeight))
        path.line(to: NSPoint(x: bounds.midX + halfWidth, y: bodyMaxY))
        return path
    }

    private func resolvedColor(_ color: NSColor) -> NSColor {
        var resolvedColor: NSColor?
        presentation.targetAppearance.performAsCurrentDrawingAppearance {
            resolvedColor = color.usingColorSpace(.sRGB)
        }
        return resolvedColor ?? color
    }

    private func optionAccessibilityIdentifier(controlIdentifier: String?, optionID: String) -> String {
        guard let controlIdentifier, !controlIdentifier.isEmpty else { return optionID }
        return "\(controlIdentifier).option.\(optionID)"
    }

    private func scrollToTop() {
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

private final class FlowDropdownMenuContentView: NSView {
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
}

final class FlowDropdownOptionRowView: NSView {
    var onSelect: ((String) -> Void)?

    private let option: FlowDropdownOption
    private var presentation: FlowDropdownPresentation
    private var isSelected: Bool
    private var isHovering = false
    private var hoverTrackingArea: NSTrackingArea?

    init(
        option: FlowDropdownOption,
        isSelected: Bool,
        presentation: FlowDropdownPresentation,
        accessibilityIdentifier: String
    ) {
        self.option = option
        self.isSelected = isSelected
        self.presentation = presentation
        super.init(frame: .zero)
        buildViewHierarchy(accessibilityIdentifier: accessibilityIdentifier)
        refreshStyle()
    }

    required init?(coder: NSCoder) {
        option = FlowDropdownOption(id: "", title: "")
        isSelected = false
        presentation = .form(targetAppearance: NSAppearance(named: .aqua) ?? NSApp.effectiveAppearance)
        super.init(coder: coder)
        buildViewHierarchy(accessibilityIdentifier: "")
    }

    var titleForTesting: String { option.title }
    var textColorForTesting: NSColor? { resolvedColor(presentation.menuStyle.textColor) }
    var backgroundColorForTesting: NSColor? {
        rowFillColor()
    }
    var titleFrameForTesting: NSRect { titleRect() }
    var titleAlignmentForTesting: NSTextAlignment { .center }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let rowColor = rowFillColor() {
            let rowRect = bounds.insetBy(dx: 6, dy: 3)
            rowColor.setFill()
            NSBezierPath(roundedRect: rowRect, xRadius: 7, yRadius: 7).fill()
        }
        drawTitle()
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
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovering = true
        refreshStyle()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovering = false
        refreshStyle()
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?(option.id)
    }

    override func accessibilityPerformPress() -> Bool {
        onSelect?(option.id)
        return true
    }

    private func buildViewHierarchy(accessibilityIdentifier: String) {
        wantsLayer = false
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityIdentifier(accessibilityIdentifier)
        setAccessibilityLabel(option.title)
        setAccessibilityValue(option.id)
    }

    private func refreshStyle() {
        appearance = presentation.targetAppearance
        needsDisplay = true
    }

    private func rowFillColor() -> NSColor? {
        if isSelected {
            return resolvedColor(presentation.menuStyle.selectedRowColor)
        }
        if isHovering {
            return resolvedColor(presentation.menuStyle.hoveredRowColor)
        }
        return nil
    }

    private func centeredTextHeight() -> CGFloat {
        ceil(presentation.font.ascender - presentation.font.descender + presentation.font.leading)
    }

    private func centeredTextY() -> CGFloat {
        floor((bounds.height - centeredTextHeight()) / 2)
    }

    private func titleRect() -> NSRect {
        let textInset: CGFloat = 12
        return NSRect(
            x: textInset,
            y: centeredTextY(),
            width: max(0, bounds.width - textInset * 2),
            height: centeredTextHeight()
        )
    }

    private func drawTitle() {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: presentation.font,
            .foregroundColor: resolvedColor(presentation.menuStyle.textColor),
            .paragraphStyle: paragraphStyle
        ]
        (option.title as NSString).draw(in: titleRect(), withAttributes: attributes)
    }

    private func resolvedColor(_ color: NSColor) -> NSColor {
        var resolvedColor: NSColor?
        presentation.targetAppearance.performAsCurrentDrawingAppearance {
            resolvedColor = color.usingColorSpace(.sRGB)
        }
        return resolvedColor ?? color
    }
}
