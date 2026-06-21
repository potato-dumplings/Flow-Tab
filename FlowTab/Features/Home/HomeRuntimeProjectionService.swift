import Foundation
import FlowTabCore

let homeRuntimeProjectionService = sharedRuntimeProjectionService

enum HomeRuntimeProjectionReader {
    static func appSummaries(from service: any RuntimeProjectionServing) -> [RuntimeHomeAppSummary]? {
        if let homeProjection = service.readHomeSummaryProjection() {
            return homeProjection.summaries
        }
        guard let appProjection = service.readAppSwitcherProjection() else { return nil }
        return appProjection.apps.map { app in
            homeSummary(
                for: app,
                context: appProjection.contextsByID[app.id]
            )
        }
    }

    static func initialAppSummaries(from service: any RuntimeProjectionServing) -> [RuntimeHomeAppSummary]? {
        if let homeProjection = service.readHomeSummaryProjection() {
            return homeProjection.summaries
        }
        guard let appProjection = service.readAppSwitcherProjection() else { return nil }
        return appProjection.apps.map { app in
            homeSummary(
                for: app,
                context: appProjection.contextsByID[app.id]
            )
        }
    }

    static func appSummary(
        for appID: String,
        from service: any RuntimeProjectionServing
    ) -> RuntimeHomeAppSummary? {
        if let summary = service.readHomeSummaryProjection()?.summary(for: appID) {
            return summary
        }
        guard
            let appProjection = service.readAppSwitcherProjection(),
            let app = appProjection.apps.first(where: { $0.id == appID })
        else {
            return nil
        }
        return homeSummary(
            for: app,
            context: appProjection.contextsByID[appID]
        )
    }

    static func appDetailProjection(
        for appID: String,
        from service: any RuntimeProjectionServing
    ) -> RuntimeHomeAppDetailProjection? {
        if let projection = service.readCurrentAppWindowProjection(appID: appID) {
            return RuntimeHomeAppDetailProjection(
                currentAppWindowPayload: projection.currentAppWindowPayload
            )
        }
        guard
            let appProjection = service.readAppSwitcherProjection(),
            let app = appProjection.apps.first(where: { $0.id == appID }),
            let context = appProjection.contextsByID[appID]
        else {
            return nil
        }
        return RuntimeHomeAppDetailProjection(
            summary: homeSummary(for: app, context: context),
            candidate: app,
            context: context
        )
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

    private static func homeSummary(
        for app: AppSwitchCandidate,
        context: RuntimeAppContext?
    ) -> RuntimeHomeAppSummary {
        RuntimeHomeAppSummary(
            appID: app.id,
            displayName: app.displayName,
            groupID: app.groupID,
            lastActiveAt: app.lastActiveAt,
            windowCount: app.windows.count,
            pid: context?.runningApp.processIdentifier ?? 0
        )
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
