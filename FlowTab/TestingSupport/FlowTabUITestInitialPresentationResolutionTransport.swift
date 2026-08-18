#if FLOWTAB_TESTING
import Foundation

struct FlowTabUITestInitialPresentationResolutionRoute:
    Equatable
{
    let notificationName: Notification.Name
    let readbackURL: URL
}

enum FlowTabUITestInitialPresentationInputReadinessPolicy {
    static let readbackCadence: TimeInterval = 0.1
    static let watchdog: TimeInterval = 3
}

enum FlowTabUITestInitialPresentationInputReadinessSource:
    String,
    Equatable
{
    case initialReadback
    case readinessRequestReadback
    case projectionUpdateReadback
    case scheduledReadback
    case watchdogReadback
}

struct FlowTabUITestInitialPresentationInputReadinessSnapshot:
    Equatable
{
    let projection:
        FlowTabUITestInitialPresentationSnapshot
    let presentationGeneration: Int
    let panelIsPresented: Bool
    let panelIsVisibleToUser: Bool
    let panelIsKey: Bool
    let applicationIsActive: Bool
    let sessionItemIDs: [String]
    let selectedAppID: String?
    let sessionMode: String?
    let panelPresentationDiagnosticProbePending: Bool
    let initialVisibilityPending: Bool
    let panelVisibilityRecoveryPending: Bool
    let activeSpaceTransitionPending: Bool
    let applicationActivationSuppressed: Bool
    let terminateInterruptionProtectionPending: Bool

    @MainActor
    init(
        panelController: SwitcherPanelController,
        mode: FlowTabUITestInitialPresentationMode
    ) {
        let model = panelController.modelForTesting
        projection = FlowTabUITestBootstrapper
            .initialPresentationSnapshot(
                panelController: panelController,
                mode: mode
            )
        presentationGeneration =
            panelController.presentationSessionGeneration
        panelIsPresented = panelController.isPanelPresented
        panelIsVisibleToUser =
            panelController.isPanelVisibleToUser
        panelIsKey = panelController.panel.isKeyWindow
        applicationIsActive =
            panelController.isAppCurrentlyActive
        sessionItemIDs = FlowTabUITestBootstrapper
            .initialPresentationSessionItemIDs(
                panelController: panelController,
                mode: mode
            )
        selectedAppID = model.session?.selectedApp.id
        sessionMode = model.session?.mode.debugName
        panelPresentationDiagnosticProbePending =
            panelController
                .hasPendingPanelPresentationDiagnosticProbe
        initialVisibilityPending =
            panelController
                .hasPendingInitialPresentationVisibilityObservation
        panelVisibilityRecoveryPending =
            panelController
                .hasPendingPanelVisibilityRecoveryObservation
        activeSpaceTransitionPending =
            panelController
                .hasPendingActiveSpaceTransitionObservation
        applicationActivationSuppressed =
            panelController
                .isApplicationActivationSuppressedForActiveSpaceTransition
        terminateInterruptionProtectionPending =
            panelController
                .hasPendingTerminateInterruptionProtection
    }

    init(
        projection:
            FlowTabUITestInitialPresentationSnapshot,
        presentationGeneration: Int,
        panelIsPresented: Bool,
        panelIsVisibleToUser: Bool,
        panelIsKey: Bool,
        applicationIsActive: Bool,
        sessionItemIDs: [String],
        selectedAppID: String?,
        sessionMode: String?,
        panelPresentationDiagnosticProbePending: Bool,
        initialVisibilityPending: Bool,
        panelVisibilityRecoveryPending: Bool,
        activeSpaceTransitionPending: Bool,
        applicationActivationSuppressed: Bool,
        terminateInterruptionProtectionPending: Bool
    ) {
        self.projection = projection
        self.presentationGeneration = presentationGeneration
        self.panelIsPresented = panelIsPresented
        self.panelIsVisibleToUser = panelIsVisibleToUser
        self.panelIsKey = panelIsKey
        self.applicationIsActive = applicationIsActive
        self.sessionItemIDs = sessionItemIDs
        self.selectedAppID = selectedAppID
        self.sessionMode = sessionMode
        self.panelPresentationDiagnosticProbePending =
            panelPresentationDiagnosticProbePending
        self.initialVisibilityPending = initialVisibilityPending
        self.panelVisibilityRecoveryPending =
            panelVisibilityRecoveryPending
        self.activeSpaceTransitionPending =
            activeSpaceTransitionPending
        self.applicationActivationSuppressed =
            applicationActivationSuppressed
        self.terminateInterruptionProtectionPending =
            terminateInterruptionProtectionPending
    }

    func unmetConditions(
        baseline:
            FlowTabUITestInitialPresentationSnapshot,
        expectedPresentationGeneration: Int,
        expectedSessionItemIDs: [String],
        expectedSelectedAppID: String
    ) -> [String] {
        var conditions: [String] = []
        if !projection.hasProgressed(from: baseline) {
            conditions.append("postPresentationProjectionGeneration")
        }
        // Initial presentation already proved a complete candidate. This barrier
        // needs a later exact target while unrelated runtime repairs may continue.
        if projection.mode != baseline.mode {
            conditions.append("projectionMode")
        }
        if projection.processIdentifier
            != baseline.processIdentifier
        {
            conditions.append("projectionProcess")
        }
        if projection.itemIDs != expectedSessionItemIDs {
            conditions.append("projectionItems")
        }
        if presentationGeneration
            != expectedPresentationGeneration
        {
            conditions.append("presentationGeneration")
        }
        if !panelIsPresented {
            conditions.append("panelPresented")
        }
        if !panelIsVisibleToUser {
            conditions.append("panelVisibleToUser")
        }
        if sessionItemIDs != expectedSessionItemIDs {
            conditions.append("sessionItems")
        }
        if selectedAppID != expectedSelectedAppID {
            conditions.append("selectedApp")
        }
        if panelPresentationDiagnosticProbePending {
            conditions.append("panelPresentationDiagnosticProbeCompletion")
        }
        if initialVisibilityPending {
            conditions.append("initialVisibilityCompletion")
        }
        if panelVisibilityRecoveryPending {
            conditions.append("panelVisibilityRecoveryCompletion")
        }
        if activeSpaceTransitionPending {
            conditions.append("activeSpaceTransitionCompletion")
        }
        if applicationActivationSuppressed {
            conditions.append("applicationActivationSuppressionEnd")
        }
        if terminateInterruptionProtectionPending {
            conditions.append("terminateInterruptionProtectionCompletion")
        }
        return conditions
    }

    var logFields: String {
        "projection{\(projection.logFields)} "
            + "presentationGeneration=\(presentationGeneration) "
            + "panelPresented=\(panelIsPresented ? 1 : 0) "
            + "panelVisibleToUser=\(panelIsVisibleToUser ? 1 : 0) "
            + "panelKey=\(panelIsKey ? 1 : 0) "
            + "appActive=\(applicationIsActive ? 1 : 0) "
            + "sessionItems=[\(sessionItemIDs.joined(separator: ","))] "
            + "selectedAppID=\(selectedAppID ?? "nil") "
            + "sessionMode=\(sessionMode ?? "nil") "
            + "panelDiagnosticPending=\(panelPresentationDiagnosticProbePending ? 1 : 0) "
            + "initialVisibilityPending=\(initialVisibilityPending ? 1 : 0) "
            + "panelRecoveryPending=\(panelVisibilityRecoveryPending ? 1 : 0) "
            + "activeSpacePending=\(activeSpaceTransitionPending ? 1 : 0) "
            + "activationSuppressed=\(applicationActivationSuppressed ? 1 : 0) "
            + "terminateProtectionPending=\(terminateInterruptionProtectionPending ? 1 : 0)"
    }
}

