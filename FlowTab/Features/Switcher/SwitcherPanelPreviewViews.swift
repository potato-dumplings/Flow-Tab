import AppKit
import SwiftUI
import FlowTabCore

struct WindowOnlyGridLayout {
    let columns: Int
    let rows: Int
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let columnSpacing: CGFloat
    let rowSpacing: CGFloat

    static func resolve(
        availableSize: CGSize,
        itemCount: Int
    ) -> WindowOnlyGridLayout {
        let count = max(itemCount, 1)
        let maxColumns = min(8, count)
        let minCardWidth: CGFloat = 120
        let titleBarHeight: CGFloat = 30
        let minPreviewHeight: CGFloat = 74
        let minCardHeight: CGFloat = titleBarHeight + minPreviewHeight
        let maxCardWidth: CGFloat = 460
        let previewAspectRatio: CGFloat = 1.58
        let columnSpacing: CGFloat = 24
        let rowSpacing: CGFloat = 28
        let horizontalPadding: CGFloat = max(14, min(64, availableSize.width * 0.04))
        let verticalPadding: CGFloat = max(12, min(52, availableSize.height * 0.05))
        let usableWidth = max(220, availableSize.width - horizontalPadding * 2)
        let usableHeight = max(160, availableSize.height - verticalPadding * 2)

        var bestLayout: (columns: Int, rows: Int, cardWidth: CGFloat, cardHeight: CGFloat, score: CGFloat)?

        for columns in 1...maxColumns {
            let rows = Int(ceil(Double(count) / Double(columns)))
            let totalColumnSpacing = CGFloat(max(columns - 1, 0)) * columnSpacing
            let totalRowSpacing = CGFloat(max(rows - 1, 0)) * rowSpacing
            let cellWidth = (usableWidth - totalColumnSpacing) / CGFloat(columns)
            let cellHeight = (usableHeight - totalRowSpacing) / CGFloat(rows)
            guard cellWidth > 0, cellHeight > 0 else { continue }

            var cardWidth = min(maxCardWidth, cellWidth)
            var cardHeight = cardWidth / previewAspectRatio + titleBarHeight

            if cardHeight > cellHeight {
                cardHeight = cellHeight
                cardWidth = max(1, (cardHeight - titleBarHeight) * previewAspectRatio)
            }
            guard cardWidth > 0, cardHeight > 0 else { continue }
            if cardWidth < minCardWidth || cardHeight < minCardHeight {
                continue
            }

            let score = cardWidth * cardHeight
            if let bestLayout {
                let scoreDifference = score - bestLayout.score
                if scoreDifference < -0.001
                    || (abs(scoreDifference) <= 0.001 && rows >= bestLayout.rows) {
                    continue
                }
            }
            bestLayout = (columns, rows, cardWidth, cardHeight, score)
        }

        let resolved = bestLayout ?? {
            let columns = min(maxColumns, max(1, Int(round(sqrt(Double(count))))))
            let rows = Int(ceil(Double(count) / Double(columns)))
            let totalColumnSpacing = CGFloat(max(columns - 1, 0)) * columnSpacing
            let totalRowSpacing = CGFloat(max(rows - 1, 0)) * rowSpacing
            let cellWidth = max(1, (usableWidth - totalColumnSpacing) / CGFloat(columns))
            let cellHeight = max(1, (usableHeight - totalRowSpacing) / CGFloat(rows))
            let cardWidth = min(maxCardWidth, cellWidth)
            let cardHeight = min(cellHeight, cardWidth / previewAspectRatio + titleBarHeight)
            return (columns, rows, cardWidth, cardHeight, cardWidth * cardHeight)
        }()

        return WindowOnlyGridLayout(
            columns: resolved.columns,
            rows: resolved.rows,
            cardWidth: resolved.cardWidth,
            cardHeight: resolved.cardHeight,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            columnSpacing: columnSpacing,
            rowSpacing: rowSpacing
        )
    }
}

