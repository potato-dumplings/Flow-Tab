import AppKit
import Foundation

struct RuntimeAffectedWindowReconciliationTarget: Equatable {
    let pid: pid_t
    let appID: String
    let affectedCGWindowIDs: Set<CGWindowID>
}

struct RuntimeAppWindowReconciliationResult {
    let pid: pid_t
    let affectedCGWindowIDs: Set<CGWindowID>
    let knownAffectedCGWindowIDs: Set<CGWindowID>
    let exactAffectedCGWindowIDs: Set<CGWindowID>
    let currentAppWindowPayload: RuntimeCurrentAppWindowPayload?
    let currentAppWindowPayloadWasEmpty: Bool
    let isTransientEmptyCurrentAppWindowPayload: Bool
}

extension RuntimeSnapshotProvider {
    @discardableResult
    func recordSpaceTopologySnapshot(
        _ snapshot: RuntimeSpaceTopologySnapshot,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> RuntimeSpaceTopologyDiff {
        let diff = reconciliationCoordinator.applySpaceTopologySnapshot(snapshot, now: now)
        markWindowRecordsForSpaceTopologyReconciliation(diff, now: now)
        return diff
    }

    private func markWindowRecordsForSpaceTopologyReconciliation(
        _ diff: RuntimeSpaceTopologyDiff,
        now: TimeInterval
    ) {
        guard !diff.affectedCGWindowIDs.isEmpty else { return }

        for pid in windowMappingStateByPID.keys.sorted() {
            guard var mappingState = windowMappingStateByPID[pid] else { continue }
            var updated = false
            for cgWindowID in diff.affectedCGWindowIDs.sorted() {
                guard var record = mappingState.windowRecordsByCGWindowID[cgWindowID] else {
                    continue
                }
                record.markNeedsReconciliation(observedAt: now)
                if let recovery = record.spaceRecovery,
                   !Set(recovery.spaceIDs).isDisjoint(with: diff.removedSpaceIDs) {
                    record.invalidateSpaceRecovery(observedAt: now)
                }
                mappingState.windowRecordsByCGWindowID[cgWindowID] = record
                updated = true
            }
            if updated {
                windowMappingStateByPID[pid] = mappingState
            }
        }
    }

    func appReconciliationTargets(
        affectedCGWindowIDs: Set<CGWindowID>,
        currentCGWindowsByPID: [pid_t: [CGWindowEntry]]
    ) -> [RuntimeAffectedWindowReconciliationTarget] {
        guard !affectedCGWindowIDs.isEmpty else { return [] }

        var affectedCGWindowIDsByPID: [pid_t: Set<CGWindowID>] = [:]
        for (pid, cgWindows) in currentCGWindowsByPID {
            let affected = Set(cgWindows.map(\.id)).intersection(affectedCGWindowIDs)
            if !affected.isEmpty {
                affectedCGWindowIDsByPID[pid, default: []].formUnion(affected)
            }
        }

        for (pid, mappingState) in windowMappingStateByPID {
            let affected = Set(mappingState.windowRecordsByCGWindowID.keys)
                .intersection(affectedCGWindowIDs)
            if !affected.isEmpty {
                affectedCGWindowIDsByPID[pid, default: []].formUnion(affected)
            }
        }

        let appIDsByPID = Dictionary(
            uniqueKeysWithValues: filteredRunningApplications().map { app in
                (app.processIdentifier, Self.baseAppID(for: app))
            }
        )
        return affectedCGWindowIDsByPID.keys.sorted().map { pid in
            RuntimeAffectedWindowReconciliationTarget(
                pid: pid,
                appID: appIDsByPID[pid]
                    ?? NSRunningApplication(processIdentifier: pid).map(Self.baseAppID(for:))
                    ?? "pid:\(pid)",
                affectedCGWindowIDs: affectedCGWindowIDsByPID[pid] ?? []
            )
        }
    }

    @discardableResult
    func reconcileAppWindows(
        processIdentifier pid: pid_t,
        affectedCGWindowIDs: Set<CGWindowID>
    ) -> RuntimeAppWindowReconciliationResult {
        let repairPayload = focusedAppWindowRepairPayload(processIdentifier: pid)
        let currentAppWindowPayload = repairPayload.map(RuntimeCurrentAppWindowPayload.init)
        let currentAppWindowPayloadWasEmpty = currentAppWindowPayload?.candidate.windows.isEmpty == true
        let mappingState = windowMappingStateByPID[pid]
        let knownAffectedCGWindowIDs = mappingState.map {
            affectedCGWindowIDs.intersection($0.windowRecordsByCGWindowID.keys)
        } ?? []
        let exactAffectedCGWindowIDs = knownAffectedCGWindowIDs.filter { cgWindowID in
            mappingState?.windowRecordsByCGWindowID[cgWindowID]?.bindingConfidence == .exact
        }
        return RuntimeAppWindowReconciliationResult(
            pid: pid,
            affectedCGWindowIDs: affectedCGWindowIDs,
            knownAffectedCGWindowIDs: knownAffectedCGWindowIDs,
            exactAffectedCGWindowIDs: exactAffectedCGWindowIDs,
            currentAppWindowPayload: currentAppWindowPayload,
            currentAppWindowPayloadWasEmpty: currentAppWindowPayloadWasEmpty,
            isTransientEmptyCurrentAppWindowPayload: currentAppWindowPayloadWasEmpty
                && isLikelyTransientAXRebuild(for: pid)
        )
    }

    func recordWindowFocusVerification(
        _ verification: RuntimeWindowFocusVerification,
        now: TimeInterval
    ) {
        guard let focusedAXWindow = verification.focusedAXWindow,
              let focusedCGWindowID = verification.focusedCGWindowID else {
            return
        }
        var mappingState = windowMappingStateByPID[verification.ownerPID] ?? RuntimeWindowMappingState()

        let axWindowID = focusedAXWindowID(
            for: focusedAXWindow,
            focusedCGWindowID: focusedCGWindowID,
            pid: verification.ownerPID,
            mappingState: mappingState
        )
        guard let axWindowID else { return }
        let focusedTitle = AXWindowInspector.title(for: focusedAXWindow)

        let focusedAXEntry = AXWindowEntry(
            index: AXWindowInspector.windowIndex(from: axWindowID, expectedPID: verification.ownerPID) ?? 0,
            id: axWindowID,
            title: focusedTitle ?? verification.title,
            sourceTitle: focusedTitle,
            isMinimized: AXWindowInspector.isMinimized(focusedAXWindow),
            isFocused: AXWindowInspector.isFocused(focusedAXWindow),
            isMain: AXWindowInspector.isMain(focusedAXWindow),
            window: focusedAXWindow,
            frame: AXWindowInspector.frame(for: focusedAXWindow) ?? verification.frame
        )
        var record = mappingState.windowRecordsByCGWindowID[focusedCGWindowID]
            ?? RuntimeWindowRecord(
                cgWindowID: focusedCGWindowID,
                stableWindowID: Self.makeCGWindowID(
                    pid: verification.ownerPID,
                    cgWindowID: focusedCGWindowID
                ),
                firstSeenAt: now
            )
        record.applyExactMatch(
            axWindow: focusedAXEntry,
            resolvedTitle: focusedAXEntry.sourceTitle ?? verification.title,
            confirmationSource: .verifiedFocusReadback,
            observedAt: now,
            matchedCGWindow: nil
        )
        mappingState.windowRecordsByCGWindowID[focusedCGWindowID] = record

        var currentAXToCG = mappingState.currentAXToCG
        currentAXToCG[axWindowID] = focusedCGWindowID
        var lastAXWindowIDs = mappingState.lastAXWindowIDs
        lastAXWindowIDs.insert(axWindowID)
        windowMappingStateByPID[verification.ownerPID] = RuntimeWindowMappingState(
            windowRecordsByCGWindowID: mappingState.windowRecordsByCGWindowID,
            currentAXToCG: currentAXToCG,
            validCGWindowIDs: mappingState.validCGWindowIDs.union([focusedCGWindowID]),
            lastAXWindowIDs: lastAXWindowIDs,
            hasObservedAXWindowHandle: true,
            consecutiveSnapshotsWithoutAXWindows: 0
        )
    }

    private func focusedAXWindowID(
        for focusedAXWindow: AXUIElement,
        focusedCGWindowID: CGWindowID,
        pid: pid_t,
        mappingState: RuntimeWindowMappingState
    ) -> String? {
        if let currentAXWindowID = mappingState.currentCGToAX[focusedCGWindowID],
           let currentWindow = AXLiveWindowRegistry.shared.window(
                forWindowID: currentAXWindowID,
                expectedPID: pid
           ),
           CFEqual(currentWindow, focusedAXWindow) {
            return currentAXWindowID
        }
        if let currentAXWindowID = mappingState.currentAXToCG.keys.sorted().first(where: { axWindowID in
            guard let currentWindow = AXLiveWindowRegistry.shared.window(
                forWindowID: axWindowID,
                expectedPID: pid
            ) else {
                return false
            }
            return CFEqual(currentWindow, focusedAXWindow)
        }) {
            return currentAXWindowID
        }
        return AXLiveWindowRegistry.shared.windowID(forKnownWindow: focusedAXWindow, expectedPID: pid)
            ?? AXWindowInspector.makeVerifiedFocusFallbackWindowID(
                pid: pid,
                cgWindowID: focusedCGWindowID
            )
    }

    @discardableResult
    func signalAXWindowDestroyed(
        processIdentifier pid: pid_t,
        axWindowID: String,
        now: TimeInterval
    ) -> CGWindowID? {
        guard var mappingState = windowMappingStateByPID[pid] else { return nil }
        let affectedCGWindowID = mappingState.clearDestroyedAXAttachment(
            axWindowID: axWindowID,
            observedAt: now
        )
        guard affectedCGWindowID != nil else { return nil }
        windowMappingStateByPID[pid] = mappingState
        return affectedCGWindowID
    }
}
