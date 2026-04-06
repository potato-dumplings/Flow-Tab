import Foundation
import NaturalLanguage
import FlowTabCore

extension SwitcherSearchCoordinator {
    static func isBetter(_ lhs: RankedResult, than rhs: RankedResult) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score < rhs.score
        }
        return lhs.order < rhs.order
    }

    static func insertTopRankedResult(
        _ result: RankedResult,
        into topRanked: inout [RankedResult],
        limit: Int
    ) {
        guard limit > 0 else { return }

        var lower = 0
        var upper = topRanked.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if isBetter(topRanked[middle], than: result) {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        topRanked.insert(result, at: lower)
        if topRanked.count > limit {
            topRanked.removeLast()
        }
    }

    static func resolvedSelectedResultIndex(
        previous: Int,
        resultCount: Int,
        resetSelection: Bool
    ) -> Int {
        if resultCount == 0 {
            return 0
        }
        if resetSelection {
            return 0
        }
        if previous >= resultCount {
            return resultCount - 1
        }
        if previous < 0 {
            return 0
        }
        return previous
    }

    static func bestScore(_ lhs: Int?, _ rhs: Int?) -> Int? {
        switch (lhs, rhs) {
        case let (left?, right?):
            return min(left, right)
        case let (left?, nil):
            return left
        case let (nil, right?):
            return right
        case (nil, nil):
            return nil
        }
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
        guard !query.normalized.isEmpty else { return 0 }
        var best: Int?
        consider(&best, matchPositionScore(query.normalized, in: index.normalized, prefixBase: 0, containsBase: 20))
        consider(&best, matchPositionScore(query.compact, in: index.compact, prefixBase: 4, containsBase: 30))
        consider(&best, matchPositionScore(query.normalized, in: index.latinNormalized, prefixBase: 8, containsBase: 34))
        consider(&best, matchPositionScore(query.compact, in: index.latinCompact, prefixBase: 12, containsBase: 38))
        consider(&best, matchTokenPrefixScore(query.terms, in: index.terms, base: 14))
        consider(&best, matchTokenPrefixScore(query.terms, in: index.latinTerms, base: 18))
        consider(&best, matchInitialsPrefixOrContainsScore(query.compact, in: index.initials, base: 10))
        consider(&best, matchInitialsPrefixOrContainsScore(query.compact, in: index.uppercaseAbbreviation, base: 10))
        consider(&best, matchIdentifierScore(query.compact, in: index.identifierTerms, base: 16))
        return best
    }

    static func consider(_ best: inout Int?, _ candidate: Int?) {
        guard let candidate else { return }
        if let currentBest = best {
            if candidate < currentBest {
                best = candidate
            }
        } else {
            best = candidate
        }
    }

    static func matchIdentifierScore(
        _ query: String,
        in identifierTerms: [String],
        base: Int
    ) -> Int? {
        guard !query.isEmpty else { return nil }
        guard !identifierTerms.isEmpty else { return nil }

        var best: Int?
        for term in identifierTerms {
            let candidate: Int?
            if term.hasPrefix(query) {
                candidate = base + max(0, term.count - query.count)
            } else if let range = term.range(of: query) {
                let distance = term.distance(from: term.startIndex, to: range.lowerBound)
                candidate = base + 6 + distance
            } else {
                candidate = nil
            }

            guard let candidate else { continue }
            if let currentBest = best {
                if candidate < currentBest {
                    best = candidate
                }
            } else {
                best = candidate
            }
        }
        return best
    }

    static func matchPositionScore(
        _ query: String,
        in source: String,
        prefixBase: Int,
        containsBase: Int
    ) -> Int? {
        guard !query.isEmpty else { return nil }
        guard !source.isEmpty else { return nil }
        if source.hasPrefix(query) {
            return prefixBase + max(0, source.count - query.count)
        }
        guard let range = source.range(of: query) else { return nil }
        let distance = source.distance(from: source.startIndex, to: range.lowerBound)
        return containsBase + distance
    }

    static func matchTokenPrefixScore(
        _ queryTerms: [String],
        in sourceTerms: [String],
        base: Int
    ) -> Int? {
        guard !queryTerms.isEmpty else { return nil }
        guard !sourceTerms.isEmpty else { return nil }

        var totalPenalty = 0
        for queryTerm in queryTerms {
            guard !queryTerm.isEmpty else { continue }
            var bestPenalty: Int?
            for sourceTerm in sourceTerms where sourceTerm.hasPrefix(queryTerm) {
                let penalty = max(0, sourceTerm.count - queryTerm.count)
                if let currentBest = bestPenalty {
                    if penalty < currentBest {
                        bestPenalty = penalty
                    }
                } else {
                    bestPenalty = penalty
                }
            }
            guard let bestPenalty else { return nil }
            totalPenalty += bestPenalty
        }
        return base + totalPenalty
    }

    static func matchInitialsPrefixOrContainsScore(
        _ query: String,
        in initials: String,
        base: Int
    ) -> Int? {
        guard !query.isEmpty else { return nil }
        guard !initials.isEmpty else { return nil }

        if initials.hasPrefix(query) {
            return base + max(0, initials.count - query.count)
        }

        if let range = initials.range(of: query) {
            let distance = initials.distance(from: initials.startIndex, to: range.lowerBound)
            return base + 10 + distance
        }
        return nil
    }
}
