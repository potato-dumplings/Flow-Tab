import ApplicationServices
import AppKit
import Foundation

final class RuntimeWindowRecordStore {
    private var mappingStatesByPID: [pid_t: RuntimeWindowMappingState]

    init(mappingStatesByPID: [pid_t: RuntimeWindowMappingState] = [:]) {
        self.mappingStatesByPID = mappingStatesByPID
    }

    func state(for pid: pid_t) -> RuntimeWindowMappingState? {
        mappingStatesByPID[pid]
    }

    func setState(_ state: RuntimeWindowMappingState, for pid: pid_t) {
        mappingStatesByPID[pid] = state
    }

    func commitState(_ state: RuntimeWindowMappingState, for pid: pid_t) {
        if state.isEmpty {
            removeState(for: pid)
        } else {
            setState(state, for: pid)
        }
    }

    func removeState(for pid: pid_t) {
        mappingStatesByPID.removeValue(forKey: pid)
    }

    @discardableResult
    func recordSpaceTopologySnapshot(
        _ snapshot: RuntimeSpaceTopologySnapshot,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime,
        reconciliationCoordinator: RuntimeReconciliationCoordinator
    ) -> RuntimeSpaceTopologyDiff {
        RuntimeWindowRecordEvidence.recordSpaceTopologySnapshot(
            snapshot,
            now: now,
            reconciliationCoordinator: reconciliationCoordinator,
            mappingStatesByPID: &mappingStatesByPID
        )
    }

    func affectedCGWindowIDsByPID(
        affectedCGWindowIDs: Set<CGWindowID>,
        currentCGWindowsByPID: [pid_t: [RuntimeCGWindowEntry]]
    ) -> [pid_t: Set<CGWindowID>] {
        RuntimeWindowMappingState.affectedCGWindowIDsByPID(
            affectedCGWindowIDs: affectedCGWindowIDs,
            currentCGWindowsByPID: currentCGWindowsByPID,
            mappingStatesByPID: mappingStatesByPID
        )
    }

    func recordWindowFocusVerification(
        _ verification: RuntimeWindowFocusVerification,
        now: TimeInterval
    ) {
        RuntimeWindowRecordEvidence.recordWindowFocusVerification(
            verification,
            now: now,
            mappingStatesByPID: &mappingStatesByPID
        )
    }

    @discardableResult
    func clearDestroyedAXAttachment(
        processIdentifier pid: pid_t,
        axWindowID: String,
        now: TimeInterval
    ) -> CGWindowID? {
        RuntimeWindowRecordEvidence.clearDestroyedAXAttachment(
            processIdentifier: pid,
            axWindowID: axWindowID,
            now: now,
            mappingStatesByPID: &mappingStatesByPID
        )
    }

    func cleanup(keepingRunningApps runningApps: [NSRunningApplication]) {
        let runningPIDs = Set(runningApps.map(\.processIdentifier))
        mappingStatesByPID = mappingStatesByPID.filter { runningPIDs.contains($0.key) }
    }
}

private enum RuntimeWindowRecordEvidence {
    @discardableResult
    static func recordSpaceTopologySnapshot(
        _ snapshot: RuntimeSpaceTopologySnapshot,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime,
        reconciliationCoordinator: RuntimeReconciliationCoordinator,
        mappingStatesByPID: inout [pid_t: RuntimeWindowMappingState]
    ) -> RuntimeSpaceTopologyDiff {
        let diff = reconciliationCoordinator.applySpaceTopologySnapshot(snapshot, now: now)
        markWindowRecordsForSpaceTopologyReconciliation(
            diff,
            now: now,
            mappingStatesByPID: &mappingStatesByPID
        )
        return diff
    }

    static func recordWindowFocusVerification(
        _ verification: RuntimeWindowFocusVerification,
        now: TimeInterval,
        mappingStatesByPID: inout [pid_t: RuntimeWindowMappingState]
    ) {
        guard let focusedAXWindow = verification.focusedAXWindow,
              let focusedCGWindowID = verification.focusedCGWindowID else {
            return
        }
        var mappingState = mappingStatesByPID[verification.ownerPID] ?? RuntimeWindowMappingState()

        let axWindowID = focusedAXWindowID(
            for: focusedAXWindow,
            focusedCGWindowID: focusedCGWindowID,
            pid: verification.ownerPID,
            mappingState: mappingState
        )
        guard let axWindowID else { return }
        let focusedTitle = AXWindowInspector.title(for: focusedAXWindow)

        let focusedAXEntry = RuntimeAXWindowEntry(
            index: AXWindowInspector.windowIndex(
                from: axWindowID,
                expectedPID: verification.ownerPID
            ) ?? 0,
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
        mappingStatesByPID[verification.ownerPID] = RuntimeWindowMappingState(
            windowRecordsByCGWindowID: mappingState.windowRecordsByCGWindowID,
            currentAXToCG: currentAXToCG,
            validCGWindowIDs: mappingState.validCGWindowIDs.union([focusedCGWindowID]),
            lastAXWindowIDs: lastAXWindowIDs,
            hasObservedAXWindowHandle: true,
            consecutiveAXCollectionMisses: 0
        )
    }

    @discardableResult
    static func clearDestroyedAXAttachment(
        processIdentifier pid: pid_t,
        axWindowID: String,
        now: TimeInterval,
        mappingStatesByPID: inout [pid_t: RuntimeWindowMappingState]
    ) -> CGWindowID? {
        guard var mappingState = mappingStatesByPID[pid] else { return nil }
        let affectedCGWindowID = mappingState.clearDestroyedAXAttachment(
            axWindowID: axWindowID,
            observedAt: now
        )
        guard affectedCGWindowID != nil else { return nil }
        mappingStatesByPID[pid] = mappingState
        return affectedCGWindowID
    }

    private static func markWindowRecordsForSpaceTopologyReconciliation(
        _ diff: RuntimeSpaceTopologyDiff,
        now: TimeInterval,
        mappingStatesByPID: inout [pid_t: RuntimeWindowMappingState]
    ) {
        guard !diff.affectedCGWindowIDs.isEmpty else { return }

        for pid in mappingStatesByPID.keys.sorted() {
            guard var mappingState = mappingStatesByPID[pid] else { continue }
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
                mappingStatesByPID[pid] = mappingState
            }
        }
    }

    private static func focusedAXWindowID(
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
}
