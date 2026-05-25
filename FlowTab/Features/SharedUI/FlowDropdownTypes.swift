import AppKit

struct FlowDropdownOption: Equatable {
    let id: String
    let title: String
}

enum FlowDropdownControlState: Hashable {
    case normal
    case hovered
    case focused
    case expanded
    case disabled
}

struct FlowDropdownMetrics: Equatable {
    let height: CGFloat
    let minimumWidth: CGFloat
    let horizontalPadding: CGFloat
    let iconSpacing: CGFloat
    let menuRowHeight: CGFloat
    let menuVerticalPadding: CGFloat
    let menuHorizontalInset: CGFloat
    let menuArrowHeight: CGFloat
    let maximumVisibleRows: Int

    func preferredWidth(for titles: [String], font: NSFont) -> CGFloat {
        let widestTitle = titles
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        return max(minimumWidth, ceil(widestTitle) + horizontalPadding * 2 + iconSpacing)
    }
}

struct FlowDropdownControlStyle {
    let backgroundColor: NSColor
    let borderColor: NSColor
    let borderWidth: CGFloat
    let textColor: NSColor
    let chevronColor: NSColor
    let shadowColor: NSColor
    let shadowOpacity: Float
    let shadowRadius: CGFloat
    let shadowOffset: CGSize
}

struct FlowDropdownMenuStyle {
    let backgroundColor: NSColor
    let borderColor: NSColor
    let borderWidth: CGFloat
    let textColor: NSColor
    let hoveredRowColor: NSColor
    let selectedRowColor: NSColor
}

struct FlowDropdownPresentation {
    let targetAppearance: NSAppearance
    let metrics: FlowDropdownMetrics
    let font: NSFont
    let cornerRadius: CGFloat
    let controlStyles: [FlowDropdownControlState: FlowDropdownControlStyle]
    let menuStyle: FlowDropdownMenuStyle

    func style(for state: FlowDropdownControlState) -> FlowDropdownControlStyle {
        controlStyles[state] ?? controlStyles[.normal] ?? Self.fallbackControlStyle
    }

    static func form(targetAppearance: NSAppearance) -> FlowDropdownPresentation {
        let isDark = targetAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let metrics = FlowDropdownMetrics(
            height: 32,
            minimumWidth: 132,
            horizontalPadding: 12,
            iconSpacing: 24,
            menuRowHeight: 34,
            menuVerticalPadding: 6,
            menuHorizontalInset: 6,
            menuArrowHeight: 10,
            maximumVisibleRows: 8
        )
        let accent = resolvedColor(targetAppearance: targetAppearance) { .controlAccentColor }
        let menuBackground = resolvedColor(targetAppearance: targetAppearance) {
            NSColor.windowBackgroundColor.withAlphaComponent(0.98)
        }
        let normal = FlowDropdownControlStyle(
            backgroundColor: isDark ? NSColor.white.withAlphaComponent(0.08) : NSColor.white.withAlphaComponent(0.99),
            borderColor: isDark ? NSColor.white.withAlphaComponent(0.14) : NSColor.black.withAlphaComponent(0.14),
            borderWidth: 1,
            textColor: isDark ? NSColor.white.withAlphaComponent(0.92) : NSColor.black.withAlphaComponent(0.78),
            chevronColor: isDark ? NSColor.white.withAlphaComponent(0.72) : NSColor.black.withAlphaComponent(0.54),
            shadowColor: NSColor.black.withAlphaComponent(0.04),
            shadowOpacity: 1,
            shadowRadius: 4,
            shadowOffset: CGSize(width: 0, height: 1)
        )
        let hovered = normal.with(
            backgroundColor: isDark ? NSColor.white.withAlphaComponent(0.12) : NSColor.white,
            borderColor: isDark ? NSColor.white.withAlphaComponent(0.22) : NSColor.black.withAlphaComponent(0.20)
        )
        let disabled = normal.with(
            textColor: isDark ? NSColor.white.withAlphaComponent(0.42) : NSColor.black.withAlphaComponent(0.38),
            chevronColor: isDark ? NSColor.white.withAlphaComponent(0.34) : NSColor.black.withAlphaComponent(0.30)
        )
        return FlowDropdownPresentation(
            targetAppearance: targetAppearance,
            metrics: metrics,
            font: FlowTypography.appKit(.controlText),
            cornerRadius: 10,
            controlStyles: [
                .normal: normal,
                .hovered: hovered,
                .focused: hovered,
                .expanded: hovered,
                .disabled: disabled
            ],
            menuStyle: FlowDropdownMenuStyle(
                backgroundColor: isDark ? menuBackground : NSColor.white,
                borderColor: isDark ? NSColor.white.withAlphaComponent(0.12) : NSColor.black.withAlphaComponent(0.14),
                borderWidth: 1,
                textColor: isDark ? NSColor.white.withAlphaComponent(0.92) : NSColor.black.withAlphaComponent(0.86),
                hoveredRowColor: isDark ? NSColor.white.withAlphaComponent(0.10) : NSColor.black.withAlphaComponent(0.045),
                selectedRowColor: accent.withAlphaComponent(isDark ? 0.24 : 0.10)
            )
        )
    }

    private static let fallbackControlStyle = FlowDropdownControlStyle(
        backgroundColor: .controlBackgroundColor,
        borderColor: .separatorColor,
        borderWidth: 1,
        textColor: .labelColor,
        chevronColor: .secondaryLabelColor,
        shadowColor: .clear,
        shadowOpacity: 0,
        shadowRadius: 0,
        shadowOffset: .zero
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

extension FlowDropdownControlStyle {
    func with(
        backgroundColor: NSColor? = nil,
        borderColor: NSColor? = nil,
        textColor: NSColor? = nil,
        chevronColor: NSColor? = nil
    ) -> FlowDropdownControlStyle {
        FlowDropdownControlStyle(
            backgroundColor: backgroundColor ?? self.backgroundColor,
            borderColor: borderColor ?? self.borderColor,
            borderWidth: borderWidth,
            textColor: textColor ?? self.textColor,
            chevronColor: chevronColor ?? self.chevronColor,
            shadowColor: shadowColor,
            shadowOpacity: shadowOpacity,
            shadowRadius: shadowRadius,
            shadowOffset: shadowOffset
        )
    }
}
