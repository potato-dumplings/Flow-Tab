import Foundation
import FlowTabCore

let homeRuntimeProjectionService = sharedRuntimeProjectionService

enum HomeRuntimeProjectionReader {
    static func appSummaries(from service: any RuntimeProjectionServing) -> [RuntimeHomeAppSummary]? {
        service.readHomeSummaryProjection()?.summaries
    }

    static func initialAppSummaries(from service: any RuntimeProjectionServing) -> [RuntimeHomeAppSummary]? {
        service.readHomeSummaryProjection()?.summaries
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
        if let projection = service.readAppSwitcherProjection(),
           projection.contextsByID[appID]?.runningApp.processIdentifier == pid {
            return !projection.freshness.isCompleteForScope
        }
        return false
    }
}

enum HomeRuntimeRefreshReader {
    static func appSummaries(
        from service: any RuntimeProjectionServing,
        current summaries: [RuntimeHomeAppSummary]
    ) -> [RuntimeHomeAppSummary] {
        guard let projectionSummaries = HomeRuntimeProjectionReader.appSummaries(from: service) else {
            service.requestAppSwitcherProjectionMaintenance(reason: .homeProjectionMissing)
            return summaries
        }
        return projectionSummaries
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

enum HomeInitialAppSummaryReader {
    static func appSummaries(from service: any RuntimeProjectionServing) -> [RuntimeHomeAppSummary] {
        HomeRuntimeProjectionReader.initialAppSummaries(from: service) ?? []
    }
}