struct FlowTabUITestInitialPresentationInputReadinessEvidence:
    Equatable
{
    let observationGeneration: UInt64
    let source:
        FlowTabUITestInitialPresentationInputReadinessSource
    let baseline:
        FlowTabUITestInitialPresentationSnapshot
    let expectedPresentationGeneration: Int
    let expectedSessionItemIDs: [String]
    let expectedSelectedAppID: String
    let snapshot:
        FlowTabUITestInitialPresentationInputReadinessSnapshot
    let isSatisfied: Bool

    var logFields: String {
        let unmet = snapshot.unmetConditions(
            baseline: baseline,
            expectedPresentationGeneration:
                expectedPresentationGeneration,
            expectedSessionItemIDs: expectedSessionItemIDs,
            expectedSelectedAppID: expectedSelectedAppID
        )
        return "generation=\(observationGeneration) "
            + "source=\(source.rawValue) "
            + "satisfied=\(isSatisfied ? 1 : 0) "
            + "unmet=[\(unmet.joined(separator: ","))] "
            + "baseline{\(baseline.logFields)} "
            + "final{\(snapshot.logFields)}"
    }
}

struct FlowTabUITestInitialPresentationInputReadinessWatchdogFailure:
    Equatable
{
    let watchdogInterval: TimeInterval
    let lastEvidence:
        FlowTabUITestInitialPresentationInputReadinessEvidence
    let finalEvidence:
        FlowTabUITestInitialPresentationInputReadinessEvidence

    var logFields: String {
        "watchdogMs=\(Int((watchdogInterval * 1_000).rounded())) "
            + "condition=inputReady "
            + "last{\(lastEvidence.logFields)} "
            + "final{\(finalEvidence.logFields)}"
    }
}

