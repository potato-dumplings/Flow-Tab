import Foundation
import XCTest

private enum FlowTabUITestHomePermissionBoundaryProjectionTestPolicy {
    static let watchdog: TimeInterval = 0.01
}

private enum FlowTabUITestHomePermissionBoundaryProjectionTestFixture {
    static let applicationRowIdentifier =
        "flowtab.home.app.com.example.flowtab"
    static let applicationRowValue = "0w hidden"
    static let hiddenAppsIdentifier =
        "flowtab.home.stats.hidden-apps"
    static let hiddenAppsValue = "1"

    static let expectation =
        FlowTabUITestHomePermissionBoundaryProjectionExpectation(
            applicationRowIdentifier: applicationRowIdentifier,
            applicationRowValue: applicationRowValue,
            hiddenAppsIdentifier: hiddenAppsIdentifier,
            hiddenAppsValue: hiddenAppsValue
        )

    static func snapshot(
        applicationRowIdentifier: String =
            FlowTabUITestHomePermissionBoundaryProjectionTestFixture
                .applicationRowIdentifier,
        applicationRowExists: Bool = true,
        applicationRowValue: String? =
            FlowTabUITestHomePermissionBoundaryProjectionTestFixture
                .applicationRowValue,
        hiddenAppsIdentifier: String =
            FlowTabUITestHomePermissionBoundaryProjectionTestFixture
                .hiddenAppsIdentifier,
        hiddenAppsExists: Bool = true,
        hiddenAppsValue: String? =
            FlowTabUITestHomePermissionBoundaryProjectionTestFixture
                .hiddenAppsValue
    ) -> FlowTabUITestHomePermissionBoundaryProjectionSnapshot {
        FlowTabUITestHomePermissionBoundaryProjectionSnapshot(
            applicationRowIdentifier: applicationRowIdentifier,
            applicationRowExists: applicationRowExists,
            applicationRowValue: applicationRowValue,
            hiddenAppsIdentifier: hiddenAppsIdentifier,
            hiddenAppsExists: hiddenAppsExists,
            hiddenAppsValue: hiddenAppsValue
        )
    }
}

extension FlowTabUITests {
    func testHomePermissionBoundaryProjectionWatchdogPreservesCompatibleBound() {
        XCTAssertEqual(
            FlowTabUITestHomePermissionBoundaryProjectionPolicy
                .watchdog,
            6
        )
        XCTAssertTrue(
            FlowTabUITestHomePermissionBoundaryProjectionPolicy
                .watchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestHomePermissionBoundaryProjectionPolicy
                .watchdog,
            0
        )
    }

    func testHomePermissionBoundaryProjectionRequiresOneExactSnapshot() {
        let expectation =
            FlowTabUITestHomePermissionBoundaryProjectionTestFixture
                .expectation

        XCTAssertTrue(
            expectation.isSatisfied(
                by:
                    FlowTabUITestHomePermissionBoundaryProjectionTestFixture
                        .snapshot()
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by:
                    FlowTabUITestHomePermissionBoundaryProjectionTestFixture
                        .snapshot(
                            applicationRowIdentifier:
                                "flowtab.home.app.com.example.other"
                        )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by:
                    FlowTabUITestHomePermissionBoundaryProjectionTestFixture
                        .snapshot(
                            applicationRowExists: false,
                            applicationRowValue: nil
                        )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by:
                    FlowTabUITestHomePermissionBoundaryProjectionTestFixture
                        .snapshot(
                            applicationRowValue: "1w hidden"
                        )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by:
                    FlowTabUITestHomePermissionBoundaryProjectionTestFixture
                        .snapshot(
                            hiddenAppsIdentifier:
                                "flowtab.home.stats.visible-apps"
                        )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by:
                    FlowTabUITestHomePermissionBoundaryProjectionTestFixture
                        .snapshot(
                            hiddenAppsExists: false,
                            hiddenAppsValue: nil
                        )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by:
                    FlowTabUITestHomePermissionBoundaryProjectionTestFixture
                        .snapshot(hiddenAppsValue: "2")
            )
        )
    }

