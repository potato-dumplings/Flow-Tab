import CoreGraphics
import Foundation
import FlowTabCore

let sharedRuntimeProjectionService = RuntimeProjectionService()

final class RuntimeProjectionService: RuntimeProjectionServing, @unchecked Sendable {
    private enum CompletedCGWindowCleanupPolicy {
        case all
        case preservingActivationFreshness
    }

    private let maintenanceOwner: RuntimeProjectionMaintenanceOwner
    private let repairProvider: RuntimeProjectionRepairProviding
    private let mainTableProjectionBuilder: RuntimeMainTableProjectionBuilding
    let readModelStore: RuntimeReadModelStore
    private let appDirectoryProvider: RuntimeAppDirectoryProviding?
    private let reconciliationDrainer: RuntimeProjectionReconciliationDrainer
    private let transientRepairObservationDriver:
        RuntimeTransientRepairObservationDriver
    private let axWindowRepairAvailability: @Sendable () -> Bool
    private var pendingSearchIndexFreshnessBarrier = false

    private var canScheduleAXWindowRepair: Bool {
        axWindowRepairAvailability()
    }

    init(
        label: String = "FlowTab.RuntimeProjectionService",
        maintenanceOwner: RuntimeProjectionMaintenanceOwner? = nil,
        repairProvider: RuntimeProjectionRepairProviding? = nil,
        mainTableProjectionBuilder: RuntimeMainTableProjectionBuilding? = nil,
        appDirectoryProvider: RuntimeAppDirectoryProviding? = nil,
        readModelStore: RuntimeReadModelStore = RuntimeReadModelStore(),
        axWindowRepairAvailability: (@Sendable () -> Bool)? = nil,
        transientRepairObservationScheduler:
            any RuntimeTransientRepairObservationScheduling =
                RuntimeTransientRepairObservationScheduler(),
        transientRepairObservationPolicy:
            RuntimeTransientRepairObservationPolicy = .standard,
        reconciliationExecutor: @escaping RuntimeProjectionReconciliationExecutor =
            runtimeProjectionDefaultReconciliationExecutor
    ) {
        let usesSystemRepairProvider = repairProvider == nil
        self.axWindowRepairAvailability = axWindowRepairAvailability ?? {
            if usesSystemRepairProvider {
                return AccessibilityPermissionChecker.isTrusted()
            }
            return true
        }
        self.maintenanceOwner = maintenanceOwner
            ?? RuntimeProjectionMaintenanceOwner(label: label)
        if let repairProvider {
            self.repairProvider = repairProvider
            self.mainTableProjectionBuilder = mainTableProjectionBuilder
                ?? RuntimeUnavailableMainTableProjectionBuilder()
        } else {
            let windowRecordStore = RuntimeWindowRecordStore()
            let reconciliationCoordinator = RuntimeReconciliationCoordinator()
            self.repairProvider = RuntimeProjectionRepairProvider(
                windowRecordStore: windowRecordStore,
                reconciliationCoordinator: reconciliationCoordinator
            )
            self.mainTableProjectionBuilder = mainTableProjectionBuilder
                ?? RuntimeMainTableProjectionBuilder(windowRecordStore: windowRecordStore)
        }
        if let appDirectoryProvider {
            self.appDirectoryProvider = appDirectoryProvider
        } else {
            self.appDirectoryProvider = repairProvider == nil ? RuntimeWorkspaceAppDirectoryProvider() : nil
        }
        self.readModelStore = readModelStore
        reconciliationDrainer = RuntimeProjectionReconciliationDrainer(
            repairProvider: self.repairProvider,
            reconciliationExecutor: reconciliationExecutor
        )
        transientRepairObservationDriver = RuntimeTransientRepairObservationDriver(
            ownerQueue: self.maintenanceOwner.queue,
            scheduler: transientRepairObservationScheduler,
            policy: transientRepairObservationPolicy
        )
    }

    deinit {
        maintenanceOwner.cancelPendingPriorityWork()
        transientRepairObservationDriver.cancelAll(reason: "serviceDeinit")
    }

