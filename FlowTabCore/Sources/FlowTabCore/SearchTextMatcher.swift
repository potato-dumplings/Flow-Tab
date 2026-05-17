import Foundation
import NaturalLanguage

public enum SearchTextMatcher {
    private static let orderedSubsequenceMinimumQueryLength = 3
    private static let orderedSubsequenceMaximumGapPenalty = 3
    private static let orderedPairMaximumSkippedCharacters = 2

    public struct Key: Equatable, Sendable {
        public let normalized: String
        public let compact: String
        public let terms: [String]

        public init(normalized: String, compact: String, terms: [String]) {
            self.normalized = normalized
            self.compact = compact
            self.terms = terms
        }
    }

    public struct Index: Equatable, Sendable {
        public let normalized: String
        public let compact: String
        public let terms: [String]
        public let latinNormalized: String
        public let latinCompact: String
        public let latinTerms: [String]
        public let initials: String
        public let uppercaseAbbreviation: String
        public let identifierTerms: [String]
        public let coarseTerms: [String]
        public let coarseBigrams: [String]

        public init(
            normalized: String,
            compact: String,
            terms: [String],
            latinNormalized: String,
            latinCompact: String,
            latinTerms: [String],
            initials: String,
            uppercaseAbbreviation: String,
            identifierTerms: [String],
            coarseTerms: [String],
            coarseBigrams: [String]
        ) {
            self.normalized = normalized
            self.compact = compact
            self.terms = terms
            self.latinNormalized = latinNormalized
            self.latinCompact = latinCompact
            self.latinTerms = latinTerms
            self.initials = initials
            self.uppercaseAbbreviation = uppercaseAbbreviation
            self.identifierTerms = identifierTerms
            self.coarseTerms = coarseTerms
            self.coarseBigrams = coarseBigrams
        }

        public func mergingCoarseTerms(with other: Index) -> Index {
            let mergedTerms = Set(coarseTerms).union(other.coarseTerms)
            let mergedBigrams = Set(coarseBigrams).union(other.coarseBigrams)
            return Index(
                normalized: normalized,
                compact: compact,
                terms: terms,
                latinNormalized: latinNormalized,
                latinCompact: latinCompact,
                latinTerms: latinTerms,
                initials: initials,
                uppercaseAbbreviation: uppercaseAbbreviation,
                identifierTerms: identifierTerms,
                coarseTerms: Array(mergedTerms),
                coarseBigrams: Array(mergedBigrams)
            )
        }
    }

    public struct RankedResult: Equatable, Sendable {
        public let score: Int
        public let order: Int

        public init(score: Int, order: Int) {
            self.score = score
            self.order = order
        }
    }

    private static let ignoredIdentifierTokens: Set<String> = ["com", "org", "net", "io", "app", "www"]

    public static func buildKey(from value: String) -> Key {
        let normalized = normalizedToken(value)
        return Key(
            normalized: normalized,
            compact: compactToken(normalized),
            terms: searchTerms(from: value)
        )
    }

    public static func buildIndex(for value: String, identifier: String? = nil) -> Index {
        let normalized = normalizedToken(value)
        let compact = compactToken(normalized)
        let terms = searchTerms(from: value)

        let latinSource = value.applyingTransform(.toLatin, reverse: false) ?? value
        let latinNormalized = normalizedToken(latinSource)
        let latinCompact = compactToken(latinNormalized)
        let latinTerms = searchTerms(from: latinSource)

        let initialsSource = latinTerms.isEmpty ? terms : latinTerms
        let initials = initialsSource.compactMap(\.first).map(String.init).joined()

        let uppercaseAbbreviation = String(
            value.unicodeScalars.filter { scalar in
                CharacterSet.uppercaseLetters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar)
            }
        ).lowercased()
        let compactUppercaseAbbreviation = compactToken(uppercaseAbbreviation)
        let identifierTerms = identifierSearchTerms(from: identifier)

        var coarseTerms = Set<String>()
        coarseTerms.formUnion(terms)
        coarseTerms.formUnion(latinTerms)
        coarseTerms.formUnion(identifierTerms)
        if !compact.isEmpty {
            coarseTerms.insert(compact)
        }
        if !latinCompact.isEmpty {
            coarseTerms.insert(latinCompact)
        }
        if !initials.isEmpty {
            coarseTerms.insert(initials)
        }
        if !compactUppercaseAbbreviation.isEmpty {
            coarseTerms.insert(compactUppercaseAbbreviation)
        }