@MainActor
final class
    FlowTabUITestInitialPresentationInputReadinessObservationOwner
{
    private struct ActiveObservation {
        let generation: UInt64
        let watchdogInterval: TimeInterval
        let baseline:
            FlowTabUITestInitialPresentationSnapshot
        let expectedPresentationGeneration: Int
        let expectedSessionItemIDs: [String]
        let expectedSelectedAppID: String
        let triggerReadiness: @MainActor () -> Void
        let onResolved:
            @MainActor (
                FlowTabUITestInitialPresentationInputReadinessEvidence
            ) -> Void
        let onWatchdog:
            @MainActor (
                FlowTabUITestInitialPresentationInputReadinessWatchdogFailure
            ) -> Void
        var lastEvidence:
            FlowTabUITestInitialPresentationInputReadinessEvidence?
        var retryToken:
            (any FlowTabUITestInitialPresentationCancellable)?
        var watchdogToken:
            (any FlowTabUITestInitialPresentationCancellable)?
    }

    private let notificationNames: [Notification.Name]
    private let notificationObject: AnyObject?
    private let notificationCenter: NotificationCenter
    private let scheduler:
        any FlowTabUITestInitialPresentationScheduling
    private let readback:
        @MainActor () ->
            FlowTabUITestInitialPresentationInputReadinessSnapshot

    private var active: ActiveObservation?
    private var notificationTokens: [NSObjectProtocol] = []

    private(set) var observationGeneration: UInt64 = 0
    private(set) var lastEvidence:
        FlowTabUITestInitialPresentationInputReadinessEvidence?
    private(set) var lastResolution:
        FlowTabUITestInitialPresentationInputReadinessEvidence?
    private(set) var lastFailure:
        FlowTabUITestInitialPresentationInputReadinessWatchdogFailure?

    init(
        notificationNames: [Notification.Name],
        notificationObject: AnyObject?,
        notificationCenter: NotificationCenter = .default,
        scheduler:
            (any FlowTabUITestInitialPresentationScheduling)? = nil,
        readback:
            @escaping @MainActor () ->
                FlowTabUITestInitialPresentationInputReadinessSnapshot
    ) {
        self.notificationNames = notificationNames
        self.notificationObject = notificationObject
        self.notificationCenter = notificationCenter
        self.scheduler = scheduler
            ?? FlowTabUITestInitialPresentationScheduler()
        self.readback = readback
    }

    var isObserving: Bool {
        active != nil
    }

    var hasPendingRetry: Bool {
        active?.retryToken != nil
    }

    var hasPendingWatchdog: Bool {
        active?.watchdogToken != nil
    }

    @discardableResult
    func start(
        baseline:
            FlowTabUITestInitialPresentationSnapshot,
        expectedPresentationGeneration: Int,
        expectedSessionItemIDs: [String],
        expectedSelectedAppID: String,
        watchdogInterval: TimeInterval,
        triggerReadiness: @escaping @MainActor () -> Void,
        onResolved:
            @escaping @MainActor (
                FlowTabUITestInitialPresentationInputReadinessEvidence
            ) -> Void,
        onWatchdog:
            @escaping @MainActor (
                FlowTabUITestInitialPresentationInputReadinessWatchdogFailure
            ) -> Void
    ) -> UInt64 {
        precondition(
            watchdogInterval > 0
                && watchdogInterval.isFinite
        )
        precondition(!expectedSessionItemIDs.isEmpty)
        precondition(!expectedSelectedAppID.isEmpty)
        cancel(invalidate: false)
        observationGeneration &+= 1
        let generation = observationGeneration
        lastEvidence = nil
        lastResolution = nil
        lastFailure = nil
        active = ActiveObservation(
            generation: generation,
            watchdogInterval: watchdogInterval,
            baseline: baseline,
            expectedPresentationGeneration:
                expectedPresentationGeneration,
            expectedSessionItemIDs: expectedSessionItemIDs,
            expectedSelectedAppID: expectedSelectedAppID,
            triggerReadiness: triggerReadiness,
            onResolved: onResolved,
            onWatchdog: onWatchdog,
            lastEvidence: nil,
            retryToken: nil,
            watchdogToken: nil
        )
        installObservers(generation: generation)

        if evaluate(
            source: .initialReadback,
            generation: generation
        ) {
            return generation
        }
        guard active?.generation == generation else {
            return generation
        }

        triggerReadiness()
        if evaluate(
            source: .readinessRequestReadback,
            generation: generation
        ) {
            return generation
        }
        guard active?.generation == generation else {
            return generation
        }

        scheduleRetry(generation: generation)
        scheduleWatchdog(generation: generation)
        return generation
    }

    @discardableResult
    func observe(
        source:
            FlowTabUITestInitialPresentationInputReadinessSource,
        observationGeneration: UInt64
    ) -> Bool {
        evaluate(
            source: source,
            generation: observationGeneration
        )
    }

    func cancel() {
        cancel(invalidate: true)
    }

    deinit {
        for token in notificationTokens {
            notificationCenter.removeObserver(token)
        }
    }

    private func installObservers(generation: UInt64) {
        notificationTokens = notificationNames.map {
            name in
            notificationCenter.addObserver(
                forName: name,
                object: notificationObject,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    _ = self?.observe(
                        source: .projectionUpdateReadback,
                        observationGeneration: generation
                    )
                }
            }
        }
    }

    @discardableResult
    private func evaluate(
        source:
            FlowTabUITestInitialPresentationInputReadinessSource,
        generation: UInt64
    ) -> Bool {
        guard var current = active,
              current.generation == generation
        else {
            return false
        }
        let snapshot = readback()
        let isSatisfied = snapshot.unmetConditions(
            baseline: current.baseline,
            expectedPresentationGeneration:
                current.expectedPresentationGeneration,
            expectedSessionItemIDs:
                current.expectedSessionItemIDs,
            expectedSelectedAppID:
                current.expectedSelectedAppID
        ).isEmpty
        let evidence =
            FlowTabUITestInitialPresentationInputReadinessEvidence(
                observationGeneration: generation,
                source: source,
                baseline: current.baseline,
                expectedPresentationGeneration:
                    current.expectedPresentationGeneration,
                expectedSessionItemIDs:
                    current.expectedSessionItemIDs,
                expectedSelectedAppID:
                    current.expectedSelectedAppID,
                snapshot: snapshot,
                isSatisfied: isSatisfied
            )
        current.lastEvidence = evidence
        active = current
        lastEvidence = evidence
        guard isSatisfied else {
            return false
        }
        guard let completed = takeActive() else {
            return false
        }
        lastResolution = evidence
        completed.onResolved(evidence)
        return true
    }

    private func scheduleRetry(generation: UInt64) {
        guard let current = active,
              current.generation == generation,
              current.retryToken == nil
        else {
            return
        }
        let token = scheduler.schedule(
            after:
                FlowTabUITestInitialPresentationInputReadinessPolicy
                    .readbackCadence
        ) { [weak self] in
            self?.performScheduledReadback(
                generation: generation
            )
        }
        guard var resumed = active,
              resumed.generation == generation
        else {
            token.cancel()
            return
        }
        resumed.retryToken = token
        active = resumed
    }

    private func performScheduledReadback(
        generation: UInt64
    ) {
        guard var current = active,
              current.generation == generation
        else {
            return
        }
        current.retryToken = nil
        active = current
        if evaluate(
            source: .scheduledReadback,
            generation: generation
        ) {
            return
        }
        scheduleRetry(generation: generation)
    }

    private func scheduleWatchdog(generation: UInt64) {
        guard let current = active,
              current.generation == generation
        else {
            return
        }
        let token = scheduler.schedule(
            after: current.watchdogInterval
        ) { [weak self] in
            self?.expireWatchdog(generation: generation)
        }
        guard var resumed = active,
              resumed.generation == generation
        else {
            token.cancel()
            return
        }
        resumed.watchdogToken = token
        active = resumed
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
              let finalEvidence = completed.lastEvidence
        else {
            return
        }
        let failure =
            FlowTabUITestInitialPresentationInputReadinessWatchdogFailure(
                watchdogInterval:
                    completed.watchdogInterval,
                lastEvidence:
                    lastEventEvidence ?? finalEvidence,
                finalEvidence: finalEvidence
            )
        lastFailure = failure
        completed.onWatchdog(failure)
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
        active.retryToken?.cancel()
        active.watchdogToken?.cancel()
        removeObservers()
        return active
    }

    private func removeObservers() {
        for token in notificationTokens {
            notificationCenter.removeObserver(token)
        }
        notificationTokens.removeAll()
    }
}

#endif
