import Foundation
import XCTest

private enum FlowTabUITestLogsProjectionTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testLogsProjectionWatchdogsRemainTerminalBounds() {
        XCTAssertEqual(
            FlowTabUITestLogsProjectionPolicy
                .tabNavigationWatchdog,
            5
        )
        XCTAssertEqual(
            FlowTabUITestLogsProjectionPolicy
                .exactProjectionWatchdog,
            8
        )
        XCTAssertTrue(
            FlowTabUITestLogsProjectionPolicy
                .tabNavigationWatchdog.isFinite
        )
        XCTAssertTrue(
            FlowTabUITestLogsProjectionPolicy
                .exactProjectionWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestLogsProjectionPolicy
                .tabNavigationWatchdog,
            0
        )
        XCTAssertGreaterThanOrEqual(
            FlowTabUITestLogsProjectionPolicy
                .exactProjectionWatchdog,
            FlowTabUITestLogsProjectionPolicy
                .tabNavigationWatchdog
        )
    }

    func testLogsProjectionObserverRequiresPostTriggerExactRows() {
        let expectation =
            FlowTabUITestLogsProjectionExpectation(
                visibleIdentifiers: ["info", "warn"],
                hiddenIdentifiers: ["debug"],
                selectedLevel: "WARN"
            )
        let matchingSnapshot =
            FlowTabUITestLogsProjectionSnapshot(
                tabContentExists: true,
                linesContainerExists: true,
                rowIdentifiers: ["info", "warn"],
                selectedLevel: "WARN"
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
            rowIdentifiers: ["info"],
            selectedLevel: "WARN"
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = FlowTabUITestLogsProjectionSnapshot(
            tabContentExists: true,
            linesContainerExists: true,
            rowIdentifiers: ["info", "debug"],
            selectedLevel: "WARN"
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = FlowTabUITestLogsProjectionSnapshot(
            tabContentExists: true,
            linesContainerExists: true,
            rowIdentifiers: ["info", "info"],
            selectedLevel: "WARN"
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = FlowTabUITestLogsProjectionSnapshot(
            tabContentExists: true,
            linesContainerExists: true,
            rowIdentifiers: ["info", "warn"],
            selectedLevel: "DEBUG"
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
                hiddenIdentifiers: ["debug", "info", "warn"],
                selectedLevel: "ERROR"
            )
        let matchingSnapshot =
            FlowTabUITestLogsProjectionSnapshot(
                tabContentExists: true,
                linesContainerExists: true,
                rowIdentifiers: ["error"],
                selectedLevel: "ERROR"
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
                    rowIdentifiers: [],
                    selectedLevel: "DEBUG"
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
                        rowIdentifiers: [],
                        selectedLevel: nil
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
                        rowIdentifiers: ["debug"],
                        selectedLevel: "DEBUG"
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
