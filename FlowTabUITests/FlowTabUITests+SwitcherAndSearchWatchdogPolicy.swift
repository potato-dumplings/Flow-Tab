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
    static let pointerInteractionForegroundReadiness: TimeInterval = 10
    static let optionTabSingleAppRowProjection: TimeInterval = 5
    static let optionTabAppRowCollectionProjection: TimeInterval = 10
    static let optionTabSelectedAppProjection: TimeInterval = 3
    static let controlTabSingleWindowProjection: TimeInterval = 5
    static let controlTabWindowCollectionProjection: TimeInterval = 10

    static let compatibleBounds = [
        optionTabAppClickDismissal,
        controlTabWindowClickDismissal,
        searchResultClickDismissal,
        searchMockForegroundReadiness,
        spaceFixtureSearchResultPublication,
        searchHeaderProjection,
        searchMockSingleResultProjection,
        searchMockMultipleResultProjection,
        pointerInteractionForegroundReadiness,
        optionTabSingleAppRowProjection,
        optionTabAppRowCollectionProjection,
        optionTabSelectedAppProjection,
        controlTabSingleWindowProjection,
        controlTabWindowCollectionProjection
    ]
}

extension FlowTabUITests {
    func testSwitcherAndSearchWatchdogPolicyPreservesCompatibleBounds() {
        let policies = FlowTabUITestSwitcherAndSearchWatchdogPolicy.compatibleBounds
        XCTAssertEqual(
            policies,
            [2, 2, 2, 10, 5, 10, 5, 10, 10, 5, 10, 3, 5, 10]
        )
        XCTAssertTrue(policies.allSatisfy { $0.isFinite && $0 > 0 })
    }
}
