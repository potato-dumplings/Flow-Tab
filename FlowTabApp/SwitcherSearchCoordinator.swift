import Foundation
import FlowTabCore

enum SwitcherSearchScope: String, CaseIterable, Equatable, Sendable {
    case app
    case window

    var label: String {
        switch self {
        case .app:
            return "应用"
        case .window:
            return "窗口"
        }
    }
}

enum SwitcherSearchResultKind: Equatable, Sendable {
    case app(appID: String)
    case window(appID: String, windowID: String)
}

struct SwitcherSearchResult: Identifiable, Equatable, Sendable {
    let id: String
    let kind: SwitcherSearchResultKind
    let primaryText: String
    let secondaryText: String?
}

struct SwitcherSearchViewState: Equatable, Sendable {
    var isActive: Bool
    var isInputFocused: Bool
    var scope: SwitcherSearchScope
    var query: String
    var results: [SwitcherSearchResult]
    var selectedResultIndex: Int

    static let inactive = SwitcherSearchViewState(
        isActive: false,
        isInputFocused: false,
        scope: .app,
        query: "",
        results: [],
        selectedResultIndex: 0
    )

    var selectedResult: SwitcherSearchResult? {
        guard results.indices.contains(selectedResultIndex) else { return nil }
        return results[selectedResultIndex]
    }
}

enum SwitcherSearchEscapeAction: Sendable {
    case clearQuery
    case exitSearch
    case ignored
}

final class SwitcherSearchCoordinator {
    struct SearchKey: Sendable {
        let normalized: String
        let compact: String
        let terms: [String]
    }

    struct SearchIndex: Sendable {
        let normalized: String
        let compact: String
        let terms: [String]
        let latinNormalized: String
        let latinCompact: String
        let latinTerms: [String]
        let initials: String
        let uppercaseAbbreviation: String
        let identifierTerms: [String]
    }

    struct AppEntry: Sendable {
        let appID: String
        let appDisplayName: String
        let searchIndex: SearchIndex
    }

    struct WindowEntry: Sendable {
        let appID: String
        let appDisplayName: String
        let windowID: String
        let windowTitle: String
        let windowSearchIndex: SearchIndex
        let appSearchIndex: SearchIndex
    }

    struct RankedResult: Sendable {
        let result: SwitcherSearchResult
        let score: Int
        let order: Int
    }

    struct QueryCacheEntry: Sendable {
        let matchedIndexes: [Int]
        let topResults: [SwitcherSearchResult]
    }

    struct ScopeMatchCache: Sendable {
        let latestQuery: String
        let latestMatchedIndexes: [Int]
        let entries: [String: QueryCacheEntry]
        let lruOrder: [String]
    }

    struct ComputationInput: Sendable {
        let query: String
        let scope: SwitcherSearchScope
        let selectedResultIndex: Int
        let resetSelection: Bool
        fileprivate let appEntries: [AppEntry]
        fileprivate let windowEntries: [WindowEntry]
        fileprivate let appMatchCache: ScopeMatchCache?
        fileprivate let windowMatchCache: ScopeMatchCache?
    }

    struct ComputationOutput: Sendable {
        let query: String
        let scope: SwitcherSearchScope
        let results: [SwitcherSearchResult]
        let selectedResultIndex: Int
        fileprivate let appMatchCache: ScopeMatchCache?
        fileprivate let windowMatchCache: ScopeMatchCache?
    }

    private(set) var state: SwitcherSearchViewState = .inactive

    private var appEntries: [AppEntry] = []
    private var windowEntries: [WindowEntry] = []
    private var appMatchCache: ScopeMatchCache?
    private var windowMatchCache: ScopeMatchCache?
    private static let scopeMatchCacheEntryLimit: Int = 32
    private static let appTopResultLimit: Int = 300
    private static let windowTopResultLimit: Int = 400
    private static let ignoredBundleIDTokens: Set<String> = ["com", "org", "net", "io", "app", "www"]

