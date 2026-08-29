import Foundation
import FlowTabCore

struct PendingFocusedAppWindowSession: Equatable {
    let appID: String
    let pid: pid_t
    let triggerDirection: CycleDirection
    let baselineReadModelGeneration: RuntimeReadModelGeneration
    let baselineProjectionGeneration: RuntimeReadModelGeneration?
}

enum FocusedAppWindowSessionStartResult: Equatable {
    case ready
    case awaitingFreshProjection(PendingFocusedAppWindowSession)
    case unavailable
}

extension LiveSwitcherModel {
    func startFocusedAppWindowSession(
        triggerDirection: CycleDirection
    ) -> FocusedAppWindowSessionStartResult {
        let startMs = Self.monotonicMilliseconds()
        invalidateSelectedAppWindowProjection(reason: .startFocusedWindowSession)
        clearTerminateSelectedAppAnimation()
        guard let focusedRead = runtimeProjectionService.readFocusedCurrentAppWindowProjection() else {
            runtimeProjectionService.signalFocusedCurrentAppWindowsChanged()
            logStartFocusedWindowSessionNoFrontmost(startMs: startMs)
            resetSessionState()
            return .unavailable
        }
        let frontmostReadyMs = Self.monotonicMilliseconds()
        let projectionReadMs = Self.monotonicMilliseconds()
        guard let projection = focusedRead.projection,
              projection.freshness.isCompleteForScope
        else {
            let pending = PendingFocusedAppWindowSession(
                appID: focusedRead.appID,
                pid: focusedRead.pid,
                triggerDirection: triggerDirection,
                baselineReadModelGeneration:
                    runtimeProjectionService
                        .runtimeReadModelDiagnostics().generation,
                baselineProjectionGeneration:
                    focusedRead.projection?.freshness.sourceGeneration
            )
            runtimeProjectionService.signalFocusedCurrentAppWindowsChanged()
            let awaitingMs = Self.monotonicMilliseconds()
            logStartFocusedWindowSession(
                result: "awaitingFreshProjection",
                frontmostAppID: focusedRead.appID,
                frontmostReadyMs: frontmostReadyMs,
                projectionReadMs: projectionReadMs,
                recencyAppliedMs: awaitingMs,
                completeMs: awaitingMs,
                startMs: startMs
            )
            resetSessionState()
            return .awaitingFreshProjection(pending)
        }
        let payload = currentAppWindowPayloadWithWindowRecencyApplied(
            projection.currentAppWindowPayload
        )
        let recencyAppliedMs = Self.monotonicMilliseconds()
        guard installFocusedAppWindowSession(
            payload: payload,
            triggerDirection: triggerDirection
        ) else {
            let failedMs = Self.monotonicMilliseconds()
            logStartFocusedWindowSession(
                result: "noWindows",
                frontmostAppID: focusedRead.appID,
                frontmostReadyMs: frontmostReadyMs,
                projectionReadMs: projectionReadMs,
                recencyAppliedMs: recencyAppliedMs,
                completeMs: failedMs,
                startMs: startMs
            )
            resetSessionState()
            return .unavailable
        }
        let completeMs = Self.monotonicMilliseconds()
        logStartFocusedWindowSession(
            result: "ready",
            frontmostAppID: focusedRead.appID,
            frontmostReadyMs: frontmostReadyMs,
            projectionReadMs: projectionReadMs,
            recencyAppliedMs: recencyAppliedMs,
            completeMs: completeMs,
            startMs: startMs,
            windows: payload.candidate.windows.count
        )
        return .ready
    }

    func completePendingFocusedAppWindowSession(
        _ pending: PendingFocusedAppWindowSession
    ) -> Bool {
        guard session == nil,
              let focusedRead = runtimeProjectionService
                .readFocusedCurrentAppWindowProjection(),
              focusedRead.appID == pending.appID,
              focusedRead.pid == pending.pid,
              let projection = focusedRead.projection,
              projection.freshness.isCompleteForScope,
              projection.freshness.sourceGeneration.isStrictlyLater(
                than: pending.baselineReadModelGeneration
              )
        else {
            return false
        }
        if let baselineProjectionGeneration =
            pending.baselineProjectionGeneration
        {
            guard projection.freshness.sourceGeneration.isStrictlyLater(
                than: baselineProjectionGeneration
            ) else {
                return false
            }
        }
        let payload = currentAppWindowPayloadWithWindowRecencyApplied(
            projection.currentAppWindowPayload
        )
        return installFocusedAppWindowSession(
            payload: payload,
            triggerDirection: pending.triggerDirection
        )
    }

