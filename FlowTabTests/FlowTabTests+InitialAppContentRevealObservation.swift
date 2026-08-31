import XCTest
@testable import FlowTab

extension FlowTabTests {
    @MainActor
    func testInitialAppContentRevealOwnerRequiresExactTargetAndCancelsWatchdog() {
        let scheduler = ManualInitialAppContentRevealScheduler()
        let owner = InitialAppContentRevealObservationOwner(
            scheduler: scheduler
        )
        var evidence: InitialAppContentRevealEvidence?
        let generation = owner.start(
            presentationGeneration: 11,
            renderGeneration: 42,
            onDraw: { evidence = $0 },
            onWatchdog: { _ in XCTFail("Unexpected watchdog") }
        )

        XCTAssertEqual(
            scheduler.scheduledIntervals,
            [InitialAppContentRevealPolicy.default.watchdogInterval]
        )
        XCTAssertEqual(owner.target?.milestone, .appContent)
        XCTAssertFalse(
            owner.observe(
                appContentRevealEvent(
                    milestone: .windowContent,
                    renderGeneration: 42
                ),
                observationGeneration: generation,
                presentationGeneration: 11
            )
        )
        XCTAssertFalse(
            owner.observe(
                appContentRevealEvent(renderGeneration: 41),
                observationGeneration: generation,
                presentationGeneration: 11
            )
        )
        XCTAssertFalse(
            owner.observe(
                appContentRevealEvent(renderGeneration: 42),
                observationGeneration: generation,
                presentationGeneration: 10
            )
        )

        let matchingEvent = appContentRevealEvent(
            renderGeneration: 42
        )
        XCTAssertTrue(
            owner.markPanelOrdered(
                observationGeneration: generation,
                presentationGeneration: 11
            )
        )
        XCTAssertTrue(
            owner.observe(
                matchingEvent,
                observationGeneration: generation,
                presentationGeneration: 11
            )
        )
        XCTAssertEqual(evidence?.event, matchingEvent)
        XCTAssertEqual(
            evidence?.target,
            InitialAppContentRevealTarget(
                observationGeneration: generation,
                presentationGeneration: 11,
                milestone: .appContent,
                renderGeneration: 42
            )
        )
        XCTAssertFalse(owner.isObserving)
        XCTAssertTrue(scheduler.tokens[0].isCancelled)
        XCTAssertTrue(
            scheduler.fire(at: 0, includingCancelled: true)
        )
        XCTAssertNil(owner.lastWatchdogFailure)
    }

