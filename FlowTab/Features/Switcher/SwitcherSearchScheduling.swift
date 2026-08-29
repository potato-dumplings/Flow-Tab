import Foundation

struct SwitcherSearchComputationDiagnostic: Equatable {
    let query: String
    let scope: SwitcherSearchScope
    let revision: UInt64
    let scheduledAtNanoseconds: UInt64
    let startedAtNanoseconds: UInt64
    let finishedAtNanoseconds: UInt64

    var debounceMilliseconds: Double {
        Self.milliseconds(
            from: scheduledAtNanoseconds,
            to: startedAtNanoseconds
        )
    }

    var computationMilliseconds: Double {
        Self.milliseconds(
            from: startedAtNanoseconds,
            to: finishedAtNanoseconds
        )
    }

    private static func milliseconds(
        from start: UInt64,
        to end: UInt64
    ) -> Double {
        guard end >= start else { return 0 }
        return Double(end - start) / 1_000_000
    }
}

struct SwitcherSearchSchedulingPolicy: Equatable {
    let initialDebounceInterval: TimeInterval
    let fastComputationThresholdNanoseconds: UInt64
    let moderateComputationThresholdNanoseconds: UInt64
    let slowComputationThresholdNanoseconds: UInt64
    let fastDebounceInterval: TimeInterval
    let moderateDebounceInterval: TimeInterval
    let slowDebounceInterval: TimeInterval
    let verySlowDebounceInterval: TimeInterval

    static let standard = SwitcherSearchSchedulingPolicy(
        initialDebounceInterval: 0.018,
        fastComputationThresholdNanoseconds: 6_000_000,
        moderateComputationThresholdNanoseconds: 10_000_000,
        slowComputationThresholdNanoseconds: 16_000_000,
        fastDebounceInterval: 0.012,
        moderateDebounceInterval: 0.018,
        slowDebounceInterval: 0.022,
        verySlowDebounceInterval: 0.025
    )

    init(
        initialDebounceInterval: TimeInterval,
        fastComputationThresholdNanoseconds: UInt64,
        moderateComputationThresholdNanoseconds: UInt64,
        slowComputationThresholdNanoseconds: UInt64,
        fastDebounceInterval: TimeInterval,
        moderateDebounceInterval: TimeInterval,
        slowDebounceInterval: TimeInterval,
        verySlowDebounceInterval: TimeInterval
    ) {
        precondition(initialDebounceInterval > 0)
        precondition(
            fastComputationThresholdNanoseconds
                < moderateComputationThresholdNanoseconds
        )
        precondition(
            moderateComputationThresholdNanoseconds
                < slowComputationThresholdNanoseconds
        )
        precondition(fastDebounceInterval > 0)
        precondition(moderateDebounceInterval > 0)
        precondition(slowDebounceInterval > 0)
        precondition(verySlowDebounceInterval > 0)
        self.initialDebounceInterval = initialDebounceInterval
        self.fastComputationThresholdNanoseconds =
            fastComputationThresholdNanoseconds
        self.moderateComputationThresholdNanoseconds =
            moderateComputationThresholdNanoseconds
        self.slowComputationThresholdNanoseconds =
            slowComputationThresholdNanoseconds
        self.fastDebounceInterval = fastDebounceInterval
        self.moderateDebounceInterval = moderateDebounceInterval
        self.slowDebounceInterval = slowDebounceInterval
        self.verySlowDebounceInterval = verySlowDebounceInterval
    }

    func debounceInterval(
        afterComputationNanoseconds elapsedNanoseconds: UInt64
    ) -> TimeInterval {
        if elapsedNanoseconds > slowComputationThresholdNanoseconds {
            return verySlowDebounceInterval
        }
        if elapsedNanoseconds > moderateComputationThresholdNanoseconds {
            return slowDebounceInterval
        }
        if elapsedNanoseconds > fastComputationThresholdNanoseconds {
            return moderateDebounceInterval
        }
        return fastDebounceInterval
    }
}

protocol SwitcherSearchCancellable: AnyObject {
    func cancel()
}

