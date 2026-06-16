import Foundation
import FlowTabCore

let homeRuntimeSnapshotService = sharedRuntimeSnapshotService

typealias HomeRuntimeSnapshotService = RuntimeSnapshotService

enum HomeRuntimeProjectionReader {
    static func appSummaries(from service: any RuntimeSnapshotServing) -> [RuntimeHomeAppSummary]? {
        service.readHomeSummaryProjection()?.summaries
    }

    static func lightweightAppSummaries(from service: any RuntimeSnapshotServing) -> [RuntimeHomeAppSummary]? {
        if let homeProjection = service.readHomeSummaryProjection() {
            return homeProjection.summaries
        }
        guard let appProjection = service.readAppSwitcherProjection() else { return nil }
        return appProjection.apps.map { app in
            RuntimeHomeAppSummary(
                appID: app.id,
                displayName: app.displayName,
                groupID: app.groupID,
                lastActiveAt: app.lastActiveAt,
                windowCount: app.windows.count,
                pid: appProjection.contextsByID[app.id]?.runningApp.processIdentifier ?? 0
            )
        }
    }

    static func appSummary(
        for appID: String,
        from service: any RuntimeSnapshotServing
    ) -> RuntimeHomeAppSummary? {
        service.readHomeSummaryProjection()?.summary(for: appID)
    }

    static func appSnapshot(
        for appID: String,
        from service: any RuntimeSnapshotServing
    ) -> RuntimeHomeAppSnapshot? {
        service.readCurrentAppWindowProjection(appID: appID)?.snapshot
    }
}

enum HomeInitialAppSummaryReader {
    static func lightweightAppSummaries(from service: any RuntimeSnapshotServing) -> [RuntimeHomeAppSummary] {
        HomeRuntimeProjectionReader.lightweightAppSummaries(from: service) ?? []
    }
}