    func requestAppSwitcherProjectionMaintenance(reason: RuntimeProjectionMaintenanceReason) {
        maintenanceOwner.enqueue { [self] in
            defer {
                publishAppSwitcherProjectionMaintenanceCompletion(reason: reason)
            }
            let now = Date.timeIntervalSinceReferenceDate
            let appDirectoryProviderEvidenceCount = commitAppDirectoryProviderEvidenceLocked(generatedAt: now)
            var mainTableProjectionCommitted = commitMainTableAppSwitcherProjectionLocked(
                generatedAt: now,
                requiresExistingProjectionCoverage: true
            )
            let diagnostics = readModelStore.diagnostics()
            let canRepairAXWindows = canScheduleAXWindowRepair
            if canRepairAXWindows
                && !diagnostics.hasCompleteAppSwitcherProjection
                && !repairProvider.hasPendingReconciliationRequests(includeFullRepair: true) {
                repairProvider.scheduleFullRepairFallback(now: now)
            }
            let drainResult: RuntimeProjectionReconciliationDrainResult
            if canRepairAXWindows {
                drainResult = reconciliationDrainer.drainReadyRequests(now: now)
                scheduleTransientRepairObservationsLocked(
                    drainResult.deferredRequests
                )
            } else {
                drainResult = RuntimeProjectionReconciliationDrainResult()
            }
            let fullRepairProjectionCommitSummary = commitFullRepairEvidenceLocked(
                drainResult.fullRepairEvidence,
                generatedAt: now
            )
            commitCurrentAppRepairEvidenceLocked(
                drainResult.currentAppRepairEvidence,
                generatedAt: now
            )
            mainTableProjectionCommitted = commitAppSwitcherAfterScopedRepairIfNeededLocked(
                drainResult,
                generatedAt: now
            ) || mainTableProjectionCommitted
            let pendingSearchIndexCommit = commitPendingSearchIndexFreshnessBarrierIfNeededLocked(
                generatedAt: now
            )
            RuntimeLog.debug(
                .projection,
                [
                    "runtimeMaintenance",
                    "scope=appSwitcherProjection",
                    "reason=\(reason.rawValue)",
                    "dirtyApps=\(diagnostics.dirtyAppIDs.count)",
                    "dirtyPIDs=\(diagnostics.dirtyPIDs.count)",
                    "dirtyCGWindowIDs=\(diagnostics.dirtyCGWindowIDs.count)",
                    "pendingScopes=\(diagnostics.pendingRepairScopes.count)",
                    "appDirectoryProviderEvidence=\(appDirectoryProviderEvidenceCount)",
                    "startedRequests=\(drainResult.startedRequests.count)",
                    "completedRequests=\(drainResult.completedCount)",
                    "fullRepairEvidence=\(drainResult.fullRepairEvidence.count)",
                    "fullRepairWindowRecordRefreshes=\(drainResult.fullRepairEvidence.filter { $0.windowRecordRefresh != nil }.count)",
                    "fullRepairColdStartCommits=\(fullRepairProjectionCommitSummary.coldStartCommittedCount)",
                    "fullRepairDegradedCommits=\(fullRepairProjectionCommitSummary.degradedCommittedCount)",
                    "mainTableProjectionCommitted=\(mainTableProjectionCommitted ? 1 : 0)",
                    "pendingSearchIndexCommit=\(pendingSearchIndexCommit != nil ? 1 : 0)",
                    "currentAppRepairEvidence=\(drainResult.currentAppRepairEvidence.count)"
                ].joined(separator: " ")
            )
        }
    }

    func requestSearchIndexFreshnessBarrier(reason: RuntimeProjectionMaintenanceReason) {
        maintenanceOwner.enqueue { [self] in
            let now = Date.timeIntervalSinceReferenceDate
            transientRepairObservationDriver.cancelScoped(
                reason: "searchFreshnessBarrier"
            )
            pendingSearchIndexFreshnessBarrier = true
            let appDirectoryProviderEvidenceCount = commitAppDirectoryProviderEvidenceLocked(generatedAt: now)
            let scheduledMissingCoverageRepairs = scheduleSearchMissingWindowCoverageRepairsLocked(
                generatedAt: now
            )
            let scheduledDirtyTopologyRepairs = scheduleSearchDirtySpaceTopologyRepairsLocked(
                generatedAt: now
            )
            let promotedRequests = repairProvider.promoteSearchFreshnessBarrierRequests(now: now)
            let drainResult = drainSearchFreshnessBarrierReadyRequestsLocked(
                now: now
            )
            commitCurrentAppRepairEvidenceLocked(
                drainResult.currentAppRepairEvidence,
                generatedAt: now
            )
            let mainTableProjectionCommitted = commitMainTableAppSwitcherProjectionLocked(
                generatedAt: now,
                requiresExistingProjectionCoverage: true,
                clearsDirtyCGWindowIDs: drainResult.completedAffectedCGWindowIDs
            )
            let hasPendingRequests = repairProvider.hasPendingReconciliationRequests(
                includeFullRepair: false
            )
            let diagnostics = readModelStore.diagnostics()
            let mainTableSearchCommit = commitPendingSearchIndexFreshnessBarrierIfNeededLocked(
                deferredRequestCount: drainResult.deferredCount,
                hasPendingRequests: hasPendingRequests,
                generatedAt: now
            )
            RuntimeLog.debug(
                .projection,
                [
                    "runtimeMaintenance",
                    "scope=searchIndex",
                    "reason=\(reason.rawValue)",
                    "dirtyApps=\(diagnostics.dirtyAppIDs.count)",
                    "dirtyPIDs=\(diagnostics.dirtyPIDs.count)",
                    "dirtyCGWindowIDs=\(diagnostics.dirtyCGWindowIDs.count)",
                    "pendingScopes=\(diagnostics.pendingRepairScopes.count)",
                    "appDirectoryProviderEvidence=\(appDirectoryProviderEvidenceCount)",
                    "scheduledMissingCoverageRepairs=\(scheduledMissingCoverageRepairs)",
                    "scheduledDirtyTopologyRepairs=\(scheduledDirtyTopologyRepairs)",
                    "promotedRequests=\(promotedRequests.count)",
                    "startedRequests=\(drainResult.startedRequests.count)",
                    "maxReadyRepairs=\(runtimeSearchFreshnessBarrierMaxReadyRepairs)",
                    "completedRequests=\(drainResult.completedCount)",
                    "deferredRequests=\(drainResult.deferredCount)",
                    "pendingRequests=\(hasPendingRequests ? 1 : 0)",
                    "currentAppRepairEvidence=\(drainResult.currentAppRepairEvidence.count)",
                    "mainTableProjectionCommitted=\(mainTableProjectionCommitted ? 1 : 0)",
                    "committedSearchIndex=\(mainTableSearchCommit != nil ? 1 : 0)",
                    "mainTableSearchCommit=\(mainTableSearchCommit != nil ? 1 : 0)"
                ].joined(separator: " ")
            )
        }
    }

