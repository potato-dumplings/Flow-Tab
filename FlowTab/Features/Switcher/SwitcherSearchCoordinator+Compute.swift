import Foundation
import NaturalLanguage
import FlowTabCore

extension SwitcherSearchCoordinator {
    static func computeOutput(from input: ComputationInput) -> ComputationOutput {
        guard let output = computeOutputIfNotCancelled(from: input) else {
            preconditionFailure(
                "Synchronous search computation cannot be cancelled."
            )
        }
        return output
    }

    static func computeOutputIfNotCancelled(
        from input: ComputationInput
    ) -> ComputationOutput? {
        guard !Task.isCancelled else { return nil }
        let query = buildSearchKey(from: input.query)
        let rebuilt: [SwitcherSearchResult]
        var appCache = input.appMatchCache
        var windowCache = input.windowMatchCache

        switch input.scope {
        case .app:
            if query.normalized.isEmpty {
                appCache = nil
                guard let allApps = cancellableMap(
                    input.appEntries,
                    transform: { app in
                    SwitcherSearchResult(
                        id: "app:\(app.appID)",
                        kind: .app(appID: app.appID),
                        primaryText: app.appDisplayName,
                        secondaryText: nil
                    )
                }) else { return nil }
                rebuilt = allApps
            } else if
                let cache = appCache,
                let cachedEntry = cache.entries[query.normalized]
            {
                appCache = touchedCache(
                    cache,
                    query: query.normalized,
                    latestMatchedIndexes: cachedEntry.matchedIndexes,
                    latestMatchedIndexesAreComplete: cachedEntry.matchedIndexesAreComplete
                )
                if cachedEntry.topResults.isEmpty {
                    RuntimeLog.debug(
                        .search,
                        "scope=app query=\"\(query.normalized)\" source=cache matched=\(cachedEntry.matchedIndexes.count) topResults=0"
                    )
                }
                rebuilt = cachedEntry.topResults
            } else {
                let candidatePlan = candidateIndexPlan(
                    query: query,
                    cache: appCache,
                    invertedIndex: input.appInvertedIndex,
                    totalCount: input.appEntries.count
                )
                guard !Task.isCancelled else { return nil }
                let candidateIndexes = candidatePlan.indexes
                let boundedCandidateIndexes = boundedCandidateIndexes(candidateIndexes, scope: .app, query: query)
                let ranksCompleteCandidateSet = candidateIndexes.count == boundedCandidateIndexes.count
                guard let rankedMatches = rankAppMatches(
                    query: query,
                    entries: input.appEntries,
                    candidateIndexes: ranksCompleteCandidateSet ? candidateIndexes : boundedCandidateIndexes,
                    topResultLimit: Self.appTopResultLimit
                ) else { return nil }
                var ranked = (
                    matchedIndexes: rankedMatches.matchedIndexes,
                    topRanked: rankedMatches.topRanked,
                    matchedIndexesAreComplete: candidatePlan.canCacheCompleteMatches
                        && ranksCompleteCandidateSet
                        && rankedMatches.matchedIndexes.count <= completeMatchCacheMatchedLimit
                )
                if shouldRunFullScanFallback(
                    topRankedIsEmpty: ranked.topRanked.isEmpty,
                    candidatePlan: candidatePlan,
                    totalCount: input.appEntries.count
                ) {
                    guard let fullScanRanked = rankAppMatches(
                        query: query,
                        entries: input.appEntries,
                        candidateIndexes: Array(input.appEntries.indices),
                        topResultLimit: Self.appTopResultLimit
                    ) else { return nil }
                    if !fullScanRanked.topRanked.isEmpty {
                        RuntimeLog.info(
                            .search,
                            "scope=app query=\"\(query.normalized)\" recallFallback=fullScan initialCandidates=\(candidateIndexes.count) totalEntries=\(input.appEntries.count) recoveredResults=\(fullScanRanked.topRanked.count)"
                        )
                    }
                    ranked = (
                        matchedIndexes: fullScanRanked.matchedIndexes,
                        topRanked: fullScanRanked.topRanked,
                        matchedIndexesAreComplete: fullScanRanked.matchedIndexes.count <= completeMatchCacheMatchedLimit
                    )
                }
                let matchedIndexes = ranked.matchedIndexes
                guard let topResults = cancellableMap(
                    ranked.topRanked,
                    transform: { ranked in
                    let app = input.appEntries[ranked.order]
                    return SwitcherSearchResult(
                        id: "app:\(app.appID)",
                        kind: .app(appID: app.appID),
                        primaryText: app.appDisplayName,
                        secondaryText: nil
                    )
                }) else { return nil }
                let cachePolicy = cachePolicy(
                    for: query.normalized,
                    matchedIndexesAreComplete: ranked.matchedIndexesAreComplete
                )
                appCache = updatedCache(
                    appCache,
                    query: query.normalized,
                    matchedIndexes: boundedMatchedIndexes(
                        matchedIndexes,
                        limit: cachePolicy.matchedIndexesLimit
                    ),
                    matchedIndexesAreComplete: ranked.matchedIndexesAreComplete,
                    topResults: topResults,
                    limit: cachePolicy.entryLimit,
                    persistEntry: cachePolicy.persistEntry
                )
                if topResults.isEmpty, RuntimeLog.isDebugEnabled(for: .search) {
                    logEmptySearchDiagnostics(
                        scope: .app,
                        query: query,
                        candidateCount: candidateIndexes.count,
                        boundedCandidateCount: boundedCandidateIndexes.count,
                        matchedCount: matchedIndexes.count,
                        topResultCount: topResults.count
                    )
                }
                rebuilt = topResults
            }
        case .window:
            if query.normalized.isEmpty {
                windowCache = nil
                guard let allWindows = cancellableMap(
                    input.windowEntries,
                    transform: { window in
                    let resolvedTitle = window.windowTitle.isEmpty ? "Untitled Window" : window.windowTitle
                    return SwitcherSearchResult(
                        id: "window:\(window.appID)#\(window.windowID)",
                        kind: .window(appID: window.appID, windowID: window.windowID),
                        primaryText: resolvedTitle,
                        secondaryText: window.appDisplayName
                    )
                }) else { return nil }
                rebuilt = allWindows
            } else if
                let cache = windowCache,
                let cachedEntry = cache.entries[query.normalized]
            {
                windowCache = touchedCache(
                    cache,
                    query: query.normalized,
                    latestMatchedIndexes: cachedEntry.matchedIndexes,
                    latestMatchedIndexesAreComplete: cachedEntry.matchedIndexesAreComplete
                )
                if cachedEntry.topResults.isEmpty {
                    RuntimeLog.debug(
                        .search,
                        "scope=window query=\"\(query.normalized)\" source=cache matched=\(cachedEntry.matchedIndexes.count) topResults=0"
                    )
                }
                rebuilt = cachedEntry.topResults
            } else {
                let candidatePlan = candidateIndexPlan(
                    query: query,
                    cache: windowCache,
                    invertedIndex: input.windowInvertedIndex,
                    totalCount: input.windowEntries.count
                )
                guard !Task.isCancelled else { return nil }
                let candidateIndexes = candidatePlan.indexes
                let boundedCandidateIndexes = boundedCandidateIndexes(candidateIndexes, scope: .window, query: query)
                let ranksCompleteCandidateSet = candidateIndexes.count == boundedCandidateIndexes.count
                guard let rankedMatches = rankWindowMatches(
                    query: query,
                    entries: input.windowEntries,
                    candidateIndexes: ranksCompleteCandidateSet ? candidateIndexes : boundedCandidateIndexes,
                    topResultLimit: Self.windowTopResultLimit
                ) else { return nil }
                var ranked = (
                    matchedIndexes: rankedMatches.matchedIndexes,
                    topRanked: rankedMatches.topRanked,
                    matchedIndexesAreComplete: candidatePlan.canCacheCompleteMatches
                        && ranksCompleteCandidateSet
                        && rankedMatches.matchedIndexes.count <= completeMatchCacheMatchedLimit
                )
                if shouldRunFullScanFallback(
                    topRankedIsEmpty: ranked.topRanked.isEmpty,
                    candidatePlan: candidatePlan,
                    totalCount: input.windowEntries.count
                ) {
                    guard let fullScanRanked = rankWindowMatches(
                        query: query,
                        entries: input.windowEntries,
                        candidateIndexes: Array(input.windowEntries.indices),
                        topResultLimit: Self.windowTopResultLimit
                    ) else { return nil }
                    if !fullScanRanked.topRanked.isEmpty {
                        RuntimeLog.info(
                            .search,
                            "scope=window query=\"\(query.normalized)\" recallFallback=fullScan initialCandidates=\(candidateIndexes.count) totalEntries=\(input.windowEntries.count) recoveredResults=\(fullScanRanked.topRanked.count)"
                        )
                    }
                    ranked = (
                        matchedIndexes: fullScanRanked.matchedIndexes,
                        topRanked: fullScanRanked.topRanked,
                        matchedIndexesAreComplete: fullScanRanked.matchedIndexes.count <= completeMatchCacheMatchedLimit
                    )
                }
                let matchedIndexes = ranked.matchedIndexes
                guard let topResults = cancellableMap(
                    ranked.topRanked,
                    transform: { ranked in
                    let window = input.windowEntries[ranked.order]
                    let resolvedTitle = window.windowTitle.isEmpty ? "Untitled Window" : window.windowTitle
                    return SwitcherSearchResult(
                        id: "window:\(window.appID)#\(window.windowID)",
                        kind: .window(appID: window.appID, windowID: window.windowID),
                        primaryText: resolvedTitle,
                        secondaryText: window.appDisplayName
                    )
                }) else { return nil }
                let cachePolicy = cachePolicy(
                    for: query.normalized,
                    matchedIndexesAreComplete: ranked.matchedIndexesAreComplete
                )
                windowCache = updatedCache(
                    windowCache,
                    query: query.normalized,
                    matchedIndexes: boundedMatchedIndexes(
                        matchedIndexes,
                        limit: cachePolicy.matchedIndexesLimit
                    ),
                    matchedIndexesAreComplete: ranked.matchedIndexesAreComplete,
                    topResults: topResults,
                    limit: cachePolicy.entryLimit,
                    persistEntry: cachePolicy.persistEntry
                )
                if topResults.isEmpty, RuntimeLog.isDebugEnabled(for: .search) {
                    logEmptySearchDiagnostics(
                        scope: .window,
                        query: query,
                        candidateCount: candidateIndexes.count,
                        boundedCandidateCount: boundedCandidateIndexes.count,
                        matchedCount: matchedIndexes.count,
                        topResultCount: topResults.count
                    )
                }
                rebuilt = topResults
            }
        }

        guard !Task.isCancelled else { return nil }
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

    private static func cancellableMap<Element, Result>(
        _ values: [Element],
        transform: (Element) -> Result
    ) -> [Result]? {
        var results: [Result] = []
        results.reserveCapacity(values.count)
        for (offset, value) in values.enumerated() {
            if offset.isMultiple(of: 32), Task.isCancelled {
                return nil
            }
            results.append(transform(value))
        }
        return Task.isCancelled ? nil : results
    }

    static func candidateIndexPlan(
        query: SearchKey,
        cache: ScopeMatchCache?,
        invertedIndex: ScopeInvertedIndex,
        totalCount: Int
    ) -> CandidateIndexPlan {
        if let cache {
            if
                !cache.latestQuery.isEmpty,
                query.normalized == cache.latestQuery
            {
                return CandidateIndexPlan(
                    indexes: cache.latestMatchedIndexes,
                    canCacheCompleteMatches: cache.latestMatchedIndexesAreComplete
                )
            }
            if
                !cache.latestQuery.isEmpty,
                query.normalized.hasPrefix(cache.latestQuery)
            {
                if cache.latestMatchedIndexesAreComplete {
                    return CandidateIndexPlan(
                        indexes: cache.latestMatchedIndexes,
                        canCacheCompleteMatches: true
                    )
                }
                return supplementedPrefixCandidatePlan(
                    cachedIndexes: cache.latestMatchedIndexes,
                    query: query,
                    invertedIndex: invertedIndex,
                    totalCount: totalCount
                )
            }
            if
                let exactEntry = cache.entries[query.normalized],
                exactEntry.matchedIndexesAreComplete
            {
                return CandidateIndexPlan(
                    indexes: exactEntry.matchedIndexes,
                    canCacheCompleteMatches: exactEntry.matchedIndexesAreComplete
                )
            }

            var prefix = query.normalized
            while !prefix.isEmpty {
                if Task.isCancelled {
                    return CandidateIndexPlan(
                        indexes: [],
                        canCacheCompleteMatches: false
                    )
                }
                prefix.removeLast()
                if let entry = cache.entries[prefix] {
                    if entry.matchedIndexesAreComplete {
                        return CandidateIndexPlan(
                            indexes: entry.matchedIndexes,
                            canCacheCompleteMatches: true
                        )
                    }
                    return supplementedPrefixCandidatePlan(
                        cachedIndexes: entry.matchedIndexes,
                        query: query,
                        invertedIndex: invertedIndex,
                        totalCount: totalCount
                    )
                }
            }
        }

        return CandidateIndexPlan(
            indexes: indexedCandidates(query: query, invertedIndex: invertedIndex, totalCount: totalCount),
            canCacheCompleteMatches: true
        )
    }

    static func shouldRunFullScanFallback(
        topRankedIsEmpty: Bool,
        candidatePlan: CandidateIndexPlan,
        totalCount: Int
    ) -> Bool {
        topRankedIsEmpty
            && candidatePlan.indexes.count < totalCount
            && (!candidatePlan.canCacheCompleteMatches || !candidatePlan.indexes.isEmpty)
    }

    static func supplementedPrefixCandidatePlan(
        cachedIndexes: [Int],
        query: SearchKey,
        invertedIndex: ScopeInvertedIndex,
        totalCount: Int
    ) -> CandidateIndexPlan {
        let supplementalIndexes = indexedCandidates(
            query: query,
            invertedIndex: invertedIndex,
            totalCount: totalCount,
            limit: prefixSupplementCandidateLimit
        )
        return CandidateIndexPlan(
            indexes: mergedCandidateIndexes(primary: supplementalIndexes, supplemental: cachedIndexes),
            canCacheCompleteMatches: false
        )
    }

    static func indexedCandidates(
        query: SearchKey,
        invertedIndex: ScopeInvertedIndex,
        totalCount: Int,
        limit: Int? = nil
    ) -> [Int] {
        let coarse: [Int]
        if let limit, limit > 0 {
            coarse = limitedCoarseCandidates(query: query, invertedIndex: invertedIndex, limit: limit)
        } else {
            coarse = coarseFilter(query: query, invertedIndex: invertedIndex)
        }
        if coarse.isEmpty {
            if emptyCoarseFilterProvesCompleteMiss(query) {
                return []
            }
            if let limit, limit > 0 {
                return Array((0..<totalCount).prefix(limit))
            }
            return Array(0..<totalCount)
        }
        return coarse
    }

    static func emptyCoarseFilterProvesCompleteMiss(_ query: SearchKey) -> Bool {
        query.terms.count == 1 && query.compact.count >= 2
    }

    static func mergedCandidateIndexes(primary: [Int], supplemental: [Int]) -> [Int] {
        guard !primary.isEmpty else { return supplemental }
        guard !supplemental.isEmpty else { return primary }

        var seen = Set(primary)
        var merged = primary
        merged.reserveCapacity(primary.count + supplemental.count)
        for index in supplemental where seen.insert(index).inserted {
            merged.append(index)
        }
        return merged
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
        for normalizedQuery: String,
        matchedIndexesAreComplete: Bool
    ) -> (entryLimit: Int, matchedIndexesLimit: Int, persistEntry: Bool) {
        let compactLength = compactToken(normalizedQuery).count
        let budgetedMatchedIndexesLimit = compactLength <= shortQueryThreshold
            ? shortQueryMatchedIndexesLimit
            : longQueryMatchedIndexesLimit
        let matchedIndexesLimit = matchedIndexesAreComplete ? 0 : budgetedMatchedIndexesLimit
        if compactLength <= 1 {
            return (
                entryLimit: 0,
                matchedIndexesLimit: matchedIndexesLimit,
                persistEntry: false
            )
        }
        if compactLength <= shortQueryThreshold {
            return (
                entryLimit: shortQueryCacheEntryLimit,
                matchedIndexesLimit: matchedIndexesLimit,
                persistEntry: true
            )
        }
        return (
            entryLimit: scopeMatchCacheEntryLimit,
            matchedIndexesLimit: matchedIndexesLimit,
            persistEntry: true
        )
    }

    static func logEmptySearchDiagnostics(
        scope: SwitcherSearchScope,
        query: SearchKey,
        candidateCount: Int,
        boundedCandidateCount: Int,
        matchedCount: Int,
        topResultCount: Int
    ) {
        RuntimeLog.debug(
            .search,
            "scope=\(scope.rawValue) query=\"\(query.normalized)\" compact=\"\(query.compact)\" terms=\(query.terms) candidateIndexes=\(candidateCount) boundedCandidates=\(boundedCandidateCount) matched=\(matchedCount) topResults=\(topResultCount)"
        )
    }

    static func limitedCoarseCandidates(
        query: SearchKey,
        invertedIndex: ScopeInvertedIndex,
        limit: Int
    ) -> [Int] {
        guard limit > 0 else { return [] }
        var selected: [Int] = []
        selected.reserveCapacity(limit)
        var seen: Set<Int> = []

        func appendPosting(_ posting: [Int]) {
            for (offset, index) in posting.enumerated()
                where seen.insert(index).inserted
            {
                if offset.isMultiple(of: 32), Task.isCancelled {
                    return
                }
                selected.append(index)
                if selected.count >= limit {
                    return
                }
            }
        }

        let dedupTerms = orderedUniqueSearchTerms(
            query.terms + [query.compact, query.normalized].filter { !$0.isEmpty }
        )
        for term in dedupTerms where !term.isEmpty {
            guard let posting = invertedIndex.termPostings[term] else { continue }
            appendPosting(posting)
            if Task.isCancelled { return [] }
            if selected.count >= limit {
                return selected
            }
        }

        for gram in bigrams(of: query.compact) {
            guard let posting = invertedIndex.bigramPostings[gram] else { continue }
            appendPosting(posting)
            if Task.isCancelled { return [] }
            if selected.count >= limit {
                return selected
            }
        }

        return selected
    }

    static func orderedUniqueSearchTerms(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        result.reserveCapacity(values.count)
        for value in values where !value.isEmpty && seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }

    static func coarseFilter(
        query: SearchKey,
        invertedIndex: ScopeInvertedIndex
    ) -> [Int] {
        var weights: [Int: Int] = [:]
        var gramHits: [Int: Int] = [:]

        let dedupTerms = Set(query.terms + [query.compact, query.normalized].filter { !$0.isEmpty })
        for term in dedupTerms where !term.isEmpty {
            if Task.isCancelled { return [] }
            guard let posting = invertedIndex.termPostings[term] else { continue }
            for (offset, index) in posting.enumerated() {
                if offset.isMultiple(of: 32), Task.isCancelled {
                    return []
                }
                weights[index, default: 0] += 4
            }
        }

        let grams = bigrams(of: query.compact)
        for gram in grams {
            if Task.isCancelled { return [] }
            guard let posting = invertedIndex.bigramPostings[gram] else { continue }
            for (offset, index) in posting.enumerated() {
                if offset.isMultiple(of: 32), Task.isCancelled {
                    return []
                }
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

        guard !Task.isCancelled else { return [] }
        let sorted = selected.sorted { lhs, rhs in
            isBetterCoarseCandidate(lhs, than: rhs)
        }
        return sorted.map(\.0)
    }

    static func isBetterCoarseCandidate(_ lhs: (Int, Int), than rhs: (Int, Int)) -> Bool {
        if lhs.1 != rhs.1 {
            return lhs.1 > rhs.1
        }
        return lhs.0 < rhs.0
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
        latestMatchedIndexes: [Int],
        latestMatchedIndexesAreComplete: Bool
    ) -> ScopeMatchCache {
        var lruOrder = cache.lruOrder
        lruOrder.removeAll { $0 == query }
        lruOrder.append(query)
        return ScopeMatchCache(
            latestQuery: query,
            latestMatchedIndexes: latestMatchedIndexes,
            latestMatchedIndexesAreComplete: latestMatchedIndexesAreComplete,
            entries: cache.entries,
            lruOrder: lruOrder
        )
    }

    static func updatedCache(
        _ existing: ScopeMatchCache?,
        query: String,
        matchedIndexes: [Int],
        matchedIndexesAreComplete: Bool,
        topResults: [SwitcherSearchResult],
        limit: Int,
        persistEntry: Bool
    ) -> ScopeMatchCache {
        var entries = existing?.entries ?? [:]
        var lruOrder = existing?.lruOrder ?? []

        if persistEntry {
            entries[query] = QueryCacheEntry(
                matchedIndexes: matchedIndexes,
                matchedIndexesAreComplete: matchedIndexesAreComplete,
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
            latestMatchedIndexesAreComplete: matchedIndexesAreComplete,
            entries: entries,
            lruOrder: lruOrder
        )
    }
}
