import Foundation
import XCTest

private enum FlowTabUITestHomeFilteredAppProjectionTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 200
}

private enum FlowTabUITestHomeFilteredAppProjectionTestFixture {
    static let visible = ["host", "ordinary"]
    static let excluded = ["nested", "deeper"]
    static let expectation =
        FlowTabUITestHomeFilteredAppProjectionExpectation(
            visibleIdentifiers: visible,
            excludedIdentifiers: excluded
        )

    static func snapshot(
        state: XCUIApplication.State = .runningForeground,
        countBefore: String? = "2 apps",
        visibleIdentifiers: [String] = visible,
        nestedExists: Bool = false,
        deeperExists: Bool = false,
        countAfter: String? = "2 apps"
    ) -> FlowTabUITestHomeFilteredAppProjectionSnapshot {
        .init(
            applicationState: state,
            appCountLabelBeforeRows: countBefore,
            visibleRowIdentifiers: visibleIdentifiers,
            excludedRows: [
                .init(identifier: excluded[0], exists: nestedExists),
                .init(identifier: excluded[1], exists: deeperExists)
            ],
            appCountLabelAfterRows: countAfter
        )
    }
}

extension FlowTabUITests {
    func testHomeNestedTopologyFilteredAppProjectionPolicy() {
        let policy =
            FlowTabUITestHomeNestedTopologyFilteredAppProjectionPolicy.self
        XCTAssertEqual(policy.watchdog, 2)
        XCTAssertTrue(policy.watchdog.isFinite)
        XCTAssertGreaterThan(policy.watchdog, 0)
        XCTAssertEqual(
            policy.visibleIdentifiers,
            [Identifier.homeAppWeChat, Identifier.homeAppTopLevelZeroWindow]
        )
        XCTAssertEqual(
            policy.excludedIdentifiers,
            [
                Identifier.homeAppNestedWeChatAppEx,
                Identifier.homeAppNestedMiniProgram
            ]
        )
        XCTAssertTrue(
            FlowTabUITestHomeFilteredAppProjectionExpectation(
                visibleIdentifiers: policy.visibleIdentifiers,
                excludedIdentifiers: policy.excludedIdentifiers
            ).isWellFormed
        )
    }

    func testHomeFilteredAppProjectionParsesLocalizedCountEvidence() {
        XCTAssertEqual(
            FlowTabUITestHomeFilteredAppProjectionSnapshot.appCount(
                from: "2 apps"
            ),
            2
        )
        XCTAssertEqual(
            FlowTabUITestHomeFilteredAppProjectionSnapshot.appCount(
                from: "2 个应用"
            ),
            2
        )
        XCTAssertEqual(
            FlowTabUITestHomeFilteredAppProjectionSnapshot.appCount(
                from: "12 apps"
            ),
            12
        )
        XCTAssertNil(
            FlowTabUITestHomeFilteredAppProjectionSnapshot.appCount(
                from: "apps"
            )
        )
        XCTAssertNil(
            FlowTabUITestHomeFilteredAppProjectionSnapshot.appCount(
                from: "2 of 3 apps"
            )
        )
    }

    func testHomeFilteredAppProjectionRequiresOneCompleteSnapshot() {
        let expectation =
            FlowTabUITestHomeFilteredAppProjectionTestFixture.expectation
        XCTAssertTrue(
            expectation.isSatisfied(
                by: FlowTabUITestHomeFilteredAppProjectionTestFixture
                    .snapshot()
            )
        )
        XCTAssertTrue(
            expectation.isSatisfied(
                by: FlowTabUITestHomeFilteredAppProjectionTestFixture
                    .snapshot(visibleIdentifiers: ["ordinary", "host"])
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: FlowTabUITestHomeFilteredAppProjectionTestFixture
                    .snapshot(state: .runningBackground)
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: FlowTabUITestHomeFilteredAppProjectionTestFixture
                    .snapshot(countBefore: "3 apps")
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: FlowTabUITestHomeFilteredAppProjectionTestFixture
                    .snapshot(countAfter: "3 apps")
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: FlowTabUITestHomeFilteredAppProjectionTestFixture
                    .snapshot(visibleIdentifiers: ["host"])
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: FlowTabUITestHomeFilteredAppProjectionTestFixture
                    .snapshot(visibleIdentifiers: ["host", "host"])
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: FlowTabUITestHomeFilteredAppProjectionTestFixture
                    .snapshot(
                        visibleIdentifiers: ["host", "ordinary", "nested"]
                    )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: FlowTabUITestHomeFilteredAppProjectionTestFixture
                    .snapshot(nestedExists: true)
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: FlowTabUITestHomeFilteredAppProjectionTestFixture
                    .snapshot(deeperExists: true)
            )
        )
    }

    func testHomeFilteredAppProjectionRequiresPostTriggerEvidence() {
        var registrationCount = 0
        let owner = FlowTabUITestHomeFilteredAppProjectionObservationOwner(
            expectation:
                FlowTabUITestHomeFilteredAppProjectionTestFixture
                    .expectation,
            scheduledRegistration: { _ in
                registrationCount += 1
                return FlowTabUITestObservationCancellation {}
            },
            readback: {
                FlowTabUITestHomeFilteredAppProjectionTestFixture.snapshot()
            }
        )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(owner.latestEvidence?.source, .initialReadback)
        owner.markSelectedHostProjectionCompleted()

        XCTAssertEqual(owner.resolvedEvidence?.source, .triggerReadback)
        XCTAssertEqual(registrationCount, 0)
    }

