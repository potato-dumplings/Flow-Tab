import Combine
import Foundation

enum HomeAppDetailProjectionRequest {
    case selected(appID: String, pid: pid_t)

    var appID: String {
        switch self {
        case let .selected(appID, _):
            appID
        }
    }

    var pid: pid_t {
        switch self {
        case let .selected(_, pid):
            pid
        }
    }

    func perform(using service: any RuntimeProjectionServing) {
        switch self {
        case let .selected(appID, pid):
            service.signalSelectedCurrentAppWindowsChanged(
                appID: appID,
                pid: pid
            )
        }
    }
}

enum HomeAppDetailProjectionObservationSource: String, Equatable {
    case initialReadback
    case requestReturnReadback
    case currentAppWindowProjectionNotification
}

struct HomeAppDetailProjectionObservationEvidence {
    let appID: String
    let observationGeneration: UInt64
    let readbackCount: Int
    let source: HomeAppDetailProjectionObservationSource
    let transition: HomeProjectionEvidenceTransition
    let projection: RuntimeHomeAppDetailProjection?

    var shouldApply: Bool {
        transition.shouldApply
            && projection != nil
    }

    var isComplete: Bool {
        projection?.freshness.isCompleteForScope == true
    }

    var completesObservation: Bool {
        source != .initialReadback
            && shouldApply
            && isComplete
    }
}

@MainActor
final class HomeAppDetailProjectionObservationOwner: ObservableObject {
    private struct Observation {
        let appID: String
        let generation: UInt64
        let reason: String
        let onEvidence:
            @MainActor (HomeAppDetailProjectionObservationEvidence) -> Void
        var readbackCount: Int
        var lastAcceptedState: HomeProjectionEvidenceState?
    }

    private let runtimeProjectionService: any RuntimeProjectionServing
    private let notificationCenter: NotificationCenter
    private let notificationObject: AnyObject
    private var nextGeneration: UInt64 = 1
    private var observationsByAppID: [String: Observation] = [:]
    private var observerToken: NSObjectProtocol?

    init(
        runtimeProjectionService: any RuntimeProjectionServing,
        notificationCenter: NotificationCenter = .default
    ) {
        self.runtimeProjectionService = runtimeProjectionService
        self.notificationCenter = notificationCenter
        notificationObject = runtimeProjectionService as AnyObject
    }

    var observationCount: Int {
        observationsByAppID.count
    }

    func isObserving(appID: String) -> Bool {
        observationsByAppID[appID] != nil
    }

    @discardableResult
    func request(
        _ request: HomeAppDetailProjectionRequest,
        reason: String,
        onEvidence:
            @escaping @MainActor (HomeAppDetailProjectionObservationEvidence) -> Void
    ) -> HomeAppDetailProjectionObservationEvidence {
        self.request(
            appID: request.appID,
            reason: reason,
            performRequest: {
                request.perform(using: runtimeProjectionService)
            },
            onEvidence: onEvidence
        )
    }

    @discardableResult
    func request(
        appID: String,
        reason: String,
        performRequest: () -> Void,
        onEvidence:
            @escaping @MainActor (HomeAppDetailProjectionObservationEvidence) -> Void
    ) -> HomeAppDetailProjectionObservationEvidence {
        cancel(appID: appID, reason: "superseded")

        let generation = nextGeneration
        nextGeneration &+= 1
        observationsByAppID[appID] = Observation(
            appID: appID,
            generation: generation,
            reason: reason,
            onEvidence: onEvidence,
            readbackCount: 0,
            lastAcceptedState: nil
        )
        installObserverIfNeeded()

        let initialEvidence = readback(
            appID: appID,
            source: .initialReadback,
            generation: generation
        )!
        guard observationsByAppID[appID]?.generation == generation else {
            return initialEvidence
        }

        performRequest()
        if observationsByAppID[appID]?.generation == generation {
            _ = readback(
                appID: appID,
                source: .requestReturnReadback,
                generation: generation
            )
        }
        return initialEvidence
    }

    func cancel(appID: String, reason: String) {
        guard let active = takeObservation(appID: appID) else { return }
        RuntimeLog.debug(
            .projection,
            [
                "homeAppDetailProjectionObservation",
                "state=cancelled",
                "appID=\(appID)",
                "generation=\(active.generation)",
                "reason=\(reason)",
                "requestReason=\(active.reason)",
                "readbacks=\(active.readbackCount)"
            ].joined(separator: " ")
        )
    }

