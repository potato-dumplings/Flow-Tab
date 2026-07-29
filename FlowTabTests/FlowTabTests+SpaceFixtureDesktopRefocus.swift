import CoreGraphics
import XCTest

extension FlowTabTests {
    @MainActor
    func testDesktopRefocusResolvesInitialReadbackAfterInstallingObserver() {
        let scheduler = ManualSpaceFixtureScheduler()
        let owner = SpaceFixtureDesktopRefocusOwner(
            scheduler: scheduler
        )
        let window = Self.makeDesktopRefocusWindow()
        window.desktopPresentationProbe.snapshot =
            SpaceFixtureDesktopPresentationProbe
                .presentedSnapshot(windowPlanIndex: 1)
        var triggerCallCount = 0
        var completions:
            [SpaceFixtureDesktopPresentationEvidence] = []

        let generation = owner.start(
            window: window,
            watchdogMilliseconds: 15_000,
            retryIntervalMilliseconds: 100,
            trigger: { triggerCallCount += 1 },
            onResolved: { completions.append($0) },
            onWatchdog: { _ in
                XCTFail("Initial presentation must resolve.")
            }
        )

        XCTAssertEqual(
            completions.map(\.source),
            [.initialReadback]
        )
        XCTAssertEqual(
            completions.first?.observationGeneration,
            generation
        )
        XCTAssertEqual(
            window.desktopPresentationProbe.observeCallCount,
            1
        )
        XCTAssertEqual(
            window.desktopPresentationProbe.activeObservationCount,
            0
        )
        XCTAssertEqual(triggerCallCount, 0)
        XCTAssertEqual(scheduler.scheduledCount, 0)
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testDesktopRefocusInstallsObserverBeforeTriggerAndResolvesEvent() {
        let scheduler = ManualSpaceFixtureScheduler()
        let owner = SpaceFixtureDesktopRefocusOwner(
            scheduler: scheduler
        )
        let window = Self.makeDesktopRefocusWindow()
        var observerWasActiveAtTrigger = false
        var completions:
            [SpaceFixtureDesktopPresentationEvidence] = []

        _ = owner.start(
            window: window,
            watchdogMilliseconds: 15_000,
            retryIntervalMilliseconds: 100,
            trigger: {
                observerWasActiveAtTrigger =
                    window.desktopPresentationProbe
                        .activeObservationCount == 1
            },
            onResolved: { completions.append($0) },
            onWatchdog: { _ in
                XCTFail("Matching event must resolve.")
            }
        )

        XCTAssertTrue(observerWasActiveAtTrigger)
        XCTAssertEqual(
            scheduler.scheduledDelays,
            [15_000, 100]
        )
        window.desktopPresentationProbe.snapshot =
            SpaceFixtureDesktopPresentationSnapshot(
                windowPlanIndex: 1,
                windowNumber: 1,
                applicationIsActive: true,
                isKeyWindow: true,
                isMainWindow: false,
                isVisible: true,
                isMiniaturized: false,
                isOnActiveSpace: true,
                isOcclusionVisible: true,
                isCGWindowOnScreen: true
            )
        window.desktopPresentationProbe.emit(
            .windowDidBecomeKey
        )
        XCTAssertTrue(completions.isEmpty)

        window.desktopPresentationProbe.snapshot =
            SpaceFixtureDesktopPresentationProbe
                .presentedSnapshot(windowPlanIndex: 1)
        window.desktopPresentationProbe.emit(
            .windowDidChangeOcclusion
        )

        XCTAssertEqual(
            completions.map(\.source),
            [.windowDidChangeOcclusion]
        )
        XCTAssertEqual(
            window.desktopPresentationProbe.activeObservationCount,
            0
        )
        XCTAssertFalse(scheduler.fire(at: 0))
        XCTAssertFalse(scheduler.fire(at: 1))
    }

    @MainActor
    func testDesktopRefocusClosesSynchronousEventGapWithTriggerReturnReadback() {
        let scheduler = ManualSpaceFixtureScheduler()
        let owner = SpaceFixtureDesktopRefocusOwner(
            scheduler: scheduler
        )
        let window = Self.makeDesktopRefocusWindow()
        var completions:
            [SpaceFixtureDesktopPresentationEvidence] = []

        _ = owner.start(
            window: window,
            watchdogMilliseconds: 15_000,
            retryIntervalMilliseconds: 100,
            trigger: {
                window.desktopPresentationProbe.snapshot =
                    SpaceFixtureDesktopPresentationProbe
                        .presentedSnapshot(
                            windowPlanIndex: 1
                        )
            },
            onResolved: { completions.append($0) },
            onWatchdog: { _ in
                XCTFail("Trigger-return readback must resolve.")
            }
        )

        XCTAssertEqual(
            completions.map(\.source),
            [.triggerReturnReadback]
        )
        XCTAssertFalse(scheduler.fire(at: 0))
    }

    @MainActor
    func testDesktopRefocusRejectsStaleIdentityAndDuplicateEvidence() {
        let scheduler = ManualSpaceFixtureScheduler()
        let owner = SpaceFixtureDesktopRefocusOwner(
            scheduler: scheduler
        )
        let window = Self.makeDesktopRefocusWindow()
        var completions:
            [SpaceFixtureDesktopPresentationEvidence] = []
        let generation = owner.start(
            window: window,
            watchdogMilliseconds: 15_000,
            retryIntervalMilliseconds: 100,
            trigger: {},
            onResolved: { completions.append($0) },
            onWatchdog: { _ in
                XCTFail("Matching evidence must resolve.")
            }
        )

        window.desktopPresentationProbe.snapshot =
            SpaceFixtureDesktopPresentationProbe
                .presentedSnapshot(windowPlanIndex: 1)
        XCTAssertFalse(owner.observe(
            source: .windowDidBecomeMain,
            observationGeneration: generation - 1,
            windowPlanIndex: 1
        ))
        XCTAssertFalse(owner.observe(
            source: .windowDidBecomeMain,
            observationGeneration: generation,
            windowPlanIndex: 2
        ))
        window.desktopPresentationProbe.snapshot =
            SpaceFixtureDesktopPresentationProbe
                .presentedSnapshot(windowPlanIndex: 2)
        window.desktopPresentationProbe.emit(
            .windowDidBecomeMain
        )
        XCTAssertTrue(completions.isEmpty)
        window.desktopPresentationProbe.snapshot =
            SpaceFixtureDesktopPresentationProbe
                .presentedSnapshot(windowPlanIndex: 1)
        window.desktopPresentationProbe.emit(
            .windowDidBecomeMain
        )
        XCTAssertFalse(owner.observe(
            source: .windowDidBecomeMain,
            observationGeneration: generation,
            windowPlanIndex: 1
        ))

        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(
            completions.first?.snapshot.windowPlanIndex,
            1
        )
    }

    @MainActor
    func testDesktopRefocusWatchdogReportsLastAndFinalReadback() {
        let scheduler = ManualSpaceFixtureScheduler()
        let owner = SpaceFixtureDesktopRefocusOwner(
            scheduler: scheduler
        )
        let window = Self.makeDesktopRefocusWindow()
        var failures:
            [SpaceFixtureDesktopRefocusWatchdogFailure] = []

        _ = owner.start(
            window: window,
            watchdogMilliseconds: 15_000,
            retryIntervalMilliseconds: 100,
            trigger: {},
            onResolved: { _ in
                XCTFail("Incomplete presentation must fail.")
            },
            onWatchdog: { failures.append($0) }
        )
        window.desktopPresentationProbe.snapshot =
            SpaceFixtureDesktopPresentationSnapshot(
                windowPlanIndex: 1,
                windowNumber: 1,
                applicationIsActive: true,
                isKeyWindow: false,
                isMainWindow: false,
                isVisible: true,
                isMiniaturized: false,
                isOnActiveSpace: false,
                isOcclusionVisible: false,
                isCGWindowOnScreen: false
            )
        window.desktopPresentationProbe.emit(
            .applicationDidBecomeActive
        )
        window.desktopPresentationProbe.snapshot =
            SpaceFixtureDesktopPresentationSnapshot(
                windowPlanIndex: 1,
                windowNumber: 1,
                applicationIsActive: true,
                isKeyWindow: false,
                isMainWindow: false,
                isVisible: true,
                isMiniaturized: false,
                isOnActiveSpace: true,
                isOcclusionVisible: false,
                isCGWindowOnScreen: false
            )

        XCTAssertTrue(scheduler.fire(at: 0))

        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(
            failures.first?.lastEvidence.source,
            .applicationDidBecomeActive
        )
        XCTAssertEqual(
            failures.first?.finalEvidence.source,
            .watchdogReadback
        )
        XCTAssertEqual(
            failures.first?.finalEvidence.snapshot
                .unmetConditions,
            [
                "windowKey",
                "windowMain",
                "windowOcclusionVisible",
                "exactCGWindowOnScreen"
            ]
        )
        XCTAssertTrue(
            failures.first?.logFields.contains(
                "condition=desktopAnchorPresented"
            ) == true
        )
        XCTAssertEqual(owner.lastFailure, failures.first)
        XCTAssertEqual(
            window.desktopPresentationProbe.activeObservationCount,
            0
        )
    }

}
