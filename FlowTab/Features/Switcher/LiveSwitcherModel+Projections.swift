import Foundation
import FlowTabCore

extension LiveSwitcherModel {
    func loadAppSwitcherProjectionSession(
        triggerDirection: CycleDirection,
        preferredSelectedAppID: String?,
        animateAppStripUpdate _: Bool = false,
        preserveSearchState: Bool = false,
        resetWhenEmpty: Bool = true,
        preservePreviewSnapshotState: Bool = false,
        preservingVisibleAppOrderFrom visibleApps: [AppSwitchCandidate] = [],
        removingTerminatedAppID: String? = nil,
        terminatedPID: pid_t? = nil
    ) -> Bool {
        let startMs = Self.monotonicMilliseconds()
        let previousSearchState = preserveSearchState ? searchViewState : .inactive
        cancelPendingSearchComputation()
        let refreshedPayload = appSwitcherPayload(
            readAppSwitcherProjectionSessionPayload(),
            removingTerminatedAppID: removingTerminatedAppID,
            terminatedPID: terminatedPID
        )
        let payload = AppSwitcherProjectionSessionPayload(
            apps: StableIdentityOrder.reconcile(
                current: visibleApps,
                updated: refreshedPayload.apps,
                identity: { $0.id }
            ),
            contextsByID: refreshedPayload.contextsByID
        )
        let projectionReadMs = Self.monotonicMilliseconds()
        return applyAppSwitcherProjectionPayload(
            payload,
            triggerDirection: triggerDirection,
            preferredSelectedAppID: preferredSelectedAppID,
            previousSearchState: previousSearchState,
            startMs: startMs,
            projectionReadMs: projectionReadMs,
            logEvent: "loadAppSwitcherProjectionSession",
            resetWhenEmpty: resetWhenEmpty,
            preservePreviewSnapshotState: preservePreviewSnapshotState
        )
    }

    func appSwitcherPayload(
        _ payload: AppSwitcherProjectionSessionPayload,
        removingTerminatedAppID appID: String?,
        terminatedPID: pid_t?
    ) -> AppSwitcherProjectionSessionPayload {
        guard let appID, let terminatedPID else { return payload }
        let knownPIDs = [
            runtimeContextsByID[appID]?.runningApp.processIdentifier,
            payload.contextsByID[appID]?.runningApp.processIdentifier,
        ].compactMap { $0 }
        guard !knownPIDs.contains(where: { $0 != terminatedPID }) else {
            return payload
        }

        // The committed projection may intentionally remain stale while its main-table
        // generation is repaired; a confirmed process death is still authoritative for
        // the active Switcher session.
        return AppSwitcherProjectionSessionPayload(
            apps: payload.apps.filter { $0.id != appID },
            contextsByID: payload.contextsByID.filter { $0.key != appID }
        )
    }

    func loadFastAppSwitcherProjectionSession(
        triggerDirection: CycleDirection,
        preferredSelectedAppID: String?
    ) -> Bool {
        let startMs = Self.monotonicMilliseconds()
        cancelPendingSearchComputation()
        let payload = readFastAppSwitcherProjectionSessionPayload()
        let projectionReadMs = Self.monotonicMilliseconds()
        return applyAppSwitcherProjectionPayload(
            payload,
            triggerDirection: triggerDirection,
            preferredSelectedAppID: preferredSelectedAppID,
            previousSearchState: .inactive,
            startMs: startMs,
            projectionReadMs: projectionReadMs,
            logEvent: "loadFastAppSwitcherProjectionSession",
            resetWhenEmpty: true,
            preservePreviewSnapshotState: false
        )
    }

