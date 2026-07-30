#if FLOWTAB_TESTING
import Foundation

enum FlowTabUITestInitialSearchActivationEvidenceSource:
    String,
    Equatable
{
    case initialReadback
    case presentationReadback
    case activationReadback
    case committedSearchIndexDidUpdate
    case watchdogReadback
}

struct FlowTabUITestInitialSearchActivationSnapshot:
    Equatable
{
    let panelIsPresented: Bool
    let sessionItemIDs: [String]
    let searchIsActive: Bool
    let searchActivationIsPending: Bool

    var logFields: String {
        "panelPresented=\(panelIsPresented ? 1 : 0) "
            + "sessionItems=[\(sessionItemIDs.joined(separator: ","))] "
            + "searchActive=\(searchIsActive ? 1 : 0) "
            + "searchPending="
            + "\(searchActivationIsPending ? 1 : 0)"
    }
}

struct FlowTabUITestInitialSearchActivationEvidence:
    Equatable
{
    let observationGeneration: UInt64
    let committedIndexGeneration: UInt64
    let source:
        FlowTabUITestInitialSearchActivationEvidenceSource
    let expectedItemIDs: [String]?
    let snapshot:
        FlowTabUITestInitialSearchActivationSnapshot

    var isSatisfied: Bool {
        guard let expectedItemIDs else { return false }
        return snapshot.panelIsPresented
            && snapshot.sessionItemIDs == expectedItemIDs
            && snapshot.searchIsActive
    }

    var logFields: String {
        "generation=\(observationGeneration) "
            + "committedIndexGeneration="
            + "\(committedIndexGeneration) "
            + "source=\(source.rawValue) "
            + "expected=[\(expectedItemIDs?.joined(separator: ",") ?? "nil")] "
            + "snapshot{\(snapshot.logFields)}"
    }
}

struct FlowTabUITestInitialSearchActivationWatchdogFailure:
    Equatable
{
    let watchdogInterval: TimeInterval
    let lastEvidence:
        FlowTabUITestInitialSearchActivationEvidence
    let finalEvidence:
        FlowTabUITestInitialSearchActivationEvidence

    var logFields: String {
        "watchdog=\(watchdogInterval) "
            + "last{\(lastEvidence.logFields)} "
            + "final{\(finalEvidence.logFields)}"
    }
}

@MainActor
final class FlowTabUITestInitialSearchActivationObservationOwner {
    private struct ActiveObservation {
        let generation: UInt64
        var committedIndexGeneration: UInt64
        var expectedItemIDs: [String]?
        var watchdogInterval: TimeInterval?
        var watchdogToken:
            (any FlowTabUITestInitialPresentationCancellable)?
        var lastEvidence:
            FlowTabUITestInitialSearchActivationEvidence?
        var onResolved:
            ((FlowTabUITestInitialSearchActivationEvidence) -> Void)?
        var onWatchdog:
            ((
                FlowTabUITestInitialSearchActivationWatchdogFailure
            ) -> Void)?
    }

    private let notificationCenter: NotificationCenter
    private let notificationName: Notification.Name
    private let notificationObject: AnyObject?
    private let scheduler:
        any FlowTabUITestInitialPresentationScheduling
    private let readback:
        @MainActor () ->
            FlowTabUITestInitialSearchActivationSnapshot
    private let activateSearch: @MainActor () -> Void

    private var active: ActiveObservation?
    private var notificationToken: NSObjectProtocol?

    private(set) var observationGeneration: UInt64 = 0
    private(set) var lastEvidence:
        FlowTabUITestInitialSearchActivationEvidence?
    private(set) var lastResolution:
        FlowTabUITestInitialSearchActivationEvidence?
    private(set) var lastFailure:
        FlowTabUITestInitialSearchActivationWatchdogFailure?

    init(
        notificationCenter: NotificationCenter = .default,
        notificationName: Notification.Name =
            .runtimeCommittedSearchIndexDidUpdate,
        notificationObject: AnyObject?,
        scheduler:
            (any FlowTabUITestInitialPresentationScheduling)? = nil,
        readback:
            @escaping @MainActor () ->
                FlowTabUITestInitialSearchActivationSnapshot,
        activateSearch: @escaping @MainActor () -> Void
    ) {
        self.notificationCenter = notificationCenter
        self.notificationName = notificationName
        self.notificationObject = notificationObject
        self.scheduler = scheduler
            ?? FlowTabUITestInitialPresentationScheduler()
        self.readback = readback
        self.activateSearch = activateSearch
    }

    var isObserving: Bool {
        active != nil
    }

    var hasPendingWatchdog: Bool {
        active?.watchdogToken != nil
    }

