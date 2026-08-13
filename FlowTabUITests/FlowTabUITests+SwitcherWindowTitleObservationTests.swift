import Foundation
import XCTest

private enum FlowTabUITestSwitcherWindowTitleTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
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
