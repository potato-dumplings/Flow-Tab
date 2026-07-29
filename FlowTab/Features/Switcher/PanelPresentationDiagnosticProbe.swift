import Foundation

struct PanelPresentationDiagnosticPolicy: Equatable {
    let frameSampleInterval: TimeInterval

    static let `default` = PanelPresentationDiagnosticPolicy(
        frameSampleInterval: 0.016
    )
}

enum PanelPresentationDiagnosticProbeSource: String, Equatable {
    case nextMainTurn = "nextTurn"
    case scheduledFrameSample = "frameDelay"
}

struct PanelPresentationDiagnosticProbe: Equatable {
    let source: PanelPresentationDiagnosticProbeSource
    let observationGeneration: Int
    let presentationGeneration: Int
    let kind: String
    let showStartMs: Double
    let presentedMs: Double
    let probeMs: Double

    var elapsedMs: Double {
        probeMs - showStartMs
    }

    var sincePresentedMs: Double {
        probeMs - presentedMs
    }
}

@MainActor
protocol PanelPresentationDiagnosticCancellable: AnyObject {
    func cancel()
}

@MainActor
protocol PanelPresentationDiagnosticScheduling: AnyObject {
    func scheduleNextMainTurn(
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any PanelPresentationDiagnosticCancellable

    func scheduleFrameSample(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any PanelPresentationDiagnosticCancellable
}

@MainActor
private final class PanelPresentationDiagnosticTaskToken:
    PanelPresentationDiagnosticCancellable
{
    private let task: Task<Void, Never>

    init(
        nextMainTurnAction:
            @escaping @MainActor @Sendable () -> Void
    ) {
        task = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            nextMainTurnAction()
        }
    }

    init(
        frameSampleInterval: TimeInterval,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        task = Task { @MainActor in
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(
                        (frameSampleInterval * 1_000_000_000).rounded()
                    )
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
final class PanelPresentationDiagnosticScheduler:
    PanelPresentationDiagnosticScheduling
{
    func scheduleNextMainTurn(
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any PanelPresentationDiagnosticCancellable {
        PanelPresentationDiagnosticTaskToken(
            nextMainTurnAction: action
        )
    }

    func scheduleFrameSample(
        after interval: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any PanelPresentationDiagnosticCancellable {
        PanelPresentationDiagnosticTaskToken(
            frameSampleInterval: interval,
            action: action
        )
    }
}

@MainActor
final class PanelPresentationDiagnosticProbeOwner {
    private enum Phase: Equatable {
        case awaitingNextMainTurn
        case awaitingFrameSample
    }

    private struct PendingProbe {
        let generation: Int
        let presentationGeneration: Int
        let kind: String
        let showStartMs: Double
        let presentedMs: Double
        let now: @MainActor () -> Double
        let onProbe:
            @MainActor (PanelPresentationDiagnosticProbe) -> Void
        var phase: Phase
        var token: (any PanelPresentationDiagnosticCancellable)?
    }

    private let scheduler: any PanelPresentationDiagnosticScheduling
    private let policy: PanelPresentationDiagnosticPolicy
    private var pending: PendingProbe?

    private(set) var generation = 0
    private(set) var lastProbe: PanelPresentationDiagnosticProbe?

    init(
        scheduler:
            (any PanelPresentationDiagnosticScheduling)? = nil,
        policy: PanelPresentationDiagnosticPolicy = .default
    ) {
        self.scheduler = scheduler
            ?? PanelPresentationDiagnosticScheduler()
        self.policy = policy
    }

    var isPending: Bool {
        pending != nil
    }

    @discardableResult
    func start(
        presentationGeneration: Int,
        kind: String,
        showStartMs: Double,
        presentedMs: Double,
        now: @escaping @MainActor () -> Double,
        onProbe:
            @escaping @MainActor
            (PanelPresentationDiagnosticProbe) -> Void
    ) -> Int {
        precondition(
            policy.frameSampleInterval > 0
                && policy.frameSampleInterval.isFinite,
            "Panel diagnostic frame sample interval must be finite and positive."
        )
        precondition(
            showStartMs.isFinite && presentedMs.isFinite,
            "Panel diagnostic presentation timestamps must be finite."
        )
        cancel(invalidate: false)
        generation += 1
        let probeGeneration = generation
        lastProbe = nil
        pending = PendingProbe(
            generation: probeGeneration,
            presentationGeneration: presentationGeneration,
            kind: kind,
            showStartMs: showStartMs,
            presentedMs: presentedMs,
            now: now,
            onProbe: onProbe,
            phase: .awaitingNextMainTurn,
            token: nil
        )
        scheduleNextMainTurn(generation: probeGeneration)
        return probeGeneration
    }

    func cancel(invalidate: Bool = true) {
        pending?.token?.cancel()
        pending = nil
        if invalidate {
            generation += 1
        }
    }

    private func scheduleNextMainTurn(generation: Int) {
        let token = scheduler.scheduleNextMainTurn { [weak self] in
            self?.recordNextMainTurn(generation: generation)
        }
        guard var active = pending,
              active.generation == generation,
              active.phase == .awaitingNextMainTurn,
              active.token == nil
        else {
            token.cancel()
            return
        }
        active.token = token
        pending = active
    }

    private func recordNextMainTurn(generation: Int) {
        guard var active = pending,
              active.generation == generation,
              active.phase == .awaitingNextMainTurn
        else {
            return
        }
        active.token = nil
        let probe = makeProbe(
            source: .nextMainTurn,
            from: active
        )
        active.phase = .awaitingFrameSample
        pending = active
        lastProbe = probe
        active.onProbe(probe)

        guard let current = pending,
              current.generation == generation,
              current.phase == .awaitingFrameSample,
              current.token == nil
        else {
            return
        }
        scheduleFrameSample(generation: generation)
    }

    private func scheduleFrameSample(generation: Int) {
        let token = scheduler.scheduleFrameSample(
            after: policy.frameSampleInterval
        ) { [weak self] in
            self?.recordFrameSample(generation: generation)
        }
        guard var active = pending,
              active.generation == generation,
              active.phase == .awaitingFrameSample,
              active.token == nil
        else {
            token.cancel()
            return
        }
        active.token = token
        pending = active
    }

    private func recordFrameSample(generation: Int) {
        guard let active = pending,
              active.generation == generation,
              active.phase == .awaitingFrameSample
        else {
            return
        }
        pending = nil
        let probe = makeProbe(
            source: .scheduledFrameSample,
            from: active
        )
        lastProbe = probe
        active.onProbe(probe)
    }

    private func makeProbe(
        source: PanelPresentationDiagnosticProbeSource,
        from pending: PendingProbe
    ) -> PanelPresentationDiagnosticProbe {
        PanelPresentationDiagnosticProbe(
            source: source,
            observationGeneration: pending.generation,
            presentationGeneration: pending.presentationGeneration,
            kind: pending.kind,
            showStartMs: pending.showStartMs,
            presentedMs: pending.presentedMs,
            probeMs: pending.now()
        )
    }
}