    func testHomeFilteredAppProjectionUsesDelayedScheduledEvidence() {
        var snapshot =
            FlowTabUITestHomeFilteredAppProjectionTestFixture.snapshot(
                countAfter: "3 apps"
            )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner = FlowTabUITestHomeFilteredAppProjectionObservationOwner(
            expectation:
                FlowTabUITestHomeFilteredAppProjectionTestFixture
                    .expectation,
            scheduledRegistration: { callback in
                scheduledReadback = callback
                return FlowTabUITestObservationCancellation {
                    cancellationCount += 1
                }
            },
            readback: { snapshot }
        )
        owner.start()
        defer { owner.cancel() }
        owner.markSelectedHostProjectionCompleted()

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertNotNil(scheduledReadback)
        snapshot =
            FlowTabUITestHomeFilteredAppProjectionTestFixture.snapshot()
        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(owner.resolvedEvidence?.source, .scheduledReadback)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testHomeFilteredAppProjectionSlowSchedulingOnlyDelaysResolution() {
        var snapshot =
            FlowTabUITestHomeFilteredAppProjectionTestFixture.snapshot(
                visibleIdentifiers: ["host"]
            )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let owner = FlowTabUITestHomeFilteredAppProjectionObservationOwner(
            expectation:
                FlowTabUITestHomeFilteredAppProjectionTestFixture
                    .expectation,
            scheduledRegistration: { callback in
                scheduledReadback = callback
                return FlowTabUITestObservationCancellation {}
            },
            readback: { snapshot }
        )
        owner.start()
        defer { owner.cancel() }
        owner.markSelectedHostProjectionCompleted()

        snapshot =
            FlowTabUITestHomeFilteredAppProjectionTestFixture.snapshot()
        XCTAssertNil(owner.resolvedEvidence)
        scheduledReadback?(.scheduledReadback)
        XCTAssertEqual(
            owner.resolvedEvidence?.value.visibleRowIdentifiers,
            ["host", "ordinary"]
        )
    }

    func testHomeFilteredAppProjectionCancellationRejectsLateEvidence() {
        var snapshot =
            FlowTabUITestHomeFilteredAppProjectionTestFixture.snapshot(
                nestedExists: true
            )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner = FlowTabUITestHomeFilteredAppProjectionObservationOwner(
            expectation:
                FlowTabUITestHomeFilteredAppProjectionTestFixture
                    .expectation,
            scheduledRegistration: { callback in
                scheduledReadback = callback
                return FlowTabUITestObservationCancellation {
                    cancellationCount += 1
                }
            },
            readback: { snapshot }
        )
        owner.start()
        owner.markSelectedHostProjectionCompleted()
        owner.cancel()

        snapshot =
            FlowTabUITestHomeFilteredAppProjectionTestFixture.snapshot()
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testHomeFilteredAppProjectionWatchdogReportsFinalReadback() {
        var readbackCount = 0
        let owner = FlowTabUITestHomeFilteredAppProjectionObservationOwner(
            expectation:
                FlowTabUITestHomeFilteredAppProjectionTestFixture
                    .expectation,
            scheduledRegistration: { _ in
                FlowTabUITestObservationCancellation {}
            },
            readback: {
                defer { readbackCount += 1 }
                return FlowTabUITestHomeFilteredAppProjectionTestFixture
                    .snapshot(
                        nestedExists: true,
                        countAfter: readbackCount >= 2
                            ? "3 apps"
                            : "2 apps"
                    )
            }
        )
        owner.start()
        defer { owner.cancel() }
        owner.markSelectedHostProjectionCompleted()

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestHomeFilteredAppProjectionTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("source=watchdogReadback")
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "countAfter=Optional(\"3 apps\")"
            )
        )
        XCTAssertTrue(owner.diagnosticSummary.contains("nested=1"))
        XCTAssertTrue(owner.diagnosticSummary.contains("waitResult="))
    }

    func testHomeFilteredAppProjectionRejectsReplacedReadbacksUnderPressure() {
        for _ in 0..<FlowTabUITestHomeFilteredAppProjectionTestPolicy
            .pressureIterations
        {
            var snapshot =
                FlowTabUITestHomeFilteredAppProjectionTestFixture.snapshot(
                    nestedExists: true
                )
            var scheduledReadbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            let owner =
                FlowTabUITestHomeFilteredAppProjectionObservationOwner(
                    expectation:
                        FlowTabUITestHomeFilteredAppProjectionTestFixture
                            .expectation,
                    scheduledRegistration: { callback in
                        scheduledReadbacks.append(callback)
                        return FlowTabUITestObservationCancellation {}
                    },
                    readback: { snapshot }
                )

            owner.start()
            owner.markSelectedHostProjectionCompleted()
            XCTAssertEqual(scheduledReadbacks.count, 1)
            let staleReadback = scheduledReadbacks[0]

            owner.cancel()
            owner.start()
            owner.markSelectedHostProjectionCompleted()
            XCTAssertEqual(scheduledReadbacks.count, 2)
            let currentReadback = scheduledReadbacks[1]

            snapshot =
                FlowTabUITestHomeFilteredAppProjectionTestFixture.snapshot()
            staleReadback(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
            currentReadback(.scheduledReadback)
            XCTAssertEqual(owner.resolvedEvidence?.generation, 2)
            owner.cancel()
        }
    }
}