    @discardableResult
    func applyAppSwitcherProjectionPayload(
        _ rawPayload: AppSwitcherProjectionSessionPayload,
        triggerDirection: CycleDirection,
        preferredSelectedAppID: String?,
        previousSearchState: SwitcherSearchViewState,
        startMs: Double,
        projectionReadMs: Double,
        logEvent: String,
        resetWhenEmpty: Bool,
        preservePreviewSnapshotState: Bool
    ) -> Bool {
        let payload = appSwitcherPayloadWithHiddenAppsFiltered(
            appSwitcherPayloadWithWindowRecencyApplied(rawPayload)
        )
        let recencyAppliedMs = Self.monotonicMilliseconds()
        guard !payload.apps.isEmpty else {
            logLoadAppSwitcherProjectionSessionEmpty(
                event: logEvent,
                triggerDirection: triggerDirection,
                projectionReadMs: projectionReadMs,
                recencyAppliedMs: recencyAppliedMs,
                startMs: startMs
            )
            if resetWhenEmpty {
                resetSessionState()
            }
            return false
        }

        runtimeContextsByID = payload.contextsByID
        if !preservePreviewSnapshotState {
            clearPreviewSnapshotState()
        }
        autoEnterSuppressedAppID = nil
        let preferences = SwitcherBehaviorPreferencesStore.loadSwitcherPreferences()
        var rebuiltSession = SwitcherSession(
            apps: payload.apps,
            preferences: preferences,
            triggerDirection: triggerDirection,
            rememberedWindowIDByAppID: rememberedWindowIDByAppID
        )

        if
            let preferredSelectedAppID,
            rebuiltSession.apps.contains(where: { $0.id == preferredSelectedAppID })
        {
            for _ in 0..<rebuiltSession.apps.count {
                if rebuiltSession.selectedApp.id == preferredSelectedAppID {
                    break
                }
                rebuiltSession.handle(.tabForward)
            }
        }

        session = rebuiltSession
        if
            let pendingTerminateRequest,
            !rebuiltSession.apps.contains(where: { $0.id == pendingTerminateRequest.appID })
        {
            self.pendingTerminateRequest = nil
            if terminatingAppID == pendingTerminateRequest.appID {
                self.terminatingAppID = nil
            }
        }
        if let terminatingAppID, !rebuiltSession.apps.contains(where: { $0.id == terminatingAppID }) {
            self.terminatingAppID = nil
        }
        let sessionReadyMs = Self.monotonicMilliseconds()
        if previousSearchState.isActive {
            _ = rebuildSearchIndexFromCommittedProjection(reason: "appSwitcherProjectionRefresh")
        } else {
            _ = searchCoordinator.exit()
        }
        let indexReadyMs = Self.monotonicMilliseconds()
        restoreSearchStateAfterProjectionRefreshIfNeeded(previousSearchState)
        publishSearchStateIfNeeded()
        let completeMs = Self.monotonicMilliseconds()
        logLoadAppSwitcherProjectionSessionReady(
            event: logEvent,
            triggerDirection: triggerDirection,
            payload: payload,
            projectionReadMs: projectionReadMs,
            recencyAppliedMs: recencyAppliedMs,
            sessionReadyMs: sessionReadyMs,
            indexReadyMs: indexReadyMs,
            completeMs: completeMs,
            startMs: startMs
        )
        return true
    }

    func requestRuntimeProjectionMaintenance(triggerDirection: CycleDirection) {
        guard runtimeProjectionMaintenanceEnabled else { return }

        runtimeProjectionMaintenanceGeneration &+= 1
        let startMs = Self.monotonicMilliseconds()
        runtimeProjectionService.requestAppSwitcherProjectionMaintenance(reason: .switcherSessionStarted)
        logRuntimeProjectionMaintenance(
            result: "maintenanceRequested",
            startMs: startMs,
            generation: runtimeProjectionMaintenanceGeneration,
            reason: .startSession,
            triggerDirection: triggerDirection
        )
    }

    func invalidateRuntimeProjectionMaintenanceRequest(
        reason: ProjectionInvalidationReason = .explicitRuntimeProjectionMaintenanceInvalidation
    ) {
        runtimeProjectionMaintenanceGeneration &+= 1
        recordProjectionInvalidation(
            reason: reason,
            scope: .runtimeProjectionMaintenance,
            clearedDeferredMaintenanceRequest: false
        )
    }

