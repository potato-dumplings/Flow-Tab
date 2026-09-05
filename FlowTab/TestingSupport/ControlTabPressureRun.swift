#if FLOWTAB_TESTING
import Foundation
import FlowTabCore

@MainActor
final class ControlTabPressureRun {
    private let recorderModeEnvironmentKey =
        "FLOWTAB_CONTROL_TAB_RECORDER_MODE"
    private let externalOnlyRecorderMode = "external-only"
    private var commandObserver:
        ControlTabPressureCommandObserver?
    private var evidenceDelivery:
        ControlTabPressureEvidenceDelivery?
    private var activeObservations:
        [UInt64: ControlTabPressureEventObservation] = [:]
    private var cooldownToken:
        ControlTabPressureMeasurementToken?
    private let clock =
        ControlTabSystemProcessCPUClock()
    private lazy var spanRecorder =
        ControlTabPressureSpanRecorder(clock: clock)
    private lazy var previewMeasurements = ControlTabPressurePreviewMeasurements(recorder: spanRecorder)
    private lazy var activationCoordinator =
        ControlTabPressureActivationCoordinator(
            spanRecorder: spanRecorder
        )
    private let hotkeyInputSourceID =
        HotkeyInputSourceID()
    private var hotkeyInputSequence: UInt64 = 0
    private var completeProjectionUpdateGeneration: UInt64 = 0
    private var projectionUpdateObserver: NSObjectProtocol?

    let focusedRepairCollector = RuntimeFocusedRepairDiagnosticCollector()
    private weak var installedPanel: SwitcherPanelController?
    private var modelDiagnostics: ControlTabPressureModelDiagnostics?
    private var panelDiagnostics: ControlTabPressurePanelDiagnostics?
    private var panelAssembly: ControlTabPressurePanelAssembly?
    private var restoreModel: (() -> Void)?
    private var restoreAttachments: (() -> Void)?
    private var inputMonitor: ControlTabPressureHotkeyMonitor?

    lazy var systemProjectionService = RuntimeProjectionService(dependencies: makeProjectionDependencies())

    func makeProjectionDependencies() -> RuntimeProjectionDependencies {
        var dependencies = RuntimeProjectionDependencies.system()
        dependencies.focusedWindowFacts = ControlTabPressureFocusedWindowFacts(
            base: RuntimeFocusedWindowFactCollector(runtimeFactProvider: dependencies.factProvider,
                windowEntries: dependencies.windowEntries), collector: focusedRepairCollector
        )
        return dependencies
    }

    func cancel() {
        commandObserver?.uninstall()
        commandObserver = nil
        evidenceDelivery?.cancel()
        evidenceDelivery = nil
        activeObservations.values.forEach { $0.cancel() }
        activeObservations.removeAll()
        focusedRepairCollector.setEnabled(false)
        previewMeasurements.cancel()
        panelAssembly?.cancel()
        panelAssembly = nil
        inputMonitor?.uninstall()
        if let sourceID = inputMonitor?.base.inputSourceID {
            installedPanel?.registerHotkeyInputSource(sourceID, for: .inAppWindowSwitcher)
        }
        inputMonitor = nil
        if let installedPanel {
            let model = installedPanel.modelForTesting
            model.interactionDiagnosticSink = nil
            model.controlTabPressureDiagnostics.onRender = nil
            activationCoordinator.uninstall(from: model)
        }
        restoreModel?()
        restoreModel = nil
        restoreAttachments?()
        restoreAttachments = nil
        spanRecorder.cancel()
        if let projectionUpdateObserver { NotificationCenter.default.removeObserver(projectionUpdateObserver) }
        projectionUpdateObserver = nil
        cooldownToken = nil
        modelDiagnostics = nil
        panelDiagnostics = nil
        installedPanel = nil
    }

