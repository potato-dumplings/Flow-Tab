import AppKit
import SwiftUI

enum FlowCompactActionButtonState: Hashable {
    case normal
    case hovered
    case focused
    case focusedHovered
    case pressed
    case disabled
}

struct FlowCompactActionButtonMetrics: Equatable {
    let height: CGFloat
    let minimumWidth: CGFloat
    let horizontalPadding: CGFloat

    func preferredWidth(for title: String, font: NSFont) -> CGFloat {
        let titleWidth = (title as NSString).size(withAttributes: [.font: font]).width
        return max(minimumWidth, ceil(titleWidth) + horizontalPadding * 2)
    }
}

struct FlowCompactActionButtonStyle {
    let textColor: NSColor
    let backgroundColor: NSColor
    let borderColor: NSColor
}

struct FlowCompactActionButtonPresentation {
    let targetAppearance: NSAppearance
    let metrics: FlowCompactActionButtonMetrics
    let font: NSFont
    let cornerRadius: CGFloat
    let borderWidth: CGFloat
    let shadowColor: NSColor
    let shadowOpacity: Float
    let shadowRadius: CGFloat
    let shadowOffset: CGSize
    let styles: [FlowCompactActionButtonState: FlowCompactActionButtonStyle]

    func style(for state: FlowCompactActionButtonState) -> FlowCompactActionButtonStyle {
        styles[state] ?? styles[.normal] ?? Self.fallbackStyle
    }

    static func compact(
        targetAppearance: NSAppearance,
        textColor: NSColor? = nil,
        backgroundColor: NSColor? = nil,
        hoverBackgroundColor: NSColor? = nil,
        borderColor: NSColor? = nil
    ) -> FlowCompactActionButtonPresentation {
        let isDark = targetAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let metrics = FlowCompactActionButtonMetrics(height: 32, minimumWidth: 68, horizontalPadding: 14)
        let normalText = textColor ?? resolvedColor(targetAppearance: targetAppearance) {
            NSColor.labelColor.withAlphaComponent(0.76)
        }
        let disabledText = resolvedColor(targetAppearance: targetAppearance) {
            NSColor.secondaryLabelColor.withAlphaComponent(0.55)
        }
        let normalBackground = backgroundColor ?? NSColor.white.withAlphaComponent(isDark ? 0.12 : 0.96)
        let hoveredBackground = hoverBackgroundColor ?? NSColor.white.withAlphaComponent(isDark ? 0.18 : 1)
        let resolvedBorder = borderColor ?? (
            isDark
                ? NSColor.white.withAlphaComponent(0.18)
                : NSColor.black.withAlphaComponent(0.12)
        )
        let normal = FlowCompactActionButtonStyle(
            textColor: normalText,
            backgroundColor: normalBackground,
            borderColor: resolvedBorder
        )
        let hovered = FlowCompactActionButtonStyle(
            textColor: normalText,
            backgroundColor: hoveredBackground,
            borderColor: resolvedBorder
        )
        let disabled = FlowCompactActionButtonStyle(
            textColor: disabledText,
            backgroundColor: normalBackground,
            borderColor: resolvedBorder
        )
        return FlowCompactActionButtonPresentation(
            targetAppearance: targetAppearance,
            metrics: metrics,
            font: FlowTypography.appKit(.controlTextEmphasized),
            cornerRadius: 8,
            borderWidth: 1,
            shadowColor: NSColor.black.withAlphaComponent(0.05),
            shadowOpacity: 1,
            shadowRadius: 3,
            shadowOffset: CGSize(width: 0, height: 1),
            styles: [
                .normal: normal,
                .hovered: hovered,
                .focused: hovered,
                .focusedHovered: hovered,
                .pressed: hovered,
                .disabled: disabled
            ]
        )
    }

    private static let fallbackStyle = FlowCompactActionButtonStyle(
        textColor: .labelColor,
        backgroundColor: .controlBackgroundColor,
        borderColor: .separatorColor
    )

    private static func resolvedColor(
        targetAppearance: NSAppearance,
        _ provider: () -> NSColor
    ) -> NSColor {
        var color: NSColor?
        targetAppearance.performAsCurrentDrawingAppearance {
            color = provider()
        }
        return color ?? provider()
    }
}

