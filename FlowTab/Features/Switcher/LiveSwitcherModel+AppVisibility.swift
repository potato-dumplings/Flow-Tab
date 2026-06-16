import Foundation
import FlowTabCore

extension LiveSwitcherModel {
    func appSwitcherPayloadWithHiddenAppsFiltered(
        _ payload: AppSwitcherProjectionSessionPayload
    ) -> AppSwitcherProjectionSessionPayload {
        let visibilityFilter = AppVisibilityPreferencesStore.visibilityFilter()
        guard !visibilityFilter.isEmpty else { return payload }

        let filteredApps = visibilityFilter.filteredApps(payload.apps)
        guard filteredApps.count != payload.apps.count else { return payload }

        let visibleAppIDs = Set(filteredApps.map(\.id))
        let filteredContexts = payload.contextsByID.filter { visibleAppIDs.contains($0.key) }
        RuntimeLog.debug(
            .snapshot,
            "hiddenAppFilter hidden=\(visibilityFilter.hiddenAppIDs.count) before=\(payload.apps.count) after=\(filteredApps.count)"
        )
        return AppSwitcherProjectionSessionPayload(
            apps: filteredApps,
            contextsByID: filteredContexts
        )
    }
}
