extension RuntimeProjectionService {
    func readAppSwitcherProjection() -> RuntimeAppSwitcherProjection? {
        readModelStore.readAppSwitcherProjection()
    }

    func readHomeSummaryProjection() -> RuntimeHomeSummaryProjection? {
        readModelStore.readHomeSummaryProjection()
    }

    func readHomeAppDetailProjection(
        appID: String
    ) -> RuntimeHomeAppDetailProjection? {
        readModelStore.readHomeAppDetailProjection(appID: appID)
    }

    func readCurrentAppWindowProjection(
        appID: String
    ) -> RuntimeCurrentAppWindowProjection? {
        readModelStore.readCurrentAppWindowProjection(appID: appID)
    }

    func readFocusedCurrentAppWindowProjection()
        -> RuntimeFocusedCurrentAppWindowProjectionRead?
    {
        readModelStore.readFocusedCurrentAppWindowProjection()
    }

    func readActivationTargetProjection() -> RuntimeActivationTargetProjection? {
        readModelStore.readActivationTargetProjection()
    }

    func readSpaceTopologyProjection() -> RuntimeSpaceTopologyProjection? {
        readModelStore.readSpaceTopologyProjection()
    }

    func readCommittedSearchIndexForSearch() -> RuntimeSearchIndexRead {
        readModelStore.readCommittedSearchIndexForSearch()
    }

    func runtimeReadModelDiagnostics() -> RuntimeReadModelDiagnostics {
        readModelStore.diagnostics()
    }
}
