import XCTest
@testable import FlowTab

extension FlowTabTests {
    func testSettingsAppVisibilityNavigationPolicyKeepsNamedVisualContract() {
        XCTAssertEqual(
            SettingsAppVisibilityNavigationAnimationPolicy.default.duration,
            0.18
        )
    }

    @MainActor
    func testAppSettingsViewUsesInjectedAppVisibilityNavigationPolicy() {
        let injectedPolicy =
            SettingsAppVisibilityNavigationAnimationPolicy(duration: 0.9)
        let view = AppSettingsView(
            isActive: true,
            appVisibilityModel: AppVisibilityManagerModel(),
            appVisibilityNavigationAnimationPolicy: injectedPolicy
        )

        XCTAssertEqual(
            view.appVisibilityNavigationAnimationPolicy,
            injectedPolicy
        )
    }
}
