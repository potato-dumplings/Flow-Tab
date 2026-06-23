import Foundation
import FlowTabCore

extension LiveSwitcherModel {
    func loadAppSwitcherProjectionSession(
        triggerDirection: CycleDirection,
        preferredSelectedAppID: String?,
        animateAppStripUpdate _: Bool = false,
        preserveSearchState: Bool = false,
        resetWhenEmpty: Bool = true
    ) -> Bool {
        let startMs = Self.monotonicMilliseconds()
        let previousSearchState = preserveSearchState ? searchViewState : .inactive
        cancelPendingSearchComputation()
        let payload = readAppSwitcherProjectionSessionPayload()
        let projectionReadMs = Self.monotonicMilliseconds()
        return applyAppSwitcherProjectionPayload(
            payload,
            triggerDirection: triggerDirection,
            preferredSelectedAppID: preferredSelectedAppID,
            previousSearchState: previousSearchState,
            startMs: startMs,
            projectionReadMs: projectionReadMs,
            logEvent: "loadAppSwitcherProjectionSession",
            resetWhenEmpty: resetWhenEmpty
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
            resetWhenEmpty: true
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
        resetWhenEmpty: Bool
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
        clearPreviewSnapshotState()
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
            completeSelectedAppWindowProjection(
                projection.currentAppWindowPayload,
                appID: targetAppID,
                generation: generation,
                startMs: startMs,
                projectionReadMs: Self.monotonicMilliseconds()
            )
            return true
        }

        let projectionReadMs = Self.monotonicMilliseconds()
        if let pid = runtimeContextsByID[targetAppID]?.runningApp.processIdentifier {
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

    func completeSelectedAppWindowProjection(
        _ currentAppWindowPayload: RuntimeCurrentAppWindowPayload?,
        appID: String,
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

        var apps = currentSession.apps
        apps[appIndex] = currentAppWindowPayload.candidate
        runtimeContextsByID[appID] = currentAppWindowPayload.context
        let preservesWindowLayerPreview: Bool
        if case .windowCycle(let windowLayerAppID) = currentSession.mode, windowLayerAppID == appID {
            preservesWindowLayerPreview = true
        } else {
            preservesWindowLayerPreview = false
        }
        if !preservesWindowLayerPreview {
            clearPreviewSnapshotState()
        }

        var rebuiltSession = SwitcherSession(
            apps: apps,
            preferences: currentSession.preferences,
            triggerDirection: .forward,
            rememberedWindowIDByAppID: currentSession.rememberedWindowIDByAppID
        )
        _ = rebuiltSession.selectApp(withID: currentSession.selectedApp.id)
        if case .windowCycle(let windowLayerAppID) = currentSession.mode, windowLayerAppID == appID {
            if let selectedWindowID = currentSession.selectedWindow?.id {
                _ = rebuiltSession.selectWindow(appID: appID, windowID: selectedWindowID)
            } else {
                _ = rebuiltSession.enterWindowCycle(allowSingleWindow: false)
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
            currentAppWindowPayload: currentAppWindowPayload,
            startMs: startMs,
            projectionReadMs: projectionReadMs,
            applyEndMs: applyEndMs
        )
        onSessionLayoutChanged?()
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
