import AppKit

final class FlowDropdownOptionRowView: NSView {
    var onSelect: ((String) -> Void)?
    var onHoverChanged: ((String, Bool) -> Void)?

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

    var optionID: String { option.id }
    var titleForTesting: String { option.title }
    var textColorForTesting: NSColor? { resolvedColor(presentation.menuStyle.textColor) }
    var backgroundColorForTesting: NSColor? { rowFillColor() }
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
        onHoverChanged?(option.id, true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChanged?(option.id, false)
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?(option.id)
    }

    override func accessibilityPerformPress() -> Bool {
        onSelect?(option.id)
        return true
    }

    func setHovering(_ isHovering: Bool) {
        guard self.isHovering != isHovering else { return }
        self.isHovering = isHovering
        refreshStyle()
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
