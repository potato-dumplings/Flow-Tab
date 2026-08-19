import AppKit
import CoreGraphics
import Foundation
import FlowTabCore

final class RuntimeProjectionRepairProvider: RuntimeProjectionRepairProviding {
    private let windowRecordStore: RuntimeWindowRecordStore
    private let reconciliationCoordinator: RuntimeReconciliationCoordinator
    private let repairFactSource: RuntimeProjectionRepairFactSource

    init(
        cgWindowListProvider: RuntimeCGWindowListProviding = RuntimeSystemCGWindowListProvider(),
        spaceTopologyProvider: RuntimeSpaceTopologyProviding = RuntimeSystemSpaceTopologyProvider(),
        windowRecordStore: RuntimeWindowRecordStore = RuntimeWindowRecordStore(),
        reconciliationCoordinator: RuntimeReconciliationCoordinator = RuntimeReconciliationCoordinator()
    ) {
        self.windowRecordStore = windowRecordStore
        self.reconciliationCoordinator = reconciliationCoordinator
        let runtimeFactProvider = RuntimeSystemRepairFactProvider(
            cgWindowListProvider: cgWindowListProvider,
            spaceTopologyProvider: spaceTopologyProvider,
            windowRecordStore: windowRecordStore,
            reconciliationCoordinator: reconciliationCoordinator
        )
        self.repairFactSource = RuntimeProjectionRepairFactSource(
            runtimeFactProvider: runtimeFactProvider,
            windowRecordStore: windowRecordStore
        )
    }
}

private struct RuntimeFocusedCurrentAppRepairEvidence {
    let repairEvidence: RuntimeCurrentAppRepairEvidence?
    let currentAppWindowPayloadWasEmpty: Bool
}

extension RuntimeProjectionRepairProvider {
    func fullRepairEvidence() -> RuntimeFullRepairEvidence {
        fullRepairEvidence(timingEvent: "fullRepairEvidence")
    }

    private func fullRepairEvidence(timingEvent: String) -> RuntimeFullRepairEvidence {
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
#if FLOWTAB_TESTING
        if let uiTestProjectionFacts = repairFactSource.collectUITestProjectionDatasetFacts() {
            let completeMs = RuntimePerformanceClock.monotonicMilliseconds()
            RuntimeProjectionDiagnostics.logTiming(
                timingEvent,
                fields: [
                    ("result", "uiTestDataset"),
                    ("apps", "\(uiTestProjectionFacts.appCount)"),
                    ("windows", "\(uiTestProjectionFacts.windowCount)"),
                    ("totalMs", RuntimeProjectionDiagnostics.formatMilliseconds(completeMs - startMs))
                ]
            )
            return RuntimeFullRepairEvidence(
                appDirectoryEntries: uiTestProjectionFacts.appDirectoryEntries,
                windowRecordRefresh: uiTestProjectionFacts.windowRecordRefresh
            )
        }
#endif

        let runningAppsStartMs = RuntimePerformanceClock.monotonicMilliseconds()
        let runningAppFacts = repairFactSource.collectFullRepairRunningAppFacts()
        let runningApps = runningAppFacts.runningApps
        let runningAppsReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        guard !runningApps.isEmpty else {
            RuntimeProjectionDiagnostics.logTiming(
                timingEvent,
                fields: [
                    ("result", "empty"),
                    ("reason", "noRunningApps"),
                    ("runningAppsMs", RuntimeProjectionDiagnostics.formatMilliseconds(runningAppsReadyMs - runningAppsStartMs)),
                    ("totalMs", RuntimeProjectionDiagnostics.formatMilliseconds(runningAppsReadyMs - startMs))
                ]
            )
            return RuntimeFullRepairEvidence(
                appDirectoryEntries: runningAppFacts.appDirectoryEntries
            )
        }

        let windowDataStartMs = RuntimePerformanceClock.monotonicMilliseconds()
        let windowData = repairFactSource.collectFullRepairWindowFacts(for: runningApps)
        let windowDataReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let completeMs = RuntimePerformanceClock.monotonicMilliseconds()
        RuntimeProjectionDiagnostics.logTiming(
            timingEvent,
            fields: [
                ("result", "ready"),
                ("runningApps", "\(runningApps.count)"),
                ("projectedWindowPIDs", "\(windowData.windowsByPID.count)"),
                ("runningAppsMs", RuntimeProjectionDiagnostics.formatMilliseconds(runningAppsReadyMs - runningAppsStartMs)),
                ("windowDataMs", RuntimeProjectionDiagnostics.formatMilliseconds(windowDataReadyMs - windowDataStartMs)),
                ("totalMs", RuntimeProjectionDiagnostics.formatMilliseconds(completeMs - startMs))
            ]
        )
        return RuntimeFullRepairEvidence(
            appDirectoryEntries: runningAppFacts.appDirectoryEntries,
            windowRecordRefresh: windowData.refreshEvidence
        )
    }

