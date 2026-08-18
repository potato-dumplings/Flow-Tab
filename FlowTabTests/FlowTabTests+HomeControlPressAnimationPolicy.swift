import XCTest
@testable import FlowTab

extension FlowTabTests {
    func testHomeControlPressAnimationPolicyKeepsNamedVisualContract() {
        XCTAssertEqual(HomeControlPressAnimationPolicy.default.duration, 0.12)
    }

    func testFlowPageActionButtonUsesInjectedPressAnimationPolicyAndDirectAction() {
        let injectedPolicy = HomeControlPressAnimationPolicy(duration: 0.8)
        var actionCount = 0
        let button = FlowPageActionButton(
            title: "Action",
            pressAnimationPolicy: injectedPolicy
        ) {
            actionCount += 1
        }

        XCTAssertEqual(button.pressAnimationPolicy, injectedPolicy)

        button.action()

        XCTAssertEqual(actionCount, 1)
    }
}
