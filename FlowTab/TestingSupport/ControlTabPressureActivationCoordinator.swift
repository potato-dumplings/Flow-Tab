#if FLOWTAB_TESTING
import CoreGraphics
import Foundation
import FlowTabCore

@MainActor
final class ControlTabPressureActivationCoordinator {
    private let spanRecorder: ControlTabPressureSpanRecorder
    private(set) var requestReceipt =
        ControlTabActivationRequestReceipt(
            generation: 0,
            issuedAtUptimeNanoseconds: 0
        )
    private(set) var verificationReceipt =
        ControlTabActivationVerificationReceipt(
            generation: 0,
            processIdentifier: 0,
            windowID: nil,
            cgWindowID: nil,
            satisfied: false,
            verificationRequired: false,
            verifiedAtUptimeNanoseconds: 0
        )
    private var pendingExactActivationSpan:
        SwitcherInteractionSpanToken?
    private var originalActivationOverride: ((ActivationTarget, [String: RuntimeAppContext]) -> Void)?
    private var isInstalled = false
    private var acceptsVerification = false

    init(spanRecorder: ControlTabPressureSpanRecorder) {
        self.spanRecorder = spanRecorder
    }

    func reset() {
        requestReceipt = ControlTabActivationRequestReceipt(
            generation: 0,
            issuedAtUptimeNanoseconds: 0
        )
        verificationReceipt =
            ControlTabActivationVerificationReceipt(
                generation: 0,
                processIdentifier: 0,
                windowID: nil,
                cgWindowID: nil,
                satisfied: false,
                verificationRequired: false,
                verifiedAtUptimeNanoseconds: 0
            )
        pendingExactActivationSpan = nil
        acceptsVerification = false
    }

    func uninstall(from model: LiveSwitcherModel) {
        guard isInstalled else { return }
        isInstalled = false
        model.activationOverride = originalActivationOverride
        originalActivationOverride = nil
        if let decorated = model.activator as? ControlTabPressureWindowActivator {
            decorated.uninstall()
            model.activator = decorated.base
        }
        reset()
    }

    func install(on model: LiveSwitcherModel, usesMockRuntime: Bool) {
        if isInstalled { uninstall(from: model) }
        originalActivationOverride = model.activationOverride
        isInstalled = true
        let verify: (RuntimeWindowFocusVerification) -> Void = {
            [weak self] verification in
            guard let self, self.isInstalled, self.acceptsVerification,
                  verification.ownerPID
                    == self.verificationReceipt.processIdentifier,
                  verification.windowID
                    == self.verificationReceipt.windowID,
                  verification.targetCGWindowID == self.verificationReceipt.cgWindowID,
                  verification.targetCGWindowID == nil
                    || verification.targetCGWindowID == verification.focusedCGWindowID
            else {
                return
            }
            self.acceptsVerification = false
            self.spanRecorder.endComponent(
                self.pendingExactActivationSpan,
                workUnits: 1
            )
            self.pendingExactActivationSpan = nil
            self.verificationReceipt =
                ControlTabActivationVerificationReceipt(
                    generation:
                        self.verificationReceipt.generation &+ 1,
                    processIdentifier: verification.ownerPID,
                    windowID: verification.windowID,
                    cgWindowID: verification.targetCGWindowID,
                    satisfied: verification.targetCGWindowID == nil
                        || verification.targetCGWindowID
                            == verification.focusedCGWindowID,
                    verificationRequired: true,
                    verifiedAtUptimeNanoseconds:
                        DispatchTime.now().uptimeNanoseconds
                )
        }
        model.activationOverride = nil
        model.activator = ControlTabPressureWindowActivator(
            base: model.activator, recorder: spanRecorder, shouldDispatch: {
            [weak self]
            target, contexts in
            guard let self else { return false }
            self.requestReceipt = ControlTabActivationRequestReceipt(
                generation: self.requestReceipt.generation &+ 1,
                issuedAtUptimeNanoseconds:
                    DispatchTime.now().uptimeNanoseconds
            )
            if usesMockRuntime {
                self.recordMockVerification(
                    target: target,
                    contexts: contexts
                )
                RuntimeLog.info(
                    .uiTest,
                    "Control+Tab pressure activation request target=\(String(describing: target))"
                )
            } else {
                self.beginExactActivation(
                    target: target,
                    contexts: contexts
                )
                return true
            }
            return false
        }, verified: verify)
    }

    func phaseDidFinish(_ phase: ControlTabPressurePhase) {
        guard phase == .commit else { return }
        pendingExactActivationSpan = nil
        acceptsVerification = false
    }

    private func beginExactActivation(
        target: ActivationTarget,
        contexts: [String: RuntimeAppContext]
    ) {
        guard case .window(let appID, let windowID, _) = target,
              let context = contexts[appID],
              let window = context.windowsByID[windowID]
        else {
            spanRecorder.recordUnexecutedComponent(
                .exactWindowActivation,
                outcome: .notRequired
            )
            spanRecorder.recordUnexecutedComponent(
                .focusReadback,
                outcome: .notRequired
            )
            verificationReceipt =
                ControlTabActivationVerificationReceipt(
                    generation:
                        verificationReceipt.generation &+ 1,
                    processIdentifier: 0,
                    windowID: nil,
                    cgWindowID: nil,
                    satisfied: true,
                    verificationRequired: false,
                    verifiedAtUptimeNanoseconds:
                        DispatchTime.now().uptimeNanoseconds
                )
            return
        }
        verificationReceipt =
            ControlTabActivationVerificationReceipt(
                generation: verificationReceipt.generation,
                processIdentifier: context.ownerPID,
                windowID: windowID,
                cgWindowID: window.cgWindowID
                    ?? RuntimeActivator.cgWindowID(from: windowID, expectedPID: context.ownerPID),
                satisfied: false,
                verificationRequired: true,
                verifiedAtUptimeNanoseconds: 0
            )
        pendingExactActivationSpan = spanRecorder.beginComponent(
            .exactWindowActivation,
            parent: .activationDispatch,
            workUnits: 1
        )
        acceptsVerification = true
    }

    private func recordMockVerification(
        target: ActivationTarget,
        contexts: [String: RuntimeAppContext]
    ) {
        let identity: (pid_t, String?, CGWindowID?)
        if case .window(let appID, let windowID, _) = target,
           let context = contexts[appID]
        {
            identity = (
                context.ownerPID,
                windowID,
                context.windowsByID[windowID]?.cgWindowID
            )
        } else {
            identity = (0, nil, nil)
        }
        spanRecorder.recordUnexecutedComponent(
            .exactWindowActivation,
            parent: .activationDispatch,
            outcome: .notRequired,
            workUnits: 1
        )
        spanRecorder.recordUnexecutedComponent(
            .focusReadback,
            parent: .exactWindowActivation,
            outcome: .notRequired,
            workUnits: 1
        )
        verificationReceipt =
            ControlTabActivationVerificationReceipt(
                generation: verificationReceipt.generation &+ 1,
                processIdentifier: identity.0,
                windowID: identity.1,
                cgWindowID: identity.2,
                satisfied: true,
                verificationRequired: false,
                verifiedAtUptimeNanoseconds:
                    DispatchTime.now().uptimeNanoseconds
            )
    }
}
#endif