    func configureIfNeeded(
        panelController: SwitcherPanelController,
        environment: [String: String] =
            ProcessInfo.processInfo.environment
    ) {
        cancel()
        guard let route = ControlTabPressureRoute(environment: environment) else { return }
        installedPanel = panelController
        let model = panelController.modelForTesting
        let originalModelDiagnostics = model.controlTabPressureDiagnostics
        let originalPanelDiagnostics = panelController.controlTabPressureDiagnostics
        let diagnosticState = ControlTabPressureModelDiagnostics()
        let presentationDiagnostics = ControlTabPressurePanelDiagnostics()
        modelDiagnostics = diagnosticState
        panelDiagnostics = presentationDiagnostics
        model.installControlTabPressureDiagnostics(diagnosticState)
        panelController.installControlTabPressureDiagnostics(presentationDiagnostics)
        restoreAttachments = { [weak model, weak panelController] in
            model?.installControlTabPressureDiagnostics(originalModelDiagnostics)
            panelController?.installControlTabPressureDiagnostics(originalPanelDiagnostics)
        }
        preserveModelAssembly(model)
        completeProjectionUpdateGeneration = 0
        let recordsComponents = environment[
            recorderModeEnvironmentKey
        ] != externalOnlyRecorderMode
        spanRecorder.setComponentRecordingEnabled(recordsComponents)
        if !AccessibilityPermissionChecker.isTrusted() {
            _ = AccessibilityPermissionChecker.requestPermission()
        }
        if !ScreenCapturePermissionChecker
            .hasScreenCapturePermission
        {
            _ = ScreenCapturePermissionChecker
                .requestScreenCapturePermission()
        }
        focusedRepairCollector
            .setEnabled(recordsComponents)
        let delivery = ControlTabPressureEvidenceDelivery(
            route: route
        )
        let observer = ControlTabPressureCommandObserver(
            route: route
        ) { [weak self] action, sequence in
            self?.receive(
                action,
                sequence: sequence,
                panelController: panelController,
                delivery: delivery
            )
        }
        observer.install()
        evidenceDelivery = delivery
        commandObserver = observer
        projectionUpdateObserver = NotificationCenter.default
            .addObserver(
                forName:
                    .runtimeCurrentAppWindowProjectionDidUpdate,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated { [weak self] in
                    guard let self else { return }
                    guard let evidence = notification.userInfo?[
                        RuntimeProjectionNotificationUserInfoKey
                            .currentAppWindowProjectionUpdateEvidence
                    ] as? RuntimeCurrentAppWindowProjectionUpdateEvidence,
                          evidence.isCompleteForScope
                    else {
                        return
                    }
                    if recordsComponents {
                        spanRecorder.recordRuntimeFocusedRepairSpans(
                            focusedRepairCollector
                                .drain(
                                    processIdentifier:
                                        evidence.processIdentifier
                                )
                        )
                    }
                    completeProjectionUpdateGeneration &+= 1
                }
            }
        model.controlTabPressureDiagnostics.onRender = { [weak self, weak panelController, weak diagnosticState] event in
            guard let self, let diagnosticState, self.modelDiagnostics === diagnosticState else { return }
            panelController?.handlePressureRenderMilestone(event)
        }
        model.interactionDiagnosticSink = spanRecorder
        model.controlTabPressureDiagnostics.previewMeasurements = previewMeasurements
        panelAssembly = ControlTabPressurePanelAssembly(controller: panelController)
        model.previewBatchFactory = ControlTabPressurePreviewFactory(
            base: model.previewBatchFactory, recorder: spanRecorder, measurements: previewMeasurements
        )
        activationCoordinator.install(
            on: model,
            usesMockRuntime:
                FlowTabTestLaunchOptions.usesMockRuntimeProjection
        )
        panelController.registerHotkeyInputSource(
            hotkeyInputSourceID,
            for: .inAppWindowSwitcher
        )
        RuntimeLog.info(
            .uiTest,
            "installed Control+Tab pressure command observer "
                + "recorderMode="
                + (recordsComponents ? "full" : externalOnlyRecorderMode)
        )
    }

