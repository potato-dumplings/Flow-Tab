import Combine
import Foundation

enum HomeInitialProjectionObservationSource: String, Equatable {
    case initialReadback
    case maintenanceRequestReadback
    case appSwitcherProjectionNotification
}

enum HomeInitialProjectionTransition: String, Equatable {
    case baseline
    case projectionBecameAvailable
    case sourceGenerationAdvanced
    case completenessSatisfied
    case unchanged
    case regressed

    var shouldApply: Bool {
        switch self {
        case .baseline,
             .projectionBecameAvailable,
             .sourceGenerationAdvanced,
             .completenessSatisfied:
            true
        case .unchanged, .regressed:
            false
        }
    }
}

struct HomeInitialProjectionObservationEvidence: Equatable {
    let observationGeneration: UInt64
    let readbackCount: Int
    let source: HomeInitialProjectionObservationSource
    let transition: HomeInitialProjectionTransition
    let projectionRead: HomeAppSummaryProjectionRead

    var shouldApply: Bool {
        transition.shouldApply
    }

    var isReady: Bool {
        projectionRead.isProjectionBacked
            && projectionRead.freshness?.isCompleteForScope == true
    }
}

@MainActor
final class HomeInitialProjectionObservationOwner: ObservableObject {
    private struct ProjectionState: Equatable {
        let isProjectionBacked: Bool
        let sourceGeneration: RuntimeReadModelGeneration?
        let isCompleteForScope: Bool

        init(_ read: HomeAppSummaryProjectionRead) {
            isProjectionBacked = read.isProjectionBacked
            sourceGeneration = read.freshness?.sourceGeneration
            isCompleteForScope =
                read.freshness?.isCompleteForScope == true
        }
    }

    private struct Observation {
        let generation: UInt64
        let reason: String
        let onEvidence:
            @MainActor (HomeInitialProjectionObservationEvidence) -> Void
        var readbackCount: Int
        var lastAcceptedState: ProjectionState?
    }

    private let runtimeProjectionService: any RuntimeProjectionServing
    private let notificationCenter: NotificationCenter
    private let notificationObject: AnyObject
    private var nextGeneration: UInt64 = 1
    private var observation: Observation?
    private var observerToken: NSObjectProtocol?

    init(
        runtimeProjectionService: any RuntimeProjectionServing,
        notificationCenter: NotificationCenter = .default
    ) {
        self.runtimeProjectionService = runtimeProjectionService
        self.notificationCenter = notificationCenter
        notificationObject = runtimeProjectionService as AnyObject
    }

    var isObserving: Bool {
        observation != nil
    }

    @discardableResult
    func start(
        reason: String,
        onEvidence:
            @escaping @MainActor (HomeInitialProjectionObservationEvidence) -> Void
    ) -> HomeInitialProjectionObservationEvidence {
        stop(reason: "superseded")

        let generation = nextGeneration
        nextGeneration &+= 1
        observation = Observation(
            generation: generation,
            reason: reason,
            onEvidence: onEvidence,
            readbackCount: 0,
            lastAcceptedState: nil
        )
        installObserver(generation: generation)

        let initialEvidence = readback(
            source: .initialReadback,
            generation: generation
        )!
        guard observation?.generation == generation else {
            return initialEvidence
        }

        runtimeProjectionService.requestAppSwitcherProjectionMaintenance(
            reason: .homeProjectionMissing
        )
        if observation?.generation == generation {
            _ = readback(
                source: .maintenanceRequestReadback,
                generation: generation
            )
        }
        return initialEvidence
    }

    func stop(reason: String) {
        guard let active = takeObservation() else { return }
        RuntimeLog.debug(
            .projection,
            [
                "homeInitialProjectionObservation",
                "state=cancelled",
                "generation=\(active.generation)",
                "reason=\(reason)",
                "requestReason=\(active.reason)",
                "readbacks=\(active.readbackCount)"
            ].joined(separator: " ")
        )
    }

