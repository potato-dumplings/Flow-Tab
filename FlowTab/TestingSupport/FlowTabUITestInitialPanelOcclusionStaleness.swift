#if FLOWTAB_TESTING
import Foundation

struct FlowTabUITestInitialPanelOcclusionStalenessPolicy:
    Equatable,
    Sendable
{
    static let minimumMilliseconds = 1
    static let maximumMilliseconds = 5_000

    let milliseconds: Int

    init(rawMilliseconds: Int) {
        milliseconds = min(
            Self.maximumMilliseconds,
            max(
                Self.minimumMilliseconds,
                rawMilliseconds
            )
        )
    }

    var interval: TimeInterval {
        TimeInterval(milliseconds) / 1_000
    }
}

struct FlowTabUITestInitialPanelOcclusionReadback:
    Equatable,
    Sendable
{
    let panelIsAvailable: Bool
    let overrideIsInstalled: Bool
    let overrideContainsVisible: Bool

    static let unavailable =
        FlowTabUITestInitialPanelOcclusionReadback(
            panelIsAvailable: false,
            overrideIsInstalled: false,
            overrideContainsVisible: false
        )
}

enum FlowTabUITestInitialPanelOcclusionStalenessPhase:
    String,
    Equatable,
    Sendable
{
    case installed
    case released
    case cancelled
}

struct FlowTabUITestInitialPanelOcclusionStalenessEvidence:
    Equatable,
    Sendable
{
    let ownerGeneration: UInt64
    let transitionGeneration: UInt64
    let phase:
        FlowTabUITestInitialPanelOcclusionStalenessPhase
    let policy:
        FlowTabUITestInitialPanelOcclusionStalenessPolicy
    let readback:
        FlowTabUITestInitialPanelOcclusionReadback

    var logFields: String {
        "ownerGeneration=\(ownerGeneration) "
            + "transitionGeneration=\(transitionGeneration) "
            + "phase=\(phase.rawValue) "
            + "staleMs=\(policy.milliseconds) "
            + "panelAvailable=\(readback.panelIsAvailable) "
            + "overrideInstalled=\(readback.overrideIsInstalled) "
            + "overrideVisible=\(readback.overrideContainsVisible)"
    }
}

@MainActor
protocol FlowTabUITestInitialPanelOcclusionCancellable:
    AnyObject
{
    func cancel()
}

@MainActor
protocol FlowTabUITestInitialPanelOcclusionScheduling:
    AnyObject
{
    func schedule(
        after interval: TimeInterval,
        _ action:
            @escaping @MainActor @Sendable () -> Void
    ) -> any FlowTabUITestInitialPanelOcclusionCancellable
}

