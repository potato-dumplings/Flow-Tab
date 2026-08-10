import Foundation
import XCTest

private enum FlowTabUITestLogsClearProjectionTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testLogsClearProjectionExpectationRequiresAtomicState() {
        XCTAssertEqual(
            FlowTabUITestLogsClearProjectionObservationPolicy
                .projectionWatchdog,
            5
        )
        XCTAssertTrue(
            FlowTabUITestLogsClearProjectionObservationPolicy
                .projectionWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestLogsClearProjectionObservationPolicy
                .projectionWatchdog,
            0
        )

        let populatedExpectation =
            FlowTabUITestLogsClearProjectionExpectation.populated(
                selectedLevel: "WARN",
                visibleIdentifiers: ["warn", "error"]
            )
        let clearedExpectation =
            FlowTabUITestLogsClearProjectionExpectation.cleared(
                selectedLevel: "WARN"
            )
        let populated = logsClearProjectionTestSnapshot(
            isCleared: false,
            rowIdentifiers: ["warn", "error"]
        )
        let cleared = logsClearProjectionTestSnapshot(
            isCleared: true
        )

        XCTAssertTrue(
            populatedExpectation.isSatisfied(by: populated)
        )
        XCTAssertTrue(clearedExpectation.isSatisfied(by: cleared))
        XCTAssertFalse(
            populatedExpectation.isSatisfied(by: cleared)
        )
        XCTAssertFalse(
            clearedExpectation.isSatisfied(by: populated)
        )
        XCTAssertFalse(
            clearedExpectation.isSatisfied(
                by: logsClearProjectionTestSnapshot(
                    isCleared: true,
                    applicationState: .runningBackground
                )
            )
        )
        XCTAssertFalse(
            clearedExpectation.isSatisfied(
                by: logsClearProjectionTestSnapshot(
                    isCleared: true,
                    logsContentExists: false
                )
            )
        )
        XCTAssertFalse(
            clearedExpectation.isSatisfied(
                by: logsClearProjectionTestSnapshot(
                    isCleared: true,
                    clearButtonExists: false
                )
            )
        )
        XCTAssertFalse(
            clearedExpectation.isSatisfied(
                by: logsClearProjectionTestSnapshot(
                    isCleared: true,
                    clearButtonIsHittable: false
                )
            )
        )
        XCTAssertFalse(
            clearedExpectation.isSatisfied(
                by: logsClearProjectionTestSnapshot(
                    isCleared: true,
                    linesContainerExists: true
                )
            )
        )
        XCTAssertFalse(
            clearedExpectation.isSatisfied(
                by: logsClearProjectionTestSnapshot(
                    isCleared: true,
                    emptyHintExists: false
                )
            )
        )
        XCTAssertFalse(
            clearedExpectation.isSatisfied(
                by: logsClearProjectionTestSnapshot(
                    isCleared: true,
                    selectedLevel: "DEBUG"
                )
            )
        )
        XCTAssertFalse(
            clearedExpectation.isSatisfied(
                by: logsClearProjectionTestSnapshot(
                    isCleared: true,
                    rowIdentifiers: ["warn"]
                )
            )
        )
        XCTAssertFalse(
            populatedExpectation.isSatisfied(
                by: logsClearProjectionTestSnapshot(
                    isCleared: false,
                    rowIdentifiers: ["warn", "warn"]
                )
            )
        )
    }

    func testLogsRelaunchProjectionExpectationRequiresLoadedSeedlessState() {
        XCTAssertEqual(
            FlowTabUITestLogsClearProjectionObservationPolicy
                .relaunchProjectionWatchdog,
            8
        )
        XCTAssertTrue(
            FlowTabUITestLogsClearProjectionObservationPolicy
                .relaunchProjectionWatchdog.isFinite
        )
        XCTAssertGreaterThanOrEqual(
            FlowTabUITestLogsClearProjectionObservationPolicy
                .relaunchProjectionWatchdog,
            FlowTabUITestLogsClearProjectionObservationPolicy
                .projectionWatchdog
        )

        let expectation =
            FlowTabUITestLogsClearProjectionExpectation
                .reloadedWithoutSeededRows(
                    selectedLevel: "DEBUG"
                )
        let loadedLines = logsClearProjectionTestSnapshot(
            isCleared: false,
            selectedLevel: "DEBUG"
        )
        let loadedEmpty = logsClearProjectionTestSnapshot(
            isCleared: true,
            selectedLevel: "DEBUG"
        )

        XCTAssertTrue(expectation.isSatisfied(by: loadedLines))
        XCTAssertTrue(expectation.isSatisfied(by: loadedEmpty))
        XCTAssertFalse(
            expectation.isSatisfied(
                by: logsClearProjectionTestSnapshot(
                    isCleared: true,
                    applicationState: .notRunning,
                    selectedLevel: "DEBUG"
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: logsClearProjectionTestSnapshot(
                    isCleared: true,
                    emptyHintExists: false,
                    selectedLevel: "DEBUG"
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: logsClearProjectionTestSnapshot(
                    isCleared: false,
                    emptyHintExists: true,
                    selectedLevel: "DEBUG"
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: logsClearProjectionTestSnapshot(
                    isCleared: false,
                    selectedLevel: "DEBUG",
                    rowIdentifiers: ["warn"]
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: logsClearProjectionTestSnapshot(
                    isCleared: false,
                    selectedLevel: "WARN"
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: logsClearProjectionTestSnapshot(
                    isCleared: false,
                    clearButtonIsHittable: false,
                    selectedLevel: "DEBUG"
                )
            )
        )
    }

    func testLogsRelaunchProjectionOwnerUsesPrelaunchEvidence() {
        let expectation =
            FlowTabUITestLogsClearProjectionExpectation
                .reloadedWithoutSeededRows(
                    selectedLevel: "DEBUG"
                )
        let matching = logsClearProjectionTestSnapshot(
            isCleared: false,
            selectedLevel: "DEBUG"
        )
        var snapshot = logsClearProjectionTestSnapshot(
            isCleared: true,
            applicationState: .notRunning,
            selectedLevel: "DEBUG"
        )
        var triggerDidComplete = false
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestLogsClearProjectionObservationOwner(
                expectation: expectation,
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                acceptsResolution: { triggerDidComplete },
                readback: { snapshot }
            )
        owner.start()

        XCTAssertEqual(owner.latestEvidence?.source, .initialReadback)
        XCTAssertTrue(
            owner.latestEvidence?.value.isNotRunningBaseline
                == true
        )
        XCTAssertNil(owner.resolvedEvidence)

        triggerDidComplete = true
        snapshot = logsClearProjectionTestSnapshot(
            isCleared: true,
            emptyHintExists: false,
            selectedLevel: "DEBUG"
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = matching
        owner.requestReadback(source: .triggerReadback)
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestLogsClearProjectionTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .triggerReadback)
        XCTAssertEqual(evidence?.value, matching)
        XCTAssertEqual(cancellationCount, 1)
        owner.cancel()
    }

    func testLogsClearProjectionObserverRequiresPostTriggerEvidence() {
        let expectation =
            FlowTabUITestLogsClearProjectionExpectation.cleared(
                selectedLevel: "WARN"
            )
        let matching = logsClearProjectionTestSnapshot(
            isCleared: true
        )
        var snapshot = matching
        var triggerDidComplete = false
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestLogsClearProjectionObservationOwner(
                expectation: expectation,
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                acceptsResolution: { triggerDidComplete },
                readback: { snapshot }
            )
        owner.start()

        XCTAssertNil(owner.resolvedEvidence)
        triggerDidComplete = true
        snapshot = logsClearProjectionTestSnapshot(
            isCleared: true,
            clearButtonIsHittable: false
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = matching
        owner.requestReadback(source: .triggerReadback)
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestLogsClearProjectionTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .triggerReadback)
        XCTAssertEqual(evidence?.value, matching)
        XCTAssertEqual(cancellationCount, 1)
        owner.cancel()
    }

    func testLogsClearProjectionObserverLifecycleUnderPressure() {
        let expectation =
            FlowTabUITestLogsClearProjectionExpectation.cleared(
                selectedLevel: "WARN"
            )
        let matching = logsClearProjectionTestSnapshot(
            isCleared: true
        )

        for iteration in
            0..<FlowTabUITestLogsClearProjectionTestPolicy
                .pressureIterations
        {
            let resolvesInitially = iteration.isMultiple(of: 3)
            var snapshot = resolvesInitially
                ? matching
                : logsClearProjectionTestSnapshot(
                    isCleared: false,
                    rowIdentifiers: ["warn", "error"]
                )
            var scheduledReadback:
                ((FlowTabUITestConditionObservationSource) -> Void)?
            var cancellationCount = 0
            var readbackCount = 0
            let owner =
                FlowTabUITestLogsClearProjectionObservationOwner(
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
                snapshot = matching
                scheduledReadback?(.scheduledReadback)
            }
            let evidence = owner.waitForResolution(
                timeout:
                    FlowTabUITestLogsClearProjectionTestPolicy
                        .watchdog
            )
            let resolvedReadbackCount = readbackCount
            scheduledReadback?(.scheduledReadback)

            XCTAssertEqual(
                evidence?.value,
                matching,
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
            FlowTabUITestLogsClearProjectionObservationOwner(
                expectation: expectation,
                observationRegistration: { callback in
                    cancelledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    cancelledReadbackCount += 1
                    return self.logsClearProjectionTestSnapshot(
                        isCleared: false,
                        rowIdentifiers: ["warn", "error"]
                    )
                }
            )
        cancelledOwner.start()
        cancelledOwner.cancel()
        cancelledReadback?(.scheduledReadback)
        XCTAssertEqual(cancelledReadbackCount, 1)
    }

    func testLogsClearProjectionObserverWatchdogReportsLastEvidence() {
        let owner =
            FlowTabUITestLogsClearProjectionObservationOwner(
                expectation:
                    FlowTabUITestLogsClearProjectionExpectation
                        .cleared(selectedLevel: "WARN"),
                observationRegistration: nil,
                readback: {
                    self.logsClearProjectionTestSnapshot(
                        isCleared: false,
                        rowIdentifiers: ["warn", "error"]
                    )
                }
            )
        owner.start()

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestLogsClearProjectionTestPolicy
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
                "emptyHintExists=false"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("warn=1")
        )
        owner.cancel()
    }

    private func logsClearProjectionTestSnapshot(
        isCleared: Bool,
        applicationState: XCUIApplication.State = .runningForeground,
        logsContentExists: Bool = true,
        clearButtonExists: Bool = true,
        clearButtonIsHittable: Bool = true,
        linesContainerExists: Bool? = nil,
        emptyHintExists: Bool? = nil,
        selectedLevel: String = "WARN",
        rowIdentifiers: [String] = []
    ) -> FlowTabUITestLogsClearProjectionSnapshot {
        guard applicationState == .runningForeground else {
            return FlowTabUITestLogsClearProjectionSnapshot(
                applicationState: applicationState,
                logsContentExists: false,
                clearButtonExists: false,
                clearButtonIsHittable: false,
                linesContainerExists: false,
                emptyHintExists: false,
                selectedLevel: nil,
                seededRowIdentifiers: []
            )
        }
        return FlowTabUITestLogsClearProjectionSnapshot(
            applicationState: applicationState,
            logsContentExists: logsContentExists,
            clearButtonExists: clearButtonExists,
            clearButtonIsHittable: clearButtonIsHittable,
            linesContainerExists:
                linesContainerExists ?? !isCleared,
            emptyHintExists: emptyHintExists ?? isCleared,
            selectedLevel: selectedLevel,
            seededRowIdentifiers: rowIdentifiers
        )
    }
}