struct WindowPreviewCard: View {
    let image: NSImage?
    let title: String
    let appIcon: NSImage?
    let isSelected: Bool
    let width: CGFloat
    let height: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private let titleAreaHeight: CGFloat = 26
    private var previewAreaHeight: CGFloat {
        max(84, height - titleAreaHeight)
    }
    private var previewBorderColor: Color {
        if isSelected {
            return colorScheme == .dark ? Color.accentColor.opacity(0.95) : Color.accentColor.opacity(0.72)
        }
        return colorScheme == .dark ? Color.white.opacity(0.20) : Color.primary.opacity(0.12)
    }
    private var previewBorderWidth: CGFloat {
        if isSelected {
            return colorScheme == .dark ? 2.6 : 2.1
        }
        return 1
    }
    private var previewGlowColor: Color {
        guard isSelected else { return .clear }
        return colorScheme == .dark ? Color.accentColor.opacity(0.42) : Color.accentColor.opacity(0.18)
    }
    private var titleForegroundColor: Color {
        if colorScheme == .dark {
            return isSelected ? Color.white.opacity(0.98) : Color.white.opacity(0.80)
        }
        return isSelected ? Color.primary : Color.primary.opacity(0.86)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                } else {
                    (colorScheme == .dark ? Color.black : Color.white)

                    if let appIcon {
                        Image(nsImage: appIcon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 84, height: 84)
                            .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
                    }
                }
            }
            .frame(width: width, height: previewAreaHeight)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(previewBorderColor, lineWidth: previewBorderWidth)
                    if isSelected {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .inset(by: 1)
                            .stroke(
                                colorScheme == .dark ? Color.white.opacity(0.24) : Color.white.opacity(0.16),
                                lineWidth: 0.8
                            )
                    }
                }
            )
            .shadow(color: previewGlowColor, radius: isSelected ? 14 : 0, y: 0)
            .shadow(color: .black.opacity(isSelected ? 0.16 : 0.12), radius: isSelected ? 12 : 10, y: 5)

            Text(title)
                .lineLimit(1)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(titleForegroundColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 4)
        }
        .frame(width: width, height: height, alignment: .top)
    }
}

