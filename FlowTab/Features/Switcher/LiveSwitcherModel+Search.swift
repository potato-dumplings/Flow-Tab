import AppKit
import Carbon
import CoreGraphics
import SwiftUI
import FlowTabCore

extension LiveSwitcherModel {
    @discardableResult
    func startSearchSession(triggerDirection: CycleDirection) -> Bool {
        guard SearchInteractionPreferencesStore.loadIsEnabled() else { return false }
        invalidateSelectedAppWindowProjection(reason: .startSession)
        clearTerminateSelectedAppAnimation()
        overlayStyle = .appAndWindow
        titleBarStyleInferenceEnabled = false

        if loadFastAppSwitcherProjectionSession(
            triggerDirection: triggerDirection,
            preferredSelectedAppID: nil
        ) {
            requestRuntimeProjectionMaintenance(triggerDirection: triggerDirection)
            return enterSearchMode()
        }

        requestRuntimeProjectionMaintenance(triggerDirection: triggerDirection)
        guard startSearchSessionFromCommittedIndex(triggerDirection: triggerDirection) else {
            pendingSearchActivationAfterFreshnessBarrier =
                lastSearchIndexReadDiagnostic?.requestedFreshnessBarrier == true
            return false
        }
        return enterSearchMode()
    }

    @discardableResult
    func enterSearchMode() -> Bool {
        guard SearchInteractionPreferencesStore.loadIsEnabled() else { return false }
        guard overlayStyle == .appAndWindow else { return false }
        guard let session, case .appCycle = session.mode else { return false }
        let freshnessBarrierWasPending = pendingSearchActivationAfterFreshnessBarrier
        cancelPendingSearchComputation()
        pendingSearchActivationAfterFreshnessBarrier = true
        sessionAppsByID = Dictionary(uniqueKeysWithValues: session.apps.map { ($0.id, $0) })
        guard rebuildSearchIndexFromCommittedProjection(
            reason: "enterSearchMode",
            requestFreshnessBarrierIfNeeded: !freshnessBarrierWasPending
        ) else {
            pendingSearchActivationAfterFreshnessBarrier = freshnessBarrierWasPending
                || lastSearchIndexReadDiagnostic?.requestedFreshnessBarrier == true
            RuntimeLog.debug(
                .searchModel,
                "enterSearchMode changed=0 reason=noCommittedSearchIndex sessionAppCount=\(session.apps.count)"
            )
            return false
        }
        pendingSearchActivationAfterFreshnessBarrier = false
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
    private func startSearchSessionFromCommittedIndex(triggerDirection: CycleDirection) -> Bool {
        let read = runtimeProjectionService.readCommittedSearchIndexForSearch()
        guard let projection = read.projection else {
            _ = rebuildSearchIndexFromCommittedProjection(reason: "startSearchSession")
            return false
        }

        let searchProjection = projection.filteringApps(
            using: AppVisibilityPreferencesStore.visibilityFilter()
        )
        let apps = Self.committedSearchSessionApps(from: searchProjection)
        guard !apps.isEmpty else {
            _ = rebuildSearchIndexFromCommittedProjection(reason: "startSearchSession")
            return false
        }

        runtimeContextsByID = [:]
        clearPreviewSnapshotState()
        autoEnterSuppressedAppID = nil
        let preferences = SwitcherBehaviorPreferencesStore.loadSwitcherPreferences()
        session = SwitcherSession(
            apps: apps,
            preferences: preferences,
            triggerDirection: triggerDirection,
            rememberedWindowIDByAppID: rememberedWindowIDByAppID
        )
        RuntimeLog.debug(
            .searchModel,
            "startSearchSession source=committedRuntimeIndex readiness=\(read.readiness.rawValue) resultState=\(read.resultState.rawValue) apps=\(apps.count) windows=\(apps.reduce(0) { $0 + $1.windows.count })"
        )
        return true
    }

    @discardableResult
    func handleCommittedSearchIndexDidUpdate() -> Bool {
        if pendingSearchActivationAfterFreshnessBarrier {
            return activatePendingSearchAfterCommittedIndexUpdate()
        }
        return refreshActiveSearchAfterCommittedIndexUpdate()
    }

    private func activatePendingSearchAfterCommittedIndexUpdate() -> Bool {
        guard pendingSearchActivationAfterFreshnessBarrier else { return false }
        pendingSearchActivationAfterFreshnessBarrier = false
        guard SearchInteractionPreferencesStore.loadIsEnabled() else { return false }
        guard overlayStyle == .appAndWindow else { return false }
        guard let session, case .appCycle = session.mode else { return false }
        cancelPendingSearchComputation()
        sessionAppsByID = Dictionary(uniqueKeysWithValues: session.apps.map { ($0.id, $0) })
        guard rebuildSearchIndexFromCommittedProjection(reason: "committedSearchIndexDidUpdate") else {
            RuntimeLog.debug(
                .searchModel,
                "committedSearchIndexDidUpdate changed=0 reason=noCommittedSearchIndex sessionAppCount=\(session.apps.count)"
            )
            return false
        }
        let defaultScope = SearchInteractionPreferencesStore.loadDefaultScope()
        let changed = searchCoordinator.activate(defaultScope: defaultScope)
        publishSearchStateIfNeeded()
        RuntimeLog.debug(
            .searchModel,
            "committedSearchIndexDidUpdate changed=\(changed ? 1 : 0) scope=\(defaultScope.rawValue) appCount=\(session.apps.count) inputFocused=\(searchViewState.isInputFocused ? 1 : 0)"
        )
        return changed
    }

    private func refreshActiveSearchAfterCommittedIndexUpdate() -> Bool {
        guard searchViewState.isActive else { return false }
        let previousSearchState = searchViewState
        cancelPendingSearchComputation()
        guard rebuildSearchIndexFromCommittedProjection(reason: "committedSearchIndexDidUpdate") else {
            return false
        }
        restoreSearchStateAfterProjectionRefreshIfNeeded(previousSearchState)
        publishSearchStateIfNeeded()
        return true
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
    func rebuildSearchIndexFromCommittedProjection(
        reason: String,
        requestFreshnessBarrierIfNeeded: Bool = true
    ) -> Bool {
        let read = runtimeProjectionService.readCommittedSearchIndexForSearch()
        let requestedFreshnessBarrier = read.shouldRequestFreshnessBarrier
            && requestFreshnessBarrierIfNeeded
        guard let projection = read.projection else {
            committedSearchAppsByID = [:]
            searchCoordinator.resetIndex()
            publishSearchStateIfNeeded()
            if requestedFreshnessBarrier {
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
                requestedFreshnessBarrier: requestedFreshnessBarrier
            )
            RuntimeLog.debug(
                .searchModel,
                "searchIndexSource reason=\(reason) source=none readiness=\(read.readiness.rawValue) resultState=\(read.resultState.rawValue) freshnessBarrierRequested=\(requestedFreshnessBarrier ? 1 : 0)"
            )
            return false
        }
        if requestedFreshnessBarrier {
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
        Dictionary(
            committedSearchSessionApps(from: projection).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private static func committedSearchSessionApps(
        from projection: RuntimeSearchIndexProjection
    ) -> [AppSwitchCandidate] {
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
        return projection.appEntries.map { entry in
            AppSwitchCandidate(
                id: entry.appID,
                displayName: entry.appDisplayName,
                groupID: entry.appGroupID,
                lastActiveAt: entry.appLastActiveAt,
                windows: windowsByAppID[entry.appID] ?? []
            )
        }
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
        if case .exitSearch = action {
            pendingSearchActivationAfterFreshnessBarrier = false
        }
        publishSearchStateIfNeeded()
        return action
    }

    @discardableResult
    func applySelectedSearchResultToSession() -> Bool {
        guard var session else { return false }
        flushCurrentSearchComputationForCommit()
        guard let selected = searchViewState.selectedResult else { return false }
        let selectedAppID: String
        let selectedWindowID: String?

        switch selected.kind {
        case .app(let appID):
            selectedAppID = appID
            selectedWindowID = nil
            if !session.selectApp(withID: appID) {
                guard let committedApp = committedSearchAppsByID[appID] else { return false }
                session = Self.sessionByApplyingCommittedSearchTarget(
                    committedApp,
                    to: session
                )
                guard session.selectApp(withID: appID) else { return false }
            }
        case .window(let appID, let windowID):
            selectedAppID = appID
            selectedWindowID = windowID
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
        hydrateRuntimeContextForSearchSelectionIfNeeded(
            appID: selectedAppID,
            windowID: selectedWindowID
        )

        autoEnterSuppressedAppID = nil
        cancelPendingSearchComputation()
        pendingSearchActivationAfterFreshnessBarrier = false
        self.session = session
        _ = searchCoordinator.exit()
        publishSearchStateIfNeeded()
        return true
    }

    private func hydrateRuntimeContextForSearchSelectionIfNeeded(
        appID: String,
        windowID: String?
    ) {
        if let windowID {
            guard runtimeContextsByID[appID]?.windowsByID[windowID] == nil else { return }
        } else {
            guard runtimeContextsByID[appID] == nil else { return }
        }
        guard
            let context = runtimeProjectionService
                .readAppSwitcherProjection()?
                .contextsByID[appID],
            windowID.map({ context.windowsByID[$0] != nil }) ?? true
        else {
            return
        }
        runtimeContextsByID[appID] = context
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
        let shouldResetSelection =
            searchSchedulingOwner.hasPendingWork
        cancelPendingSearchComputation()
        searchCoordinator.rebuildResults(resetSelection: shouldResetSelection)
        publishSearchStateIfNeeded()
    }

    func scheduleSearchComputation(resetSelection: Bool, debounced: Bool) {
        guard searchViewState.isActive else { return }
        guard
            let input = searchCoordinator.makeComputationInput(
                resetSelection: resetSelection
            )
        else {
            cancelPendingSearchComputation()
            return
        }
        searchSchedulingOwner.schedule(
            input: input,
            debounced: debounced
        ) { [weak self] output in
            guard let self else { return }
            if self.searchCoordinator.applyComputationOutput(output) {
                self.publishSearchStateIfNeeded()
                self.onSearchStateChanged?()
            }
        }
    }

    func cancelPendingSearchComputation() {
        searchSchedulingOwner.cancel()
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