@MainActor
private final class
    FlowTabUITestInitialPanelOcclusionReleaseToken:
    FlowTabUITestInitialPanelOcclusionCancellable
{
    private let task: Task<Void, Never>

    init(
        interval: TimeInterval,
        action:
            @escaping @MainActor @Sendable () -> Void
    ) {
        let nanoseconds = UInt64(
            (interval * 1_000_000_000).rounded()
        )
        task = Task { @MainActor in
            do {
                try await Task.sleep(
                    nanoseconds: nanoseconds
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
final class FlowTabUITestInitialPanelOcclusionScheduler:
    FlowTabUITestInitialPanelOcclusionScheduling
{
    func schedule(
        after interval: TimeInterval,
        _ action:
            @escaping @MainActor @Sendable () -> Void
    ) -> any FlowTabUITestInitialPanelOcclusionCancellable {
        FlowTabUITestInitialPanelOcclusionReleaseToken(
            interval: interval,
            action: action
        )
    }
}

@MainActor
final class FlowTabUITestInitialPanelOcclusionStalenessOwner {
    typealias Mutation =
        @MainActor () ->
            FlowTabUITestInitialPanelOcclusionReadback
    typealias EvidenceHandler =
        @MainActor (
            FlowTabUITestInitialPanelOcclusionStalenessEvidence
        ) -> Void

    private struct ActiveInjection {
        let ownerGeneration: UInt64
        let policy:
            FlowTabUITestInitialPanelOcclusionStalenessPolicy
        let release: Mutation
        let cancelInjection: Mutation
        let onEvidence: EvidenceHandler
        var releaseToken:
            (any FlowTabUITestInitialPanelOcclusionCancellable)?
    }

    private let scheduler:
        any FlowTabUITestInitialPanelOcclusionScheduling
    private var active: ActiveInjection?

    private(set) var ownerGeneration: UInt64 = 0
    private(set) var transitionGeneration: UInt64 = 0
    private(set) var lastEvidence:
        FlowTabUITestInitialPanelOcclusionStalenessEvidence?

    init(
        scheduler:
            (any FlowTabUITestInitialPanelOcclusionScheduling)? =
                nil
    ) {
        self.scheduler = scheduler
            ?? FlowTabUITestInitialPanelOcclusionScheduler()
    }

    var isActive: Bool {
        active != nil
    }

    var hasPendingRelease: Bool {
        active?.releaseToken != nil
    }

    @discardableResult
    func start(
        policy:
            FlowTabUITestInitialPanelOcclusionStalenessPolicy,
        install: Mutation,
        release: @escaping Mutation,
        cancelInjection: @escaping Mutation,
        onEvidence: @escaping EvidenceHandler
    ) -> UInt64 {
        cancel(invalidate: false)
        ownerGeneration &+= 1
        let generation = ownerGeneration
        active = ActiveInjection(
            ownerGeneration: generation,
            policy: policy,
            release: release,
            cancelInjection: cancelInjection,
            onEvidence: onEvidence,
            releaseToken: nil
        )

        publish(
            phase: .installed,
            readback: install(),
            generation: generation
        )
        guard active?.ownerGeneration == generation
        else {
            return generation
        }

        let token = scheduler.schedule(
            after: policy.interval
        ) { [weak self] in
            self?.release(generation: generation)
        }
        guard var current = active,
              current.ownerGeneration == generation
        else {
            token.cancel()
            return generation
        }
        current.releaseToken = token
        active = current
        return generation
    }

    func cancel() {
        cancel(invalidate: true)
    }

    deinit {
        guard let abandoned = active else { return }
        let releaseToken = abandoned.releaseToken
        let cancelInjection = abandoned.cancelInjection
        Task { @MainActor [
            releaseToken,
            cancelInjection
        ] in
            releaseToken?.cancel()
            _ = cancelInjection()
        }
    }

    private func release(generation: UInt64) {
        guard let completed = takeActive(
            generation: generation
        ) else {
            return
        }
        publish(
            phase: .released,
            readback: completed.release(),
            completed: completed
        )
    }

    private func cancel(invalidate: Bool) {
        guard let completed = takeActive()
        else {
            if invalidate {
                ownerGeneration &+= 1
            }
            return
        }
        publish(
            phase: .cancelled,
            readback: completed.cancelInjection(),
            completed: completed
        )
        if invalidate {
            ownerGeneration &+= 1
        }
    }

    private func takeActive(
        generation: UInt64? = nil
    ) -> ActiveInjection? {
        guard let active,
              generation == nil
                || active.ownerGeneration == generation
        else {
            return nil
        }
        self.active = nil
        active.releaseToken?.cancel()
        return active
    }

    private func publish(
        phase:
            FlowTabUITestInitialPanelOcclusionStalenessPhase,
        readback:
            FlowTabUITestInitialPanelOcclusionReadback,
        generation: UInt64
    ) {
        guard let active,
              active.ownerGeneration == generation
        else {
            return
        }
        publish(
            phase: phase,
            readback: readback,
            completed: active
        )
    }

    private func publish(
        phase:
            FlowTabUITestInitialPanelOcclusionStalenessPhase,
        readback:
            FlowTabUITestInitialPanelOcclusionReadback,
        completed: ActiveInjection
    ) {
        transitionGeneration &+= 1
        let evidence =
            FlowTabUITestInitialPanelOcclusionStalenessEvidence(
                ownerGeneration:
                    completed.ownerGeneration,
                transitionGeneration:
                    transitionGeneration,
                phase: phase,
                policy: completed.policy,
                readback: readback
            )
        lastEvidence = evidence
        completed.onEvidence(evidence)
    }
}
#endif
