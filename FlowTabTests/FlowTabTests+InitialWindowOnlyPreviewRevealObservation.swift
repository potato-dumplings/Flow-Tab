import XCTest
@testable import FlowTab

extension FlowTabTests {
    @MainActor
    func testInitialPreviewRevealOwnerCompletesFromInitialReadbackWithoutWatchdog() {
        let scheduler = ManualInitialPreviewRevealScheduler()
        let owner = InitialWindowOnlyPreviewRevealObservationOwner(
            scheduler: scheduler
        )
        var evidence: InitialWindowOnlyPreviewRevealEvidence?

        let generation = owner.start(
            presentationGeneration: 11,
            readback: {
                InitialWindowOnlyPreviewReadinessSnapshot(
                    pendingCaptureCount: 0
                )
            },
            onReady: { evidence = $0 },
            onWatchdog: { _ in XCTFail("Unexpected watchdog") }
        )

        XCTAssertEqual(
            evidence,
            InitialWindowOnlyPreviewRevealEvidence(
                source: .initialReadback,
                observationGeneration: generation,
                presentationGeneration: 11,
                snapshot: InitialWindowOnlyPreviewReadinessSnapshot(
                    pendingCaptureCount: 0
                )
            )
        )
        XCTAssertTrue(scheduler.scheduledIntervals.isEmpty)
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testInitialPreviewRevealOwnerCompletesFromBatchEvidenceAndCancelsWatchdog() {
        let scheduler = ManualInitialPreviewRevealScheduler()
        let owner = InitialWindowOnlyPreviewRevealObservationOwner(
            scheduler: scheduler
        )
        var pendingCaptureCount = 2
        var evidence: [InitialWindowOnlyPreviewRevealEvidence] = []
        let generation = owner.start(
            presentationGeneration: 12,
            readback: {
                InitialWindowOnlyPreviewReadinessSnapshot(
                    pendingCaptureCount: pendingCaptureCount
                )
            },
            onReady: { evidence.append($0) },
            onWatchdog: { _ in XCTFail("Unexpected watchdog") }
        )

        XCTAssertEqual(
            scheduler.scheduledIntervals,
            [
                InitialWindowOnlyPreviewRevealPolicy.default
                    .degradedRevealWatchdogInterval
            ]
        )
        pendingCaptureCount = 0
        XCTAssertTrue(
            owner.observe(
                source: .previewBatchCompleted,
                observationGeneration: generation,
                presentationGeneration: 12
            )
        )
        XCTAssertEqual(evidence.map(\.source), [.previewBatchCompleted])
        XCTAssertFalse(owner.isObserving)
        XCTAssertFalse(
            owner.observe(
                source: .previewBatchCompleted,
                observationGeneration: generation,
                presentationGeneration: 12
            )
        )
        XCTAssertTrue(scheduler.tokens[0].isCancelled)
        XCTAssertTrue(
            scheduler.fire(
                at: 0,
                includingCancelled: true
            )
        )
        XCTAssertEqual(evidence.count, 1)
    }

    @MainActor
    func testInitialPreviewRevealWatchdogFinalReadbackCanProvideReadyEvidence() {
        let scheduler = ManualInitialPreviewRevealScheduler()
        let owner = InitialWindowOnlyPreviewRevealObservationOwner(
            scheduler: scheduler
        )
        var pendingCaptureCount = 1
        var evidence: InitialWindowOnlyPreviewRevealEvidence?
        var failure: InitialWindowOnlyPreviewRevealWatchdogFailure?
        let generation = owner.start(
            presentationGeneration: 13,
            readback: {
                InitialWindowOnlyPreviewReadinessSnapshot(
                    pendingCaptureCount: pendingCaptureCount
                )
            },
            onReady: { evidence = $0 },
            onWatchdog: { failure = $0 }
        )

        pendingCaptureCount = 0
        XCTAssertTrue(scheduler.fire(at: 0))

        XCTAssertEqual(evidence?.source, .watchdogReadback)
        XCTAssertEqual(evidence?.observationGeneration, generation)
        XCTAssertNil(failure)
        XCTAssertNil(owner.lastWatchdogFailure)
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testInitialPreviewRevealWatchdogReportsLastEventAndFinalReadback() {
        let scheduler = ManualInitialPreviewRevealScheduler()
        let owner = InitialWindowOnlyPreviewRevealObservationOwner(
            scheduler: scheduler
        )
        var pendingCaptureCount = 3
        var failure: InitialWindowOnlyPreviewRevealWatchdogFailure?
        let generation = owner.start(
            presentationGeneration: 14,
            readback: {
                InitialWindowOnlyPreviewReadinessSnapshot(
                    pendingCaptureCount: pendingCaptureCount
                )
            },
            onReady: { _ in XCTFail("Unexpected ready evidence") },
            onWatchdog: { failure = $0 }
        )

        pendingCaptureCount = 2
        XCTAssertFalse(
            owner.observe(
                source: .previewBatchCompleted,
                observationGeneration: generation,
                presentationGeneration: 14
            )
        )
        pendingCaptureCount = 1
        XCTAssertTrue(scheduler.fire(at: 0))

        XCTAssertEqual(
            failure?.lastEventEvidence.source,
            .previewBatchCompleted
        )
        XCTAssertEqual(
            failure?.lastEventEvidence.snapshot.pendingCaptureCount,
            2
        )
        XCTAssertEqual(failure?.finalEvidence.source, .watchdogReadback)
        XCTAssertEqual(
            failure?.finalEvidence.snapshot.pendingCaptureCount,
            1
        )
        XCTAssertEqual(owner.lastWatchdogFailure, failure)
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testInitialPreviewRevealOwnerRejectsReplacedCancelledAndMismatchedEvidence() {
        let scheduler = ManualInitialPreviewRevealScheduler()
        let owner = InitialWindowOnlyPreviewRevealObservationOwner(
            scheduler: scheduler
        )
        var pendingCaptureCount = 1
        let recorder = InitialPreviewGenerationRecorder()
        let firstGeneration = startInitialPreviewObservation(
            owner: owner,
            presentationGeneration: 15,
            pendingCaptureCount: { pendingCaptureCount },
            recorder: recorder
        )
        let secondGeneration = startInitialPreviewObservation(
            owner: owner,
            presentationGeneration: 16,
            pendingCaptureCount: { pendingCaptureCount },
            recorder: recorder
        )

        XCTAssertGreaterThan(secondGeneration, firstGeneration)
        pendingCaptureCount = 0
        XCTAssertFalse(
            owner.observe(
                source: .previewBatchCompleted,
                observationGeneration: firstGeneration,
                presentationGeneration: 15
            )
        )
        XCTAssertFalse(
            owner.observe(
                source: .previewBatchCompleted,
                observationGeneration: secondGeneration,
                presentationGeneration: 15
            )
        )
        XCTAssertTrue(
            scheduler.fire(
                at: 0,
                includingCancelled: true
            )
        )
        XCTAssertTrue(
            owner.observe(
                source: .previewBatchCompleted,
                observationGeneration: secondGeneration,
                presentationGeneration: 16
            )
        )
        XCTAssertEqual(recorder.generations, [secondGeneration])

        _ = startInitialPreviewObservation(
            owner: owner,
            presentationGeneration: 17,
            pendingCaptureCount: { 1 },
            recorder: recorder
        )
        owner.cancel()
        XCTAssertTrue(
            scheduler.fire(
                at: 2,
                includingCancelled: true
            )
        )
        XCTAssertEqual(recorder.generations, [secondGeneration])
    }

    @MainActor
    func testInitialPreviewRevealOwnerSupportsSynchronousWatchdogDelivery() {
        let scheduler = SynchronousInitialPreviewRevealScheduler()
        let owner = InitialWindowOnlyPreviewRevealObservationOwner(
            scheduler: scheduler
        )
        var failure: InitialWindowOnlyPreviewRevealWatchdogFailure?

        _ = owner.start(
            presentationGeneration: 18,
            readback: {
                InitialWindowOnlyPreviewReadinessSnapshot(
                    pendingCaptureCount: 1
                )
            },
            onReady: { _ in XCTFail("Unexpected ready evidence") },
            onWatchdog: { failure = $0 }
        )

        XCTAssertEqual(failure?.finalEvidence.source, .watchdogReadback)
        XCTAssertFalse(owner.isObserving)
        XCTAssertTrue(scheduler.token.isCancelled)
    }

    @MainActor
    private func startInitialPreviewObservation(
        owner: InitialWindowOnlyPreviewRevealObservationOwner,
        presentationGeneration: Int,
        pendingCaptureCount: @escaping @MainActor () -> Int,
        recorder: InitialPreviewGenerationRecorder
    ) -> Int {
        owner.start(
            presentationGeneration: presentationGeneration,
            readback: {
                InitialWindowOnlyPreviewReadinessSnapshot(
                    pendingCaptureCount: pendingCaptureCount()
                )
            },
            onReady: {
                recorder.generations.append($0.observationGeneration)
            },
            onWatchdog: { _ in }
        )
    }
}

@MainActor
private final class InitialPreviewGenerationRecorder {
    var generations: [Int] = []
}

@MainActor
final class ManualInitialPreviewRevealScheduler:
    InitialWindowOnlyPreviewRevealScheduling
{
    private struct ScheduledAction {
        let interval: TimeInterval
        let token: ManualInitialPreviewRevealToken
        let action: @MainActor @Sendable () -> Void
    }

    private var scheduled: [ScheduledAction] = []

    var scheduledIntervals: [TimeInterval] {
        scheduled.map(\.interval)
    }

    var tokens: [ManualInitialPreviewRevealToken] {
        scheduled.map(\.token)
    }

    func scheduleWatchdog(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any InitialWindowOnlyPreviewRevealCancellable {
        let token = ManualInitialPreviewRevealToken()
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
        let scheduledAction = scheduled[index]
        guard !scheduledAction.token.didFire else { return false }
        guard includingCancelled || !scheduledAction.token.isCancelled
        else {
            return false
        }
        scheduledAction.token.didFire = true
        scheduledAction.action()
        return true
    }
}

@MainActor
final class ManualInitialPreviewRevealToken:
    InitialWindowOnlyPreviewRevealCancellable
{
    private(set) var isCancelled = false
    var didFire = false

    func cancel() {
        isCancelled = true
    }
}

@MainActor
private final class SynchronousInitialPreviewRevealScheduler:
    InitialWindowOnlyPreviewRevealScheduling
{
    let token = ManualInitialPreviewRevealToken()

    func scheduleWatchdog(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any InitialWindowOnlyPreviewRevealCancellable {
        action()
        return token
    }
}
