import Foundation
import XCTest

private enum FlowTabUITestElementCollectionExistenceTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 200
}

extension FlowTabUITests {
    func testEnglishSearchProjectionPolicyUsesNamedWatchdog() {
        let watchdog =
            FlowTabUITestEnglishSearchProjectionPolicy
                .projectionWatchdog
        XCTAssertEqual(watchdog, 10)
        XCTAssertTrue(watchdog.isFinite)
        XCTAssertGreaterThan(watchdog, 0)
    }

    func testElementCollectionExistenceSnapshotRequiresExactCompleteProjection() {
        XCTAssertTrue(
            elementCollectionExistenceSnapshot(
                elements: [
                    .init(identifier: "first", exists: true),
                    .init(identifier: "second", exists: true)
                ]
            ).isCompleteProjection
        )
        XCTAssertFalse(
            elementCollectionExistenceSnapshot(
                expectedIdentifiers: [],
                elements: []
            ).isCompleteProjection
        )
        XCTAssertFalse(
            elementCollectionExistenceSnapshot(
                elements: [
                    .init(identifier: "first", exists: true),
                    .init(identifier: "second", exists: false)
                ]
            ).isCompleteProjection
        )
        XCTAssertFalse(
            elementCollectionExistenceSnapshot(
                elements: [
                    .init(identifier: "second", exists: true),
                    .init(identifier: "first", exists: true)
                ]
            ).isCompleteProjection
        )
        XCTAssertFalse(
            elementCollectionExistenceSnapshot(
                elements: [
                    .init(identifier: "first", exists: true)
                ]
            ).isCompleteProjection
        )
    }

    func testElementCollectionExistenceRequiresPostTriggerReadback() {
        var scheduledRegistrationCount = 0
        let owner =
            FlowTabUITestElementCollectionExistenceObservationOwner(
                expectedIdentifiers: ["first", "second"],
                scheduledRegistration: { _ in
                    scheduledRegistrationCount += 1
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    self.completeElementCollectionExistenceReadback()
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(owner.latestEvidence?.source, .initialReadback)

        owner.markTriggerCompleted()
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestElementCollectionExistenceTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .triggerReadback)
        XCTAssertEqual(evidence?.value.isCompleteProjection, true)
        XCTAssertEqual(scheduledRegistrationCount, 0)
    }

    func testElementCollectionExistenceUsesDelayedScheduledEvidence() {
        var elements = incompleteElementCollectionExistenceReadback()
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestElementCollectionExistenceObservationOwner(
                expectedIdentifiers: ["first", "second"],
                scheduledRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: { elements }
            )
        owner.start()
        defer { owner.cancel() }

        owner.markTriggerCompleted()
        XCTAssertNotNil(scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        elements = completeElementCollectionExistenceReadback()
        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(owner.resolvedEvidence?.source, .scheduledReadback)
        XCTAssertEqual(
            owner.resolvedEvidence?.value.elements,
            completeElementCollectionExistenceReadback()
        )
        XCTAssertEqual(cancellationCount, 1)
    }

    func testElementCollectionExistenceSlowSchedulingOnlyDelaysResolution() {
        var elements = incompleteElementCollectionExistenceReadback()
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        let owner =
            FlowTabUITestElementCollectionExistenceObservationOwner(
                expectedIdentifiers: ["first", "second"],
                scheduledRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { elements }
            )
        owner.start()
        defer { owner.cancel() }
        owner.markTriggerCompleted()

        elements = completeElementCollectionExistenceReadback()
        XCTAssertNil(owner.resolvedEvidence)

        scheduledReadback?(.scheduledReadback)
        XCTAssertEqual(
            owner.resolvedEvidence?.value.elements,
            completeElementCollectionExistenceReadback()
        )
        XCTAssertEqual(owner.resolvedEvidence?.source, .scheduledReadback)
    }

    func testElementCollectionExistenceCancellationRejectsLateReadback() {
        var elements = incompleteElementCollectionExistenceReadback()
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestElementCollectionExistenceObservationOwner(
                expectedIdentifiers: ["first", "second"],
                scheduledRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: { elements }
            )
        owner.start()
        owner.markTriggerCompleted()
        owner.cancel()

        elements = completeElementCollectionExistenceReadback()
        scheduledReadback?(.scheduledReadback)

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testElementCollectionExistenceWatchdogReportsFinalReadback() {
        var readbackCount = 0
        let owner =
            FlowTabUITestElementCollectionExistenceObservationOwner(
                expectedIdentifiers: ["first", "second"],
                scheduledRegistration: { _ in
                    FlowTabUITestObservationCancellation {}
                },
                readback: {
                    defer { readbackCount += 1 }
                    if readbackCount >= 2 {
                        return self.completeElementCollectionExistenceReadback()
                    }
                    return self.incompleteElementCollectionExistenceReadback()
                }
            )
        owner.start()
        defer { owner.cancel() }
        owner.markTriggerCompleted()

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestElementCollectionExistenceTestPolicy
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
                "observed=[first=1,second=1]"
            )
        )
        XCTAssertTrue(owner.diagnosticSummary.contains("waitResult="))
    }

    func testElementCollectionExistenceRejectsReplacedReadbacksUnderPressure() {
        for _ in 0..<FlowTabUITestElementCollectionExistenceTestPolicy
            .pressureIterations
        {
            var elements = incompleteElementCollectionExistenceReadback()
            var scheduledReadbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            let owner =
                FlowTabUITestElementCollectionExistenceObservationOwner(
                    expectedIdentifiers: ["first", "second"],
                    scheduledRegistration: { callback in
                        scheduledReadbacks.append(callback)
                        return FlowTabUITestObservationCancellation {}
                    },
                    readback: { elements }
                )

            owner.start()
            owner.markTriggerCompleted()
            owner.markTriggerCompleted()
            XCTAssertEqual(scheduledReadbacks.count, 1)
            let staleReadback = scheduledReadbacks[0]

            owner.cancel()
            owner.start()
            owner.markTriggerCompleted()
            XCTAssertEqual(scheduledReadbacks.count, 2)
            let currentReadback = scheduledReadbacks[1]

            elements = completeElementCollectionExistenceReadback()
            staleReadback(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
            currentReadback(.scheduledReadback)
            XCTAssertEqual(owner.resolvedEvidence?.generation, 2)
            XCTAssertEqual(
                owner.resolvedEvidence?.source,
                .scheduledReadback
            )
            owner.cancel()
        }
    }

    private func elementCollectionExistenceSnapshot(
        expectedIdentifiers: [String] = ["first", "second"],
        elements: [FlowTabUITestElementExistenceReadback]
    ) -> FlowTabUITestElementCollectionExistenceSnapshot {
        FlowTabUITestElementCollectionExistenceSnapshot(
            expectedIdentifiers: expectedIdentifiers,
            elements: elements
        )
    }

    private func completeElementCollectionExistenceReadback()
        -> [FlowTabUITestElementExistenceReadback]
    {
        [
            .init(identifier: "first", exists: true),
            .init(identifier: "second", exists: true)
        ]
    }

    private func incompleteElementCollectionExistenceReadback()
        -> [FlowTabUITestElementExistenceReadback]
    {
        [
            .init(identifier: "first", exists: true),
            .init(identifier: "second", exists: false)
        ]
    }
}