    private func receive(
        _ action: ControlTabPressureCommandAction,
        sequence: UInt64,
        panelController: SwitcherPanelController,
        delivery: ControlTabPressureEvidenceDelivery
    ) {
        if action == .cooldownBegin {
            focusedRepairCollector.reset()
            cooldownToken = makeToken(
                sequence: sequence,
                phase: .cooldown,
                panelController: panelController
            )
            if let cooldownToken {
                spanRecorder.beginPhase(cooldownToken)
            }
            return
        }
        if action == .cooldownEnd {
            guard let started = cooldownToken else { return }
            cooldownToken = nil
            let token = ControlTabPressureMeasurementToken(
                sequence: sequence,
                phase: .cooldown,
                startedAtNanoseconds:
                    started.startedAtNanoseconds,
                startedCPU: started.startedCPU,
                panelWasPresented: started.panelWasPresented,
                selectedAppIDBefore:
                    started.selectedAppIDBefore,
                selectedWindowIDBefore:
                    started.selectedWindowIDBefore,
                selectedWindowCountBefore:
                    started.selectedWindowCountBefore,
                activationRequestGenerationBefore:
                    started.activationRequestGenerationBefore,
                activationVerificationGenerationBefore:
                    started.activationVerificationGenerationBefore,
                completeProjectionUpdateGenerationBefore:
                    started
                        .completeProjectionUpdateGenerationBefore,
                focusedSessionDiagnosticGenerationBefore:
                    started.focusedSessionDiagnosticGenerationBefore,
                windowContentRenderGenerationBefore:
                    started.windowContentRenderGenerationBefore,
                reusableShellPreparationGenerationBefore:
                    started.reusableShellPreparationGenerationBefore,
                panelHiddenGenerationBefore:
                    started.panelHiddenGenerationBefore,
                cleanupCompleteGenerationBefore:
                    started.cleanupCompleteGenerationBefore,
                presentationCleanupRequiredBefore:
                    started.presentationCleanupRequiredBefore
            )
            let observation = makeObservation(
                token: token,
                panelController: panelController,
                delivery: delivery,
                strategy: .commandReturn
            )
            spanRecorder.setOutputSequence(sequence)
            observation.finishCooldown()
            return
        }
        guard let phase = action.phase else { return }
        guard let strategy = action.observationStrategy else {
            return
        }
        let token = makeToken(
            sequence: sequence,
            phase: phase,
            panelController: panelController
        )
        focusedRepairCollector.reset()
        spanRecorder.beginPhase(token)
        recordNoOpCancellationComponentsIfNeeded(
            token: token,
            panelController: panelController
        )
        let observation = makeObservation(
            token: token,
            panelController: panelController,
            delivery: delivery,
            strategy: strategy
        )
        observation.start()
        ensureInputMonitor(panelController: panelController)
        perform(action, panelController: panelController)
        observation.commandDidReturn()
    }

    private func makeToken(
        sequence: UInt64,
        phase: ControlTabPressurePhase,
        panelController: SwitcherPanelController
    ) -> ControlTabPressureMeasurementToken {
        ControlTabPressureMeasurementToken(
            sequence: sequence,
            phase: phase,
            startedAtNanoseconds:
                DispatchTime.now().uptimeNanoseconds,
            startedCPU: clock.snapshot(),
            panelWasPresented:
                panelController.isPanelPresented,
            selectedAppIDBefore:
                panelController.modelForTesting
                    .session?.selectedApp.id,
            selectedWindowIDBefore:
                panelController.modelForTesting
                    .session?.selectedWindow?.id,
            selectedWindowCountBefore:
                panelController.modelForTesting
                    .session?.selectedApp.windows.count ?? 0,
            activationRequestGenerationBefore:
                activationCoordinator.requestReceipt.generation,
            activationVerificationGenerationBefore:
                activationCoordinator.verificationReceipt.generation,
            completeProjectionUpdateGenerationBefore:
                completeProjectionUpdateGeneration,
            focusedSessionDiagnosticGenerationBefore:
                panelController
                    .focusedWindowSessionDiagnosticGeneration,
            windowContentRenderGenerationBefore:
                panelController.modelForTesting
                    .windowContentRenderGeneration,
            reusableShellPreparationGenerationBefore:
                panelController.reusableShellPreparationGeneration,
            panelHiddenGenerationBefore:
                panelController.panelHiddenReceipt.generation,
            cleanupCompleteGenerationBefore:
                panelController.cleanupCompleteReceipt.generation,
            presentationCleanupRequiredBefore:
                panelController.isPanelPresented
                    || panelController.hasActivePresentationSession
                    || panelController
                        .pendingFocusedWindowSessionPresentation != nil
        )
    }

    private func recordNoOpCancellationComponentsIfNeeded(
        token: ControlTabPressureMeasurementToken,
        panelController: SwitcherPanelController
    ) {
        guard token.phase == .cancel,
              !token.presentationCleanupRequiredBefore
        else {
            return
        }
        panelController.recordPanelHiddenMilestone()
        panelController.recordCleanupCompleteMilestone()
        for component in [
            SwitcherInteractionComponent.panelTeardown,
            .observerRemoval,
            .delayedTaskCancellation,
            .cacheSessionCleanup,
            .reusableShellPrepare
        ] {
            spanRecorder.recordUnexecutedComponent(
                component,
                parent: component == .panelTeardown
                    ? nil : .panelTeardown,
                outcome: .notRequired,
                workUnits: 0
            )
        }
    }