    private func focusedCurrentAppRepairEvidence(
        processIdentifier pid: pid_t
    ) -> RuntimeFocusedCurrentAppRepairEvidence {
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
#if FLOWTAB_TESTING
        if let uiTestProjectionFacts = repairFactSource.collectUITestProjectionDatasetFacts() {
            let repairEvidence = uiTestProjectionFacts.focusedCurrentAppRepairEvidence(processIdentifier: pid)
            RuntimeProjectionDiagnostics.logTiming(
                "focusedCurrentAppRepairEvidence",
                fields: [
                    ("result", repairEvidence == nil ? "missingPID" : "uiTestDataset"),
                    ("pid", "\(pid)"),
                    ("empty", "\(repairEvidence?.currentAppWindowPayloadWasEmpty == true ? 1 : 0)"),
                    ("totalMs", RuntimeProjectionDiagnostics.formatMilliseconds(RuntimePerformanceClock.monotonicMilliseconds() - startMs))
                ]
            )
            return RuntimeFocusedCurrentAppRepairEvidence(
                repairEvidence: repairEvidence,
                currentAppWindowPayloadWasEmpty: repairEvidence?.currentAppWindowPayloadWasEmpty == true
            )
        }
#endif

        let runningAppsStartMs = RuntimePerformanceClock.monotonicMilliseconds()
        let runningApps = repairFactSource.collectRepairRunningApps().runningApps
        let runningAppsReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        guard let app = runningApps.first(where: { $0.processIdentifier == pid })
            ?? NSRunningApplication(processIdentifier: pid)
        else {
            RuntimeProjectionDiagnostics.logTiming(
                "focusedCurrentAppRepairEvidence",
                fields: [
                    ("result", "missingRunningApp"),
                    ("pid", "\(pid)"),
                    ("knownApps", "\(runningApps.count)"),
                    ("runningAppsMs", RuntimeProjectionDiagnostics.formatMilliseconds(runningAppsReadyMs - runningAppsStartMs)),
                    ("totalMs", RuntimeProjectionDiagnostics.formatMilliseconds(runningAppsReadyMs - startMs))
                ]
            )
            return RuntimeFocusedCurrentAppRepairEvidence(
                repairEvidence: nil,
                currentAppWindowPayloadWasEmpty: false
            )
        }

        let windowFacts = repairFactSource.collectFocusedCurrentAppWindowFacts(
            for: app,
            in: runningApps
        )
        let rowsStartMs = RuntimePerformanceClock.monotonicMilliseconds()
        let policyFacts = repairFactSource.collectRepairAppLayerPolicyFacts()
        let selectionFacts = repairFactSource.collectFocusedCurrentAppSelectionFacts(
            for: app,
            windowFacts: windowFacts,
            policyFacts: policyFacts
        )
        let appID = RuntimeAppIdentity.appID(for: selectionFacts.app)
        let rowsReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        if !selectionFacts.isIncludedInAppLayer {
            let completeMs = RuntimePerformanceClock.monotonicMilliseconds()
            RuntimeProjectionDiagnostics.logTiming(
                "focusedCurrentAppRepairEvidence",
                fields: [
                    ("result", "minimizedOnly"),
                    ("appID", appID),
                    ("pid", "\(pid)"),
                    ("windows", "\(selectionFacts.windows.count)"),
                    ("knownApps", "\(runningApps.count)"),
                    ("axApps", "\(selectionFacts.appGroup.count)"),
                    ("runningAppsMs", RuntimeProjectionDiagnostics.formatMilliseconds(runningAppsReadyMs - runningAppsStartMs)),
                    ("cleanupMs", RuntimeProjectionDiagnostics.formatMilliseconds(windowFacts.timings.cleanupMs)),
                    ("onscreenCGMs", RuntimeProjectionDiagnostics.formatMilliseconds(windowFacts.timings.onScreenCGMs)),
                    ("allCGMs", RuntimeProjectionDiagnostics.formatMilliseconds(windowFacts.timings.allCGMs)),
                    ("axMs", RuntimeProjectionDiagnostics.formatMilliseconds(windowFacts.timings.axMs)),
                    ("rowsMs", RuntimeProjectionDiagnostics.formatMilliseconds(rowsReadyMs - rowsStartMs)),
                    ("totalMs", RuntimeProjectionDiagnostics.formatMilliseconds(completeMs - startMs))
                ]
            )
            return RuntimeFocusedCurrentAppRepairEvidence(
                repairEvidence: nil,
                currentAppWindowPayloadWasEmpty: false
            )
        }

        let currentAppWindowPayloadWasEmpty = selectionFacts.windows.isEmpty
        let appDirectoryEntries = RuntimeAppDirectoryFactSource.entries(
            from: selectionFacts.appGroup,
            preservingRankFrom: windowFacts.rankByPID
        )
        let repairEvidence = RuntimeCurrentAppRepairEvidence(
            appID: appID,
            pid: selectionFacts.app.processIdentifier,
            appDirectoryEntries: appDirectoryEntries,
            currentAppWindowPayloadWasEmpty: currentAppWindowPayloadWasEmpty,
            authoritativeCGWindowIDs: Set(selectionFacts.windows.compactMap(\.cgWindowID))
        )
        let completeMs = RuntimePerformanceClock.monotonicMilliseconds()
        RuntimeProjectionDiagnostics.logTiming(
            "focusedCurrentAppRepairEvidence",
            fields: [
                ("result", currentAppWindowPayloadWasEmpty ? "empty" : "ready"),
                ("appID", appID),
                ("pid", "\(pid)"),
                ("windows", "\(selectionFacts.windows.count)"),
                ("knownApps", "\(runningApps.count)"),
                ("axApps", "\(selectionFacts.appGroup.count)"),
                ("runningAppsMs", RuntimeProjectionDiagnostics.formatMilliseconds(runningAppsReadyMs - runningAppsStartMs)),
                ("cleanupMs", RuntimeProjectionDiagnostics.formatMilliseconds(windowFacts.timings.cleanupMs)),
                ("onscreenCGMs", RuntimeProjectionDiagnostics.formatMilliseconds(windowFacts.timings.onScreenCGMs)),
                ("allCGMs", RuntimeProjectionDiagnostics.formatMilliseconds(windowFacts.timings.allCGMs)),
                ("axMs", RuntimeProjectionDiagnostics.formatMilliseconds(windowFacts.timings.axMs)),
                ("rowsMs", RuntimeProjectionDiagnostics.formatMilliseconds(rowsReadyMs - rowsStartMs)),
                ("totalMs", RuntimeProjectionDiagnostics.formatMilliseconds(completeMs - startMs))
            ]
        )
        return RuntimeFocusedCurrentAppRepairEvidence(
            repairEvidence: repairEvidence,
            currentAppWindowPayloadWasEmpty: currentAppWindowPayloadWasEmpty
        )
    }
}