    func retainObservations(for appIDs: Set<String>) {
        let removedAppIDs = Set(observationsByAppID.keys).subtracting(appIDs)
        for appID in removedAppIDs {
            cancel(appID: appID, reason: "appNoLongerPresented")
        }
    }

    func stopAll(reason: String) {
        let activeAppIDs = observationsByAppID.keys.sorted()
        for appID in activeAppIDs {
            cancel(appID: appID, reason: reason)
        }
    }

    deinit {
        if let observerToken {
            notificationCenter.removeObserver(observerToken)
        }
    }

    private func installObserverIfNeeded() {
        guard observerToken == nil else { return }
        observerToken = notificationCenter.addObserver(
            forName: .runtimeCurrentAppWindowProjectionDidUpdate,
            object: notificationObject,
            queue: .main
        ) { [weak self] notification in
            guard let appID = notification.userInfo?[
                RuntimeProjectionNotificationUserInfoKey.appID
            ] as? String else {
                return
            }
            MainActor.assumeIsolated {
                guard let generation =
                    self?.observationsByAppID[appID]?.generation
                else {
                    return
                }
                _ = self?.readback(
                    appID: appID,
                    source: .currentAppWindowProjectionNotification,
                    generation: generation
                )
            }
        }
    }

    @discardableResult
    private func readback(
        appID: String,
        source: HomeAppDetailProjectionObservationSource,
        generation: UInt64
    ) -> HomeAppDetailProjectionObservationEvidence? {
        guard var active = observationsByAppID[appID],
              active.generation == generation
        else {
            return nil
        }

        let projection = exactProjection(
            runtimeProjectionService
                .readHomeAppDetailProjection(appID: appID),
            appID: appID
        )
        let state = HomeProjectionEvidenceState(projection)
        let transition = HomeProjectionEvidenceTransitionResolver.transition(
            from: active.lastAcceptedState,
            to: state
        )
        active.readbackCount += 1
        if transition.shouldApply {
            active.lastAcceptedState = state
        }
        observationsByAppID[appID] = active

        let evidence = HomeAppDetailProjectionObservationEvidence(
            appID: appID,
            observationGeneration: generation,
            readbackCount: active.readbackCount,
            source: source,
            transition: transition,
            projection: projection
        )
        active.onEvidence(evidence)

        if evidence.completesObservation {
            finish(
                appID: appID,
                generation: generation,
                source: source
            )
        }
        return evidence
    }

    private func finish(
        appID: String,
        generation: UInt64,
        source: HomeAppDetailProjectionObservationSource
    ) {
        guard let active = observationsByAppID[appID],
              active.generation == generation
        else {
            return
        }
        _ = takeObservation(appID: appID)
        RuntimeLog.debug(
            .projection,
            [
                "homeAppDetailProjectionObservation",
                "state=completed",
                "appID=\(appID)",
                "generation=\(generation)",
                "source=\(source.rawValue)",
                "requestReason=\(active.reason)",
                "readbacks=\(active.readbackCount)"
            ].joined(separator: " ")
        )
    }

    private func takeObservation(appID: String) -> Observation? {
        guard let active = observationsByAppID.removeValue(forKey: appID) else {
            return nil
        }
        if observationsByAppID.isEmpty, let observerToken {
            notificationCenter.removeObserver(observerToken)
            self.observerToken = nil
        }
        return active
    }

    private func exactProjection(
        _ projection: RuntimeHomeAppDetailProjection?,
        appID: String
    ) -> RuntimeHomeAppDetailProjection? {
        guard let projection else { return nil }
        guard projection.summary.appID == appID,
              projection.candidate.id == appID,
              projection.context.appID == appID
        else {
            RuntimeLog.debug(
                .projection,
                [
                    "homeAppDetailProjectionObservation",
                    "state=identityRejected",
                    "expectedAppID=\(appID)",
                    "summaryAppID=\(projection.summary.appID)",
                    "candidateAppID=\(projection.candidate.id)",
                    "contextAppID=\(projection.context.appID)"
                ].joined(separator: " ")
            )
            return nil
        }
        return projection
    }
}