    private func drainSearchFreshnessBarrierReadyRequestsLocked(
        now: TimeInterval
    ) -> RuntimeProjectionReconciliationDrainResult {
        guard canScheduleAXWindowRepair else {
            return RuntimeProjectionReconciliationDrainResult()
        }
        var remainingBudget = runtimeSearchFreshnessBarrierMaxReadyRepairs
        var aggregateResult = RuntimeProjectionReconciliationDrainResult()

        while remainingBudget > 0 {
            let drainResult = reconciliationDrainer.drainReadyRequests(
                now: now,
                maxRequests: remainingBudget,
                includeFullRepair: false
            )
            guard !drainResult.startedRequests.isEmpty else { break }
            aggregateResult.append(drainResult)
            remainingBudget -= drainResult.startedRequests.count
            if drainResult.deferredCount > 0 {
                break
            }
        }

        scheduleTransientRepairObservationsLocked(
            aggregateResult.deferredRequests
        )
        return aggregateResult
    }

    func signalSpaceTopologyChanged() {
        maintenanceOwner.enqueue { [self] in
            let now = Date.timeIntervalSinceReferenceDate
            transientRepairObservationDriver.cancel(
                target: .spaceTopology,
                reason: "spaceTopologyChanged"
            )
            let signalFacts = repairProvider.recordSpaceTopologyChanged(now: now)
            readModelStore.markSpaceTopologyDirty(
                affectedCGWindowIDs: signalFacts.affectedCGWindowIDs,
                signature: signalFacts.signature,
                signatureSummary: signalFacts.signatureSummary,
                pendingScope: "spaceTopology",
                generatedAt: now
            )
            commitAppDirectoryProviderEvidenceLocked(generatedAt: now)
            commitMainTableAppSwitcherProjectionLocked(
                generatedAt: now,
                requiresExistingProjectionCoverage: true
            )
            drainReadyReconciliationRequestResultLocked(
                now: now,
                completedCGWindowCleanupPolicy: .all
            )
        }
    }

    func signalAppLaunched(
        appID: String,
        pid: pid_t,
        appDirectoryEntry: RuntimeAppDirectoryEntry? = nil
    ) {
        maintenanceOwner.enqueuePriority { [weak self] generation in
            self?.applyAppLaunchSignalLocked(
                appID: appID,
                pid: pid,
                appDirectoryEntry: appDirectoryEntry,
                generation: generation
            )
        }
    }

    func signalAppWindowsChanged(appID: String, pid: pid_t) {
        guard canScheduleAXWindowRepair else { return }
        maintenanceOwner.enqueue { [self] in
            let now = Date.timeIntervalSinceReferenceDate
            transientRepairObservationDriver.cancel(
                target: .app(pid),
                reason: "appWindowsChanged"
            )
            readModelStore.markAppWindowsDirty(
                appID: appID,
                pid: pid,
                pendingScope: "appWindows:\(appID)"
            )
            commitAppDirectoryProviderEvidenceLocked(generatedAt: now)
            commitMainTableCurrentAppProjectionLocked(
                appID: appID,
                pid: pid,
                clearsDirtyState: false,
                generatedAt: now
            )
            repairProvider.recordAppWindowsChanged(appID: appID, pid: pid, now: now)
            drainReadyReconciliationRequestsLocked(now: now)
        }
    }

    func signalSelectedCurrentAppWindowsChanged(appID: String, pid: pid_t) {
        guard canScheduleAXWindowRepair else { return }
        maintenanceOwner.enqueue { [self] in
            let now = Date.timeIntervalSinceReferenceDate
            transientRepairObservationDriver.cancel(
                target: .app(pid),
                reason: "selectedCurrentAppWindowsChanged"
            )
            readModelStore.markAppWindowsDirty(
                appID: appID,
                pid: pid,
                pendingScope: "selectedCurrentAppWindows:\(appID)"
            )
            commitAppDirectoryProviderEvidenceLocked(generatedAt: now)
            commitMainTableCurrentAppProjectionLocked(
                appID: appID,
                pid: pid,
                clearsDirtyState: false,
                generatedAt: now
            )
            repairProvider.recordSelectedCurrentAppWindowsChanged(appID: appID, pid: pid, now: now)
            drainReadyReconciliationRequestsLocked(now: now)
        }
    }

