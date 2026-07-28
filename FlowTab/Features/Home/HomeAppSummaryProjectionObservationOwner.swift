import Combine
import Foundation

enum HomeAppSummaryProjectionObservationSource: String, Equatable {
    case initialReadback
    case maintenanceRequestReadback
    case appSwitcherProjectionNotification
}

struct HomeAppSummaryProjectionObservationEvidence: Equatable {
    let observationGeneration: UInt64
    let readbackCount: Int
    let source: HomeAppSummaryProjectionObservationSource
    let transition: HomeAppSummaryProjectionTransition
    let projectionRead: HomeAppSummaryProjectionRead

    var shouldApply: Bool {
        transition.shouldApply
    }
}

@MainActor
final class HomeAppSummaryProjectionObservationOwner: ObservableObject {
    private struct Observation {
        let generation: UInt64
        let reason: String
        let onEvidence:
            @MainActor (HomeAppSummaryProjectionObservationEvidence) -> Void
        var readbackCount: Int
        var lastAcceptedState: HomeAppSummaryProjectionState?
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
            @escaping @MainActor (HomeAppSummaryProjectionObservationEvidence) -> Void
    ) -> HomeAppSummaryProjectionObservationEvidence {
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
        if observation?.generation == generation,
           !initialEvidence.projectionRead.isProjectionBacked {
            requestMaintenance(
                reason: "initialProjectionMissing",
                generation: generation
            )
        }
        return initialEvidence
    }

    func requestMaintenance(reason: String) {
        guard let generation = observation?.generation else { return }
        requestMaintenance(reason: reason, generation: generation)
    }

    func stop(reason: String) {
        guard let active = takeObservation() else { return }
        RuntimeLog.debug(
            .projection,
            [
                "homeAppSummaryProjectionObservation",
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

    private func requestMaintenance(
        reason: String,
        generation: UInt64
    ) {
        guard observation?.generation == generation else { return }
        RuntimeLog.debug(
            .projection,
            [
                "homeAppSummaryProjectionObservation",
                "state=maintenanceRequested",
                "generation=\(generation)",
                "reason=\(reason)"
            ].joined(separator: " ")
        )
        runtimeProjectionService.requestAppSwitcherProjectionMaintenance(
            reason: .homeProjectionMissing
        )
        if observation?.generation == generation {
            _ = readback(
                source: .maintenanceRequestReadback,
                generation: generation
            )
        }
    }

    @discardableResult
    private func readback(
        source: HomeAppSummaryProjectionObservationSource,
        generation: UInt64
    ) -> HomeAppSummaryProjectionObservationEvidence? {
        guard var active = observation,
              active.generation == generation
        else {
            return nil
        }

        let projectionRead = HomeAppSummaryProjectionReadback
            .read(from: runtimeProjectionService)
        let state = HomeAppSummaryProjectionState(projectionRead)
        let transition = HomeAppSummaryProjectionTransitionResolver.transition(
            from: active.lastAcceptedState,
            to: state
        )
        active.readbackCount += 1
        if transition.shouldApply {
            active.lastAcceptedState = state
        }
        observation = active

        let evidence = HomeAppSummaryProjectionObservationEvidence(
            observationGeneration: generation,
            readbackCount: active.readbackCount,
            source: source,
            transition: transition,
            projectionRead: projectionRead
        )
        active.onEvidence(evidence)
        return evidence
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
