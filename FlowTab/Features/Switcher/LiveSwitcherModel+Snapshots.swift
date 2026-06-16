import Foundation
import FlowTabCore

extension LiveSwitcherModel {
    func loadSnapshot(
        triggerDirection: CycleDirection,
        preferredSelectedAppID: String?,
        animateAppStripUpdate _: Bool = false,
        preserveSearchState: Bool = false
    ) -> Bool {
        let startMs = Self.monotonicMilliseconds()
        let previousSearchState = preserveSearchState ? searchViewState : .inactive
        cancelPendingSearchComputation()
        let rawSnapshot = makeSnapshot()
        let snapshotReadMs = Self.monotonicMilliseconds()
        return applySnapshot(
            rawSnapshot,
            triggerDirection: triggerDirection,
            preferredSelectedAppID: preferredSelectedAppID,
            previousSearchState: previousSearchState,
            startMs: startMs,
            snapshotReadMs: snapshotReadMs,
            logEvent: "loadSnapshot",
            resetWhenEmpty: true
        )
    }

    func loadFastAppSnapshot(
        triggerDirection: CycleDirection,
        preferredSelectedAppID: String?
    ) -> Bool {
        let startMs = Self.monotonicMilliseconds()
        cancelPendingSearchComputation()
        let rawSnapshot = makeFastAppSnapshot()
        let snapshotReadMs = Self.monotonicMilliseconds()
        return applySnapshot(
            rawSnapshot,
            triggerDirection: triggerDirection,
            preferredSelectedAppID: preferredSelectedAppID,
            previousSearchState: .inactive,
            startMs: startMs,
            snapshotReadMs: snapshotReadMs,
            logEvent: "loadFastAppSnapshot",
            resetWhenEmpty: true
        )
    }

