import Foundation
import FlowTabCore

let homeRuntimeProjectionService = sharedRuntimeProjectionService

struct HomeProjectionEvidenceState: Equatable {
    let isProjectionBacked: Bool
    let sourceGeneration: RuntimeReadModelGeneration?
    let isCompleteForScope: Bool

    init(_ read: HomeAppSummaryProjectionRead) {
        isProjectionBacked = read.isProjectionBacked
        sourceGeneration = read.freshness?.sourceGeneration
        isCompleteForScope =
            read.freshness?.isCompleteForScope == true
    }

    init(_ projection: RuntimeHomeAppDetailProjection?) {
        isProjectionBacked = projection != nil
        sourceGeneration = projection?.freshness.sourceGeneration
        isCompleteForScope =
            projection?.freshness.isCompleteForScope == true
    }
}

enum HomeProjectionEvidenceTransition: String, Equatable {
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

enum HomeProjectionEvidenceTransitionResolver {
    static func transition(
        from previous: HomeProjectionEvidenceState?,
        to current: HomeProjectionEvidenceState
    ) -> HomeProjectionEvidenceTransition {
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

struct HomeSelectedAppRefreshExpectation: Equatable {
    let processIdentifier: pid_t
    let windowCount: Int
}

enum HomeSelectedAppSummaryRefreshDecision: Equatable {
    case noRequest
    case clearOutstanding
    case request(HomeSelectedAppRefreshExpectation)
}

enum HomeSelectedAppSummaryRefreshPolicy {
    static func decision(
        summaryProcessIdentifier: pid_t,
        summaryWindowCount: Int,
        cachedWindowCount: Int?,
        outstandingExpectation: HomeSelectedAppRefreshExpectation?
    ) -> HomeSelectedAppSummaryRefreshDecision {
        guard cachedWindowCount != summaryWindowCount else {
            return .clearOutstanding
        }
        let expectation = HomeSelectedAppRefreshExpectation(
            processIdentifier: summaryProcessIdentifier,
            windowCount: summaryWindowCount
        )
        guard outstandingExpectation != expectation else {
            return .noRequest
        }
        return .request(expectation)
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
