import Foundation
import NaturalLanguage
import FlowTabCore

extension SwitcherSearchCoordinator {
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
                        .search,
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
                        RuntimeLog.info(
                            .search,
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
                        .search,
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
                        RuntimeLog.info(
                            .search,
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

    static func candidateIndexes(
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

    static func boundedCandidateIndexes(
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

    static func boundedMatchedIndexes(_ matchedIndexes: [Int], limit: Int) -> [Int] {
        guard limit > 0, matchedIndexes.count > limit else { return matchedIndexes }
        return Array(matchedIndexes.prefix(limit))
    }

    static func cachePolicy(
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

    static func logEmptySearchDiagnostics(
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
            .search,
            "scope=\(scope.rawValue) query=\"\(query.normalized)\" compact=\"\(query.compact)\" terms=\(query.terms) coarseCandidates=\(coarseCandidateCount) candidateIndexes=\(candidateCount) boundedCandidates=\(boundedCandidateCount) matched=\(matchedCount) topResults=\(topResultCount) rawIdentifierContains=\(rawIdentifierContainsCount)"
        )
    }

    static func coarseFilter(query: SearchKey, invertedIndex: ScopeInvertedIndex) -> [Int] {
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

    static func buildScopeInvertedIndex(from indexes: [SearchIndex]) -> ScopeInvertedIndex {
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

    static func touchedCache(
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

    static func updatedCache(
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
}
