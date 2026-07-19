import CoreGraphics
import Foundation

struct SwitcherWindowPreviewPage: Equatable {
    let visibleRange: Range<Int>
    let selectedIndex: Int?
    let cardAreaWidth: CGFloat
    let showsNavigationIndicators: Bool

    var hasPreviousPage: Bool {
        visibleRange.lowerBound > 0
    }

    var hasNextPage: Bool {
        visibleRange.upperBound < itemCount
    }

    private let itemCount: Int

    init(
        visibleRange: Range<Int>,
        selectedIndex: Int?,
        cardAreaWidth: CGFloat,
        showsNavigationIndicators: Bool,
        itemCount: Int
    ) {
        self.visibleRange = visibleRange
        self.selectedIndex = selectedIndex
        self.cardAreaWidth = cardAreaWidth
        self.showsNavigationIndicators = showsNavigationIndicators
        self.itemCount = itemCount
    }
}

enum SwitcherWindowPreviewPaging {
    static let itemSpacing: CGFloat = 12
    static let indicatorWidth: CGFloat = 28
    static let indicatorSpacing: CGFloat = 8
    static let targetCardWidth: CGFloat = 140
    static let minimumVisibleSlots = 6
    static let maximumVisibleSlots = 16

    private static let minimumRenderedCardWidth: CGFloat = 36
    private static let maxCardWidth: CGFloat = 360

    static func page(
        itemCount: Int,
        selectedIndex: Int?,
        availableWidth: CGFloat
    ) -> SwitcherWindowPreviewPage {
        guard itemCount > 0 else {
            return SwitcherWindowPreviewPage(
                visibleRange: 0..<0,
                selectedIndex: nil,
                cardAreaWidth: max(0, availableWidth),
                showsNavigationIndicators: false,
                itemCount: 0
            )
        }

        let fullWidthCapacity = capacity(for: availableWidth)
        let needsIndicators = itemCount > fullWidthCapacity
        let cardAreaWidth = max(0, availableWidth - (needsIndicators ? navigationIndicatorReserveWidth : 0))
        let pageSize = min(itemCount, capacity(for: cardAreaWidth))
        let boundedSelectedIndex = min(max(selectedIndex ?? 0, 0), itemCount - 1)
        let pageStart = (boundedSelectedIndex / pageSize) * pageSize
        let pageEnd = min(itemCount, pageStart + pageSize)

        return SwitcherWindowPreviewPage(
            visibleRange: pageStart..<pageEnd,
            selectedIndex: boundedSelectedIndex,
            cardAreaWidth: cardAreaWidth,
            showsNavigationIndicators: needsIndicators,
            itemCount: itemCount
        )
    }

    static func cardWidth(
        cardAreaWidth: CGFloat,
        visibleCount: Int
    ) -> CGFloat {
        let count = max(visibleCount, 1)
        let totalSpacing = itemSpacing * CGFloat(max(count - 1, 0))
        let rawWidth = (cardAreaWidth - totalSpacing) / CGFloat(count)
        return max(minimumRenderedCardWidth, min(maxCardWidth, rawWidth))
    }

    static func preferredAvailableWidth(
        itemCount: Int,
        maximumAvailableWidth: CGFloat
    ) -> CGFloat {
        guard itemCount > 0 else { return 0 }
        let maximumPage = page(
            itemCount: itemCount,
            selectedIndex: 0,
            availableWidth: maximumAvailableWidth
        )
        let visibleCount = max(maximumPage.visibleRange.count, 1)
        let cardAreaWidth =
            CGFloat(visibleCount) * targetCardWidth
            + CGFloat(max(visibleCount - 1, 0)) * itemSpacing
        let indicatorReserve = maximumPage.showsNavigationIndicators
            ? navigationIndicatorReserveWidth
            : 0
        return cardAreaWidth + indicatorReserve
    }

    private static var navigationIndicatorReserveWidth: CGFloat {
        indicatorWidth * 2 + indicatorSpacing * 2
    }

    private static func capacity(for availableWidth: CGFloat) -> Int {
        guard availableWidth > 0 else { return minimumVisibleSlots }
        let capacity = floor((availableWidth + itemSpacing) / (targetCardWidth + itemSpacing))
        return min(maximumVisibleSlots, max(minimumVisibleSlots, Int(capacity)))
    }
}

enum SwitcherWindowOnlyPanelSizing {
    static let maximumWidthRatio: CGFloat = 0.82
    static let maximumHeightRatio: CGFloat = 0.75

    private static let minimumWidth: CGFloat = 640
    private static let minimumHeight: CGFloat = 360
    private static let targetCardWidth: CGFloat = 260
    private static let cardAspectRatio: CGFloat = 1.58
    private static let titleBarHeight: CGFloat = 30
    private static let horizontalPadding: CGFloat = 48
    private static let verticalPadding: CGFloat = 32
    private static let columnSpacing: CGFloat = 24
    private static let rowSpacing: CGFloat = 28
    private static let maximumColumns = 5

    static func preferredSize(
        visibleFrameSize: CGSize,
        itemCount: Int
    ) -> CGSize {
        let maximumWidth = max(1, visibleFrameSize.width * maximumWidthRatio)
        let maximumHeight = max(1, visibleFrameSize.height * maximumHeightRatio)
        let minimumResolvedWidth = min(minimumWidth, maximumWidth)
        let minimumResolvedHeight = min(minimumHeight, maximumHeight)
        let count = max(itemCount, 1)
        let widthCapacity = max(
            1,
            Int(
                floor(
                    (maximumWidth - horizontalPadding * 2 + columnSpacing)
                        / (targetCardWidth + columnSpacing)
                )
            )
        )
        let balancedColumns = max(1, Int(ceil(sqrt(Double(count) * 1.8))))
        let columns = min(
            min(count, maximumColumns),
            min(widthCapacity, balancedColumns)
        )
        let rows = Int(ceil(Double(count) / Double(columns)))
        let cardHeight = targetCardWidth / cardAspectRatio + titleBarHeight
        let preferredWidth =
            horizontalPadding * 2
            + CGFloat(columns) * targetCardWidth
            + CGFloat(max(columns - 1, 0)) * columnSpacing
        let preferredHeight =
            verticalPadding * 2
            + CGFloat(rows) * cardHeight
            + CGFloat(max(rows - 1, 0)) * rowSpacing

        return CGSize(
            width: min(maximumWidth, max(minimumResolvedWidth, preferredWidth)),
            height: min(maximumHeight, max(minimumResolvedHeight, preferredHeight))
        )
    }
}