extension RuntimeProjectionRepairProvider {
    func signalAXWindowDestroyed(
        appID: String,
        processIdentifier pid: pid_t,
        axWindowID: String,
        now: TimeInterval
    ) -> CGWindowID? {
        let affectedCGWindowID = windowRecordStore.clearDestroyedAXAttachment(
            processIdentifier: pid,
            axWindowID: axWindowID,
            now: now
        )
        reconciliationCoordinator.markAppDirty(
            appID: appID,
            pid: pid,
            reason: .axNotification,
            affectedCGWindowIDs: affectedCGWindowID.map { Set([$0]) } ?? [],
            now: now
        )
        return affectedCGWindowID
    }

    func recordAppTerminated(appID: String, processIdentifier pid: pid_t) -> Bool {
        if let pendingAppID = reconciliationCoordinator.pendingAppID(pid: pid),
           pendingAppID != appID {
            RuntimeLog.debug(
                .projection,
                "runtimeLifecycle appTerminatedIgnored appID=\(appID) pid=\(pid) pendingAppID=\(pendingAppID)"
            )
            return false
        }
        reconciliationCoordinator.cancelAppRequests(appID: appID, pid: pid)
        windowRecordStore.removeState(for: pid)
        AXLiveWindowRegistry.shared.remove(pid: pid)
        return true
    }