    func signalFocusedCurrentAppWindowsChanged() {
        guard canScheduleAXWindowRepair else { return }
        maintenanceOwner.enqueue { [self] in
            var focusedRead = readModelStore.readFocusedCurrentAppWindowProjection()
            let now = Date.timeIntervalSinceReferenceDate
            if focusedRead == nil {
                commitAppDirectoryProviderEvidenceLocked(generatedAt: now)
                focusedRead = readModelStore.readFocusedCurrentAppWindowProjection()
            }
            guard let focusedRead else {
                RuntimeLog.debug(
                    .projection,
                    "selectedAppWindowProjection result=missingFocusedAppDirectoryEntry"
                )
                return
            }
            transientRepairObservationDriver.cancel(
                target: .app(focusedRead.pid),
                reason: "focusedCurrentAppWindowsChanged"
            )
            readModelStore.markAppWindowsDirty(
                appID: focusedRead.appID,
                pid: focusedRead.pid,
                pendingScope: "selectedCurrentAppWindows:\(focusedRead.appID)"
            )
            commitAppDirectoryProviderEvidenceLocked(generatedAt: now)
            commitMainTableCurrentAppProjectionLocked(
                appID: focusedRead.appID,
                pid: focusedRead.pid,
                clearsDirtyState: false,
                generatedAt: now
            )
            repairProvider.recordSelectedCurrentAppWindowsChanged(
                appID: focusedRead.appID,
                pid: focusedRead.pid,
                now: now
            )
            drainReadyReconciliationRequestsLocked(now: now)
        }
    }

    func signalAXWindowDestroyed(appID: String, pid: pid_t, axWindowID: String) {
        maintenanceOwner.enqueue { [self] in
            let now = Date.timeIntervalSinceReferenceDate
            transientRepairObservationDriver.cancel(
                target: .app(pid),
                reason: "axWindowDestroyed"
            )
            let affectedCGWindowID = repairProvider.signalAXWindowDestroyed(
                appID: appID,
                processIdentifier: pid,
                axWindowID: axWindowID,
                now: now
            )
            readModelStore.markAppWindowsDirty(
                appID: appID,
                pid: pid,
                pendingScope: "axWindowDestroyed:\(appID)"
            )
            commitAppDirectoryProviderEvidenceLocked(generatedAt: now)
            commitMainTableCurrentAppProjectionLocked(
                appID: appID,
                pid: pid,
                clearsDirtyState: false,
                generatedAt: now
            )
            RuntimeLog.debug(
                .projection,
                "runtimeAXDestroyed appID=\(appID) pid=\(pid) axWindowID=\(axWindowID) affectedCGWindowID=\(affectedCGWindowID.map(String.init) ?? "none")"
            )
            drainReadyReconciliationRequestsLocked(now: now)
        }
    }

    func signalAppTerminated(appID: String, pid: pid_t) {
        performMaintenanceSynchronously { [self] in
            applyAppTerminationSignalLocked(
                appID: appID,
                pid: pid,
                generation: nil
            )
        }
    }

    func scheduleWorkspaceAppTerminated(appID: String, pid: pid_t) {
        maintenanceOwner.enqueuePriority { [weak self] generation in
            self?.applyAppTerminationSignalLocked(
                appID: appID,
                pid: pid,
                generation: generation
            )
        }
    }

    private func applyAppLaunchSignalLocked(
        appID: String,
        pid: pid_t,
        appDirectoryEntry: RuntimeAppDirectoryEntry?,
        generation: RuntimeProjectionMaintenanceGeneration
    ) {
        let now = Date.timeIntervalSinceReferenceDate
        transientRepairObservationDriver.cancel(
            target: .app(pid),
            reason: "appLaunched"
        )
        readModelStore.markAppLifecycleDirty(
            appID: appID,
            pid: pid,
            pendingScope: "appLaunched:\(appID)",
            appDirectoryEntry: appDirectoryEntry,
            generatedAt: now
        )
        commitAppDirectoryProviderEvidenceLocked(generatedAt: now)
        commitMainTableAppSwitcherProjectionLocked(
            generatedAt: now,
            requiresExistingProjectionCoverage: true
        )
        repairProvider.recordAppLaunched(appID: appID, pid: pid, now: now)
        RuntimeLog.debug(
            .projection,
            "runtimeLifecycle appLaunched appID=\(appID) pid=\(pid) maintenanceGeneration=\(generation)"
        )
        drainReadyReconciliationRequestsLocked(now: now)
    }

    private func applyAppTerminationSignalLocked(
        appID: String,
        pid: pid_t,
        generation: RuntimeProjectionMaintenanceGeneration?
    ) {
        let now = Date.timeIntervalSinceReferenceDate
        guard repairProvider.recordAppTerminated(
            appID: appID,
            processIdentifier: pid
        ) else {
            return
        }
        transientRepairObservationDriver.cancelApp(
            appID: appID,
            pid: pid,
            reason: "appTerminated"
        )
        commitAppDirectoryProviderEvidenceLocked(generatedAt: now)
        readModelStore.markAppTerminatedForMainTableProjection(appID: appID, pid: pid)
        commitMainTableAppSwitcherProjectionLocked(
            generatedAt: now,
            requiresExistingProjectionCoverage: true,
            permittedMissingAppIDs: [appID],
            clearsDirtyForAppID: appID,
            clearsDirtyForPID: pid
        )
        RuntimeLog.debug(
            .projection,
            "runtimeLifecycle appTerminated appID=\(appID) pid=\(pid) maintenanceGeneration=\(generation?.description ?? "synchronous")"
        )
    }

    func signalWindowFocusVerified(_ verification: RuntimeWindowFocusVerification) {
        maintenanceOwner.enqueuePriority { [weak self] generation in
            self?.applyWindowFocusVerificationLocked(
                verification,
                generation: generation
            )
        }
    }

