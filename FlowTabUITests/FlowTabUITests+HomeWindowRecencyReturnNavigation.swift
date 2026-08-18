import Foundation
import XCTest

enum FlowTabUITestHomeWindowRecencyReturnNavigationPolicy {
    static let homeTabTriggerWatchdog: TimeInterval = 10
    static let homeProjectionWatchdog: TimeInterval = 10
}

extension FlowTabUITests {
    @discardableResult
    func navigateHomeAfterHomeWindowRecencyFlowTabActivation(
        in app: XCUIApplication
    ) -> Bool {
        assertSidebarTabProjectionAfterNavigation(
            in: app,
            target: .home,
            triggerWatchdog:
                FlowTabUITestHomeWindowRecencyReturnNavigationPolicy
                    .homeTabTriggerWatchdog,
            projectionWatchdog:
                FlowTabUITestHomeWindowRecencyReturnNavigationPolicy
                    .homeProjectionWatchdog
        )
    }

    func testHomeWindowRecencyReturnNavigationPolicyCompatibility() {
        let policy =
            FlowTabUITestHomeWindowRecencyReturnNavigationPolicy.self
        XCTAssertEqual(policy.homeTabTriggerWatchdog, 10)
        XCTAssertTrue(policy.homeTabTriggerWatchdog.isFinite)
        XCTAssertGreaterThan(policy.homeTabTriggerWatchdog, 0)
        XCTAssertEqual(policy.homeProjectionWatchdog, 10)
        XCTAssertTrue(policy.homeProjectionWatchdog.isFinite)
        XCTAssertGreaterThan(policy.homeProjectionWatchdog, 0)
    }

    func testHomeWindowRecencyReturnNavigationSlowSchedulingOnlyDelaysProjection() {
        var snapshot = FlowTabUITestSidebarTabProjectionSnapshot(
            applicationState: .runningForeground,
            homeContentExists: false,
            logsContentExists: true,
            settingsContentExists: false
        )
        var triggerDidComplete = false
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner = FlowTabUITestSidebarTabProjectionObservationOwner(
            expectation: .init(target: .home),
            observationRegistration: { callback in
                scheduledReadback = callback
                return FlowTabUITestObservationCancellation {
                    cancellationCount += 1
                }
            },
            acceptsResolution: { triggerDidComplete },
            readback: { snapshot }
        )
        owner.start()
        defer { owner.cancel() }

        triggerDidComplete = true
        owner.requestReadback(source: .triggerReadback)
        for _ in 0..<5 {
            scheduledReadback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }

        snapshot = FlowTabUITestSidebarTabProjectionSnapshot(
            applicationState: .runningForeground,
            homeContentExists: true,
            logsContentExists: false,
            settingsContentExists: false
        )
        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .scheduledReadback
        )
        XCTAssertEqual(owner.resolvedEvidence?.value, snapshot)
        XCTAssertEqual(cancellationCount, 1)
    }
}
