import XCTest
@testable import FlowTab

extension FlowTabTests {
    func testSwitcherAppRemovalAnimationPolicyKeepsNamedVisualContract() {
        let policy = SwitcherAppRemovalAnimationPolicy.default

        XCTAssertEqual(policy.duration, 0.14)
        XCTAssertEqual(policy.maximumAnimatedAppCount, 16)
        XCTAssertEqual(
            policy.animationDuration(appCount: 0),
            policy.duration
        )
        XCTAssertEqual(
            policy.animationDuration(
                appCount: policy.maximumAnimatedAppCount
            ),
            policy.duration
        )
        XCTAssertNil(policy.animationDuration(appCount: -1))
        XCTAssertNil(
            policy.animationDuration(
                appCount: policy.maximumAnimatedAppCount + 1
            )
        )
    }

    func testSwitcherAppRemovalAnimationPolicyUsesInjectedDurationAndBoundary() {
        let injectedDuration = 0.6
        let policy = SwitcherAppRemovalAnimationPolicy(
            duration: injectedDuration,
            maximumAnimatedAppCount: 2
        )

        XCTAssertEqual(
            policy.animationDuration(appCount: 1),
            injectedDuration
        )
        XCTAssertEqual(
            policy.animationDuration(appCount: 2),
            injectedDuration
        )
        XCTAssertNil(policy.animationDuration(appCount: 3))
    }
}
