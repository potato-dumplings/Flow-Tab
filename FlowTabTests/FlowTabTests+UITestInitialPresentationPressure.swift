import XCTest
@testable import FlowTab

extension FlowTabTests {
    @MainActor
    func testUITestInitialPresentationReplacementPressureRejectsStaleWork() {
        let cancellationScheduler =
            ManualInitialPresentationScheduler()
        var cancellationSnapshot =
            initialPresentationSnapshot(
                generation: 1,
                isComplete: false,
                itemIDs: ["app-a"]
            )
        var cancellationCallbackCount = 0
        let cancelledOwner = makeInitialPresentationOwner(
            scheduler: cancellationScheduler,
            readback: { cancellationSnapshot }
        )
        let cancelledGeneration = cancelledOwner.start(
            watchdogInterval: 3,
            triggerReadiness: {},
            attemptPresentation: { candidate in
                .init(
                    didPresent: true,
                    sessionItemIDs: candidate.itemIDs,
                    searchIsActiveOrPending: false
                )
            },
            cancelPresentation: {},
            onResolved: { _ in
                cancellationCallbackCount += 1
            },
            onWatchdog: { _ in
                cancellationCallbackCount += 1
            }
        )
        let cancelledToken =
            cancellationScheduler.tokens[0]

        cancelledOwner.cancel()
        cancellationSnapshot =
            initialPresentationSnapshot(
                generation: 2,
                itemIDs: ["app-a"]
            )
        XCTAssertFalse(
            cancelledOwner.observe(
                source:
                    .appSwitcherProjectionDidUpdate,
                observationGeneration:
                    cancelledGeneration
            )
        )
        cancellationScheduler.fire(
            cancelledToken,
            includingCancelled: true
        )
        XCTAssertEqual(cancellationCallbackCount, 0)
        XCTAssertFalse(cancelledOwner.isObserving)
        XCTAssertTrue(cancelledToken.isCancelled)

        let scheduler =
            ManualInitialPresentationScheduler()
        var snapshot = initialPresentationSnapshot(
            generation: 1,
            isComplete: false,
            itemIDs: ["app-a"]
        )
        var resolutions:
            [FlowTabUITestInitialPresentationEvidence] = []
        var failures:
            [FlowTabUITestInitialPresentationWatchdogFailure]
                = []
        let owner = makeInitialPresentationOwner(
            scheduler: scheduler,
            readback: { snapshot }
        )
        var generations: [UInt64] = []

        for index in 1...500 {
            snapshot = initialPresentationSnapshot(
                generation: UInt64(index),
                isComplete: false,
                itemIDs: ["app-a"]
            )
            generations.append(
                owner.start(
                    watchdogInterval: 3,
                    triggerReadiness: {},
                    attemptPresentation: { candidate in
                        .init(
                            didPresent: true,
                            sessionItemIDs:
                                candidate.itemIDs,
                            searchIsActiveOrPending:
                                false
                        )
                    },
                    cancelPresentation: {},
                    onResolved: {
                        resolutions.append($0)
                    },
                    onWatchdog: {
                        failures.append($0)
                    }
                )
            )
        }

        for staleGeneration in generations.dropLast() {
            XCTAssertFalse(
                owner.observe(
                    source:
                        .appSwitcherProjectionDidUpdate,
                    observationGeneration:
                        staleGeneration
                )
            )
        }
        snapshot = initialPresentationSnapshot(
            generation: 501,
            itemIDs: ["app-a", "app-b"]
        )
        XCTAssertTrue(
            owner.observe(
                source: .appSwitcherProjectionDidUpdate,
                observationGeneration:
                    generations.last!
            )
        )
        for token in scheduler.tokens {
            scheduler.fire(
                token,
                includingCancelled: true
            )
        }

        XCTAssertEqual(resolutions.count, 1)
        XCTAssertTrue(failures.isEmpty)
        XCTAssertFalse(owner.isObserving)
        XCTAssertTrue(
            scheduler.tokens.allSatisfy(\.isCancelled)
        )
    }
}