    @discardableResult
    func scheduleSelectedAppWindowProjectionIfNeeded(for appID: String? = nil) -> Bool {
        guard let currentSession = session else { return false }
        guard case .appCycle = currentSession.mode else { return false }
        let targetAppID = appID ?? currentSession.selectedApp.id
        guard targetAppID == currentSession.selectedApp.id else { return false }
        guard currentSession.selectedApp.windows.isEmpty else { return false }
        if selectedAppWindowProjectionPendingAppID == targetAppID {
            return false
        }

        selectedAppWindowProjectionGeneration &+= 1
        let generation = selectedAppWindowProjectionGeneration
        selectedAppWindowProjectionPendingAppID = targetAppID
        let startMs = Self.monotonicMilliseconds()
        let runtimeService = runtimeProjectionService

        RuntimeLog.debug(
            .projection,
            "selectedAppWindowProjection result=scheduled appID=\(targetAppID)"
        )

        if let projection = runtimeService.readCurrentAppWindowProjection(appID: targetAppID) {
            let projectionReadMs = Self.monotonicMilliseconds()
            if projection.freshness.isCompleteForScope {
                completeSelectedAppWindowProjection(
                    currentAppWindowPayloadWithWindowRecencyApplied(
                        projection.currentAppWindowPayload
                    ),
                    appID: targetAppID,
                    generation: generation,
                    startMs: startMs,
                    projectionReadMs: projectionReadMs
                )
                return true
            }
            if !projection.currentAppWindowPayload.candidate.windows.isEmpty {
                if let pid = runtimeContextsByID[targetAppID]?.ownerPID {
                    runtimeService.signalSelectedCurrentAppWindowsChanged(appID: targetAppID, pid: pid)
                }
                RuntimeLog.debug(
                    .projection,
                    "selectedAppWindowProjection result=degradedStaleCommitted appID=\(targetAppID) windows=\(projection.currentAppWindowPayload.candidate.windows.count)"
                )
                completeSelectedAppWindowProjection(
                    nil,
                    appID: targetAppID,
                    generation: generation,
                    startMs: startMs,
                    projectionReadMs: projectionReadMs
                )
                return false
            }
        }

        let projectionReadMs = Self.monotonicMilliseconds()
        if let pid = runtimeContextsByID[targetAppID]?.ownerPID {
            runtimeService.signalSelectedCurrentAppWindowsChanged(appID: targetAppID, pid: pid)
        }
        completeSelectedAppWindowProjection(
            nil,
            appID: targetAppID,
            generation: generation,
            startMs: startMs,
            projectionReadMs: projectionReadMs
        )
        return runtimeContextsByID[targetAppID] != nil
    }

    @discardableResult
    func applySelectedAppWindowProjectionIfReady(for appID: String? = nil) -> Bool {
        guard let currentSession = session else { return false }
        guard case .appCycle = currentSession.mode else { return false }
        let targetAppID = appID ?? currentSession.selectedApp.id
        guard targetAppID == currentSession.selectedApp.id else { return false }
        guard currentSession.selectedApp.windows.isEmpty else { return false }

        let startMs = Self.monotonicMilliseconds()
        guard
            let projection = runtimeProjectionService.readCurrentAppWindowProjection(appID: targetAppID),
            projection.freshness.isCompleteForScope
        else {
            return false
        }

        selectedAppWindowProjectionGeneration &+= 1
        completeSelectedAppWindowProjection(
            projection.currentAppWindowPayload,
            appID: targetAppID,
            generation: selectedAppWindowProjectionGeneration,
            startMs: startMs,
            projectionReadMs: Self.monotonicMilliseconds()
        )
        return true
    }

    @discardableResult
    func applyCurrentAppWindowProjectionIfReady(
        appID: String,
        restoringWindowCycleSelectedWindowID: String? = nil
    ) -> Bool {
        guard let currentSession = session else { return false }
        guard currentSession.apps.contains(where: { $0.id == appID }) else { return false }

        let startMs = Self.monotonicMilliseconds()
        guard
            let projection = runtimeProjectionService.readCurrentAppWindowProjection(appID: appID),
            projection.freshness.isCompleteForScope
        else {
            return false
        }

        selectedAppWindowProjectionGeneration &+= 1
        let payload = currentAppWindowPayloadWithWindowRecencyApplied(
            projection.currentAppWindowPayload
        )
        completeSelectedAppWindowProjection(
            payload,
            appID: appID,
            restoringWindowCycleSelectedWindowID: restoringWindowCycleSelectedWindowID,
            generation: selectedAppWindowProjectionGeneration,
            startMs: startMs,
            projectionReadMs: Self.monotonicMilliseconds()
        )
        return true
    }

