import XCTest

private enum FlowTabUITestElementNonExistenceObservationTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 200
}

extension FlowTabUITests {
    func testElementNonExistenceObservationRequiresPostTriggerReadback() {
        var scheduledRegistrationCount = 0
        let owner =
            FlowTabUITestElementNonExistenceObservationOwner(
                elementIdentifier: "target",
                scheduledRegistration: { _ in
                    scheduledRegistrationCount += 1
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { false }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(
            owner.latestEvidence?.source,
            .initialReadback
        )

        owner.markTriggerCompleted()
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestElementNonExistenceObservationTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .triggerReadback)
        XCTAssertEqual(evidence?.value.exists, false)
        XCTAssertEqual(scheduledRegistrationCount, 0)
    }

    func testElementNonExistenceObservationUsesDelayedScheduledEvidence() {
        var exists = true
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestElementNonExistenceObservationOwner(
                elementIdentifier: "target",
                scheduledRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: { exists }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(scheduledReadback)
        owner.markTriggerCompleted()
        XCTAssertNotNil(scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        exists = false
        scheduledReadback?(.scheduledReadback)
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestElementNonExistenceObservationTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .scheduledReadback)
        XCTAssertEqual(evidence?.value.exists, false)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testElementNonExistenceObservationCancellationRejectsLateReadback() {
        var exists = true
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestElementNonExistenceObservationOwner(
                elementIdentifier: "target",
                scheduledRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: { exists }
            )
        owner.start()
        owner.markTriggerCompleted()
        owner.cancel()

        exists = false
        scheduledReadback?(.scheduledReadback)

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testElementNonExistenceObservationWatchdogReportsFinalReadback() {
        var readbackCount = 0
        let owner =
            FlowTabUITestElementNonExistenceObservationOwner(
                elementIdentifier: "target",
                scheduledRegistration: { _ in
                    FlowTabUITestObservationCancellation {}
                },
                readback: {
                    defer { readbackCount += 1 }
                    return readbackCount < 2
                }
            )
        owner.start()
        defer { owner.cancel() }
        owner.markTriggerCompleted()

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestElementNonExistenceObservationTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("exists=0")
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("waitResult=")
        )
    }

    func testElementNonExistenceObservationRejectsReplacedReadbacksUnderPressure() {
        for _ in 0..<FlowTabUITestElementNonExistenceObservationTestPolicy
            .pressureIterations
        {
            var exists = true
            var scheduledReadbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            let owner =
                FlowTabUITestElementNonExistenceObservationOwner(
                    elementIdentifier: "target",
                    scheduledRegistration: { callback in
                        scheduledReadbacks.append(callback)
                        return FlowTabUITestObservationCancellation {}
                    },
                    readback: { exists }
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

            exists = false
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
}
