import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    func testWindowPreviewPagingUsesResolutionDependentPageSize() {
        let narrowPage = SwitcherWindowPreviewPaging.page(
            itemCount: 100,
            selectedIndex: 0,
            availableWidth: 520
        )
        let widePage = SwitcherWindowPreviewPaging.page(
            itemCount: 100,
            selectedIndex: 0,
            availableWidth: 1_440
        )

        XCTAssertTrue(narrowPage.showsNavigationIndicators)
        XCTAssertTrue(widePage.showsNavigationIndicators)
        XCTAssertEqual(narrowPage.visibleRange.lowerBound, 0)
        XCTAssertEqual(widePage.visibleRange.lowerBound, 0)
        XCTAssertGreaterThan(widePage.visibleRange.count, narrowPage.visibleRange.count)
        XCTAssertLessThan(widePage.visibleRange.count, 100)
        XCTAssertFalse(narrowPage.hasPreviousPage)
        XCTAssertTrue(narrowPage.hasNextPage)
    }

    func testWindowPreviewPagingClampsVisibleSlotsToDesignRange() {
        let narrowPage = SwitcherWindowPreviewPaging.page(
            itemCount: 100,
            selectedIndex: 0,
            availableWidth: 520
        )
        let sixteenInchPage = SwitcherWindowPreviewPaging.page(
            itemCount: 100,
            selectedIndex: 0,
            availableWidth: 1_728
        )
        let hugePage = SwitcherWindowPreviewPaging.page(
            itemCount: 100,
            selectedIndex: 0,
            availableWidth: 4_000
        )

        XCTAssertEqual(narrowPage.visibleRange.count, 6)
        XCTAssertEqual(sixteenInchPage.visibleRange.count, 10)
        XCTAssertEqual(hugePage.visibleRange.count, 16)
    }

    func testWindowPreviewPagingPreferredAvailableWidthKeepsTargetCardWidthForResolvedSlots() {
        let fourteenFortyWidth = SwitcherWindowPreviewPaging.preferredAvailableWidth(
            itemCount: 100,
            maximumAvailableWidth: 1_292
        )
        let sixteenInchWidth = SwitcherWindowPreviewPaging.preferredAvailableWidth(
            itemCount: 100,
            maximumAvailableWidth: 1_580
        )

        XCTAssertEqual(fourteenFortyWidth, 1_276, accuracy: 0.001)
        XCTAssertEqual(sixteenInchWidth, 1_580, accuracy: 0.001)
    }

    func testWindowPreviewPagingShowsSelectedWindowContainingPage() {
        let page = SwitcherWindowPreviewPaging.page(
            itemCount: 100,
            selectedIndex: 42,
            availableWidth: 760
        )

        XCTAssertTrue(page.visibleRange.contains(42))
        XCTAssertLessThan(page.visibleRange.count, 100)
        XCTAssertTrue(page.hasPreviousPage)
        XCTAssertTrue(page.hasNextPage)
    }

    func testWindowPreviewPagingOmitsNavigationWhenAllWindowsFit() {
        let page = SwitcherWindowPreviewPaging.page(
            itemCount: 3,
            selectedIndex: 1,
            availableWidth: 760
        )

        XCTAssertEqual(page.visibleRange, 0..<3)
        XCTAssertFalse(page.showsNavigationIndicators)
        XCTAssertFalse(page.hasPreviousPage)
        XCTAssertFalse(page.hasNextPage)
    }

    func testWindowOnlyPanelSizingUsesResponsiveScreenBounds() {
        let singleWindowSize = SwitcherWindowOnlyPanelSizing.preferredSize(
            visibleFrameSize: CGSize(width: 1_728, height: 1_117),
            itemCount: 1
        )
        let eightWindowSize = SwitcherWindowOnlyPanelSizing.preferredSize(
            visibleFrameSize: CGSize(width: 1_728, height: 1_117),
            itemCount: 8
        )
        let compactScreenSize = SwitcherWindowOnlyPanelSizing.preferredSize(
            visibleFrameSize: CGSize(width: 600, height: 400),
            itemCount: 8
        )

        XCTAssertEqual(singleWindowSize, CGSize(width: 640, height: 360))
        XCTAssertGreaterThan(eightWindowSize.width, singleWindowSize.width)
        XCTAssertGreaterThan(eightWindowSize.height, singleWindowSize.height)
        XCTAssertLessThanOrEqual(eightWindowSize.width, 1_728 * 0.82)
        XCTAssertLessThanOrEqual(eightWindowSize.height, 1_117 * 0.75)
        XCTAssertEqual(compactScreenSize.width, 492, accuracy: 0.001)
        XCTAssertEqual(compactScreenSize.height, 300, accuracy: 0.001)
    }
}
