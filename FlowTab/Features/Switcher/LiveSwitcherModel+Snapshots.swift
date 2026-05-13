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
        let snapshot = snapshotWithWindowRecencyApplied(rawSnapshot)
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
            searchCoordinator.rebuildIndex(with: rebuiltSession.apps)
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

    func scheduleBackgroundFullSnapshotRefresh(triggerDirection: CycleDirection) {
        guard backgroundFullSnapshotRefreshEnabled else { return }
        guard snapshotProviderOverride == nil || backgroundFullSnapshotProviderOverride != nil else { return }

        backgroundFullSnapshotRefreshGeneration &+= 1
        let generation = backgroundFullSnapshotRefreshGeneration
        scheduleBackgroundFullSnapshotRefreshWork(
            triggerDirection: triggerDirection,
            generation: generation,
            scheduledMs: Self.monotonicMilliseconds()
        )
    }

    private func scheduleBackgroundFullSnapshotRefreshWork(
        triggerDirection: CycleDirection,
        generation: UInt64,
        scheduledMs: Double
    ) {
        let delay: DispatchTimeInterval = .milliseconds(150)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard generation == self.backgroundFullSnapshotRefreshGeneration else {
                    self.logBackgroundFullSnapshotRefresh(result: "staleBeforeStart", startMs: scheduledMs)
                    return
                }
                if let pendingAppID = self.selectedAppWindowSnapshotPendingAppID {
                    self.logBackgroundFullSnapshotRefresh(
                        result: "deferredSelectedAppPending:\(pendingAppID)",
                        startMs: scheduledMs
                    )
                    self.scheduleBackgroundFullSnapshotRefreshWork(
                        triggerDirection: triggerDirection,
                        generation: generation,
                        scheduledMs: scheduledMs
                    )
                    return
                }

                let startMs = Self.monotonicMilliseconds()
                let snapshotProvider = self.backgroundFullSnapshotProviderOverride
                let snapshotService = self.runtimeSnapshotService
                DispatchQueue.global(qos: .utility).async {
                    let snapshot = snapshotProvider?() ?? snapshotService.snapshot()
                    let snapshotReadMs = Self.monotonicMilliseconds()
                    Task { @MainActor [weak self] in
                        self?.completeBackgroundFullSnapshotRefresh(
                            snapshot,
                            triggerDirection: triggerDirection,
                            generation: generation,
                            startMs: startMs,
                            snapshotReadMs: snapshotReadMs
                        )
                    }
                }
            }
        }
    }

    func completeBackgroundFullSnapshotRefresh(
        _ rawSnapshot: RuntimeSnapshot,
        triggerDirection: CycleDirection,
        generation: UInt64,
        startMs: Double,
        snapshotReadMs: Double
    ) {
        guard generation == backgroundFullSnapshotRefreshGeneration else {
            logBackgroundFullSnapshotRefresh(result: "stale", startMs: startMs)
            return
        }
        guard let currentSession = session, overlayStyle == .appAndWindow else {
            logBackgroundFullSnapshotRefresh(result: "inactive", startMs: startMs)
            return
        }
        guard case .appCycle = currentSession.mode else {
            logBackgroundFullSnapshotRefresh(result: "nonAppCycle", startMs: startMs)
            return
        }

        let preferredSelectedAppID = currentSession.selectedApp.id
        let previousSearchState = searchViewState.isActive ? searchViewState : .inactive
        cancelPendingSearchComputation()
        let applied = applySnapshot(
            rawSnapshot,
            triggerDirection: triggerDirection,
            preferredSelectedAppID: preferredSelectedAppID,
            previousSearchState: previousSearchState,
            startMs: startMs,
            snapshotReadMs: snapshotReadMs,
            logEvent: "loadBackgroundFullSnapshot",
            resetWhenEmpty: false
        )
        logBackgroundFullSnapshotRefresh(
            result: applied ? "applied" : "empty",
            startMs: startMs
        )
        if applied {
            onSessionLayoutChanged?()
        }
    }

    func invalidateBackgroundFullSnapshotRefresh() {
        backgroundFullSnapshotRefreshGeneration &+= 1
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

        DispatchQueue.global(qos: .userInitiated).async {
            let orderedSnapshot: RuntimeHomeAppSnapshot?
            if let overrideSnapshot = providerOverride?(targetAppID) {
                orderedSnapshot = recencyTracker.homeSnapshotWithRecencyApplied(overrideSnapshot)
            } else {
                orderedSnapshot = snapshotService.homeAppSnapshotSynchronously(for: targetAppID)
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

    func invalidateSelectedAppWindowSnapshot() {
        selectedAppWindowSnapshotGeneration &+= 1
        selectedAppWindowSnapshotPendingAppID = nil
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
        } else {
            source = "runtimeSnapshotService.lightweight"
            snapshot = runtimeSnapshotService.lightweightAppSnapshot()
        }
        let durationMs = Self.monotonicMilliseconds() - startMs
        logMakeSnapshot(source: source, snapshot: snapshot, durationMs: durationMs)
        return snapshot
    }
}
