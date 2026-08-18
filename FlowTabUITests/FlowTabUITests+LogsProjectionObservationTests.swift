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

    func testSeededLogsProjectionExpectationRequiresAtomicStructuredRows() {
        let expectation = seededLogsProjectionTestExpectation()
        let matching = seededLogsProjectionTestSnapshot()

        XCTAssertTrue(expectation.isSatisfied(by: matching))
        XCTAssertEqual(
            expectation.fingerprints(in: matching),
            ["debug-fingerprint", "info-fingerprint"]
        )
        let reordered = seededLogsProjectionTestSnapshot(
            rows: Array(matching.rows.reversed())
        )
        XCTAssertTrue(expectation.isSatisfied(by: reordered))
        XCTAssertEqual(
            expectation.fingerprints(in: reordered),
            ["debug-fingerprint", "info-fingerprint"]
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: seededLogsProjectionTestSnapshot(
                    applicationState: .runningBackground
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: seededLogsProjectionTestSnapshot(
                    logsContentExists: false
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: seededLogsProjectionTestSnapshot(
                    privacyNoticeExists: false
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: seededLogsProjectionTestSnapshot(
                    linesContainerExists: false
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: seededLogsProjectionTestSnapshot(
                    emptyHintExists: true
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: seededLogsProjectionTestSnapshot(
                    selectedLevel: "WARN"
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: seededLogsProjectionTestSnapshot(
                    rows: Array(matching.rows.dropLast())
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: seededLogsProjectionTestSnapshot(
                    rows: [matching.rows[0], matching.rows[0]]
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: seededLogsProjectionTestSnapshot(
                    rows: matching.rows + [
                        FlowTabUITestSeededLogProjectionRowSnapshot(
                            identifier: "extra",
                            content:
                                "message.type=structured "
                                + "message.fingerprint=extra"
                        )
                    ]
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: seededLogsProjectionTestSnapshot(
                    rows: [
                        FlowTabUITestSeededLogProjectionRowSnapshot(
                            identifier: "debug",
                            content:
                                "seeded-debug-log-1 "
                                + "message.type=structured "
                                + "message.fingerprint=debug-fingerprint"
                        ),
                        matching.rows[1]
                    ]
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: seededLogsProjectionTestSnapshot(
                    rows: [
                        FlowTabUITestSeededLogProjectionRowSnapshot(
                            identifier: "debug",
                            content:
                                "message.fingerprint=debug-fingerprint"
                        ),
                        matching.rows[1]
                    ]
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: seededLogsProjectionTestSnapshot(
                    rows: [
                        FlowTabUITestSeededLogProjectionRowSnapshot(
                            identifier: "debug",
                            content: "message.type=structured"
                        ),
                        matching.rows[1]
                    ]
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: seededLogsProjectionTestSnapshot(
                    rows: [
                        FlowTabUITestSeededLogProjectionRowSnapshot(
                            identifier: "debug",
                            content:
                                "message.type=structured "
                                + "message.fingerprint= "
                        ),
                        matching.rows[1]
                    ]
                )
            )
        )
    }

    func testSeededLogsProjectionOwnerUsesInitialAndPostTriggerEvidence() {
        let expectation = seededLogsProjectionTestExpectation()
        let matching = seededLogsProjectionTestSnapshot()
        var snapshot = matching
        var acceptsResolution = false
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestSeededLogsProjectionObservationOwner(
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

        XCTAssertEqual(owner.latestEvidence?.source, .initialReadback)
        XCTAssertEqual(owner.latestEvidence?.value, matching)
        XCTAssertNil(owner.resolvedEvidence)

        acceptsResolution = true
        owner.requestReadback(source: .triggerReadback)
        let initialEvidence = owner.waitForResolution(
            timeout:
                FlowTabUITestLogsProjectionTestPolicy.watchdog
        )
        XCTAssertEqual(initialEvidence?.source, .triggerReadback)
        XCTAssertEqual(initialEvidence?.value, matching)
        XCTAssertEqual(cancellationCount, 1)
        owner.cancel()

        snapshot = seededLogsProjectionTestSnapshot(
            privacyNoticeExists: false
        )
        acceptsResolution = false
        scheduledReadback = nil
        cancellationCount = 0
        let delayedOwner =
            FlowTabUITestSeededLogsProjectionObservationOwner(
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
        delayedOwner.start()
        acceptsResolution = true
        delayedOwner.requestReadback(source: .triggerReadback)
        XCTAssertNil(delayedOwner.resolvedEvidence)

        snapshot = matching
        scheduledReadback?(.scheduledReadback)
        let delayedEvidence = delayedOwner.waitForResolution(
            timeout:
                FlowTabUITestLogsProjectionTestPolicy.watchdog
        )
        XCTAssertEqual(delayedEvidence?.source, .scheduledReadback)
        XCTAssertEqual(delayedEvidence?.value, matching)
        XCTAssertEqual(cancellationCount, 1)
        delayedOwner.cancel()
    }

    func testSeededLogsProjectionOwnerLifecycleUnderPressure() {
        let expectation = seededLogsProjectionTestExpectation()
        let matching = seededLogsProjectionTestSnapshot()
        let incomplete = seededLogsProjectionTestSnapshot(
            privacyNoticeExists: false
        )

        for iteration in
            0..<FlowTabUITestLogsProjectionTestPolicy
                .pressureIterations
        {
            let resolvesInitially = iteration.isMultiple(of: 2)
            var snapshot = resolvesInitially ? matching : incomplete
            var scheduledReadback:
                ((FlowTabUITestConditionObservationSource) -> Void)?
            var cancellationCount = 0
            var readbackCount = 0
            let owner =
                FlowTabUITestSeededLogsProjectionObservationOwner(
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
                snapshot = matching
                scheduledReadback?(.scheduledReadback)
            }
            let evidence = owner.waitForResolution(
                timeout:
                    FlowTabUITestLogsProjectionTestPolicy.watchdog
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
        var cancellationCount = 0
        let cancelledOwner =
            FlowTabUITestSeededLogsProjectionObservationOwner(
                expectation: expectation,
                observationRegistration: { callback in
                    cancelledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    cancelledReadbackCount += 1
                    return incomplete
                }
            )
        cancelledOwner.start()
        cancelledOwner.cancel()
        cancelledReadback?(.scheduledReadback)
        XCTAssertEqual(cancelledReadbackCount, 1)
        XCTAssertEqual(cancellationCount, 1)

        let watchdogOwner =
            FlowTabUITestSeededLogsProjectionObservationOwner(
                expectation: expectation,
                observationRegistration: nil,
                readback: { incomplete }
            )
        watchdogOwner.start()
        XCTAssertNil(
            watchdogOwner.waitForResolution(
                timeout:
                    FlowTabUITestLogsProjectionTestPolicy.watchdog
            )
        )
        XCTAssertTrue(
            watchdogOwner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(
            watchdogOwner.diagnosticSummary.contains(
                "privacyNoticeExists=false"
            )
        )
        watchdogOwner.cancel()
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

    private func seededLogsProjectionTestExpectation()
        -> FlowTabUITestSeededLogsProjectionExpectation
    {
        FlowTabUITestSeededLogsProjectionExpectation(
            selectedLevel: "DEBUG",
            rows: [
                FlowTabUITestSeededLogProjectionExpectation(
                    identifier: "debug",
                    cleartextMarker: "seeded-debug-log-1"
                ),
                FlowTabUITestSeededLogProjectionExpectation(
                    identifier: "info",
                    cleartextMarker: "seeded-info-log-2"
                )
            ]
        )
    }

    private func seededLogsProjectionTestSnapshot(
        applicationState: XCUIApplication.State = .runningForeground,
        logsContentExists: Bool = true,
        privacyNoticeExists: Bool = true,
        linesContainerExists: Bool = true,
        emptyHintExists: Bool = false,
        selectedLevel: String? = "DEBUG",
        rows: [FlowTabUITestSeededLogProjectionRowSnapshot]? = nil
    ) -> FlowTabUITestSeededLogsProjectionSnapshot {
        FlowTabUITestSeededLogsProjectionSnapshot(
            applicationState: applicationState,
            logsContentExists: logsContentExists,
            privacyNoticeExists: privacyNoticeExists,
            linesContainerExists: linesContainerExists,
            emptyHintExists: emptyHintExists,
            selectedLevel: selectedLevel,
            rows: rows ?? [
                FlowTabUITestSeededLogProjectionRowSnapshot(
                    identifier: "debug",
                    content:
                        "message.type=structured "
                        + "message.fingerprint=debug-fingerprint"
                ),
                FlowTabUITestSeededLogProjectionRowSnapshot(
                    identifier: "info",
                    content:
                        "message.type=structured "
                        + "message.fingerprint=info-fingerprint"
                )
            ]
        )
    }
}
