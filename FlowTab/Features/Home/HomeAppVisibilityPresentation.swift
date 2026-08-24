import Foundation
import FlowTabCore

struct HomeAppRowPresentation: Identifiable, Equatable {
    let appID: String
    let displayName: String
    let bundleIdentifier: String?
    let bundleURL: URL?
    let windowCount: Int
    let isHidden: Bool
    let runtimeSummary: RuntimeHomeAppSummary?

    var id: String { appID }

    var hasRuntimeProjection: Bool {
        runtimeSummary != nil
    }
}

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

    func appRows(
        runtimeSummaries: [RuntimeHomeAppSummary],
        installedApps: [InstalledAppRecord]
    ) -> [HomeAppRowPresentation] {
        var seenAppIDs: Set<String> = []
        var rows: [HomeAppRowPresentation] = []

        for summary in runtimeSummaries {
            guard let normalizedAppID = AppVisibilityFilter.normalizedAppID(summary.appID),
                  seenAppIDs.insert(normalizedAppID).inserted
            else {
                continue
            }
            rows.append(
                HomeAppRowPresentation(
                    appID: normalizedAppID,
                    displayName: summary.displayName,
                    bundleIdentifier: summary.bundleIdentifier,
                    bundleURL: summary.bundleURL,
                    windowCount: summary.windowCount,
                    isHidden: visibilityFilter.isHidden(appID: normalizedAppID),
                    runtimeSummary: summary
                )
            )
        }

        for app in installedApps {
            guard app.isRunning,
                  app.visibilityCapability.isConfigurable,
                  visibilityFilter.isHidden(appID: app.id),
                  let normalizedAppID = AppVisibilityFilter.normalizedAppID(app.id),
                  seenAppIDs.insert(normalizedAppID).inserted
            else {
                continue
            }
            rows.append(
                HomeAppRowPresentation(
                    appID: normalizedAppID,
                    displayName: app.displayName,
                    bundleIdentifier: app.bundleIdentifier,
                    bundleURL: app.path.map {
                        URL(fileURLWithPath: $0).standardizedFileURL
                    },
                    windowCount: 0,
                    isHidden: true,
                    runtimeSummary: nil
                )
            )
        }

        return rows.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.isHidden != rhs.element.isHidden {
                    return !lhs.element.isHidden
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
