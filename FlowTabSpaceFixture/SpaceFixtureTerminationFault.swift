import Foundation

struct SpaceFixtureTerminationFaultPolicy: Equatable {
    let delayMilliseconds: Int

    init?(delayMilliseconds: Int) {
        guard delayMilliseconds > 0 else { return nil }
        self.delayMilliseconds = delayMilliseconds
    }
}

enum SpaceFixtureTerminationFaultRequestDisposition:
    Equatable
{
    case scheduled(requestGeneration: Int)
    case alreadyPending(requestGeneration: Int)
}

@MainActor
final class SpaceFixtureTerminationFaultOwner {
    typealias EvidencePublisher =
        @MainActor (
            SpaceFixtureTerminationFaultEvidence
        ) -> Void

    private struct ActiveRequest {
        let generation: Int
        let source:
            SpaceFixtureTerminationFaultRequestSource
        let apply: @MainActor () -> Void
        var scheduledToken:
            (any SpaceFixtureCancellable)?
    }

    private let policy: SpaceFixtureTerminationFaultPolicy
    private let identity: SpaceFixtureTerminationFaultIdentity
    private let scheduler: any SpaceFixtureScheduling
    private let evidencePublisher: EvidencePublisher
    private var activeRequest: ActiveRequest?

    private(set) var requestGeneration = 0
    private(set) var lastEvidence:
        SpaceFixtureTerminationFaultEvidence?

    init(
        policy: SpaceFixtureTerminationFaultPolicy,
        identity: SpaceFixtureTerminationFaultIdentity,
        scheduler: (any SpaceFixtureScheduling)? = nil,
        evidencePublisher:
            @escaping EvidencePublisher
    ) {
        precondition(
            !identity.bundleIdentifier.isEmpty,
            "Fixture termination identity requires a bundle ID."
        )
        precondition(
            identity.processIdentifier > 0,
            "Fixture termination identity requires a positive PID."
        )
        self.policy = policy
        self.identity = identity
        self.scheduler = scheduler ?? SpaceFixtureScheduler()
        self.evidencePublisher = evidencePublisher
    }

    var isPending: Bool {
        activeRequest != nil
    }

    @discardableResult
    func request(
        source: SpaceFixtureTerminationFaultRequestSource,
        apply: @escaping @MainActor () -> Void
    ) -> SpaceFixtureTerminationFaultRequestDisposition {
        if let activeRequest {
            return .alreadyPending(
                requestGeneration: activeRequest.generation
            )
        }

        requestGeneration += 1
        let generation = requestGeneration
        activeRequest = ActiveRequest(
            generation: generation,
            source: source,
            apply: apply,
            scheduledToken: nil
        )
        publish(
            phase: .scheduled,
            source: source,
            generation: generation
        )

        guard activeRequest?.generation == generation else {
            return .scheduled(
                requestGeneration: generation
            )
        }
        let token = scheduler.schedule(
            afterMilliseconds: policy.delayMilliseconds
        ) { [weak self] in
            self?.apply(requestGeneration: generation)
        }
        guard var current = activeRequest,
              current.generation == generation,
              current.scheduledToken == nil
        else {
            token.cancel()
            return .scheduled(
                requestGeneration: generation
            )
        }
        current.scheduledToken = token
        activeRequest = current
        return .scheduled(
            requestGeneration: generation
        )
    }

    func cancel() {
        activeRequest?.scheduledToken?.cancel()
        activeRequest = nil
    }

    private func apply(requestGeneration: Int) {
        guard let current = activeRequest,
              current.generation == requestGeneration
        else {
            return
        }
        current.scheduledToken?.cancel()
        activeRequest = nil
        publish(
            phase: .applied,
            source: current.source,
            generation: current.generation
        )
        current.apply()
    }

    private func publish(
        phase: SpaceFixtureTerminationFaultEvidencePhase,
        source: SpaceFixtureTerminationFaultRequestSource,
        generation: Int
    ) {
        let evidence = SpaceFixtureTerminationFaultEvidence(
            requestGeneration: generation,
            phase: phase,
            source: source,
            delayMilliseconds: policy.delayMilliseconds,
            identity: identity
        )
        lastEvidence = evidence
        evidencePublisher(evidence)
    }
}
