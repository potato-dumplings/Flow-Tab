import XCTest

extension FlowTabTests {
    @MainActor
    func testDesktopRefocusRetriesRejectedRequestUntilExactReadback() {
        let scheduler = ManualSpaceFixtureScheduler()
        let owner = SpaceFixtureDesktopRefocusOwner(
            scheduler: scheduler
        )
        let window = Self.makeDesktopRefocusWindow()
        var triggerCallCount = 0
        var completions:
            [SpaceFixtureDesktopPresentationEvidence] = []

        _ = owner.start(
            window: window,
            watchdogMilliseconds: 15_000,
            retryIntervalMilliseconds: 100,
            trigger: {
                triggerCallCount += 1
                guard triggerCallCount == 3 else { return }
                window.desktopPresentationProbe.snapshot =
                    SpaceFixtureDesktopPresentationProbe
                        .presentedSnapshot(windowPlanIndex: 1)
            },
            onResolved: { completions.append($0) },
            onWatchdog: { _ in
                XCTFail("Repeated request must resolve.")
            }
        )

        XCTAssertEqual(triggerCallCount, 1)
        XCTAssertEqual(
            scheduler.scheduledDelays,
            [15_000, 100]
        )
        XCTAssertTrue(scheduler.fire(at: 1))
        XCTAssertEqual(triggerCallCount, 2)
        XCTAssertEqual(
            scheduler.scheduledDelays,
            [15_000, 100, 100]
        )
        XCTAssertTrue(scheduler.fire(at: 2))

        XCTAssertEqual(triggerCallCount, 3)
        XCTAssertEqual(
            completions.map(\.source),
            [.retryTriggerReturnReadback]
        )
        XCTAssertFalse(scheduler.fire(at: 0))
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testDesktopRefocusSlowSchedulingChangesOnlyResolutionTime() {
        let scheduler = ManualSpaceFixtureScheduler()
        let owner = SpaceFixtureDesktopRefocusOwner(
            scheduler: scheduler
        )
        let window = Self.makeDesktopRefocusWindow()
        var triggerCallCount = 0
        var completions:
            [SpaceFixtureDesktopPresentationEvidence] = []
        var failureCount = 0

        _ = owner.start(
            window: window,
            watchdogMilliseconds: 15_000,
            retryIntervalMilliseconds: 100,
            trigger: { triggerCallCount += 1 },
            onResolved: { completions.append($0) },
            onWatchdog: { _ in failureCount += 1 }
        )
        window.desktopPresentationProbe.snapshot =
            SpaceFixtureDesktopPresentationProbe
                .presentedSnapshot(windowPlanIndex: 1)

        XCTAssertTrue(scheduler.fire(at: 1))

        XCTAssertEqual(
            completions.map(\.source),
            [.retryReadback]
        )
        XCTAssertEqual(triggerCallCount, 1)
        XCTAssertEqual(failureCount, 0)
        XCTAssertNil(owner.lastFailure)
        XCTAssertFalse(scheduler.fire(at: 0))
    }

    @MainActor
    func testDesktopRefocusReplacementCancellationPressureRejectsLateWork() {
        let scheduler = ManualSpaceFixtureScheduler()
        let owner = SpaceFixtureDesktopRefocusOwner(
            scheduler: scheduler
        )
        let window = Self.makeDesktopRefocusWindow()
        var completedGenerations: [Int] = []
        var failureCount = 0

        for cycle in 0..<500 {
            window.desktopPresentationProbe.snapshot =
                SpaceFixtureDesktopPresentationProbe
                    .waitingSnapshot(windowPlanIndex: 1)
            let generation = owner.start(
                window: window,
                watchdogMilliseconds: 15_000,
                retryIntervalMilliseconds: 100,
                trigger: {},
                onResolved: {
                    completedGenerations.append(
                        $0.observationGeneration
                    )
                },
                onWatchdog: { _ in failureCount += 1 }
            )
            if cycle.isMultiple(of: 2) {
                window.desktopPresentationProbe.snapshot =
                    SpaceFixtureDesktopPresentationProbe
                        .presentedSnapshot(
                            windowPlanIndex: 1
                        )
                window.desktopPresentationProbe.emit(
                    .activeSpaceDidChange
                )
                XCTAssertEqual(
                    completedGenerations.last,
                    generation
                )
            }
        }
        owner.cancel()
        for index in 0..<scheduler.scheduledCount {
            _ = scheduler.fire(
                at: index,
                includingCancelled: true
            )
        }
        window.desktopPresentationProbe.emit(
            .windowDidBecomeKey,
            includingCancelled: true
        )

        XCTAssertEqual(completedGenerations.count, 250)
        XCTAssertEqual(
            completedGenerations,
            completedGenerations.sorted()
        )
        XCTAssertEqual(failureCount, 0)
        XCTAssertFalse(owner.isObserving)
        XCTAssertEqual(
            window.desktopPresentationProbe
                .activeObservationCount,
            0
        )
    }
}