    deinit {
        if let observerToken {
            notificationCenter.removeObserver(observerToken)
        }
    }

    private func installObserver(generation: UInt64) {
        observerToken = notificationCenter.addObserver(
            forName: .runtimeAppSwitcherProjectionDidUpdate,
            object: notificationObject,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                _ = self?.readback(
                    source: .appSwitcherProjectionNotification,
                    generation: generation
                )
            }
        }
    }

    @discardableResult
    private func readback(
        source: HomeInitialProjectionObservationSource,
        generation: UInt64
    ) -> HomeInitialProjectionObservationEvidence? {
        guard var active = observation,
              active.generation == generation
        else {
            return nil
        }

        let projectionRead = HomeInitialAppSummaryReader
            .appSummaryProjection(from: runtimeProjectionService)
        let state = ProjectionState(projectionRead)
        let transition = transition(
            from: active.lastAcceptedState,
            to: state
        )
        active.readbackCount += 1
        if transition.shouldApply {
            active.lastAcceptedState = state
        }
        observation = active

        let evidence = HomeInitialProjectionObservationEvidence(
            observationGeneration: generation,
            readbackCount: active.readbackCount,
            source: source,
            transition: transition,
            projectionRead: projectionRead
        )
        active.onEvidence(evidence)

        guard observation?.generation == generation,
              evidence.shouldApply,
              evidence.isReady
        else {
            return evidence
        }
        finish(
            generation: generation,
            source: source,
            reason: "completeProjectionObserved"
        )
        return evidence
    }

    private func transition(
        from previous: ProjectionState?,
        to current: ProjectionState
    ) -> HomeInitialProjectionTransition {
        guard let previous else { return .baseline }
        guard previous.isProjectionBacked else {
            return current.isProjectionBacked
                ? .projectionBecameAvailable
                : .unchanged
        }
        guard current.isProjectionBacked else { return .regressed }

        switch (previous.sourceGeneration, current.sourceGeneration) {
        case let (previousGeneration?, currentGeneration?):
            if currentGeneration.isStrictlyLater(than: previousGeneration) {
                return .sourceGenerationAdvanced
            }
            if currentGeneration == previousGeneration {
                if !previous.isCompleteForScope,
                   current.isCompleteForScope {
                    return .completenessSatisfied
                }
                return previous.isCompleteForScope
                    && !current.isCompleteForScope
                    ? .regressed
                    : .unchanged
            }
            return .regressed
        case (nil, .some):
            return .sourceGenerationAdvanced
        case (.some, nil):
            return .regressed
        case (nil, nil):
            if !previous.isCompleteForScope,
               current.isCompleteForScope {
                return .completenessSatisfied
            }
            return previous.isCompleteForScope
                && !current.isCompleteForScope
                ? .regressed
                : .unchanged
        }
    }

    private func finish(
        generation: UInt64,
        source: HomeInitialProjectionObservationSource,
        reason: String
    ) {
        guard let active = observation,
              active.generation == generation
        else {
            return
        }
        _ = takeObservation()
        RuntimeLog.info(
            .projection,
            [
                "homeInitialProjectionObservation",
                "state=completed",
                "generation=\(generation)",
                "source=\(source.rawValue)",
                "reason=\(reason)",
                "requestReason=\(active.reason)",
                "readbacks=\(active.readbackCount)"
            ].joined(separator: " ")
        )
    }

    private func takeObservation() -> Observation? {
        guard let active = observation else { return nil }
        observation = nil
        if let observerToken {
            notificationCenter.removeObserver(observerToken)
            self.observerToken = nil
        }
        return active
    }
}

private extension RuntimeReadModelGeneration {
    func isStrictlyLater(
        than other: RuntimeReadModelGeneration
    ) -> Bool {
        appLifecycle >= other.appLifecycle
            && cg >= other.cg
            && space >= other.space
            && axDirty >= other.axDirty
            && projection >= other.projection
            && self != other
    }
}
