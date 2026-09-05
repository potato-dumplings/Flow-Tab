#if FLOWTAB_TESTING
import Foundation

@MainActor
final class ControlTabPressureSessionResources: SwitcherSessionResourceManaging {
    let base: any SwitcherSessionResourceManaging
    let contexts: SwitcherRuntimeContextStore
    let diagnostics: ControlTabPressureModelDiagnostics
    init(base: any SwitcherSessionResourceManaging, contexts: SwitcherRuntimeContextStore,
         diagnostics: ControlTabPressureModelDiagnostics) {
        self.base = base
        self.contexts = contexts
        self.diagnostics = diagnostics
    }
    func resetSession() { base.resetSession() }
    func resetRuntime() {
        let sink = diagnostics.measurementSink
        let token = sink?.beginComponent(.cacheSessionCleanup, parent: nil, workUnits: contexts.values.count)
        defer { sink?.endComponent(token) }
        base.resetRuntime()
    }
}
#endif
