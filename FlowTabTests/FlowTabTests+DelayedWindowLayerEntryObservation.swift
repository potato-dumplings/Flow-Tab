import XCTest
@testable import FlowTab

extension FlowTabTests {
    @MainActor
    func testDelayedWindowLayerEntryInitialProjectionWaitsForConfiguredDeadline() {
        let scheduler =
            ManualDelayedWindowLayerEntryScheduler()
        let owner = DelayedWindowLayerEntryObservationOwner(
            scheduler: scheduler
        )
        let snapshot = Self.delayedWindowLayerSnapshot(
            windowCount: 3,
            projectionGeneration: 7
        )
        var completions: [DelayedWindowLayerEntryEvidence] = []

        _ = owner.start(
            targetAppID: "app-a",
            presentationGeneration: 11,
            delay: 0.75,
            readback: { snapshot },
            onReady: { completions.append($0) }
        )

        XCTAssertTrue(completions.isEmpty)
        XCTAssertEqual(scheduler.scheduledIntervals, [0.75])
        XCTAssertEqual(scheduler.pendingCount, 1)

        XCTAssertTrue(scheduler.fireNextDeadline())

        XCTAssertEqual(
            completions.map(\.source),
            [.deadlineReadback]
        )
        XCTAssertEqual(
            completions.first?.snapshot.selectedWindowCount,
            3
        )
        XCTAssertFalse(owner.isObserving)
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    @MainActor
    func testDelayedWindowLayerEntryDeadlineWaitsForMatchingProjectionEvidence() {
        let scheduler =
            ManualDelayedWindowLayerEntryScheduler()
        let owner = DelayedWindowLayerEntryObservationOwner(
            scheduler: scheduler
        )
        var snapshot = Self.delayedWindowLayerSnapshot(
            windowCount: 0,
            projectionGeneration: 13,
            presentationGeneration: 17
        )
        var completions: [DelayedWindowLayerEntryEvidence] = []
        let generation = owner.start(
            targetAppID: "app-a",
            presentationGeneration: 17,
            delay: 0.3,
            readback: { snapshot },
            onReady: { completions.append($0) }
        )

        XCTAssertTrue(scheduler.fireNextDeadline())
        XCTAssertTrue(owner.isObserving)
        XCTAssertTrue(completions.isEmpty)
        XCTAssertEqual(scheduler.pendingCount, 0)

        snapshot = Self.delayedWindowLayerSnapshot(
            windowCount: 2,
            projectionGeneration: 14,
            presentationGeneration: 17
        )
        XCTAssertFalse(
            owner.observe(
                source: .currentAppWindowProjectionUpdated,
                eventAppID: "app-b",
                observationGeneration: generation,
                presentationGeneration: 17
            )
        )
        XCTAssertTrue(completions.isEmpty)
        XCTAssertTrue(
            owner.observe(
                source: .currentAppWindowProjectionUpdated,
                eventAppID: "app-a",
                observationGeneration: generation,
                presentationGeneration: 17
            )
        )

        XCTAssertEqual(
            completions.map(\.source),
            [.currentAppWindowProjectionUpdated]
        )
        XCTAssertEqual(
            completions.first?.baselineProjectionGeneration,
            13
        )
        XCTAssertEqual(
            completions.first?.snapshot.projectionGeneration,
            14
        )
    }

    @MainActor
    func testDelayedWindowLayerEntryDelayedSchedulerUsesClockAndProjectionReadback() {
        let scheduler =
            ManualDelayedWindowLayerEntryScheduler()
        let owner = DelayedWindowLayerEntryObservationOwner(
            scheduler: scheduler
        )
        var snapshot = Self.delayedWindowLayerSnapshot(
            windowCount: 0,
            projectionGeneration: 21,
            presentationGeneration: 23
        )
        var completions: [DelayedWindowLayerEntryEvidence] = []
        let generation = owner.start(
            targetAppID: "app-a",
            presentationGeneration: 23,
            delay: 0.5,
            readback: { snapshot },
            onReady: { completions.append($0) }
        )

        snapshot = Self.delayedWindowLayerSnapshot(
            windowCount: 5,
            projectionGeneration: 22,
            presentationGeneration: 23
        )
        scheduler.advance(byMilliseconds: 800)
        XCTAssertTrue(
            owner.observe(
                source: .appSwitcherProjectionUpdated,
                observationGeneration: generation,
                presentationGeneration: 23
            )
        )

        XCTAssertEqual(
            completions.map(\.source),
            [.appSwitcherProjectionUpdated]
        )
        XCTAssertEqual(
            completions.first?.overshootMilliseconds,
            300
        )
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertFalse(scheduler.fireNextDeadline())
    }

    @MainActor
    func testDelayedWindowLayerEntryRejectsStaleDuplicateAndReplacedEvidence() {
        let scheduler =
            ManualDelayedWindowLayerEntryScheduler()
        let owner = DelayedWindowLayerEntryObservationOwner(
            scheduler: scheduler
        )
        var snapshot = Self.delayedWindowLayerSnapshot(
            appID: "app-a",
            windowCount: 2,
            projectionGeneration: 31,
            presentationGeneration: 37
        )
        var completions: [DelayedWindowLayerEntryEvidence] = []
        let staleGeneration = owner.start(
            targetAppID: "app-a",
            presentationGeneration: 37,
            delay: 1,
            readback: { snapshot },
            onReady: { completions.append($0) }
        )
        snapshot = Self.delayedWindowLayerSnapshot(
            appID: "app-b",
            windowCount: 2,
            projectionGeneration: 32,
            presentationGeneration: 41
        )
        let currentGeneration = owner.start(
            targetAppID: "app-b",
            presentationGeneration: 41,
            delay: 0,
            readback: { snapshot },
            onReady: { completions.append($0) }
        )

        XCTAssertGreaterThan(
            currentGeneration,
            staleGeneration
        )
        XCTAssertFalse(
            owner.observe(
                source: .sessionLayoutChanged,
                observationGeneration: staleGeneration,
                presentationGeneration: 37
            )
        )
        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(completions.first?.targetAppID, "app-b")
        XCTAssertFalse(
            owner.observe(
                source: .sessionLayoutChanged,
                observationGeneration: currentGeneration,
                presentationGeneration: 41
            )
        )
        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    @MainActor
    func testDelayedWindowLayerEntryEarlyDeadlineReschedulesRemainingDuration() {
        let scheduler =
            ManualDelayedWindowLayerEntryScheduler()
        let owner = DelayedWindowLayerEntryObservationOwner(
            scheduler: scheduler
        )
        let snapshot = Self.delayedWindowLayerSnapshot(
            windowCount: 2,
            projectionGeneration: 43
        )
        var completionCount = 0
        _ = owner.start(
            targetAppID: "app-a",
            presentationGeneration: 11,
            delay: 1,
            readback: { snapshot },
            onReady: { _ in completionCount += 1 }
        )

        XCTAssertTrue(
            scheduler.fireNextDeadline(advancingClock: false)
        )
        XCTAssertEqual(completionCount, 0)
        XCTAssertEqual(scheduler.pendingCount, 1)
        XCTAssertEqual(scheduler.scheduledIntervals, [1, 1])

        XCTAssertTrue(scheduler.fireNextDeadline())
        XCTAssertEqual(completionCount, 1)
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    @MainActor
    func testDelayedWindowLayerEntryReplacementAndCancellationPressure() {
        let scheduler =
            ManualDelayedWindowLayerEntryScheduler()
        let owner = DelayedWindowLayerEntryObservationOwner(
            scheduler: scheduler
        )
        var completionCount = 0

        for index in 0..<2_000 {
            let appID = "app-\(index)"
            let snapshot = Self.delayedWindowLayerSnapshot(
                appID: appID,
                windowCount: 2,
                projectionGeneration: UInt64(index),
                presentationGeneration: index
            )
            _ = owner.start(
                targetAppID: appID,
                presentationGeneration: index,
                delay: 1,
                readback: { snapshot },
                onReady: { _ in completionCount += 1 }
            )
        }

        XCTAssertEqual(scheduler.pendingCount, 1)
        owner.cancel()
        scheduler.fireAllDeadlines()

        XCTAssertEqual(completionCount, 0)
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertFalse(owner.isObserving)
    }

    private static func delayedWindowLayerSnapshot(
        appID: String = "app-a",
        windowCount: Int,
        projectionGeneration: UInt64,
        presentationGeneration: Int = 11
    ) -> DelayedWindowLayerEntrySnapshot {
        DelayedWindowLayerEntrySnapshot(
            presentationGeneration: presentationGeneration,
            selectedAppID: appID,
            selectedWindowCount: windowCount,
            projectionGeneration: projectionGeneration,
            isPanelPresented: true,
            isAppLayer: true,
            isSearchActive: false,
            canAutoEnterWindowLayer: windowCount >= 2
        )
    }
}
