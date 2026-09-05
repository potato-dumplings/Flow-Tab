#if FLOWTAB_TESTING
import FlowTabCore

@MainActor
final class ControlTabPressureWindowActivator: WindowActivating {
    let base: any WindowActivating
    private let recorder: ControlTabPressureSpanRecorder
    private let shouldDispatch: (ActivationTarget, [String: RuntimeAppContext]) -> Bool
    private let verified: (RuntimeWindowFocusVerification) -> Void

    var windowFocusVerifiedHandler: ((RuntimeWindowFocusVerification) -> Void)? {
        didSet { bindVerification() }
    }
    var windowFocusReadbackMismatchHandler: ((WindowBindingReadbackDiagnostic) -> Void)? {
        get { base.windowFocusReadbackMismatchHandler }
        set { base.windowFocusReadbackMismatchHandler = newValue }
    }

    init(base: any WindowActivating, recorder: ControlTabPressureSpanRecorder,
         shouldDispatch: @escaping (ActivationTarget, [String: RuntimeAppContext]) -> Bool,
         verified: @escaping (RuntimeWindowFocusVerification) -> Void) {
        self.base = base
        self.recorder = recorder
        self.shouldDispatch = shouldDispatch
        self.verified = verified
        windowFocusVerifiedHandler = base.windowFocusVerifiedHandler
        bindVerification()
    }

    private func bindVerification() {
        base.windowFocusVerifiedHandler = { [weak self] verification in
            guard let self else { return }
            windowFocusVerifiedHandler?(verification)
            verified(verification)
        }
    }

    func uninstall() {
        base.windowFocusVerifiedHandler = windowFocusVerifiedHandler
    }

    func activate(target: ActivationTarget, contextsByID: [String: RuntimeAppContext]) {
        let token = recorder.beginComponent(.activationDispatch, parent: .targetResolution, workUnits: 1)
        defer { recorder.endComponent(token) }
        guard shouldDispatch(target, contextsByID) else { return }
        base.activate(target: target, contextsByID: contextsByID)
    }
}
#endif
