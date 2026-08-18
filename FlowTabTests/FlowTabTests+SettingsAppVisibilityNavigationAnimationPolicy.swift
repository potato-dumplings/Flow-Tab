import XCTest
@testable import FlowTab

extension FlowTabTests {
    func testSettingsAppVisibilityNavigationPolicyKeepsNamedVisualContract() {
        XCTAssertEqual(
            SettingsAppVisibilityNavigationAnimationPolicy.default.duration,
            0.18
        )
    }

    func testAppSettingsViewUsesInjectedAppVisibilityNavigationPolicy() {
        let injectedPolicy =
            SettingsAppVisibilityNavigationAnimationPolicy(duration: 0.9)
        let view = AppSettingsView(
            isActive: true,
            appVisibilityNavigationAnimationPolicy: injectedPolicy
        )

        XCTAssertEqual(
            view.appVisibilityNavigationAnimationPolicy,
            injectedPolicy
        )
    }
}
