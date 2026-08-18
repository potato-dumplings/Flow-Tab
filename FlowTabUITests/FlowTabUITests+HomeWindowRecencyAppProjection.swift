import Foundation
import XCTest

enum FlowTabUITestHomeWindowRecencyAppProjectionPolicy {
    static let homeNavigationWatchdog: TimeInterval = 10
    static let targetAppRowPublicationWatchdog: TimeInterval = 20
}

extension FlowTabUITests {
    func waitForHomeWindowRecencyTargetAppRowAfterNavigation(
        identifier: String,
        appName: String,
        in app: XCUIApplication,
        targetDescription: String = #function,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement? {
        let row = app.buttons
            .matching(identifier: identifier)
            .firstMatch
        let observation =
            FlowTabUITestElementCollectionExistenceObservationOwner(
                expectedIdentifiers: [identifier],
                readback: {
                    [
                        FlowTabUITestElementExistenceReadback(
                            identifier: identifier,
                            exists: row.exists
                        )
                    ]
                }
            )
        observation.start()
        defer { observation.cancel() }

        guard observation.latestEvidence?.source == .initialReadback else {
            XCTFail(
                "Home recency target-App observation did not establish "
                    + "its initial readback. target=\(targetDescription) "
                    + observation.diagnosticSummary,
                file: file,
                line: line
            )
            return nil
        }

        guard assertSidebarTabProjectionAfterNavigation(
            in: app,
            target: .home,
            triggerWatchdog:
                FlowTabUITestHomeWindowRecencyAppProjectionPolicy
                    .homeNavigationWatchdog,
            projectionWatchdog:
                FlowTabUITestHomeWindowRecencyAppProjectionPolicy
                    .homeNavigationWatchdog
        ) else {
            return nil
        }

        observation.markTriggerCompleted()
        guard observation.waitForResolution(
            timeout:
                FlowTabUITestHomeWindowRecencyAppProjectionPolicy
                    .targetAppRowPublicationWatchdog
        ) != nil else {
            XCTFail(
                "Home recency target-App row publication watchdog "
                    + "expired. target=\(targetDescription) "
                    + "app=\(appName) expectedIdentifier=\(identifier) "
                    + observation.diagnosticSummary,
                file: file,
                line: line
            )
            return nil
        }
        return row
    }

    func testHomeWindowRecencyAppProjectionPolicyCompatibility() {
        let policy =
            FlowTabUITestHomeWindowRecencyAppProjectionPolicy.self
        XCTAssertEqual(policy.homeNavigationWatchdog, 10)
        XCTAssertTrue(policy.homeNavigationWatchdog.isFinite)
        XCTAssertGreaterThan(policy.homeNavigationWatchdog, 0)
        XCTAssertEqual(policy.targetAppRowPublicationWatchdog, 20)
        XCTAssertTrue(policy.targetAppRowPublicationWatchdog.isFinite)
        XCTAssertGreaterThanOrEqual(
            policy.targetAppRowPublicationWatchdog,
            policy.homeNavigationWatchdog
        )
    }
}