    // Search happens on every key press, so we pre-normalize source text once per session.
    func rebuildIndex(with apps: [AppSwitchCandidate]) {
        appEntries = apps.map { app in
            let searchIndex = Self.buildSearchIndex(for: app.displayName, identifier: app.id)
            return AppEntry(
                appID: app.id,
                appDisplayName: app.displayName,
                searchIndex: searchIndex
            )
        }
        let appSearchIndexes = Dictionary(uniqueKeysWithValues: appEntries.map { ($0.appID, $0.searchIndex) })

        var windows: [WindowEntry] = []
        windows.reserveCapacity(apps.reduce(0) { partial, app in
            partial + app.windows.count
        })

        for app in apps {
            let appSearchIndex = appSearchIndexes[app.id]
                ?? Self.buildSearchIndex(for: app.displayName, identifier: app.id)
            for window in app.windows {
                let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
                windows.append(
                    WindowEntry(
                        appID: app.id,
                        appDisplayName: app.displayName,
                        windowID: window.id,
                        windowTitle: title,
                        windowSearchIndex: Self.buildSearchIndex(for: title),
                        appSearchIndex: appSearchIndex
                    )
                )
            }
        }
        windowEntries = windows
        appMatchCache = nil
        windowMatchCache = nil
        state = .inactive
    }

    @discardableResult
    func activate(defaultScope: SwitcherSearchScope = .app) -> Bool {
        guard !appEntries.isEmpty else { return false }
        guard !state.isActive else { return true }

        state.isActive = true
        state.isInputFocused = true
        state.scope = defaultScope
        state.query = ""
        state.selectedResultIndex = 0
        rebuildResults(resetSelection: true)
        return true
    }

    @discardableResult
    func exit() -> Bool {
        guard state.isActive else { return false }
        state = .inactive
        return true
    }

    @discardableResult
    func toggleScope() -> Bool {
        guard toggleScopeWithoutRebuild() else { return false }
        rebuildResults(resetSelection: true)
        return true
    }

    @discardableResult
    func toggleScopeWithoutRebuild() -> Bool {
        guard state.isActive else { return false }
        state.scope = state.scope == .app ? .window : .app
        state.selectedResultIndex = 0
        return true
    }

    @discardableResult
    func focusResults() -> Bool {
        guard state.isActive else { return false }
        guard state.isInputFocused else { return false }
        state.isInputFocused = false
        return true
    }

    @discardableResult
    func focusInput() -> Bool {
        guard state.isActive else { return false }
        guard !state.isInputFocused else { return false }
        state.isInputFocused = true
        return true
    }

    @discardableResult
    func moveSelection(by delta: Int) -> Bool {
        guard state.isActive else { return false }
        guard !state.results.isEmpty else { return false }
        guard delta != 0 else { return false }
        let count = state.results.count
        state.selectedResultIndex = Self.wrappedIndex(
            current: state.selectedResultIndex,
            count: count,
            delta: delta
        )
        return true
    }

    @discardableResult
    func appendQueryText(_ value: String) -> Bool {
        guard appendQueryTextWithoutRebuild(value) else { return false }
        rebuildResults(resetSelection: true)
        return true
    }

    @discardableResult
    func appendQueryTextWithoutRebuild(_ value: String) -> Bool {
        guard state.isActive else { return false }
        guard !value.isEmpty else { return false }
        state.query.append(value)
        state.selectedResultIndex = 0
        return true
    }

    @discardableResult
    func deleteBackwardInQuery() -> Bool {
        guard deleteBackwardInQueryWithoutRebuild() else { return false }
        rebuildResults(resetSelection: true)
        return true
    }

    @discardableResult
    func deleteBackwardInQueryWithoutRebuild() -> Bool {
        guard state.isActive else { return false }
        guard !state.query.isEmpty else { return false }
        state.query.removeLast()
        state.selectedResultIndex = 0
        return true
    }

    func handleEscape() -> SwitcherSearchEscapeAction {
        guard state.isActive else { return .ignored }
        if !state.query.isEmpty {
            state.query = ""
            state.selectedResultIndex = 0
            rebuildResults(resetSelection: true)
            return .clearQuery
        }
        state = .inactive
        return .exitSearch
    }

    private func rebuildResults(resetSelection: Bool) {
        guard let input = makeComputationInput(resetSelection: resetSelection) else { return }
        let output = Self.computeOutput(from: input)
        _ = applyComputationOutput(output)
    }

