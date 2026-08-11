import XCTest

private enum FlowTabUITestElementExistenceObservationTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 200
}

extension FlowTabUITests {
    func testElementExistenceObservationRequiresPostTriggerReadback() {
        var scheduledRegistrationCount = 0
        let owner =
            FlowTabUITestElementExistenceObservationOwner(
                elementIdentifier: "target",
                scheduledRegistration: { _ in
                    scheduledRegistrationCount += 1
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { true }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(owner.latestEvidence?.source, .initialReadback)

        owner.markTriggerCompleted()
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestElementExistenceObservationTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .triggerReadback)
        XCTAssertEqual(evidence?.value.exists, true)
        XCTAssertEqual(scheduledRegistrationCount, 0)
    }

    func testElementExistenceObservationUsesDelayedScheduledEvidence() {
        var exists = false
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestElementExistenceObservationOwner(
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

        owner.markTriggerCompleted()
        XCTAssertNotNil(scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        exists = true
        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .scheduledReadback
        )
        XCTAssertEqual(owner.resolvedEvidence?.value.exists, true)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testElementExistenceObservationCancellationRejectsLateReadback() {
        var exists = false
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestElementExistenceObservationOwner(
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

        exists = true
        scheduledReadback?(.scheduledReadback)

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testElementExistenceObservationWatchdogReportsFinalReadback() {
        var readbackCount = 0
        let owner =
            FlowTabUITestElementExistenceObservationOwner(
                elementIdentifier: "target",
                scheduledRegistration: { _ in
                    FlowTabUITestObservationCancellation {}
                },
                readback: {
                    defer { readbackCount += 1 }
                    return readbackCount >= 2
                }
            )
        owner.start()
        defer { owner.cancel() }
        owner.markTriggerCompleted()

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestElementExistenceObservationTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(owner.diagnosticSummary.contains("exists=1"))
        XCTAssertTrue(owner.diagnosticSummary.contains("waitResult="))
    }

    func testElementExistenceObservationRejectsReplacedReadbacksUnderPressure() {
        for _ in 0..<FlowTabUITestElementExistenceObservationTestPolicy
            .pressureIterations
        {
            var exists = false
            var scheduledReadbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            let owner =
                FlowTabUITestElementExistenceObservationOwner(
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

            exists = true
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
