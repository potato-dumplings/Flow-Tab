import Foundation

struct DelayedWindowLayerEntrySnapshot: Equatable {
    let presentationGeneration: Int
    let selectedAppID: String?
    let selectedWindowCount: Int
    let projectionGeneration: UInt64
    let isPanelPresented: Bool
    let isAppLayer: Bool
    let isSearchActive: Bool
    let canAutoEnterWindowLayer: Bool

    func isReady(
        for appID: String,
        presentationGeneration: Int
    ) -> Bool {
        self.presentationGeneration == presentationGeneration
            && selectedAppID == appID
            && selectedWindowCount >= 2
            && isPanelPresented
            && isAppLayer
            && !isSearchActive
            && canAutoEnterWindowLayer
    }

    var logFields: String {
        "presentationGeneration=\(presentationGeneration) "
            + "selectedAppID=\(selectedAppID ?? "nil") "
            + "selectedWindowCount=\(selectedWindowCount) "
            + "projectionGeneration=\(projectionGeneration) "
            + "panelPresented=\(isPanelPresented ? 1 : 0) "
            + "appLayer=\(isAppLayer ? 1 : 0) "
            + "searchActive=\(isSearchActive ? 1 : 0) "
            + "canAutoEnter=\(canAutoEnterWindowLayer ? 1 : 0)"
    }
}

enum DelayedWindowLayerEntryEvidenceSource: String, Equatable {
    case initialReadback
    case projectionRequestReturnReadback
    case sessionLayoutChanged
    case appSwitcherProjectionUpdated
    case currentAppWindowProjectionUpdated
    case deadlineReadback
}

struct DelayedWindowLayerEntryEvidence: Equatable {
    let source: DelayedWindowLayerEntryEvidenceSource
    let observationGeneration: Int
    let targetAppID: String
    let presentationGeneration: Int
    let baselineProjectionGeneration: UInt64
    let deadlineMilliseconds: Double
    let observedAtMilliseconds: Double
    let deadlineReached: Bool
    let snapshot: DelayedWindowLayerEntrySnapshot

    var overshootMilliseconds: Double {
        max(0, observedAtMilliseconds - deadlineMilliseconds)
    }

    var logFields: String {
        "source=\(source.rawValue) "
            + "observationGeneration=\(observationGeneration) "
            + "targetAppID=\(targetAppID) "
            + "baselineProjectionGeneration=\(baselineProjectionGeneration) "
            + "deadlineMs=\(deadlineMilliseconds) "
            + "observedAtMs=\(observedAtMilliseconds) "
            + "deadlineReached=\(deadlineReached ? 1 : 0) "
            + "snapshot{\(snapshot.logFields)}"
    }
}

@MainActor
final class DelayedWindowLayerEntryObservationOwner {
    private struct PendingObservation {
        let generation: Int
        let targetAppID: String
        let presentationGeneration: Int
        let baselineProjectionGeneration: UInt64
        let deadlineMilliseconds: Double
        let readback:
            @MainActor () -> DelayedWindowLayerEntrySnapshot
        let onReady:
            @MainActor (DelayedWindowLayerEntryEvidence) -> Void
        var deadlineReached: Bool
        var lastEvidence: DelayedWindowLayerEntryEvidence
        var deadlineToken:
            (any DelayedWindowLayerEntryCancellable)?
    }

    private let scheduler: any DelayedWindowLayerEntryScheduling
    private var pending: PendingObservation?

    private(set) var generation = 0

    init(
        scheduler:
            (any DelayedWindowLayerEntryScheduling)? = nil
    ) {
        self.scheduler = scheduler
            ?? DelayedWindowLayerEntryScheduler()
    }

    var isObserving: Bool {
        pending != nil
    }

    var targetAppID: String? {
        pending?.targetAppID
    }

    var deadlineMilliseconds: Double? {
        pending?.deadlineMilliseconds
    }

    var lastEvidence: DelayedWindowLayerEntryEvidence? {
        pending?.lastEvidence
    }

    func matches(
        targetAppID: String,
        presentationGeneration: Int
    ) -> Bool {
        guard let pending else { return false }
        return pending.targetAppID == targetAppID
            && pending.presentationGeneration == presentationGeneration
    }

    @discardableResult
    func start(
        targetAppID: String,
        presentationGeneration: Int,
        delay: TimeInterval,
        readback:
            @escaping @MainActor () -> DelayedWindowLayerEntrySnapshot,
        onReady:
            @escaping @MainActor (DelayedWindowLayerEntryEvidence) -> Void
    ) -> Int {
        precondition(
            delay.isFinite && delay >= 0,
            "Window-layer auto-entry delay must be finite and nonnegative."
        )
        cancel(invalidate: false)
        generation += 1
        let observationGeneration = generation
        let baseline = readback()
        let nowMilliseconds = scheduler.nowMilliseconds
        let deadlineMilliseconds =
            nowMilliseconds + delay * 1_000
        let deadlineReached =
            nowMilliseconds >= deadlineMilliseconds
        let initialEvidence = DelayedWindowLayerEntryEvidence(
            source: .initialReadback,
            observationGeneration: observationGeneration,
            targetAppID: targetAppID,
            presentationGeneration: presentationGeneration,
            baselineProjectionGeneration:
                baseline.projectionGeneration,
            deadlineMilliseconds: deadlineMilliseconds,
            observedAtMilliseconds: nowMilliseconds,
            deadlineReached: deadlineReached,
            snapshot: baseline
        )
        pending = PendingObservation(
            generation: observationGeneration,
            targetAppID: targetAppID,
            presentationGeneration: presentationGeneration,
            baselineProjectionGeneration:
                baseline.projectionGeneration,
            deadlineMilliseconds: deadlineMilliseconds,
            readback: readback,
            onReady: onReady,
            deadlineReached: deadlineReached,
            lastEvidence: initialEvidence
        )

        if resolveIfReady() {
            return observationGeneration
        }
        if !deadlineReached {
            scheduleRemainingDeadline(
                observationGeneration: observationGeneration,
                presentationGeneration: presentationGeneration
            )
        }
        return observationGeneration
    }

