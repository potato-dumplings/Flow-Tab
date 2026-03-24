public enum Grouping {
    public static func buildGroups(from apps: [AppSwitchCandidate]) -> [AppGroup] {
        var orderedGroupIDs: [String] = []
        var groupedApps: [String: [AppSwitchCandidate]] = [:]

        for app in apps {
            let normalizedGroupID = app.groupID.isEmpty ? "app:\(app.id)" : app.groupID
            if groupedApps[normalizedGroupID] == nil {
                orderedGroupIDs.append(normalizedGroupID)
                groupedApps[normalizedGroupID] = []
            }
            groupedApps[normalizedGroupID, default: []].append(app)
        }

        return orderedGroupIDs.compactMap { groupID in
            guard let appsInGroup = groupedApps[groupID] else { return nil }
            return AppGroup(id: groupID, apps: appsInGroup)
        }
    }

    public static func groupIndex(
        containing appID: String,
        groups: [AppGroup]
    ) -> Int {
        for (index, group) in groups.enumerated() {
            if group.apps.contains(where: { $0.id == appID }) {
                return index
            }
        }
        return 0
    }
}
