import Foundation
import XCTest

private enum FlowTabUITestSwitcherWindowTitleTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let eventWatchdog: TimeInterval = 1
    static let queuePressureTurns = 100
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testSwitcherWindowTitleOpenMutationInitialProjectionWatchdogPolicyCompatibility() {
        XCTAssertEqual(
            FlowTabUITestSwitcherWindowTitleObservationPolicy
                .openWindowMutationInitialProjectionWatchdog,
            8
        )
        XCTAssertTrue(
            FlowTabUITestSwitcherWindowTitleObservationPolicy
                .openWindowMutationInitialProjectionWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSwitcherWindowTitleObservationPolicy
                .openWindowMutationInitialProjectionWatchdog,
            0
        )
    }

    func testSwitcherWindowTitleObserverRejectsMatchingPreTriggerEvidenceUnderPressure() {
        let expectation =
            FlowTabUITestSwitcherWindowTitleExpectation(
                titles: ["Primary", "Secondary"]
            )
        let matchingSnapshot =
            FlowTabUITestSwitcherWindowTitleSnapshot(
                cardCount: 2,
                titleCounts: expectation.titleCounts
            )

        for iteration in
            0..<FlowTabUITestSwitcherWindowTitleTestPolicy
                .pressureIterations
        {
            var acceptsResolution = false
            var scheduledReadback:
                ((FlowTabUITestConditionObservationSource) -> Void)?
            var readbackCount = 0
            var cancellationCount = 0
            let owner =
                FlowTabUITestSwitcherWindowTitleObservationOwner(
                    expectation: expectation,
                    observationRegistration: { callback in
                        scheduledReadback = callback
                        return FlowTabUITestObservationCancellation {
                            cancellationCount += 1
                        }
                    },
                    acceptsResolution: {
                        acceptsResolution
                    },
                    readback: {
                        readbackCount += 1
                        return matchingSnapshot
                    }
                )
            owner.start()

            XCTAssertNil(
                owner.resolvedEvidence,
                "iteration=\(iteration)"
            )
            scheduledReadback?(.scheduledReadback)
            XCTAssertNil(
                owner.resolvedEvidence,
                "iteration=\(iteration)"
            )

            acceptsResolution = true
            owner.requestReadback(source: .triggerReadback)
            let evidence = owner.waitForResolution(
                timeout:
                    FlowTabUITestSwitcherWindowTitleTestPolicy
                        .watchdog
            )
            let resolvedReadbackCount = readbackCount
            scheduledReadback?(.scheduledReadback)

            XCTAssertEqual(
                evidence?.source,
                .triggerReadback,
                "iteration=\(iteration)"
            )
            XCTAssertEqual(
                evidence?.value,
                matchingSnapshot,
                "iteration=\(iteration)"
            )
            XCTAssertEqual(
                readbackCount,
                resolvedReadbackCount,
                "iteration=\(iteration)"
            )
            XCTAssertEqual(
                cancellationCount,
                1,
                "iteration=\(iteration)"
            )
            owner.cancel()
        }
    }

    func testSwitcherWindowTitleOpenMutationWatchdogPolicyCompatibility() {
        XCTAssertEqual(
            FlowTabUITestSwitcherWindowTitleObservationPolicy
                .openWindowMutationProjectionWatchdog,
            25
        )
        XCTAssertTrue(
            FlowTabUITestSwitcherWindowTitleObservationPolicy
                .openWindowMutationProjectionWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSwitcherWindowTitleObservationPolicy
                .openWindowMutationProjectionWatchdog,
            0
        )
    }

    func testSwitcherWindowTitleObserverStartsBeforeExplicitContractionTrigger() {
        let expectation =
            FlowTabUITestSwitcherWindowTitleExpectation(
                titles: ["Primary"]
            )
        var snapshot = FlowTabUITestSwitcherWindowTitleSnapshot(
            cardCount: 2,
            titleCounts: ["Primary": 1, "Secondary": 1]
        )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var readbackCount = 0
        var triggerCompleted = false
        let owner =
            FlowTabUITestSwitcherWindowTitleObservationOwner(
                expectation: expectation,
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    readbackCount += 1
                    return snapshot
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(readbackCount, 1)
        for _ in
            0..<FlowTabUITestSwitcherWindowTitleTestPolicy
                .queuePressureTurns
        {
            DispatchQueue.main.async {}
        }
        DispatchQueue.main.async {
            triggerCompleted = true
            snapshot = FlowTabUITestSwitcherWindowTitleSnapshot(
                cardCount: 1,
                titleCounts: ["Primary": 1]
            )
            scheduledReadback?(.scheduledReadback)
        }

        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestSwitcherWindowTitleTestPolicy
                    .eventWatchdog
        )

        XCTAssertTrue(triggerCompleted)
        XCTAssertEqual(evidence?.source, .scheduledReadback)
        XCTAssertEqual(evidence?.value, snapshot)
        XCTAssertEqual(readbackCount, 2)
    }

    func testSwitcherWindowTitleOpenMutationWatchdogReportsPreTriggerBaseline() {
        let owner =
            FlowTabUITestSwitcherWindowTitleObservationOwner(
                expectation:
                    FlowTabUITestSwitcherWindowTitleExpectation(
                        titles: ["Primary"]
                    ),
                observationRegistration: { _ in
                    FlowTabUITestObservationCancellation {}
                },
                readback: {
                    FlowTabUITestSwitcherWindowTitleSnapshot(
                        cardCount: 2,
                        titleCounts: [
                            "Primary": 1,
                            "Secondary": 1
                        ]
                    )
                }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestSwitcherWindowTitleTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "expected{cardCount=1 titleCounts=Primary=1}"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "cardCount=2 titleCounts=Primary=1,Secondary=1"
            )
        )
    }

    func testSwitcherWindowTitleCountReadbackRefreshesCollectionContractionEvidence() {
        var cardCount = 2
        var counts = [
            "Primary": 1,
            "Secondary": 1
        ]
        var cardCountReadbacks = 0
        var titleReadbacks: [String] = []
        let readback = FlowTabUITestSwitcherWindowTitleCountReadback(
            cardCount: {
                cardCountReadbacks += 1
                return cardCount
            },
            titleCount: { title in
                titleReadbacks.append(title)
                return counts[title, default: 0]
            }
        )
        let observedTitles: Set<String> = [
            "Primary",
            "Secondary"
        ]

        XCTAssertEqual(
            readback.snapshot(observing: observedTitles),
            FlowTabUITestSwitcherWindowTitleSnapshot(
                cardCount: 2,
                titleCounts: counts
            )
        )

        cardCount = 1
        counts["Secondary"] = 0
        XCTAssertEqual(
            readback.snapshot(observing: observedTitles),
            FlowTabUITestSwitcherWindowTitleSnapshot(
                cardCount: 1,
                titleCounts: ["Primary": 1]
            )
        )
        XCTAssertEqual(cardCountReadbacks, 2)
        XCTAssertEqual(
            titleReadbacks,
            ["Primary", "Secondary", "Primary", "Secondary"]
        )
    }

    func testSwitcherWindowTitleObserverUsesExactMultiplicityEvidence() {
        let expectation =
            FlowTabUITestSwitcherWindowTitleExpectation(
                titles: ["Document", "Document", "Settings"]
            )
        var snapshot = FlowTabUITestSwitcherWindowTitleSnapshot(
            cardCount: 3,
            titleCounts: [
                "Document": 1,
                "Settings": 1
            ]
        )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestSwitcherWindowTitleObservationOwner(
                expectation: expectation,
                observationRegistration: { callback in
                    scheduledReadback = callback
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: { snapshot }
            )
        owner.start()

        XCTAssertNil(owner.resolvedEvidence)
        snapshot = FlowTabUITestSwitcherWindowTitleSnapshot(
            cardCount: 3,
            titleCounts: expectation.titleCounts
        )
        scheduledReadback?(.scheduledReadback)
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestSwitcherWindowTitleTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .scheduledReadback)
        XCTAssertEqual(evidence?.value, snapshot)
        XCTAssertEqual(cancellationCount, 1)
        owner.cancel()
    }

    func testSwitcherWindowTitleObserverLifecycleUnderPressure() {
        let expectation =
            FlowTabUITestSwitcherWindowTitleExpectation(
                titles: ["Primary", "Secondary"]
            )
        let matchingSnapshot =
            FlowTabUITestSwitcherWindowTitleSnapshot(
                cardCount: 2,
                titleCounts: expectation.titleCounts
            )

        for iteration in 0..<FlowTabUITestSwitcherWindowTitleTestPolicy
            .pressureIterations
        {
            let resolvesInitially = iteration.isMultiple(of: 2)
            var snapshot = resolvesInitially
                ? matchingSnapshot
                : FlowTabUITestSwitcherWindowTitleSnapshot(
                    cardCount: 1,
                    titleCounts: ["Primary": 1, "Secondary": 0]
                )
            var scheduledReadback:
                ((FlowTabUITestConditionObservationSource) -> Void)?
            var cancellationCount = 0
            var readbackCount = 0
            let owner =
                FlowTabUITestSwitcherWindowTitleObservationOwner(
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
                    FlowTabUITestSwitcherWindowTitleTestPolicy
                        .watchdog
            )
            let resolvedReadbackCount = readbackCount
            scheduledReadback?(.scheduledReadback)

            XCTAssertNotNil(evidence, "iteration=\(iteration)")
            XCTAssertEqual(readbackCount, resolvedReadbackCount)
            XCTAssertEqual(cancellationCount, 1)
            owner.cancel()
        }

        var cancelledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancelledReadbackCount = 0
        let cancelledOwner =
            FlowTabUITestSwitcherWindowTitleObservationOwner(
                expectation: expectation,
                observationRegistration: { callback in
                    cancelledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    cancelledReadbackCount += 1
                    return FlowTabUITestSwitcherWindowTitleSnapshot(
                        cardCount: 0,
                        titleCounts: [:]
                    )
                }
            )
        cancelledOwner.start()
        cancelledOwner.cancel()
        cancelledReadback?(.scheduledReadback)
        XCTAssertEqual(cancelledReadbackCount, 1)
    }
}
