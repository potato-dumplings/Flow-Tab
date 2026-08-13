import Foundation
import XCTest

private enum FlowTabUITestHomeAppRowProjectionTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 200
}

private enum FlowTabUITestHomeAppRowProjectionTestFixture {
    static let mailIdentifier =
        "flowtab.home.app.com-flowtab-mock-mail"
    static let browserIdentifier =
        "flowtab.home.app.com-flowtab-mock-browser"
    static let value = "0w"

    static let expectation =
        FlowTabUITestHomeAppRowProjectionExpectation(
            rows: [
                .init(identifier: mailIdentifier, value: value),
                .init(identifier: browserIdentifier, value: value)
            ]
        )

    static let foregroundExpectation =
        FlowTabUITestHomeAppRowProjectionExpectation(
            rows: expectation.rows,
            requiredApplicationState: .runningForeground
        )

    static let positionExpectation =
        FlowTabUITestHomeAppRowPositionExpectation(
            rows: [
                .init(
                    identifier: mailIdentifier,
                    frameMinY: 100,
                    accuracy: 1
                ),
                .init(
                    identifier: browserIdentifier,
                    frameMinY: 200,
                    accuracy: 1
                )
            ]
        )

    static func snapshot(
        applicationState: XCUIApplication.State? = nil,
        mailIdentifier: String =
            FlowTabUITestHomeAppRowProjectionTestFixture
                .mailIdentifier,
        mailExists: Bool = true,
        mailValue: String? =
            FlowTabUITestHomeAppRowProjectionTestFixture.value,
        mailFrameMinY: Double? = 100,
        browserIdentifier: String =
            FlowTabUITestHomeAppRowProjectionTestFixture
                .browserIdentifier,
        browserExists: Bool = true,
        browserValue: String? =
            FlowTabUITestHomeAppRowProjectionTestFixture.value,
        browserFrameMinY: Double? = 200
    ) -> FlowTabUITestHomeAppRowProjectionSnapshot {
        FlowTabUITestHomeAppRowProjectionSnapshot(
            applicationState: applicationState,
            rows: [
                .init(
                    identifier: mailIdentifier,
                    exists: mailExists,
                    value: mailValue,
                    frameMinY: mailFrameMinY
                ),
                .init(
                    identifier: browserIdentifier,
                    exists: browserExists,
                    value: browserValue,
                    frameMinY: browserFrameMinY
                )
            ]
        )
    }
}

extension FlowTabUITests {
    func testHomeInitialRowProjectionWatchdogPreservesCompatibleBound() {
        XCTAssertEqual(
            FlowTabUITestHomeInitialRowProjectionPolicy.watchdog,
            16
        )
        XCTAssertTrue(
            FlowTabUITestHomeInitialRowProjectionPolicy
                .watchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestHomeInitialRowProjectionPolicy.watchdog,
            0
        )
    }

    func testHomeAppliedRowProjectionPolicyPreservesCompatibleBound() {
        XCTAssertEqual(
            FlowTabUITestHomeAppliedRowProjectionPolicy.watchdog,
            4
        )
        XCTAssertTrue(
            FlowTabUITestHomeAppliedRowProjectionPolicy
                .watchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestHomeAppliedRowProjectionPolicy.watchdog,
            0
        )
        XCTAssertEqual(
            FlowTabUITestHomeAppliedRowProjectionPolicy
                .positionAccuracy,
            1
        )
    }

    func testHomeRuntimeOrderProjectionPolicyPreservesCumulativeBound() {
        XCTAssertEqual(
            FlowTabUITestHomeRuntimeOrderProjectionPolicy.watchdog,
            36
        )
        XCTAssertTrue(
            FlowTabUITestHomeRuntimeOrderProjectionPolicy
                .watchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestHomeRuntimeOrderProjectionPolicy.watchdog,
            0
        )
    }

