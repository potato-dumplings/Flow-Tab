import AppKit
import Carbon
import CoreGraphics
import SwiftUI
import FlowTabCore

extension LiveSwitcherModel {
    @discardableResult
    func enterSearchMode() -> Bool {
        guard SearchInteractionPreferencesStore.loadIsEnabled() else { return false }
        guard overlayStyle == .appAndWindow else { return false }
        guard let session, case .appCycle = session.mode else { return false }
        cancelPendingSearchComputation()
        sessionAppsByID = Dictionary(uniqueKeysWithValues: session.apps.map { ($0.id, $0) })
        guard rebuildSearchIndexFromCommittedProjection(reason: "enterSearchMode") else {
            RuntimeLog.debug(
                .searchModel,
                "enterSearchMode changed=0 reason=noCommittedSearchIndex sessionAppCount=\(session.apps.count)"
            )
            return false
        }
        let defaultScope = SearchInteractionPreferencesStore.loadDefaultScope()
        let changed = searchCoordinator.activate(defaultScope: defaultScope)
        publishSearchStateIfNeeded()
        RuntimeLog.debug(
            .searchModel,
            "enterSearchMode changed=\(changed ? 1 : 0) scope=\(defaultScope.rawValue) appCount=\(session.apps.count) inputFocused=\(searchViewState.isInputFocused ? 1 : 0)"
        )
        return changed
    }

    @discardableResult
    func toggleSearchScope() -> Bool {
        cancelPendingSearchComputation()
        let changed = searchCoordinator.toggleScopeWithoutRebuild()
        guard changed else { return false }
        publishSearchStateIfNeeded()
        scheduleSearchComputation(resetSelection: true, debounced: false)
        return true
    }

    @discardableResult
    func rebuildSearchIndexFromCommittedProjection(reason: String) -> Bool {
        let read = runtimeProjectionService.readCommittedSearchIndexForSearch()
        guard let projection = read.projection else {
            committedSearchAppsByID = [:]
            if read.shouldRequestFreshnessBarrier {
                runtimeProjectionService.requestSearchIndexFreshnessBarrier(reason: .searchFreshnessBarrier)
            }
            lastSearchIndexReadDiagnostic = SearchIndexReadDiagnostic(
                reason: reason,
                readiness: read.readiness,
                resultState: read.resultState,
                appCount: 0,
                windowCount: 0,
                committedIndexCoversCurrentGeneration: read.committedIndexCoversCurrentGeneration,
                dirtyAppCount: 0,
                dirtyPIDCount: 0,
                dirtyCGWindowIDCount: 0,
                pendingRepairScopeCount: 0,
                requestedFreshnessBarrier: read.shouldRequestFreshnessBarrier
            )
            RuntimeLog.debug(
                .searchModel,
                "searchIndexSource reason=\(reason) source=none readiness=\(read.readiness.rawValue) resultState=\(read.resultState.rawValue) freshnessBarrierRequested=\(read.shouldRequestFreshnessBarrier ? 1 : 0)"
            )
            return false
        }
        if read.shouldRequestFreshnessBarrier {
            runtimeProjectionService.requestSearchIndexFreshnessBarrier(reason: .searchFreshnessBarrier)
        }
        let searchProjection = projection.filteringApps(
            using: AppVisibilityPreferencesStore.visibilityFilter()
        )
        committedSearchAppsByID = Self.committedSearchAppsByID(from: searchProjection)
        let indexStatus = SwitcherSearchIndexStatus(read: read)
        let diagnostic = SearchIndexReadDiagnostic(
            reason: reason,
            readiness: indexStatus.readiness,
            resultState: indexStatus.resultState,
            appCount: searchProjection.appEntries.count,
            windowCount: searchProjection.windowEntries.count,
            committedIndexCoversCurrentGeneration: indexStatus.committedIndexCoversCurrentGeneration,
            dirtyAppCount: projection.freshness.dirtyAppIDs.count,
            dirtyPIDCount: projection.freshness.dirtyPIDs.count,
            dirtyCGWindowIDCount: projection.freshness.dirtyCGWindowIDs.count,
            pendingRepairScopeCount: projection.freshness.pendingRepairScopes.count,
            requestedFreshnessBarrier: indexStatus.requestedFreshnessBarrier
        )
        lastSearchIndexReadDiagnostic = diagnostic
        searchCoordinator.rebuildIndex(with: searchProjection, indexStatus: indexStatus)
        RuntimeLog.debug(.searchModel, diagnostic.logMessage)
        return true
    }

