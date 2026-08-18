import Foundation

extension SwitcherPanelController {
    @discardableResult
    func prepareTerminateInterruptionProtection(
        trigger: String,
        appID: String
    ) -> Int {
        let generation =
            terminateInterruptionProtectionObservationOwner.prepareRequest(
                trigger: trigger,
                presentationGeneration: presentationSessionGeneration,
                baseline: captureTerminateInterruptionProtectionBaseline(
                    appID: appID
                )
            )
        logSearchTrace(
            "terminateInterruptionProtection trigger=\(trigger) action=prepared generation=\(generation) presentationGeneration=\(presentationSessionGeneration) \(searchTraceStateSummary())"
        )
        return generation
    }

    func commitTerminateInterruptionProtection(
        observationGeneration: Int,
        request: LiveSwitcherModel.PendingTerminateRequest
    ) {
        let target = TerminateInterruptionTargetIdentity(
            appID: request.appID,
            pid: request.pid,
            requestGeneration: request.generation
        )
        let committed =
            terminateInterruptionProtectionObservationOwner
                .commitPreparedRequest(
                    observationGeneration: observationGeneration,
                    target: target,
                    watchdogInterval:
                        terminateInterruptionProtectionWatchdogInterval,
                    readback: { [unowned self] in
                        self.terminateInterruptionProtectionSnapshot(
                            target: target
                        )
                    },
                    onResolved: { [weak self] evidence in
                        self?.handleResolvedTerminateInterruptionProtection(
                            evidence
                        )
                    },
                    onWatchdog: { [weak self] failure in
                        self?.handleTerminateInterruptionProtectionWatchdog(
                            failure
                        )
                    }
                )
        guard committed else {
            logSearchTrace(
                "terminateInterruptionProtection action=commitRejected generation=\(observationGeneration) targetAppID=\(target.appID) targetPID=\(target.pid) requestGeneration=\(request.generation) \(searchTraceStateSummary())"
            )
            return
        }
        logSearchTrace(
            "terminateInterruptionProtection action=observing generation=\(observationGeneration) targetAppID=\(target.appID) targetPID=\(target.pid) requestGeneration=\(request.generation) watchdogMs=\(formatMilliseconds(terminateInterruptionProtectionWatchdogInterval * 1_000)) \(searchTraceStateSummary())"
        )
    }

    func cancelPreparedTerminateInterruptionProtection(
        observationGeneration: Int
    ) {
        terminateInterruptionProtectionObservationOwner
            .cancelPreparedRequest(
                observationGeneration: observationGeneration
            )
    }

    func cancelTerminateInterruptionProtection() {
        terminateInterruptionProtectionObservationOwner.cancel()
    }

    func observeWorkspaceTerminationForInterruptionProtection(
        appID: String,
        pid: pid_t,
        baseline: TerminateInterruptionProtectionBaseline,
        refreshedSession: Bool
    ) {
        guard refreshedSession else { return }
        if terminateInterruptionProtectionObservationOwner.isObserving {
            _ = terminateInterruptionProtectionObservationOwner
                .observeWorkspaceTermination(
                    appID: appID,
                    pid: pid,
                    presentationGeneration:
                        presentationSessionGeneration
                )
            return
        }

        let target = TerminateInterruptionTargetIdentity(
            appID: appID,
            pid: pid,
            requestGeneration: nil
        )
        let generation =
            terminateInterruptionProtectionObservationOwner
                .startObservedTermination(
                    trigger: "workspace_termination",
                    presentationGeneration:
                        presentationSessionGeneration,
                    target: target,
                    baseline: baseline,
                    watchdogInterval:
                        terminateInterruptionProtectionWatchdogInterval,
                    readback: { [unowned self] in
                        self.terminateInterruptionProtectionSnapshot(
                            target: target
                        )
                    },
                    onResolved: { [weak self] evidence in
                        self?.handleResolvedTerminateInterruptionProtection(
                            evidence
                        )
                    },
                    onWatchdog: { [weak self] failure in
                        self?.handleTerminateInterruptionProtectionWatchdog(
                            failure
                        )
                    }
                )
        logSearchTrace(
            "terminateInterruptionProtection trigger=workspace_termination action=observing generation=\(generation) targetAppID=\(appID) targetPID=\(pid) requestGeneration=none watchdogMs=\(formatMilliseconds(terminateInterruptionProtectionWatchdogInterval * 1_000)) \(searchTraceStateSummary())"
        )
    }

    func observeTerminateInterruptionProtectionProjectionUpdate() {
        guard terminateInterruptionProtectionObservationOwner.isObserving else {
            return
        }
        _ = terminateInterruptionProtectionObservationOwner
            .observeProjectionUpdate(
                presentationGeneration: presentationSessionGeneration
            )
    }

