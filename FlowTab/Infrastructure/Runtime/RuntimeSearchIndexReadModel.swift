import Foundation
import FlowTabCore

struct RuntimeSearchAppIndexEntry: Equatable, Sendable {
    let appID: String
    let appDisplayName: String
    let appGroupID: String
    let appLastActiveAt: TimeInterval
    let searchIndex: SearchTextMatcher.Index
}

struct RuntimeSearchWindowIndexEntry: Equatable, Sendable {
    let appID: String
    let appDisplayName: String
    let windowID: String
    let windowTitle: String
    let windowIsMinimized: Bool
    let windowLastActiveAt: TimeInterval
    let windowSearchIndex: SearchTextMatcher.Index
    let appSearchIndex: SearchTextMatcher.Index
}

struct RuntimeSearchIndexProjection: Equatable, Sendable {
    let appEntries: [RuntimeSearchAppIndexEntry]
    let windowEntries: [RuntimeSearchWindowIndexEntry]
    var freshness: RuntimeProjectionFreshness

    func removingApp(
        _ appID: String,
        freshness: RuntimeProjectionFreshness
    ) -> RuntimeSearchIndexProjection {
        RuntimeSearchIndexProjection(
            appEntries: appEntries.filter { $0.appID != appID },
            windowEntries: windowEntries.filter { $0.appID != appID },
            freshness: freshness
        )
    }

    func filteringApps(using visibilityFilter: AppVisibilityFilter) -> RuntimeSearchIndexProjection {
        guard !visibilityFilter.isEmpty else { return self }
        let filteredAppEntries = appEntries.filter { visibilityFilter.includes(appID: $0.appID) }
        let visibleAppIDs = Set(filteredAppEntries.map(\.appID))
        return RuntimeSearchIndexProjection(
            appEntries: filteredAppEntries,
            windowEntries: windowEntries.filter { visibleAppIDs.contains($0.appID) },
            freshness: freshness
        )
    }
}

enum RuntimeSearchIndexReadiness: String, Equatable, Sendable {
    case committedGenerationValidated
    case degradedStaleCommitted
    case missingCommittedIndex
}

enum RuntimeSearchIndexResultState: String, Equatable, Sendable {
    case committedGenerationResult
    case degradedStaleCommittedResult
    case missingCommittedIndex
}

struct RuntimeSearchIndexRead: Equatable, Sendable {
    let projection: RuntimeSearchIndexProjection?
    let readiness: RuntimeSearchIndexReadiness
    let resultState: RuntimeSearchIndexResultState

    init(
        projection: RuntimeSearchIndexProjection?,
        readiness: RuntimeSearchIndexReadiness
    ) {
        self.projection = projection
        self.readiness = readiness
        switch readiness {
        case .committedGenerationValidated:
            resultState = .committedGenerationResult
        case .degradedStaleCommitted:
            resultState = .degradedStaleCommittedResult
        case .missingCommittedIndex:
            resultState = .missingCommittedIndex
        }
    }

    var freshness: RuntimeProjectionFreshness? {
        projection?.freshness
    }

    var shouldRequestFreshnessBarrier: Bool {
        readiness != .committedGenerationValidated
    }

    var committedIndexCoversCurrentGeneration: Bool {
        readiness == .committedGenerationValidated
    }
}
