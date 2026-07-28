import Foundation
import FlowTabCore

let homeRuntimeProjectionService = sharedRuntimeProjectionService

struct HomeAppSummaryProjectionState: Equatable {
    let isProjectionBacked: Bool
    let sourceGeneration: RuntimeReadModelGeneration?
    let isCompleteForScope: Bool

    init(_ read: HomeAppSummaryProjectionRead) {
        isProjectionBacked = read.isProjectionBacked
        sourceGeneration = read.freshness?.sourceGeneration
        isCompleteForScope =
            read.freshness?.isCompleteForScope == true
    }
}

enum HomeAppSummaryProjectionTransition: String, Equatable {
    case baseline
    case projectionBecameAvailable
    case sourceGenerationAdvanced
    case completenessSatisfied
    case unchanged
    case regressed

    var shouldApply: Bool {
        switch self {
        case .baseline,
             .projectionBecameAvailable,
             .sourceGenerationAdvanced,
             .completenessSatisfied:
            true
        case .unchanged, .regressed:
            false
        }
    }
}

enum HomeAppSummaryProjectionTransitionResolver {
    static func transition(
        from previous: HomeAppSummaryProjectionState?,
        to current: HomeAppSummaryProjectionState
    ) -> HomeAppSummaryProjectionTransition {
        guard let previous else { return .baseline }
        guard previous.isProjectionBacked else {
            return current.isProjectionBacked
                ? .projectionBecameAvailable
                : .unchanged
        }
        guard current.isProjectionBacked else { return .regressed }

        switch (previous.sourceGeneration, current.sourceGeneration) {
        case let (previousGeneration?, currentGeneration?):
            if currentGeneration.isStrictlyLater(than: previousGeneration) {
                return .sourceGenerationAdvanced
            }
            if currentGeneration == previousGeneration {
                if !previous.isCompleteForScope,
                   current.isCompleteForScope {
                    return .completenessSatisfied
                }
                return previous.isCompleteForScope
                    && !current.isCompleteForScope
                    ? .regressed
                    : .unchanged
            }
            return .regressed
        case (nil, .some):
            return .sourceGenerationAdvanced
        case (.some, nil):
            return .regressed
        case (nil, nil):
            if !previous.isCompleteForScope,
               current.isCompleteForScope {
                return .completenessSatisfied
            }
            return previous.isCompleteForScope
                && !current.isCompleteForScope
                ? .regressed
                : .unchanged
        }
    }
}

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
            if projection.candidate.windows.isEmpty,
               !projection.freshness.isCompleteForScope {
                signalMissingProjection(
                    appID: appID,
                    summary: projection.summary,
                    service: service
                )
            }
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

extension RuntimeReadModelGeneration {
    func isStrictlyLater(
        than other: RuntimeReadModelGeneration
    ) -> Bool {
        appLifecycle >= other.appLifecycle
            && cg >= other.cg
            && space >= other.space
            && axDirty >= other.axDirty
            && projection >= other.projection
            && self != other
    }
}

enum HomeAppSummaryProjectionReadback {
    static func read(
        from service: any RuntimeProjectionServing
    ) -> HomeAppSummaryProjectionRead {
        HomeRuntimeProjectionReader.appSummaryProjection(from: service)
            ?? HomeAppSummaryProjectionRead(
                summaries: [],
                freshness: nil,
                isProjectionBacked: false
            )
    }
}

enum HomeInitialAppSummaryUpdatePolicy {
    static func shouldCommitSingleAppSummary(
        appID: String,
        selectedAppID: String?,
        loadingWindowCountAppIDs: Set<String>
    ) -> Bool {
        loadingWindowCountAppIDs.isEmpty || appID == selectedAppID
    }
}