    func recordWindowFocusVerification(
        _ verification: RuntimeWindowFocusVerification,
        now: TimeInterval
    ) -> Set<CGWindowID> {
        windowRecordStore.recordWindowFocusVerification(
            verification,
            now: now
        )
        reconciliationCoordinator.markWindowFocusVerified(verification, now: now)
        return verification.affectedCGWindowIDs
    }

    func recordWindowFocusReadbackMismatch(
        _ diagnostic: WindowBindingReadbackDiagnostic,
        now: TimeInterval
    ) -> Set<CGWindowID> {
        windowRecordStore.recordWindowFocusReadbackMismatch(diagnostic, now: now)
        let affectedCGWindowIDs = diagnostic.affectedCGWindowIDs
        reconciliationCoordinator.markAppDirty(
            appID: diagnostic.appID,
            pid: diagnostic.ownerPID,
            reason: .activationReadbackMismatch,
            affectedCGWindowIDs: affectedCGWindowIDs,
            now: now
        )
        return affectedCGWindowIDs
    }

    func hasPendingReconciliationRequests(includeFullRepair: Bool) -> Bool {
        reconciliationCoordinator.hasPendingRequests(includeFullRepair: includeFullRepair)
    }

    func pendingScopedReconciliationAffectedCGWindowIDs() -> Set<CGWindowID> {
        reconciliationCoordinator.pendingScopedAffectedCGWindowIDs()
    }

    func scheduleFullRepairFallback(now: TimeInterval) {
        reconciliationCoordinator.scheduleFullRepairFallback(now: now)
    }

    func promoteSearchFreshnessBarrierRequests(now: TimeInterval) -> [RuntimeReconciliationRequest] {
        reconciliationCoordinator.promotePendingRequests(
            reason: .searchFreshnessBarrier,
            now: now
        )
    }

    func recordAppLaunched(appID: String, pid: pid_t, now: TimeInterval) {
        reconciliationCoordinator.markAppDirty(
            appID: appID,
            pid: pid,
            reason: .appLaunched,
            now: now
        )
    }

    func recordSearchWindowCoverageNeeded(appID: String, pid: pid_t, now: TimeInterval) {
        reconciliationCoordinator.markAppDirty(
            appID: appID,
            pid: pid,
            reason: .searchFreshnessBarrier,
            now: now
        )
    }

    func recordSpaceTopologyRepairNeeded(
        affectedCGWindowIDs: Set<CGWindowID>,
        now: TimeInterval
    ) {
        reconciliationCoordinator.markSpaceTopologyDirty(
            affectedCGWindowIDs: affectedCGWindowIDs,
            now: now
        )
    }

    func recordAppWindowsChanged(appID: String, pid: pid_t, now: TimeInterval) {
        reconciliationCoordinator.markAppDirty(
            appID: appID,
            pid: pid,
            reason: .axNotification,
            now: now
        )
    }

