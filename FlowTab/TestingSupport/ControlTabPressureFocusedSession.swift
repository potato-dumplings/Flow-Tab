#if FLOWTAB_TESTING
import Foundation
import FlowTabCore

@MainActor
final class ControlTabPressureFocusedSession: SwitcherFocusedWindowSessionStarting {
    let base: any SwitcherFocusedWindowSessionStarting
    let original: any SwitcherFocusedWindowSessionStarting
    let diagnostics: ControlTabPressureModelDiagnostics
    private let reader: ControlTabPressureFocusedProjection?
    private unowned let model: LiveSwitcherModel

    init(base: any SwitcherFocusedWindowSessionStarting, model: LiveSwitcherModel,
         diagnostics: ControlTabPressureModelDiagnostics) {
        self.original = base
        self.model = model
        self.diagnostics = diagnostics
        if let coordinator = base as? SwitcherFocusedWindowSessionCoordinator {
            let reader = ControlTabPressureFocusedProjection(base: coordinator.projection, diagnostics: diagnostics)
            self.reader = reader
            self.base = SwitcherFocusedWindowSessionCoordinator(model: coordinator.model, projection: reader,
                installation: ControlTabPressureFocusedInstallation(base: coordinator.installation, diagnostics: diagnostics))
        } else {
            self.reader = nil
            self.base = base
        }
    }

    func startFocusedAppWindowSession(triggerDirection: CycleDirection) -> FocusedAppWindowSessionStartResult {
        diagnostics.finishReconciliation(outcome: .cancelled)
        diagnostics.beginFocusedSession(startedAt: LiveSwitcherModel.monotonicMilliseconds())
        reader?.pending = nil
        let result = base.startFocusedAppWindowSession(triggerDirection: triggerDirection)
        let name: String
        switch result {
        case .ready: name = "ready"
        case .awaitingFreshProjection: name = "awaitingFreshProjection"
        case .unavailable: name = reader?.lastRead == nil ? "noFrontmostApp" : "noWindows"
        }
        record(result: name)
        return result
    }

    func completePendingFocusedAppWindowSession(_ pending: PendingFocusedAppWindowSession) -> Bool {
        reader?.pending = pending
        defer { reader?.pending = nil }
        let completed = base.completePendingFocusedAppWindowSession(pending)
        if completed { record(result: "readyAfterFreshness") }
        return completed
    }

    private func record(result: String) {
        model.pressureRecordFocusedStart(result: result, appID: reader?.lastRead?.appID,
            projectionReadMs: diagnostics.recencyStartedAt,
            recencyAppliedMs: diagnostics.recencyCompletedAt,
            completeMs: LiveSwitcherModel.monotonicMilliseconds(),
            windowCount: model.session?.selectedApp.windows.count ?? 0)
    }
}

@MainActor
private final class ControlTabPressureFocusedProjection: SwitcherFocusedWindowProjectionReading {
    let base: any SwitcherFocusedWindowProjectionReading
    let diagnostics: ControlTabPressureModelDiagnostics
    var pending: PendingFocusedAppWindowSession?
    var lastRead: RuntimeFocusedCurrentAppWindowProjectionRead?

    init(base: any SwitcherFocusedWindowProjectionReading, diagnostics: ControlTabPressureModelDiagnostics) {
        self.base = base
        self.diagnostics = diagnostics
    }
    var generation: RuntimeReadModelGeneration { base.generation }

    func read() -> RuntimeFocusedCurrentAppWindowProjectionRead? {
        let started = LiveSwitcherModel.monotonicMilliseconds()
        if pending == nil { diagnostics.projectionStartedAt = started }
        let token = diagnostics.measurementSink?.beginComponent(.projectionRead,
            parent: pending == nil ? .inputRouting : .axCGSpaceReconciliation, workUnits: 1)
        let read = base.read()
        diagnostics.measurementSink?.endComponent(token)
        lastRead = read
        diagnostics.projectionReadMilliseconds += max(0, LiveSwitcherModel.monotonicMilliseconds() - started)
        if let read, let pending, pending.accepts(read) {
            diagnostics.finishReconciliation(outcome: .completed, waitCompletedAt: started)
        } else if pending == nil, read?.projection?.freshness.isCompleteForScope == true {
            for component in [SwitcherInteractionComponent.axCGSpaceReconciliation,
                              .onScreenCGRead, .allCGRead, .axRead, .mappingSpaceFilter] {
                diagnostics.measurementSink?.recordUnexecutedComponent(component, outcome: .cacheHit, workUnits: 1)
            }
        }
        return read
    }

    func requestRefresh() {
        if let lastRead, lastRead.projection?.freshness.isCompleteForScope != true {
            diagnostics.freshnessStartedAt = LiveSwitcherModel.monotonicMilliseconds()
            diagnostics.reconciliationSpan = diagnostics.measurementSink?.beginComponent(
                .axCGSpaceReconciliation, parent: .projectionRead, workUnits: 1)
        }
        base.requestRefresh()
    }
}

@MainActor
private struct ControlTabPressureFocusedInstallation: SwitcherFocusedWindowSessionInstalling {
    let base: any SwitcherFocusedWindowSessionInstalling
    let diagnostics: ControlTabPressureModelDiagnostics

    func applyRecency(_ payload: RuntimeCurrentAppWindowPayload) -> RuntimeCurrentAppWindowPayload {
        diagnostics.recencyStartedAt = LiveSwitcherModel.monotonicMilliseconds()
        let result = base.applyRecency(payload)
        diagnostics.recencyCompletedAt = LiveSwitcherModel.monotonicMilliseconds()
        return result
    }

    func install(payload: RuntimeCurrentAppWindowPayload, triggerDirection: CycleDirection) -> Bool {
        base.install(payload: payload, triggerDirection: triggerDirection)
    }
}
#endif
