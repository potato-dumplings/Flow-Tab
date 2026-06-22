import AppKit
import Foundation
import FlowTabCore

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

        var currentAppProjectionInputs: [RuntimeCurrentAppWindowProjectionAssemblyInput] = []
        currentAppProjectionInputs.reserveCapacity(selectionFacts.appLayerCandidates.count)

        let rowsStartMs = RuntimePerformanceClock.monotonicMilliseconds()
        for (index, app) in selectionFacts.appLayerCandidates.enumerated() {
            let pid = app.processIdentifier
            let baseAppID = RuntimeAppIdentity.appID(for: app)
            let appGroup = selectionFacts.appsGroupedByAppID[baseAppID] ?? [app]
            let appID = baseAppID
            let displayName = app.localizedName ?? baseAppID

            let windows = selectionFacts.mergedWindowsByPrimaryPID[pid] ?? []
            RuntimeLog.debug(
                .projection,
                "\(displayName) pid=\(pid) appID=\(appID) windows=\(windows.count)"
            )

            let input = RuntimeCurrentAppWindowProjectionAssemblyInput(
                appID: appID,
                app: app,
                appGroup: appGroup,
                rankByPID: windowData.rankByPID,
                rankFallback: 10_000 + index,
                generatedAt: now,
                windowSeeds: windows.enumerated().map { entryIndex, entry in
                    entry.projectionSeed(lastActiveAt: now - Double(entryIndex))
                }
            )
            currentAppProjectionInputs.append(input)
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
            assemblyInput: RuntimeCurrentAppWindowProjectionAssemblyInput(
                appID: appID,
                app: selectionFacts.app,
                appGroup: selectionFacts.appGroup,
                rankByPID: windowFacts.rankByPID,
                rankFallback: 10_000,
                generatedAt: now,
                windowSeeds: selectionFacts.windows.enumerated().map { entryIndex, entry in
                    entry.projectionSeed(lastActiveAt: now - Double(entryIndex))
                }
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
            assemblyInput: RuntimeCurrentAppWindowProjectionAssemblyInput(
                appID: appID,
                app: selectionFacts.app,
                appGroup: selectionFacts.appGroup,
                rankByPID: windowFacts.rankByPID,
                rankFallback: 0,
                generatedAt: now,
                windowSeeds: selectionFacts.windows.enumerated().map { entryIndex, entry in
                    entry.projectionSeed(lastActiveAt: now - Double(entryIndex))
                }
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