@MainActor
protocol SwitcherSearchScheduling: AnyObject {
    func schedule(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any SwitcherSearchCancellable
}

private final class SwitcherSearchScheduledTask:
    SwitcherSearchCancellable
{
    private let task: Task<Void, Never>

    @MainActor
    init(
        interval: TimeInterval,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        let nanoseconds = UInt64(
            (max(0, interval) * 1_000_000_000).rounded(.up)
        )
        task = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
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
final class SwitcherSearchScheduler: SwitcherSearchScheduling {
    func schedule(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any SwitcherSearchCancellable {
        SwitcherSearchScheduledTask(
            interval: interval,
            action: action
        )
    }
}

@MainActor
protocol SwitcherSearchClockReading: AnyObject {
    var monotonicNanoseconds: UInt64 { get }
}

@MainActor
final class SystemSwitcherSearchClock: SwitcherSearchClockReading {
    var monotonicNanoseconds: UInt64 {
        UInt64(
            (ProcessInfo.processInfo.systemUptime * 1_000_000_000)
                .rounded(.down)
        )
    }
}

@MainActor
protocol SwitcherSearchComputationExecuting: AnyObject {
    func execute(
        input: SwitcherSearchCoordinator.ComputationInput,
        completion: @escaping @MainActor @Sendable (
            SwitcherSearchCoordinator.ComputationOutput
        ) -> Void
    ) -> any SwitcherSearchCancellable
}

private final class SwitcherSearchComputationTask:
    SwitcherSearchCancellable
{
    private let computationTask:
        Task<SwitcherSearchCoordinator.ComputationOutput?, Never>
    private let deliveryTask: Task<Void, Never>

    @MainActor
    init(
        input: SwitcherSearchCoordinator.ComputationInput,
        completion: @escaping @MainActor @Sendable (
            SwitcherSearchCoordinator.ComputationOutput
        ) -> Void
    ) {
        let computationTask = Task.detached(priority: .userInitiated) {
            SwitcherSearchCoordinator.computeOutputIfNotCancelled(
                from: input
            )
        }
        self.computationTask = computationTask
        deliveryTask = Task { @MainActor in
            let output = await computationTask.value
            guard !Task.isCancelled, let output else { return }
            completion(output)
        }
    }

    func cancel() {
        computationTask.cancel()
        deliveryTask.cancel()
    }

    deinit {
        computationTask.cancel()
        deliveryTask.cancel()
    }
}

@MainActor
final class SwitcherSearchComputationExecutor:
    SwitcherSearchComputationExecuting
{
    func execute(
        input: SwitcherSearchCoordinator.ComputationInput,
        completion: @escaping @MainActor @Sendable (
            SwitcherSearchCoordinator.ComputationOutput
        ) -> Void
    ) -> any SwitcherSearchCancellable {
        SwitcherSearchComputationTask(
            input: input,
            completion: completion
        )
    }
}

@MainActor
private final class SwitcherSearchCallbackRegistration {
    var didInvoke = false
}

@MainActor
final class SwitcherSearchSchedulingOwner {
    private let scheduler: any SwitcherSearchScheduling
    private let clock: any SwitcherSearchClockReading
    private let computationExecutor:
        any SwitcherSearchComputationExecuting
    private let policy: SwitcherSearchSchedulingPolicy

    private(set) var pendingDebounceToken:
        (any SwitcherSearchCancellable)?
    private(set) var pendingComputationToken:
        (any SwitcherSearchCancellable)?
    private(set) var revision: UInt64 = 0
    private(set) var debounceInterval: TimeInterval
    private(set) var lastCompletedDiagnostic:
        SwitcherSearchComputationDiagnostic?
    private var scheduledAtNanoseconds: UInt64?

    var hasPendingWork: Bool {
        pendingDebounceToken != nil
            || pendingComputationToken != nil
    }

    init(
        scheduler: (any SwitcherSearchScheduling)? = nil,
        clock: (any SwitcherSearchClockReading)? = nil,
        computationExecutor:
            (any SwitcherSearchComputationExecuting)? = nil,
        policy: SwitcherSearchSchedulingPolicy = .standard
    ) {
        self.scheduler = scheduler ?? SwitcherSearchScheduler()
        self.clock = clock ?? SystemSwitcherSearchClock()
        self.computationExecutor =
            computationExecutor ?? SwitcherSearchComputationExecutor()
        self.policy = policy
        debounceInterval = policy.initialDebounceInterval
    }

    func schedule(
        input: SwitcherSearchCoordinator.ComputationInput,
        debounced: Bool,
        completion: @escaping @MainActor @Sendable (
            SwitcherSearchCoordinator.ComputationOutput
        ) -> Void
    ) {
        cancel()
        let scheduledRevision = revision
        scheduledAtNanoseconds = clock.monotonicNanoseconds
        guard debounced else {
            startComputation(
                input: input,
                revision: scheduledRevision,
                completion: completion
            )
            return
        }

        let registration = SwitcherSearchCallbackRegistration()
        let token = scheduler.schedule(
            after: debounceInterval
        ) { [weak self, registration] in
            registration.didInvoke = true
            self?.startComputation(
                input: input,
                revision: scheduledRevision,
                completion: completion
            )
        }
        guard !registration.didInvoke else {
            token.cancel()
            return
        }
        guard scheduledRevision == revision else {
            token.cancel()
            return
        }
        pendingDebounceToken = token
    }

    func cancel() {
        pendingDebounceToken?.cancel()
        pendingDebounceToken = nil
        pendingComputationToken?.cancel()
        pendingComputationToken = nil
        scheduledAtNanoseconds = nil
        revision &+= 1
    }

    private func startComputation(
        input: SwitcherSearchCoordinator.ComputationInput,
        revision scheduledRevision: UInt64,
        completion: @escaping @MainActor @Sendable (
            SwitcherSearchCoordinator.ComputationOutput
        ) -> Void
    ) {
        guard scheduledRevision == revision else { return }
        pendingDebounceToken?.cancel()
        pendingDebounceToken = nil
        pendingComputationToken?.cancel()
        pendingComputationToken = nil
        let startedAtNanoseconds = clock.monotonicNanoseconds
        let registration = SwitcherSearchCallbackRegistration()
        let token = computationExecutor.execute(
            input: input
        ) { [weak self, registration] output in
            registration.didInvoke = true
            self?.finishComputation(
                output,
                revision: scheduledRevision,
                startedAtNanoseconds: startedAtNanoseconds,
                completion: completion
            )
        }
        guard !registration.didInvoke else {
            token.cancel()
            return
        }
        guard scheduledRevision == revision else {
            token.cancel()
            return
        }
        pendingComputationToken = token
    }

    private func finishComputation(
        _ output: SwitcherSearchCoordinator.ComputationOutput,
        revision scheduledRevision: UInt64,
        startedAtNanoseconds: UInt64,
        completion: @escaping @MainActor @Sendable (
            SwitcherSearchCoordinator.ComputationOutput
        ) -> Void
    ) {
        guard scheduledRevision == revision else { return }
        pendingComputationToken = nil
        let finishedAtNanoseconds = clock.monotonicNanoseconds
        let elapsedNanoseconds: UInt64
        if finishedAtNanoseconds >= startedAtNanoseconds {
            elapsedNanoseconds =
                finishedAtNanoseconds - startedAtNanoseconds
        } else {
            elapsedNanoseconds = 0
        }
        debounceInterval = policy.debounceInterval(
            afterComputationNanoseconds: elapsedNanoseconds
        )
        lastCompletedDiagnostic =
            SwitcherSearchComputationDiagnostic(
                query: output.query,
                scope: output.scope,
                revision: scheduledRevision,
                scheduledAtNanoseconds:
                    scheduledAtNanoseconds
                        ?? startedAtNanoseconds,
                startedAtNanoseconds: startedAtNanoseconds,
                finishedAtNanoseconds: finishedAtNanoseconds
            )
        scheduledAtNanoseconds = nil
        completion(output)
    }
}
