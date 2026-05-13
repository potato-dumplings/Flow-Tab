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
}
