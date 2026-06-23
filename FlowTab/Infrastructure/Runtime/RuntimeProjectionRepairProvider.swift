import AppKit
import CoreGraphics
import Foundation
import FlowTabCore

final class RuntimeProjectionRepairProvider: RuntimeProjectionRepairProviding {
    private let runtimeFactProvider: any RuntimeProjectionRepairFactProviding
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
        let runtimeFactProvider = RuntimeSnapshotProvider(
            cgWindowListProvider: cgWindowListProvider,
            spaceTopologyProvider: spaceTopologyProvider,
            windowRecordStore: windowRecordStore,
            reconciliationCoordinator: reconciliationCoordinator
        )
        self.runtimeFactProvider = runtimeFactProvider
        self.repairFactSource = RuntimeProjectionRepairFactSource(
            runtimeFactProvider: runtimeFactProvider,
            windowRecordStore: windowRecordStore
        )
    }
}

extension RuntimeProjectionRepairProvider {
    func fullRepairProjectionPayload() -> RuntimeFullRepairProjectionPayload {
        fullRepairProjectionPayload(timingEvent: "fullRepairProjectionPayload")
    }

    private func fullRepairProjectionPayload(timingEvent: String) -> RuntimeFullRepairProjectionPayload {
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
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
            return uiTestProjectionFacts.fullRepairProjectionPayload
        }
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
            return RuntimeFullRepairProjectionPayload(
                apps: [],
                contextsByID: [:],
                appDirectoryEntries: runningAppFacts.appDirectoryEntries
            )
        }

        RuntimeLog.debug(.projection, "runningApps=\(runningApps.count)")
        let windowDataStartMs = RuntimePerformanceClock.monotonicMilliseconds()
        let windowData = repairFactSource.collectFullRepairWindowFacts(for: runningApps)
        let windowDataReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let selectionStartMs = windowDataReadyMs
        let policyFacts = repairFactSource.collectRepairAppLayerPolicyFacts()
        let selectionFacts = repairFactSource.collectFullRepairAppSelectionFacts(
            for: runningApps,
            windowFacts: windowData,
            policyFacts: policyFacts
        )
        let selectionReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        RuntimeLog.debug(
            .projection,
            "selectedApps=\(selectionFacts.selectedApps.count) appLayerCandidates=\(selectionFacts.appLayerCandidates.count) hideMinimized=\(policyFacts.hideMinimizedAppsFromAppLayer)"
        )

        guard !selectionFacts.appLayerCandidates.isEmpty else {
            let completeMs = RuntimePerformanceClock.monotonicMilliseconds()
            RuntimeProjectionDiagnostics.logTiming(
                timingEvent,
                fields: [
                    ("result", "empty"),
                    ("reason", "noAppLayerCandidates"),
                    ("runningApps", "\(runningApps.count)"),
                    ("selectedApps", "\(selectionFacts.selectedApps.count)"),
                    ("windows", "\(windowData.windowsByPID.values.reduce(0) { $0 + $1.count })"),
                    ("runningAppsMs", RuntimeProjectionDiagnostics.formatMilliseconds(runningAppsReadyMs - runningAppsStartMs)),
                    ("windowDataMs", RuntimeProjectionDiagnostics.formatMilliseconds(windowDataReadyMs - windowDataStartMs)),
                    ("selectionMs", RuntimeProjectionDiagnostics.formatMilliseconds(selectionReadyMs - selectionStartMs)),
                    ("totalMs", RuntimeProjectionDiagnostics.formatMilliseconds(completeMs - startMs))
                ]
            )
            return RuntimeFullRepairProjectionPayload(
                apps: [],
                contextsByID: [:],
                appDirectoryEntries: runningAppFacts.appDirectoryEntries
            )
        }
        let now = Date.timeIntervalSinceReferenceDate

        let rowsStartMs = RuntimePerformanceClock.monotonicMilliseconds()
        let currentAppProjectionInputs = selectionFacts.currentAppProjectionAssemblyInputs(
            rankByPID: windowData.rankByPID,
            generatedAt: now
        )
        for input in currentAppProjectionInputs {
            RuntimeLog.debug(
                .projection,
                "\(input.displayName) pid=\(input.pid) appID=\(input.appID) windows=\(input.windowSeeds.count)"
            )
        }
        let rowsReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        let payload = RuntimeFullRepairProjectionAssembler.payload(
            fromCurrentAppWindowProjectionInputs: currentAppProjectionInputs,
            appDirectoryEntries: runningAppFacts.appDirectoryEntries,
            duplicateContextHandler: { appID in
                RuntimeLog.debug(.projection, "duplicate appID fallback overwrite=\(appID)")
            }
        )
        let completeMs = RuntimePerformanceClock.monotonicMilliseconds()

        RuntimeProjectionDiagnostics.logTiming(
            timingEvent,
            fields: [
                ("result", "ready"),
                ("runningApps", "\(runningApps.count)"),
                ("selectedApps", "\(selectionFacts.selectedApps.count)"),
                ("appLayerCandidates", "\(selectionFacts.appLayerCandidates.count)"),
                ("windows", "\(payload.apps.reduce(0) { $0 + $1.windows.count })"),
                ("contexts", "\(payload.contextsByID.count)"),
                ("runningAppsMs", RuntimeProjectionDiagnostics.formatMilliseconds(runningAppsReadyMs - runningAppsStartMs)),
                ("windowDataMs", RuntimeProjectionDiagnostics.formatMilliseconds(windowDataReadyMs - windowDataStartMs)),
                ("selectionMs", RuntimeProjectionDiagnostics.formatMilliseconds(selectionReadyMs - selectionStartMs)),
                ("rowsMs", RuntimeProjectionDiagnostics.formatMilliseconds(rowsReadyMs - rowsStartMs)),
                ("sortContextMs", RuntimeProjectionDiagnostics.formatMilliseconds(completeMs - rowsReadyMs)),
                ("totalMs", RuntimeProjectionDiagnostics.formatMilliseconds(completeMs - startMs))
            ]
        )

        return payload
    }

    func currentAppWindowPayload(for appID: String) -> RuntimeCurrentAppWindowPayload? {
        if let uiTestProjectionFacts = repairFactSource.collectUITestProjectionDatasetFacts() {
            return uiTestProjectionFacts.currentAppWindowPayload(for: appID)
        }
        let runningApps = repairFactSource.collectRepairRunningApps().runningApps
        let matchingApps = runningApps.filter { RuntimeAppIdentity.appID(for: $0) == appID }
        guard !matchingApps.isEmpty else { return nil }

        let windowFacts = repairFactSource.collectCurrentAppWindowFacts(
            for: matchingApps,
            in: runningApps
        )
        let policyFacts = repairFactSource.collectRepairAppLayerPolicyFacts()
        guard let selectionFacts = repairFactSource.collectCurrentAppSelectionFacts(
            for: matchingApps,
            windowFacts: windowFacts,
            policyFacts: policyFacts
        ) else { return nil }
        guard selectionFacts.isIncludedInAppLayer else { return nil }

        let now = Date.timeIntervalSinceReferenceDate
        return RuntimeCurrentAppWindowPayload(
            assemblyInput: selectionFacts.currentAppProjectionAssemblyInput(
                appID: appID,
                rankByPID: windowFacts.rankByPID,
                rankFallback: 10_000,
                generatedAt: now
            )
        )
    }

    func focusedCurrentAppWindowPayload(processIdentifier pid: pid_t) -> RuntimeCurrentAppWindowPayload? {
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
        if let uiTestProjectionFacts = repairFactSource.collectUITestProjectionDatasetFacts() {
            let payload = uiTestProjectionFacts.focusedCurrentAppWindowPayload(processIdentifier: pid)
            RuntimeProjectionDiagnostics.logTiming(
                "focusedCurrentAppWindowPayload",
                fields: [
                    ("result", payload == nil ? "missingPID" : "uiTestDataset"),
                    ("pid", "\(pid)"),
                    ("windows", "\(payload?.candidate.windows.count ?? 0)"),
                    ("totalMs", RuntimeProjectionDiagnostics.formatMilliseconds(RuntimePerformanceClock.monotonicMilliseconds() - startMs))
                ]
            )
            return payload
        }

        let runningAppsStartMs = RuntimePerformanceClock.monotonicMilliseconds()
        let runningApps = repairFactSource.collectRepairRunningApps().runningApps
        let runningAppsReadyMs = RuntimePerformanceClock.monotonicMilliseconds()
        guard let app = runningApps.first(where: { $0.processIdentifier == pid })
            ?? NSRunningApplication(processIdentifier: pid)
        else {
            RuntimeProjectionDiagnostics.logTiming(
                "focusedCurrentAppWindowPayload",
                fields: [
                    ("result", "missingRunningApp"),
                    ("pid", "\(pid)"),
                    ("knownApps", "\(runningApps.count)"),
                    ("runningAppsMs", RuntimeProjectionDiagnostics.formatMilliseconds(runningAppsReadyMs - runningAppsStartMs)),
                    ("totalMs", RuntimeProjectionDiagnostics.formatMilliseconds(runningAppsReadyMs - startMs))
                ]
            )
            return nil
        }

        let windowFacts = repairFactSource.collectFocusedCurrentAppWindowFacts(
            for: app,
            in: runningApps,
            processIdentifier: pid
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
                "focusedCurrentAppWindowPayload",
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
            return nil
        }

        let now = Date.timeIntervalSinceReferenceDate
        let payload = RuntimeCurrentAppWindowPayload(
            assemblyInput: selectionFacts.currentAppProjectionAssemblyInput(
                appID: appID,
                rankByPID: windowFacts.rankByPID,
                rankFallback: 0,
                generatedAt: now
            )
        )
        let completeMs = RuntimePerformanceClock.monotonicMilliseconds()
        RuntimeProjectionDiagnostics.logTiming(
            "focusedCurrentAppWindowPayload",
            fields: [
                ("result", payload.candidate.windows.isEmpty ? "empty" : "ready"),
                ("appID", appID),
                ("pid", "\(pid)"),
                ("windows", "\(payload.candidate.windows.count)"),
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
        return payload
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

    func recordAppTerminated(processIdentifier pid: pid_t) {
        reconciliationCoordinator.cancelAppRequests(pid: pid)
        windowRecordStore.removeState(for: pid)
        AXLiveWindowRegistry.shared.remove(pid: pid)
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

    func hasPendingReconciliationRequests() -> Bool {
        reconciliationCoordinator.hasPendingRequests()
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
        now: TimeInterval,
        includeFullRepair: Bool
    ) -> [RuntimeReconciliationRequest] {
        reconciliationCoordinator.readyRequests(
            now: now,
            includeFullRepair: includeFullRepair
        )
    }

    func startReconciliationRequest(id: UInt64) -> RuntimeReconciliationRequest? {
        reconciliationCoordinator.startRequest(id: id)
    }

    func completeReconciliationRequest(id: UInt64) {
        reconciliationCoordinator.completeRequest(id: id)
    }

    func deferReconciliationRequestAfterTransientEmptyCurrentAppWindowPayload(
        id: UInt64,
        now: TimeInterval
    ) {
        reconciliationCoordinator.scheduleRetryAfterTransientEmptyCurrentAppWindowPayload(
            id: id,
            now: now
        )
    }

    func recordSpaceTopologyChanged(now: TimeInterval) -> RuntimeSpaceTopologySignalFacts {
        repairFactSource.collectSpaceTopologySignalFacts(now: now)
    }

    func reconcileAppWindows(
        processIdentifier pid: pid_t,
        affectedCGWindowIDs: Set<CGWindowID>
    ) -> RuntimeAppWindowReconciliationResult {
        let currentAppWindowPayload = focusedCurrentAppWindowPayload(processIdentifier: pid)
        let currentAppWindowPayloadWasEmpty = currentAppWindowPayload?.candidate.windows.isEmpty == true
        let mappingState = windowRecordStore.state(for: pid)
        let affectedWindowEvidence = mappingState?.affectedWindowEvidence(
            for: affectedCGWindowIDs
        ) ?? .empty
        return RuntimeAppWindowReconciliationResult(
            pid: pid,
            affectedCGWindowIDs: affectedCGWindowIDs,
            knownAffectedCGWindowIDs: affectedWindowEvidence.knownAffectedCGWindowIDs,
            exactAffectedCGWindowIDs: affectedWindowEvidence.exactAffectedCGWindowIDs,
            currentAppWindowPayload: currentAppWindowPayload,
            currentAppWindowPayloadWasEmpty: currentAppWindowPayloadWasEmpty,
            isTransientEmptyCurrentAppWindowPayload: mappingState?
                .isTransientEmptyCurrentAppWindowPayload(
                    currentAppWindowPayloadWasEmpty: currentAppWindowPayloadWasEmpty
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