    @discardableResult
    func applySnapshot(
        _ rawSnapshot: RuntimeSnapshot,
        triggerDirection: CycleDirection,
        preferredSelectedAppID: String?,
        previousSearchState: SwitcherSearchViewState,
        startMs: Double,
        snapshotReadMs: Double,
        logEvent: String,
        resetWhenEmpty: Bool
    ) -> Bool {
        let snapshot = snapshotWithHiddenAppsFiltered(
            snapshotWithWindowRecencyApplied(rawSnapshot)
        )
        let recencyAppliedMs = Self.monotonicMilliseconds()
        guard !snapshot.apps.isEmpty else {
            logLoadSnapshotEmpty(
                event: logEvent,
                triggerDirection: triggerDirection,
                snapshotReadMs: snapshotReadMs,
                recencyAppliedMs: recencyAppliedMs,
                startMs: startMs
            )
            if resetWhenEmpty {
                resetSessionState()
            }
            return false
        }

        runtimeContextsByID = snapshot.contextsByID
        clearPreviewSnapshotState()
        autoEnterSuppressedAppID = nil
        let preferences = SwitcherBehaviorPreferencesStore.loadSwitcherPreferences()
        var rebuiltSession = SwitcherSession(
            apps: snapshot.apps,
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
            _ = rebuildSearchIndexFromCommittedProjection(reason: "snapshotRefresh")
        } else {
            _ = searchCoordinator.exit()
        }
        let indexReadyMs = Self.monotonicMilliseconds()
        restoreSearchStateAfterSnapshotRefreshIfNeeded(previousSearchState)
        publishSearchStateIfNeeded()
        let completeMs = Self.monotonicMilliseconds()
        logLoadSnapshotReady(
            event: logEvent,
            triggerDirection: triggerDirection,
            snapshot: snapshot,
            snapshotReadMs: snapshotReadMs,
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
        guard snapshotProviderOverride == nil else { return }

        runtimeProjectionMaintenanceGeneration &+= 1
        let startMs = Self.monotonicMilliseconds()
        runtimeSnapshotService.requestAppSwitcherProjectionMaintenance(reason: .switcherSessionStarted)
        logRuntimeProjectionMaintenance(
            result: "maintenanceRequested",
            startMs: startMs,
            generation: runtimeProjectionMaintenanceGeneration,
            reason: .startSession,
            triggerDirection: triggerDirection
        )
    }

    func invalidateRuntimeProjectionMaintenanceRequest(
        reason: SnapshotInvalidationReason = .explicitRuntimeProjectionMaintenanceInvalidation
    ) {
        runtimeProjectionMaintenanceGeneration &+= 1
        recordSnapshotInvalidation(
            reason: reason,
            scope: .runtimeProjectionMaintenance,
            clearedDeferredMaintenanceRequest: false
        )
    }

    @discardableResult
    func scheduleSelectedAppWindowSnapshotIfNeeded(for appID: String? = nil) -> Bool {
        guard let currentSession = session else { return false }
        guard case .appCycle = currentSession.mode else { return false }
        let targetAppID = appID ?? currentSession.selectedApp.id
        guard targetAppID == currentSession.selectedApp.id else { return false }
        guard currentSession.selectedApp.windows.isEmpty else { return false }
        if selectedAppWindowSnapshotPendingAppID == targetAppID {
            return false
        }

        selectedAppWindowSnapshotGeneration &+= 1
        let generation = selectedAppWindowSnapshotGeneration
        selectedAppWindowSnapshotPendingAppID = targetAppID
        let startMs = Self.monotonicMilliseconds()
        let providerOverride = selectedAppSnapshotProviderOverride
        let snapshotService = runtimeSnapshotService
        let recencyTracker = windowRecencyTracker

        RuntimeLog.debug(
            "Snapshot",
            "selectedAppWindowSnapshot result=scheduled appID=\(targetAppID)"
        )

        if
            providerOverride == nil,
            let projection = snapshotService.readCurrentAppWindowProjection(appID: targetAppID)
        {
            completeSelectedAppWindowSnapshot(
                projection.snapshot,
                appID: targetAppID,
                generation: generation,
                startMs: startMs,
                snapshotReadMs: Self.monotonicMilliseconds()
            )
            return true
        }

        if providerOverride == nil {
            let snapshotReadMs = Self.monotonicMilliseconds()
            if let pid = runtimeContextsByID[targetAppID]?.runningApp.processIdentifier {
                snapshotService.signalAppWindowsChanged(appID: targetAppID, pid: pid)
            }
            completeSelectedAppWindowSnapshot(
                nil,
                appID: targetAppID,
                generation: generation,
                startMs: startMs,
                snapshotReadMs: snapshotReadMs
            )
            return runtimeContextsByID[targetAppID] != nil
        }

        guard let providerOverride else { return false }

        DispatchQueue.global(qos: .userInitiated).async {
            let orderedSnapshot = providerOverride(targetAppID).map {
                recencyTracker.homeSnapshotWithRecencyApplied($0)
            }
            let snapshotReadMs = Self.monotonicMilliseconds()
            Task { @MainActor [weak self] in
                self?.completeSelectedAppWindowSnapshot(
                    orderedSnapshot,
                    appID: targetAppID,
                    generation: generation,
                    startMs: startMs,
                    snapshotReadMs: snapshotReadMs
                )
            }
        }
        return true
    }

    func completeSelectedAppWindowSnapshot(
        _ snapshot: RuntimeHomeAppSnapshot?,
        appID: String,
        generation: UInt64,
        startMs: Double,
        snapshotReadMs: Double
    ) {
        defer {
            if selectedAppWindowSnapshotPendingAppID == appID {
                selectedAppWindowSnapshotPendingAppID = nil
            }
        }
        guard generation == selectedAppWindowSnapshotGeneration else {
            logSelectedAppWindowSnapshot(
                result: "staleGeneration",
                appID: appID,
                snapshot: snapshot,
                startMs: startMs,
                snapshotReadMs: snapshotReadMs,
                applyEndMs: Self.monotonicMilliseconds()
            )
            return
        }
        guard let snapshot else {
            logSelectedAppWindowSnapshot(
                result: "missing",
                appID: appID,
                snapshot: nil,
                startMs: startMs,
                snapshotReadMs: snapshotReadMs,
                applyEndMs: Self.monotonicMilliseconds()
            )
            return
        }
        guard let currentSession = session, currentSession.selectedApp.id == appID else {
            logSelectedAppWindowSnapshot(
                result: "staleSelection",
                appID: appID,
                snapshot: snapshot,
                startMs: startMs,
                snapshotReadMs: snapshotReadMs,
                applyEndMs: Self.monotonicMilliseconds()
            )
            return
        }
        guard let appIndex = currentSession.apps.firstIndex(where: { $0.id == appID }) else {
            logSelectedAppWindowSnapshot(
                result: "missingSessionApp",
                appID: appID,
                snapshot: snapshot,
                startMs: startMs,
                snapshotReadMs: snapshotReadMs,
                applyEndMs: Self.monotonicMilliseconds()
            )
            return
        }

        var apps = currentSession.apps
        apps[appIndex] = snapshot.candidate
        runtimeContextsByID[appID] = snapshot.context
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
        }

        session = rebuiltSession
        let applyEndMs = Self.monotonicMilliseconds()
        logSelectedAppWindowSnapshot(
            result: "applied",
            appID: appID,
            snapshot: snapshot,
            startMs: startMs,
            snapshotReadMs: snapshotReadMs,
            applyEndMs: applyEndMs
        )
        onSessionLayoutChanged?()
    }

