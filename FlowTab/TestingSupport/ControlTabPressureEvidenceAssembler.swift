#if FLOWTAB_TESTING
import Foundation

@MainActor
struct ControlTabPressureEvidenceContext {
    let token: ControlTabPressureMeasurementToken
    let completedAtNanoseconds: UInt64
    let completedCPU: ControlTabProcessCPUSnapshot
    let panelController: SwitcherPanelController
    let strategy: ControlTabPressureObservationStrategy
    let commandReturnedAtNanoseconds: UInt64?
    let activationRequest: ControlTabActivationRequestReceipt
    let activationVerification:
        ControlTabActivationVerificationReceipt
    let completeProjectionUpdateGeneration: UInt64
    let latePresentationObserved: Bool
    let cachedFirstFrameCPU: ControlTabProcessCPUSnapshot?
    let freshVisiblePreviewsCompleteCPU:
        ControlTabProcessCPUSnapshot?
    let spanEvidence: ControlTabPressureSpanEvidence
    let watchdogExpired: Bool
}

@MainActor
enum ControlTabPressureEvidenceAssembler {
    static func make(
        context: ControlTabPressureEvidenceContext
    ) -> ControlTabPressureEvidence {
        let token = context.token
        let panelController = context.panelController
        let duration = ControlTabPressureMetricRules.duration(
            startedAtNanoseconds: token.startedAtNanoseconds,
            completedAtNanoseconds: context.completedAtNanoseconds,
            startedCPU: token.startedCPU,
            completedCPU: context.completedCPU
        )
        let model = panelController.modelForTesting
        let session = model.session
        let selectedAfter = session?.selectedWindow?.id
        let panelPresented = panelController.isPanelPresented
        let userVisible = panelController.isPanelVisibleToUser
        var partitions: [String: Double] = [:]
        var milestones: [String: Double] = [:]
        var partitionsReconciled = true
        if token.phase == .open,
           let diagnostic =
            panelController.lastFocusedWindowSessionDiagnostic
        {
            partitions = diagnostic.partitions
            milestones = diagnostic.milestones
            if let cachedFirstFrameCPU =
                    context.cachedFirstFrameCPU,
               let cpuTime = cpuTimeMilliseconds(
                    from: token.startedCPU,
                    to: cachedFirstFrameCPU
               ) {
                milestones[
                    FocusedWindowSessionDiagnostic.MilestoneKey
                        .cachedFirstFrameCPUTime
                ] = cpuTime
            }
            if let freshVisiblePreviewsCompleteCPU =
                    context.freshVisiblePreviewsCompleteCPU,
               let cpuTime = cpuTimeMilliseconds(
                    from: token.startedCPU,
                    to: freshVisiblePreviewsCompleteCPU
               ) {
                milestones[
                    FocusedWindowSessionDiagnostic.MilestoneKey
                        .freshVisiblePreviewsCompleteCPUTime
                ] = cpuTime
            }
            partitionsReconciled = diagnostic.reconciles
        }
        if let commandReturnedAtNanoseconds =
            context.commandReturnedAtNanoseconds
        {
            let commandNanoseconds = commandReturnedAtNanoseconds
                >= token.startedAtNanoseconds
                ? commandReturnedAtNanoseconds
                    - token.startedAtNanoseconds
                : 0
            milestones["command_return_ms"] =
                Double(commandNanoseconds) / 1_000_000
        }
        if token.phase != .open {
            partitions["command_execution_ms"] =
                milestones["command_return_ms"] ?? 0
        }
        let selectedWindowCount =
            session?.selectedApp.windows.count ?? 0
        let activationRequestIssued = token.phase == .commit
            && context.activationRequest.generation
                > token.activationRequestGenerationBefore
            && context.activationRequest
                .issuedAtUptimeNanoseconds
                >= token.startedAtNanoseconds
        let activationVerified = token.phase == .commit
            && context.activationVerification.generation
                > token.activationVerificationGenerationBefore
            && context.activationVerification.satisfied
        if activationRequestIssued {
            milestones["activation_request_ms"] = Double(
                context.activationRequest
                    .issuedAtUptimeNanoseconds
                    - token.startedAtNanoseconds
            ) / 1_000_000
        }
        if activationVerified,
           context.activationVerification
            .verifiedAtUptimeNanoseconds
                >= token.startedAtNanoseconds {
            milestones["focus_verified_ms"] = Double(
                context.activationVerification
                    .verifiedAtUptimeNanoseconds
                    - token.startedAtNanoseconds
            ) / 1_000_000
        }
        let panelHiddenReceipt = panelController
            .panelHiddenReceipt
        if panelHiddenReceipt.generation
                > token.panelHiddenGenerationBefore,
           panelHiddenReceipt.recordedAtUptimeNanoseconds
                >= token.startedAtNanoseconds {
            milestones["panel_hidden_ms"] = Double(
                panelHiddenReceipt.recordedAtUptimeNanoseconds
                    - token.startedAtNanoseconds
            ) / 1_000_000
        }
        let cleanupCompleteReceipt = panelController
            .cleanupCompleteReceipt
        if cleanupCompleteReceipt.generation
                > token.cleanupCompleteGenerationBefore,
           cleanupCompleteReceipt.recordedAtUptimeNanoseconds
                >= token.startedAtNanoseconds {
            milestones["cleanup_complete_ms"] = Double(
                cleanupCompleteReceipt
                    .recordedAtUptimeNanoseconds
                    - token.startedAtNanoseconds
            ) / 1_000_000
        }
        let satisfied = duration.isValid
            && !context.watchdogExpired
            && context.spanEvidence.isValid
            && correctness(
                context: context,
                selectedWindowIDAfter: selectedAfter,
                selectedWindowCount: selectedWindowCount,
                partitionsReconciled: partitionsReconciled,
                activationRequestIssued: activationRequestIssued,
                activationVerified: activationVerified
            )
        return ControlTabPressureEvidence(
            sequence: token.sequence,
            phase: token.phase,
            startedAtNanoseconds: token.startedAtNanoseconds,
            completedAtNanoseconds: context.completedAtNanoseconds,
            duration: duration,
            timingValid: duration.isValid,
            satisfied: satisfied,
            panelPresented: panelPresented,
            userVisible: userVisible,
            selectedAppID:
                session?.selectedApp.id
                    ?? token.selectedAppIDBefore,
            selectedWindowIDBefore: token.selectedWindowIDBefore,
            selectedWindowIDAfter: selectedAfter,
            projectedAppCount:
                model.runtimeProjectionService
                    .readAppSwitcherProjection()?.apps.count ?? 0,
            selectedWindowCount:
                selectedWindowCount > 0
                    ? selectedWindowCount
                    : token.selectedWindowCountBefore,
            activationRequestIssued: activationRequestIssued,
            activationVerified: activationVerified,
            activationTargetPID:
                context.activationVerification.processIdentifier,
            activationTargetWindowID:
                context.activationVerification.windowID,
            activationTargetCGWindowID:
                context.activationVerification.cgWindowID,
            latePresentationObserved:
                context.latePresentationObserved,
            projectionGeneration:
                model.selectedAppWindowProjectionGeneration,
            accessibilityTrusted:
                AccessibilityPermissionChecker.isTrusted(),
            screenCaptureTrusted:
                ScreenCapturePermissionChecker
                    .hasScreenCapturePermission,
            partitions: partitions,
            milestones: milestones,
            partitionsReconciled: partitionsReconciled,
            spans: context.spanEvidence.spans,
            requiredComponentsPresent:
                context.spanEvidence.requiredComponentsPresent,
            timelineReconciled:
                context.spanEvidence.timelineReconciled,
            componentTimingValid:
                context.spanEvidence.componentTimingValid,
            watchdogExpired: context.watchdogExpired
        )
    }