    func observeTerminateInterruptionProtectionPresentationUpdate(
        source: TerminateInterruptionProtectionEvidenceSource
    ) {
        guard terminateInterruptionProtectionObservationOwner.isObserving else {
            return
        }
        _ = terminateInterruptionProtectionObservationOwner
            .observePresentationUpdate(
                source: source,
                presentationGeneration: presentationSessionGeneration
            )
    }

    func observeProtectedTerminateSystemInterruption() {
        guard terminateInterruptionProtectionObservationOwner.isObserving else {
            return
        }
        _ = terminateInterruptionProtectionObservationOwner
            .observeProtectedSystemInterruption(
                presentationGeneration: presentationSessionGeneration
            )
    }

    func shouldProtectTerminateSystemInterruption() -> Bool {
        terminateInterruptionProtectionObservationOwner.isObserving
            && model.session != nil
    }

    func captureTerminateInterruptionProtectionBaseline(
        appID: String
    ) -> TerminateInterruptionProtectionBaseline {
        let service = model.runtimeProjectionService
        let projection = service.readAppSwitcherProjection()
        return TerminateInterruptionProtectionBaseline(
            appID: appID,
            projectionGeneration:
                projection?.freshness.sourceGeneration.projection
                ?? service.runtimeReadModelDiagnostics()
                    .generation.projection,
            projectionContainsAppID: projection.map { projection in
                projection.apps.contains { $0.id == appID }
            },
            panelVisibility: panelVisibilitySnapshot()
        )
    }

    private func terminateInterruptionProtectionSnapshot(
        target: TerminateInterruptionTargetIdentity
    ) -> TerminateInterruptionProtectionSnapshot {
        let service = model.runtimeProjectionService
        let projection = service.readAppSwitcherProjection()
        let projectionGeneration =
            projection?.freshness.sourceGeneration.projection
            ?? service.runtimeReadModelDiagnostics()
                .generation.projection
        let projectionState: TerminateTargetProjectionState
        if let projection {
            if !projection.apps.contains(where: {
                $0.id == target.appID
            }) {
                projectionState = .instanceAbsent
            } else if let context =
                projection.contextsByID[target.appID]
            {
                projectionState = context.ownerPID == target.pid
                    ? .exactInstancePresent
                    : .instanceReplaced
            } else {
                projectionState = .identityUnavailable
            }
        } else {
            projectionState = .projectionUnavailable
        }
        let pendingRequestMatches =
            model.pendingTerminateRequest.map {
                $0.appID == target.appID
                    && $0.pid == target.pid
                    && (
                        target.requestGeneration == nil
                            || $0.generation
                                == target.requestGeneration
                    )
            } ?? false
        return TerminateInterruptionProtectionSnapshot(
            projectionGeneration: projectionGeneration,
            projectionState: projectionState,
            processState:
                terminateTargetProcessStateReader.state(
                    forPID: target.pid
                ),
            sessionContainsAppID:
                model.session?.apps.contains {
                    $0.id == target.appID
                } ?? false,
            pendingRequestMatches: pendingRequestMatches,
            activeSpaceTransitionPending:
                activeSpaceTransitionObservationOwner.isObserving,
            panelVisibility: panelVisibilitySnapshot()
        )
    }

    private func handleResolvedTerminateInterruptionProtection(
        _ evidence: TerminateInterruptionProtectionEvidence
    ) {
        guard isPresentationSessionGenerationCurrent(
            evidence.presentationGeneration
        ) else {
            return
        }
        if evidence.snapshot.pendingRequestMatches {
            _ = model.handleApplicationTerminated(
                appID: evidence.target.appID,
                pid: evidence.target.pid
            )
        }
        logSearchTrace(
            "terminateInterruptionProtection action=resolved generation=\(evidence.observationGeneration) presentationGeneration=\(evidence.presentationGeneration) source=\(evidence.source.rawValue) matchingTerminationObserved=\(evidence.matchingTerminationObserved ? 1 : 0) protectedSystemInterruptionObserved=\(evidence.protectedSystemInterruptionObserved ? 1 : 0) targetAppID=\(evidence.target.appID) targetPID=\(evidence.target.pid) evidence{\(evidence.snapshot.logFields)} \(searchTraceStateSummary())"
        )
    }

    private func handleTerminateInterruptionProtectionWatchdog(
        _ failure: TerminateInterruptionProtectionWatchdogFailure
    ) {
        guard isPresentationSessionGenerationCurrent(
            failure.presentationGeneration
        ) else {
            return
        }
        logSearchTrace(
            "terminateInterruptionProtection action=watchdog generation=\(failure.observationGeneration) presentationGeneration=\(failure.presentationGeneration) \(failure.logFields) \(searchTraceStateSummary())"
        )
    }
}