        var coarseBigrams = Set<String>()
        coarseBigrams.formUnion(bigrams(of: compact))
        coarseBigrams.formUnion(bigrams(of: latinCompact))
        coarseBigrams.formUnion(bigrams(of: compactUppercaseAbbreviation))
        for term in identifierTerms {
            coarseBigrams.formUnion(bigrams(of: term))
            coarseBigrams.formUnion(
                orderedCharacterPairs(of: term, maxSkippedCharacters: orderedPairMaximumSkippedCharacters)
            )
        }

        return Index(
            normalized: normalized,
            compact: compact,
            terms: terms,
            latinNormalized: latinNormalized,
            latinCompact: latinCompact,
            latinTerms: latinTerms,
            initials: initials,
            uppercaseAbbreviation: compactUppercaseAbbreviation,
            identifierTerms: identifierTerms,
            coarseTerms: Array(coarseTerms),
            coarseBigrams: Array(coarseBigrams)
        )
    }

    private static func identifierSearchTerms(from identifier: String?) -> [String] {
        guard let identifier else { return [] }
        let normalized = normalizedToken(identifier)
        let rawTerms = orderedUniqueTerms(
            basicSearchTerms(from: normalized) + searchTerms(from: identifier)
        )
        guard !rawTerms.isEmpty else { return [] }

        var seen: Set<String> = []
        var result: [String] = []
        for term in rawTerms {
            guard !term.isEmpty else { continue }
            guard term.count >= 2 else { continue }
            guard !ignoredIdentifierTokens.contains(term) else { continue }
            if seen.insert(term).inserted {
                result.append(term)
            }
        }
        return result
    }

    public static func matchScore(query: Key, in index: Index) -> Int? {
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
        consider(&best, matchIdentifierSubsequenceScore(query.compact, in: index.identifierTerms, base: 76))
        return best
    }

    public static func isBetter(_ lhs: RankedResult, than rhs: RankedResult) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score < rhs.score
        }
        return lhs.order < rhs.order
    }

    public static func insertTopRankedResult(
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

    public static func resolvedSelectedResultIndex(
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

    public static func bestScore(_ lhs: Int?, _ rhs: Int?) -> Int? {
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

    private static func matchIdentifierScore(
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

    private static func matchPositionScore(
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

    private static func matchTokenPrefixScore(
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

    private static func matchInitialsPrefixOrContainsScore(
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

    private static func matchIdentifierSubsequenceScore(
        _ query: String,
        in identifierTerms: [String],
        base: Int
    ) -> Int? {
        guard !identifierTerms.isEmpty else { return nil }

        var best: Int?
        for term in identifierTerms {
            consider(&best, matchOrderedSubsequenceScore(query, in: term, base: base))
        }
        return best
    }

    private static func matchOrderedSubsequenceScore(
        _ query: String,
        in source: String,
        base: Int
    ) -> Int? {
        let queryLength = query.count
        guard queryLength >= orderedSubsequenceMinimumQueryLength else { return nil }
        guard source.count >= queryLength else { return nil }
        guard let match = orderedSubsequenceMatch(query: query, in: source) else { return nil }
        guard match.gapPenalty <= orderedSubsequenceMaximumGapPenalty else { return nil }

        let lengthPenalty = max(0, source.count - queryLength)
        return base + match.startOffset + (match.gapPenalty * 2) + lengthPenalty
    }

    private static func orderedSubsequenceMatch(
        query: String,
        in source: String
    ) -> (startOffset: Int, gapPenalty: Int)? {
        var sourceCursor = source.startIndex
        var firstMatchIndex: String.Index?
        var lastMatchIndex: String.Index?

        for character in query {
            guard let found = source[sourceCursor...].firstIndex(of: character) else { return nil }
            if firstMatchIndex == nil {
                firstMatchIndex = found
            }
            lastMatchIndex = found
            sourceCursor = source.index(after: found)
        }

        guard let firstMatchIndex, let lastMatchIndex else { return nil }
        let startOffset = source.distance(from: source.startIndex, to: firstMatchIndex)
        let span = source.distance(from: firstMatchIndex, to: lastMatchIndex)
        let tightSpan = max(0, query.count - 1)
        return (startOffset: startOffset, gapPenalty: max(0, span - tightSpan))
    }

    private static func searchTerms(from value: String) -> [String] {
        let segments = value.split { character in
            !character.isLetter && !character.isNumber
        }

        var terms: [String] = []
        terms.reserveCapacity(segments.count)

        for segment in segments {
            let naturalLanguageTerms = naturalLanguageSearchTerms(in: String(segment))
            if naturalLanguageTerms.count > 1 {
                terms.append(contentsOf: naturalLanguageTerms)
                continue
            }

            let boundaryTerms = boundarySegmentTerms(in: segment)
            if boundaryTerms.count > 1 {
                terms.append(contentsOf: boundaryTerms)
                continue
            }

            let normalized = normalizedToken(String(segment))
            if !normalized.isEmpty {
                terms.append(normalized)
            }
        }

        return orderedUniqueTerms(terms)
    }

    private static func basicSearchTerms(from value: String) -> [String] {
        value
            .split { character in
                !character.isLetter && !character.isNumber
            }
            .map(String.init)
    }

    private static func naturalLanguageSearchTerms(in value: String) -> [String] {
        guard shouldUseNaturalLanguageSegmentation(for: value) else { return [] }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = value

        var terms: [String] = []
        tokenizer.enumerateTokens(in: value.startIndex..<value.endIndex) { range, _ in
            let token = normalizedToken(String(value[range]))
            if !token.isEmpty {
                terms.append(token)
            }
            return true
        }
        return orderedUniqueTerms(terms)
    }

    private static func shouldUseNaturalLanguageSegmentation(for value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            scalar.value > 127 && CharacterSet.letters.contains(scalar)
        }
    }

    private static func boundarySegmentTerms(in value: Substring) -> [String] {
        let scalars = Array(value.unicodeScalars)
        guard scalars.count >= 2 else { return [] }

        var ranges: [(start: Int, end: Int)] = []
        var start = 0

        for index in 1..<scalars.count {
            let previous = scalars[index - 1]
            let current = scalars[index]
            let next = index + 1 < scalars.count ? scalars[index + 1] : nil
            guard shouldSplitBoundary(previous: previous, current: current, next: next) else {
                continue
            }
            ranges.append((start: start, end: index))
            start = index
        }

        guard !ranges.isEmpty else { return [] }
        ranges.append((start: start, end: scalars.count))

        return orderedUniqueTerms(
            ranges.compactMap { range in
                let token = String(String.UnicodeScalarView(scalars[range.start..<range.end]))
                let normalized = normalizedToken(token)
                return normalized.isEmpty ? nil : normalized
            }
        )
    }

    private static func shouldSplitBoundary(
        previous: Unicode.Scalar,
        current: Unicode.Scalar,
        next: Unicode.Scalar?
    ) -> Bool {
        let previousIsDigit = CharacterSet.decimalDigits.contains(previous)
        let currentIsDigit = CharacterSet.decimalDigits.contains(current)
        if previousIsDigit != currentIsDigit {
            return true
        }

        let previousIsLower = CharacterSet.lowercaseLetters.contains(previous)
        let previousIsUpper = CharacterSet.uppercaseLetters.contains(previous)
        let currentIsUpper = CharacterSet.uppercaseLetters.contains(current)

        if previousIsLower && currentIsUpper {
            return true
        }

        if previousIsUpper, currentIsUpper, let next, CharacterSet.lowercaseLetters.contains(next) {
            return true
        }

        return false
    }

    private static func orderedUniqueTerms(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        result.reserveCapacity(values.count)

        for value in values where !value.isEmpty {
            if seen.insert(value).inserted {
                result.append(value)
            }
        }

        return result
    }

    public static func compactToken(_ value: String) -> String {
        String(
            value.unicodeScalars.filter { scalar in
                CharacterSet.alphanumerics.contains(scalar)
            }
        )
    }

    private static func normalizedToken(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
            .lowercased()
    }

    public static func bigrams(of value: String) -> [String] {
        guard value.count >= 2 else { return [] }
        let characters = Array(value)
        guard characters.count >= 2 else { return [] }

        var grams: [String] = []
        grams.reserveCapacity(characters.count - 1)
        for index in 0..<(characters.count - 1) {
            grams.append(String(characters[index...index + 1]))
        }
        return grams
    }

    private static func orderedCharacterPairs(
        of value: String,
        maxSkippedCharacters: Int
    ) -> [String] {
        guard value.count >= 2 else { return [] }
        let characters = Array(value)
        guard characters.count >= 2 else { return [] }

        var pairs: [String] = []
        for index in 0..<(characters.count - 1) {
            let upperBound = min(characters.count - 1, index + maxSkippedCharacters + 1)
            guard index + 1 <= upperBound else { continue }
            for nextIndex in (index + 1)...upperBound {
                pairs.append(String([characters[index], characters[nextIndex]]))
            }
        }
        return pairs
    }

    private static func consider(_ best: inout Int?, _ candidate: Int?) {
        guard let candidate else { return }
        if let currentBest = best {
            if candidate < currentBest {
                best = candidate
            }
        } else {
            best = candidate
        }
    }
}
