import Foundation
import FlowTabCore

let homeRuntimeProjectionService = sharedRuntimeProjectionService

struct HomeAppSummaryProjectionRead: Equatable {
    let summaries: [RuntimeHomeAppSummary]
    let freshness: RuntimeProjectionFreshness?
    let isProjectionBacked: Bool

    init(
        summaries: [RuntimeHomeAppSummary],
        freshness: RuntimeProjectionFreshness?,
        isProjectionBacked: Bool
    ) {
        self.summaries = summaries
        self.freshness = freshness
        self.isProjectionBacked = isProjectionBacked
    }

    init(projection: RuntimeHomeSummaryProjection) {
        self.init(
            summaries: projection.summaries,
            freshness: projection.freshness,
            isProjectionBacked: true
        )
    }
}

enum HomeRuntimeProjectionReader {
    static func appSummaryProjection(from service: any RuntimeProjectionServing) -> HomeAppSummaryProjectionRead? {
        service.readHomeSummaryProjection().map(HomeAppSummaryProjectionRead.init(projection:))
    }

    static func appSummaries(from service: any RuntimeProjectionServing) -> [RuntimeHomeAppSummary]? {
        appSummaryProjection(from: service)?.summaries
    }

    static func initialAppSummaryProjection(from service: any RuntimeProjectionServing) -> HomeAppSummaryProjectionRead? {
        service.readHomeSummaryProjection().map(HomeAppSummaryProjectionRead.init(projection:))
    }

    static func initialAppSummaries(from service: any RuntimeProjectionServing) -> [RuntimeHomeAppSummary]? {
        initialAppSummaryProjection(from: service)?.summaries
    }

    static func appSummary(
        for appID: String,
        from service: any RuntimeProjectionServing
    ) -> RuntimeHomeAppSummary? {
        service.readHomeSummaryProjection()?.summary(for: appID)
    }

    static func appDetailProjection(
        for appID: String,
        from service: any RuntimeProjectionServing
    ) -> RuntimeHomeAppDetailProjection? {
        service.readHomeAppDetailProjection(appID: appID)
    }

    static func shouldWaitForNoSwitchableWindowProjection(
        appID: String,
        pid: pid_t,
        from service: any RuntimeProjectionServing
    ) -> Bool {
        guard pid > 0 else { return false }
        if let projection = service.readCurrentAppWindowProjection(appID: appID),
           projection.currentAppWindowPayload.summary.pid == pid
            || projection.currentAppWindowPayload.context.runningApp.processIdentifier == pid
        {
            return !projection.freshness.isCompleteForScope
        }
        if let projection = service.readHomeSummaryProjection(),
           projection.summary(for: appID)?.pid == pid {
            return !projection.freshness.isCompleteForScope
        }
        return false
    }
}

enum HomeRuntimeRefreshReader {
    static func appSummaryProjection(
        from service: any RuntimeProjectionServing,
        current summaries: [RuntimeHomeAppSummary]
    ) -> HomeAppSummaryProjectionRead {
        guard let projectionRead = HomeRuntimeProjectionReader.appSummaryProjection(from: service) else {
            service.requestAppSwitcherProjectionMaintenance(reason: .homeProjectionMissing)
            return HomeAppSummaryProjectionRead(
                summaries: summaries,
                freshness: nil,
                isProjectionBacked: false
            )
        }
        return projectionRead
    }

    static func appSummaries(
        from service: any RuntimeProjectionServing,
        current summaries: [RuntimeHomeAppSummary]
    ) -> [RuntimeHomeAppSummary] {
        appSummaryProjection(from: service, current: summaries).summaries
    }

    static func appSummary(
        for appID: String,
        from service: any RuntimeProjectionServing,
        current summaries: [RuntimeHomeAppSummary]
    ) -> RuntimeHomeAppSummary? {
        if let summary = HomeRuntimeProjectionReader.appSummary(for: appID, from: service) {
            return summary
        }
        let currentSummary = summaries.first { $0.appID == appID }
        signalMissingProjection(appID: appID, summary: currentSummary, service: service)
        return currentSummary
    }

    static func appDetailProjection(
        for appID: String,
        from service: any RuntimeProjectionServing,
        current detailProjection: RuntimeHomeAppDetailProjection?,
        currentSummary: RuntimeHomeAppSummary?
    ) -> RuntimeHomeAppDetailProjection? {
        if let projection = HomeRuntimeProjectionReader.appDetailProjection(for: appID, from: service) {
            return projection
        }
        signalMissingProjection(
            appID: appID,
            summary: detailProjection?.summary ?? currentSummary,
            service: service
        )
        return detailProjection
    }

    private static func signalMissingProjection(
        appID: String,
        summary: RuntimeHomeAppSummary?,
        service: any RuntimeProjectionServing
    ) {
        guard let pid = summary?.pid, pid > 0 else {
            service.requestAppSwitcherProjectionMaintenance(reason: .homeProjectionMissing)
            return
        }
        service.signalAppWindowsChanged(appID: appID, pid: pid)
    }
}

enum HomeRuntimeProjectionRefreshPolicy {
    static func shouldRequestAppSummaryRefresh(
        appSummaryCount: Int,
        loadingWindowCountAppCount: Int
    ) -> Bool {
        appSummaryCount > 0 && loadingWindowCountAppCount == 0
    }
}

enum HomeInitialAppSummaryReader {
    static func appSummaryProjection(from service: any RuntimeProjectionServing) -> HomeAppSummaryProjectionRead {
        HomeRuntimeProjectionReader.initialAppSummaryProjection(from: service)
            ?? HomeAppSummaryProjectionRead(
                summaries: [],
                freshness: nil,
                isProjectionBacked: false
            )
    }

    static func appSummaries(from service: any RuntimeProjectionServing) -> [RuntimeHomeAppSummary] {
        appSummaryProjection(from: service).summaries
    }
}