    private static func cpuTimeMilliseconds(
        from started: ControlTabProcessCPUSnapshot,
        to completed: ControlTabProcessCPUSnapshot
    ) -> Double? {
        guard let startedTotal = started.totalNanoseconds,
              let completedTotal = completed.totalNanoseconds,
              completedTotal >= startedTotal
        else {
            return nil
        }
        return Double(completedTotal - startedTotal) / 1_000_000
    }

    private static func correctness(
        context: ControlTabPressureEvidenceContext,
        selectedWindowIDAfter: String?,
        selectedWindowCount: Int,
        partitionsReconciled: Bool,
        activationRequestIssued: Bool,
        activationVerified: Bool
    ) -> Bool {
        let token = context.token
        let panelController = context.panelController
        switch token.phase {
        case .open:
            let diagnostic = panelController
                .lastFocusedWindowSessionDiagnostic
            return panelController.isPanelPresented
                && panelController.isPanelVisibleToUser
                && panelController.modelForTesting
                    .isWindowOnlyOverlay
                && panelController.modelForTesting
                    .session?.apps.count == 1
                && selectedWindowCount > 0
                && selectedWindowIDAfter != nil
                && diagnostic?.result.hasPrefix("ready") == true
                && partitionsReconciled
        case .forward, .reverse:
            return panelController.isPanelPresented
                && selectedWindowCount > 0
                && selectedWindowIDAfter != nil
                && (
                    selectedWindowCount == 1
                        || selectedWindowIDAfter
                            != token.selectedWindowIDBefore
                )
        case .commit, .cancel:
            let reachedClosedState =
                !panelController.isPanelPresented
                && !panelController.isPanelVisibleToUser
                && panelController.modelForTesting.session == nil
                && !panelController
                    .suppressHotkeyReplayUntilReleaseForTesting
            if token.phase == .commit {
                return reachedClosedState
                    && activationRequestIssued
                    && activationVerified
            }
            if context.strategy == .cancelledPresentationReadback {
                return reachedClosedState
                    && !context.latePresentationObserved
                    && context.completeProjectionUpdateGeneration
                        > token.completeProjectionUpdateGenerationBefore
                    && panelController
                        .pendingFocusedWindowSessionPresentation == nil
            }
            return reachedClosedState
        case .cooldown:
            return !token.panelWasPresented
                && !panelController.isPanelPresented
                && !panelController.isPanelVisibleToUser
                && panelController.modelForTesting.session == nil
                && !panelController
                    .suppressHotkeyReplayUntilReleaseForTesting
        }
    }
}
#endif
