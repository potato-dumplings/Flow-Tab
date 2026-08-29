import Foundation
import NaturalLanguage
import FlowTabCore

extension SwitcherSearchCoordinator {
    static func isBetter(_ lhs: RankedResult, than rhs: RankedResult) -> Bool {
        SearchTextMatcher.isBetter(lhs, than: rhs)
    }

    static func topRankedResults(
        _ rankedResults: [RankedResult],
        limit: Int
    ) -> [RankedResult] {
        guard limit > 0 else { return [] }
        guard rankedResults.count > 1 else { return rankedResults }
        var rankedResults = rankedResults
        rankedResults.sort { lhs, rhs in
            isBetter(lhs, than: rhs)
        }
        if rankedResults.count > limit {
            rankedResults.removeSubrange(limit...)
        }
        return rankedResults
    }

    static func resolvedSelectedResultIndex(
        previous: Int,
        resultCount: Int,
        resetSelection: Bool
    ) -> Int {
        SearchTextMatcher.resolvedSelectedResultIndex(
            previous: previous,
            resultCount: resultCount,
            resetSelection: resetSelection
        )
    }

    static func bestScore(_ lhs: Int?, _ rhs: Int?) -> Int? {
        SearchTextMatcher.bestScore(lhs, rhs)
    }

    static func rankAppMatches(
        query: SearchKey,
        entries: [AppEntry],
        candidateIndexes: [Int],
        topResultLimit: Int
    ) -> (matchedIndexes: [Int], topRanked: [RankedResult])? {
        var matchedIndexes: [Int] = []
        matchedIndexes.reserveCapacity(candidateIndexes.count)
        var rankedResults: [RankedResult] = []
        rankedResults.reserveCapacity(candidateIndexes.count)

        for (offset, index) in candidateIndexes.enumerated() {
            if offset.isMultiple(of: 32), Task.isCancelled {
                return nil
            }
            let app = entries[index]
            guard let score = matchScore(query: query, in: app.searchIndex) else {
                continue
            }
            matchedIndexes.append(index)
            rankedResults.append(RankedResult(score: score, order: index))
        }
        guard !Task.isCancelled else { return nil }
        let topRanked = topRankedResults(
            rankedResults,
            limit: topResultLimit
        )
        guard !Task.isCancelled else { return nil }
        return (matchedIndexes, topRanked)
    }

    static func rankWindowMatches(
        query: SearchKey,
        entries: [WindowEntry],
        candidateIndexes: [Int],
        topResultLimit: Int
    ) -> (matchedIndexes: [Int], topRanked: [RankedResult])? {
        var matchedIndexes: [Int] = []
        matchedIndexes.reserveCapacity(candidateIndexes.count)
        var rankedResults: [RankedResult] = []
        rankedResults.reserveCapacity(candidateIndexes.count)
        var appScoreCache: [String: Int] = [:]
        var appScoreMisses: Set<String> = []

        for (offset, index) in candidateIndexes.enumerated() {
            if offset.isMultiple(of: 32), Task.isCancelled {
                return nil
            }
            let window = entries[index]
            let titleScore = matchScore(query: query, in: window.windowSearchIndex)
            let appScore: Int?
            if let cached = appScoreCache[window.appID] {
                appScore = cached
            } else if appScoreMisses.contains(window.appID) {
                appScore = nil
            } else if let score = matchScore(query: query, in: window.appSearchIndex) {
                let adjusted = score + 8
                appScoreCache[window.appID] = adjusted
                appScore = adjusted
            } else {
                appScoreMisses.insert(window.appID)
                appScore = nil
            }
            guard let score = bestScore(titleScore, appScore) else {
                continue
            }
            matchedIndexes.append(index)
            rankedResults.append(RankedResult(score: score, order: index))
        }
        guard !Task.isCancelled else { return nil }
        let topRanked = topRankedResults(
            rankedResults,
            limit: topResultLimit
        )
        guard !Task.isCancelled else { return nil }
        return (matchedIndexes, topRanked)
    }

    static func matchScore(query: SearchKey, in index: SearchIndex) -> Int? {
        SearchTextMatcher.matchScore(query: query, in: index)
    }
}
