import Foundation
import NaturalLanguage
import FlowTabCore

extension SwitcherSearchCoordinator {
    static func isBetter(_ lhs: RankedResult, than rhs: RankedResult) -> Bool {
        SearchTextMatcher.isBetter(lhs, than: rhs)
    }

    static func insertTopRankedResult(
        _ result: RankedResult,
        into topRanked: inout [RankedResult],
        limit: Int
    ) {
        SearchTextMatcher.insertTopRankedResult(result, into: &topRanked, limit: limit)
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
    ) -> (matchedIndexes: [Int], topRanked: [RankedResult]) {
        var matchedIndexes: [Int] = []
        matchedIndexes.reserveCapacity(candidateIndexes.count)
        var topRanked: [RankedResult] = []
        topRanked.reserveCapacity(min(topResultLimit, candidateIndexes.count))

        for index in candidateIndexes {
            let app = entries[index]
            guard let score = matchScore(query: query, in: app.searchIndex) else {
                continue
            }
            matchedIndexes.append(index)
            let ranked = RankedResult(score: score, order: index)
            insertTopRankedResult(ranked, into: &topRanked, limit: topResultLimit)
        }
        return (matchedIndexes, topRanked)
    }

    static func rankWindowMatches(
        query: SearchKey,
        entries: [WindowEntry],
        candidateIndexes: [Int],
        topResultLimit: Int
    ) -> (matchedIndexes: [Int], topRanked: [RankedResult]) {
        var matchedIndexes: [Int] = []
        matchedIndexes.reserveCapacity(candidateIndexes.count)
        var topRanked: [RankedResult] = []
        topRanked.reserveCapacity(min(topResultLimit, candidateIndexes.count))
        var appScoreCache: [String: Int] = [:]
        var appScoreMisses: Set<String> = []

        for index in candidateIndexes {
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
            let ranked = RankedResult(score: score, order: index)
            insertTopRankedResult(ranked, into: &topRanked, limit: topResultLimit)
        }
        return (matchedIndexes, topRanked)
    }

    static func matchScore(query: SearchKey, in index: SearchIndex) -> Int? {
        SearchTextMatcher.matchScore(query: query, in: index)
    }
}