    func recordSelectedCurrentAppWindowsChanged(appID: String, pid: pid_t, now: TimeInterval) {
        reconciliationCoordinator.markAppDirty(
            appID: appID,
            pid: pid,
            reason: .selectedCurrentAppWindows,
            now: now
        )
    }

    func readyReconciliationRequests(
        includeFullRepair: Bool
    ) -> [RuntimeReconciliationRequest] {
        reconciliationCoordinator.readyRequests(includeFullRepair: includeFullRepair)
    }

    func startReconciliationRequest(id: UInt64) -> RuntimeReconciliationRequest? {
        reconciliationCoordinator.startRequest(id: id)
    }

    func completeReconciliationRequest(id: UInt64) {
        reconciliationCoordinator.completeRequest(id: id)
    }

    @discardableResult
    func deferReconciliationRequestAfterIncompleteEvidence(
        id: UInt64,
        requirements:
            Set<RuntimeReconciliationEvidenceRequirement>,
        now: TimeInterval
    ) -> RuntimeReconciliationRequest? {
        reconciliationCoordinator.deferRequestAfterIncompleteEvidence(
            id: id,
            requirements: requirements,
            now: now
        )
    }

    func resumeDeferredReconciliationRequestForConditionReadback(
        id: UInt64,
        attempt: Int,
        now: TimeInterval
    ) -> RuntimeReconciliationRequest? {
        reconciliationCoordinator.resumeDeferredRequestForConditionReadback(
            id: id,
            attempt: attempt,
            now: now
        )
    }

    func failDeferredReconciliationRequestAfterObservationWatchdog(
        id: UInt64,
        attempt: Int
    ) -> RuntimeReconciliationRequest? {
        reconciliationCoordinator.failDeferredRequestAfterObservationWatchdog(
            id: id,
            attempt: attempt
        )
    }

    func recordSpaceTopologyChanged(now: TimeInterval) -> RuntimeSpaceTopologySignalFacts {
        repairFactSource.collectSpaceTopologySignalFacts(now: now)
    }

    func reconcileAppWindows(
        processIdentifier pid: pid_t,
        affectedCGWindowIDs: Set<CGWindowID>
    ) -> RuntimeAppWindowReconciliationResult {
        let focusedRepairEvidence = focusedCurrentAppRepairEvidence(processIdentifier: pid)
        let mappingState = windowRecordStore.state(for: pid)
        let affectedWindowEvidence = mappingState?.affectedWindowEvidence(
            for: affectedCGWindowIDs
        ) ?? .empty
        return RuntimeAppWindowReconciliationResult(
            pid: pid,
            affectedCGWindowIDs: affectedCGWindowIDs,
            knownAffectedCGWindowIDs: affectedWindowEvidence.knownAffectedCGWindowIDs,
            exactAffectedCGWindowIDs: affectedWindowEvidence.exactAffectedCGWindowIDs,
            pendingDestroyedCGWindowIDs:
                affectedWindowEvidence.pendingDestroyedCGWindowIDs,
            currentAppRepairEvidence: focusedRepairEvidence.repairEvidence,
            isTransientEmptyCurrentAppWindowPayload: mappingState?
                .isTransientEmptyCurrentAppWindowPayload(
                    currentAppWindowPayloadWasEmpty: focusedRepairEvidence.currentAppWindowPayloadWasEmpty
                ) == true
        )
    }

    func reconcileSpaceTopology(
        affectedCGWindowIDs: Set<CGWindowID>
    ) -> [RuntimeAppWindowReconciliationResult] {
        let affectedTargets = repairFactSource.collectSpaceTopologyReconciliationTargets(
            affectedCGWindowIDs: affectedCGWindowIDs
        )
        return affectedTargets.map { target in
            reconcileAppWindows(
                processIdentifier: target.pid,
                affectedCGWindowIDs: target.affectedCGWindowIDs
            )
        }
    }
}