    func makeComputationInput(resetSelection: Bool) -> ComputationInput? {
        guard state.isActive else { return nil }
        return ComputationInput(
            query: state.query,
            scope: state.scope,
            selectedResultIndex: state.selectedResultIndex,
            resetSelection: resetSelection,
            appEntries: appEntries,
            windowEntries: windowEntries,
            appMatchCache: appMatchCache,
            windowMatchCache: windowMatchCache
        )
    }

    @discardableResult
    func applyComputationOutput(_ output: ComputationOutput) -> Bool {
        guard state.isActive else { return false }
        guard state.query == output.query else { return false }
        guard state.scope == output.scope else { return false }

        let oldState = state
        appMatchCache = output.appMatchCache
        windowMatchCache = output.windowMatchCache
        state.results = output.results
        state.selectedResultIndex = output.selectedResultIndex
        return state != oldState
    }

    static func computeOutput(from input: ComputationInput) -> ComputationOutput {
        let query = buildSearchKey(from: input.query)
        let rebuilt: [SwitcherSearchResult]
        var appCache = input.appMatchCache
        var windowCache = input.windowMatchCache

        switch input.scope {
        case .app:
            if query.normalized.isEmpty {
                appCache = nil
                rebuilt = input.appEntries.map { app in
                    SwitcherSearchResult(
                        id: "app:\(app.appID)",
                        kind: .app(appID: app.appID),
                        primaryText: app.appDisplayName,
                        secondaryText: nil
                    )
                }
            } else if
                let cache = appCache,
                let cachedEntry = cache.entries[query.normalized]
            {
                appCache = touchedCache(
                    cache,
                    query: query.normalized,
                    latestMatchedIndexes: cachedEntry.matchedIndexes
                )
                rebuilt = cachedEntry.topResults
            } else {
                let candidateIndexes = candidateIndexes(
                    query: query.normalized,
                    cache: appCache,
                    totalCount: input.appEntries.count
                )
                var matchedIndexes: [Int] = []
                matchedIndexes.reserveCapacity(candidateIndexes.count)
                var topRanked: [RankedResult] = []
                topRanked.reserveCapacity(min(Self.appTopResultLimit, candidateIndexes.count))
                for index in candidateIndexes {
                    let app = input.appEntries[index]
                    guard let score = Self.matchScore(query: query, in: app.searchIndex) else {
                        continue
                    }
                    matchedIndexes.append(index)
                    let ranked = RankedResult(
                        result: SwitcherSearchResult(
                            id: "app:\(app.appID)",
                            kind: .app(appID: app.appID),
                            primaryText: app.appDisplayName,
                            secondaryText: nil
                        ),
                        score: score,
                        order: index
                    )
                    insertTopRankedResult(ranked, into: &topRanked, limit: Self.appTopResultLimit)
                }
                let topResults = topRanked.map(\.result)
                appCache = updatedCache(
                    appCache,
                    query: query.normalized,
                    matchedIndexes: matchedIndexes,
                    topResults: topResults,
                    limit: Self.scopeMatchCacheEntryLimit
                )
                rebuilt = topResults
            }
        case .window:
            if query.normalized.isEmpty {
                windowCache = nil
                rebuilt = input.windowEntries.map { window in
                    let resolvedTitle = window.windowTitle.isEmpty ? "Untitled Window" : window.windowTitle
                    return SwitcherSearchResult(
                        id: "window:\(window.appID)#\(window.windowID)",
                        kind: .window(appID: window.appID, windowID: window.windowID),
                        primaryText: resolvedTitle,
                        secondaryText: window.appDisplayName
                    )
                }
            } else if
                let cache = windowCache,
                let cachedEntry = cache.entries[query.normalized]
            {
                windowCache = touchedCache(
                    cache,
                    query: query.normalized,
                    latestMatchedIndexes: cachedEntry.matchedIndexes
                )
                rebuilt = cachedEntry.topResults
            } else {
                let candidateIndexes = candidateIndexes(
                    query: query.normalized,
                    cache: windowCache,
                    totalCount: input.windowEntries.count
                )
                var matchedIndexes: [Int] = []
                matchedIndexes.reserveCapacity(candidateIndexes.count)
                var topRanked: [RankedResult] = []
                topRanked.reserveCapacity(min(Self.windowTopResultLimit, candidateIndexes.count))
                for index in candidateIndexes {
                    let window = input.windowEntries[index]
                    let titleScore = Self.matchScore(query: query, in: window.windowSearchIndex)
                    let appScore = Self.matchScore(query: query, in: window.appSearchIndex).map { $0 + 35 }
                    guard let score = Self.bestScore(titleScore, appScore) else {
                        continue
                    }
                    matchedIndexes.append(index)
                    let resolvedTitle = window.windowTitle.isEmpty ? "Untitled Window" : window.windowTitle
                    let ranked = RankedResult(
                        result: SwitcherSearchResult(
                            id: "window:\(window.appID)#\(window.windowID)",
                            kind: .window(appID: window.appID, windowID: window.windowID),
                            primaryText: resolvedTitle,
                            secondaryText: window.appDisplayName
                        ),
                        score: score,
                        order: index
                    )
                    insertTopRankedResult(ranked, into: &topRanked, limit: Self.windowTopResultLimit)
                }
                let topResults = topRanked.map(\.result)
                windowCache = updatedCache(
                    windowCache,
                    query: query.normalized,
                    matchedIndexes: matchedIndexes,
                    topResults: topResults,
                    limit: Self.scopeMatchCacheEntryLimit
                )
                rebuilt = topResults
            }
        }

        return ComputationOutput(
            query: input.query,
            scope: input.scope,
            results: rebuilt,
            selectedResultIndex: resolvedSelectedResultIndex(
                previous: input.selectedResultIndex,
                resultCount: rebuilt.count,
                resetSelection: input.resetSelection
            ),
            appMatchCache: appCache,
            windowMatchCache: windowCache
        )
    }

