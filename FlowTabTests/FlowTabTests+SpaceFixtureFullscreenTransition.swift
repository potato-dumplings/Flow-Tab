import CoreGraphics
import XCTest

extension FlowTabTests {
    @MainActor
    func testSpaceFixtureFullscreenOwnerAcceptsInitialReadbackCompletion() {
        let scheduler = ManualSpaceFixtureScheduler()
        let owner = SpaceFixtureFullscreenTransitionOwner(
            scheduler: scheduler
        )
        let window = SpaceFixtureWindowSpy(
            plan: makeFullscreenTransitionPlan(index: 4),
            completesFullScreenImmediately: true
        )
        var evidence: SpaceFixtureFullscreenTransitionEvidence?
        var completion: SpaceFixtureFullscreenTransitionCompletion?

        let generation = owner.start(
            windows: [window],
            initialDelayMilliseconds: 0,
            onWillEnter: { _, _, _ in },
            onDidEnter: { evidence = $0 },
            onComplete: { completion = $0 }
        )

        XCTAssertTrue(scheduler.fire(at: 0))
        XCTAssertEqual(
            evidence,
            SpaceFixtureFullscreenTransitionEvidence(
                observationGeneration: generation,
                sequenceIndex: 0,
                totalWindowCount: 1,
                windowPlanIndex: 4
            )
        )
        XCTAssertEqual(
            completion,
            SpaceFixtureFullscreenTransitionCompletion(
                observationGeneration: generation,
                windowPlanIndices: [4]
            )
        )
        XCTAssertTrue(
            window.enterFullScreenTokens[0].isCancelled
        )
        XCTAssertFalse(owner.isRunning)
    }

    @MainActor
    func testSpaceFixtureFullscreenOwnerChainsFromCompletionEvidence() {
        let scheduler = ManualSpaceFixtureScheduler()
        let owner = SpaceFixtureFullscreenTransitionOwner(
            scheduler: scheduler
        )
        let windows = [
            SpaceFixtureWindowSpy(
                plan: makeFullscreenTransitionPlan(index: 2)
            ),
            SpaceFixtureWindowSpy(
                plan: makeFullscreenTransitionPlan(index: 3)
            )
        ]
        var willEnterIndices: [Int] = []
        var evidence: [SpaceFixtureFullscreenTransitionEvidence] = []
        var completion: SpaceFixtureFullscreenTransitionCompletion?

        let generation = owner.start(
            windows: windows,
            initialDelayMilliseconds: 1_200,
            onWillEnter: { window, _, _ in
                willEnterIndices.append(window.plan.index)
            },
            onDidEnter: { evidence.append($0) },
            onComplete: { completion = $0 }
        )

        XCTAssertEqual(scheduler.scheduledDelays, [1_200])
        XCTAssertTrue(scheduler.fire(at: 0))
        XCTAssertEqual(willEnterIndices, [2])
        XCTAssertEqual(windows[0].enterFullScreenCallCount, 1)
        XCTAssertEqual(windows[1].enterFullScreenCallCount, 0)
        let firstCompletion =
            windows[0].enterFullScreenCompletions[0]

        XCTAssertTrue(windows[0].completeFullScreenTransition())

        XCTAssertEqual(scheduler.scheduledDelays, [1_200])
        XCTAssertEqual(willEnterIndices, [2, 3])
        XCTAssertEqual(windows[1].enterFullScreenCallCount, 1)
        XCTAssertEqual(
            evidence,
            [
                SpaceFixtureFullscreenTransitionEvidence(
                    observationGeneration: generation,
                    sequenceIndex: 0,
                    totalWindowCount: 2,
                    windowPlanIndex: 2
                )
            ]
        )

        firstCompletion()

        XCTAssertEqual(evidence.map(\.windowPlanIndex), [2])
        XCTAssertNil(completion)
        XCTAssertEqual(windows[1].enterFullScreenCallCount, 1)

        XCTAssertTrue(windows[1].completeFullScreenTransition())

        XCTAssertEqual(evidence.map(\.windowPlanIndex), [2, 3])
        XCTAssertEqual(
            completion,
            SpaceFixtureFullscreenTransitionCompletion(
                observationGeneration: generation,
                windowPlanIndices: [2, 3]
            )
        )
        XCTAssertFalse(owner.isRunning)
    }

