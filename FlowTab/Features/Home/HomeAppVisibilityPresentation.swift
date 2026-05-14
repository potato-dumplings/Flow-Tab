import FlowTabCore

struct HomeAppVisibilityPresentation {
    private let visibilityFilter: AppVisibilityFilter

    init(hiddenAppIDs: Set<String>) {
        visibilityFilter = AppVisibilityFilter(hiddenAppIDs: hiddenAppIDs)
    }

    func isHidden(appID: String) -> Bool {
        visibilityFilter.isHidden(appID: appID)
    }

    func orderedAppSummaries(_ summaries: [RuntimeHomeAppSummary]) -> [RuntimeHomeAppSummary] {
        summaries.enumerated()
            .sorted { lhs, rhs in
                let lhsRank = visibilityFilter.visibilitySortRank(appID: lhs.element.appID)
                let rhsRank = visibilityFilter.visibilitySortRank(appID: rhs.element.appID)
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