    private func installFocusedAppWindowSession(
        payload: RuntimeCurrentAppWindowPayload,
        triggerDirection: CycleDirection
    ) -> Bool {
        let appCandidate = payload.candidate
        guard !appCandidate.windows.isEmpty else { return false }

        overlayStyle = .windowOnly
        titleBarStyleInferenceEnabled = true
        runtimeContextsByID = [appCandidate.id: payload.context]
        clearPreviewSnapshotState()
        autoEnterSuppressedAppID = nil
        var rebuiltSession = SwitcherSession(
            apps: [appCandidate],
            preferences: SwitcherBehaviorPreferencesStore
                .loadSwitcherPreferences(),
            triggerDirection: triggerDirection,
            rememberedWindowIDByAppID: rememberedWindowIDByAppID
        )
        guard rebuiltSession.enterWindowCycle(
            allowSingleWindow: true
        ) else {
            return false
        }
        session = rebuiltSession
        _ = searchCoordinator.exit()
        publishSearchStateIfNeeded()
        return true
    }

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
        beginSessionAppWindowReadinessTracking()
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

        deferredRuntimeProjectionMaintenanceDirection = nil
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

    func deferRuntimeProjectionMaintenance(
        triggerDirection: CycleDirection
    ) {
        guard runtimeProjectionMaintenanceEnabled else { return }
        deferredRuntimeProjectionMaintenanceDirection =
            triggerDirection
    }

    @discardableResult
    func performDeferredRuntimeProjectionMaintenance() -> Bool {
        guard let triggerDirection =
            deferredRuntimeProjectionMaintenanceDirection
        else {
            return false
        }
        requestRuntimeProjectionMaintenance(
            triggerDirection: triggerDirection
        )
        return true
    }

    func invalidateRuntimeProjectionMaintenanceRequest(
        reason: ProjectionInvalidationReason = .explicitRuntimeProjectionMaintenanceInvalidation
    ) {
        let clearedDeferredMaintenanceRequest =
            deferredRuntimeProjectionMaintenanceDirection != nil
        deferredRuntimeProjectionMaintenanceDirection = nil
        runtimeProjectionMaintenanceGeneration &+= 1
        recordProjectionInvalidation(
            reason: reason,
            scope: .runtimeProjectionMaintenance,
            clearedDeferredMaintenanceRequest:
                clearedDeferredMaintenanceRequest
        )
    }

    @discardableResult
    func scheduleSelectedAppWindowProjectionIfNeeded(for appID: String? = nil) -> Bool {
        guard let currentSession = session,
              case .appCycle = currentSession.mode
        else {
            return false
        }
        let targetAppID = appID ?? currentSession.selectedApp.id
        guard targetAppID == currentSession.selectedApp.id else {
            return false
        }
        switch resolveSelectedAppWindowReadiness() {
        case .ready:
            return false
        case .pending(let identity):
            return requestSelectedAppWindowMaintenanceIfNeeded(
                identity: identity
            )
        case .unavailable:
            return false
        }
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
    func applyCurrentAppWindowProjectionIfReady(appID: String) -> Bool {
        guard let currentSession = session else { return false }
        guard !isPresentingWindowLayerSnapshot(currentSession) else { return false }
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
            generation: selectedAppWindowProjectionGeneration,
            startMs: startMs,
            projectionReadMs: Self.monotonicMilliseconds()
        )
        return true
    }

    func completeSelectedAppWindowProjection(
        _ currentAppWindowPayload: RuntimeCurrentAppWindowPayload?,
        appID: String,
        generation: UInt64,
        startMs: Double,
        projectionReadMs: Double,
        notifiesSessionLayoutChange: Bool = true
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
        guard !isPresentingWindowLayerSnapshot(currentSession) else {
            logSelectedAppWindowProjection(
                result: "windowLayerSnapshot",
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

        runtimeContextsByID[appID] = currentAppWindowPayload.context
        if currentSession.apps[appIndex] == currentAppWindowPayload.candidate,
           pendingManualWindowLayerEntryAppID != appID {
            logSelectedAppWindowProjection(
                result: "unchanged",
                appID: appID,
                currentAppWindowPayload: currentAppWindowPayload,
                startMs: startMs,
                projectionReadMs: projectionReadMs,
                applyEndMs: Self.monotonicMilliseconds()
            )
            return
        }

        var apps = currentSession.apps
        apps[appIndex] = currentAppWindowPayload.candidate
        clearPreviewSnapshotState()

        var rebuiltSession = SwitcherSession(
            apps: apps,
            preferences: currentSession.preferences,
            triggerDirection: .forward,
            rememberedWindowIDByAppID: currentSession.rememberedWindowIDByAppID
        )
        _ = rebuiltSession.selectApp(withID: currentSession.selectedApp.id)
        if pendingManualWindowLayerEntryAppID == appID {
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
            currentAppWindowPayload: currentAppWindowPayload,
            startMs: startMs,
            projectionReadMs: projectionReadMs,
            applyEndMs: applyEndMs
        )
        if notifiesSessionLayoutChange {
            onSessionLayoutChanged?()
        }
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