    private static func committedSearchAppsByID(
        from projection: RuntimeSearchIndexProjection
    ) -> [String: AppSwitchCandidate] {
        let windowsByAppID = Dictionary(grouping: projection.windowEntries, by: \.appID)
            .mapValues { entries in
                entries.map { entry in
                    WindowCandidate(
                        id: entry.windowID,
                        title: entry.windowTitle,
                        isMinimized: entry.windowIsMinimized,
                        lastActiveAt: entry.windowLastActiveAt
                    )
                }
            }
        return Dictionary(
            projection.appEntries.map { entry in
                (
                    entry.appID,
                    AppSwitchCandidate(
                        id: entry.appID,
                        displayName: entry.appDisplayName,
                        groupID: entry.appGroupID,
                        lastActiveAt: entry.appLastActiveAt,
                        windows: windowsByAppID[entry.appID] ?? []
                    )
                )
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    @discardableResult
    func focusSearchResults() -> Bool {
        let changed = searchCoordinator.focusResults()
        publishSearchStateIfNeeded()
        return changed
    }

    @discardableResult
    func focusSearchInput() -> Bool {
        let changed = searchCoordinator.focusInput()
        publishSearchStateIfNeeded()
        return changed
    }

    @discardableResult
    func moveSearchSelection(by delta: Int) -> Bool {
        let changed = searchCoordinator.moveSelection(by: delta)
        publishSearchStateIfNeeded()
        return changed
    }

    @discardableResult
    func selectSearchResult(withID id: String) -> Bool {
        let changed = searchCoordinator.selectResult(withID: id)
        publishSearchStateIfNeeded()
        return changed
    }

    @discardableResult
    func stepSearchSelectionDown() -> Bool {
        if searchViewState.isInputFocused {
            return focusSearchResults()
        }
        return moveSearchSelection(by: +1)
    }

    @discardableResult
    func stepSearchSelectionUp() -> Bool {
        guard !searchViewState.isInputFocused else { return false }
        if searchViewState.selectedResultIndex == 0 {
            return focusSearchInput()
        }
        return moveSearchSelection(by: -1)
    }

    @discardableResult
    func moveSearchQueryCursor(by delta: Int) -> Bool {
        let changed = searchCoordinator.moveQueryCursor(by: delta)
        publishSearchStateIfNeeded()
        return changed
    }

    func synchronizeSearchInput(query: String, cursorPosition: Int) {
        guard searchViewState.isActive else { return }
        let previousQuery = searchCoordinator.state.query
        let changed = searchCoordinator.replaceQueryWithoutRebuild(
            query,
            cursorPosition: cursorPosition
        )
        guard changed else { return }
        publishSearchStateIfNeeded()
        RuntimeLog.debug(
            .searchModel,
            "synchronizeSearchInput query=\(query.debugDescription) cursor=\(cursorPosition) previousQuery=\(previousQuery.debugDescription) active=\(searchViewState.isActive ? 1 : 0) inputFocused=\(searchViewState.isInputFocused ? 1 : 0)"
        )
        guard previousQuery != searchCoordinator.state.query else { return }
        scheduleSearchComputation(resetSelection: true, debounced: true)
    }

    func updateSearchInputMarkedTextState(_ hasMarkedText: Bool) {
        let nextValue = searchViewState.isActive ? hasMarkedText : false
        guard searchInputHasMarkedText != nextValue else { return }
        searchInputHasMarkedText = nextValue
        RuntimeLog.debug(
            .searchModel,
            "markedText changed=\(nextValue ? 1 : 0) active=\(searchViewState.isActive ? 1 : 0) inputFocused=\(searchViewState.isInputFocused ? 1 : 0) query=\(searchViewState.query.debugDescription)"
        )
    }

    @discardableResult
    func appendSearchQuery(_ value: String) -> Bool {
        let changed = searchCoordinator.appendQueryTextWithoutRebuild(value)
        guard changed else { return false }
        publishSearchStateIfNeeded()
        scheduleSearchComputation(resetSelection: true, debounced: true)
        return true
    }

    @discardableResult
    func deleteSearchQueryBackward() -> Bool {
        let changed = searchCoordinator.deleteBackwardInQueryWithoutRebuild()
        guard changed else { return false }
        publishSearchStateIfNeeded()
        scheduleSearchComputation(resetSelection: true, debounced: true)
        return true
    }

    func handleSearchEscape() -> SwitcherSearchEscapeAction {
        cancelPendingSearchComputation()
        let action = searchCoordinator.handleEscape()
        publishSearchStateIfNeeded()
        return action
    }

    @discardableResult
    func applySelectedSearchResultToSession() -> Bool {
        guard var session else { return false }
        flushCurrentSearchComputationForCommit()
        guard let selected = searchViewState.selectedResult else { return false }

        switch selected.kind {
        case .app(let appID):
            if !session.selectApp(withID: appID) {
                guard let committedApp = committedSearchAppsByID[appID] else { return false }
                session = Self.sessionByApplyingCommittedSearchTarget(
                    committedApp,
                    to: session
                )
                guard session.selectApp(withID: appID) else { return false }
            }
        case .window(let appID, let windowID):
            if !session.selectWindow(appID: appID, windowID: windowID) {
                guard
                    let committedApp = committedSearchAppsByID[appID],
                    committedApp.windows.contains(where: { $0.id == windowID })
                else {
                    return false
                }
                session = Self.sessionByApplyingCommittedSearchTarget(
                    committedApp,
                    to: session
                )
                guard session.selectWindow(appID: appID, windowID: windowID) else {
                    return false
                }
            }
        }

        autoEnterSuppressedAppID = nil
        cancelPendingSearchComputation()
        self.session = session
        _ = searchCoordinator.exit()
        publishSearchStateIfNeeded()
        return true
    }

    private static func sessionByApplyingCommittedSearchTarget(
        _ committedApp: AppSwitchCandidate,
        to session: SwitcherSession
    ) -> SwitcherSession {
        var apps = session.apps
        if let index = apps.firstIndex(where: { $0.id == committedApp.id }) {
            apps[index] = committedApp
        } else {
            apps.append(committedApp)
        }
        return SwitcherSession(
            apps: apps,
            preferences: session.preferences,
            triggerDirection: .forward,
            rememberedWindowIDByAppID: session.rememberedWindowIDByAppID
        )
    }

    func flushCurrentSearchComputationForCommit() {
        let shouldResetSelection = pendingSearchComputationTask != nil
        cancelPendingSearchComputation()
        searchCoordinator.rebuildResults(resetSelection: shouldResetSelection)
        publishSearchStateIfNeeded()
    }

    func scheduleSearchComputation(resetSelection: Bool, debounced: Bool) {
        guard searchViewState.isActive else { return }
        pendingSearchComputationTask?.cancel()
        searchComputationRevision &+= 1
        let revision = searchComputationRevision
        guard let input = searchCoordinator.makeComputationInput(resetSelection: resetSelection) else {
            return
        }
        let debounceDelay = debounced ? searchDebounceNanoseconds : 0

        pendingSearchComputationTask = Task { [weak self] in
            guard let self else { return }
            if debounceDelay > 0 {
                try? await Task.sleep(nanoseconds: debounceDelay)
            }
            guard !Task.isCancelled else { return }

            let startedAt = DispatchTime.now().uptimeNanoseconds
            let output = await Task.detached(priority: .userInitiated) {
                SwitcherSearchCoordinator.computeOutput(from: input)
            }.value
            let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt

            await MainActor.run {
                guard revision == self.searchComputationRevision else { return }
                self.pendingSearchComputationTask = nil
                if self.searchCoordinator.applyComputationOutput(output) {
                    self.publishSearchStateIfNeeded()
                    self.onSearchStateChanged?()
                }
                self.updateSearchDebounceWindow(lastComputationNanoseconds: elapsed)
            }
        }
    }

    func updateSearchDebounceWindow(lastComputationNanoseconds: UInt64) {
        let elapsedMilliseconds = Double(lastComputationNanoseconds) / 1_000_000
        if elapsedMilliseconds > 16 {
            searchDebounceNanoseconds = 45_000_000
        } else if elapsedMilliseconds > 10 {
            searchDebounceNanoseconds = 35_000_000
        } else if elapsedMilliseconds > 6 {
            searchDebounceNanoseconds = 25_000_000
        } else {
            searchDebounceNanoseconds = 14_000_000
        }
    }

    func publishSearchStateIfNeeded() {
        let newState = searchCoordinator.state
        let shouldBumpScrollRevision = shouldBumpSearchResultScrollRevision(
            from: searchViewState,
            to: newState
        )
        if !newState.isActive {
            searchInputHasMarkedText = false
        }
        guard searchViewState != newState else { return }
        searchViewState = newState
        if shouldBumpScrollRevision {
            searchResultScrollRevision &+= 1
        }
    }
}
