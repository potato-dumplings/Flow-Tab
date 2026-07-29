import Foundation

@MainActor
protocol SpaceFixtureCancellable: AnyObject {
    func cancel()
}

@MainActor
protocol SpaceFixtureScheduling: AnyObject {
    func schedule(
        afterMilliseconds delayMilliseconds: Int,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any SpaceFixtureCancellable
}

@MainActor
private final class SpaceFixtureScheduledTaskToken:
    SpaceFixtureCancellable
{
    private let task: Task<Void, Never>

    init(
        delayMilliseconds: Int,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        task = Task { @MainActor in
            do {
                try await Task.sleep(
                    nanoseconds:
                        UInt64(max(0, delayMilliseconds))
                        * 1_000_000
                )
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        task.cancel()
    }

    deinit {
        task.cancel()
    }
}

@MainActor
final class SpaceFixtureScheduler: SpaceFixtureScheduling {
    func schedule(
        afterMilliseconds delayMilliseconds: Int,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any SpaceFixtureCancellable {
        SpaceFixtureScheduledTaskToken(
            delayMilliseconds: delayMilliseconds,
            action: action
        )
    }
}

struct SpaceFixtureFullscreenTransitionEvidence: Equatable {
    let observationGeneration: Int
    let sequenceIndex: Int
    let totalWindowCount: Int
    let windowPlanIndex: Int
}

struct SpaceFixtureFullscreenTransitionCompletion: Equatable {
    let observationGeneration: Int
    let windowPlanIndices: [Int]
}

@MainActor
final class SpaceFixtureFullscreenTransitionOwner {
    private enum Phase: Equatable {
        case awaitingConfiguredDelay
        case enteringWindow(sequenceIndex: Int)
    }

    private struct ActiveTransition {
        let generation: Int
        let windows: [any SpaceFixtureWindowing]
        let onWillEnter:
            @MainActor (
                _ window: any SpaceFixtureWindowing,
                _ sequenceIndex: Int,
                _ totalWindowCount: Int
            ) -> Void
        let onDidEnter:
            @MainActor (
                SpaceFixtureFullscreenTransitionEvidence
            ) -> Void
        let onComplete:
            @MainActor (
                SpaceFixtureFullscreenTransitionCompletion
            ) -> Void
        var completedWindowPlanIndices: [Int]
        var phase: Phase
        var scheduledToken: (any SpaceFixtureCancellable)?
        var windowObservationToken: (any SpaceFixtureCancellable)?
    }

    private let scheduler: any SpaceFixtureScheduling
    private var active: ActiveTransition?

    private(set) var generation = 0
    private(set) var lastEvidence:
        SpaceFixtureFullscreenTransitionEvidence?

    init(scheduler: (any SpaceFixtureScheduling)? = nil) {
        self.scheduler = scheduler ?? SpaceFixtureScheduler()
    }

    var isRunning: Bool {
        active != nil
    }

    @discardableResult
    func start(
        windows: [any SpaceFixtureWindowing],
        initialDelayMilliseconds: Int,
        onWillEnter:
            @escaping @MainActor (
                _ window: any SpaceFixtureWindowing,
                _ sequenceIndex: Int,
                _ totalWindowCount: Int
            ) -> Void,
        onDidEnter:
            @escaping @MainActor (
                SpaceFixtureFullscreenTransitionEvidence
            ) -> Void,
        onComplete:
            @escaping @MainActor (
                SpaceFixtureFullscreenTransitionCompletion
            ) -> Void
    ) -> Int {
        precondition(
            initialDelayMilliseconds >= 0,
            "Fixture fullscreen delay must be nonnegative."
        )
        cancel(invalidate: false)
        generation += 1
        let transitionGeneration = generation
        lastEvidence = nil
        active = ActiveTransition(
            generation: transitionGeneration,
            windows: windows,
            onWillEnter: onWillEnter,
            onDidEnter: onDidEnter,
            onComplete: onComplete,
            completedWindowPlanIndices: [],
            phase: .awaitingConfiguredDelay,
            scheduledToken: nil,
            windowObservationToken: nil
        )

        guard !windows.isEmpty else {
            finish(generation: transitionGeneration)
            return transitionGeneration
        }

        let token = scheduler.schedule(
            afterMilliseconds: initialDelayMilliseconds
        ) { [weak self] in
            self?.beginWindow(
                sequenceIndex: 0,
                generation: transitionGeneration
            )
        }
        guard var current = active,
              current.generation == transitionGeneration,
              current.phase == .awaitingConfiguredDelay,
              current.scheduledToken == nil
        else {
            token.cancel()
            return transitionGeneration
        }
        current.scheduledToken = token
        active = current
        return transitionGeneration
    }

    func cancel(invalidate: Bool = true) {
        active?.scheduledToken?.cancel()
        active?.windowObservationToken?.cancel()
        active = nil
        if invalidate {
            generation += 1
        }
    }

    private func beginWindow(
        sequenceIndex: Int,
        generation: Int
    ) {
        guard var current = active,
              current.generation == generation,
              current.windows.indices.contains(sequenceIndex)
        else {
            return
        }
        current.scheduledToken = nil
        current.phase = .enteringWindow(
            sequenceIndex: sequenceIndex
        )
        active = current

        let window = current.windows[sequenceIndex]
        current.onWillEnter(
            window,
            sequenceIndex,
            current.windows.count
        )
        guard let pending = active,
              pending.generation == generation,
              pending.phase == .enteringWindow(
                sequenceIndex: sequenceIndex
              ),
              pending.windowObservationToken == nil
        else {
            return
        }

        let token = window.enterFullScreen { [weak self] in
            self?.completeWindow(
                sequenceIndex: sequenceIndex,
                generation: generation
            )
        }
        guard var observing = active,
              observing.generation == generation,
              observing.phase == .enteringWindow(
                sequenceIndex: sequenceIndex
              ),
              observing.windowObservationToken == nil
        else {
            token.cancel()
            return
        }
        observing.windowObservationToken = token
        active = observing
    }

    private func completeWindow(
        sequenceIndex: Int,
        generation: Int
    ) {
        guard var current = active,
              current.generation == generation,
              current.phase == .enteringWindow(
                sequenceIndex: sequenceIndex
              ),
              current.windows.indices.contains(sequenceIndex)
        else {
            return
        }
        current.windowObservationToken = nil
        let window = current.windows[sequenceIndex]
        current.completedWindowPlanIndices.append(
            window.plan.index
        )
        active = current

        let evidence = SpaceFixtureFullscreenTransitionEvidence(
            observationGeneration: generation,
            sequenceIndex: sequenceIndex,
            totalWindowCount: current.windows.count,
            windowPlanIndex: window.plan.index
        )
        lastEvidence = evidence
        current.onDidEnter(evidence)

        guard let pending = active,
              pending.generation == generation,
              pending.phase == .enteringWindow(
                sequenceIndex: sequenceIndex
              )
        else {
            return
        }
        let nextIndex = sequenceIndex + 1
        if pending.windows.indices.contains(nextIndex) {
            beginWindow(
                sequenceIndex: nextIndex,
                generation: generation
            )
            return
        }
        finish(generation: generation)
    }

    private func finish(generation: Int) {
        guard let current = active,
              current.generation == generation
        else {
            return
        }
        active = nil
        current.onComplete(
            SpaceFixtureFullscreenTransitionCompletion(
                observationGeneration: generation,
                windowPlanIndices:
                    current.completedWindowPlanIndices
            )
        )
    }
}
