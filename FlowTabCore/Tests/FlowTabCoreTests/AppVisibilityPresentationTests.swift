import XCTest
@testable import FlowTabCore

final class AppVisibilityPresentationTests: XCTestCase {
    func testStaticDeclarationsAreUnavailableAcrossRuntimeModes() {
        for runtimePolicy in policiesIncludingNotRunning {
            XCTAssertEqual(
                presentation(
                    capability: .systemManaged(reason: .staticBundleDeclaration),
                    runtimePolicy: runtimePolicy,
                    preferenceHidden: true
                ),
                AppVisibilityPresentation(
                    state: .unavailable(reason: .staticBundleDeclaration),
                    controlMode: .unavailable
                )
            )
        }
    }

    func testDynamicAccessoryAndProhibitedApplicationsAreRuntimeHidden() {
        for runtimePolicy in [
            ApplicationRuntimeActivationPolicy.accessory,
            .prohibited
        ] {
            XCTAssertEqual(
                presentation(
                    runtimePolicy: runtimePolicy,
                    preferenceHidden: false
                ),
                AppVisibilityPresentation(
                    state: .hidden(reason: .runtimeMode),
                    controlMode: .regularModeOnly
                )
            )
        }
    }

    func testRegularAndNotRunningApplicationsUseUserPreference() {
        for runtimePolicy in [ApplicationRuntimeActivationPolicy.regular, nil] {
            XCTAssertEqual(
                presentation(
                    runtimePolicy: runtimePolicy,
                    preferenceHidden: false
                ),
                AppVisibilityPresentation(
                    state: .visible,
                    controlMode: .standard
                )
            )
            XCTAssertEqual(
                presentation(
                    runtimePolicy: runtimePolicy,
                    preferenceHidden: true
                ),
                AppVisibilityPresentation(
                    state: .hidden(reason: .userPreference),
                    controlMode: .standard
                )
            )
        }
    }

    func testCurrentFlowTabProcessUsesStandardPreferenceControl() {
        XCTAssertEqual(
            presentation(
                runtimePolicy: .accessory,
                isCurrentProcess: true,
                preferenceHidden: false
            ),
            AppVisibilityPresentation(
                state: .visible,
                controlMode: .standard
            )
        )
    }

    func testRuntimePolicyAggregationUsesSwitcherEligibilityPriority() {
        XCTAssertEqual(
            ApplicationRuntimeActivationPolicyAggregation.aggregate([
                .prohibited,
                .accessory,
                .regular
            ]),
            .regular
        )
        XCTAssertEqual(
            ApplicationRuntimeActivationPolicyAggregation.aggregate([
                .prohibited,
                .accessory
            ]),
            .accessory
        )
        XCTAssertEqual(
            ApplicationRuntimeActivationPolicyAggregation.aggregate([.prohibited]),
            .prohibited
        )
        XCTAssertNil(ApplicationRuntimeActivationPolicyAggregation.aggregate([]))
    }

    private var policiesIncludingNotRunning: [ApplicationRuntimeActivationPolicy?] {
        [.regular, .accessory, .prohibited, nil]
    }

    private func presentation(
        capability: AppVisibilityCapability = .configurable,
        runtimePolicy: ApplicationRuntimeActivationPolicy?,
        isCurrentProcess: Bool = false,
        preferenceHidden: Bool
    ) -> AppVisibilityPresentation {
        AppVisibilityPresentationPolicy.presentation(
            for: AppVisibilityPresentationFacts(
                visibilityCapability: capability,
                runtimeActivationPolicy: runtimePolicy,
                isCurrentProcess: isCurrentProcess,
                isHiddenByUserPreference: preferenceHidden
            )
        )
    }
}
