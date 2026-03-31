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
    var queryCursorPosition: Int
    var results: [SwitcherSearchResult]
    var selectedResultIndex: Int

    static let inactive = SwitcherSearchViewState(
        isActive: false,
        isInputFocused: false,
        scope: .app,
        query: "",
        queryCursorPosition: 0,
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
        let coarseTerms: [String]
        let coarseBigrams: [String]
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

    struct ScopeInvertedIndex: Sendable {
        let termPostings: [String: [Int]]
        let bigramPostings: [String: [Int]]
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
        fileprivate let appInvertedIndex: ScopeInvertedIndex
        fileprivate let windowInvertedIndex: ScopeInvertedIndex
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
    private var appInvertedIndex = ScopeInvertedIndex(termPostings: [:], bigramPostings: [:])
    private var windowInvertedIndex = ScopeInvertedIndex(termPostings: [:], bigramPostings: [:])
    private var pendingRebuildWorkItem: DispatchWorkItem?
    private var pendingRebuildResetSelection: Bool = false
    private static let scopeMatchCacheEntryLimit: Int = 32
    private static let shortQueryCacheEntryLimit: Int = 12
    private static let appTopResultLimit: Int = 300
    private static let windowTopResultLimit: Int = 400
    private static let appCandidateLimitShortQuery: Int = 1_000
    private static let appCandidateLimitLongQuery: Int = 1_600
    private static let windowCandidateLimitShortQuery: Int = 1_200
    private static let windowCandidateLimitLongQuery: Int = 2_000
    private static let shortQueryMatchedIndexesLimit: Int = 512
    private static let longQueryMatchedIndexesLimit: Int = 2_000
    private static let shortQueryThreshold: Int = 2
    private static let queryDebounceNanoseconds: UInt64 = 10_000_000
    private static let ignoredBundleIDTokens: Set<String> = ["com", "org", "net", "io", "app", "www"]

    // Search happens on every key press, so we pre-normalize source text once per session.
    func rebuildIndex(with apps: [AppSwitchCandidate]) {
        cancelPendingRebuild()
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
        appInvertedIndex = Self.buildScopeInvertedIndex(from: appEntries.map(\.searchIndex))
        windowInvertedIndex = Self.buildScopeInvertedIndex(
            from: windowEntries.map { window in
                let mergedTerms = Set(window.windowSearchIndex.coarseTerms).union(window.appSearchIndex.coarseTerms)
                let mergedBigrams = Set(window.windowSearchIndex.coarseBigrams).union(window.appSearchIndex.coarseBigrams)
                return SearchIndex(
                    normalized: window.windowSearchIndex.normalized,
                    compact: window.windowSearchIndex.compact,
                    terms: window.windowSearchIndex.terms,
                    latinNormalized: window.windowSearchIndex.latinNormalized,
                    latinCompact: window.windowSearchIndex.latinCompact,
                    latinTerms: window.windowSearchIndex.latinTerms,
                    initials: window.windowSearchIndex.initials,
                    uppercaseAbbreviation: window.windowSearchIndex.uppercaseAbbreviation,
                    identifierTerms: window.windowSearchIndex.identifierTerms,
                    coarseTerms: Array(mergedTerms),
                    coarseBigrams: Array(mergedBigrams)
                )
            }
        )
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
        state.queryCursorPosition = 0
        state.selectedResultIndex = 0
        rebuildResults(resetSelection: true)
        return true
    }

    @discardableResult
    func exit() -> Bool {
        guard state.isActive else { return false }
        cancelPendingRebuild()
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
        scheduleRebuild(resetSelection: true, debounced: true)
        return true
    }

    @discardableResult
    func appendQueryTextWithoutRebuild(_ value: String) -> Bool {
        guard state.isActive else { return false }
        guard !value.isEmpty else { return false }
        let cursorPosition: Int
        if state.isInputFocused {
            cursorPosition = Self.clampedCursorPosition(state.queryCursorPosition, in: state.query)
        } else {
            cursorPosition = state.query.count
        }
        let insertionIndex = Self.stringIndex(in: state.query, characterOffset: cursorPosition)
        state.query.insert(contentsOf: value, at: insertionIndex)
        state.queryCursorPosition = cursorPosition + value.count
        state.selectedResultIndex = 0
        return true
    }

    @discardableResult
    func replaceQueryWithoutRebuild(_ value: String, cursorPosition: Int) -> Bool {
        guard state.isActive else { return false }
        let resolvedCursorPosition = Self.clampedCursorPosition(cursorPosition, in: value)
        guard state.query != value || state.queryCursorPosition != resolvedCursorPosition else {
            return false
        }
        state.query = value
        state.queryCursorPosition = resolvedCursorPosition
        state.selectedResultIndex = 0
        return true
    }

    @discardableResult
    func deleteBackwardInQuery() -> Bool {
        guard deleteBackwardInQueryWithoutRebuild() else { return false }
        scheduleRebuild(resetSelection: true, debounced: true)
        return true
    }

    @discardableResult
    func deleteBackwardInQueryWithoutRebuild() -> Bool {
        guard state.isActive else { return false }
        let cursorPosition: Int
        if state.isInputFocused {
            cursorPosition = Self.clampedCursorPosition(state.queryCursorPosition, in: state.query)
        } else {
            cursorPosition = state.query.count
        }
        guard cursorPosition > 0 else { return false }
        let upperBound = Self.stringIndex(in: state.query, characterOffset: cursorPosition)
        let lowerBound = state.query.index(before: upperBound)
        state.query.removeSubrange(lowerBound..<upperBound)
        state.queryCursorPosition = cursorPosition - 1
        state.selectedResultIndex = 0
        return true
    }

    @discardableResult
    func moveQueryCursor(by delta: Int) -> Bool {
        guard state.isActive else { return false }
        guard state.isInputFocused else { return false }
        guard delta != 0 else { return false }
        let current = Self.clampedCursorPosition(state.queryCursorPosition, in: state.query)
        let resolved = min(max(current + delta, 0), state.query.count)
        guard resolved != current else { return false }
        state.queryCursorPosition = resolved
        state.selectedResultIndex = 0
        return true
    }

    func handleEscape() -> SwitcherSearchEscapeAction {
        guard state.isActive else { return .ignored }
        cancelPendingRebuild()
        if !state.query.isEmpty {
            state.query = ""
            state.queryCursorPosition = 0
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

    func flushPendingRebuild() {
        guard pendingRebuildWorkItem != nil else { return }
        pendingRebuildWorkItem?.cancel()
        pendingRebuildWorkItem = nil
        let resetSelection = pendingRebuildResetSelection
        pendingRebuildResetSelection = false
        rebuildResults(resetSelection: resetSelection)
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
            windowMatchCache: windowMatchCache,
            appInvertedIndex: appInvertedIndex,
            windowInvertedIndex: windowInvertedIndex
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
                if cachedEntry.topResults.isEmpty {
                    RuntimeLog.warning(
                        "Search",
                        "scope=app query=\"\(query.normalized)\" source=cache matched=\(cachedEntry.matchedIndexes.count) topResults=0"
                    )
                }
                rebuilt = cachedEntry.topResults
            } else {
                let candidateIndexes = candidateIndexes(
                    query: query,
                    cache: appCache,
                    invertedIndex: input.appInvertedIndex,
                    totalCount: input.appEntries.count
                )
                let boundedCandidateIndexes = boundedCandidateIndexes(
                    candidateIndexes,
                    scope: .app,
                    query: query
                )
                var ranked = rankAppMatches(
                    query: query,
                    entries: input.appEntries,
                    candidateIndexes: boundedCandidateIndexes,
                    topResultLimit: Self.appTopResultLimit
                )
                if ranked.topRanked.isEmpty, boundedCandidateIndexes.count < input.appEntries.count {
                    ranked = rankAppMatches(
                        query: query,
                        entries: input.appEntries,
                        candidateIndexes: Array(input.appEntries.indices),
                        topResultLimit: Self.appTopResultLimit
                    )
                    if !ranked.topRanked.isEmpty {
                        RuntimeLog.warning(
                            "Search",
                            "scope=app query=\"\(query.normalized)\" recallFallback=fullScan initialCandidates=\(boundedCandidateIndexes.count) totalEntries=\(input.appEntries.count) recoveredResults=\(ranked.topRanked.count)"
                        )
                    }
                }
                let matchedIndexes = ranked.matchedIndexes
                let topResults = ranked.topRanked.map { ranked in
                    let app = input.appEntries[ranked.order]
                    return SwitcherSearchResult(
                        id: "app:\(app.appID)",
                        kind: .app(appID: app.appID),
                        primaryText: app.appDisplayName,
                        secondaryText: nil
                    )
                }
                let cachePolicy = cachePolicy(for: query.normalized)
                appCache = updatedCache(
                    appCache,
                    query: query.normalized,
                    matchedIndexes: boundedMatchedIndexes(
                        matchedIndexes,
                        limit: cachePolicy.matchedIndexesLimit
                    ),
                    topResults: topResults,
                    limit: cachePolicy.entryLimit,
                    persistEntry: cachePolicy.persistEntry
                )
                if topResults.isEmpty {
                    logEmptySearchDiagnostics(
                        scope: .app,
                        query: query,
                        coarseCandidateCount: coarseFilter(query: query, invertedIndex: input.appInvertedIndex).count,
                        candidateCount: candidateIndexes.count,
                        boundedCandidateCount: boundedCandidateIndexes.count,
                        matchedCount: matchedIndexes.count,
                        topResultCount: topResults.count,
                        rawIdentifierContainsCount: input.appEntries.filter {
                            $0.appID.localizedCaseInsensitiveContains(query.compact)
                        }.count
                    )
                }
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
                if cachedEntry.topResults.isEmpty {
                    RuntimeLog.warning(
                        "Search",
                        "scope=window query=\"\(query.normalized)\" source=cache matched=\(cachedEntry.matchedIndexes.count) topResults=0"
                    )
                }
                rebuilt = cachedEntry.topResults
            } else {
                let candidateIndexes = candidateIndexes(
                    query: query,
                    cache: windowCache,
                    invertedIndex: input.windowInvertedIndex,
                    totalCount: input.windowEntries.count
                )
                let boundedCandidateIndexes = boundedCandidateIndexes(
                    candidateIndexes,
                    scope: .window,
                    query: query
                )
                var ranked = rankWindowMatches(
                    query: query,
                    entries: input.windowEntries,
                    candidateIndexes: boundedCandidateIndexes,
                    topResultLimit: Self.windowTopResultLimit
                )
                if ranked.topRanked.isEmpty, boundedCandidateIndexes.count < input.windowEntries.count {
                    ranked = rankWindowMatches(
                        query: query,
                        entries: input.windowEntries,
                        candidateIndexes: Array(input.windowEntries.indices),
                        topResultLimit: Self.windowTopResultLimit
                    )
                    if !ranked.topRanked.isEmpty {
                        RuntimeLog.warning(
                            "Search",
                            "scope=window query=\"\(query.normalized)\" recallFallback=fullScan initialCandidates=\(boundedCandidateIndexes.count) totalEntries=\(input.windowEntries.count) recoveredResults=\(ranked.topRanked.count)"
                        )
                    }
                }
                let matchedIndexes = ranked.matchedIndexes
                let topResults = ranked.topRanked.map { ranked in
                    let window = input.windowEntries[ranked.order]
                    let resolvedTitle = window.windowTitle.isEmpty ? "Untitled Window" : window.windowTitle
                    return SwitcherSearchResult(
                        id: "window:\(window.appID)#\(window.windowID)",
                        kind: .window(appID: window.appID, windowID: window.windowID),
                        primaryText: resolvedTitle,
                        secondaryText: window.appDisplayName
                    )
                }
                let cachePolicy = cachePolicy(for: query.normalized)
                windowCache = updatedCache(
                    windowCache,
                    query: query.normalized,
                    matchedIndexes: boundedMatchedIndexes(
                        matchedIndexes,
                        limit: cachePolicy.matchedIndexesLimit
                    ),
                    topResults: topResults,
                    limit: cachePolicy.entryLimit,
                    persistEntry: cachePolicy.persistEntry
                )
                if topResults.isEmpty {
                    logEmptySearchDiagnostics(
                        scope: .window,
                        query: query,
                        coarseCandidateCount: coarseFilter(query: query, invertedIndex: input.windowInvertedIndex).count,
                        candidateCount: candidateIndexes.count,
                        boundedCandidateCount: boundedCandidateIndexes.count,
                        matchedCount: matchedIndexes.count,
                        topResultCount: topResults.count,
                        rawIdentifierContainsCount: input.windowEntries.filter {
                            $0.appID.localizedCaseInsensitiveContains(query.compact)
                        }.count
                    )
                }
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
        query: SearchKey,
        cache: ScopeMatchCache?,
        invertedIndex: ScopeInvertedIndex,
        totalCount: Int
    ) -> [Int] {
        if let cache {
            if
                !cache.latestQuery.isEmpty,
                query.normalized.hasPrefix(cache.latestQuery)
            {
                return cache.latestMatchedIndexes
            }
            if let exactEntry = cache.entries[query.normalized] {
                return exactEntry.matchedIndexes
            }

            var prefix = query.normalized
            while !prefix.isEmpty {
                prefix.removeLast()
                if let entry = cache.entries[prefix] {
                    return entry.matchedIndexes
                }
            }
        }

        let coarse = coarseFilter(query: query, invertedIndex: invertedIndex)
        if coarse.isEmpty {
            return Array(0..<totalCount)
        }
        return coarse
    }

    private static func boundedCandidateIndexes(
        _ candidateIndexes: [Int],
        scope: SwitcherSearchScope,
        query: SearchKey
    ) -> [Int] {
        let compactLength = query.compact.count
        let limit: Int
        switch scope {
        case .app:
            limit = compactLength <= 2 ? appCandidateLimitShortQuery : appCandidateLimitLongQuery
        case .window:
            limit = compactLength <= 2 ? windowCandidateLimitShortQuery : windowCandidateLimitLongQuery
        }
        guard limit > 0, candidateIndexes.count > limit else { return candidateIndexes }
        return Array(candidateIndexes.prefix(limit))
    }

    private static func boundedMatchedIndexes(_ matchedIndexes: [Int], limit: Int) -> [Int] {
        guard limit > 0, matchedIndexes.count > limit else { return matchedIndexes }
        return Array(matchedIndexes.prefix(limit))
    }

    private static func cachePolicy(
        for normalizedQuery: String
    ) -> (entryLimit: Int, matchedIndexesLimit: Int, persistEntry: Bool) {
        let compactLength = compactToken(normalizedQuery).count
        if compactLength <= 1 {
            return (
                entryLimit: 0,
                matchedIndexesLimit: shortQueryMatchedIndexesLimit,
                persistEntry: false
            )
        }
        if compactLength <= shortQueryThreshold {
            return (
                entryLimit: shortQueryCacheEntryLimit,
                matchedIndexesLimit: shortQueryMatchedIndexesLimit,
                persistEntry: true
            )
        }
        return (
            entryLimit: scopeMatchCacheEntryLimit,
            matchedIndexesLimit: longQueryMatchedIndexesLimit,
            persistEntry: true
        )
    }

    private static func logEmptySearchDiagnostics(
        scope: SwitcherSearchScope,
        query: SearchKey,
        coarseCandidateCount: Int,
        candidateCount: Int,
        boundedCandidateCount: Int,
        matchedCount: Int,
        topResultCount: Int,
        rawIdentifierContainsCount: Int
    ) {
        RuntimeLog.warning(
            "Search",
            "scope=\(scope.rawValue) query=\"\(query.normalized)\" compact=\"\(query.compact)\" terms=\(query.terms) coarseCandidates=\(coarseCandidateCount) candidateIndexes=\(candidateCount) boundedCandidates=\(boundedCandidateCount) matched=\(matchedCount) topResults=\(topResultCount) rawIdentifierContains=\(rawIdentifierContainsCount)"
        )
    }

    private static func coarseFilter(query: SearchKey, invertedIndex: ScopeInvertedIndex) -> [Int] {
        var weights: [Int: Int] = [:]
        var gramHits: [Int: Int] = [:]

        let dedupTerms = Set(query.terms + [query.compact, query.normalized].filter { !$0.isEmpty })
        for term in dedupTerms where !term.isEmpty {
            guard let posting = invertedIndex.termPostings[term] else { continue }
            for index in posting {
                weights[index, default: 0] += 4
            }
        }

        let grams = bigrams(of: query.compact)
        for gram in grams {
            guard let posting = invertedIndex.bigramPostings[gram] else { continue }
            for index in posting {
                weights[index, default: 0] += 1
                gramHits[index, default: 0] += 1
            }
        }

        if weights.isEmpty {
            return []
        }

        let minGramHits = grams.isEmpty ? 0 : max(1, grams.count / 2)
        let selected = weights.compactMap { index, weight -> (Int, Int)? in
            let hits = gramHits[index, default: 0]
            if minGramHits == 0 || hits >= minGramHits || weight >= 4 {
                return (index, weight)
            }
            return nil
        }

        let sorted = selected.sorted { lhs, rhs in
            if lhs.1 != rhs.1 {
                return lhs.1 > rhs.1
            }
            return lhs.0 < rhs.0
        }
        return sorted.map(\.0)
    }

    private static func buildScopeInvertedIndex(from indexes: [SearchIndex]) -> ScopeInvertedIndex {
        var termBuckets: [String: [Int]] = [:]
        var bigramBuckets: [String: [Int]] = [:]

        for (index, searchIndex) in indexes.enumerated() {
            for term in Set(searchIndex.coarseTerms) where !term.isEmpty {
                termBuckets[term, default: []].append(index)
            }
            for bigram in Set(searchIndex.coarseBigrams) where !bigram.isEmpty {
                bigramBuckets[bigram, default: []].append(index)
            }
        }

        return ScopeInvertedIndex(termPostings: termBuckets, bigramPostings: bigramBuckets)
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
        limit: Int,
        persistEntry: Bool
    ) -> ScopeMatchCache {
        var entries = existing?.entries ?? [:]
        var lruOrder = existing?.lruOrder ?? []

        if persistEntry {
            entries[query] = QueryCacheEntry(
                matchedIndexes: matchedIndexes,
                topResults: topResults
            )
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
        } else {
            lruOrder.removeAll { $0 == query }
            entries.removeValue(forKey: query)
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

    private static func rankAppMatches(
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

    private static func rankWindowMatches(
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

    private static func matchScore(query: SearchKey, in index: SearchIndex) -> Int? {
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

    private static func bigrams(of value: String) -> [String] {
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

    private static func wrappedIndex(current: Int, count: Int, delta: Int) -> Int {
        guard count > 0 else { return 0 }
        let raw = (current + delta) % count
        return raw >= 0 ? raw : raw + count
    }

    private static func clampedCursorPosition(_ cursorPosition: Int, in query: String) -> Int {
        min(max(cursorPosition, 0), query.count)
    }

    private static func stringIndex(in value: String, characterOffset: Int) -> String.Index {
        let offset = min(max(characterOffset, 0), value.count)
        return value.index(value.startIndex, offsetBy: offset)
    }

    private func cancelPendingRebuild() {
        pendingRebuildWorkItem?.cancel()
        pendingRebuildWorkItem = nil
        pendingRebuildResetSelection = false
    }

    private func scheduleRebuild(resetSelection: Bool, debounced: Bool) {
        guard state.isActive else { return }
        pendingRebuildResetSelection = pendingRebuildResetSelection || resetSelection
        pendingRebuildWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let shouldResetSelection = self.pendingRebuildResetSelection
            self.pendingRebuildResetSelection = false
            self.pendingRebuildWorkItem = nil
            self.rebuildResults(resetSelection: shouldResetSelection)
        }
        pendingRebuildWorkItem = workItem

        if debounced {
            DispatchQueue.main.asyncAfter(
                deadline: .now() + .nanoseconds(Int(Self.queryDebounceNanoseconds)),
                execute: workItem
            )
        } else {
            DispatchQueue.main.async(execute: workItem)
        }
    }
}