    private static func candidateIndexes(
        query: String,
        cache: ScopeMatchCache?,
        totalCount: Int
    ) -> [Int] {
        guard let cache else {
            return Array(0..<totalCount)
        }

        if !cache.latestQuery.isEmpty, query.hasPrefix(cache.latestQuery) {
            return cache.latestMatchedIndexes
        }
        if let exactEntry = cache.entries[query] {
            return exactEntry.matchedIndexes
        }

        var prefix = query
        while !prefix.isEmpty {
            prefix.removeLast()
            if let entry = cache.entries[prefix] {
                return entry.matchedIndexes
            }
        }
        return Array(0..<totalCount)
    }

    private static func touchedCache(
        _ cache: ScopeMatchCache,
        query: String,
        latestMatchedIndexes: [Int]
    ) -> ScopeMatchCache {
        var lruOrder = cache.lruOrder
        lruOrder.removeAll { $0 == query }
        lruOrder.append(query)
        return ScopeMatchCache(
            latestQuery: query,
            latestMatchedIndexes: latestMatchedIndexes,
            entries: cache.entries,
            lruOrder: lruOrder
        )
    }

    private static func updatedCache(
        _ existing: ScopeMatchCache?,
        query: String,
        matchedIndexes: [Int],
        topResults: [SwitcherSearchResult],
        limit: Int
    ) -> ScopeMatchCache {
        var entries = existing?.entries ?? [:]
        var lruOrder = existing?.lruOrder ?? []

        entries[query] = QueryCacheEntry(matchedIndexes: matchedIndexes, topResults: topResults)
        lruOrder.removeAll { $0 == query }
        lruOrder.append(query)

        if limit > 0 {
            while lruOrder.count > limit {
                let removed = lruOrder.removeFirst()
                entries.removeValue(forKey: removed)
            }
        } else {
            lruOrder.removeAll(keepingCapacity: false)
            entries.removeAll(keepingCapacity: false)
        }

        return ScopeMatchCache(
            latestQuery: query,
            latestMatchedIndexes: matchedIndexes,
            entries: entries,
            lruOrder: lruOrder
        )
    }