    private func applyWindowFocusVerificationLocked(
        _ verification: RuntimeWindowFocusVerification,
        generation: RuntimeProjectionMaintenanceGeneration
    ) {
        let now = Date.timeIntervalSinceReferenceDate
        transientRepairObservationDriver.cancel(
            target: .app(verification.ownerPID),
            reason: "windowFocusVerified"
        )
        let affectedCGWindowIDs = repairProvider.recordWindowFocusVerification(
            verification,
            now: now
        )
        readModelStore.markWindowFocusVerified(
            verification,
            affectedCGWindowIDs: affectedCGWindowIDs,
            generatedAt: now
        )
        commitAppDirectoryProviderEvidenceLocked(generatedAt: now)
        commitMainTableCurrentAppProjectionLocked(
            appID: verification.appID,
            pid: verification.ownerPID,
            clearsDirtyState: false,
            generatedAt: now
        )
        drainReadyReconciliationRequestsLocked(now: now)
        RuntimeLog.debug(
            .projection,
            [
                "runtimeWindowFocusVerified",
                "maintenanceGeneration=\(generation)",
                "appID=\(verification.appID)",
                "pid=\(verification.ownerPID)",
                "windowID=\(verification.windowID)",
                "targetCG=\(verification.targetCGWindowID.map(String.init) ?? "nil")",
                "focusedCG=\(verification.focusedCGWindowID.map(String.init) ?? "nil")",
                "focusedAX=\(verification.focusedAXWindow == nil ? 0 : 1)",
                "affectedCGWindowIDs=\(affectedCGWindowIDs.map(String.init).sorted().joined(separator: ","))"
            ].joined(separator: " ")
        )
    }

    func signalWindowFocusVerified(appID: String, pid: pid_t) {
        signalWindowFocusVerified(
            RuntimeWindowFocusVerification(
                appID: appID,
                windowID: "",
                ownerPID: pid,
                targetCGWindowID: nil,
                focusedCGWindowID: nil,
                focusedAXWindow: nil,
                title: "",
                frame: nil,
                allowedActions: []
            )
        )
    }

    func signalWindowFocusReadbackMismatch(_ diagnostic: WindowBindingReadbackDiagnostic) {
        maintenanceOwner.enqueue { [self] in
            let now = Date.timeIntervalSinceReferenceDate
            transientRepairObservationDriver.cancel(
                target: .app(diagnostic.ownerPID),
                reason: "windowFocusReadbackMismatch"
            )
            let affectedCGWindowIDs = repairProvider.recordWindowFocusReadbackMismatch(
                diagnostic,
                now: now
            )
            readModelStore.markWindowFocusReadbackMismatch(
                diagnostic,
                affectedCGWindowIDs: affectedCGWindowIDs,
                generatedAt: now
            )
            commitAppDirectoryProviderEvidenceLocked(generatedAt: now)
            commitMainTableCurrentAppProjectionLocked(
                appID: diagnostic.appID,
                pid: diagnostic.ownerPID,
                clearsDirtyState: false,
                generatedAt: now
            )
            drainReadyReconciliationRequestsLocked(now: now)
            RuntimeLog.debug(
                .projection,
                [
                    "runtimeActivationReadbackMismatch",
                    "appID=\(diagnostic.appID)",
                    "pid=\(diagnostic.ownerPID)",
                    "windowID=\(diagnostic.windowID)",
                    "route=\(diagnostic.route)",
                    "reason=\(diagnostic.reason.rawValue)",
                    "affectedCGWindowIDs=\(affectedCGWindowIDs.map(String.init).sorted().joined(separator: ","))"
                ].joined(separator: " ")
            )
        }
    }

    @discardableResult
    func drainReadyReconciliationRequestsSynchronouslyForTesting(
        now: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) -> [RuntimeReconciliationRequest] {
        maintenanceOwner.performSynchronously {
            drainReadyReconciliationRequestsLocked(now: now)
        }
    }

    func waitForMaintenanceQueueForTesting() {
        maintenanceOwner.performSynchronously {}
    }

    @discardableResult
    private func drainReadyReconciliationRequestsLocked(now: TimeInterval) -> [RuntimeReconciliationRequest] {
        var result = drainReadyReconciliationRequestResultLocked(now: now)
        var commitGeneratedAt = now
        if pendingSearchIndexFreshnessBarrier {
            let followUpNow = Date.timeIntervalSinceReferenceDate
            let followUpResult = drainSearchFreshnessBarrierReadyRequestsLocked(now: followUpNow)
            commitCurrentAppRepairEvidenceLocked(
                followUpResult.currentAppRepairEvidence,
                generatedAt: followUpNow
            )
            commitAppSwitcherAfterScopedRepairIfNeededLocked(
                followUpResult,
                generatedAt: followUpNow
            )
            result.append(followUpResult)
            commitGeneratedAt = followUpNow
        }
        commitPendingSearchIndexFreshnessBarrierIfNeededLocked(generatedAt: commitGeneratedAt)
        return result.startedRequests
    }

