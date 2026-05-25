import AppKit

final class FlowDropdownMenuView: NSView {
    var onSelect: ((String) -> Void)?

    private let scrollView = NSScrollView()
    private let contentView = FlowDropdownMenuContentView()
    private var presentation: FlowDropdownPresentation
    private var rows: [FlowDropdownOptionRowView] = []
    private var usesScrollView = false
    private var hoveredOptionID: String?
    private var scrollObserver: NSObjectProtocol?

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
