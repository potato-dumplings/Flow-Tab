import XCTest
@testable import FlowTabCore

final class ApplicationIdentityPolicyTests: XCTestCase {
    func testRegularRunningApplicationIsConfigurable() {
        XCTAssertEqual(
            ApplicationIdentityPolicy.decision(
                for: ApplicationIdentityFacts(
                    isCurrentProcess: false,
                    isTerminated: false,
                    runtimeActivationPolicy: .regular,
                    bundleSource: .none,
                    isUIElement: false,
                    isBackgroundOnly: false
                )
            ),
            .included(visibilityCapability: .configurable)
        )
    }

    func testCurrentFlowTabProcessIsConfigurableWhileAccessory() {
        XCTAssertEqual(
            ApplicationIdentityPolicy.decision(
                for: ApplicationIdentityFacts(
                    isCurrentProcess: true,
                    isTerminated: false,
                    runtimeActivationPolicy: .accessory,
                    bundleSource: .none,
                    isUIElement: true,
                    isBackgroundOnly: false
                )
            ),
            .included(visibilityCapability: .configurable)
        )
    }

    func testTopLevelMenuBarAndBackgroundApplicationsAreSystemManaged() {
        let menuBarDecision = ApplicationIdentityPolicy.decision(
            for: ApplicationIdentityFacts(
                isCurrentProcess: false,
                isTerminated: false,
                runtimeActivationPolicy: .accessory,
                bundleSource: .standardApplicationsDirectory,
                isUIElement: true,
                isBackgroundOnly: false
            )
        )
        let backgroundDecision = ApplicationIdentityPolicy.decision(
            for: ApplicationIdentityFacts(
                isCurrentProcess: false,
                isTerminated: false,
                runtimeActivationPolicy: nil,
                bundleSource: .standardApplicationsDirectory,
                isUIElement: false,
                isBackgroundOnly: true
            )
        )

        let expected = ApplicationDirectoryDecision.included(
            visibilityCapability: .systemManaged(reason: .macOSRuntimeMode)
        )
        XCTAssertEqual(menuBarDecision, expected)
        XCTAssertEqual(backgroundDecision, expected)
    }

    func testAccessoryHelperOutsideStandardApplicationDirectoryIsExcluded() {
        XCTAssertEqual(
            ApplicationIdentityPolicy.decision(
                for: ApplicationIdentityFacts(
                    isCurrentProcess: false,
                    isTerminated: false,
                    runtimeActivationPolicy: .accessory,
                    bundleSource: .none,
                    isUIElement: false,
                    isBackgroundOnly: false
                )
            ),
            .excluded
        )
    }

    func testTerminatedRunningObjectIsExcluded() {
        XCTAssertEqual(
            ApplicationIdentityPolicy.decision(
                for: ApplicationIdentityFacts(
                    isCurrentProcess: false,
                    isTerminated: true,
                    runtimeActivationPolicy: .regular,
                    bundleSource: .standardApplicationsDirectory,
                    isUIElement: false,
                    isBackgroundOnly: false
                )
            ),
            .excluded
        )
    }
}
