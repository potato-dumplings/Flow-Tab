import CoreGraphics
import Foundation
import XCTest

private enum FlowTabUITestSwitcherWindowCardTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testSwitcherWindowCardObserverRequiresFreshExactIdentityEvidence() {
        let expectation =
            FlowTabUITestSwitcherWindowCardExpectation(
                expectedTitles: ["Document", "Document"],
                excludedTitles: ["Other"],
                previousWindowCardIdentifiers: ["old-card"]
            )
        var acceptsResolution = false
        var snapshot =
            FlowTabUITestSwitcherWindowCardSnapshot(
                cards: [
                    switcherWindowCard(
                        identifier: "new-card-1",
                        title: "Document"
                    ),
                    switcherWindowCard(
                        identifier: "new-card-2",
                        title: "Document"
                    )
                ]
            )
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        let owner =
            FlowTabUITestSwitcherWindowCardObservationOwner(
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
        snapshot = FlowTabUITestSwitcherWindowCardSnapshot(
            cards: [
                switcherWindowCard(
                    identifier: "old-card",
                    title: "Document"
                ),
                switcherWindowCard(
                    identifier: "new-card-2",
                    title: "Document"
                )
            ]
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = FlowTabUITestSwitcherWindowCardSnapshot(
            cards: [
                switcherWindowCard(
                    identifier: "new-card-1",
                    title: "Document"
                ),
                switcherWindowCard(
                    identifier: "new-card-2",
                    title: "Other"
                )
            ]
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        snapshot = FlowTabUITestSwitcherWindowCardSnapshot(
            cards: [
                switcherWindowCard(
                    identifier: "duplicate-card",
                    title: "Document"
                ),
                switcherWindowCard(
                    identifier: "duplicate-card",
                    title: "Document"
                )
            ]
        )
        scheduledReadback?(.scheduledReadback)
        XCTAssertNil(owner.resolvedEvidence)

        let matchingSnapshot =
            FlowTabUITestSwitcherWindowCardSnapshot(
                cards: [
                    switcherWindowCard(
                        identifier: "new-card-1",
                        title: "Document",
                        frame: CGRect(
                            x: 10,
                            y: 20,
                            width: 300,
                            height: 180
                        ),
                        hasImage: true
                    ),
                    switcherWindowCard(
                        identifier: "new-card-2",
                        title: "Document"
                    )
                ]
            )
        snapshot = matchingSnapshot
        scheduledReadback?(.scheduledReadback)
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestSwitcherWindowCardTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .scheduledReadback)
        XCTAssertEqual(evidence?.value, matchingSnapshot)
        XCTAssertEqual(cancellationCount, 1)
        owner.cancel()
    }

    func testSwitcherWindowCardObserverLifecycleUnderPressure() {
        let expectation =
            FlowTabUITestSwitcherWindowCardExpectation(
                expectedTitles: ["Primary", "Secondary"],
                excludedTitles: ["Other"],
                previousWindowCardIdentifiers: ["stale-card"]
            )
        let matchingSnapshot =
            FlowTabUITestSwitcherWindowCardSnapshot(
                cards: [
                    switcherWindowCard(
                        identifier: "primary-card",
                        title: "Primary"
                    ),
                    switcherWindowCard(
                        identifier: "secondary-card",
                        title: "Secondary"
                    )
                ]
            )

        for iteration in
            0..<FlowTabUITestSwitcherWindowCardTestPolicy
                .pressureIterations
        {
            let resolvesInitially = iteration.isMultiple(of: 2)
            var snapshot = resolvesInitially
                ? matchingSnapshot
                : FlowTabUITestSwitcherWindowCardSnapshot(
                    cards: [
                        switcherWindowCard(
                            identifier: "stale-card",
                            title: "Primary"
                        )
                    ]
                )
            var scheduledReadback:
                ((FlowTabUITestConditionObservationSource) -> Void)?
            var cancellationCount = 0
            var readbackCount = 0
            let owner =
                FlowTabUITestSwitcherWindowCardObservationOwner(
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
                    FlowTabUITestSwitcherWindowCardTestPolicy
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
            FlowTabUITestSwitcherWindowCardObservationOwner(
                expectation: expectation,
                observationRegistration: { callback in
                    cancelledReadback = callback
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    cancelledReadbackCount += 1
                    return FlowTabUITestSwitcherWindowCardSnapshot(
                        cards: []
                    )
                }
            )
        cancelledOwner.start()
        cancelledOwner.cancel()
        cancelledReadback?(.scheduledReadback)
        XCTAssertEqual(cancelledReadbackCount, 1)

        let watchdogOwner =
            FlowTabUITestSwitcherWindowCardObservationOwner(
                expectation: expectation,
                observationRegistration: nil,
                readback: {
                    FlowTabUITestSwitcherWindowCardSnapshot(
                        cards: [
                            self.switcherWindowCard(
                                identifier: "stale-card",
                                title: "Primary"
                            )
                        ]
                    )
                }
            )
        watchdogOwner.start()
        XCTAssertNil(
            watchdogOwner.waitForResolution(
                timeout:
                    FlowTabUITestSwitcherWindowCardTestPolicy
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
                "stale-card"
            )
        )
        watchdogOwner.cancel()
    }

    private func switcherWindowCard(
        identifier: String,
        title: String,
        frame: CGRect = CGRect(
            x: 0,
            y: 0,
            width: 200,
            height: 120
        ),
        hasImage: Bool = false
    ) -> SwitcherWindowCardObservation {
        SwitcherWindowCardObservation(
            identifier: identifier,
            title: title,
            value: "title=\(title)",
            frame: frame,
            hasImage: hasImage
        )
    }
}