    func completeSelectedAppWindowProjection(
        _ currentAppWindowPayload: RuntimeCurrentAppWindowPayload?,
        appID: String,
        restoringWindowCycleSelectedWindowID: String? = nil,
        generation: UInt64,
        startMs: Double,
        projectionReadMs: Double
    ) {
        defer {
            if selectedAppWindowProjectionPendingAppID == appID {
                selectedAppWindowProjectionPendingAppID = nil
            }
        }
        guard generation == selectedAppWindowProjectionGeneration else {
            logSelectedAppWindowProjection(
                result: "staleGeneration",
                appID: appID,
                currentAppWindowPayload: currentAppWindowPayload,
                startMs: startMs,
                projectionReadMs: projectionReadMs,
                applyEndMs: Self.monotonicMilliseconds()
            )
            return
        }
        guard let currentAppWindowPayload else {
            logSelectedAppWindowProjection(
                result: "missing",
                appID: appID,
                currentAppWindowPayload: nil,
                startMs: startMs,
                projectionReadMs: projectionReadMs,
                applyEndMs: Self.monotonicMilliseconds()
            )
            return
        }
        guard let currentSession = session, currentSession.selectedApp.id == appID else {
            logSelectedAppWindowProjection(
                result: "staleSelection",
                appID: appID,
                currentAppWindowPayload: currentAppWindowPayload,
                startMs: startMs,
                projectionReadMs: projectionReadMs,
                applyEndMs: Self.monotonicMilliseconds()
            )
            return
        }
        guard let appIndex = currentSession.apps.firstIndex(where: { $0.id == appID }) else {
            logSelectedAppWindowProjection(
                result: "missingSessionApp",
                appID: appID,
                currentAppWindowPayload: currentAppWindowPayload,
                startMs: startMs,
                projectionReadMs: projectionReadMs,
                applyEndMs: Self.monotonicMilliseconds()
            )
            return
        }

        let currentSessionIsWindowLayerForApp: Bool
        if case .windowCycle(let windowLayerAppID) = currentSession.mode, windowLayerAppID == appID {
            currentSessionIsWindowLayerForApp = true
        } else {
            currentSessionIsWindowLayerForApp = false
        }
        let appliedPayload = currentSessionIsWindowLayerForApp
            ? currentAppWindowPayloadByPreservingActiveWindowLayerOrder(
                currentAppWindowPayload,
                currentSession: currentSession
            )
            : currentAppWindowPayload

        runtimeContextsByID[appID] = appliedPayload.context
        if currentSession.apps[appIndex] == appliedPayload.candidate,
           !currentSessionIsWindowLayerForApp,
           restoringWindowCycleSelectedWindowID == nil,
           pendingManualWindowLayerEntryAppID != appID {
            logSelectedAppWindowProjection(
                result: "unchanged",
                appID: appID,
                currentAppWindowPayload: appliedPayload,
                startMs: startMs,
                projectionReadMs: projectionReadMs,
                applyEndMs: Self.monotonicMilliseconds()
            )
            return
        }

        var apps = currentSession.apps
        apps[appIndex] = appliedPayload.candidate
        let restoringWindowCycle = restoringWindowCycleSelectedWindowID != nil
        let preservesWindowLayerPreview: Bool
        if currentSessionIsWindowLayerForApp {
            preservesWindowLayerPreview = true
        } else if restoringWindowCycle {
            preservesWindowLayerPreview = true
        } else {
            preservesWindowLayerPreview = false
        }
        if !preservesWindowLayerPreview {
            clearPreviewSnapshotState()
        } else {
            refreshFrozenPreviewOrderIfChanged(
                for: appID,
                windows: appliedPayload.candidate.windows
            )
        }

        var rebuiltSession = SwitcherSession(
            apps: apps,
            preferences: currentSession.preferences,
            triggerDirection: .forward,
            rememberedWindowIDByAppID: currentSession.rememberedWindowIDByAppID
        )
        _ = rebuiltSession.selectApp(withID: currentSession.selectedApp.id)
        if currentSessionIsWindowLayerForApp || restoringWindowCycle {
            if let selectedWindowID = currentSession.selectedWindow?.id ?? restoringWindowCycleSelectedWindowID {
                if !rebuiltSession.selectWindow(appID: appID, windowID: selectedWindowID) {
                    _ = rebuiltSession.selectApp(withID: appID)
                    _ = rebuiltSession.enterWindowCycle(allowSingleWindow: true)
                }
            } else {
                _ = rebuiltSession.enterWindowCycle(allowSingleWindow: true)
            }
        } else if pendingManualWindowLayerEntryAppID == appID {
            let enteredWindowLayer = rebuiltSession.enterWindowCycle(allowSingleWindow: false)
            RuntimeLog.debug(
                .projection,
                "manualWindowLayerEntry result=\(enteredWindowLayer ? "entered" : "notReady") appID=\(appID) windows=\(rebuiltSession.selectedApp.windows.count)"
            )
            pendingManualWindowLayerEntryAppID = nil
        }
        session = rebuiltSession
        let applyEndMs = Self.monotonicMilliseconds()
        logSelectedAppWindowProjection(
            result: "applied",
            appID: appID,
            currentAppWindowPayload: appliedPayload,
            startMs: startMs,
            projectionReadMs: projectionReadMs,
            applyEndMs: applyEndMs
        )
        onSessionLayoutChanged?()
    }

