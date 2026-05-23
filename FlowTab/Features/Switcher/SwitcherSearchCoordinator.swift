import Foundation
import NaturalLanguage
import FlowTabCore

enum SwitcherSearchScope: String, CaseIterable, Equatable, Sendable {
    case app
    case window

    var label: String {
        switch self {
        case .app:
            return AppStrings.text(.searchScopeApp)
        case .window:
            return AppStrings.text(.searchScopeWindow)
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
    typealias SearchKey = SearchTextMatcher.Key
    typealias SearchIndex = SearchTextMatcher.Index
    typealias RankedResult = SearchTextMatcher.RankedResult

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

    struct QueryCacheEntry: Sendable {
        let matchedIndexes: [Int]
        let matchedIndexesAreComplete: Bool
        let topResults: [SwitcherSearchResult]
    }

    struct ScopeMatchCache: Sendable {
        let latestQuery: String
        let latestMatchedIndexes: [Int]
        let latestMatchedIndexesAreComplete: Bool
        let entries: [String: QueryCacheEntry]
        let lruOrder: [String]
    }

    struct ScopeInvertedIndex: Sendable {
        let termPostings: [String: [Int]]
        let bigramPostings: [String: [Int]]
    }

    struct CandidateIndexPlan: Sendable {
        let indexes: [Int]
        let canCacheCompleteMatches: Bool
    }

    struct ComputationInput: Sendable {
        let query: String
        let scope: SwitcherSearchScope
        let selectedResultIndex: Int
        let resetSelection: Bool
        let appEntries: [AppEntry]
        let windowEntries: [WindowEntry]
        let appMatchCache: ScopeMatchCache?
        let windowMatchCache: ScopeMatchCache?
        let appInvertedIndex: ScopeInvertedIndex
        let windowInvertedIndex: ScopeInvertedIndex
    }

    struct ComputationOutput: Sendable {
        let query: String
        let scope: SwitcherSearchScope
        let results: [SwitcherSearchResult]
        let selectedResultIndex: Int
        let appMatchCache: ScopeMatchCache?
        let windowMatchCache: ScopeMatchCache?
    }

    private(set) var state: SwitcherSearchViewState = .inactive

    var appEntries: [AppEntry] = []
    var windowEntries: [WindowEntry] = []
    var appMatchCache: ScopeMatchCache?
    var windowMatchCache: ScopeMatchCache?
    var appInvertedIndex = ScopeInvertedIndex(termPostings: [:], bigramPostings: [:])
    var windowInvertedIndex = ScopeInvertedIndex(termPostings: [:], bigramPostings: [:])
    var pendingRebuildWorkItem: DispatchWorkItem?
    var pendingRebuildResetSelection: Bool = false
    var pendingRebuildGeneration: UInt64 = 0
    static let scopeMatchCacheEntryLimit: Int = 32
    static let shortQueryCacheEntryLimit: Int = 12
    static let appTopResultLimit: Int = 300
    static let windowTopResultLimit: Int = 400
    static let completeMatchCacheMatchedLimit: Int = 250
    static let prefixSupplementCandidateLimit: Int = 256
    static let appCandidateLimitShortQuery: Int = 1_000
    static let appCandidateLimitLongQuery: Int = 1_600
    static let windowCandidateLimitShortQuery: Int = 1_200
    static let windowCandidateLimitLongQuery: Int = 2_000
    static let shortQueryMatchedIndexesLimit: Int = 512
    static let longQueryMatchedIndexesLimit: Int = 2_000
    static let shortQueryThreshold: Int = 2
    static let queryDebounceNanoseconds: UInt64 = 10_000_000

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
                window.windowSearchIndex.mergingCoarseTerms(with: window.appSearchIndex)
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
    func selectResult(withID id: String) -> Bool {
        guard state.isActive else { return false }
        guard let index = state.results.firstIndex(where: { $0.id == id }) else { return false }
        state.isInputFocused = false
        state.selectedResultIndex = index
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

    func rebuildResults(resetSelection: Bool) {
        guard let input = makeComputationInput(resetSelection: resetSelection) else { return }
        let output = Self.computeOutput(from: input)
        _ = applyComputationOutput(output)
    }

    func flushPendingRebuild() {
        guard pendingRebuildWorkItem != nil else { return }
        pendingRebuildWorkItem?.cancel()
        pendingRebuildWorkItem = nil
        pendingRebuildGeneration &+= 1
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
    func cancelPendingRebuild() {
        pendingRebuildWorkItem?.cancel()
        pendingRebuildWorkItem = nil
        pendingRebuildResetSelection = false
        pendingRebuildGeneration &+= 1
    }

    func scheduleRebuild(resetSelection: Bool, debounced: Bool) {
        guard state.isActive else { return }
        pendingRebuildResetSelection = pendingRebuildResetSelection || resetSelection
        pendingRebuildWorkItem?.cancel()
        pendingRebuildGeneration &+= 1
        let scheduledGeneration = pendingRebuildGeneration

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.pendingRebuildGeneration == scheduledGeneration else { return }
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
