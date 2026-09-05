#if FLOWTAB_TESTING
import Foundation

@MainActor
final class ControlTabPressureEventObservation {
    private static let watchdogNanoseconds: UInt64 =
        4_000_000_000

    private let token: ControlTabPressureMeasurementToken
    private let clock: any ControlTabProcessCPUClock
    private let spanRecorder: ControlTabPressureSpanRecorder
    private weak var panelController: SwitcherPanelController?
    private let strategy: ControlTabPressureObservationStrategy
    private let activationRequestReceipt:
        () -> ControlTabActivationRequestReceipt
    private let activationVerificationReceipt:
        () -> ControlTabActivationVerificationReceipt
    private let completeProjectionUpdateGeneration: () -> UInt64
    private let onFinish: (ControlTabPressureEvidence) -> Void
    private let presentationSessionGenerationBefore: Int
    private var commandReturnedAtNanoseconds: UInt64?
    private var firstVisibleFrameObserverID: UUID?
    private var renderMilestoneObserverID: UUID?
    private var watchdogTask: Task<Void, Never>?
    private var stateReadbackTask: Task<Void, Never>?
    private var componentDrainToken:
        ControlTabPressureSpanRecorder.ComponentDrainToken?
    private var latePresentationObserved = false
    private var renderSpanToken: SwitcherInteractionSpanToken?
    private var readbackSpanToken: SwitcherInteractionSpanToken?
    private var expectedRenderGeneration: UInt64?
    private var selectionRenderExpectation:
        ControlTabPressureSelectionRenderExpectation?
    private var firstRenderObserved = false
    private var matchingRenderObserved = false
    private var cachedFirstFrameCPU:
        ControlTabProcessCPUSnapshot?
    private var freshVisiblePreviewsCompleteCPU:
        ControlTabProcessCPUSnapshot?
    private var stateReadbackSatisfied = false
    private var didFinish = false

    init(
        token: ControlTabPressureMeasurementToken,
        clock: any ControlTabProcessCPUClock,
        spanRecorder: ControlTabPressureSpanRecorder,
        panelController: SwitcherPanelController,
        strategy: ControlTabPressureObservationStrategy,
        activationRequestReceipt:
            @escaping () -> ControlTabActivationRequestReceipt,
        activationVerificationReceipt:
            @escaping () -> ControlTabActivationVerificationReceipt,
        completeProjectionUpdateGeneration: @escaping () -> UInt64,
        onFinish: @escaping (ControlTabPressureEvidence) -> Void
    ) {
        self.token = token
        self.clock = clock
        self.spanRecorder = spanRecorder
        self.panelController = panelController
        self.strategy = strategy
        self.activationRequestReceipt = activationRequestReceipt
        self.activationVerificationReceipt =
            activationVerificationReceipt
        self.completeProjectionUpdateGeneration =
            completeProjectionUpdateGeneration
        self.onFinish = onFinish
        presentationSessionGenerationBefore =
            panelController.presentationSessionGeneration
        if token.phase == .forward || token.phase == .reverse {
            selectionRenderExpectation =
                ControlTabPressureSelectionRenderExpectation(
                    selectedWindowIDBefore:
                        token.selectedWindowIDBefore,
                    renderGenerationBefore:
                        token.windowContentRenderGenerationBefore
                )
        }
    }