    private static func isBetter(_ lhs: RankedResult, than rhs: RankedResult) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score < rhs.score
        }
        return lhs.order < rhs.order
    }

    private static func insertTopRankedResult(
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

    private static func resolvedSelectedResultIndex(
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

    private static func bestScore(_ lhs: Int?, _ rhs: Int?) -> Int? {
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

    private static func matchScore(query: SearchKey, in index: SearchIndex) -> Int? {
        guard !query.normalized.isEmpty else { return 0 }

        guard let fastScore = fastMatchScore(query: query, in: index) else {
            guard query.compact.count <= 2 else { return nil }
            return matchInitialsSubsequenceScore(query.compact, in: index.initials, base: 16)
                ?? matchInitialsSubsequenceScore(query.compact, in: index.uppercaseAbbreviation, base: 15)
        }

        var best: Int? = fastScore
        consider(&best, matchInitialsSubsequenceScore(query.compact, in: index.initials, base: 16))
        consider(&best, matchInitialsSubsequenceScore(query.compact, in: index.uppercaseAbbreviation, base: 15))
        return best
    }

    private static func fastMatchScore(query: SearchKey, in index: SearchIndex) -> Int? {
        var best: Int?
        consider(&best, matchPositionScore(query.normalized, in: index.normalized, prefixBase: 0, containsBase: 20))
        consider(&best, matchPositionScore(query.compact, in: index.compact, prefixBase: 4, containsBase: 30))
        consider(&best, matchPositionScore(query.normalized, in: index.latinNormalized, prefixBase: 10, containsBase: 36))
        consider(&best, matchPositionScore(query.compact, in: index.latinCompact, prefixBase: 14, containsBase: 40))
        consider(&best, matchTokenPrefixScore(query.terms, in: index.terms, base: 18))
        consider(&best, matchTokenPrefixScore(query.terms, in: index.latinTerms, base: 24))
        consider(&best, matchInitialsPrefixOrContainsScore(query.compact, in: index.initials, base: 16))
        consider(&best, matchInitialsPrefixOrContainsScore(query.compact, in: index.uppercaseAbbreviation, base: 15))
        consider(&best, matchIdentifierScore(query.compact, in: index.identifierTerms, base: 22))
        return best
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
                candidate = base + 8 + distance
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

    private static func matchInitialsSubsequenceScore(
        _ query: String,
        in initials: String,
        base: Int
    ) -> Int? {
        guard !query.isEmpty else { return nil }
        guard !initials.isEmpty else { return nil }
        guard let gapPenalty = subsequenceGap(query: query, in: initials) else { return nil }
        return base + 20 + gapPenalty
    }

    private static func subsequenceGap(query: String, in source: String) -> Int? {
        guard !query.isEmpty else { return 0 }
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
        let span = source.distance(from: firstMatchIndex, to: lastMatchIndex)
        return max(0, span - max(0, query.count - 1))
    }

    private static func buildSearchKey(from value: String) -> SearchKey {
        let normalized = normalizedToken(value)
        return SearchKey(
            normalized: normalized,
            compact: compactToken(normalized),
            terms: searchTerms(from: normalized)
        )
    }

    private static func buildSearchIndex(for value: String, identifier: String? = nil) -> SearchIndex {
        let normalized = normalizedToken(value)
        let compact = compactToken(normalized)
        let terms = searchTerms(from: normalized)

        let latinSource = value.applyingTransform(.toLatin, reverse: false) ?? value
        let latinNormalized = normalizedToken(latinSource)
        let latinCompact = compactToken(latinNormalized)
        let latinTerms = searchTerms(from: latinNormalized)

        let initialsSource = latinTerms.isEmpty ? terms : latinTerms
        let initials = initialsSource.compactMap(\.first).map(String.init).joined()

        let uppercaseAbbreviation = String(
            value.unicodeScalars.filter { scalar in
                CharacterSet.uppercaseLetters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar)
            }
        ).lowercased()
        let identifierTerms = bundleIDTerms(from: identifier)

        return SearchIndex(
            normalized: normalized,
            compact: compact,
            terms: terms,
            latinNormalized: latinNormalized,
            latinCompact: latinCompact,
            latinTerms: latinTerms,
            initials: initials,
            uppercaseAbbreviation: compactToken(uppercaseAbbreviation),
            identifierTerms: identifierTerms
        )
    }

    private static func bundleIDTerms(from identifier: String?) -> [String] {
        guard let identifier else { return [] }
        let normalized = normalizedToken(identifier)
        let rawTerms = searchTerms(from: normalized)
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

    private static func searchTerms(from value: String) -> [String] {
        value
            .split { character in
                !character.isLetter && !character.isNumber
            }
            .map(String.init)
    }

    private static func compactToken(_ value: String) -> String {
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

    private static func wrappedIndex(current: Int, count: Int, delta: Int) -> Int {
        guard count > 0 else { return 0 }
        let raw = (current + delta) % count
        return raw >= 0 ? raw : raw + count
    }
}
