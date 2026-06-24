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
    func fullAppSwitcherProjectionPayloadFromMainTables(
        appDirectoryEntries: [RuntimeAppDirectoryEntry],
        generatedAt: TimeInterval
    ) -> RuntimeFullRepairProjectionPayload? {
        guard !appDirectoryEntries.isEmpty else { return nil }

        var windowsByPID: [pid_t: [RuntimeWindowListEntry]] = [:]
        for entry in appDirectoryEntries {
            let displayName = Self.displayName(for: entry)
            windowsByPID[entry.pid] = windowRecordStore.projectedWindowEntries(
                processIdentifier: entry.pid,
                appName: displayName
            )
        }
        let windowStatsByPID = RuntimeAppDirectory.windowStats(
            for: appDirectoryEntries,
            windowsByPID: windowsByPID,
            isVisibleWindow: { !$0.isMinimized }
        )
        let entriesByAppID = RuntimeAppDirectory.groupedEntriesByAppID(appDirectoryEntries)
        let selectedEntries = RuntimeAppDirectory.selectPrimaryEntries(
            from: appDirectoryEntries,
            windowStatsByPID: windowStatsByPID,
            rankByPID: [:]
        )
        let sortedEntries = selectedEntries.sorted { lhs, rhs in
            let lhsDisplayName = Self.displayName(for: lhs)
            let rhsDisplayName = Self.displayName(for: rhs)
            if lhsDisplayName == rhsDisplayName {
                return lhs.appID < rhs.appID
            }
            return lhsDisplayName.localizedCaseInsensitiveCompare(rhsDisplayName) == .orderedAscending
        }

        let rows = sortedEntries.enumerated().map { index, entry in
            let displayName = Self.displayName(for: entry)
            let appGroup = RuntimeAppDirectory.sortedEntriesWithinGroup(
                entriesByAppID[entry.appID] ?? [entry],
                windowStatsByPID: windowStatsByPID,
                rankByPID: [:]
            )
            let windowSeeds = appGroup
                .flatMap { windowsByPID[$0.pid] ?? [] }
                .enumerated()
                .map { windowIndex, windowEntry in
                    windowEntry.projectionSeed(
                        lastActiveAt: generatedAt - Double(windowIndex)
                    )
                }
            let candidate = AppSwitchCandidate(
                id: entry.appID,
                displayName: displayName,
                groupID: RuntimeAppIdentity.groupID(
                    for: entry.bundleIdentifier,
                    fallbackName: displayName
                ),
                lastActiveAt: generatedAt - Double(index),
                windows: windowSeeds.map(\.candidate)
            )
            let context = NSRunningApplication(processIdentifier: entry.pid).map { runningApp in
                RuntimeAppContext(
                    appID: entry.appID,
                    runningApp: runningApp,
                    windowsByID: Dictionary(
                        uniqueKeysWithValues: windowSeeds.map { seed in
                            (seed.windowID, seed.context)
                        }
                    )
                )
            }
            return (candidate: candidate, context: context)
        }

        return RuntimeFullRepairProjectionPayload(
            apps: rows.map(\.candidate),
            contextsByID: Dictionary(
                uniqueKeysWithValues: rows.compactMap { row in
                    row.context.map { ($0.appID, $0) }
                }
            ),
            appDirectoryEntries: appDirectoryEntries
        )
    }

    func currentAppWindowPayloadFromMainTables(
        appID: String,
        pid: pid_t,
        appDirectoryEntries: [RuntimeAppDirectoryEntry],
        generatedAt: TimeInterval
    ) -> RuntimeCurrentAppWindowPayload? {
        guard let runningApp = NSRunningApplication(processIdentifier: pid) else { return nil }

        var directoryEntries = appDirectoryEntries.filter { $0.appID == appID }
        let selectedEntry: RuntimeAppDirectoryEntry
        if let matchingEntry = directoryEntries.first(where: { $0.pid == pid }) {
            selectedEntry = matchingEntry
        } else {
            selectedEntry = RuntimeAppDirectoryEntry(app: runningApp)
            directoryEntries.append(selectedEntry)
        }
        let displayName = selectedEntry.localizedName
            ?? runningApp.localizedName
            ?? selectedEntry.bundleIdentifier
            ?? appID
        let windowEntries = windowRecordStore.projectedWindowEntries(
            processIdentifier: pid,
            appName: displayName
        )
        guard !windowEntries.isEmpty else { return nil }

        return RuntimeCurrentAppWindowPayload(
            assemblyInput: RuntimeCurrentAppWindowProjectionAssemblyInput(
                appID: appID,
                displayName: displayName,
                groupID: RuntimeAppIdentity.groupID(
                    for: selectedEntry.bundleIdentifier ?? runningApp.bundleIdentifier,
                    fallbackName: displayName
                ),
                summaryLastActiveAt: RuntimeAppDirectory.stableLastActiveValue(forRank: 0),
                candidateLastActiveAt: generatedAt,
                pid: selectedEntry.pid,
                runningApp: runningApp,
                windowSeeds: windowEntries.enumerated().map { index, entry in
                    entry.projectionSeed(lastActiveAt: generatedAt - Double(index))
                },
                appDirectoryEntries: directoryEntries
            )
        )
    }

    private static func displayName(for entry: RuntimeAppDirectoryEntry) -> String {
        entry.localizedName ?? entry.bundleIdentifier ?? entry.appID
    }

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

    private func focusedCurrentAppRepairEvidence(
        processIdentifier pid: pid_t
    ) -> RuntimeFocusedCurrentAppRepairEvidence {
        let startMs = RuntimePerformanceClock.monotonicMilliseconds()
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
        let repairEvidence = RuntimeCurrentAppRepairEvidence(
            appID: appID,
            pid: selectionFacts.app.processIdentifier,
            appDirectoryEntries: selectionFacts.appGroup.map(RuntimeAppDirectoryEntry.init(app:)),
            currentAppWindowPayloadWasEmpty: currentAppWindowPayloadWasEmpty
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