    @MainActor
    func testInitialAppContentRevealWatchdogReportsExpectedAndLastEvent() {
        let scheduler = ManualInitialAppContentRevealScheduler()
        let owner = InitialAppContentRevealObservationOwner(
            scheduler: scheduler
        )
        var failure: InitialAppContentRevealWatchdogFailure?
        let generation = owner.start(
            presentationGeneration: 12,
            renderGeneration: 50,
            onDraw: { _ in XCTFail("Unexpected draw") },
            onWatchdog: { failure = $0 }
        )
        let staleEvent = appContentRevealEvent(
            renderGeneration: 49
        )
        XCTAssertFalse(
            owner.observe(
                staleEvent,
                observationGeneration: generation,
                presentationGeneration: 12
            )
        )

        XCTAssertTrue(scheduler.fire(at: 0))

        XCTAssertEqual(failure?.target.renderGeneration, 50)
        XCTAssertEqual(failure?.lastEvent, staleEvent)
        XCTAssertEqual(owner.lastWatchdogFailure, failure)
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testInitialAppContentRevealHoldsMatchingDrawUntilPanelOrder() {
        let scheduler = ManualInitialAppContentRevealScheduler()
        let owner = InitialAppContentRevealObservationOwner(
            scheduler: scheduler
        )
        var evidence: InitialAppContentRevealEvidence?
        let generation = owner.start(
            presentationGeneration: 13,
            renderGeneration: 51,
            onDraw: { evidence = $0 },
            onWatchdog: { _ in XCTFail("Unexpected watchdog") }
        )
        let event = appContentRevealEvent(renderGeneration: 51)

        XCTAssertTrue(
            owner.observe(
                event,
                observationGeneration: generation,
                presentationGeneration: 13
            )
        )
        XCTAssertNil(evidence)
        XCTAssertTrue(owner.isObserving)

        XCTAssertTrue(
            owner.markPanelOrdered(
                observationGeneration: generation,
                presentationGeneration: 13
            )
        )
        XCTAssertEqual(evidence?.event, event)
        XCTAssertFalse(owner.isObserving)
        XCTAssertTrue(scheduler.tokens[0].isCancelled)
    }

    @MainActor
    func testInitialAppContentRevealOwnerRejectsReplacedAndCancelledGenerations() {
        let scheduler = ManualInitialAppContentRevealScheduler()
        let owner = InitialAppContentRevealObservationOwner(
            scheduler: scheduler
        )
        var completedRenderGenerations: [UInt64] = []
        let firstGeneration = owner.start(
            presentationGeneration: 20,
            renderGeneration: 60,
            onDraw: {
                completedRenderGenerations.append(
                    $0.event.renderGeneration
                )
            },
            onWatchdog: { _ in XCTFail("Unexpected watchdog") }
        )
        let secondGeneration = owner.start(
            presentationGeneration: 21,
            renderGeneration: 61,
            onDraw: {
                completedRenderGenerations.append(
                    $0.event.renderGeneration
                )
            },
            onWatchdog: { _ in XCTFail("Unexpected watchdog") }
        )

        XCTAssertGreaterThan(secondGeneration, firstGeneration)
        XCTAssertTrue(scheduler.tokens[0].isCancelled)
        XCTAssertTrue(
            scheduler.fire(at: 0, includingCancelled: true)
        )
        XCTAssertFalse(
            owner.observe(
                appContentRevealEvent(renderGeneration: 60),
                observationGeneration: firstGeneration,
                presentationGeneration: 20
            )
        )
        XCTAssertTrue(
            owner.markPanelOrdered(
                observationGeneration: secondGeneration,
                presentationGeneration: 21
            )
        )
        XCTAssertTrue(
            owner.observe(
                appContentRevealEvent(renderGeneration: 61),
                observationGeneration: secondGeneration,
                presentationGeneration: 21
            )
        )
        XCTAssertEqual(completedRenderGenerations, [61])

        _ = owner.start(
            presentationGeneration: 22,
            renderGeneration: 62,
            onDraw: { _ in XCTFail("Unexpected draw") },
            onWatchdog: { _ in XCTFail("Unexpected watchdog") }
        )
        owner.cancel()
        XCTAssertTrue(
            scheduler.fire(at: 2, includingCancelled: true)
        )
        XCTAssertEqual(completedRenderGenerations, [61])
    }

    @MainActor
    func testInitialAppContentRevealSchedulesOneRenderPassAfterPreparationThenPanelOrder() {
        let scheduler = ManualInitialAppContentRevealScheduler()
        let owner = InitialAppContentRevealObservationOwner(
            scheduler: scheduler
        )
        var displayCount = 0
        let generation = owner.start(
            presentationGeneration: 30,
            renderGeneration: 70,
            onDraw: { _ in },
            onWatchdog: { _ in XCTFail("Unexpected watchdog") }
        )
        let preparation = appContentPreparation(
            renderGeneration: 70
        ) {
            displayCount += 1
        }

        XCTAssertTrue(
            owner.observePreparation(
                preparation,
                presentationGeneration: 30
            )
        )
        XCTAssertTrue(scheduler.renderPassTokens.isEmpty)
        XCTAssertTrue(
            owner.markPanelOrdered(
                observationGeneration: generation,
                presentationGeneration: 30
            )
        )
        XCTAssertEqual(scheduler.renderPassTokens.count, 1)

        XCTAssertTrue(
            owner.observePreparation(
                preparation,
                presentationGeneration: 30
            )
        )
        XCTAssertTrue(
            owner.markPanelOrdered(
                observationGeneration: generation,
                presentationGeneration: 30
            )
        )
        XCTAssertEqual(scheduler.renderPassTokens.count, 1)
        XCTAssertTrue(scheduler.fireRenderPass(at: 0))
        XCTAssertEqual(displayCount, 1)
        XCTAssertEqual(
            owner.lastRenderPassEvidence,
            InitialAppContentRenderPassEvidence(
                target: InitialAppContentRevealTarget(
                    observationGeneration: generation,
                    presentationGeneration: 30,
                    milestone: .appContent,
                    renderGeneration: 70
                ),
                durationMilliseconds: 1.25,
                completedAtMilliseconds: 200
            )
        )
    }

    @MainActor
    func testInitialAppContentRevealSchedulesRenderPassAfterPanelOrderThenExactPreparation() {
        let scheduler = ManualInitialAppContentRevealScheduler()
        let owner = InitialAppContentRevealObservationOwner(
            scheduler: scheduler
        )
        var displayedGenerations: [UInt64] = []
        let generation = owner.start(
            presentationGeneration: 31,
            renderGeneration: 71,
            onDraw: { _ in },
            onWatchdog: { _ in XCTFail("Unexpected watchdog") }
        )

        XCTAssertTrue(
            owner.markPanelOrdered(
                observationGeneration: generation,
                presentationGeneration: 31
            )
        )
        XCTAssertTrue(scheduler.renderPassTokens.isEmpty)
        XCTAssertFalse(
            owner.observePreparation(
                appContentPreparation(
                    milestone: .windowContent,
                    renderGeneration: 71
                ),
                presentationGeneration: 31
            )
        )
        XCTAssertFalse(
            owner.observePreparation(
                appContentPreparation(renderGeneration: 70),
                presentationGeneration: 31
            )
        )
        XCTAssertFalse(
            owner.observePreparation(
                appContentPreparation(renderGeneration: 71),
                presentationGeneration: 30
            )
        )
        XCTAssertTrue(scheduler.renderPassTokens.isEmpty)

        XCTAssertTrue(
            owner.observePreparation(
                appContentPreparation(renderGeneration: 71) {
                    displayedGenerations.append(71)
                },
                presentationGeneration: 31
            )
        )
        XCTAssertEqual(scheduler.renderPassTokens.count, 1)
        XCTAssertTrue(scheduler.fireRenderPass(at: 0))
        XCTAssertEqual(displayedGenerations, [71])
    }

    @MainActor
    func testInitialAppContentRevealNaturalDrawCancelsFallbackAndPendingWork() {
        let scheduler = ManualInitialAppContentRevealScheduler()
        let owner = InitialAppContentRevealObservationOwner(
            scheduler: scheduler
        )
        var displayedGenerations: [UInt64] = []
        var completedDrawCount = 0
        let firstGeneration = owner.start(
            presentationGeneration: 40,
            renderGeneration: 80,
            onDraw: { _ in completedDrawCount += 1 },
            onWatchdog: { _ in XCTFail("Unexpected watchdog") }
        )
        _ = owner.observePreparation(
            appContentPreparation(renderGeneration: 80) {
                displayedGenerations.append(80)
            },
            presentationGeneration: 40
        )
        _ = owner.markPanelOrdered(
            observationGeneration: firstGeneration,
            presentationGeneration: 40
        )
        XCTAssertTrue(
            owner.observe(
                appContentRevealEvent(renderGeneration: 80),
                observationGeneration: firstGeneration,
                presentationGeneration: 40
            )
        )
        XCTAssertEqual(completedDrawCount, 1)
        XCTAssertFalse(owner.isObserving)
        XCTAssertTrue(scheduler.tokens[0].isCancelled)
        XCTAssertTrue(scheduler.renderPassTokens[0].isCancelled)
        XCTAssertTrue(
            scheduler.fireRenderPass(
                at: 0,
                includingCancelled: true
            )
        )
        XCTAssertTrue(displayedGenerations.isEmpty)

        let secondGeneration = owner.start(
            presentationGeneration: 41,
            renderGeneration: 81,
            onDraw: { _ in },
            onWatchdog: { _ in XCTFail("Unexpected watchdog") }
        )
        _ = owner.observePreparation(
            appContentPreparation(renderGeneration: 81) {
                displayedGenerations.append(81)
            },
            presentationGeneration: 41
        )
        _ = owner.markPanelOrdered(
            observationGeneration: secondGeneration,
            presentationGeneration: 41
        )
        let thirdGeneration = owner.start(
            presentationGeneration: 42,
            renderGeneration: 82,
            onDraw: { _ in },
            onWatchdog: { _ in XCTFail("Unexpected watchdog") }
        )
        XCTAssertTrue(scheduler.renderPassTokens[1].isCancelled)
        XCTAssertTrue(
            scheduler.fireRenderPass(
                at: 1,
                includingCancelled: true
            )
        )
        XCTAssertTrue(displayedGenerations.isEmpty)

        _ = owner.observePreparation(
            appContentPreparation(renderGeneration: 82) {
                displayedGenerations.append(82)
            },
            presentationGeneration: 42
        )
        _ = owner.markPanelOrdered(
            observationGeneration: thirdGeneration,
            presentationGeneration: 42
        )
        owner.cancel()
        XCTAssertTrue(scheduler.renderPassTokens[2].isCancelled)
        XCTAssertTrue(
            scheduler.fireRenderPass(
                at: 2,
                includingCancelled: true
            )
        )
        XCTAssertTrue(displayedGenerations.isEmpty)

        var watchdogGeneration: UInt64?
        let fourthGeneration = owner.start(
            presentationGeneration: 43,
            renderGeneration: 83,
            onDraw: { _ in },
            onWatchdog: {
                watchdogGeneration = $0.target.renderGeneration
            }
        )
        _ = owner.observePreparation(
            appContentPreparation(renderGeneration: 83) {
                displayedGenerations.append(83)
            },
            presentationGeneration: 43
        )
        _ = owner.markPanelOrdered(
            observationGeneration: fourthGeneration,
            presentationGeneration: 43
        )
        XCTAssertTrue(scheduler.fire(at: 3))
        XCTAssertEqual(watchdogGeneration, 83)
        XCTAssertTrue(scheduler.renderPassTokens[3].isCancelled)
        XCTAssertTrue(
            scheduler.fireRenderPass(
                at: 3,
                includingCancelled: true
            )
        )
        XCTAssertTrue(displayedGenerations.isEmpty)
    }

    @MainActor
    func testInitialAppContentRevealReusesExactPreparationPublishedBeforeStart() {
        let scheduler = ManualInitialAppContentRevealScheduler()
        let owner = InitialAppContentRevealObservationOwner(
            scheduler: scheduler
        )
        var displayCount = 0
        XCTAssertTrue(
            owner.observePreparation(
                appContentPreparation(renderGeneration: 90) {
                    displayCount += 1
                },
                presentationGeneration: 50
            )
        )
        let generation = owner.start(
            presentationGeneration: 50,
            renderGeneration: 90,
            onDraw: { _ in },
            onWatchdog: { _ in XCTFail("Unexpected watchdog") }
        )

        _ = owner.markPanelOrdered(
            observationGeneration: generation,
            presentationGeneration: 50
        )
        XCTAssertEqual(scheduler.renderPassTokens.count, 1)
        XCTAssertTrue(scheduler.fireRenderPass(at: 0))
        XCTAssertEqual(displayCount, 1)
    }

    private func appContentRevealEvent(
        milestone: SwitcherRenderMilestone = .appContent,
        renderGeneration: UInt64
    ) -> SwitcherRenderMilestoneEvent {
        SwitcherRenderMilestoneEvent(
            milestone: milestone,
            renderGeneration: renderGeneration,
            drawnAtMilliseconds: 100
        )
    }

    private func appContentPreparation(
        milestone: SwitcherRenderMilestone = .appContent,
        renderGeneration: UInt64,
        onDisplay: @escaping () -> Void = {}
    ) -> SwitcherRenderMilestonePreparation {
        SwitcherRenderMilestonePreparation(
            milestone: milestone,
            renderGeneration: renderGeneration,
            displayAction: {
                onDisplay()
                return SwitcherRenderMilestoneDisplayEvidence(
                    milestone: milestone,
                    renderGeneration: renderGeneration,
                    durationMilliseconds: 1.25,
                    completedAtMilliseconds: 200
                )
            }
        )
    }
}

@MainActor
final class ManualInitialAppContentRevealScheduler:
    InitialAppContentRevealScheduling
{
    private struct ScheduledAction {
        let interval: TimeInterval
        let token: ManualInitialAppContentRevealToken
        let action: @MainActor @Sendable () -> Void
    }

    private var scheduled: [ScheduledAction] = []
    private var scheduledRenderPasses:
        [(token: ManualInitialAppContentRevealToken,
          action: @MainActor @Sendable () -> Void)] = []

    var scheduledIntervals: [TimeInterval] {
        scheduled.map(\.interval)
    }

    var tokens: [ManualInitialAppContentRevealToken] {
        scheduled.map(\.token)
    }

    var renderPassTokens: [ManualInitialAppContentRevealToken] {
        scheduledRenderPasses.map(\.token)
    }

    func scheduleRenderPass(
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any InitialAppContentRevealCancellable {
        let token = ManualInitialAppContentRevealToken()
        scheduledRenderPasses.append(
            (token: token, action: action)
        )
        return token
    }

    func scheduleWatchdog(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any InitialAppContentRevealCancellable {
        let token = ManualInitialAppContentRevealToken()
        scheduled.append(
            ScheduledAction(
                interval: interval,
                token: token,
                action: action
            )
        )
        return token
    }

    @discardableResult
    func fire(
        at index: Int,
        includingCancelled: Bool = false
    ) -> Bool {
        guard scheduled.indices.contains(index) else { return false }
        let entry = scheduled[index]
        guard !entry.token.didFire else { return false }
        guard includingCancelled || !entry.token.isCancelled else {
            return false
        }
        entry.token.didFire = true
        entry.action()
        return true
    }

    @discardableResult
    func fireRenderPass(
        at index: Int,
        includingCancelled: Bool = false
    ) -> Bool {
        guard scheduledRenderPasses.indices.contains(index) else {
            return false
        }
        let entry = scheduledRenderPasses[index]
        guard !entry.token.didFire else { return false }
        guard includingCancelled || !entry.token.isCancelled else {
            return false
        }
        entry.token.didFire = true
        entry.action()
        return true
    }
}

@MainActor
final class ManualInitialAppContentRevealToken:
    InitialAppContentRevealCancellable
{
    private(set) var isCancelled = false
    var didFire = false

    func cancel() {
        isCancelled = true
    }
}