    @MainActor
    func testSpaceFixtureFullscreenOwnerRejectsReplacedAndCancelledCallbacks() {
        let scheduler = ManualSpaceFixtureScheduler()
        let owner = SpaceFixtureFullscreenTransitionOwner(
            scheduler: scheduler
        )
        let firstWindow = SpaceFixtureWindowSpy(
            plan: makeFullscreenTransitionPlan(index: 1)
        )
        let secondWindow = SpaceFixtureWindowSpy(
            plan: makeFullscreenTransitionPlan(index: 2)
        )
        var enteredIndices: [Int] = []
        var completions: [SpaceFixtureFullscreenTransitionCompletion] = []

        let firstGeneration = owner.start(
            windows: [firstWindow],
            initialDelayMilliseconds: 500,
            onWillEnter: { _, _, _ in },
            onDidEnter: { enteredIndices.append($0.windowPlanIndex) },
            onComplete: { completions.append($0) }
        )
        let secondGeneration = owner.start(
            windows: [secondWindow],
            initialDelayMilliseconds: 700,
            onWillEnter: { _, _, _ in },
            onDidEnter: { enteredIndices.append($0.windowPlanIndex) },
            onComplete: { completions.append($0) }
        )

        XCTAssertGreaterThan(secondGeneration, firstGeneration)
        XCTAssertTrue(scheduler.token(at: 0).isCancelled)
        XCTAssertTrue(
            scheduler.fire(
                at: 0,
                includingCancelled: true
            )
        )
        XCTAssertEqual(firstWindow.enterFullScreenCallCount, 0)

        XCTAssertTrue(scheduler.fire(at: 1))
        XCTAssertEqual(secondWindow.enterFullScreenCallCount, 1)

        owner.cancel()

        XCTAssertTrue(
            secondWindow.enterFullScreenTokens[0].isCancelled
        )
        XCTAssertTrue(
            secondWindow.completeFullScreenTransition(
                includingCancelled: true
            )
        )
        XCTAssertTrue(enteredIndices.isEmpty)
        XCTAssertTrue(completions.isEmpty)
        XCTAssertFalse(owner.isRunning)
    }

    @MainActor
    func testSpaceFixtureFullscreenOwnerPressurePreservesCompletionOracle() {
        let scheduler = ManualSpaceFixtureScheduler()
        let owner = SpaceFixtureFullscreenTransitionOwner(
            scheduler: scheduler
        )
        var completedGenerations: [Int] = []
        let cycleCount = 500

        for cycle in 0..<cycleCount {
            let schedulerIndex = scheduler.scheduledCount
            let window = SpaceFixtureWindowSpy(
                plan: makeFullscreenTransitionPlan(index: cycle + 1)
            )
            let generation = owner.start(
                windows: [window],
                initialDelayMilliseconds: cycle,
                onWillEnter: { _, _, _ in },
                onDidEnter: { _ in },
                onComplete: {
                    completedGenerations.append(
                        $0.observationGeneration
                    )
                }
            )
            XCTAssertTrue(scheduler.fire(at: schedulerIndex))

            if cycle.isMultiple(of: 2) {
                owner.cancel()
                XCTAssertTrue(
                    window.completeFullScreenTransition(
                        includingCancelled: true
                    )
                )
                XCTAssertFalse(
                    completedGenerations.contains(generation)
                )
            } else {
                XCTAssertTrue(
                    window.completeFullScreenTransition()
                )
            }
        }

        XCTAssertEqual(
            completedGenerations.count,
            cycleCount / 2
        )
        XCTAssertEqual(
            completedGenerations,
            completedGenerations.sorted()
        )
        XCTAssertFalse(owner.isRunning)
    }

    private func makeFullscreenTransitionPlan(
        index: Int
    ) -> SpaceFixtureWindowPlan {
        SpaceFixtureWindowPlan(
            index: index,
            totalWindowCount: max(1, index),
            configuredTitle: "Fullscreen \(index)",
            fixtureAppName: "Fixture",
            title: "Fullscreen \(index)",
            frame: CGRect(
                x: 20 * index,
                y: 20 * index,
                width: 960,
                height: 640
            ),
            isFullscreenTarget: true,
            tabs: [],
            noisyCGSiblings: false
        )
    }
}
