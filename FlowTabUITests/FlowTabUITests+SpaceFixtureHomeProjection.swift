import Foundation
import XCTest

enum FlowTabUITestSpaceFixtureHomeProjectionPolicy {
    static let homeTabNavigationWatchdog: TimeInterval = 10
    static let defaultAppRowProjectionWatchdog: TimeInterval = 20
    static let runtimeLifecycleAppSummaryWatchdog: TimeInterval = 12
}

extension FlowTabUITests {
    func testSpaceFixtureHomeProjectionWatchdogPolicyCompatibility() {
        XCTAssertEqual(
            FlowTabUITestSpaceFixtureHomeProjectionPolicy
                .homeTabNavigationWatchdog,
            10
        )
        XCTAssertTrue(
            FlowTabUITestSpaceFixtureHomeProjectionPolicy
                .homeTabNavigationWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSpaceFixtureHomeProjectionPolicy
                .homeTabNavigationWatchdog,
            0
        )
        XCTAssertEqual(
            FlowTabUITestSpaceFixtureHomeProjectionPolicy
                .defaultAppRowProjectionWatchdog,
            20
        )
        XCTAssertTrue(
            FlowTabUITestSpaceFixtureHomeProjectionPolicy
                .defaultAppRowProjectionWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSpaceFixtureHomeProjectionPolicy
                .defaultAppRowProjectionWatchdog,
            0
        )
        XCTAssertEqual(
            FlowTabUITestSpaceFixtureHomeProjectionPolicy
                .runtimeLifecycleAppSummaryWatchdog,
            12
        )
        XCTAssertTrue(
            FlowTabUITestSpaceFixtureHomeProjectionPolicy
                .runtimeLifecycleAppSummaryWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSpaceFixtureHomeProjectionPolicy
                .runtimeLifecycleAppSummaryWatchdog,
            0
        )
    }

    func openHomeTabAndSelectSpaceFixtureApp(
        in app: XCUIApplication,
        identity: SpaceFixtureAppIdentity,
        expectedValue: String? = nil,
        timeout: TimeInterval =
            FlowTabUITestSpaceFixtureHomeProjectionPolicy
                .defaultAppRowProjectionWatchdog
    ) -> XCUIElement {
        let rowIdentifier =
            identity.homeAppAccessibilityIdentifier
        let fixtureAppRows =
            app.buttons.matching(identifier: rowIdentifier)
        let fixtureAppRow = fixtureAppRows.firstMatch
        let rowProjection =
            makeHomeAppRowProjectionObservation(
                in: app,
                rows: [
                    .init(
                        identifier: rowIdentifier,
                        value: expectedValue
                    )
                ],
                frameOrder: .unconstrained
            )
        rowProjection.start()
        defer { rowProjection.cancel() }

        let homeTabButtons =
            app.buttons.matching(
                identifier: Identifier.homeTabButton
            )
        guard tapFirstHittable(
            in: homeTabButtons,
            timeout:
                FlowTabUITestSpaceFixtureHomeProjectionPolicy
                    .homeTabNavigationWatchdog
        ) else {
            XCTFail(
                "Space Fixture Home navigation watchdog expired. "
                    + "finalCandidateCount=\(homeTabButtons.count)"
            )
            return fixtureAppRow
        }

        guard rowProjection.waitForResolution(
            timeout: timeout
        ) != nil else {
            XCTFail(
                "Space Fixture Home app-row projection watchdog expired. "
                    + "identifier=\(rowIdentifier) "
                    + "expectedValue=\(expectedValue ?? "any") "
                    + rowProjection.diagnosticSummary
            )
            return fixtureAppRow
        }

        guard tapFirstHittable(
            in: fixtureAppRows,
            timeout: timeout
        ) else {
            XCTFail(
                "Space Fixture Home app-row selection watchdog expired. "
                    + "identifier=\(rowIdentifier) "
                    + "finalCandidateCount=\(fixtureAppRows.count) "
                    + "finalExists=\(fixtureAppRow.exists) "
                    + "finalHittable=\(fixtureAppRow.isHittable)"
            )
            return fixtureAppRow
        }
        return fixtureAppRow
    }
}
