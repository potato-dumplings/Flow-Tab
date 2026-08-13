import CoreGraphics
import Foundation
import XCTest

private enum FlowTabUITestSwitcherWindowCardTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testSwitcherWindowCardEdgeInputsPolicyPreservesCompatibleBound() {
        XCTAssertEqual(
            FlowTabUITestSwitcherWindowCardPolicy
                .edgeInputsProjectionWatchdog,
            8
        )
        XCTAssertTrue(
            FlowTabUITestSwitcherWindowCardPolicy
                .edgeInputsProjectionWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSwitcherWindowCardPolicy
                .edgeInputsProjectionWatchdog,
            0
        )
    }

    func testSwitcherWindowCardMultiAppIdentityPolicyPreservesCompatibleBound() {
        XCTAssertEqual(
            FlowTabUITestSwitcherWindowCardPolicy
                .multiAppCardIdentityProjectionWatchdog,
            8
        )
        XCTAssertTrue(
            FlowTabUITestSwitcherWindowCardPolicy
                .multiAppCardIdentityProjectionWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestSwitcherWindowCardPolicy
                .multiAppCardIdentityProjectionWatchdog,
            0
        )
    }

    func testSwitcherWindowPageExpectationRequiresCompleteLayoutClosure() {
        let expectation = switcherWindowPageExpectation()
        let matching = switcherWindowPageSnapshot()

        XCTAssertTrue(expectation.isSatisfied(by: matching))
        XCTAssertTrue(
            expectation.isSatisfied(
                by: FlowTabUITestSwitcherWindowPageSnapshot(
                    cards: Array(matching.cards.reversed()),
                    nextPageBoundary: matching.nextPageBoundary
                )
            )
        )

        var cards = matching.cards
        cards.removeLast()
        XCTAssertFalse(
            expectation.isSatisfied(
                by: switcherWindowPageSnapshot(cards: cards)
            )
        )

        cards = matching.cards
        cards[2] = switcherWindowPageCard(
            index: 2,
            identifier: "wrong-card"
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: switcherWindowPageSnapshot(cards: cards)
            )
        )

        cards = matching.cards
        cards[2] = switcherWindowPageCard(
            index: 2,
            title: "Wrong title"
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: switcherWindowPageSnapshot(cards: cards)
            )
        )

        cards = matching.cards
        cards[2] = switcherWindowPageCard(
            index: 2,
            hasImage: false
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: switcherWindowPageSnapshot(cards: cards)
            )
        )

        cards = matching.cards
        cards[2] = switcherWindowPageCard(
            index: 2,
            frame: CGRect(x: 224, y: 0, width: 99, height: 120)
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: switcherWindowPageSnapshot(cards: cards)
            )
        )

        cards = matching.cards
        cards[3] = switcherWindowPageCard(
            index: 3,
            frame: CGRect(x: 360, y: 0, width: 100, height: 120)
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: switcherWindowPageSnapshot(cards: cards)
            )
        )

        XCTAssertFalse(
            expectation.isSatisfied(
                by: switcherWindowPageSnapshot(
                    nextPageExists: false
                )
            )
        )
        XCTAssertFalse(
            expectation.isSatisfied(
                by: switcherWindowPageSnapshot(
                    nextPageX: 700
                )
            )
        )
    }

    func testSwitcherWindowPageObserverRequiresPostTriggerReadback() {
        let matching = switcherWindowPageSnapshot()
        var registrationCount = 0
        let owner = FlowTabUITestSwitcherWindowPageObservationOwner(
            expectation: switcherWindowPageExpectation(),
            scheduledRegistration: { _ in
                registrationCount += 1
                return FlowTabUITestObservationCancellation {}
            },
            readback: { matching }
        )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(owner.resolvedEvidence)
        owner.markTriggerCompleted()

        XCTAssertEqual(owner.resolvedEvidence?.source, .triggerReadback)
        XCTAssertEqual(owner.resolvedEvidence?.value, matching)
        XCTAssertEqual(registrationCount, 0)
    }

    func testSwitcherWindowPageObserverUsesPostTriggerScheduledEvidence() {
        let matching = switcherWindowPageSnapshot()
        var snapshot = switcherWindowPageSnapshot(cards: [])
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var registrationCount = 0
        var cancellationCount = 0
        let owner = FlowTabUITestSwitcherWindowPageObservationOwner(
            expectation: switcherWindowPageExpectation(),
            scheduledRegistration: { callback in
                registrationCount += 1
                scheduledReadback = callback
                return FlowTabUITestObservationCancellation {
                    cancellationCount += 1
                }
            },
            readback: { snapshot }
        )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertEqual(registrationCount, 0)
        owner.markTriggerCompleted()
        XCTAssertEqual(registrationCount, 1)

        for _ in 0..<5 {
            scheduledReadback?(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
        }

        snapshot = matching
        scheduledReadback?(.scheduledReadback)

        XCTAssertEqual(owner.resolvedEvidence?.source, .scheduledReadback)
        XCTAssertEqual(owner.resolvedEvidence?.value, matching)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testSwitcherWindowPageObserverCancellationWatchdogAndPressure() {
        let expectation = switcherWindowPageExpectation()
        let matching = switcherWindowPageSnapshot()
        var cancelledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var cancellationCount = 0
        var cancelledSnapshot = switcherWindowPageSnapshot(cards: [])
        let cancelledOwner = FlowTabUITestSwitcherWindowPageObservationOwner(
            expectation: expectation,
            scheduledRegistration: { callback in
                cancelledReadback = callback
                return FlowTabUITestObservationCancellation {
                    cancellationCount += 1
                }
            },
            readback: { cancelledSnapshot }
        )
        cancelledOwner.start()
        cancelledOwner.markTriggerCompleted()
        cancelledOwner.cancel()
        cancelledSnapshot = matching
        cancelledReadback?(.scheduledReadback)
        XCTAssertNil(cancelledOwner.resolvedEvidence)
        XCTAssertEqual(cancellationCount, 1)

        var watchdogReadbackCount = 0
        let watchdogOwner = FlowTabUITestSwitcherWindowPageObservationOwner(
            expectation: expectation,
            scheduledRegistration: { _ in
                FlowTabUITestObservationCancellation {}
            },
            readback: {
                defer { watchdogReadbackCount += 1 }
                return watchdogReadbackCount >= 2
                    ? matching
                    : self.switcherWindowPageSnapshot(cards: [])
            }
        )
        watchdogOwner.start()
        watchdogOwner.markTriggerCompleted()
        XCTAssertNil(
            watchdogOwner.waitForResolution(
                timeout:
                    FlowTabUITestSwitcherWindowCardTestPolicy
                        .watchdog
            )
        )
        XCTAssertEqual(watchdogOwner.latestSnapshot, matching)
        XCTAssertTrue(
            watchdogOwner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(
            watchdogOwner.diagnosticSummary.contains(
                "phase=triggerCompleted"
            )
        )
        watchdogOwner.cancel()

        for _ in 0..<FlowTabUITestSwitcherWindowCardTestPolicy
            .pressureIterations
        {
            var snapshot = switcherWindowPageSnapshot(cards: [])
            var scheduledReadbacks: [
                (FlowTabUITestConditionObservationSource) -> Void
            ] = []
            let owner = FlowTabUITestSwitcherWindowPageObservationOwner(
                expectation: expectation,
                scheduledRegistration: { callback in
                    scheduledReadbacks.append(callback)
                    return FlowTabUITestObservationCancellation {}
                },
                readback: { snapshot }
            )
            owner.start()
            owner.markTriggerCompleted()
            let staleReadback = scheduledReadbacks[0]
            owner.cancel()
            owner.start()
            owner.markTriggerCompleted()
            let currentReadback = scheduledReadbacks[1]

            snapshot = matching
            staleReadback(.scheduledReadback)
            XCTAssertNil(owner.resolvedEvidence)
            currentReadback(.scheduledReadback)
            XCTAssertEqual(owner.resolvedEvidence?.generation, 2)
            owner.cancel()
        }
    }

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
        owner.requestReadback(source: .triggerReadback)
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestSwitcherWindowCardTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .triggerReadback)
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

    private func switcherWindowPageExpectation()
        -> FlowTabUITestSwitcherWindowPageExpectation
    {
        FlowTabUITestSwitcherWindowPageExpectation(
            expectedCards: (0..<6).map { index in
                FlowTabUITestSwitcherWindowPageCardExpectation(
                    identifier: "card-\(index)",
                    title: "Window \(index)"
                )
            },
            excludedIdentifiers: ["card-25"],
            minimumCardCount: 3,
            maximumCardCount: 6,
            minimumCardWidth: 100,
            maximumCardGap: 24
        )
    }

    private func switcherWindowPageSnapshot(
        cards: [SwitcherWindowCardObservation]? = nil,
        nextPageExists: Bool = true,
        nextPageX: CGFloat = 668
    ) -> FlowTabUITestSwitcherWindowPageSnapshot {
        FlowTabUITestSwitcherWindowPageSnapshot(
            cards: cards ?? (0..<6).map {
                switcherWindowPageCard(index: $0)
            },
            nextPageBoundary:
                FlowTabUITestSwitcherWindowPageBoundarySnapshot(
                    exists: nextPageExists,
                    frame: nextPageExists
                        ? CGRect(
                            x: nextPageX,
                            y: 0,
                            width: 28,
                            height: 48
                        )
                        : .zero
                )
        )
    }

    private func switcherWindowPageCard(
        index: Int,
        identifier: String? = nil,
        title: String? = nil,
        frame: CGRect? = nil,
        hasImage: Bool = true
    ) -> SwitcherWindowCardObservation {
        switcherWindowCard(
            identifier: identifier ?? "card-\(index)",
            title: title ?? "Window \(index)",
            frame: frame
                ?? CGRect(
                    x: CGFloat(index) * 112,
                    y: 0,
                    width: 100,
                    height: 120
                ),
            hasImage: hasImage
        )
    }
}