final class FlowCompactActionButtonControl: NSButton {
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovering = false
    private var hasFocus = false
    private var buttonTitle = ""
    private var presentation = FlowCompactActionButtonPresentation.compact(
        targetAppearance: NSAppearance(named: .aqua) ?? NSApp.effectiveAppearance
    )

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: presentation.metrics.preferredWidth(for: buttonTitle, font: presentation.font),
            height: presentation.metrics.height
        )
    }

    override var isEnabled: Bool {
        didSet {
            if !isEnabled {
                isHovering = false
                hasFocus = false
            }
            refreshStyle()
        }
    }

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

    override func layout() {
        super.layout()
        updateShadowPath()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshStyle()
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

    func configure(
        title: String,
        accessibilityLabel: String?,
        tooltip: String? = nil,
        presentation: FlowCompactActionButtonPresentation
    ) {
        buttonTitle = title
        self.title = title
        self.presentation = presentation
        appearance = presentation.targetAppearance
        toolTip = tooltip
        setAccessibilityLabel(accessibilityLabel)
        refreshStyle()
        invalidateIntrinsicContentSize()
    }

    var presentationForTesting: FlowCompactActionButtonPresentation { presentation }

    func refreshStyle() {
        wantsLayer = true
        let stateStyle = presentation.style(for: resolvedState())
        attributedTitle = attributedString(text: buttonTitle, color: stateStyle.textColor)
        attributedAlternateTitle = attributedTitle
        contentTintColor = stateStyle.textColor

        guard let layer else { return }
        layer.backgroundColor = stateStyle.backgroundColor.cgColor
        layer.borderColor = stateStyle.borderColor.cgColor
        layer.borderWidth = presentation.borderWidth
        layer.cornerRadius = bounds.height > 0
            ? min(presentation.cornerRadius, bounds.height / 2)
            : presentation.cornerRadius
        layer.shadowColor = presentation.shadowColor.cgColor
        layer.shadowOpacity = presentation.shadowOpacity
        layer.shadowRadius = presentation.shadowRadius
        layer.shadowOffset = presentation.shadowOffset
        updateShadowPath()
    }

    private func buildViewHierarchy() {
        wantsLayer = true
        isBordered = false
        focusRingType = .none
        alignment = .center
        setButtonType(.momentaryPushIn)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
        heightAnchor.constraint(greaterThanOrEqualToConstant: presentation.metrics.height).isActive = true
        refreshStyle()
    }

    private func resolvedState() -> FlowCompactActionButtonState {
        guard isEnabled else { return .disabled }
        if isHighlighted { return .pressed }
        if hasFocus && isHovering { return .focusedHovered }
        if isHovering { return .hovered }
        if hasFocus { return .focused }
        return .normal
    }

    private func attributedString(text: String, color: NSColor) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byClipping
        return NSAttributedString(
            string: text,
            attributes: [
                .font: presentation.font,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle
            ]
        )
    }

    private func updateShadowPath() {
        guard let layer else { return }
        layer.shadowPath = CGPath(
            roundedRect: bounds,
            cornerWidth: layer.cornerRadius,
            cornerHeight: layer.cornerRadius,
            transform: nil
        )
    }
}

struct FlowCompactActionButton: NSViewRepresentable {
    let title: String
    let targetAppearance: NSAppearance
    let presentation: FlowCompactActionButtonPresentation?
    let accessibilityIdentifier: String?
    let isEnabled: Bool
    let action: () -> Void

    init(
        title: String,
        targetAppearance: NSAppearance,
        presentation: FlowCompactActionButtonPresentation? = nil,
        accessibilityIdentifier: String? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.targetAppearance = targetAppearance
        self.presentation = presentation
        self.accessibilityIdentifier = accessibilityIdentifier
        self.isEnabled = isEnabled
        self.action = action
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> FlowCompactActionButtonControl {
        let control = FlowCompactActionButtonControl(frame: .zero)
        control.target = context.coordinator
        control.action = #selector(Coordinator.performAction)
        configure(control)
        return control
    }

    func updateNSView(_ nsView: FlowCompactActionButtonControl, context: Context) {
        context.coordinator.action = action
        configure(nsView)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: FlowCompactActionButtonControl,
        context: Context
    ) -> CGSize? {
        nsView.intrinsicContentSize
    }

    private func configure(_ control: FlowCompactActionButtonControl) {
        if let accessibilityIdentifier {
            control.identifier = NSUserInterfaceItemIdentifier(accessibilityIdentifier)
            control.setAccessibilityIdentifier(accessibilityIdentifier)
        }
        control.isEnabled = isEnabled
        control.configure(
            title: title,
            accessibilityLabel: title,
            presentation: presentation ?? .compact(targetAppearance: targetAppearance)
        )
    }

    final class Coordinator {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func performAction() {
            action()
        }
    }
}