    private func currentAppWindowPayloadByPreservingActiveWindowLayerOrder(
        _ payload: RuntimeCurrentAppWindowPayload,
        currentSession: SwitcherSession
    ) -> RuntimeCurrentAppWindowPayload {
        let currentWindows = currentSession.selectedApp.windows
        guard !currentWindows.isEmpty else { return payload }
        let currentWindowIDs = currentWindows.map(\.id)
        let projectedWindowsByID = Dictionary(uniqueKeysWithValues: payload.candidate.windows.map { ($0.id, $0) })
        let retainedWindows = currentWindowIDs.compactMap { projectedWindowsByID[$0] }
        guard !retainedWindows.isEmpty else { return payload }
        let retainedWindowIDs = Set(retainedWindows.map(\.id))
        let appendedWindows = payload.candidate.windows.filter { !retainedWindowIDs.contains($0.id) }
        let windows = retainedWindows + appendedWindows
        guard windows.map(\.id) != payload.candidate.windows.map(\.id) else {
            return payload
        }
        let candidate = AppSwitchCandidate(
            id: payload.candidate.id,
            displayName: payload.candidate.displayName,
            groupID: payload.candidate.groupID,
            lastActiveAt: payload.candidate.lastActiveAt,
            windows: windows
        )
        let summary = RuntimeHomeAppSummary(
            appID: payload.summary.appID,
            displayName: payload.summary.displayName,
            groupID: payload.summary.groupID,
            lastActiveAt: payload.summary.lastActiveAt,
            windowCount: windows.count,
            pid: payload.summary.pid,
            bundleIdentifier: payload.summary.bundleIdentifier,
            bundleURL: payload.summary.bundleURL
        )
        return RuntimeCurrentAppWindowPayload(
            summary: summary,
            candidate: candidate,
            context: payload.context,
            appDirectoryEntries: payload.appDirectoryEntries
        )
    }

    func invalidateSelectedAppWindowProjection(
        reason: ProjectionInvalidationReason = .explicitSelectedAppWindowProjectionInvalidation
    ) {
        selectedAppWindowProjectionGeneration &+= 1
        selectedAppWindowProjectionPendingAppID = nil
        pendingManualWindowLayerEntryAppID = nil
        recordProjectionInvalidation(
            reason: reason,
            scope: .selectedAppWindowProjection,
            clearedDeferredMaintenanceRequest: false
        )
    }

    func recordProjectionInvalidation(
        reason: ProjectionInvalidationReason,
        scope: ProjectionInvalidationScope,
        clearedDeferredMaintenanceRequest: Bool
    ) {
        let record = ProjectionInvalidationRecord(
            reason: reason,
            scope: scope,
            maintenanceGeneration: runtimeProjectionMaintenanceGeneration,
            selectedAppWindowProjectionGeneration: selectedAppWindowProjectionGeneration,
            clearedDeferredMaintenanceRequest: clearedDeferredMaintenanceRequest
        )
        lastProjectionInvalidationRecord = record
        RuntimeLog.debug(.projection, record.logMessage)
    }

    func readAppSwitcherProjectionSessionPayload() -> AppSwitcherProjectionSessionPayload {
        let startMs = Self.monotonicMilliseconds()
        let source: String
        let payload: AppSwitcherProjectionSessionPayload
        if let projection = runtimeProjectionService.readAppSwitcherProjection() {
            source = projection.freshness.isCompleteForScope
                ? "runtimeProjection"
                : "runtimeProjectionDirty"
            payload = AppSwitcherProjectionSessionPayload(projection: projection)
        } else {
            runtimeProjectionService.requestAppSwitcherProjectionMaintenance(reason: .appLifecycleRefresh)
            source = "runtimeProjectionMissing"
            payload = AppSwitcherProjectionSessionPayload(apps: [], contextsByID: [:])
        }
        let durationMs = Self.monotonicMilliseconds() - startMs
        logReadAppSwitcherProjectionPayload(source: source, payload: payload, durationMs: durationMs)
        return payload
    }

    func readFastAppSwitcherProjectionSessionPayload() -> AppSwitcherProjectionSessionPayload {
        let startMs = Self.monotonicMilliseconds()
        let source: String
        let payload: AppSwitcherProjectionSessionPayload
        if let projection = runtimeProjectionService.readAppSwitcherProjection() {
            source = projection.freshness.isCompleteForScope
                ? "runtimeProjection"
                : "runtimeProjectionDirty"
            payload = AppSwitcherProjectionSessionPayload(projection: projection)
        } else {
            source = "runtimeProjectionMissing"
            payload = AppSwitcherProjectionSessionPayload(apps: [], contextsByID: [:])
        }
        let durationMs = Self.monotonicMilliseconds() - startMs
        logReadAppSwitcherProjectionPayload(source: source, payload: payload, durationMs: durationMs)
        return payload
    }

}
