import FlowTabCore

enum RuntimeApplicationMembershipProjection {
    static func appSwitcherProjection(
        _ projection: RuntimeAppSwitcherProjection,
        using evidence: RuntimeAppDirectorySnapshotEvidence
    ) -> RuntimeAppSwitcherProjection {
        let filtered = appSwitcherContent(
            apps: projection.apps,
            contextsByID: projection.contextsByID,
            using: evidence
        )
        guard filtered.didChange else { return projection }
        return RuntimeAppSwitcherProjection(
            apps: filtered.apps,
            contextsByID: filtered.contextsByID,
            freshness: incompleteFreshness(projection.freshness)
        )
    }

    static func homeSummaryProjection(
        _ projection: RuntimeHomeSummaryProjection,
        using evidence: RuntimeAppDirectorySnapshotEvidence
    ) -> RuntimeHomeSummaryProjection {
        let filtered = projection.summaries.compactMap { summary -> RuntimeHomeAppSummary? in
            guard evidence.membership.directoryAppIDs.contains(summary.appID) else { return nil }
            guard evidence.containsDirectoryProcess(appID: summary.appID, pid: summary.pid) else {
                guard let entry = evidence.entries.first(where: { $0.appID == summary.appID }) else {
                    return nil
                }
                return RuntimeHomeAppSummary(
                    appID: summary.appID,
                    displayName: summary.displayName,
                    groupID: summary.groupID,
                    lastActiveAt: summary.lastActiveAt,
                    windowCount: 0,
                    pid: entry.pid,
                    bundleIdentifier: entry.bundleIdentifier,
                    bundleURL: entry.bundleURL
                )
            }
            return summary
        }
        guard filtered != projection.summaries else { return projection }
        return RuntimeHomeSummaryProjection(
            summaries: filtered,
            freshness: incompleteFreshness(projection.freshness)
        )
    }

    static func searchIndexProjection(
        _ projection: RuntimeSearchIndexProjection,
        using membership: ApplicationDirectoryMembership,
        excludingWindowAppIDs: Set<String> = []
    ) -> RuntimeSearchIndexProjection {
        let appEntries = projection.appEntries.filter {
            membership.switcherEligibleAppIDs.contains($0.appID)
        }
        let retainedAppIDs = Set(appEntries.map(\.appID))
        let windowEntries = projection.windowEntries.filter {
            retainedAppIDs.contains($0.appID)
                && !excludingWindowAppIDs.contains($0.appID)
        }
        guard appEntries != projection.appEntries || windowEntries != projection.windowEntries else {
            return projection
        }
        return RuntimeSearchIndexProjection(
            appEntries: appEntries,
            windowEntries: windowEntries,
            freshness: incompleteFreshness(projection.freshness)
        )
    }

    static func appSwitcherPayload(
        _ payload: RuntimeAppSwitcherProjectionPayload,
        using evidence: RuntimeAppDirectorySnapshotEvidence
    ) -> RuntimeAppSwitcherProjectionPayload {
        let filtered = appSwitcherContent(
            apps: payload.apps,
            contextsByID: payload.contextsByID,
            using: evidence
        )
        let homeSummaries = payload.homeSummaries.filter {
            evidence.membership.directoryAppIDs.contains($0.appID)
        }
        guard filtered.didChange || homeSummaries != payload.homeSummaries else { return payload }
        return RuntimeAppSwitcherProjectionPayload(
            apps: filtered.apps,
            contextsByID: filtered.contextsByID,
            homeSummaries: homeSummaries,
            hasCompleteWindowCoverage: payload.hasCompleteWindowCoverage
        )
    }

    static func searchIndexPayload(
        _ payload: RuntimeSearchIndexPayload,
        using membership: ApplicationDirectoryMembership
    ) -> RuntimeSearchIndexPayload {
        let appEntries = payload.appEntries.filter {
            membership.switcherEligibleAppIDs.contains($0.appID)
        }
        let retainedAppIDs = Set(appEntries.map(\.appID))
        let windowEntries = payload.windowEntries.filter {
            retainedAppIDs.contains($0.appID)
        }
        guard appEntries != payload.appEntries || windowEntries != payload.windowEntries else {
            return payload
        }
        return RuntimeSearchIndexPayload(
            appEntries: appEntries,
            windowEntries: windowEntries,
            hasCompleteWindowCoverage: payload.hasCompleteWindowCoverage
        )
    }

    private static func appSwitcherContent(
        apps: [AppSwitchCandidate],
        contextsByID: [String: RuntimeAppContext],
        using evidence: RuntimeAppDirectorySnapshotEvidence
    ) -> (
        apps: [AppSwitchCandidate],
        contextsByID: [String: RuntimeAppContext],
        didChange: Bool
    ) {
        let eligibleAppIDs = evidence.membership.switcherEligibleAppIDs
        var didChange = false
        var retainedContexts: [String: RuntimeAppContext] = [:]
        let retainedApps = apps.compactMap { app -> AppSwitchCandidate? in
            guard eligibleAppIDs.contains(app.id) else {
                didChange = true
                return nil
            }
            guard let context = contextsByID[app.id] else { return app }
            let contextPID = context.ownerPID
            guard evidence.containsSwitcherEligibleProcess(appID: app.id, pid: contextPID) else {
                didChange = true
                var app = app
                app.windows = []
                return app
            }
            retainedContexts[app.id] = context
            return app
        }
        if retainedContexts.count != contextsByID.count {
            didChange = true
        }
        return (retainedApps, retainedContexts, didChange)
    }

    private static func incompleteFreshness(
        _ freshness: RuntimeProjectionFreshness
    ) -> RuntimeProjectionFreshness {
        RuntimeProjectionFreshness(
            generatedAt: freshness.generatedAt,
            sourceGeneration: freshness.sourceGeneration,
            dirtyAppIDs: freshness.dirtyAppIDs,
            dirtyPIDs: freshness.dirtyPIDs,
            dirtyCGWindowIDs: freshness.dirtyCGWindowIDs,
            spaceTopologySignatureSummary: freshness.spaceTopologySignatureSummary,
            pendingRepairScopes: freshness.pendingRepairScopes,
            isCompleteForScope: false
        )
    }
}
