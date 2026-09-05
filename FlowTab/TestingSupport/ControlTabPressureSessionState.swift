#if FLOWTAB_TESTING
import Combine
import FlowTabCore

@MainActor
final class ControlTabPressureSessionState: SwitcherSessionManaging {
    let base: any SwitcherSessionManaging
    let diagnostics: ControlTabPressureModelDiagnostics
    private var publicationParent: SwitcherInteractionComponent = .inputRouting
    private var publicationHandler: ((SwitcherSession?, SwitcherSession?) -> Void)?

    init(base: any SwitcherSessionManaging, diagnostics: ControlTabPressureModelDiagnostics) {
        self.base = base
        self.diagnostics = diagnostics
        didPublish = base.didPublish
    }

    var session: SwitcherSession? { base.session }
    var publisher: AnyPublisher<SwitcherSession?, Never> { base.publisher }
    var willChange: ObservableObjectPublisher { base.willChange }
    var didPublish: ((SwitcherSession?, SwitcherSession?) -> Void)? {
        get { publicationHandler }
        set {
            publicationHandler = newValue
            base.didPublish = { [diagnostics] previous, current in
                diagnostics.renderGeneration &+= 1
                newValue?(previous, current)
            }
        }
    }

    func publish(_ session: SwitcherSession?) {
        let started = LiveSwitcherModel.monotonicMilliseconds()
        let token = diagnostics.measurementSink?.beginComponent(.sessionPublish, parent: publicationParent, workUnits: 1)
        base.publish(session)
        diagnostics.measurementSink?.endComponent(token)
        diagnostics.sessionPublishMilliseconds += max(0, LiveSwitcherModel.monotonicMilliseconds() - started)
    }

    func applying(_ input: KeyInput) -> SwitcherSession? {
        publicationParent = .selectionMutation
        let token = diagnostics.measurementSink?.beginComponent(.selectionMutation, parent: .inputRouting, workUnits: 1)
        defer { diagnostics.measurementSink?.endComponent(token) }
        return base.applying(input)
    }

    func resolvingSelection() -> (session: SwitcherSession, target: ActivationTarget?)? {
        let token = diagnostics.measurementSink?.beginComponent(.targetResolution, workUnits: 1)
        defer { diagnostics.measurementSink?.endComponent(token) }
        return base.resolvingSelection()
    }

    func buildWindowSession(app: AppSwitchCandidate, preferences: SwitcherPreferences,
                            direction: CycleDirection, rememberedWindows: [String: String]) -> SwitcherSession? {
        publicationParent = .inputRouting
        let started = LiveSwitcherModel.monotonicMilliseconds()
        let token = diagnostics.measurementSink?.beginComponent(.sessionBuild, parent: .inputRouting, workUnits: app.windows.count)
        let result = base.buildWindowSession(app: app, preferences: preferences,
            direction: direction, rememberedWindows: rememberedWindows)
        diagnostics.measurementSink?.endComponent(token, outcome: result == nil ? .failed : .completed)
        diagnostics.sessionBuildMilliseconds += max(0, LiveSwitcherModel.monotonicMilliseconds() - started)
        return result
    }
}
#endif
