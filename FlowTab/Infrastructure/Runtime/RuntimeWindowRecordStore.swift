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

    func projectedWindowEntries(
        processIdentifier pid: pid_t,
        appName: String
    ) -> [RuntimeWindowListEntry] {
        state(for: pid)?.projectedWindowEntries(
            processIdentifier: pid,
            appName: appName
        ) ?? []
    }

    func hasWindowProjectionCoverage(processIdentifier pid: pid_t) -> Bool {
        state(for: pid)?.hasRecordedWindowCollection == true
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

    func resolveStableWindowMapping(
        axWindows: [RuntimeAXWindowEntry],
        cgWindows: [RuntimeCGWindowEntry],
        pid: pid_t,
        appName: String,
        remoteScanCompleteness: RuntimeAXRemoteWindowResolver.RemoteScanCompleteness? = nil
    ) -> RuntimeWindowMappingResolution {
        let validCGWindows = RuntimeWindowListSupplementer.selectSupplementalOffSpaceCGWindows(
            existingCGWindowIDs: [],
            allCGWindows: cgWindows
        )
        let validCGWindowIDs = Set(validCGWindows.map(\.id))
        let currentAXWindowsByID = Dictionary(uniqueKeysWithValues: axWindows.map { ($0.id, $0) })
        let previousState = state(for: pid) ?? RuntimeWindowMappingState()
        let observedAt = Date.timeIntervalSinceReferenceDate
        let hasAXWindowsInCurrentCollection = !axWindows.isEmpty
        let axWindowAbsenceIsAuthoritative = RuntimeAXWindowAbsencePolicy.isAbsenceAuthoritative(
            remoteScanCompleteness: remoteScanCompleteness
        )
        var mappingState = previousState
        mappingState.recordAXCollectionPresence(
            hasAXWindowsInCurrentCollection: hasAXWindowsInCurrentCollection,
            absenceIsAuthoritative: axWindowAbsenceIsAuthoritative
        )
        let allowSpaceOneWithoutCurrentAXHandle =
            RuntimeAXWindowAbsencePolicy.allowsSpaceOneWithoutCurrentAXHandle(
                hasObservedAXWindowHandle: mappingState.hasObservedAXWindowHandle,
                hasAXWindowsInCurrentCollection: hasAXWindowsInCurrentCollection,
                absenceIsAuthoritative: axWindowAbsenceIsAuthoritative,
                consecutiveAXCollectionMissCount: mappingState.consecutiveAXCollectionMisses
            )

        mappingState.refreshCGWindowRecords(
            validCGWindows: validCGWindows,
            pid: pid,
            observedAt: observedAt
        )
        var windowRecordsByCGWindowID = mappingState.windowRecordsByCGWindowID
        var bindingDiagnostics: [WindowBindingDiagnostic] = []

        let knownCGWindowsByID = RuntimeWindowRecord.knownCGWindowsByID(
            windowRecordsByCGWindowID: windowRecordsByCGWindowID,
            validCGWindows: validCGWindows
        )
        let stickyBindingResolution = mappingState.applyReusableStickyBindings(
            axWindows: axWindows,
            validCGWindowIDs: validCGWindowIDs,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName,
            observedAt: observedAt
        )
        windowRecordsByCGWindowID = mappingState.windowRecordsByCGWindowID
        var exactMatchesByAXWindowID = stickyBindingResolution.exactMatchesByAXWindowID
        let assignedAXWindowIDs = stickyBindingResolution.assignedAXWindowIDs
        bindingDiagnostics.append(contentsOf: stickyBindingResolution.bindingDiagnostics)

        let unresolvedAXWindows = axWindows.filter { !assignedAXWindowIDs.contains($0.id) }
        let unresolvedCGWindows = validCGWindows.filter { cgWindow in
            windowRecordsByCGWindowID[cgWindow.id]?.hasCurrentActivationHandle != true
        }
        let publicAssignmentResult = RuntimeWindowAssignmentMatcher.matchCGWindowAssignmentsWithDiagnostics(
            axWindows: unresolvedAXWindows,
            cgWindows: unresolvedCGWindows,
            appName: appName
        )
        let publicMatches = publicAssignmentResult.matches
        bindingDiagnostics.append(contentsOf: publicAssignmentResult.bindingDiagnostics)
        let publicMatchResolution = RuntimeWindowTopologyBindingResolver.resolveFullscreenContentRebindings(
            matches: publicMatches,
            axWindows: unresolvedAXWindows,
            cgWindows: validCGWindows,
            assignedCGWindowIDs: Set(exactMatchesByAXWindowID.values),
            appName: appName
        )
        RuntimeWindowRecord.applyExactMatches(
            publicMatchResolution.directMatches,
            source: .publicExactMatch,
            pid: pid,
            currentAXWindowsByID: currentAXWindowsByID,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName,
            observedAt: observedAt,
            windowRecordsByCGWindowID: &windowRecordsByCGWindowID,
            exactMatchesByAXWindowID: &exactMatchesByAXWindowID
        )
        RuntimeWindowRecord.applyExactMatches(
            publicMatchResolution.reboundMatches,
            source: .fullscreenContentRebinding,
            pid: pid,
            currentAXWindowsByID: currentAXWindowsByID,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName,
            observedAt: observedAt,
            windowRecordsByCGWindowID: &windowRecordsByCGWindowID,
            exactMatchesByAXWindowID: &exactMatchesByAXWindowID
        )

        let remainingAXWindows = axWindows.filter {
            exactMatchesByAXWindowID[$0.id] == nil
        }
        let privateExactBridgeMatches = RuntimeAXWindowRecovery.resolvePrivateExactBridgeMatches(
            axWindows: remainingAXWindows,
            validCGWindowIDs: validCGWindowIDs,
            assignedCGWindowIDs: Set(exactMatchesByAXWindowID.values)
        )
        let privateMatchResolution = RuntimeWindowTopologyBindingResolver.resolveFullscreenContentRebindings(
            matches: privateExactBridgeMatches,
            axWindows: remainingAXWindows,
            cgWindows: validCGWindows,
            assignedCGWindowIDs: Set(exactMatchesByAXWindowID.values),
            appName: appName
        )
        RuntimeWindowRecord.applyExactMatches(
            privateMatchResolution.directMatches,
            source: .privateExactBridge,
            pid: pid,
            currentAXWindowsByID: currentAXWindowsByID,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName,
            observedAt: observedAt,
            windowRecordsByCGWindowID: &windowRecordsByCGWindowID,
            exactMatchesByAXWindowID: &exactMatchesByAXWindowID
        )
        RuntimeWindowRecord.applyExactMatches(
            privateMatchResolution.reboundMatches,
            source: .fullscreenContentRebinding,
            pid: pid,
            currentAXWindowsByID: currentAXWindowsByID,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName,
            observedAt: observedAt,
            windowRecordsByCGWindowID: &windowRecordsByCGWindowID,
            exactMatchesByAXWindowID: &exactMatchesByAXWindowID
        )

        let remainingAXWindowsForDesktopSibling = axWindows.filter {
            exactMatchesByAXWindowID[$0.id] == nil
        }
        let desktopSiblingMatches = RuntimeWindowTopologyBindingResolver.resolveDesktopSiblingAXBindings(
            axWindows: remainingAXWindowsForDesktopSibling,
            cgWindows: validCGWindows,
            assignedCGWindowIDs: Set(exactMatchesByAXWindowID.values),
            appName: appName
        )
        RuntimeWindowRecord.applyExactMatches(
            desktopSiblingMatches,
            source: .desktopSiblingBinding,
            pid: pid,
            currentAXWindowsByID: currentAXWindowsByID,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName,
            observedAt: observedAt,
            windowRecordsByCGWindowID: &windowRecordsByCGWindowID,
            exactMatchesByAXWindowID: &exactMatchesByAXWindowID
        )

        let remainingAXWindowsForContentFallback = axWindows.filter {
            exactMatchesByAXWindowID[$0.id] == nil
        }
        let fullscreenContentFallbackResult = RuntimeWindowTopologyBindingResolver.resolveFullscreenContentFallbackBindingsWithDiagnostics(
            axWindows: remainingAXWindowsForContentFallback,
            cgWindows: validCGWindows,
            assignedCGWindowIDs: Set(exactMatchesByAXWindowID.values),
            appName: appName
        )
        bindingDiagnostics.append(contentsOf: fullscreenContentFallbackResult.bindingDiagnostics)
        RuntimeWindowRecord.applyExactMatches(
            fullscreenContentFallbackResult.matches,
            source: .fullscreenContentFallbackBinding,
            pid: pid,
            currentAXWindowsByID: currentAXWindowsByID,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName,
            observedAt: observedAt,
            windowRecordsByCGWindowID: &windowRecordsByCGWindowID,
            exactMatchesByAXWindowID: &exactMatchesByAXWindowID
        )

        mappingState.windowRecordsByCGWindowID = windowRecordsByCGWindowID
        mappingState.updateFallbackDisplayStateForRecords()
        mappingState.reconcileWindowRecordLifecycle(
            validCGWindowIDs: validCGWindowIDs,
            observedAt: observedAt
        )
        let currentAXToCG = exactMatchesByAXWindowID
        mappingState.commitDerivedIndexes(
            currentAXToCG: currentAXToCG,
            validCGWindowIDs: validCGWindowIDs,
            axWindows: axWindows,
            hasAXWindowsInCurrentCollection: hasAXWindowsInCurrentCollection,
            absenceIsAuthoritative: axWindowAbsenceIsAuthoritative
        )
        let nextState = mappingState
        windowRecordsByCGWindowID = nextState.windowRecordsByCGWindowID
        commitState(nextState, for: pid)

        let unmatchedAXCount = max(0, axWindows.count - exactMatchesByAXWindowID.count)
        let unmatchedCGCount = max(0, validCGWindows.count - Set(exactMatchesByAXWindowID.values).count)
        let stickyCount = windowRecordsByCGWindowID.values.filter(\.hasStickyBinding).count
        RuntimeLog.debug(
            .axMatch,
            "\(appName) records=\(windowRecordsByCGWindowID.count) sticky=\(stickyCount) exact=\(exactMatchesByAXWindowID.count) unmatchedAX=\(unmatchedAXCount) unmatchedCG=\(unmatchedCGCount)"
        )
        if allowSpaceOneWithoutCurrentAXHandle {
            if !axWindowAbsenceIsAuthoritative, let remoteScanCompleteness {
                RuntimeLog.debug(
                    .axMatch,
                    "\(appName) remote-ax-scan-incomplete; keeping space-1 windows remoteScan=\(AXWindowInspector.remoteScanLogDescription(remoteScanCompleteness))"
                )
            } else {
                RuntimeLog.debug(
                    .axMatch,
                    "\(appName) transient-ax-rebuild suspected; keeping space-1 windows axCollectionMisses=\(nextState.consecutiveAXCollectionMisses)/\(RuntimeAXWindowAbsencePolicy.transientRebuildGraceAXCollectionMissLimit)"
                )
            }
        }
        return RuntimeWindowMappingResolution(
            exactMatchesByAXWindowID: exactMatchesByAXWindowID,
            windowRecordsByCGWindowID: windowRecordsByCGWindowID,
            validCGWindows: validCGWindows,
            allowSpaceOneWithoutCurrentAXHandle: allowSpaceOneWithoutCurrentAXHandle,
            bindingDiagnostics: bindingDiagnostics
        )
    }
}

