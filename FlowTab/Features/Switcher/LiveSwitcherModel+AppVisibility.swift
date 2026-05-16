import Foundation
import FlowTabCore

extension LiveSwitcherModel {
    func snapshotWithHiddenAppsFiltered(_ snapshot: RuntimeSnapshot) -> RuntimeSnapshot {
        let visibilityFilter = AppVisibilityPreferencesStore.visibilityFilter()
        guard !visibilityFilter.isEmpty else { return snapshot }

        let filteredApps = visibilityFilter.filteredApps(snapshot.apps)
        guard filteredApps.count != snapshot.apps.count else { return snapshot }

        let visibleAppIDs = Set(filteredApps.map(\.id))
        let filteredContexts = snapshot.contextsByID.filter { visibleAppIDs.contains($0.key) }
        RuntimeLog.debug(
            .snapshot,
            "hiddenAppFilter hidden=\(visibilityFilter.hiddenAppIDs.count) before=\(snapshot.apps.count) after=\(filteredApps.count)"
        )
        return RuntimeSnapshot(
            apps: filteredApps,
            contextsByID: filteredContexts
        )
    }
}