    func start() {
        beginRenderObservationIfNeeded()
        guard token.phase == .open
                || strategy == .cancelledPresentationReadback,
              let panelController
        else {
            return
        }
        firstVisibleFrameObserverID =
            panelController
                .addFocusedWindowFirstVisibleFrameObserver {
                    [weak self] diagnostic in
                    guard let self else { return }
                    if cachedFirstFrameCPU == nil {
                        cachedFirstFrameCPU = clock.snapshot()
                    }
                    let observedPresentationGeneration =
                        Self.observedPresentationGeneration(
                            diagnosticGeneration:
                                diagnostic
                                    .presentationSessionGeneration,
                            currentGeneration:
                                panelController
                                    .presentationSessionGeneration
                        )
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if self.strategy
                            == .cancelledPresentationReadback
                        {
                            self.latePresentationObserved =
                                self.latePresentationObserved
                                ||
                                Self.cancelledPresentationIsLate(
                                    panelWasPresented:
                                        self.token.panelWasPresented,
                                    presentationGenerationBefore:
                                        self.presentationSessionGenerationBefore,
                                    observedPresentationGeneration:
                                        observedPresentationGeneration
                                )
                        } else {
                            self.startStateReadback()
                        }
                    }
                }
    }

    nonisolated static func observedPresentationGeneration(
        diagnosticGeneration: Int?,
        currentGeneration: Int
    ) -> Int {
        diagnosticGeneration ?? currentGeneration
    }

    nonisolated static func cancelledPresentationIsLate(
        panelWasPresented: Bool,
        presentationGenerationBefore: Int,
        observedPresentationGeneration: Int
    ) -> Bool {
        let permittedGeneration: Int
        if panelWasPresented {
            permittedGeneration = presentationGenerationBefore
        } else {
            let incremented = presentationGenerationBefore
                .addingReportingOverflow(1)
            permittedGeneration = incremented.overflow
                ? Int.max : incremented.partialValue
        }
        return observedPresentationGeneration > permittedGeneration
    }

    nonisolated static func openRenderMilestoneDisposition(
        eventGeneration: UInt64,
        renderGenerationBefore: UInt64,
        expectedRenderGeneration: UInt64?,
        currentRenderGeneration: UInt64,
        previewPreparationSucceeded: Bool,
        firstRenderObserved: Bool
    ) -> ControlTabPressureOpenRenderMilestoneDisposition {
        guard eventGeneration > renderGenerationBefore else {
            return .ignored
        }
        let isFirstRender = !firstRenderObserved
        let isFreshRender = previewPreparationSucceeded
            && eventGeneration == currentRenderGeneration
            && expectedRenderGeneration.map {
                eventGeneration >= $0
            } != false
        switch (isFirstRender, isFreshRender) {
        case (true, true):
            return .firstFrameAndFreshPreviews
        case (true, false):
            return .firstFrame
        case (false, true):
            return .freshPreviews
        case (false, false):
            return .ignored
        }
    }

    nonisolated static func processCPUSnapshot(
        for event: ControlTabPressureRenderEvent,
        fallback: @autoclosure () -> ControlTabProcessCPUSnapshot
    ) -> ControlTabProcessCPUSnapshot {
        guard let processCPUSnapshot = event.processCPUSnapshot else {
            return fallback()
        }
        return ControlTabProcessCPUSnapshot(
            runtimeSnapshot: processCPUSnapshot
        )
    }

    nonisolated static func stateReadbackCanStart(
        phase: ControlTabPressurePhase,
        matchingRenderObserved: Bool
    ) -> Bool {
        switch phase {
        case .open, .forward, .reverse:
            return matchingRenderObserved
        case .commit, .cancel:
            return true
        case .cooldown:
            return false
        }
    }

    nonisolated static func stateReadbackCanFinish(
        commandReturnedAtNanoseconds: UInt64?
    ) -> Bool {
        commandReturnedAtNanoseconds != nil
    }

    func commandDidReturn() {
        guard !didFinish else { return }
        commandReturnedAtNanoseconds =
            DispatchTime.now().uptimeNanoseconds
        if let model = panelController?.modelForTesting {
            if token.phase == .forward || token.phase == .reverse {
                selectionRenderExpectation?.observeCommandReturn(
                    selectedWindowID:
                        model.session?.selectedWindow?.id,
                    renderGeneration:
                        model.windowContentRenderGeneration
                )
            } else {
                expectedRenderGeneration =
                    model.windowContentRenderGeneration
            }
        }
        if stateReadbackSatisfied,
           externalInputReachedExpectedState()
        {
            scheduleCompletionAfterReadback()
            return
        }
        stateReadbackSatisfied = false
        if strategy != .commandReturn {
            watchdogTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await Task.sleep(nanoseconds: self.watchdogInterval)
                } catch {
                    return
                }
                self.finish(watchdogExpired: true)
            }
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch self.strategy {
            case .firstVisibleFrame:
                self.startStateReadback()
            case .externalStateReadback,
                 .cancelledPresentationReadback:
                self.startStateReadback()
            case .commandReturn:
                self.finish(watchdogExpired: false)
            }
        }
    }

    func finishCooldown() {
        guard token.phase == .cooldown else { return }
        commandReturnedAtNanoseconds =
            DispatchTime.now().uptimeNanoseconds
        finish(watchdogExpired: false)
    }

    func cancel() {
        guard !didFinish else { return }
        didFinish = true
        cleanup()
    }

    private func startStateReadback() {
        guard !didFinish, !stateReadbackSatisfied else { return }
        guard Self.stateReadbackCanStart(
            phase: token.phase,
            matchingRenderObserved: matchingRenderObserved
        ) else {
            return
        }
        beginReadbackSpanIfNeeded()
        stateReadbackTask?.cancel()
        stateReadbackTask = nil
        if externalInputReachedExpectedState() {
            completeSatisfiedStateReadback()
            return
        }
        stateReadbackTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, !self.didFinish else { return }
                if self.externalInputReachedExpectedState() {
                    self.completeSatisfiedStateReadback()
                    return
                }
                do {
                    try await Task.sleep(nanoseconds: 5_000_000)
                } catch {
                    return
                }
            }
        }
    }

    private func completeSatisfiedStateReadback() {
        completeReadbackSpan()
        stateReadbackSatisfied = true
        guard Self.stateReadbackCanFinish(
            commandReturnedAtNanoseconds:
                commandReturnedAtNanoseconds
        ) else {
            return
        }
        scheduleCompletionAfterReadback()
    }

    private func scheduleCompletionAfterReadback() {
        guard componentDrainToken == nil else { return }
        componentDrainToken = spanRecorder.afterActiveComponentsDrain {
            [weak self] in
            guard let self else { return }
            self.componentDrainToken = nil
            guard self.stateReadbackSatisfied,
                  Self.stateReadbackCanFinish(
                    commandReturnedAtNanoseconds:
                        self.commandReturnedAtNanoseconds
                  )
            else {
                return
            }
            self.finish(watchdogExpired: false)
        }
    }

    private func externalInputReachedExpectedState() -> Bool {
        guard let panelController else { return false }
        let selectedWindowID = panelController.modelForTesting
            .session?.selectedWindow?.id
        switch token.phase {
        case .open:
            return panelController.isPanelPresented
                && panelController.isPanelVisibleToUser
                && panelController.lastFocusedWindowSessionDiagnostic?
                    .milestones[
                        FocusedWindowSessionDiagnostic.MilestoneKey
                            .firstVisibleFrame
                    ] != nil
                && matchingRenderObserved
        case .forward, .reverse:
            return panelController.isPanelPresented
                && selectedWindowID != nil
                && selectionRenderExpectation?
                    .matchesReadback(
                        selectedWindowID: selectedWindowID
                    ) == true
                && matchingRenderObserved
        case .commit, .cancel:
            let reachedClosedState =
                !panelController.isPanelPresented
                && !panelController.isPanelVisibleToUser
                && panelController.modelForTesting.session == nil
                && !panelController
                    .suppressHotkeyReplayUntilReleaseForTesting
                && reusableShellPreparationCompleted(
                    panelController: panelController
                )
            guard strategy == .cancelledPresentationReadback
            else {
                if token.phase == .commit {
                    let verification = activationVerificationReceipt()
                    return reachedClosedState
                        && verification.generation
                            > token
                                .activationVerificationGenerationBefore
                        && verification.satisfied
                }
                return reachedClosedState
            }
            return reachedClosedState
                && completeProjectionUpdateGeneration()
                    > token
                        .completeProjectionUpdateGenerationBefore
                && panelController
                    .pendingFocusedWindowSessionPresentation == nil
        case .cooldown:
            return false
        }
    }

    private func reusableShellPreparationCompleted(
        panelController: SwitcherPanelController
    ) -> Bool {
        let completed = panelController
            .completedReusableShellPreparationGeneration
        return token.reusableShellPreparationCompleted(
            at: completed
        )
    }

    private func finish(watchdogExpired: Bool) {
        guard !didFinish, let panelController else { return }
        didFinish = true
        if watchdogExpired {
            let state = panelController.controlTabPressureDiagnostics
            RuntimeLog.error(
                .uiTest,
                "Control+Tab pressure observation expired phase=\(token.phase.rawValue) "
                    + "sequence=\(token.sequence) "
                    + "currentRender=\(panelController.modelForTesting.windowContentRenderGeneration) "
                    + "lastDraw=\(state.lastObservedRenderGeneration.map(String.init) ?? "none") "
                    + "pendingDraw=\(state.pendingRenderEvent.map { String($0.renderGeneration) } ?? "none") "
                    + "firstRender=\(firstRenderObserved) matchingRender=\(matchingRenderObserved) "
                    + "\(panelController.panelVisibilitySnapshot().logFields)"
            )
        }
        let completedAtNanoseconds =
            DispatchTime.now().uptimeNanoseconds
        let completedCPU = clock.snapshot()
        let spanEvidence = spanRecorder.finishPhase(
            completedAtNanoseconds: completedAtNanoseconds,
            completedCPU: completedCPU
        )
        let evidence = ControlTabPressureEvidenceAssembler.make(
            context: ControlTabPressureEvidenceContext(
                token: token,
                completedAtNanoseconds: completedAtNanoseconds,
                completedCPU: completedCPU,
                panelController: panelController,
                strategy: strategy,
                commandReturnedAtNanoseconds:
                    commandReturnedAtNanoseconds,
                activationRequest: activationRequestReceipt(),
                activationVerification:
                    activationVerificationReceipt(),
                completeProjectionUpdateGeneration:
                    completeProjectionUpdateGeneration(),
                latePresentationObserved:
                    latePresentationObserved,
                cachedFirstFrameCPU: cachedFirstFrameCPU,
                freshVisiblePreviewsCompleteCPU:
                    freshVisiblePreviewsCompleteCPU,
                spanEvidence: spanEvidence,
                watchdogExpired: watchdogExpired
            )
        )
        cleanup()
        onFinish(evidence)
    }

    private func cleanup() {
        watchdogTask?.cancel()
        watchdogTask = nil
        stateReadbackTask?.cancel()
        stateReadbackTask = nil
        spanRecorder.cancelComponentDrainAction(componentDrainToken)
        componentDrainToken = nil
        if let firstVisibleFrameObserverID {
            panelController?
                .removeFocusedWindowFirstVisibleFrameObserver(
                    firstVisibleFrameObserverID
                )
        }
        firstVisibleFrameObserverID = nil
        if let renderMilestoneObserverID {
            panelController?.removePressureRenderMilestoneObserver(
                renderMilestoneObserverID
            )
        }
        renderMilestoneObserverID = nil
    }

    private var watchdogInterval: UInt64 {
        token.phase == .commit ? 8_000_000_000
            : Self.watchdogNanoseconds
    }

    private func beginRenderObservationIfNeeded() {
        let component: SwitcherInteractionComponent
        switch token.phase {
        case .open:
            component = .swiftUILayoutFirstDraw
        case .forward, .reverse:
            component = .swiftUIDiffLayoutDraw
        case .commit, .cancel, .cooldown:
            return
        }
        renderSpanToken = spanRecorder.beginComponent(
            component,
            parent: nil,
            workUnits: max(1, token.selectedWindowCountBefore)
        )
        renderMilestoneObserverID = panelController?
            .addPressureRenderMilestoneObserver { [weak self] event in
                guard let self,
                      event.milestone == .windowContent
                else {
                    return
                }
                if self.token.phase == .open {
                    guard let model = self.panelController?
                        .modelForTesting
                    else {
                        return
                    }
                    let disposition = Self
                        .openRenderMilestoneDisposition(
                            eventGeneration: event.renderGeneration,
                            renderGenerationBefore:
                                self.token
                                    .windowContentRenderGenerationBefore,
                            expectedRenderGeneration:
                                self.expectedRenderGeneration,
                            currentRenderGeneration:
                                model.windowContentRenderGeneration,
                            previewPreparationSucceeded:
                                model
                                    .windowOnlyPreviewPreparationSucceeded,
                            firstRenderObserved:
                                self.firstRenderObserved
                        )
                    if disposition.includesFirstFrame {
                        self.firstRenderObserved = true
                        if self.cachedFirstFrameCPU == nil {
                            self.cachedFirstFrameCPU = Self
                                .processCPUSnapshot(
                                    for: event,
                                    fallback: self.clock.snapshot()
                                )
                        }
                        self.spanRecorder.endComponent(
                            self.renderSpanToken,
                            workUnits: max(
                                1,
                                model.previewWindowCount
                            )
                        )
                        self.renderSpanToken = nil
                    }
                    guard disposition.includesFreshPreviews,
                          !self.matchingRenderObserved
                    else {
                        return
                    }
                    self.matchingRenderObserved = true
                    self.freshVisiblePreviewsCompleteCPU = Self
                        .processCPUSnapshot(
                            for: event,
                            fallback: self.clock.snapshot()
                        )
                    self.startStateReadback()
                    return
                }
                guard event.renderGeneration
                        > self.token
                            .windowContentRenderGenerationBefore,
                      let model = self.panelController?
                        .modelForTesting,
                      model.windowOnlyPreviewPreparationSucceeded,
                      event.renderGeneration
                        == model.windowContentRenderGeneration
                else {
                    return
                }
                if let expected = self.expectedRenderGeneration,
                   event.renderGeneration < expected
                {
                    return
                }
                if self.token.phase == .forward
                    || self.token.phase == .reverse
                {
                    let selected = self.panelController?
                        .modelForTesting.session?.selectedWindow?.id
                    guard var expectation =
                            self.selectionRenderExpectation,
                          let currentRenderGeneration =
                            self.panelController?.modelForTesting
                                .windowContentRenderGeneration,
                          expectation.acceptDraw(
                              selectedWindowID: selected,
                              renderGeneration:
                                event.renderGeneration,
                              currentRenderGeneration:
                                currentRenderGeneration
                          )
                    else {
                        return
                    }
                    self.selectionRenderExpectation = expectation
                }
                guard !self.matchingRenderObserved else { return }
                self.matchingRenderObserved = true
                self.spanRecorder.endComponent(
                    self.renderSpanToken,
                    workUnits: max(
                        1,
                        self.panelController?.modelForTesting
                            .previewWindowCount ?? 1
                    )
                )
                self.renderSpanToken = nil
                self.startStateReadback()
            }
    }

    private func beginReadbackSpanIfNeeded() {
        guard readbackSpanToken == nil else { return }
        let component: SwitcherInteractionComponent
        switch token.phase {
        case .open:
            component = .visibilityReadback
        case .forward, .reverse:
            component = .selectionReadback
        case .commit:
            component = .focusReadback
        case .cancel:
            component = .closedStateReadback
        case .cooldown:
            return
        }
        readbackSpanToken = spanRecorder.beginComponent(
            component,
            parent: nil,
            workUnits: 1
        )
    }

    private func completeReadbackSpan() {
        spanRecorder.endComponent(readbackSpanToken)
        readbackSpanToken = nil
    }

    deinit {
        watchdogTask?.cancel()
        stateReadbackTask?.cancel()
    }
}

enum ControlTabPressureOpenRenderMilestoneDisposition: Equatable {
    case ignored
    case firstFrame
    case freshPreviews
    case firstFrameAndFreshPreviews

    var includesFirstFrame: Bool {
        self == .firstFrame || self == .firstFrameAndFreshPreviews
    }

    var includesFreshPreviews: Bool {
        self == .freshPreviews || self == .firstFrameAndFreshPreviews
    }
}
#endif