    @discardableResult
    private func drainReadyReconciliationRequestResultLocked(
        now: TimeInterval,
        completedCGWindowCleanupPolicy: CompletedCGWindowCleanupPolicy =
            .preservingActivationFreshness
    ) -> RuntimeProjectionReconciliationDrainResult {
        guard canScheduleAXWindowRepair else {
            return RuntimeProjectionReconciliationDrainResult()
        }
        let result = reconciliationDrainer.drainReadyRequests(now: now)
        scheduleTransientRepairObservationsLocked(result.deferredRequests)
        commitFullRepairEvidenceLocked(
            result.fullRepairEvidence,
            generatedAt: now
        )
        commitCurrentAppRepairEvidenceLocked(
            result.currentAppRepairEvidence,
            generatedAt: now
        )
        commitAppSwitcherAfterScopedRepairIfNeededLocked(
            result,
            completedCGWindowCleanupPolicy: completedCGWindowCleanupPolicy,
            generatedAt: now
        )
        return result
    }

    private func scheduleTransientRepairObservationsLocked(
        _ requests: [RuntimeReconciliationRequest]
    ) {
        for request in requests {
            transientRepairObservationDriver.schedule(
                request,
                onReadbackRequested: { [weak self] id, attempt in
                    self?.handleTransientRepairConditionReadbackLocked(
                        requestID: id,
                        attempt: attempt
                    )
                },
                onWatchdogExpired: { [weak self] request in
                    self?.handleTransientRepairObservationWatchdogLocked(
                        request
                    )
                }
            )
        }
    }

    private func handleTransientRepairConditionReadbackLocked(
        requestID: UInt64,
        attempt: Int
    ) {
        let now = Date.timeIntervalSinceReferenceDate
        guard repairProvider.resumeDeferredReconciliationRequestForConditionReadback(
            id: requestID,
            attempt: attempt,
            now: now
        ) != nil else {
            RuntimeLog.debug(
                .projection,
                "transientRepairObservation state=stale requestID=\(requestID) attempt=\(attempt)"
            )
            return
        }
        drainReadyReconciliationRequestsLocked(now: now)
    }

    private func handleTransientRepairObservationWatchdogLocked(
        _ request: RuntimeReconciliationRequest
    ) {
        guard repairProvider.failDeferredReconciliationRequestAfterObservationWatchdog(
            id: request.id,
            attempt: request.attempt
        ) != nil else {
            RuntimeLog.debug(
                .projection,
                "transientRepairObservation state=staleWatchdog requestID=\(request.id) attempt=\(request.attempt)"
            )
            return
        }
        commitPendingSearchIndexFreshnessBarrierIfNeededLocked(
            generatedAt: Date.timeIntervalSinceReferenceDate
        )
    }

    @discardableResult
    private func commitAppSwitcherAfterScopedRepairIfNeededLocked(
        _ result: RuntimeProjectionReconciliationDrainResult,
        completedCGWindowCleanupPolicy: CompletedCGWindowCleanupPolicy = .all,
        generatedAt: TimeInterval
    ) -> Bool {
        guard !result.currentAppRepairEvidence.isEmpty
            || !result.completedAffectedCGWindowIDs.isEmpty
        else {
            return false
        }
        let clearedCGWindowIDs: Set<CGWindowID>
        switch completedCGWindowCleanupPolicy {
        case .all:
            clearedCGWindowIDs = result.completedAffectedCGWindowIDs
        case .preservingActivationFreshness:
            // Activation readback evidence stays stale until an explicit maintenance barrier.
            let activationCGWindowIDs = result.startedRequests.reduce(into: Set<CGWindowID>()) {
                protectedIDs, request in
                guard request.reasons.contains(.activationVerified)
                    || request.reasons.contains(.activationReadbackMismatch)
                else {
                    return
                }
                protectedIDs.formUnion(request.affectedCGWindowIDs)
            }
            clearedCGWindowIDs = result.completedAffectedCGWindowIDs.subtracting(
                activationCGWindowIDs
            )
        }
        return commitMainTableAppSwitcherProjectionLocked(
            generatedAt: generatedAt,
            requiresExistingProjectionCoverage: true,
            clearsDirtyCGWindowIDs: clearedCGWindowIDs
        )
    }

    @discardableResult
    private func commitFullRepairEvidenceLocked(
        _ evidenceBatch: [RuntimeFullRepairEvidence],
        generatedAt: TimeInterval
    ) -> RuntimeAppSwitcherProjectionCommitSummary {
        var summary = RuntimeAppSwitcherProjectionCommitSummary()
        for evidence in evidenceBatch {
            let diagnostics = readModelStore.diagnostics()
            readModelStore.commitFullRepairAppDirectoryEvidence(
                evidence.appDirectoryEntries,
                generatedAt: generatedAt
            )
            guard commitMainTableAppSwitcherProjectionLocked(
                generatedAt: generatedAt,
                requiresExistingProjectionCoverage: false
            ) else {
                continue
            }
            if diagnostics.hasAppSwitcherProjection || diagnostics.hasDirtyState {
                summary.degradedCommittedCount += 1
            } else {
                summary.coldStartCommittedCount += 1
            }
        }
        return summary
    }