    func invalidateSelectedAppWindowSnapshot(
        reason: SnapshotInvalidationReason = .explicitSelectedAppWindowInvalidation
    ) {
        selectedAppWindowSnapshotGeneration &+= 1
        selectedAppWindowSnapshotPendingAppID = nil
        recordSnapshotInvalidation(
            reason: reason,
            scope: .selectedAppWindowSnapshot,
            clearedDeferredMaintenanceRequest: false
        )
    }

    func recordSnapshotInvalidation(
        reason: SnapshotInvalidationReason,
        scope: SnapshotInvalidationScope,
        clearedDeferredMaintenanceRequest: Bool
    ) {
        let record = SnapshotInvalidationRecord(
            reason: reason,
            scope: scope,
            maintenanceGeneration: runtimeProjectionMaintenanceGeneration,
            selectedAppWindowGeneration: selectedAppWindowSnapshotGeneration,
            clearedDeferredMaintenanceRequest: clearedDeferredMaintenanceRequest
        )
        lastSnapshotInvalidationRecord = record
        RuntimeLog.debug(.snapshot, record.logMessage)
    }

    func makeSnapshot() -> RuntimeSnapshot {
        let startMs = Self.monotonicMilliseconds()
        let source: String
        let snapshot: RuntimeSnapshot
        if let snapshotProviderOverride {
            source = "override"
            snapshot = snapshotProviderOverride()
        } else {
            source = "runtimeSnapshotService"
            snapshot = runtimeSnapshotService.snapshot()
        }
        let durationMs = Self.monotonicMilliseconds() - startMs
        logMakeSnapshot(source: source, snapshot: snapshot, durationMs: durationMs)
        return snapshot
    }

    func makeFastAppSnapshot() -> RuntimeSnapshot {
        let startMs = Self.monotonicMilliseconds()
        let source: String
        let snapshot: RuntimeSnapshot
        if let fastAppSnapshotProviderOverride {
            source = "fastOverride"
            snapshot = fastAppSnapshotProviderOverride()
        } else if let snapshotProviderOverride {
            source = "override"
            snapshot = snapshotProviderOverride()
        } else if let projection = runtimeSnapshotService.readAppSwitcherProjection() {
            source = projection.freshness.isCompleteForScope
                ? "runtimeProjection"
                : "runtimeProjectionDirty"
            snapshot = projection.appCycleSnapshot
        } else {
            source = "runtimeSnapshotService.lightweight"
            snapshot = runtimeSnapshotService.lightweightAppSnapshot()
        }
        let durationMs = Self.monotonicMilliseconds() - startMs
        logMakeSnapshot(source: source, snapshot: snapshot, durationMs: durationMs)
        return snapshot
    }
}