    private func makeObservation(
        token: ControlTabPressureMeasurementToken,
        panelController: SwitcherPanelController,
        delivery: ControlTabPressureEvidenceDelivery,
        strategy: ControlTabPressureObservationStrategy
    ) -> ControlTabPressureEventObservation {
        let observation = ControlTabPressureEventObservation(
            token: token,
            clock: clock,
            spanRecorder: spanRecorder,
            panelController: panelController,
            strategy: strategy,
            activationRequestReceipt: { [self] in
                activationCoordinator.requestReceipt
            },
            activationVerificationReceipt: { [self] in
                activationCoordinator.verificationReceipt
            },
            completeProjectionUpdateGeneration: { [self] in
                completeProjectionUpdateGeneration
            }
        ) { [weak self] evidence in
            guard let self else { return }
            activationCoordinator.phaseDidFinish(evidence.phase)
            activeObservations[evidence.sequence] = nil
            delivery.publish(evidence)
        }
        activeObservations[token.sequence] = observation
        return observation
    }

    private func perform(
        _ action: ControlTabPressureCommandAction,
        panelController: SwitcherPanelController
    ) {
        switch action {
        case .open, .forward, .reverse:
            panelController
                .setModifierReleaseConfirmationSuppressedForTesting(
                    true
                )
            panelController.inAppHotkeyHoldSetPressedOverride =
                true
            if let inputMonitor {
                inputMonitor.dispatch(phase: .pressed, isBackward: action == .reverse, holdSetPressedEvidence: true)
                return
            }
            panelController.registerHotkeyInputSource(
                hotkeyInputSourceID,
                for: .inAppWindowSwitcher
            )
            hotkeyInputSequence &+= 1
            let token = spanRecorder.beginComponent(.inputRouting, parent: nil, workUnits: 1)
            defer { spanRecorder.endComponent(token) }
            panelController.handleInAppWindowHotkeyInput(
                HotkeyInputEvent(
                    identity: HotkeyInputEventIdentity(
                        sourceID: hotkeyInputSourceID,
                        sequence: hotkeyInputSequence
                    ),
                    phase: .pressed,
                    isBackward: action == .reverse
                )
            )
        case .commit:
            panelController.finishSelection()
            releaseModifierOverride(
                panelController: panelController
            )
        case .cancel:
            panelController.cancelSelection(
                trigger: "controlTabPressure"
            )
            releaseModifierOverride(
                panelController: panelController
            )
        case .cooldownBegin, .cooldownEnd:
            break
        case .physicalOpen,
             .physicalForward,
             .physicalReverse,
             .physicalCommit,
             .physicalCancel:
            break
        }
    }

    private func releaseModifierOverride(
        panelController: SwitcherPanelController
    ) {
        panelController.globalHotkeyHoldSetPressedOverride = nil
        panelController.inAppHotkeyHoldSetPressedOverride = nil
        panelController.updateHotkeyHoldSetPressedEvidence(
            false,
            for: .globalAppSwitcher
        )
        panelController.updateHotkeyHoldSetPressedEvidence(
            false,
            for: .inAppWindowSwitcher
        )
        panelController.modifierReleaseObservationOwner
            .observeInputTransition()
        panelController
            .setModifierReleaseConfirmationSuppressedForTesting(
                false
            )
    }

    private func ensureInputMonitor(panelController: SwitcherPanelController) {
        guard let base = AppDelegate.shared?.inAppWindowHotkeyMonitor else { return }
        if let inputMonitor, inputMonitor.base === base { return }
        inputMonitor?.uninstall()
        let monitor = ControlTabPressureHotkeyMonitor(base: base, recorder: spanRecorder)
        inputMonitor = monitor
        panelController.registerHotkeyInputSource(monitor.inputSourceID, for: .inAppWindowSwitcher)
    }

    private func preserveModelAssembly(_ model: LiveSwitcherModel) {
        let session = model.sessionState
        let resources = model.sessionResources
        let didPublish = session.didPublish
        let preview = model.previewSession
        let publication = (preview as? SwitcherPreviewSession)?.publication
        let planner = model.previewPlanner
        let focused = model.focusedWindowSession
        let batchFactory = model.previewBatchFactory
        let onRender = model.controlTabPressureDiagnostics.onRender
        let measurements = model.controlTabPressureDiagnostics.previewMeasurements
        restoreModel = { [weak model] in
            guard let model else { return }
            session.didPublish = didPublish
            model.sessionState = session
            model.sessionResources = resources
            if let publication, let preview = preview as? SwitcherPreviewSession { preview.publication = publication }
            model.previewSession = preview
            model.previewPlanner = planner
            model.focusedWindowSession = focused
            model.previewBatchFactory = batchFactory
            model.controlTabPressureDiagnostics.onRender = onRender
            model.controlTabPressureDiagnostics.previewMeasurements = measurements
        }
    }

}
#endif
