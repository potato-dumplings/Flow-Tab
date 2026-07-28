import AppKit
import CoreGraphics

extension RuntimeActivator {
    func startFocusRecovery(
        for request: WindowFocusRequest,
        in app: NSRunningApplication
    ) -> UInt64? {
        let target = RuntimeFocusRecoveryTarget(
            appID: request.appID,
            pid: app.processIdentifier,
            windowID: request.windowID,
            targetCGWindowID: request.targetCGWindowID(
                expectedPID: app.processIdentifier
            )
        )
        return focusRecoveryCoordinator.start(
            target: target,
            policy: focusRecoveryPolicy
        ) { [weak self] trigger in
            guard let self else {
                return RuntimeFocusRecoveryReadback(
                    completed: false,
                    observation: RuntimeFocusRecoveryObservation(
                        conditionSatisfied: false,
                        processIsTerminated: app.isTerminated,
                        targetIsVisible: false,
                        focusedCGWindowID: nil,
                        frontmostCGWindowID: nil,
                        visibleCGWindowIDs: []
                    )
                )
            }
            return self.performFocusRecoveryReadback(
                trigger: trigger,
                request: request,
                app: app
            )
        }
    }

    func completeFocusRecoveryInitialAction(generation: UInt64?) {
        guard let generation else { return }
        focusRecoveryCoordinator.completeInitialAction(
            generation: generation,
            reason: "initialActionVerified"
        )
    }

    func performFocusRecoveryInitialReadback(generation: UInt64?) {
        guard let generation else { return }
        focusRecoveryCoordinator.performInitialReadback(
            generation: generation
        )
    }

    private func performFocusRecoveryReadback(
        trigger: RuntimeFocusRecoveryTrigger,
        request: WindowFocusRequest,
        app: NSRunningApplication
    ) -> RuntimeFocusRecoveryReadback {
        var evidence = focusRecoveryObservation(
            trigger: trigger,
            request: request,
            app: app
        )
        if evidence.observation.conditionSatisfied {
            _ = reportWindowFocusVerified(
                request,
                readback: evidence.focusReadback,
                in: app
            )
            return RuntimeFocusRecoveryReadback(
                completed: true,
                observation: evidence.observation
            )
        }

        if trigger.permitsRecoveryAction,
           attemptWindowFocus(
               request,
               in: app,
               allowChromeInternalFocus: false
           ) {
            evidence = focusRecoveryObservation(
                trigger: trigger,
                request: request,
                app: app
            )
            return RuntimeFocusRecoveryReadback(
                completed: true,
                observation: evidence.observation
            )
        }

        if trigger.permitsRecoveryAction {
            evidence = focusRecoveryObservation(
                trigger: trigger,
                request: request,
                app: app
            )
        }
        return RuntimeFocusRecoveryReadback(
            completed: false,
            observation: evidence.observation
        )
    }

    private func focusRecoveryObservation(
        trigger: RuntimeFocusRecoveryTrigger,
        request: WindowFocusRequest,
        app: NSRunningApplication
    ) -> (
        observation: RuntimeFocusRecoveryObservation,
        focusReadback: RuntimeWindowFocusReadbackEvidence
    ) {
        let targetCGWindowID = request.targetCGWindowID(
            expectedPID: app.processIdentifier
        )
        let currentWindows = currentCGWindows(
            forPID: app.processIdentifier
        )
        let focusReadback = currentWindowFocusReadbackEvidence(in: app)
        let focusedCGWindowID = focusReadback.focusedCGWindowID
        let frontmostCGWindowID = frontmostVisibleCGWindowID(
            in: currentWindows
        )
        let visibleCGWindowIDs = currentWindows
            .filter {
                $0.isOnscreen
                    && RuntimeCGWindowFacts.passesValidityConstraints($0)
            }
            .map(\.id)
        let targetIsVisible = targetCGWindowID.map {
            visibleCGWindowIDs.contains($0)
        } ?? false
        let conditionSatisfied = targetCGWindowID.map {
            focusedCGWindowID == $0
                || (focusedCGWindowID == nil && frontmostCGWindowID == $0)
        } ?? false
        let observation = RuntimeFocusRecoveryObservation(
            conditionSatisfied: conditionSatisfied,
            processIsTerminated:
                trigger == .targetApplicationTerminated || app.isTerminated,
            targetIsVisible: targetIsVisible,
            focusedCGWindowID: focusedCGWindowID,
            frontmostCGWindowID: frontmostCGWindowID,
            visibleCGWindowIDs: visibleCGWindowIDs
        )
        RuntimeLog.debug(
            .activation,
            [
                "focus-recovery",
                "state=readback",
                "trigger=\(trigger.logValue)",
                "appID=\(request.appID)",
                "pid=\(app.processIdentifier)",
                "windowID=\(request.windowID)",
                "targetCG=\(targetCGWindowID.map(String.init) ?? "nil")",
                "conditionSatisfied=\(conditionSatisfied ? 1 : 0)",
                "processTerminated=\(observation.processIsTerminated ? 1 : 0)",
                "targetVisible=\(targetIsVisible ? 1 : 0)",
                "focusedCG=\(focusedCGWindowID.map(String.init) ?? "nil")",
                "frontmostCG=\(frontmostCGWindowID.map(String.init) ?? "nil")",
                "visibleCG=\(visibleCGWindowIDs.map(String.init).joined(separator: ","))"
            ].joined(separator: " ")
        )
        return (observation, focusReadback)
    }
}
