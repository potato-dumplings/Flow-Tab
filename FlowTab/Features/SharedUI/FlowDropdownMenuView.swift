import AppKit

final class FlowDropdownMenuView: NSView {
    var onSelect: ((String) -> Void)?

    private let scrollView = NSScrollView()
    private let contentView = FlowDropdownMenuContentView()
    private var presentation: FlowDropdownPresentation
    private var rows: [FlowDropdownOptionRowView] = []
    private var usesScrollView = false
    private var direction: FlowDropdownMenuDirection = .below
    private var visibleRowCount: Int
    private var arrowAnchor: CGFloat?
    private var hoveredOptionID: String?
    private var scrollObserver: NSObjectProtocol?

    init(
        frame frameRect: NSRect = .zero,
        options: [FlowDropdownOption],
        selectedID: String?,
        controlIdentifier: String?,
        presentation: FlowDropdownPresentation,
        direction: FlowDropdownMenuDirection = .below,
        visibleRowCount: Int? = nil,
        arrowAnchor: CGFloat? = nil
    ) {
        self.presentation = presentation
        self.direction = direction
        self.visibleRowCount = visibleRowCount ?? min(options.count, presentation.metrics.maximumVisibleRows)
        self.arrowAnchor = arrowAnchor
        super.init(frame: frameRect)
        buildViewHierarchy()
        configure(
            options: options,
            selectedID: selectedID,
            controlIdentifier: controlIdentifier,
            presentation: presentation,
            direction: direction,
            visibleRowCount: visibleRowCount,
            arrowAnchor: arrowAnchor
        )
    }

    required init?(coder: NSCoder) {
        presentation = .form(targetAppearance: NSAppearance(named: .aqua) ?? NSApp.effectiveAppearance)
        visibleRowCount = 0
        super.init(coder: coder)
        buildViewHierarchy()
    }

    var rowsForTesting: [FlowDropdownOptionRowView] { rows }
    var directionForTesting: FlowDropdownMenuDirection { direction }
    var menuBodyRectForTesting: NSRect { menuBodyRect() }
    var scrollViewFrameForTesting: NSRect { scrollView.frame }
    var usesScrollViewForTesting: Bool { usesScrollView }

