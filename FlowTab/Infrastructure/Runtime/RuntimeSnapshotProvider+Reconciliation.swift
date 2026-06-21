import AppKit
import Foundation

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

        let focusedAXEntry = RuntimeAXWindowEntry(
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
                stableWindowID: RuntimeWindowListEntry.cgStableWindowID(
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
