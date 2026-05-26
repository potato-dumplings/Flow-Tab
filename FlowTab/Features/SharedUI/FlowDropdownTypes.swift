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

enum FlowDropdownMenuDirection: Equatable {
    case below
    case above
    case right
    case left
}

enum FlowDropdownPlacementPreference: Equatable {
    case defaultBelow
    case preferAbove
    case preferRight
    case preferLeft
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
    let placementPreference: FlowDropdownPlacementPreference
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
            placementPreference: .defaultBelow,
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

struct FlowDropdownMenuLayout: Equatable {
    let direction: FlowDropdownMenuDirection
    let frame: NSRect
    let contentSize: NSSize
    let visibleRowCount: Int
    let arrowAnchor: CGFloat
}

enum FlowDropdownMenuLayoutResolver {
    static func resolve(
        optionCount: Int,
        metrics: FlowDropdownMetrics,
        menuBodyWidth: CGFloat,
        controlFrame: NSRect,
        contentFrame: NSRect,
        screenVisibleFrame: NSRect,
        preference: FlowDropdownPlacementPreference
    ) -> FlowDropdownMenuLayout {
        let availableBelow = max(0, controlFrame.minY - contentFrame.minY)
        let availableAbove = max(0, contentFrame.maxY - controlFrame.maxY)

        switch preference {
        case .defaultBelow:
            return verticalLayout(
                direction: .below,
                optionCount: optionCount,
                metrics: metrics,
                menuBodyWidth: menuBodyWidth,
                controlFrame: controlFrame,
                availableHeight: availableBelow
            )
        case .preferAbove:
            if verticalRowCapacity(availableHeight: availableAbove, metrics: metrics) >= minimumUsableRows(
                optionCount: optionCount
            ) {
                return verticalLayout(
                    direction: .above,
                    optionCount: optionCount,
                    metrics: metrics,
                    menuBodyWidth: menuBodyWidth,
                    controlFrame: controlFrame,
                    availableHeight: availableAbove
                )
            }
            return fallbackVerticalLayout(
                optionCount: optionCount,
                metrics: metrics,
                menuBodyWidth: menuBodyWidth,
                controlFrame: controlFrame,
                availableBelow: availableBelow,
                availableAbove: availableAbove
            )
        case .preferRight:
            let sideWidth = sideMenuWidth(menuBodyWidth: menuBodyWidth, metrics: metrics)
            if screenVisibleFrame.maxX - controlFrame.maxX >= sideWidth {
                return sideLayout(
                    direction: .right,
                    optionCount: optionCount,
                    metrics: metrics,
                    menuBodyWidth: menuBodyWidth,
                    controlFrame: controlFrame,
                    contentFrame: contentFrame
                )
            }
            return fallbackVerticalLayout(
                optionCount: optionCount,
                metrics: metrics,
                menuBodyWidth: menuBodyWidth,
                controlFrame: controlFrame,
                availableBelow: availableBelow,
                availableAbove: availableAbove
            )
        case .preferLeft:
            let sideWidth = sideMenuWidth(menuBodyWidth: menuBodyWidth, metrics: metrics)
            if controlFrame.minX - screenVisibleFrame.minX >= sideWidth {
                return sideLayout(
                    direction: .left,
                    optionCount: optionCount,
                    metrics: metrics,
                    menuBodyWidth: menuBodyWidth,
                    controlFrame: controlFrame,
                    contentFrame: contentFrame
                )
            }
            return fallbackVerticalLayout(
                optionCount: optionCount,
                metrics: metrics,
                menuBodyWidth: menuBodyWidth,
                controlFrame: controlFrame,
                availableBelow: availableBelow,
                availableAbove: availableAbove
            )
        }
    }

    private static func fallbackVerticalLayout(
        optionCount: Int,
        metrics: FlowDropdownMetrics,
        menuBodyWidth: CGFloat,
        controlFrame: NSRect,
        availableBelow: CGFloat,
        availableAbove: CGFloat
    ) -> FlowDropdownMenuLayout {
        let direction = fallbackVerticalDirection(
            optionCount: optionCount,
            metrics: metrics,
            availableBelow: availableBelow,
            availableAbove: availableAbove
        )
        return verticalLayout(
            direction: direction,
            optionCount: optionCount,
            metrics: metrics,
            menuBodyWidth: menuBodyWidth,
            controlFrame: controlFrame,
            availableHeight: direction == .below ? availableBelow : availableAbove
        )
    }

    private static func fallbackVerticalDirection(
        optionCount: Int,
        metrics: FlowDropdownMetrics,
        availableBelow: CGFloat,
        availableAbove: CGFloat
    ) -> FlowDropdownMenuDirection {
        let preferredRows = preferredRows(optionCount: optionCount, metrics: metrics)
        let minimumRows = minimumUsableRows(optionCount: optionCount)
        let belowRows = verticalRowCapacity(availableHeight: availableBelow, metrics: metrics)
        let aboveRows = verticalRowCapacity(availableHeight: availableAbove, metrics: metrics)

        if belowRows >= preferredRows {
            return .below
        }
        if aboveRows >= preferredRows {
            return .above
        }
        if belowRows >= minimumRows {
            return .below
        }
        if aboveRows >= minimumRows {
            return .above
        }
        return aboveRows > belowRows ? .above : .below
    }

