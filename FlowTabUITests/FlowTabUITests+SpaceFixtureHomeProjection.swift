import Foundation
import XCTest

enum FlowTabUITestSpaceFixtureHomeProjectionPolicy {
    static let homeTabNavigationWatchdog: TimeInterval = 10
    static let defaultAppRowProjectionWatchdog: TimeInterval = 20
    static let runtimeLifecycleAppSummaryWatchdog: TimeInterval = 12
    static let runtimeWindowMutationInitialSummaryWatchdog: TimeInterval = 12
    static let runtimeWindowMutationFinalSummaryWatchdog: TimeInterval = 15

    static func multiAppAtomicRowProjectionWatchdog(
        rowCount: Int
    ) -> TimeInterval {
        let compatibleRowCount = max(rowCount, 1)
        let compatibleBoundsPerRow = 2
        return defaultAppRowProjectionWatchdog
            * TimeInterval(
                compatibleRowCount * compatibleBoundsPerRow
            )
    }
}

fileprivate final class FlowTabUITestSpaceFixtureHomeTransitionState {
    var acceptsPostTriggerEvidence = false
}

final class FlowTabUITestSpaceFixtureHomeTransitionObservationOwner {
    private let state:
        FlowTabUITestSpaceFixtureHomeTransitionState
    private let projection:
        FlowTabUITestHomeAppRowProjectionObservationOwner

    fileprivate init(
        state: FlowTabUITestSpaceFixtureHomeTransitionState,
        projection:
            FlowTabUITestHomeAppRowProjectionObservationOwner
    ) {
        self.state = state
        self.projection = projection
    }

    func start() {
        state.acceptsPostTriggerEvidence = false
        projection.start()
    }

    func markTriggerCompleted() {
        guard !state.acceptsPostTriggerEvidence else {
            return
        }
        state.acceptsPostTriggerEvidence = true
        projection.requestReadback(source: .triggerReadback)
    }

    func waitForResolution(
        timeout: TimeInterval
    ) -> FlowTabUITestConditionEvidence<
        FlowTabUITestHomeAppRowProjectionSnapshot
    >? {
        projection.waitForResolution(timeout: timeout)
    }

    var diagnosticSummary: String {
        "acceptsPostTriggerEvidence="
            + "\(state.acceptsPostTriggerEvidence) "
            + projection.diagnosticSummary
    }

    func cancel() {
        projection.cancel()
    }

    deinit {
        cancel()
    }
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
        let multiAppWatchdog =
            FlowTabUITestSpaceFixtureHomeProjectionPolicy
            .multiAppAtomicRowProjectionWatchdog(rowCount: 3)
        XCTAssertEqual(multiAppWatchdog, 120)
        XCTAssertTrue(multiAppWatchdog.isFinite)
        XCTAssertGreaterThan(multiAppWatchdog, 0)
    }

    func testSpaceFixtureHomeProjectionWindowMutationWatchdogPolicyCompatibility() {
        XCTAssertEqual(
            FlowTabUITestSpaceFixtureHomeProjectionPolicy
                .runtimeWindowMutationInitialSummaryWatchdog,
            12
        )
        XCTAssertTrue(
            FlowTabUITestSpaceFixtureHomeProjectionPolicy
                .runtimeWindowMutationInitialSummaryWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSpaceFixtureHomeProjectionPolicy
                .runtimeWindowMutationInitialSummaryWatchdog,
            0
        )
    }

    func testSpaceFixtureHomeProjectionWindowMutationFinalWatchdogPolicyCompatibility() {
        XCTAssertEqual(
            FlowTabUITestSpaceFixtureHomeProjectionPolicy
                .runtimeWindowMutationFinalSummaryWatchdog,
            15
        )
        XCTAssertTrue(
            FlowTabUITestSpaceFixtureHomeProjectionPolicy
                .runtimeWindowMutationFinalSummaryWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSpaceFixtureHomeProjectionPolicy
                .runtimeWindowMutationFinalSummaryWatchdog,
            0
        )
    }

    func makeSpaceFixtureHomeTransitionObservation(
        in app: XCUIApplication,
        rowIdentifier: String,
        expectedValue: String
    ) -> FlowTabUITestSpaceFixtureHomeTransitionObservationOwner {
        let state =
            FlowTabUITestSpaceFixtureHomeTransitionState()
        let projection =
            makeHomeAppRowProjectionObservation(
                in: app,
                rows: [
                    .init(
                        identifier: rowIdentifier,
                        value: expectedValue
                    )
                ],
                frameOrder: .unconstrained,
                acceptsEvidence: {
                    state.acceptsPostTriggerEvidence
                }
            )
        return FlowTabUITestSpaceFixtureHomeTransitionObservationOwner(
            state: state,
            projection: projection
        )
    }

    func makeSpaceFixtureHomeTransitionObservation(
        in app: XCUIApplication,
        rows: [FlowTabUITestHomeAppRowProjectionExpectation.Row],
        requiredApplicationState: XCUIApplication.State? = nil
    ) -> FlowTabUITestSpaceFixtureHomeTransitionObservationOwner {
        let state =
            FlowTabUITestSpaceFixtureHomeTransitionState()
        let projection =
            makeHomeAppRowProjectionObservation(
                in: app,
                rows: rows,
                frameOrder: .unconstrained,
                requiredApplicationState:
                    requiredApplicationState,
                acceptsEvidence: {
                    state.acceptsPostTriggerEvidence
                }
            )
        return FlowTabUITestSpaceFixtureHomeTransitionObservationOwner(
            state: state,
            projection: projection
        )
    }

    @discardableResult
    func waitForSpaceFixtureHomeAppRowsAfterNavigation(
        _ workflow: SpaceFixtureResolvedWorkflow,
        in app: XCUIApplication
    ) -> FlowTabUITestHomeAppRowProjectionSnapshot? {
        let rows = workflow.apps.map {
            FlowTabUITestHomeAppRowProjectionExpectation.Row(
                identifier:
                    $0.identity.homeAppAccessibilityIdentifier,
                value: "\($0.windowCount)w"
            )
        }
        let observation =
            makeSpaceFixtureHomeTransitionObservation(
                in: app,
                rows: rows,
                requiredApplicationState: .runningForeground
            )
        observation.start()
        defer { observation.cancel() }

        let homeTabButtons = app.buttons.matching(
            identifier: Identifier.homeTabButton
        )
        guard tapFirstHittable(
            in: homeTabButtons,
            timeout:
                FlowTabUITestSpaceFixtureHomeProjectionPolicy
                .homeTabNavigationWatchdog
        ) else {
            XCTFail(
                "Space Fixture multi-App Home navigation watchdog expired. "
                    + "finalCandidateCount=\(homeTabButtons.count) "
                    + observation.diagnosticSummary
            )
            return nil
        }

        observation.markTriggerCompleted()
        let watchdog =
            FlowTabUITestSpaceFixtureHomeProjectionPolicy
            .multiAppAtomicRowProjectionWatchdog(
                rowCount: rows.count
            )
        guard let evidence = observation.waitForResolution(
            timeout: watchdog
        ) else {
            XCTFail(
                "Space Fixture multi-App Home row-projection watchdog "
                    + "expired. "
                    + observation.diagnosticSummary
            )
            return nil
        }
        return evidence.value
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