    @discardableResult
    private func commitMainTableAppSwitcherProjectionLocked(
        generatedAt: TimeInterval,
        requiresExistingProjectionCoverage: Bool,
        permittedMissingAppIDs: Set<String> = [],
        clearsDirtyForAppID: String? = nil,
        clearsDirtyForPID: pid_t? = nil,
        clearsDirtyCGWindowIDs: Set<CGWindowID> = []
    ) -> Bool {
        guard
            let appDirectoryEntries = readModelStore.readAppDirectoryProjection()?.entries,
            let payload = mainTableProjectionBuilder.appSwitcherProjectionPayloadFromMainTables(
                appDirectoryEntries: appDirectoryEntries,
                generatedAt: generatedAt
            )
        else {
            return false
        }
        if requiresExistingProjectionCoverage,
           let existingProjection = readModelStore.readCommittedAppSwitcherProjectionCacheForMaintenance() {
            let payloadAppIDs = Set(payload.apps.map(\.id))
            let requiredExistingAppIDs = Set(existingProjection.apps.map(\.id))
                .subtracting(permittedMissingAppIDs)
            guard requiredExistingAppIDs.isSubset(of: payloadAppIDs) else {
                return false
            }
        }
        readModelStore.commitMainTableAppSwitcherProjectionPayload(
            payload,
            clearsDirtyForAppID: clearsDirtyForAppID,
            clearsDirtyForPID: clearsDirtyForPID,
            clearsDirtyCGWindowIDs: clearsDirtyCGWindowIDs,
            generatedAt: generatedAt
        )
        RuntimeProjectionNotificationPublisher.post(
            name: .runtimeAppSwitcherProjectionDidUpdate,
            object: self
        )
        return true
    }

    @discardableResult
    private func commitAppDirectoryProviderEvidenceLocked(generatedAt: TimeInterval) -> Int {
        guard let entries = appDirectoryProvider?.appDirectoryEntriesForRuntimeMaintenance() else {
            return 0
        }
        readModelStore.commitAppDirectoryProviderEvidence(entries, generatedAt: generatedAt)
        return entries.count
    }

    @discardableResult
    private func scheduleSearchMissingWindowCoverageRepairsLocked(
        generatedAt: TimeInterval
    ) -> Int {
        guard let appDirectoryEntries = readModelStore.readAppDirectoryProjection()?.entries,
              let payload = mainTableProjectionBuilder.searchIndexPayloadFromMainTables(
                appDirectoryEntries: appDirectoryEntries,
                generatedAt: generatedAt
              )
        else {
            return 0
        }

        let diagnostics = readModelStore.diagnostics()
        let entriesByPID = Dictionary(
            uniqueKeysWithValues: appDirectoryEntries.map { ($0.pid, $0) }
        )
        var scheduledCount = 0
        for pid in payload.coverageDiagnostics.missingWindowCoveragePIDs.sorted() {
            guard !diagnostics.dirtyPIDs.contains(pid),
                  let entry = entriesByPID[pid]
            else {
                continue
            }
            readModelStore.markAppWindowsDirty(
                appID: entry.appID,
                pid: pid,
                pendingScope: "searchWindowCoverage:\(entry.appID)"
            )
            repairProvider.recordSearchWindowCoverageNeeded(
                appID: entry.appID,
                pid: pid,
                now: generatedAt
            )
            scheduledCount += 1
        }
        return scheduledCount
    }

    @discardableResult
    private func scheduleSearchDirtySpaceTopologyRepairsLocked(
        generatedAt: TimeInterval
    ) -> Int {
        let diagnostics = readModelStore.diagnostics()
        guard diagnostics.pendingRepairScopes.contains("spaceTopology"),
              !diagnostics.dirtyCGWindowIDs.isEmpty
        else {
            return 0
        }
        let alreadyScheduledCGWindowIDs = repairProvider.pendingScopedReconciliationAffectedCGWindowIDs()
        let unscheduledDirtyCGWindowIDs = diagnostics.dirtyCGWindowIDs.subtracting(
            alreadyScheduledCGWindowIDs
        )
        guard !unscheduledDirtyCGWindowIDs.isEmpty else { return 0 }
        repairProvider.recordSpaceTopologyRepairNeeded(
            affectedCGWindowIDs: unscheduledDirtyCGWindowIDs,
            now: generatedAt
        )
        return 1
    }

    private func commitCurrentAppRepairEvidenceLocked(
        _ repairEvidence: [RuntimeCurrentAppRepairEvidence],
        generatedAt: TimeInterval
    ) {
        for evidence in repairEvidence {
            readModelStore.commitCurrentAppRepairAppDirectoryEvidence(
                evidence.appDirectoryEntries,
                generatedAt: generatedAt
            )
            commitMainTableCurrentAppProjectionLocked(
                appID: evidence.appID,
                pid: evidence.pid,
                clearsDirtyState: true,
                authoritativeCGWindowIDs: evidence.authoritativeCGWindowIDs,
                generatedAt: generatedAt
            )
        }
    }