private extension RuntimeWindowMappingState {
    func projectedWindowEntries(
        processIdentifier pid: pid_t,
        appName: String
    ) -> [RuntimeWindowListEntry] {
        windowRecordsByCGWindowID.values
            .sorted { lhs, rhs in
                if lhs.isFocused != rhs.isFocused {
                    return lhs.isFocused
                }
                if lhs.isMain != rhs.isMain {
                    return lhs.isMain
                }
                if lhs.lastExactConfirmedAt != rhs.lastExactConfirmedAt {
                    return (lhs.lastExactConfirmedAt ?? 0) > (rhs.lastExactConfirmedAt ?? 0)
                }
                if lhs.lastSeenAt != rhs.lastSeenAt {
                    return lhs.lastSeenAt > rhs.lastSeenAt
                }
                return lhs.cgWindowID < rhs.cgWindowID
            }
            .compactMap { record in
                record.projectedWindowEntry(processIdentifier: pid, appName: appName)
            }
    }
}

private extension RuntimeWindowRecord {
    func projectedWindowEntry(
        processIdentifier pid: pid_t,
        appName: String
    ) -> RuntimeWindowListEntry? {
        let synthesizedCGWindow = synthesizedKnownCGWindowEntry()
        let title = displayTitle
            ?? synthesizedCGWindow.map {
                RuntimeWindowTitleResolver.supplementalCGWindowTitle(
                    appName: appName,
                    cgWindow: $0
                )
            }
        guard let title else { return nil }

        let rawSpaceIDs = spaceRecovery?.spaceIDs ?? synthesizedCGWindow?.spaceIDs ?? []
        let normalizedSpaceIDs = RuntimeWindowTopologyClassifier.normalizedSpaceIDs(rawSpaceIDs)
        let frame = displayFrame ?? synthesizedCGWindow?.bounds
        let spaceEvidence = RuntimeWindowTopologyClassifier.spaceEvidence(
            cgWindowID: cgWindowID,
            spaceIDs: normalizedSpaceIDs,
            bounds: frame,
            source: "window-record-projection"
        )
        let exposesWithoutCurrentAX = currentAXAttachment != nil
            || hasStickyBinding
            || spaceRecovery?.hasConfirmedActivationRoute == true
        guard exposesWithoutCurrentAX else { return nil }

        return RuntimeWindowListEntry(
            windowID: stableWindowID,
            title: title,
            isMinimized: isMinimized,
            ownerPID: pid,
            cgWindowID: cgWindowID,
            activationHandleID: currentAXWindowID,
            axWindow: currentAXAttachment?.axWindow,
            frame: frame,
            spaceIDs: normalizedSpaceIDs,
            isOnscreen: false,
            allowsPublicAXRecovery: spaceEvidence.allowsPublicAXRecovery,
            hasStickyBinding: hasStickyBinding,
            lastConfirmationSource: lastConfirmationSource,
            bindingConfidenceOverride: hasStickyBinding ? nil : .inferred,
            spaceEvidence: spaceEvidence
        )
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
