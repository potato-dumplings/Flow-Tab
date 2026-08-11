import XCTest
@testable import FlowTab

extension FlowTabTests {
    @MainActor
    func testUITestInitialPresentationResolvesFromInitialAndEmptyReadbacks() {
        let scheduler =
            ManualInitialPresentationScheduler()
        var snapshot =
            initialPresentationSnapshot(
                generation: 1,
                itemIDs: ["app-a", "app-b"]
            )
        var attempts = 0
        var resolutions:
            [FlowTabUITestInitialPresentationEvidence] = []
        let owner = makeInitialPresentationOwner(
            scheduler: scheduler,
            readback: { snapshot }
        )

        owner.start(
            watchdogInterval: 3,
            triggerReadiness: {
                XCTFail(
                    "Initial complete evidence must not request readiness."
                )
            },
            attemptPresentation: { candidate in
                attempts += 1
                return .init(
                    didPresent: true,
                    sessionItemIDs: candidate.itemIDs,
                    searchIsActiveOrPending: false
                )
            },
            cancelPresentation: {},
            onResolved: { resolutions.append($0) },
            onWatchdog: {
                XCTFail($0.logFields)
            }
        )

        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(
            resolutions.first?.resolution,
            .presented
        )
        XCTAssertEqual(
            resolutions.first?.source,
            .initialReadback
        )
        XCTAssertFalse(owner.isObserving)
        XCTAssertTrue(scheduler.tokens.isEmpty)

        snapshot = initialPresentationSnapshot(
            generation: 2,
            itemIDs: []
        )
        owner.start(
            watchdogInterval: 3,
            triggerReadiness: {
                XCTFail(
                    "Complete empty evidence is terminal."
                )
            },
            attemptPresentation: { _ in
                attempts += 1
                return .init(
                    didPresent: false,
                    sessionItemIDs: [],
                    searchIsActiveOrPending: false
                )
            },
            cancelPresentation: {},
            onResolved: { resolutions.append($0) },
            onWatchdog: {
                XCTFail($0.logFields)
            }
        )

        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(
            resolutions.last?.resolution,
            .noContent
        )
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testUITestInitialPresentationObservesBeforeReadinessTrigger() {
        let center = NotificationCenter()
        let object = NSObject()
        let scheduler =
            ManualInitialPresentationScheduler()
        var snapshot = initialPresentationSnapshot(
            generation: 1,
            isComplete: false,
            itemIDs: ["app-a"]
        )
        var owner:
            FlowTabUITestInitialPresentationObservationOwner!
        var resolutions:
            [FlowTabUITestInitialPresentationEvidence] = []
        owner = makeInitialPresentationOwner(
            notificationCenter: center,
            notificationObject: object,
            scheduler: scheduler,
            readback: { snapshot }
        )

        owner.start(
            watchdogInterval: 3,
            triggerReadiness: {
                XCTAssertTrue(owner.isObserving)
                snapshot = self.initialPresentationSnapshot(
                    generation: 1,
                    itemIDs: ["app-a", "app-b"]
                )
                center.post(
                    name:
                        .runtimeAppSwitcherProjectionDidUpdate,
                    object: object
                )
            },
            attemptPresentation: { candidate in
                .init(
                    didPresent: true,
                    sessionItemIDs: candidate.itemIDs,
                    searchIsActiveOrPending: false
                )
            },
            cancelPresentation: {},
            onResolved: { resolutions.append($0) },
            onWatchdog: {
                XCTFail($0.logFields)
            }
        )

        XCTAssertEqual(resolutions.count, 1)
        XCTAssertEqual(
            resolutions.first?.source,
            .appSwitcherProjectionDidUpdate
        )
        XCTAssertEqual(
            resolutions.first?
                .baseline.sourceGeneration,
            RuntimeReadModelGeneration(projection: 1)
        )
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testUITestInitialPresentationRequiresFreshMatchingAttempt() {
        let scheduler =
            ManualInitialPresentationScheduler()
        var snapshot = initialPresentationSnapshot(
            generation: 1,
            isComplete: false,
            itemIDs: ["app-a"]
        )
        var attempts = 0
        var cancellations = 0
        var resolutions:
            [FlowTabUITestInitialPresentationEvidence] = []
        let owner = makeInitialPresentationOwner(
            scheduler: scheduler,
            readback: { snapshot }
        )
        let generation = owner.start(
            watchdogInterval: 3,
            triggerReadiness: {},
            attemptPresentation: { candidate in
                attempts += 1
                if attempts == 2 {
                    snapshot =
                        self.initialPresentationSnapshot(
                            generation: 4,
                            itemIDs: ["other-app"]
                        )
                } else if attempts == 3 {
                    snapshot =
                        self.initialPresentationSnapshot(
                            generation: 6,
                            isComplete: false,
                            itemIDs: candidate.itemIDs
                        )
                }
                return .init(
                    didPresent: true,
                    sessionItemIDs:
                        attempts == 1
                        ? ["wrong-app"]
                        : candidate.itemIDs,
                    searchIsActiveOrPending: false
                )
            },
            cancelPresentation: {
                cancellations += 1
            },
            onResolved: { resolutions.append($0) },
            onWatchdog: {
                XCTFail($0.logFields)
            }
        )

        XCTAssertFalse(
            owner.observe(
                source: .appSwitcherProjectionDidUpdate,
                observationGeneration:
                    generation &+ 1
            )
        )
        snapshot = initialPresentationSnapshot(
            generation: 0,
            itemIDs: ["app-a", "app-b"]
        )
        XCTAssertFalse(
            owner.observe(
                source: .appSwitcherProjectionDidUpdate,
                observationGeneration: generation
            )
        )
        XCTAssertEqual(attempts, 0)
        snapshot = initialPresentationSnapshot(
            generation: 2,
            itemIDs: ["app-a", "app-b"]
        )
        XCTAssertFalse(
            owner.observe(
                source: .appSwitcherProjectionDidUpdate,
                observationGeneration: generation
            )
        )
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(cancellations, 1)
        XCTAssertFalse(
            owner.observe(
                source: .appSwitcherProjectionDidUpdate,
                observationGeneration: generation
            )
        )
        XCTAssertEqual(attempts, 1)

        snapshot = initialPresentationSnapshot(
            generation: 3,
            itemIDs: ["app-a", "app-b"]
        )
        XCTAssertFalse(
            owner.observe(
                source: .appSwitcherProjectionDidUpdate,
                observationGeneration: generation
            )
        )
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(cancellations, 2)
        snapshot = initialPresentationSnapshot(
            generation: 3,
            itemIDs: ["app-a", "app-b"]
        )
        XCTAssertFalse(
            owner.observe(
                source: .appSwitcherProjectionDidUpdate,
                observationGeneration: generation
            )
        )
        XCTAssertEqual(attempts, 2)

        snapshot = initialPresentationSnapshot(
            generation: 5,
            itemIDs: ["app-a", "app-b"]
        )
        XCTAssertTrue(
            owner.observe(
                source: .appSwitcherProjectionDidUpdate,
                observationGeneration: generation
            )
        )
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(cancellations, 2)
        XCTAssertEqual(resolutions.count, 1)
        XCTAssertEqual(
            resolutions.first?
                .postPresentationReadback?
                .sourceGeneration,
            RuntimeReadModelGeneration(projection: 6)
        )
        XCTAssertEqual(
            resolutions.first?
                .postPresentationReadback?
                .projectionIsComplete,
            false
        )
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testUITestInitialPresentationWatchdogUsesFinalReadback() {
        let scheduler =
            ManualInitialPresentationScheduler()
        var snapshot = initialPresentationSnapshot(
            generation: 1,
            isComplete: false,
            itemIDs: ["app-a"]
        )
        var failures:
            [FlowTabUITestInitialPresentationWatchdogFailure]
                = []
        var resolutions:
            [FlowTabUITestInitialPresentationEvidence] = []
        let owner = makeInitialPresentationOwner(
            scheduler: scheduler,
            readback: { snapshot }
        )
        owner.start(
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
            onResolved: { resolutions.append($0) },
            onWatchdog: { failures.append($0) }
        )
        let firstWatchdog = scheduler.tokens.last!
        snapshot = initialPresentationSnapshot(
            generation: 2,
            isComplete: false,
            itemIDs: ["app-a"]
        )
        scheduler.fire(firstWatchdog)

        XCTAssertEqual(failures.count, 1)
        XCTAssertTrue(
            failures[0].logFields
                .contains("projectionComplete")
        )
        XCTAssertTrue(resolutions.isEmpty)
        XCTAssertFalse(owner.isObserving)

        snapshot = initialPresentationSnapshot(
            generation: 3,
            isComplete: false,
            itemIDs: ["app-a"]
        )
        owner.start(
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
            onResolved: { resolutions.append($0) },
            onWatchdog: { failures.append($0) }
        )
        let secondWatchdog = scheduler.tokens.last!
        snapshot = initialPresentationSnapshot(
            generation: 4,
            itemIDs: ["app-a"]
        )
        scheduler.fire(secondWatchdog)

        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(
            resolutions.last?.source,
            .watchdogReadback
        )
        XCTAssertEqual(
            resolutions.last?.resolution,
            .presented
        )
    }

    @MainActor
    func testUITestInitialPresentationInputReadinessResolvesFromInitialLaterGeneration() {
        let scheduler = ManualInitialPresentationScheduler()
        let baseline = initialPresentationSnapshot(
            generation: 1,
            itemIDs: ["app-a", "app-b"]
        )
        var snapshot =
            initialPresentationInputReadinessSnapshot(
                generation: 2
            )
        var triggerCount = 0
        var resolutions:
            [FlowTabUITestInitialPresentationInputReadinessEvidence]
                = []
        let owner = makeInitialPresentationInputReadinessOwner(
            scheduler: scheduler,
            readback: { snapshot }
        )

        owner.start(
            baseline: baseline,
            expectedPresentationGeneration: 3,
            expectedSessionItemIDs: ["app-a", "app-b"],
            expectedSelectedAppID: "app-a",
            watchdogInterval:
                FlowTabUITestInitialPresentationInputReadinessPolicy
                    .watchdog,
            triggerReadiness: { triggerCount += 1 },
            onResolved: { resolutions.append($0) },
            onWatchdog: { XCTFail($0.logFields) }
        )

        XCTAssertEqual(triggerCount, 0)
        XCTAssertEqual(resolutions.count, 1)
        XCTAssertEqual(
            resolutions.first?.source,
            .initialReadback
        )
        XCTAssertTrue(resolutions.first?.isSatisfied == true)
        XCTAssertFalse(owner.isObserving)
        XCTAssertTrue(scheduler.tokens.isEmpty)
        snapshot = initialPresentationInputReadinessSnapshot(
            generation: 3
        )
        XCTAssertEqual(resolutions.count, 1)
    }

    @MainActor
    func testUITestInitialPresentationInputReadinessUsesScheduledConditionReadback() {
        let scheduler = ManualInitialPresentationScheduler()
        let baseline = initialPresentationSnapshot(
            generation: 1,
            itemIDs: ["app-a", "app-b"]
        )
        var snapshot =
            initialPresentationInputReadinessSnapshot(
                generation: 1
            )
        var triggerCount = 0
        var resolutions:
            [FlowTabUITestInitialPresentationInputReadinessEvidence]
                = []
        var owner:
            FlowTabUITestInitialPresentationInputReadinessObservationOwner!
        owner = makeInitialPresentationInputReadinessOwner(
            scheduler: scheduler,
            readback: { snapshot }
        )

        owner.start(
            baseline: baseline,
            expectedPresentationGeneration: 3,
            expectedSessionItemIDs: ["app-a", "app-b"],
            expectedSelectedAppID: "app-a",
            watchdogInterval:
                FlowTabUITestInitialPresentationInputReadinessPolicy
                    .watchdog,
            triggerReadiness: {
                XCTAssertTrue(owner.isObserving)
                triggerCount += 1
                snapshot = self
                    .initialPresentationInputReadinessSnapshot(
                        generation: 2,
                        activeSpaceTransitionPending: true,
                        applicationActivationSuppressed: true
                    )
            },
            onResolved: { resolutions.append($0) },
            onWatchdog: { XCTFail($0.logFields) }
        )

        XCTAssertEqual(triggerCount, 1)
        XCTAssertTrue(owner.isObserving)
        XCTAssertEqual(scheduler.tokens.count, 2)
        let firstRetry = scheduler.tokens.first {
            $0.interval
                == FlowTabUITestInitialPresentationInputReadinessPolicy
                    .readbackCadence
        }!
        scheduler.fire(firstRetry)
        XCTAssertTrue(resolutions.isEmpty)

        let secondRetry = scheduler.tokens.last {
            $0.interval
                == FlowTabUITestInitialPresentationInputReadinessPolicy
                    .readbackCadence
                && !$0.isCancelled
        }!
        snapshot = initialPresentationInputReadinessSnapshot(
            generation: 2,
            panelVisibilityRecoveryPending: true
        )
        scheduler.fire(secondRetry)
        XCTAssertTrue(resolutions.isEmpty)

        let finalRetry = scheduler.tokens.last {
            $0.interval
                == FlowTabUITestInitialPresentationInputReadinessPolicy
                    .readbackCadence
                && !$0.isCancelled
        }!
        snapshot = initialPresentationInputReadinessSnapshot(
            generation: 2
        )
        scheduler.fire(finalRetry)

        XCTAssertEqual(resolutions.count, 1)
        XCTAssertEqual(
            resolutions.first?.source,
            .scheduledReadback
        )
        XCTAssertFalse(owner.isObserving)
        XCTAssertTrue(
            scheduler.tokens
                .filter {
                    $0.interval
                        == FlowTabUITestInitialPresentationInputReadinessPolicy
                            .watchdog
                }
                .allSatisfy(\.isCancelled)
        )
    }

    @MainActor
    func testUITestInitialPresentationInputReadinessAcceptsLaterExactTargetDuringUnrelatedRepair() {
        let scheduler = ManualInitialPresentationScheduler()
        let baseline = initialPresentationSnapshot(
            generation: 1,
            itemIDs: ["app-a", "app-b"]
        )
        var resolutions:
            [FlowTabUITestInitialPresentationInputReadinessEvidence]
                = []
        let owner = makeInitialPresentationInputReadinessOwner(
            scheduler: scheduler,
            readback: {
                self.initialPresentationInputReadinessSnapshot(
                    generation: 2,
                    projectionIsComplete: false
                )
            }
        )

        owner.start(
            baseline: baseline,
            expectedPresentationGeneration: 3,
            expectedSessionItemIDs: ["app-a", "app-b"],
            expectedSelectedAppID: "app-a",
            watchdogInterval:
                FlowTabUITestInitialPresentationInputReadinessPolicy
                    .watchdog,
            triggerReadiness: {},
            onResolved: { resolutions.append($0) },
            onWatchdog: { XCTFail($0.logFields) }
        )

        XCTAssertEqual(resolutions.count, 1)
        XCTAssertEqual(
            resolutions.first?.source,
            .initialReadback
        )
        XCTAssertEqual(
            resolutions.first?.snapshot.projection
                .projectionIsComplete,
            false
        )
        XCTAssertTrue(resolutions.first?.isSatisfied == true)
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testUITestInitialPresentationInputReadinessRejectsStaleEventsAndCancellation()
        async
    {
        let center = NotificationCenter()
        let object = NSObject()
        let scheduler = ManualInitialPresentationScheduler()
        let baseline = initialPresentationSnapshot(
            generation: 1,
            itemIDs: ["app-a", "app-b"]
        )
        var snapshot =
            initialPresentationInputReadinessSnapshot(
                generation: 1
            )
        var resolutions:
            [FlowTabUITestInitialPresentationInputReadinessEvidence]
                = []
        let owner = makeInitialPresentationInputReadinessOwner(
            notificationCenter: center,
            notificationObject: object,
            scheduler: scheduler,
            readback: { snapshot }
        )
        let generation = owner.start(
            baseline: baseline,
            expectedPresentationGeneration: 3,
            expectedSessionItemIDs: ["app-a", "app-b"],
            expectedSelectedAppID: "app-a",
            watchdogInterval:
                FlowTabUITestInitialPresentationInputReadinessPolicy
                    .watchdog,
            triggerReadiness: {},
            onResolved: { resolutions.append($0) },
            onWatchdog: { XCTFail($0.logFields) }
        )

        snapshot = initialPresentationInputReadinessSnapshot(
            generation: 2
        )
        XCTAssertFalse(
            owner.observe(
                source: .projectionUpdateReadback,
                observationGeneration: generation &+ 1
            )
        )
        center.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: object
        )
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(resolutions.count, 1)
        XCTAssertEqual(
            resolutions.first?.source,
            .projectionUpdateReadback
        )
        XCTAssertFalse(
            owner.observe(
                source: .projectionUpdateReadback,
                observationGeneration: generation
            )
        )

        snapshot = initialPresentationInputReadinessSnapshot(
            generation: 2,
            activeSpaceTransitionPending: true
        )
        let cancelledGeneration = owner.start(
            baseline: snapshot.projection,
            expectedPresentationGeneration: 3,
            expectedSessionItemIDs: ["app-a", "app-b"],
            expectedSelectedAppID: "app-a",
            watchdogInterval:
                FlowTabUITestInitialPresentationInputReadinessPolicy
                    .watchdog,
            triggerReadiness: {},
            onResolved: { resolutions.append($0) },
            onWatchdog: { XCTFail($0.logFields) }
        )
        let pendingTokens = scheduler.tokens.filter {
            !$0.isCancelled
        }
        owner.cancel()
        snapshot = initialPresentationInputReadinessSnapshot(
            generation: 3
        )
        center.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: object
        )
        XCTAssertFalse(
            owner.observe(
                source: .projectionUpdateReadback,
                observationGeneration: cancelledGeneration
            )
        )
        for token in pendingTokens {
            scheduler.fire(token, includingCancelled: true)
        }
        await Task.yield()

        XCTAssertEqual(resolutions.count, 1)
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testUITestInitialPresentationInputReadinessWatchdogUsesFinalReadback() {
        let scheduler = ManualInitialPresentationScheduler()
        let baseline = initialPresentationSnapshot(
            generation: 1,
            itemIDs: ["app-a", "app-b"]
        )
        var snapshot =
            initialPresentationInputReadinessSnapshot(
                generation: 1
            )
        var failures:
            [FlowTabUITestInitialPresentationInputReadinessWatchdogFailure]
                = []
        var resolutions:
            [FlowTabUITestInitialPresentationInputReadinessEvidence]
                = []
        let owner = makeInitialPresentationInputReadinessOwner(
            scheduler: scheduler,
            readback: { snapshot }
        )
        owner.start(
            baseline: baseline,
            expectedPresentationGeneration: 3,
            expectedSessionItemIDs: ["app-a", "app-b"],
            expectedSelectedAppID: "app-a",
            watchdogInterval:
                FlowTabUITestInitialPresentationInputReadinessPolicy
                    .watchdog,
            triggerReadiness: {},
            onResolved: { resolutions.append($0) },
            onWatchdog: { failures.append($0) }
        )
        let firstWatchdog = scheduler.tokens.first {
            $0.interval
                == FlowTabUITestInitialPresentationInputReadinessPolicy
                    .watchdog
        }!
        snapshot = initialPresentationInputReadinessSnapshot(
            generation: 2,
            terminateInterruptionProtectionPending: true
        )
        scheduler.fire(firstWatchdog)

        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(
            failures.first?.finalEvidence.source,
            .watchdogReadback
        )
        XCTAssertTrue(
            failures.first?.logFields.contains(
                "terminateInterruptionProtectionCompletion"
            ) == true
        )
        XCTAssertTrue(resolutions.isEmpty)
        XCTAssertFalse(owner.isObserving)

        snapshot = initialPresentationInputReadinessSnapshot(
            generation: 3
        )
        owner.start(
            baseline: initialPresentationSnapshot(
                generation: 3,
                itemIDs: ["app-a", "app-b"]
            ),
            expectedPresentationGeneration: 3,
            expectedSessionItemIDs: ["app-a", "app-b"],
            expectedSelectedAppID: "app-a",
            watchdogInterval:
                FlowTabUITestInitialPresentationInputReadinessPolicy
                    .watchdog,
            triggerReadiness: {},
            onResolved: { resolutions.append($0) },
            onWatchdog: { failures.append($0) }
        )
        let secondWatchdog = scheduler.tokens.last {
            $0.interval
                == FlowTabUITestInitialPresentationInputReadinessPolicy
                    .watchdog
                && !$0.isCancelled
        }!
        snapshot = initialPresentationInputReadinessSnapshot(
            generation: 4
        )
        scheduler.fire(secondWatchdog)

        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(resolutions.count, 1)
        XCTAssertEqual(
            resolutions.first?.source,
            .watchdogReadback
        )
        XCTAssertFalse(owner.isObserving)
    }

}