    @discardableResult
    private func commitMainTableCurrentAppProjectionLocked(
        appID: String,
        pid: pid_t,
        clearsDirtyState: Bool,
        authoritativeCGWindowIDs: Set<CGWindowID>? = nil,
        generatedAt: TimeInterval
    ) -> Bool {
        let appDirectoryEntries = readModelStore
            .readAppDirectoryProjection()?
            .entries(forAppID: appID) ?? []
        guard let mainTablePayload = mainTableProjectionBuilder.currentAppWindowPayloadFromMainTables(
            appID: appID,
            pid: pid,
            appDirectoryEntries: appDirectoryEntries,
            generatedAt: generatedAt
        ) else {
            return false
        }
        readModelStore.commitCurrentAppWindowProjection(
            mainTablePayload,
            clearsDirtyState: clearsDirtyState,
            authoritativeCGWindowIDs: authoritativeCGWindowIDs,
            generatedAt: generatedAt
        )
        var userInfo: [AnyHashable: Any] = [
            RuntimeProjectionNotificationUserInfoKey.appID: appID
        ]
        if let committedProjection =
            readModelStore.readCurrentAppWindowProjection(
                appID: appID
            )
        {
            userInfo[
                RuntimeProjectionNotificationUserInfoKey
                    .currentAppWindowProjectionUpdateEvidence
            ] = RuntimeCurrentAppWindowProjectionUpdateEvidence(
                projection: committedProjection
            )
        }
        RuntimeProjectionNotificationPublisher.post(
            name: .runtimeCurrentAppWindowProjectionDidUpdate,
            object: self,
            userInfo: userInfo
        )
        return true
    }

    @discardableResult
    private func commitPendingSearchIndexFreshnessBarrierIfNeededLocked(
        deferredRequestCount: Int = 0,
        hasPendingRequests: Bool? = nil,
        generatedAt: TimeInterval
    ) -> RuntimeSearchIndexProjection? {
        guard pendingSearchIndexFreshnessBarrier else { return nil }
        let pendingRequests = hasPendingRequests ?? repairProvider.hasPendingReconciliationRequests(
            includeFullRepair: false
        )
        let committed = commitSearchIndexFromMainTablesLocked(
            deferredRequestCount: deferredRequestCount,
            hasPendingRequests: pendingRequests,
            generatedAt: generatedAt
        )
        guard committed != nil else { return nil }
        pendingSearchIndexFreshnessBarrier = false
        RuntimeProjectionNotificationPublisher.post(
            name: .runtimeCommittedSearchIndexDidUpdate,
            object: self
        )
        return committed
    }

    @discardableResult
    private func commitSearchIndexFromMainTablesLocked(
        deferredRequestCount: Int,
        hasPendingRequests: Bool,
        generatedAt: TimeInterval
    ) -> RuntimeSearchIndexProjection? {
        guard let appDirectoryEntries = readModelStore.readAppDirectoryProjection()?.entries else {
            logSearchIndexCommitRejectedLocked(
                reason: "missingAppDirectory",
                deferredRequestCount: deferredRequestCount,
                hasPendingRequests: hasPendingRequests,
                payload: nil
            )
            return nil
        }
        guard let payload = mainTableProjectionBuilder.searchIndexPayloadFromMainTables(
            appDirectoryEntries: appDirectoryEntries,
            generatedAt: generatedAt
        ) else {
            logSearchIndexCommitRejectedLocked(
                reason: "missingMainTablePayload",
                deferredRequestCount: deferredRequestCount,
                hasPendingRequests: hasPendingRequests,
                payload: nil
            )
            return nil
        }
        let committed = readModelStore.commitSearchFreshnessBarrierFromMainTablePayload(
            payload,
            deferredRequestCount: deferredRequestCount,
            hasPendingRequests: hasPendingRequests,
            generatedAt: generatedAt
        )
        if committed == nil {
            let diagnostics = readModelStore.diagnostics()
            let reason: String
            if deferredRequestCount > 0 {
                reason = "deferredRepair"
            } else if hasPendingRequests {
                reason = "pendingRepair"
            } else if !diagnostics.dirtyAppIDs.isEmpty
                || !diagnostics.dirtyPIDs.isEmpty
                || !diagnostics.dirtyCGWindowIDs.isEmpty
                || !diagnostics.pendingRepairScopes.isEmpty {
                reason = "dirtyReadModel"
            } else if !payload.hasCompleteWindowCoverage {
                reason = "incompleteMainTableCoverage"
            } else {
                reason = "storeRejected"
            }
            logSearchIndexCommitRejectedLocked(
                reason: reason,
                deferredRequestCount: deferredRequestCount,
                hasPendingRequests: hasPendingRequests,
                payload: payload
            )
        }
        return committed
    }

    private func logSearchIndexCommitRejectedLocked(
        reason: String,
        deferredRequestCount: Int,
        hasPendingRequests: Bool,
        payload: RuntimeSearchIndexPayload?
    ) {
        let diagnostics = readModelStore.diagnostics()
        RuntimeLog.debug(
            .projection,
            [
                "searchIndexCommitRejected",
                "reason=\(reason)",
                "dirtyApps=\(diagnostics.dirtyAppIDs.count)",
                "dirtyPIDs=\(diagnostics.dirtyPIDs.count)",
                "dirtyCGWindowIDs=\(diagnostics.dirtyCGWindowIDs.count)",
                "pendingScopes=\(diagnostics.pendingRepairScopes.count)",
                "deferredRequests=\(deferredRequestCount)",
                "pendingRequests=\(hasPendingRequests ? 1 : 0)",
                "hasPayload=\(payload == nil ? 0 : 1)",
                "hasCompleteWindowCoverage=\(payload?.hasCompleteWindowCoverage == true ? 1 : 0)",
                "coverage=\(payload?.coverageDiagnostics.logSummary ?? "none")"
            ].joined(separator: " ")
        )
    }

    private func performMaintenanceSynchronously(_ work: () -> Void) {
        maintenanceOwner.performSynchronously(work)
    }

}
