import FlowTabCore

@MainActor
protocol WindowActivating: AnyObject {
    var windowFocusVerifiedHandler: ((RuntimeWindowFocusVerification) -> Void)? { get set }
    var windowFocusReadbackMismatchHandler: ((WindowBindingReadbackDiagnostic) -> Void)? { get set }
    func activate(target: ActivationTarget, contextsByID: [String: RuntimeAppContext])
}