    override func layout() {
        super.layout()
        let metrics = presentation.metrics
        let contentHeight = metrics.menuVerticalPadding * 2 + CGFloat(rows.count) * metrics.menuRowHeight
        let bodyRect = menuBodyRect()
        let contentRect = usesScrollView ? scrollViewportRect(in: bodyRect) : bodyRect
        if usesScrollView {
            scrollView.frame = contentRect
            contentView.frame = NSRect(x: 0, y: 0, width: contentRect.width, height: contentHeight)
        } else {
            contentView.frame = bodyRect
        }
        for (index, row) in rows.enumerated() {
            row.frame = NSRect(
                x: metrics.menuHorizontalInset,
                y: metrics.menuVerticalPadding + CGFloat(index) * metrics.menuRowHeight,
                width: max(0, contentRect.width - metrics.menuHorizontalInset * 2),
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
        presentation: FlowDropdownPresentation,
        direction: FlowDropdownMenuDirection = .below,
        visibleRowCount: Int? = nil,
        arrowAnchor: CGFloat? = nil
    ) {
        self.presentation = presentation
        self.direction = direction
        self.visibleRowCount = visibleRowCount ?? min(options.count, presentation.metrics.maximumVisibleRows)
        self.arrowAnchor = arrowAnchor
        appearance = presentation.targetAppearance
        usesScrollView = options.count > self.visibleRowCount
        updateContentContainer()
        scrollView.hasVerticalScroller = usesScrollView
        if let controlIdentifier, !controlIdentifier.isEmpty {
            scrollView.setAccessibilityIdentifier("\(controlIdentifier).options")
        } else {
            scrollView.setAccessibilityIdentifier(nil)
        }
        rows.forEach { $0.removeFromSuperview() }
        setHoveredOption(nil)
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
            row.onHoverChanged = { [weak self] id, isHovering in
                self?.handleRowHoverChanged(optionID: id, isHovering: isHovering)
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
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.verticalScrollElasticity = .none
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.setHoveredOption(nil)
        }
    }

    deinit {
        if let scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
        }
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
        let arrowLength = boundedArrowLength()
        switch direction {
        case .below:
            return NSRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - arrowLength))
        case .above:
            return NSRect(x: 0, y: arrowLength, width: bounds.width, height: max(0, bounds.height - arrowLength))
        case .right:
            return NSRect(x: arrowLength, y: 0, width: max(0, bounds.width - arrowLength), height: bounds.height)
        case .left:
            return NSRect(x: 0, y: 0, width: max(0, bounds.width - arrowLength), height: bounds.height)
        }
    }

    private func scrollViewportRect(in bodyRect: NSRect) -> NSRect {
        let viewportHeight = min(bodyRect.height, completeRowsViewportHeight())
        return NSRect(
            x: bodyRect.minX,
            y: bodyRect.maxY - viewportHeight,
            width: bodyRect.width,
            height: max(0, viewportHeight)
        )
    }

    private func completeRowsViewportHeight() -> CGFloat {
        let metrics = presentation.metrics
        let rowCount = min(rows.count, max(0, visibleRowCount))
        return metrics.menuVerticalPadding * 2 + CGFloat(rowCount) * metrics.menuRowHeight
    }

    private func menuArrowPath() -> NSBezierPath {
        guard bounds.width > 0, bounds.height > 0 else { return NSBezierPath() }
        let arrowLength = boundedArrowLength()
        let bodyRect = menuBodyRect()
        let halfWidth = arrowHalfWidth()
        let anchor = clampedArrowAnchor()
        let path = NSBezierPath()
        switch direction {
        case .below:
            path.move(to: NSPoint(x: anchor - halfWidth, y: bodyRect.maxY - 0.5))
            path.line(to: NSPoint(x: anchor, y: bodyRect.maxY + arrowLength))
            path.line(to: NSPoint(x: anchor + halfWidth, y: bodyRect.maxY - 0.5))
        case .above:
            path.move(to: NSPoint(x: anchor - halfWidth, y: bodyRect.minY + 0.5))
            path.line(to: NSPoint(x: anchor, y: bounds.minY))
            path.line(to: NSPoint(x: anchor + halfWidth, y: bodyRect.minY + 0.5))
        case .right:
            path.move(to: NSPoint(x: bodyRect.minX + 0.5, y: anchor - halfWidth))
            path.line(to: NSPoint(x: bounds.minX, y: anchor))
            path.line(to: NSPoint(x: bodyRect.minX + 0.5, y: anchor + halfWidth))
        case .left:
            path.move(to: NSPoint(x: bodyRect.maxX - 0.5, y: anchor - halfWidth))
            path.line(to: NSPoint(x: bounds.maxX, y: anchor))
            path.line(to: NSPoint(x: bodyRect.maxX - 0.5, y: anchor + halfWidth))
        }
        path.close()
        return path
    }

    private func menuArrowStrokePath() -> NSBezierPath {
        guard bounds.width > 0, bounds.height > 0 else { return NSBezierPath() }
        let arrowLength = boundedArrowLength()
        let bodyRect = menuBodyRect()
        let halfWidth = arrowHalfWidth()
        let anchor = clampedArrowAnchor()
        let path = NSBezierPath()
        path.lineWidth = presentation.menuStyle.borderWidth
        switch direction {
        case .below:
            path.move(to: NSPoint(x: anchor - halfWidth, y: bodyRect.maxY))
            path.line(to: NSPoint(x: anchor, y: bodyRect.maxY + arrowLength))
            path.line(to: NSPoint(x: anchor + halfWidth, y: bodyRect.maxY))
        case .above:
            path.move(to: NSPoint(x: anchor - halfWidth, y: bodyRect.minY))
            path.line(to: NSPoint(x: anchor, y: bounds.minY))
            path.line(to: NSPoint(x: anchor + halfWidth, y: bodyRect.minY))
        case .right:
            path.move(to: NSPoint(x: bodyRect.minX, y: anchor - halfWidth))
            path.line(to: NSPoint(x: bounds.minX, y: anchor))
            path.line(to: NSPoint(x: bodyRect.minX, y: anchor + halfWidth))
        case .left:
            path.move(to: NSPoint(x: bodyRect.maxX, y: anchor - halfWidth))
            path.line(to: NSPoint(x: bounds.maxX, y: anchor))
            path.line(to: NSPoint(x: bodyRect.maxX, y: anchor + halfWidth))
        }
        return path
    }

    private func boundedArrowLength() -> CGFloat {
        switch direction {
        case .below, .above:
            return min(presentation.metrics.menuArrowHeight, max(0, bounds.height))
        case .right, .left:
            return min(presentation.metrics.menuArrowHeight, max(0, bounds.width))
        }
    }

    private func arrowHalfWidth() -> CGFloat {
        switch direction {
        case .below, .above:
            return min(CGFloat(14), max(0, bounds.width / 2 - presentation.cornerRadius))
        case .right, .left:
            return min(CGFloat(14), max(0, bounds.height / 2 - presentation.cornerRadius))
        }
    }

    private func clampedArrowAnchor() -> CGFloat {
        let fallback = axisLength() / 2
        let anchor = arrowAnchor ?? fallback
        let inset = presentation.cornerRadius + arrowHalfWidth()
        return min(max(anchor, inset), max(inset, axisLength() - inset))
    }

    private func axisLength() -> CGFloat {
        switch direction {
        case .below, .above:
            return bounds.width
        case .right, .left:
            return bounds.height
        }
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
        setHoveredOption(nil)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func handleRowHoverChanged(optionID: String, isHovering: Bool) {
        if isHovering {
            setHoveredOption(optionID)
        } else if hoveredOptionID == optionID {
            setHoveredOption(nil)
        }
    }

    private func setHoveredOption(_ optionID: String?) {
        hoveredOptionID = optionID
        for row in rows {
            row.setHovering(row.optionID == optionID)
        }
    }
}

final class FlowDropdownMenuContentView: NSView {
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
}
