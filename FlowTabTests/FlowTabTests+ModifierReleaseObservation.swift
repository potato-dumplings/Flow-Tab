import XCTest
@testable import FlowTab

@MainActor
private final class ManualModifierReleaseObservationToken:
    ModifierReleaseObservationCancellable
{
    private var action: (@MainActor @Sendable () -> Void)?
    private(set) var isCanceled = false

    init(action: @escaping @MainActor @Sendable () -> Void) {
        self.action = action
    }

    func fire() {
        guard !isCanceled, let action else { return }
        self.action = nil
        action()
    }

    func cancel() {
        isCanceled = true
        action = nil
    }
}

@MainActor
final class ManualModifierReleaseObservationScheduler:
    ModifierReleaseObservationScheduling
{
    private(set) var intervals: [TimeInterval] = []
    private var tokens: [ManualModifierReleaseObservationToken] = []

    var pendingCount: Int {
        tokens.filter { !$0.isCanceled }.count
    }

    func schedule(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any ModifierReleaseObservationCancellable {
        intervals.append(interval)
        let token = ManualModifierReleaseObservationToken(action: action)
        tokens.append(token)
        return token
    }

    func fireNext() {
        guard let index = tokens.firstIndex(where: { !$0.isCanceled }) else {
            XCTFail("Expected a pending modifier-release sample.")
            return
        }
        let token = tokens.remove(at: index)
        token.fire()
    }
}

@MainActor
final class ManualModifierReleaseEventSource:
    ModifierReleaseEventObserving
{
    @MainActor
    private final class EventToken: ModifierReleaseObservationCancellable {
        private var action: (@MainActor @Sendable () -> Void)?
        private(set) var isCanceled = false

        init(action: @escaping @MainActor @Sendable () -> Void) {
            self.action = action
        }

        func emit() {
            guard !isCanceled else { return }
            action?()
        }

        func cancel() {
            isCanceled = true
            action = nil
        }
    }

    private var activeToken: EventToken?
    private(set) var observedKeyCodes: Set<UInt16> = []
    private(set) var startCount = 0

    var activeObserverCount: Int {
        activeToken?.isCanceled == false ? 1 : 0
    }

    func start(
        relevantKeyCodes: Set<UInt16>,
        onInputTransition: @escaping @MainActor @Sendable () -> Void
    ) -> any ModifierReleaseObservationCancellable {
        startCount += 1
        observedKeyCodes = relevantKeyCodes
        let token = EventToken(action: onInputTransition)
        activeToken = token
        return token
    }

    func emitInputTransition() {
        activeToken?.emit()
    }
}

@MainActor
private final class ImmediateModifierReleaseObservationScheduler:
    ModifierReleaseObservationScheduling
{
    func schedule(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any ModifierReleaseObservationCancellable {
        let token = ManualModifierReleaseObservationToken(action: action)
        token.fire()
        return token
    }
}

extension FlowTabTests {
    @MainActor
    func testModifierReleaseObservationInstallsObserverBeforeInitialReadback() {
        let scheduler = ManualModifierReleaseObservationScheduler()
        let eventSource = ManualModifierReleaseEventSource()
        let owner = ModifierReleaseObservationOwner(
            scheduler: scheduler,
            eventSource: eventSource
        )
        var samples: [ModifierReleaseObservationSample] = []

        let generation = owner.start(
            kind: .selectionConfirmation,
            relevantKeyCodes: [48, 58],
            sampleInterval: 0.025,
            requiredReleasedSampleCount: 2,
            readback: { _, _ in
                XCTAssertEqual(eventSource.activeObserverCount, 1)
                return false
            },
            onStarted: { _ in },
            onSample: { samples.append($0) },
            onComplete: { _ in }
        )

        XCTAssertEqual(eventSource.startCount, 1)
        XCTAssertEqual(eventSource.observedKeyCodes, [48, 58])
        XCTAssertEqual(
            samples,
            [
                ModifierReleaseObservationSample(
                    generation: generation,
                    source: .initialReadback,
                    inputPressed: false,
                    releasedSamples: 1
                )
            ]
        )
        XCTAssertEqual(scheduler.pendingCount, 1)
    }

    @MainActor
    func testModifierReleaseObservationCompletesOnlyAfterStableConditionReadback() {
        let scheduler = ManualModifierReleaseObservationScheduler()
        let eventSource = ManualModifierReleaseEventSource()
        let owner = ModifierReleaseObservationOwner(
            scheduler: scheduler,
            eventSource: eventSource
        )
        var completedGenerations: [Int] = []

        let generation = owner.start(
            kind: .selectionConfirmation,
            relevantKeyCodes: [58],
            sampleInterval: 0.025,
            requiredReleasedSampleCount: 2,
            readback: { _, _ in false },
            onStarted: { _ in },
            onSample: { _ in },
            onComplete: { completedGenerations.append($0) }
        )
        XCTAssertTrue(completedGenerations.isEmpty)

        scheduler.fireNext()

        XCTAssertEqual(completedGenerations, [generation])
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertEqual(eventSource.activeObserverCount, 0)
    }

    @MainActor
    func testModifierReleaseObservationUsesFallbackWhenTransitionEventIsMissing() {
        let scheduler = ManualModifierReleaseObservationScheduler()
        let owner = ModifierReleaseObservationOwner(
            scheduler: scheduler,
            eventSource: ManualModifierReleaseEventSource()
        )
        var inputPressed = true
        var completed = false

        owner.start(
            kind: .selectionConfirmation,
            relevantKeyCodes: [58],
            sampleInterval: 0.025,
            requiredReleasedSampleCount: 2,
            readback: { _, _ in inputPressed },
            onStarted: { _ in },
            onSample: { _ in },
            onComplete: { _ in completed = true }
        )
        inputPressed = false

        scheduler.fireNext()
        XCTAssertFalse(completed)
        scheduler.fireNext()

        XCTAssertTrue(completed)
    }

    @MainActor
    func testModifierReleaseObservationResetsOnPressedEvidenceAndRejectsDuplicateEvents() {
        let scheduler = ManualModifierReleaseObservationScheduler()
        let eventSource = ManualModifierReleaseEventSource()
        let owner = ModifierReleaseObservationOwner(
            scheduler: scheduler,
            eventSource: eventSource
        )
        var inputPressed = false
        var samples: [ModifierReleaseObservationSample] = []
        var completed = false

        owner.start(
            kind: .selectionConfirmation,
            relevantKeyCodes: [58],
            sampleInterval: 0.025,
            requiredReleasedSampleCount: 2,
            readback: { _, _ in inputPressed },
            onStarted: { _ in },
            onSample: { samples.append($0) },
            onComplete: { _ in completed = true }
        )
        inputPressed = true
        eventSource.emitInputTransition()
        inputPressed = false
        eventSource.emitInputTransition()
        eventSource.emitInputTransition()

        XCTAssertFalse(completed)
        XCTAssertEqual(samples.suffix(3).map(\.releasedSamples), [0, 1, 1])
        XCTAssertEqual(scheduler.pendingCount, 1)

        scheduler.fireNext()
        XCTAssertTrue(completed)
    }

    @MainActor
    func testModifierReleaseObservationCancellationRejectsQueuedFallback() {
        let scheduler = ManualModifierReleaseObservationScheduler()
        let eventSource = ManualModifierReleaseEventSource()
        let owner = ModifierReleaseObservationOwner(
            scheduler: scheduler,
            eventSource: eventSource
        )
        var completedGenerations: [Int] = []

        let firstGeneration = owner.start(
            kind: .replaySuppression,
            relevantKeyCodes: [48, 58],
            sampleInterval: 0.025,
            requiredReleasedSampleCount: 2,
            readback: { _, _ in false },
            onStarted: { _ in },
            onSample: { _ in },
            onComplete: { completedGenerations.append($0) }
        )
        XCTAssertEqual(
            owner.cancel(kind: .replaySuppression),
            firstGeneration
        )
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertEqual(eventSource.activeObserverCount, 0)
        eventSource.emitInputTransition()

        let secondGeneration = owner.start(
            kind: .selectionConfirmation,
            relevantKeyCodes: [58],
            sampleInterval: 0.025,
            requiredReleasedSampleCount: 2,
            readback: { _, _ in false },
            onStarted: { _ in },
            onSample: { _ in },
            onComplete: { completedGenerations.append($0) }
        )
        scheduler.fireNext()

        XCTAssertGreaterThan(secondGeneration, firstGeneration)
        XCTAssertEqual(completedGenerations, [secondGeneration])
    }

    @MainActor
    func testModifierReleaseObservationSupportsSynchronousSchedulerCompletion() {
        let eventSource = ManualModifierReleaseEventSource()
        let owner = ModifierReleaseObservationOwner(
            scheduler: ImmediateModifierReleaseObservationScheduler(),
            eventSource: eventSource
        )
        var completedGeneration: Int?

        let generation = owner.start(
            kind: .selectionConfirmation,
            relevantKeyCodes: [58],
            sampleInterval: 0.025,
            requiredReleasedSampleCount: 2,
            readback: { _, _ in false },
            onStarted: { _ in },
            onSample: { _ in },
            onComplete: { completedGeneration = $0 }
        )

        XCTAssertEqual(completedGeneration, generation)
        XCTAssertEqual(eventSource.activeObserverCount, 0)
    }

    @MainActor
    func testModifierReleaseObservationPressureKeepsOneFallbackAndSameResult() {
        let scheduler = ManualModifierReleaseObservationScheduler()
        let eventSource = ManualModifierReleaseEventSource()
        let owner = ModifierReleaseObservationOwner(
            scheduler: scheduler,
            eventSource: eventSource
        )
        var completed = false

        owner.start(
            kind: .replaySuppression,
            relevantKeyCodes: [48, 58],
            sampleInterval: 0.025,
            requiredReleasedSampleCount: 2,
            readback: { _, _ in false },
            onStarted: { _ in },
            onSample: { _ in },
            onComplete: { _ in completed = true }
        )
        for _ in 0..<2_000 {
            eventSource.emitInputTransition()
        }

        XCTAssertFalse(completed)
        XCTAssertEqual(scheduler.pendingCount, 1)
        XCTAssertEqual(eventSource.activeObserverCount, 1)
        scheduler.fireNext()

        XCTAssertTrue(completed)
        XCTAssertEqual(eventSource.activeObserverCount, 0)
    }
}