    @discardableResult
    func start(
        triggerReadiness:
            @escaping @MainActor () -> Void = {}
    ) -> UInt64 {
        cancel(invalidate: false)
        observationGeneration &+= 1
        let generation = observationGeneration
        lastEvidence = nil
        lastResolution = nil
        lastFailure = nil
        active = ActiveObservation(
            generation: generation,
            committedIndexGeneration: 0,
            expectedItemIDs: nil,
            watchdogInterval: nil,
            watchdogToken: nil,
            lastEvidence: nil,
            onResolved: nil,
            onWatchdog: nil
        )
        installObserver(generation: generation)
        _ = evaluate(
            source: .initialReadback,
            generation: generation
        )
        guard active?.generation == generation else {
            return generation
        }
        triggerReadiness()
        return generation
    }

    func awaitActivation(
        expectedItemIDs: [String],
        watchdogInterval: TimeInterval,
        onResolved:
            @escaping (
                FlowTabUITestInitialSearchActivationEvidence
            ) -> Void,
        onWatchdog:
            @escaping (
                FlowTabUITestInitialSearchActivationWatchdogFailure
            ) -> Void
    ) {
        precondition(
            !expectedItemIDs.isEmpty
                && watchdogInterval > 0
                && watchdogInterval.isFinite
        )
        guard var current = active else { return }
        current.expectedItemIDs = expectedItemIDs
        current.watchdogInterval = watchdogInterval
        current.onResolved = onResolved
        current.onWatchdog = onWatchdog
        active = current

        if evaluate(
            source: .presentationReadback,
            generation: current.generation
        ) {
            return
        }
        activateSearch()
        if evaluate(
            source: .activationReadback,
            generation: current.generation
        ) {
            return
        }
        installWatchdog(
            interval: watchdogInterval,
            generation: current.generation
        )
    }

    @discardableResult
    func observeCommittedSearchIndexUpdate(
        generation: UInt64
    ) -> Bool {
        guard var current = active,
              current.generation == generation
        else {
            return false
        }
        current.committedIndexGeneration &+= 1
        active = current
        if evaluate(
            source: .committedSearchIndexDidUpdate,
            generation: generation
        ) {
            return true
        }
        guard active?.expectedItemIDs != nil else {
            return false
        }
        activateSearch()
        return evaluate(
            source: .committedSearchIndexDidUpdate,
            generation: generation
        )
    }

    func cancel() {
        cancel(invalidate: true)
    }

    deinit {
        let watchdogToken = active?.watchdogToken
        if let notificationToken {
            notificationCenter.removeObserver(
                notificationToken
            )
        }
        Task { @MainActor [watchdogToken] in
            watchdogToken?.cancel()
        }
    }

    private func installObserver(generation: UInt64) {
        notificationToken = notificationCenter.addObserver(
            forName: notificationName,
            object: notificationObject,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                _ = self?.observeCommittedSearchIndexUpdate(
                    generation: generation
                )
            }
        }
    }

    private func installWatchdog(
        interval: TimeInterval,
        generation: UInt64
    ) {
        let token = scheduler.schedule(after: interval) {
            [weak self] in
            self?.expireWatchdog(generation: generation)
        }
        guard var current = active,
              current.generation == generation
        else {
            token.cancel()
            return
        }
        current.watchdogToken = token
        active = current
    }

    @discardableResult
    private func evaluate(
        source:
            FlowTabUITestInitialSearchActivationEvidenceSource,
        generation: UInt64
    ) -> Bool {
        guard var current = active,
              current.generation == generation
        else {
            return false
        }
        let evidence =
            FlowTabUITestInitialSearchActivationEvidence(
                observationGeneration: generation,
                committedIndexGeneration:
                    current.committedIndexGeneration,
                source: source,
                expectedItemIDs: current.expectedItemIDs,
                snapshot: readback()
            )
        current.lastEvidence = evidence
        active = current
        lastEvidence = evidence
        guard evidence.isSatisfied else { return false }
        guard let completed = takeActive() else {
            return false
        }
        lastResolution = evidence
        completed.onResolved?(evidence)
        return true
    }

    private func expireWatchdog(generation: UInt64) {
        guard let current = active,
              current.generation == generation
        else {
            return
        }
        let lastEventEvidence = current.lastEvidence
        if evaluate(
            source: .watchdogReadback,
            generation: generation
        ) {
            return
        }
        guard let completed = takeActive(),
              let finalEvidence = completed.lastEvidence,
              let watchdogInterval =
                completed.watchdogInterval
        else {
            return
        }
        let failure =
            FlowTabUITestInitialSearchActivationWatchdogFailure(
                watchdogInterval: watchdogInterval,
                lastEvidence:
                    lastEventEvidence
                    ?? finalEvidence,
                finalEvidence: finalEvidence
            )
        lastFailure = failure
        completed.onWatchdog?(failure)
    }

    private func cancel(invalidate: Bool) {
        let hadActive = active != nil
        _ = takeActive()
        if invalidate && hadActive {
            observationGeneration &+= 1
        }
    }

    private func takeActive() -> ActiveObservation? {
        guard let active else { return nil }
        self.active = nil
        active.watchdogToken?.cancel()
        if let notificationToken {
            notificationCenter.removeObserver(
                notificationToken
            )
            self.notificationToken = nil
        }
        return active
    }
}
#endif