    func testHomeAppRowProjectionCapturesOrderWithoutConstrainingValues() {
        let expectation = FlowTabUITestHomeAppRowProjectionExpectation(
            rows: [
                .init(
                    identifier:
                        FlowTabUITestHomeAppRowProjectionTestFixture
                            .mailIdentifier,
                    value: nil
                ),
                .init(
                    identifier:
                        FlowTabUITestHomeAppRowProjectionTestFixture
                            .browserIdentifier,
                    value: nil
                )
            ],
            frameOrder: .unconstrained
        )
        let snapshot =
            FlowTabUITestHomeAppRowProjectionTestFixture.snapshot(
                mailValue: "5w",
                mailFrameMinY: 200,
                browserValue: "1w hidden",
                browserFrameMinY: 100
            )

        XCTAssertTrue(expectation.isSatisfied(by: snapshot))
        XCTAssertEqual(
            snapshot.identifiersByAscendingFrame,
            [
                FlowTabUITestHomeAppRowProjectionTestFixture
                    .browserIdentifier,
                FlowTabUITestHomeAppRowProjectionTestFixture
                    .mailIdentifier
            ]
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by:
                    FlowTabUITestHomeAppRowProjectionTestFixture
                        .snapshot(browserExists: false)
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by:
                    FlowTabUITestHomeAppRowProjectionTestFixture
                        .snapshot(mailFrameMinY: .nan)
            )
        )
    }

    func testHomeAppRowPositionRequiresExactRowsWithinAccuracy() {
        let expectation =
            FlowTabUITestHomeAppRowProjectionTestFixture
                .positionExpectation

        XCTAssertTrue(
            expectation.isSatisfied(
                by:
                    FlowTabUITestHomeAppRowProjectionTestFixture
                        .snapshot()
            )
        )
        XCTAssertTrue(
            expectation.isSatisfied(
                by:
                    FlowTabUITestHomeAppRowProjectionTestFixture
                        .snapshot(
                            mailFrameMinY: 99,
                            browserFrameMinY: 201
                        )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by:
                    FlowTabUITestHomeAppRowProjectionTestFixture
                        .snapshot(mailFrameMinY: 98.9)
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by:
                    FlowTabUITestHomeAppRowProjectionTestFixture
                        .snapshot(
                            browserIdentifier:
                                "flowtab.home.app.com.example.other"
                        )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by:
                    FlowTabUITestHomeAppRowProjectionTestFixture
                        .snapshot(
                            browserExists: false,
                            browserFrameMinY: nil
                        )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by:
                    FlowTabUITestHomeAppRowProjectionTestFixture
                        .snapshot(mailFrameMinY: .nan)
            )
        )
    }

    func testHomeAppRowProjectionRequiresOneExactOrderedSnapshot() {
        let expectation =
            FlowTabUITestHomeAppRowProjectionTestFixture.expectation

        XCTAssertTrue(
            expectation.isSatisfied(
                by:
                    FlowTabUITestHomeAppRowProjectionTestFixture
                        .snapshot()
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by:
                    FlowTabUITestHomeAppRowProjectionTestFixture
                        .snapshot(
                            mailIdentifier:
                                "flowtab.home.app.com.example.other"
                        )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by:
                    FlowTabUITestHomeAppRowProjectionTestFixture
                        .snapshot(
                            mailExists: false,
                            mailValue: nil,
                            mailFrameMinY: nil
                        )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by:
                    FlowTabUITestHomeAppRowProjectionTestFixture
                        .snapshot(browserValue: "1w")
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by:
                    FlowTabUITestHomeAppRowProjectionTestFixture
                        .snapshot(mailFrameMinY: .nan)
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by:
                    FlowTabUITestHomeAppRowProjectionTestFixture
                        .snapshot(
                            mailFrameMinY: 200,
                            browserFrameMinY: 100
                        )
            )
        )
    }

    func testHomeAppRowProjectionRequiresExactApplicationStateWhenRequested() {
        let expectation = FlowTabUITestHomeAppRowProjectionExpectation(
            rows:
                FlowTabUITestHomeAppRowProjectionTestFixture
                    .expectation.rows,
            requiredApplicationState: .runningForeground
        )

        XCTAssertTrue(
            expectation.isSatisfied(
                by: FlowTabUITestHomeAppRowProjectionTestFixture
                    .snapshot(applicationState: .runningForeground)
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: FlowTabUITestHomeAppRowProjectionTestFixture
                    .snapshot(applicationState: .runningBackground)
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: FlowTabUITestHomeAppRowProjectionTestFixture
                    .snapshot()
            )
        )
    }

    func testHomeAppRowProjectionObserverUsesInitialExactSnapshot() {
        let owner =
            FlowTabUITestHomeAppRowProjectionObservationOwner(
                expectation:
                    FlowTabUITestHomeAppRowProjectionTestFixture
                        .expectation,
                observationRegistration: nil,
                readback: {
                    FlowTabUITestHomeAppRowProjectionTestFixture
                        .snapshot()
                }
            )
        owner.start()
        defer { owner.cancel() }

        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestHomeAppRowProjectionTestPolicy.watchdog
        )

        XCTAssertEqual(evidence?.source, .initialReadback)
        XCTAssertEqual(
            evidence?.value,
            FlowTabUITestHomeAppRowProjectionTestFixture.snapshot()
        )
    }

    func testHomeAppRowProjectionObserverUsesPreinstalledScheduledReadback() {
        var snapshot =
            FlowTabUITestHomeAppRowProjectionTestFixture.snapshot(
                mailExists: false,
                mailValue: nil,
                mailFrameMinY: nil,
                browserExists: false,
                browserValue: nil,
                browserFrameMinY: nil
            )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestHomeAppRowProjectionObservationOwner(
                expectation:
                    FlowTabUITestHomeAppRowProjectionTestFixture
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
            FlowTabUITestHomeAppRowProjectionTestFixture.snapshot()
        scheduledReadback?(.scheduledReadback)
        scheduledReadback?(.notificationReadback)

        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestHomeAppRowProjectionTestPolicy.watchdog
        )
        XCTAssertEqual(evidence?.source, .scheduledReadback)
        XCTAssertEqual(evidence?.value, snapshot)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testHomeAppRowProjectionObserverRequiresTriggerAcceptance() {
        var acceptsEvidence = false
        let snapshot =
            FlowTabUITestHomeAppRowProjectionTestFixture.snapshot()
        let owner =
            FlowTabUITestHomeAppRowProjectionObservationOwner(
                expectation:
                    FlowTabUITestHomeAppRowProjectionTestFixture
                        .expectation,
                acceptsEvidence: {
                    acceptsEvidence
                },
                observationRegistration: nil,
                readback: { snapshot }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "acceptanceEnabled=false"
            )
        )

        acceptsEvidence = true
        owner.requestReadback(source: .triggerReadback)

        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestHomeAppRowProjectionTestPolicy.watchdog
        )
        XCTAssertEqual(evidence?.source, .triggerReadback)
        XCTAssertEqual(evidence?.value, snapshot)
    }

    func testHomeAppRowProjectionObserverRequiresAdditionalSnapshotEvidence() {
        var acceptsEvidence = false
        var snapshot =
            FlowTabUITestHomeAppRowProjectionTestFixture.snapshot(
                mailFrameMinY: 110
            )
        let positionExpectation =
            FlowTabUITestHomeAppRowProjectionTestFixture
                .positionExpectation
        let owner =
            FlowTabUITestHomeAppRowProjectionObservationOwner(
                expectation:
                    FlowTabUITestHomeAppRowProjectionTestFixture
                        .expectation,
                acceptsEvidence: {
                    acceptsEvidence
                },
                acceptsSnapshot: {
                    positionExpectation.isSatisfied(by: $0)
                },
                snapshotExpectationDescription: {
                    positionExpectation.diagnosticSummary
                },
                observationRegistration: nil,
                readback: { snapshot }
            )
        owner.start()
        defer { owner.cancel() }

        acceptsEvidence = true
        owner.requestReadback(source: .triggerReadback)

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "snapshotExpected{identifier="
                    + FlowTabUITestHomeAppRowProjectionTestFixture
                        .mailIdentifier
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("frameMinY=110.0")
        )

        snapshot =
            FlowTabUITestHomeAppRowProjectionTestFixture.snapshot()
        owner.requestReadback(source: .triggerReadback)

        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestHomeAppRowProjectionTestPolicy.watchdog
        )
        XCTAssertEqual(evidence?.source, .triggerReadback)
        XCTAssertEqual(evidence?.value, snapshot)
    }

    func testHomeAppRowProjectionSlowSchedulingOnlyDelaysExactForegroundSnapshot() {
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var snapshot =
            FlowTabUITestHomeAppRowProjectionTestFixture.snapshot(
                applicationState: .runningBackground
            )
        let owner =
            FlowTabUITestHomeAppRowProjectionObservationOwner(
                expectation:
                    FlowTabUITestHomeAppRowProjectionTestFixture
                        .foregroundExpectation,
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(owner.resolvedEvidence)
        snapshot =
            FlowTabUITestHomeAppRowProjectionTestFixture.snapshot(
                applicationState: .runningForeground,
                browserValue: "1w"
            )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot =
            FlowTabUITestHomeAppRowProjectionTestFixture.snapshot(
                applicationState: .runningForeground
            )
        scheduledReadback?(.scheduledReadback)

        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestHomeAppRowProjectionTestPolicy.watchdog
        )
        XCTAssertEqual(evidence?.source, .scheduledReadback)
        XCTAssertEqual(evidence?.value, snapshot)
    }

    func testHomeAppRowProjectionObserverIgnoresEventsAfterCancellation() {
        var snapshot =
            FlowTabUITestHomeAppRowProjectionTestFixture.snapshot(
                mailExists: false,
                mailValue: nil,
                mailFrameMinY: nil
            )
        var eventHandler:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestHomeAppRowProjectionObservationOwner(
                expectation:
                    FlowTabUITestHomeAppRowProjectionTestFixture
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
            FlowTabUITestHomeAppRowProjectionTestFixture.snapshot()
        eventHandler?(.notificationReadback)

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testHomeAppRowProjectionWatchdogReportsFinalSnapshot() {
        var readbackCount = 0
        let owner =
            FlowTabUITestHomeAppRowProjectionObservationOwner(
                expectation:
                    FlowTabUITestHomeAppRowProjectionTestFixture
                        .expectation,
                observationRegistration: nil,
                readback: {
                    defer { readbackCount += 1 }
                    return readbackCount == 0
                        ? FlowTabUITestHomeAppRowProjectionTestFixture
                            .snapshot(
                                mailExists: false,
                                mailValue: nil,
                                mailFrameMinY: nil
                            )
                        : FlowTabUITestHomeAppRowProjectionTestFixture
                            .snapshot(browserValue: "1w")
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestHomeAppRowProjectionTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("value=0w")
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("value=1w")
        )
    }

    func testHomeAppRowProjectionRejectsReplacedReadbacksUnderPressure() {
        for _ in 0..<FlowTabUITestHomeAppRowProjectionTestPolicy
            .pressureIterations
        {
            var snapshot =
                FlowTabUITestHomeAppRowProjectionTestFixture.snapshot(
                    applicationState: .runningBackground,
                    mailExists: false,
                    mailValue: nil,
                    mailFrameMinY: nil
                )
            var scheduledReadbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            var cancellationCount = 0
            let owner =
                FlowTabUITestHomeAppRowProjectionObservationOwner(
                    expectation:
                        FlowTabUITestHomeAppRowProjectionTestFixture
                            .foregroundExpectation,
                    observationRegistration: { callback in
                        scheduledReadbacks.append(callback)
                        return FlowTabUITestObservationCancellation {
                            cancellationCount += 1
                        }
                    },
                    readback: { snapshot }
                )

            owner.start()
            XCTAssertEqual(scheduledReadbacks.count, 1)
            let staleReadback = scheduledReadbacks[0]

            owner.cancel()
            owner.start()
            XCTAssertEqual(scheduledReadbacks.count, 2)
            let currentReadback = scheduledReadbacks[1]

            snapshot =
                FlowTabUITestHomeAppRowProjectionTestFixture.snapshot(
                    applicationState: .runningForeground
                )
            staleReadback(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
            currentReadback(.scheduledReadback)
            XCTAssertEqual(owner.resolvedEvidence?.generation, 2)
            XCTAssertEqual(
                owner.resolvedEvidence?.source,
                .scheduledReadback
            )
            XCTAssertEqual(cancellationCount, 2)
            owner.cancel()
        }
    }
}