    @discardableResult
    func observe(
        source: DelayedWindowLayerEntryEvidenceSource,
        eventAppID: String? = nil,
        observationGeneration: Int,
        presentationGeneration: Int
    ) -> Bool {
        guard var active = matchingPending(
            observationGeneration: observationGeneration,
            presentationGeneration: presentationGeneration
        ) else {
            return false
        }
        if source == .currentAppWindowProjectionUpdated,
           eventAppID != active.targetAppID {
            return false
        }
        let evidence = makeEvidence(
            source: source,
            pending: active
        )
        active.deadlineReached = evidence.deadlineReached
        active.lastEvidence = evidence
        if active.deadlineReached {
            active.deadlineToken?.cancel()
            active.deadlineToken = nil
        }
        pending = active
        return resolveIfReady()
    }

    func cancel(invalidate: Bool = true) {
        pending?.deadlineToken?.cancel()
        pending = nil
        if invalidate {
            generation += 1
        }
    }

    private func deadlineDidFire(
        observationGeneration: Int,
        presentationGeneration: Int
    ) {
        guard var active = matchingPending(
            observationGeneration: observationGeneration,
            presentationGeneration: presentationGeneration
        ) else {
            return
        }
        let evidence = makeEvidence(
            source: .deadlineReadback,
            pending: active
        )
        active.deadlineReached = evidence.deadlineReached
        active.lastEvidence = evidence
        active.deadlineToken = nil
        pending = active

        if resolveIfReady() || active.deadlineReached {
            return
        }
        scheduleRemainingDeadline(
            observationGeneration: observationGeneration,
            presentationGeneration: presentationGeneration
        )
    }

    private func scheduleRemainingDeadline(
        observationGeneration: Int,
        presentationGeneration: Int
    ) {
        guard let active = matchingPending(
            observationGeneration: observationGeneration,
            presentationGeneration: presentationGeneration
        ) else {
            return
        }
        let remainingInterval = max(
            0,
            (active.deadlineMilliseconds
                - scheduler.nowMilliseconds) / 1_000
        )
        let token = scheduler.scheduleDeadline(
            after: remainingInterval
        ) { [weak self] in
            self?.deadlineDidFire(
                observationGeneration: observationGeneration,
                presentationGeneration: presentationGeneration
            )
        }
        guard var matching = matchingPending(
            observationGeneration: observationGeneration,
            presentationGeneration: presentationGeneration
        ) else {
            token.cancel()
            return
        }
        matching.deadlineToken?.cancel()
        matching.deadlineToken = token
        pending = matching
    }

    private func makeEvidence(
        source: DelayedWindowLayerEntryEvidenceSource,
        pending: PendingObservation
    ) -> DelayedWindowLayerEntryEvidence {
        let observedAtMilliseconds = scheduler.nowMilliseconds
        return DelayedWindowLayerEntryEvidence(
            source: source,
            observationGeneration: pending.generation,
            targetAppID: pending.targetAppID,
            presentationGeneration:
                pending.presentationGeneration,
            baselineProjectionGeneration:
                pending.baselineProjectionGeneration,
            deadlineMilliseconds: pending.deadlineMilliseconds,
            observedAtMilliseconds: observedAtMilliseconds,
            deadlineReached: pending.deadlineReached
                || observedAtMilliseconds
                    >= pending.deadlineMilliseconds,
            snapshot: pending.readback()
        )
    }

    private func resolveIfReady() -> Bool {
        guard
            let active = pending,
            active.deadlineReached,
            active.lastEvidence.snapshot.isReady(
                for: active.targetAppID,
                presentationGeneration:
                    active.presentationGeneration
            )
        else {
            return false
        }
        guard let completed = takePending() else { return false }
        completed.onReady(completed.lastEvidence)
        return true
    }

    private func matchingPending(
        observationGeneration: Int,
        presentationGeneration: Int
    ) -> PendingObservation? {
        guard
            let pending,
            pending.generation == observationGeneration,
            pending.presentationGeneration
                == presentationGeneration
        else {
            return nil
        }
        return pending
    }

    private func takePending() -> PendingObservation? {
        guard let pending else { return nil }
        self.pending = nil
        pending.deadlineToken?.cancel()
        return pending
    }
}
