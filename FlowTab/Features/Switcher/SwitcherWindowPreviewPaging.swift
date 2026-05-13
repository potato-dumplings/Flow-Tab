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

    private static let minCardWidth: CGFloat = 120
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
        return max(minCardWidth, min(maxCardWidth, rawWidth))
    }

    private static var navigationIndicatorReserveWidth: CGFloat {
        indicatorWidth * 2 + indicatorSpacing * 2
    }

    private static func capacity(for availableWidth: CGFloat) -> Int {
        guard availableWidth > 0 else { return 1 }
        let capacity = floor((availableWidth + itemSpacing) / (minCardWidth + itemSpacing))
        return max(1, Int(capacity))
    }
}