    func testHomePermissionBoundaryProjectionAcceptsMinimumHiddenAppCount() {
        let expectation =
            FlowTabUITestHomePermissionBoundaryProjectionExpectation(
                applicationRowIdentifier:
                    FlowTabUITestHomePermissionBoundaryProjectionTestFixture
                        .applicationRowIdentifier,
                applicationRowValue:
                    FlowTabUITestHomePermissionBoundaryProjectionTestFixture
                        .applicationRowValue,
                hiddenAppsIdentifier:
                    FlowTabUITestHomePermissionBoundaryProjectionTestFixture
                        .hiddenAppsIdentifier,
                minimumHiddenApps: 1
            )

        XCTAssertTrue(
            expectation.isSatisfied(
                by:
                    FlowTabUITestHomePermissionBoundaryProjectionTestFixture
                        .snapshot(hiddenAppsValue: "2")
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by:
                    FlowTabUITestHomePermissionBoundaryProjectionTestFixture
                        .snapshot(hiddenAppsValue: "0")
            )
        )
    }

    func testHomePermissionBoundaryProjectionObserverUsesInitialExactSnapshot() {
        let owner =
            FlowTabUITestHomePermissionBoundaryProjectionObservationOwner(
                expectation:
                    FlowTabUITestHomePermissionBoundaryProjectionTestFixture
                        .expectation,
                observationRegistration: nil,
                readback: {
                    FlowTabUITestHomePermissionBoundaryProjectionTestFixture
                        .snapshot()
                }
            )
        owner.start()
        defer { owner.cancel() }

        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestHomePermissionBoundaryProjectionTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .initialReadback)
        XCTAssertEqual(
            evidence?.value,
            FlowTabUITestHomePermissionBoundaryProjectionTestFixture
                .snapshot()
        )
    }

    func testHomePermissionBoundaryProjectionObserverUsesPreinstalledScheduledReadback() {
        var snapshot =
            FlowTabUITestHomePermissionBoundaryProjectionTestFixture
                .snapshot(
                    applicationRowExists: false,
                    applicationRowValue: nil,
                    hiddenAppsExists: false,
                    hiddenAppsValue: nil
                )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestHomePermissionBoundaryProjectionObservationOwner(
                expectation:
                    FlowTabUITestHomePermissionBoundaryProjectionTestFixture
                        .expectation,
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: { snapshot }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(owner.resolvedEvidence)
        snapshot =
            FlowTabUITestHomePermissionBoundaryProjectionTestFixture
                .snapshot()
        scheduledReadback?(.scheduledReadback)
        scheduledReadback?(.notificationReadback)

        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestHomePermissionBoundaryProjectionTestPolicy
                    .watchdog
        )
        XCTAssertEqual(evidence?.source, .scheduledReadback)
        XCTAssertEqual(evidence?.value, snapshot)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testHomePermissionBoundaryProjectionObserverIgnoresEventsAfterCancellation() {
        var snapshot =
            FlowTabUITestHomePermissionBoundaryProjectionTestFixture
                .snapshot(
                    applicationRowExists: false,
                    applicationRowValue: nil
                )
        var eventHandler:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestHomePermissionBoundaryProjectionObservationOwner(
                expectation:
                    FlowTabUITestHomePermissionBoundaryProjectionTestFixture
                        .expectation,
                observationRegistration: { callback in
                    eventHandler = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: { snapshot }
            )
        owner.start()

        owner.cancel()
        snapshot =
            FlowTabUITestHomePermissionBoundaryProjectionTestFixture
                .snapshot()
        eventHandler?(.notificationReadback)

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testHomePermissionBoundaryProjectionWatchdogReportsFinalSnapshot() {
        var readbackCount = 0
        let owner =
            FlowTabUITestHomePermissionBoundaryProjectionObservationOwner(
                expectation:
                    FlowTabUITestHomePermissionBoundaryProjectionTestFixture
                        .expectation,
                observationRegistration: nil,
                readback: {
                    defer { readbackCount += 1 }
                    return readbackCount == 0
                        ? FlowTabUITestHomePermissionBoundaryProjectionTestFixture
                            .snapshot(
                                applicationRowExists: false,
                                applicationRowValue: nil
                            )
                        : FlowTabUITestHomePermissionBoundaryProjectionTestFixture
                            .snapshot(hiddenAppsValue: "2")
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestHomePermissionBoundaryProjectionTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "hiddenAppsValue=1"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "value=2"
            )
        )
    }
}
