import XCTest

enum FlowTabUITestSwitcherAndSearchWatchdogPolicy {
    static let optionTabAppClickDismissal: TimeInterval = 2
    static let controlTabWindowClickDismissal: TimeInterval = 2
    static let searchResultClickDismissal: TimeInterval = 2
    static let searchMockForegroundReadiness: TimeInterval = 10
    static let spaceFixtureSearchResultPublication: TimeInterval = 5
    static let searchHeaderProjection: TimeInterval = 10
    static let searchMockSingleResultProjection: TimeInterval = 5
    static let searchMockMultipleResultProjection: TimeInterval = 10
    static let switcherAndSearchForegroundReadiness: TimeInterval = 10
    static let optionTabSingleAppRowProjection: TimeInterval = 5
    static let optionTabAppRowCollectionProjection: TimeInterval = 10
    static let optionTabSelectedAppProjection: TimeInterval = 3
    static let controlTabSingleWindowProjection: TimeInterval = 5
    static let controlTabWindowCollectionProjection: TimeInterval = 10
    static let controlTabSelectedWindowProjection: TimeInterval = 3
    static let searchSelectedResultProjection: TimeInterval = 3
    static let searchPointerSingleResultProjection: TimeInterval = 5
    static let searchPointerResultCollectionProjection: TimeInterval = 10
    static let initialStaleOcclusionBrowserRowProjection: TimeInterval = 5

    static let compatibleBounds = [
        optionTabAppClickDismissal,
        controlTabWindowClickDismissal,
        searchResultClickDismissal,
        searchMockForegroundReadiness,
        spaceFixtureSearchResultPublication,
        searchHeaderProjection,
        searchMockSingleResultProjection,
        searchMockMultipleResultProjection,
        switcherAndSearchForegroundReadiness,
        optionTabSingleAppRowProjection,
        optionTabAppRowCollectionProjection,
        optionTabSelectedAppProjection,
        controlTabSingleWindowProjection,
        controlTabWindowCollectionProjection,
        controlTabSelectedWindowProjection,
        searchSelectedResultProjection,
        searchPointerSingleResultProjection,
        searchPointerResultCollectionProjection,
        initialStaleOcclusionBrowserRowProjection
    ]
}

extension FlowTabUITests {
    func testSwitcherAndSearchWatchdogPolicyPreservesCompatibleBounds() {
        let policies = FlowTabUITestSwitcherAndSearchWatchdogPolicy.compatibleBounds
        XCTAssertEqual(
            policies,
            [
                2, 2, 2, 10, 5, 10, 5, 10, 10, 5, 10, 3,
                5, 10, 3, 3, 5, 10, 5
            ]
        )
        XCTAssertTrue(policies.allSatisfy { $0.isFinite && $0 > 0 })
    }
}
