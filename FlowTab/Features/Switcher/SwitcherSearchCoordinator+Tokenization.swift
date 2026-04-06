import Foundation
import NaturalLanguage
import FlowTabCore

extension SwitcherSearchCoordinator {
    static func buildSearchKey(from value: String) -> SearchKey {
        let normalized = normalizedToken(value)
        return SearchKey(
            normalized: normalized,
            compact: compactToken(normalized),
            terms: searchTerms(from: value)
        )
    }

    static func buildSearchIndex(for value: String, identifier: String? = nil) -> SearchIndex {
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
        let identifierTerms = bundleIDTerms(from: identifier)

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
        }

        return SearchIndex(
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

    static func bundleIDTerms(from identifier: String?) -> [String] {
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
            guard !ignoredBundleIDTokens.contains(term) else { continue }
            if seen.insert(term).inserted {
                result.append(term)
            }
        }
        return result
    }

    static func searchTerms(from value: String) -> [String] {
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

    static func basicSearchTerms(from value: String) -> [String] {
        value
            .split { character in
                !character.isLetter && !character.isNumber
            }
            .map(String.init)
    }

    static func naturalLanguageSearchTerms(in value: String) -> [String] {
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

    static func shouldUseNaturalLanguageSegmentation(for value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            scalar.value > 127 && CharacterSet.letters.contains(scalar)
        }
    }

    static func boundarySegmentTerms(in value: Substring) -> [String] {
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

    static func shouldSplitBoundary(
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

    static func orderedUniqueTerms(_ values: [String]) -> [String] {
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

    static func compactToken(_ value: String) -> String {
        String(
            value.unicodeScalars.filter { scalar in
                CharacterSet.alphanumerics.contains(scalar)
            }
        )
    }

    static func normalizedToken(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
            .lowercased()
    }

    static func bigrams(of value: String) -> [String] {
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

    static func wrappedIndex(current: Int, count: Int, delta: Int) -> Int {
        guard count > 0 else { return 0 }
        let raw = (current + delta) % count
        return raw >= 0 ? raw : raw + count
    }

    static func clampedCursorPosition(_ cursorPosition: Int, in query: String) -> Int {
        min(max(cursorPosition, 0), query.count)
    }

    static func stringIndex(in value: String, characterOffset: Int) -> String.Index {
        let offset = min(max(characterOffset, 0), value.count)
        return value.index(value.startIndex, offsetBy: offset)
    }
}
