import FlowTabCore

@MainActor
protocol SwitcherSessionResourceManaging: AnyObject {
    func resetSession()
    func resetRuntime()
}

@MainActor
final class SwitcherSessionResources: SwitcherSessionResourceManaging {
    unowned let model: LiveSwitcherModel
    init(model: LiveSwitcherModel) { self.model = model }

    func resetSession() {
        model.invalidateRuntimeProjectionMaintenanceRequest(reason: .resetSession)
        model.cancelPendingSearchComputation()
        model.pendingSearchActivationAfterFreshnessBarrier = false
        model.session = nil
        model.resetSessionAppWindowReadinessTracking()
        model.pendingTerminateRequest = nil
        model.terminatingAppID = nil
        model.overlayStyle = .appAndWindow
        _ = model.searchCoordinator.exit()
        model.committedSearchAppsByID = [:]
        model.publishSearchStateIfNeeded()
        model.resetRuntimeState()
    }

    func resetRuntime() {
        model.invalidateSelectedAppWindowProjection(reason: .resetRuntimeState)
        model.runtimeContextsByID = [:]
        model.clearPreviewSnapshotState()
        model.autoEnterSuppressedAppID = nil
        model.pendingManualWindowLayerEntryAppID = nil
        model.titleBarStyleInferenceEnabled = false
    }
}