    private static func verticalLayout(
        direction: FlowDropdownMenuDirection,
        optionCount: Int,
        metrics: FlowDropdownMetrics,
        menuBodyWidth: CGFloat,
        controlFrame: NSRect,
        availableHeight: CGFloat
    ) -> FlowDropdownMenuLayout {
        let visibleRows = min(
            max(0, optionCount),
            verticalRowCapacity(availableHeight: availableHeight, metrics: metrics)
        )
        let contentHeight = min(
            max(0, availableHeight),
            metrics.menuArrowHeight + bodyHeight(rowCount: visibleRows, metrics: metrics)
        )
        let contentSize = NSSize(width: max(0, menuBodyWidth), height: contentHeight)
        let originY: CGFloat = direction == .below
            ? floor(controlFrame.minY - contentSize.height)
            : floor(controlFrame.maxY)
        let frame = NSRect(
            x: floor(controlFrame.midX - contentSize.width / 2),
            y: originY,
            width: contentSize.width,
            height: contentSize.height
        )
        return FlowDropdownMenuLayout(
            direction: direction,
            frame: frame,
            contentSize: contentSize,
            visibleRowCount: visibleRows,
            arrowAnchor: controlFrame.midX - frame.minX
        )
    }

    private static func sideLayout(
        direction: FlowDropdownMenuDirection,
        optionCount: Int,
        metrics: FlowDropdownMetrics,
        menuBodyWidth: CGFloat,
        controlFrame: NSRect,
        contentFrame: NSRect
    ) -> FlowDropdownMenuLayout {
        let visibleRows = min(
            max(0, optionCount),
            sideRowCapacity(contentHeight: contentFrame.height, metrics: metrics)
        )
        let contentHeight = min(
            max(0, contentFrame.height),
            bodyHeight(rowCount: visibleRows, metrics: metrics)
        )
        let contentSize = NSSize(
            width: sideMenuWidth(menuBodyWidth: menuBodyWidth, metrics: metrics),
            height: contentHeight
        )
        let originY = contentFrame.midY - contentSize.height / 2
        let frame = NSRect(
            x: direction == .right ? floor(controlFrame.maxX) : floor(controlFrame.minX - contentSize.width),
            y: floor(originY),
            width: contentSize.width,
            height: contentSize.height
        )
        return FlowDropdownMenuLayout(
            direction: direction,
            frame: frame,
            contentSize: contentSize,
            visibleRowCount: visibleRows,
            arrowAnchor: controlFrame.midY - frame.minY
        )
    }

    private static func preferredRows(optionCount: Int, metrics: FlowDropdownMetrics) -> Int {
        min(max(0, optionCount), max(0, metrics.maximumVisibleRows))
    }

    private static func minimumUsableRows(optionCount: Int) -> Int {
        min(max(0, optionCount), 2)
    }

    private static func preferredVerticalHeight(optionCount: Int, metrics: FlowDropdownMetrics) -> CGFloat {
        metrics.menuArrowHeight + bodyHeight(
            rowCount: preferredRows(optionCount: optionCount, metrics: metrics),
            metrics: metrics
        )
    }

    private static func bodyHeight(rowCount: Int, metrics: FlowDropdownMetrics) -> CGFloat {
        metrics.menuVerticalPadding * 2 + CGFloat(max(0, rowCount)) * metrics.menuRowHeight
    }

    private static func verticalRowCapacity(availableHeight: CGFloat, metrics: FlowDropdownMetrics) -> Int {
        min(
            max(0, metrics.maximumVisibleRows),
            rowCapacity(contentHeight: max(0, availableHeight - metrics.menuArrowHeight), metrics: metrics)
        )
    }

    private static func sideRowCapacity(contentHeight: CGFloat, metrics: FlowDropdownMetrics) -> Int {
        rowCapacity(contentHeight: contentHeight, metrics: metrics)
    }

    private static func rowCapacity(contentHeight: CGFloat, metrics: FlowDropdownMetrics) -> Int {
        guard metrics.menuRowHeight > 0 else { return 0 }
        let rowSpace = max(0, contentHeight - metrics.menuVerticalPadding * 2)
        return max(0, Int(floor((rowSpace + 0.5) / metrics.menuRowHeight)))
    }

    private static func sideMenuWidth(menuBodyWidth: CGFloat, metrics: FlowDropdownMetrics) -> CGFloat {
        max(0, menuBodyWidth) + max(0, metrics.menuArrowHeight)
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