struct WindowOnlyPreviewCard: View {
    let image: NSImage?
    let title: String
    let appIcon: NSImage?
    let titleBarStyle: WindowTitleBarStyleGuess?
    let isSelected: Bool
    let width: CGFloat
    let height: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private let titleAreaHeight: CGFloat = 30
    private var previewAreaHeight: CGFloat {
        max(1, height - titleAreaHeight)
    }
    private var fallbackAppIconSize: CGFloat {
        max(42, min(96, min(width, previewAreaHeight) * 0.24))
    }
    private var usesDarkTitleBar: Bool {
        if let titleBarStyle {
            return titleBarStyle == .dark
        }
        return colorScheme == .dark
    }
    private var titleForegroundColor: Color {
        if usesDarkTitleBar {
            return Color.white.opacity(isSelected ? 0.98 : 0.92)
        }
        return Color.black.opacity(isSelected ? 0.84 : 0.74)
    }
    private var titleBarBackgroundColor: Color {
        if usesDarkTitleBar {
            return Color(nsColor: NSColor(calibratedWhite: 0.12, alpha: 1.0))
        }
        return Color(nsColor: NSColor(calibratedWhite: 0.97, alpha: 1.0))
    }
    private var titleBarDividerColor: Color {
        if usesDarkTitleBar {
            return Color.white.opacity(0.14)
        }
        return Color.black.opacity(0.12)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .lineLimit(1)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(titleForegroundColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 10)
                .frame(height: titleAreaHeight)
                .background(titleBarBackgroundColor)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(titleBarDividerColor)
                        .frame(height: 1)
                }
                .zIndex(1)

            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                } else {
                    if colorScheme == .dark {
                        LinearGradient(
                            colors: [Color.white.opacity(0.08), Color.white.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    } else {
                        Color.white
                    }
                    if let appIcon {
                        Image(nsImage: appIcon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: fallbackAppIconSize, height: fallbackAppIconSize)
                            .shadow(color: .black.opacity(0.16), radius: 8, y: 2)
                    } else {
                        Image(systemName: "macwindow")
                            .font(.system(size: 52, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: width, height: previewAreaHeight)
            .clipped()
        }
        .frame(width: width, height: height, alignment: .top)
        .background(Color.black.opacity(usesDarkTitleBar ? 0.20 : 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.95) : Color.white.opacity(0.28),
                    lineWidth: isSelected ? 2.1 : 1.0
                )
        )
        .shadow(
            color: Color.black.opacity(isSelected ? 0.22 : 0.12),
            radius: isSelected ? 14 : 9,
            y: isSelected ? 8 : 5
        )
    }
}

struct WindowPreviewPageIndicator: View {
    enum Direction {
        case previous
        case next

        var systemName: String {
            switch self {
            case .previous:
                return "chevron.left"
            case .next:
                return "chevron.right"
            }
        }

        var accessibilityIdentifier: String {
            switch self {
            case .previous:
                return SwitcherAccessibilityIdentifiers.previousWindowPage
            case .next:
                return SwitcherAccessibilityIdentifiers.nextWindowPage
            }
        }
    }

    let direction: Direction
    let isVisible: Bool

    var body: some View {
        Image(systemName: direction.systemName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(isVisible ? 0.55 : 0))
            .frame(width: SwitcherWindowPreviewPaging.indicatorWidth, height: 48)
            .accessibilityHidden(!isVisible)
            .accessibilityIdentifier(direction.accessibilityIdentifier)
    }
}

extension AnyTransition {
    static var appQuitRemoval: AnyTransition {
        let removal = AnyTransition.opacity
            .combined(with: .scale(scale: 0.72, anchor: .center))
        let insertion = AnyTransition.opacity
        return .asymmetric(insertion: insertion, removal: removal)
    }
}

struct AppTileView: View {
    let app: AppSwitchCandidate
    let isSelected: Bool
    let isTerminating: Bool
    let size: CGFloat
    let icon: NSImage?
    let accessibilityIdentifier: String
    let accessibilityLabel: String
    let accessibilityValue: String

    var body: some View {
        let cornerRadius = max(1, min(16, size * 0.18))
        let iconSize = max(1, min(56, size * 0.58))
        let fallbackFontSize = max(1, min(28, size * 0.32))
        let fallbackDotSize = max(1, size * 0.38)

        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            isSelected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.1),
                            lineWidth: isSelected ? 2 : 1
                        )
                )

            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: iconSize, height: iconSize)
                    .accessibilityLabel(Text(accessibilityLabel))
                    .accessibilityValue(Text(accessibilityValue))
                    .accessibilityIdentifier(accessibilityIdentifier)
            } else {
                if size >= 11 {
                    Text(app.displayName.prefix(1).uppercased())
                        .font(.system(size: fallbackFontSize, weight: .semibold))
                        .foregroundStyle(.primary)
                        .accessibilityLabel(Text(accessibilityLabel))
                        .accessibilityValue(Text(accessibilityValue))
                        .accessibilityIdentifier(accessibilityIdentifier)
                } else {
                    Circle()
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: fallbackDotSize, height: fallbackDotSize)
                        .accessibilityLabel(Text(accessibilityLabel))
                        .accessibilityValue(Text(accessibilityValue))
                        .accessibilityIdentifier(accessibilityIdentifier)
                }
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(isTerminating ? 0.96 : 1.0)
        .opacity(isTerminating ? 0.9 : 1.0)
        .saturation(isTerminating ? 0.88 : 1.0)
        .animation(
            .easeOut(
                duration:
                    TerminatePressFeedbackPolicy.default
                    .completionInterval
            ),
            value: isTerminating
        )
    }
}
