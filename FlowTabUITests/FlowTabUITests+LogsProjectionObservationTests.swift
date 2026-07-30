import Foundation
import XCTest

private enum FlowTabUITestLogsProjectionTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testLogsProjectionObserverRequiresPostTriggerExactRows() {
        let expectation =
            FlowTabUITestLogsProjectionExpectation(
                visibleIdentifiers: ["info", "warn"],
                hiddenIdentifiers: ["debug"]
            )
        let matchingSnapshot =
            FlowTabUITestLogsProjectionSnapshot(
                tabContentExists: true,
                linesContainerExists: true,
                rowIdentifiers: ["info", "warn"]
            )
        var acceptsResolution = false
        var snapshot = matchingSnapshot
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestLogsProjectionObservationOwner(
                expectation: expectation,
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                acceptsResolution: { acceptsResolution },
                readback: { snapshot }
            )
        owner.start()

        XCTAssertNil(owner.resolvedEvidence)
        acceptsResolution = true
        snapshot = FlowTabUITestLogsProjectionSnapshot(
            tabContentExists: true,
            linesContainerExists: true,
            rowIdentifiers: ["info"]
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = FlowTabUITestLogsProjectionSnapshot(
            tabContentExists: true,
            linesContainerExists: true,
            rowIdentifiers: ["info", "debug"]
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = FlowTabUITestLogsProjectionSnapshot(
            tabContentExists: true,
            linesContainerExists: true,
            rowIdentifiers: ["info", "info"]
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = matchingSnapshot
        scheduledReadback?(.scheduledReadback)
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestLogsProjectionTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .scheduledReadback)
        XCTAssertEqual(evidence?.value, matchingSnapshot)
        XCTAssertEqual(cancellationCount, 1)
        owner.cancel()
    }

    func testLogsProjectionObserverLifecycleUnderPressure() {
        let expectation =
            FlowTabUITestLogsProjectionExpectation(
                visibleIdentifiers: ["error"],
                hiddenIdentifiers: ["debug", "info", "warn"]
            )
        let matchingSnapshot =
            FlowTabUITestLogsProjectionSnapshot(
                tabContentExists: true,
                linesContainerExists: true,
                rowIdentifiers: ["error"]
            )

        for iteration in
            0..<FlowTabUITestLogsProjectionTestPolicy
                .pressureIterations
        {
            let resolvesInitially = iteration.isMultiple(of: 2)
            var snapshot = resolvesInitially
                ? matchingSnapshot
                : FlowTabUITestLogsProjectionSnapshot(
                    tabContentExists: true,
                    linesContainerExists: false,
                    rowIdentifiers: []
                )
            var scheduledReadback:
                ((FlowTabUITestConditionObservationSource) -> Void)?
            var cancellationCount = 0
            var readbackCount = 0
            let owner =
                FlowTabUITestLogsProjectionObservationOwner(
                    expectation: expectation,
                    observationRegistration: { callback in
                        scheduledReadback = callback
                        return FlowTabUITestObservationCancellation {
                            cancellationCount += 1
                        }
                    },
                    readback: {
                        readbackCount += 1
                        return snapshot
                    }
                )
            owner.start()

            if !resolvesInitially {
                XCTAssertNil(owner.resolvedEvidence)
                snapshot = matchingSnapshot
                scheduledReadback?(.scheduledReadback)
            }
            let evidence = owner.waitForResolution(
                timeout:
                    FlowTabUITestLogsProjectionTestPolicy
                        .watchdog
            )
            let resolvedReadbackCount = readbackCount
            scheduledReadback?(.scheduledReadback)

            XCTAssertEqual(
                evidence?.value,
                matchingSnapshot,
                "iteration=\(iteration)"
            )
            XCTAssertEqual(readbackCount, resolvedReadbackCount)
            XCTAssertEqual(cancellationCount, 1)
            owner.cancel()
        }

        var cancelledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancelledReadbackCount = 0
        let cancelledOwner =
            FlowTabUITestLogsProjectionObservationOwner(
                expectation: expectation,
                observationRegistration: { callback in
                    cancelledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    cancelledReadbackCount += 1
                    return FlowTabUITestLogsProjectionSnapshot(
                        tabContentExists: false,
                        linesContainerExists: false,
                        rowIdentifiers: []
                    )
                }
            )
        cancelledOwner.start()
        cancelledOwner.cancel()
        cancelledReadback?(.scheduledReadback)
        XCTAssertEqual(cancelledReadbackCount, 1)

        let watchdogOwner =
            FlowTabUITestLogsProjectionObservationOwner(
                expectation: expectation,
                observationRegistration: nil,
                readback: {
                    FlowTabUITestLogsProjectionSnapshot(
                        tabContentExists: true,
                        linesContainerExists: false,
                        rowIdentifiers: ["debug"]
                    )
                }
            )
        watchdogOwner.start()
        XCTAssertNil(
            watchdogOwner.waitForResolution(
                timeout:
                    FlowTabUITestLogsProjectionTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            watchdogOwner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(
            watchdogOwner.diagnosticSummary.contains(
                "debug"
            )
        )
        watchdogOwner.cancel()
    }
}
