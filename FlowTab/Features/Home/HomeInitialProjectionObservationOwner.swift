import Combine
import Foundation

extension Notification.Name {
    static let homeInitialProjectionObservationDidApply =
        Notification.Name(
            "io.github.potato-dumplings.flowtab."
                + "home-initial-projection-observation-did-apply"
        )
}

enum HomeInitialProjectionObservationSource: String, Equatable {
    case initialReadback
    case maintenanceRequestReadback
    case maintenanceCompletion
    case appSwitcherProjectionNotification
}

struct HomeInitialProjectionObservationEvidence: Equatable {
    let observationGeneration: UInt64
    let readbackCount: Int
    let source: HomeInitialProjectionObservationSource
    let transition: HomeProjectionEvidenceTransition
    let projectionRead: HomeAppSummaryProjectionRead

    var shouldApply: Bool {
        transition.shouldApply
            || source == .maintenanceCompletion
                && projectionRead.isProjectionBacked
    }

    var isReady: Bool {
        projectionRead.isProjectionBacked
            && projectionRead.freshness?.isCompleteForScope == true
    }

    var isReadyForPresentation: Bool {
        isReady
            || source == .maintenanceCompletion
                && projectionRead.isProjectionBacked
    }
}

struct HomeInitialProjectionObservationApplication: Equatable {
    private static let notificationUserInfoKey =
        "homeInitialProjectionObservationApplication"

    let evidence: HomeInitialProjectionObservationEvidence
    let requestReason: String

    init(
        evidence:
            HomeInitialProjectionObservationEvidence,
        requestReason: String
    ) {
        self.evidence = evidence
        self.requestReason = requestReason
    }

    init?(
        notification: Notification
    ) {
        guard notification.name
                == .homeInitialProjectionObservationDidApply,
              let application = notification.userInfo?[
                Self.notificationUserInfoKey
              ] as? Self
        else {
            return nil
        }
        self = application
    }

    var notificationUserInfo: [AnyHashable: Any] {
        [Self.notificationUserInfoKey: self]
    }
}

@MainActor
final class HomeInitialProjectionObservationOwner: ObservableObject {
    private struct Observation {
        let generation: UInt64
        let reason: String
        let onEvidence:
            @MainActor (HomeInitialProjectionObservationEvidence) -> Void
        var readbackCount: Int
        var lastAcceptedState: HomeProjectionEvidenceState?
    }

    private let runtimeProjectionService: any RuntimeProjectionServing
    private let notificationCenter: NotificationCenter
    private let notificationObject: AnyObject
    private var nextGeneration: UInt64 = 1
    private var observation: Observation?
    private var observerTokens: [NSObjectProtocol] = []

    init(
        runtimeProjectionService: any RuntimeProjectionServing,
        notificationCenter: NotificationCenter = .default
    ) {
        self.runtimeProjectionService = runtimeProjectionService
        self.notificationCenter = notificationCenter
        notificationObject = runtimeProjectionService.notificationSource
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
        for observerToken in observerTokens {
            notificationCenter.removeObserver(observerToken)
        }
    }

    private func installObserver(generation: UInt64) {
        observerTokens.append(notificationCenter.addObserver(
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
        })
        observerTokens.append(notificationCenter.addObserver(
            forName: .runtimeAppSwitcherProjectionMaintenanceDidFinish,
            object: notificationObject,
            queue: .main
        ) { [weak self] notification in
            guard RuntimeAppSwitcherProjectionMaintenanceCompletion(
                notification: notification
            )?.reason == .homeProjectionMissing else {
                return
            }
            MainActor.assumeIsolated {
                _ = self?.readback(
                    source: .maintenanceCompletion,
                    generation: generation
                )
            }
        })
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

        let projectionRead = HomeAppSummaryProjectionReadback
            .read(from: runtimeProjectionService)
        let state = HomeProjectionEvidenceState(projectionRead)
        let transition = HomeProjectionEvidenceTransitionResolver.transition(
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

        guard observation?.generation == generation else {
            return evidence
        }
        if evidence.shouldApply, evidence.isReadyForPresentation {
            finish(
                generation: generation,
                source: source,
                reason: evidence.isReady
                    ? "completeProjectionObserved"
                    : "maintenanceCompletedWithDegradedProjection"
            )
        }
        publishApplication(
            evidence,
            requestReason: active.reason
        )
        return evidence
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

    private func publishApplication(
        _ evidence: HomeInitialProjectionObservationEvidence,
        requestReason: String
    ) {
        guard evidence.transition.shouldApply,
              evidence.projectionRead.isProjectionBacked
        else {
            return
        }
        let application =
            HomeInitialProjectionObservationApplication(
                evidence: evidence,
                requestReason: requestReason
            )
        notificationCenter.post(
            name:
                .homeInitialProjectionObservationDidApply,
            object: notificationObject,
            userInfo: application.notificationUserInfo
        )
    }

    private func takeObservation() -> Observation? {
        guard let active = observation else { return nil }
        observation = nil
        for observerToken in observerTokens {
            notificationCenter.removeObserver(observerToken)
        }
        observerTokens.removeAll()
        return active
    }
}
