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
        guard snapshotProviderOverride == nil else { return }

        backgroundFullSnapshotRefreshGeneration &+= 1
        let generation = backgroundFullSnapshotRefreshGeneration
        let startMs = Self.monotonicMilliseconds()
        DispatchQueue.global(qos: .userInitiated).async {
            let snapshot = RuntimeSnapshotProvider().snapshot()
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

    func makeSnapshot() -> RuntimeSnapshot {
        let startMs = Self.monotonicMilliseconds()
        let source: String
        let snapshot: RuntimeSnapshot
        if let snapshotProviderOverride {
            source = "override"
            snapshot = snapshotProviderOverride()
        } else {
            source = "runtimeProvider"
            snapshot = snapshotProvider.snapshot()
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
            source = "lightweightRuntimeProvider"
            snapshot = snapshotProvider.lightweightAppSnapshot()
        }
        let durationMs = Self.monotonicMilliseconds() - startMs
        logMakeSnapshot(source: source, snapshot: snapshot, durationMs: durationMs)
        return snapshot
    }
}
