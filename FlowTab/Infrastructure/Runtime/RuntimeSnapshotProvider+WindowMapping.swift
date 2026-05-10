import AppKit
import ApplicationServices
import Foundation

struct RuntimeWindowMappingState {
    var windowRecordsByCGWindowID: [CGWindowID: RuntimeWindowRecord] = [:]
    var currentAXToCG: [String: CGWindowID] = [:]
    var currentCGToAX: [CGWindowID: String] = [:]
    var validCGWindowIDs: Set<CGWindowID> = []
    var lastAXWindowIDs: Set<String> = []
    var hasObservedAXWindowHandle = false
    var consecutiveSnapshotsWithoutAXWindows = 0

    var isEmpty: Bool {
        windowRecordsByCGWindowID.isEmpty
    }
}

struct RuntimeWindowMappingResolution {
    let exactMatchesByAXWindowID: [String: CGWindowID]
    let windowRecordsByCGWindowID: [CGWindowID: RuntimeWindowRecord]
    let validCGWindows: [RuntimeSnapshotProvider.CGWindowEntry]
    let allowSpaceOneWithoutCurrentAXHandle: Bool

    var knownCGWindowsByID: [CGWindowID: RuntimeSnapshotProvider.CGWindowEntry] {
        runtimeKnownCGWindowsByID(
            windowRecordsByCGWindowID: windowRecordsByCGWindowID,
            validCGWindows: validCGWindows
        )
    }
}

private let runtimeAXRebuildGraceMissingSnapshotLimit = 3

extension RuntimeSnapshotProvider {
    func isLikelyTransientAXRebuild(for pid: pid_t) -> Bool {
        guard let state = windowMappingStateByPID[pid] else { return false }
        guard state.hasObservedAXWindowHandle else { return false }
        let missingSnapshots = state.consecutiveSnapshotsWithoutAXWindows
        return missingSnapshots > 0 && missingSnapshots <= runtimeAXRebuildGraceMissingSnapshotLimit
    }

    func cleanupWindowMappingState(for runningApps: [NSRunningApplication]) {
        let runningPIDs = Set(runningApps.map(\.processIdentifier))
        windowMappingStateByPID = windowMappingStateByPID.filter { runningPIDs.contains($0.key) }
    }

    func resolvedStableWindowEntries(
        axWindows: [AXWindowEntry],
        cgWindows: [CGWindowEntry],
        pid: pid_t,
        appName: String
    ) -> [WindowListEntry] {
        let mappingResolution = resolveStableWindowMapping(
            axWindows: axWindows,
            cgWindows: cgWindows,
            pid: pid,
            appName: appName
        )
        let knownCGWindowsByID = mappingResolution.knownCGWindowsByID
        let fullscreenContentBounds = mappingResolution.validCGWindows.compactMap { cgWindow -> CGRect? in
            guard RuntimeWindowTopologyClassifier.isLikelyOffDesktopFullscreenContent(
                bounds: cgWindow.bounds,
                spaceIDs: cgWindow.spaceIDs
            ) else { return nil }
            return cgWindow.bounds
        }
        let exactEntries = axWindows.compactMap { axEntry -> WindowListEntry? in
            guard
                let cgWindowID = mappingResolution.exactMatchesByAXWindowID[axEntry.id],
                let record = mappingResolution.windowRecordsByCGWindowID[cgWindowID]
            else {
                return nil
            }
            let matchedCGTitle = knownCGWindowsByID[cgWindowID]?.title ?? record.displayTitle
            let sourceLooksLikeAppNameFallback = runtimeTitleLooksLikeAppNameFallback(
                axEntry.sourceTitle,
                appName: appName
            )
            let refreshedAXTitle: String?
            if sourceLooksLikeAppNameFallback
                || (
                    normalizedRuntimeWindowTitle(axEntry.sourceTitle) == nil
                        && normalizedRuntimeWindowTitle(matchedCGTitle) == nil
                )
            {
                refreshedAXTitle = AXWindowInspector.title(for: axEntry.window)
            } else {
                refreshedAXTitle = nil
            }
            let title = resolveStableWindowTitle(
                sourceTitle: axEntry.sourceTitle,
                matchedCGTitle: matchedCGTitle,
                appName: appName,
                fallbackIndex: axEntry.index,
                refreshedAXTitle: refreshedAXTitle
            )
            return WindowListEntry(
                windowID: record.stableWindowID,
                title: title,
                isMinimized: axEntry.isMinimized,
                ownerPID: pid,
                cgWindowID: cgWindowID,
                activationHandleID: axEntry.id,
                axWindow: axEntry.window,
                frame: axEntry.frame ?? record.displayFrame,
                spaceIDs: knownCGWindowsByID[cgWindowID]?.spaceIDs
                    ?? record.spaceRecovery?.spaceIDs
                    ?? [],
                isOnscreen: knownCGWindowsByID[cgWindowID]?.isOnscreen ?? false,
                allowsPublicAXRecovery: true,
                hasStickyBinding: true,
                lastConfirmationSource: record.lastConfirmationSource
            )
        }

        let exactCGWindowIDs = Set(exactEntries.compactMap(\.cgWindowID))
        let stickyCGEntries = mappingResolution.validCGWindows.compactMap { cgWindow -> WindowListEntry? in
            guard !exactCGWindowIDs.contains(cgWindow.id) else { return nil }
            guard
                let record = mappingResolution.windowRecordsByCGWindowID[cgWindow.id],
                record.hasStickyBinding
            else {
                return nil
            }
            let rawSpaceIDs = knownCGWindowsByID[cgWindow.id]?.spaceIDs
                ?? record.spaceRecovery?.spaceIDs
                ?? cgWindow.spaceIDs
            let normalizedSpaceIDs = RuntimeWindowTopologyClassifier.normalizedSpaceIDs(rawSpaceIDs)
            guard runtimeWindowCanBeExposedWithoutCurrentAXHandle(
                spaceIDs: normalizedSpaceIDs,
                isLikelyDesktopWrapper: RuntimeWindowTopologyClassifier.isLikelyDesktopWrapper(
                    bounds: cgWindow.bounds,
                    spaceIDs: normalizedSpaceIDs,
                    fullscreenContentBounds: fullscreenContentBounds
                ),
                hasFullscreenTopology: !fullscreenContentBounds.isEmpty,
                allowSpaceOneWithoutCurrentAXHandle: mappingResolution.allowSpaceOneWithoutCurrentAXHandle
            ) else {
                return nil
            }
            return WindowListEntry(
                windowID: record.stableWindowID,
                title: record.displayTitle
                    ?? runtimeSupplementalCGWindowTitle(appName: appName, cgWindow: cgWindow),
                isMinimized: record.isMinimized,
                ownerPID: pid,
                cgWindowID: cgWindow.id,
                activationHandleID: nil,
                axWindow: nil,
                frame: record.displayFrame ?? cgWindow.bounds,
                spaceIDs: normalizedSpaceIDs,
                isOnscreen: cgWindow.isOnscreen,
                allowsPublicAXRecovery: true,
                hasStickyBinding: true,
                lastConfirmationSource: record.lastConfirmationSource
            )
        }

        let stickyCGWindowIDs = Set(stickyCGEntries.compactMap(\.cgWindowID))
        var hiddenProvisionalCGOnlyCount = 0
        let unmatchedCGEntries = mappingResolution.validCGWindows.compactMap { cgWindow -> WindowListEntry? in
            guard !exactCGWindowIDs.contains(cgWindow.id) else { return nil }
            guard !stickyCGWindowIDs.contains(cgWindow.id) else { return nil }
            let record = mappingResolution.windowRecordsByCGWindowID[cgWindow.id]
            let rawSpaceIDs = knownCGWindowsByID[cgWindow.id]?.spaceIDs
                ?? record?.spaceRecovery?.spaceIDs
                ?? cgWindow.spaceIDs
            let normalizedSpaceIDs = RuntimeWindowTopologyClassifier.normalizedSpaceIDs(rawSpaceIDs)
            guard !normalizedSpaceIDs.isEmpty else {
                hiddenProvisionalCGOnlyCount += 1
                return nil
            }
            guard runtimeWindowCanBeExposedWithoutCurrentAXHandle(
                spaceIDs: normalizedSpaceIDs,
                isLikelyDesktopWrapper: RuntimeWindowTopologyClassifier.isLikelyDesktopWrapper(
                    bounds: cgWindow.bounds,
                    spaceIDs: normalizedSpaceIDs,
                    fullscreenContentBounds: fullscreenContentBounds
                ),
                hasFullscreenTopology: !fullscreenContentBounds.isEmpty,
                allowSpaceOneWithoutCurrentAXHandle: mappingResolution.allowSpaceOneWithoutCurrentAXHandle
            ) else {
                hiddenProvisionalCGOnlyCount += 1
                return nil
            }
            return WindowListEntry(
                windowID: record?.stableWindowID ?? Self.makeCGWindowID(pid: pid, cgWindowID: cgWindow.id),
                title: record?.displayTitle
                    ?? runtimeSupplementalCGWindowTitle(appName: appName, cgWindow: cgWindow),
                isMinimized: false,
                ownerPID: pid,
                cgWindowID: cgWindow.id,
                activationHandleID: nil,
                axWindow: nil,
                frame: record?.displayFrame ?? cgWindow.bounds,
                spaceIDs: normalizedSpaceIDs,
                isOnscreen: cgWindow.isOnscreen,
                allowsPublicAXRecovery: true,
                hasStickyBinding: false,
                lastConfirmationSource: nil
            )
        }
        if hiddenProvisionalCGOnlyCount > 0 {
            RuntimeLog.info(
                "AXMatch",
                "\(appName) hidden-provisional-cg windows=\(hiddenProvisionalCGOnlyCount)"
            )
        }

        let unmatchedAXEntries = stickyCGEntries + unmatchedCGEntries
        let deduplicatedUnmatchedAXEntries = deduplicateUnmatchedAXEntriesBySpace(
            unmatchedAXEntries,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName
        )

        return orderWindowEntriesForPresentation(exactEntries + deduplicatedUnmatchedAXEntries)
    }

    private func orderWindowEntriesForPresentation(_ entries: [WindowListEntry]) -> [WindowListEntry] {
        let orderedEntries = entries.enumerated().sorted { lhs, rhs in
            let lhsHasActivationHandle = lhs.element.activationHandleID != nil || lhs.element.axWindow != nil
            let rhsHasActivationHandle = rhs.element.activationHandleID != nil || rhs.element.axWindow != nil
            if lhsHasActivationHandle != rhsHasActivationHandle {
                return lhsHasActivationHandle
            }
            if lhs.element.isOnscreen != rhs.element.isOnscreen {
                return lhs.element.isOnscreen
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
        return orderedEntries
    }

    func resolveStableWindowMapping(
        axWindows: [AXWindowEntry],
        cgWindows: [CGWindowEntry],
        pid: pid_t,
        appName: String
    ) -> RuntimeWindowMappingResolution {
        let validCGWindows = selectSupplementalOffSpaceCGWindows(
            existingCGWindowIDs: [],
            allCGWindows: cgWindows
        )
        let validCGWindowIDs = Set(validCGWindows.map(\.id))
        let currentAXWindowsByID = Dictionary(uniqueKeysWithValues: axWindows.map { ($0.id, $0) })
        let previousState = windowMappingStateByPID[pid] ?? RuntimeWindowMappingState()
        let observedAt = Date.timeIntervalSinceReferenceDate
        let hasAXWindowsInCurrentSnapshot = !axWindows.isEmpty
        let hasObservedAXWindowHandle = previousState.hasObservedAXWindowHandle || hasAXWindowsInCurrentSnapshot
        let consecutiveSnapshotsWithoutAXWindows = hasAXWindowsInCurrentSnapshot
            ? 0
            : previousState.consecutiveSnapshotsWithoutAXWindows + 1
        let allowSpaceOneWithoutCurrentAXHandle = hasObservedAXWindowHandle
            && !hasAXWindowsInCurrentSnapshot
            && consecutiveSnapshotsWithoutAXWindows <= runtimeAXRebuildGraceMissingSnapshotLimit

        var windowRecordsByCGWindowID = previousState.windowRecordsByCGWindowID
        for cgWindow in validCGWindows {
            var record = windowRecordsByCGWindowID[cgWindow.id]
                ?? RuntimeWindowRecord(
                    cgWindowID: cgWindow.id,
                    stableWindowID: Self.makeCGWindowID(pid: pid, cgWindowID: cgWindow.id),
                    firstSeenAt: observedAt
                )
            record.refreshCGState(from: cgWindow, observedAt: observedAt)
            record.updateFallbackDisplayStateIfNeeded()
            windowRecordsByCGWindowID[cgWindow.id] = record
        }
        for cgWindowID in windowRecordsByCGWindowID.keys.sorted() {
            guard var record = windowRecordsByCGWindowID[cgWindowID] else { continue }
            record.clearCurrentAXAttachment()
            windowRecordsByCGWindowID[cgWindowID] = record
        }

        let knownCGWindowsByID = runtimeKnownCGWindowsByID(
            windowRecordsByCGWindowID: windowRecordsByCGWindowID,
            validCGWindows: validCGWindows
        )
        var exactMatchesByAXWindowID: [String: CGWindowID] = [:]
        var assignedAXWindowIDs: Set<String> = []

        for cgWindowID in windowRecordsByCGWindowID.keys.sorted() {
            guard var record = windowRecordsByCGWindowID[cgWindowID] else { continue }
            let reusedAXWindow = resolveStickyAXWindow(
                for: record,
                axWindows: axWindows,
                assignedAXWindowIDs: assignedAXWindowIDs
            )

            if let reusedAXWindow {
                let resolvedTitle = resolveStableWindowTitle(
                    sourceTitle: reusedAXWindow.sourceTitle,
                    matchedCGTitle: knownCGWindowsByID[cgWindowID]?.title ?? record.displayTitle,
                    appName: appName,
                    fallbackIndex: reusedAXWindow.index,
                    refreshedAXTitle: nil
                )
                record.applyExactMatch(
                    axWindow: reusedAXWindow,
                    resolvedTitle: resolvedTitle,
                    confirmationSource: .stickyBinding,
                    observedAt: observedAt,
                    matchedCGWindow: knownCGWindowsByID[cgWindowID]
                )
                exactMatchesByAXWindowID[reusedAXWindow.id] = cgWindowID
                assignedAXWindowIDs.insert(reusedAXWindow.id)
            } else {
                record.updateFallbackDisplayStateIfNeeded()
            }

            windowRecordsByCGWindowID[cgWindowID] = record
        }

        let unresolvedAXWindows = axWindows.filter { !assignedAXWindowIDs.contains($0.id) }
        let unresolvedCGWindows = validCGWindows.filter { cgWindow in
            windowRecordsByCGWindowID[cgWindow.id]?.hasCurrentActivationHandle != true
        }
        let publicMatches = Self.matchCGWindowAssignments(
            axWindows: unresolvedAXWindows,
            cgWindows: unresolvedCGWindows,
            appName: appName
        )
        let publicMatchResolution = Self.resolveFullscreenContentRebindings(
            matches: publicMatches,
            axWindows: unresolvedAXWindows,
            cgWindows: validCGWindows,
            assignedCGWindowIDs: Set(exactMatchesByAXWindowID.values),
            appName: appName
        )
        applyExactMatches(
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
        applyExactMatches(
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
        let privateExactBridgeMatches = Self.resolvePrivateExactBridgeMatches(
            axWindows: remainingAXWindows,
            validCGWindowIDs: validCGWindowIDs,
            assignedCGWindowIDs: Set(exactMatchesByAXWindowID.values)
        )
        let privateMatchResolution = Self.resolveFullscreenContentRebindings(
            matches: privateExactBridgeMatches,
            axWindows: remainingAXWindows,
            cgWindows: validCGWindows,
            assignedCGWindowIDs: Set(exactMatchesByAXWindowID.values),
            appName: appName
        )
        applyExactMatches(
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
        applyExactMatches(
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
        let desktopSiblingMatches = Self.resolveDesktopSiblingAXBindings(
            axWindows: remainingAXWindowsForDesktopSibling,
            cgWindows: validCGWindows,
            assignedCGWindowIDs: Set(exactMatchesByAXWindowID.values),
            appName: appName
        )
        applyExactMatches(
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
        applyExactMatches(
            Self.resolveFullscreenContentFallbackBindings(
                axWindows: remainingAXWindowsForContentFallback,
                cgWindows: validCGWindows,
                assignedCGWindowIDs: Set(exactMatchesByAXWindowID.values),
                appName: appName
            ),
            source: .fullscreenContentFallbackBinding,
            pid: pid,
            currentAXWindowsByID: currentAXWindowsByID,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName,
            observedAt: observedAt,
            windowRecordsByCGWindowID: &windowRecordsByCGWindowID,
            exactMatchesByAXWindowID: &exactMatchesByAXWindowID
        )

        for cgWindowID in windowRecordsByCGWindowID.keys.sorted() {
            guard var record = windowRecordsByCGWindowID[cgWindowID] else { continue }
            record.updateFallbackDisplayStateIfNeeded()
            windowRecordsByCGWindowID[cgWindowID] = record
        }

        let retainedCGWindowIDs = Set(windowRecordsByCGWindowID.keys.filter { cgWindowID in
            guard let record = windowRecordsByCGWindowID[cgWindowID] else { return false }
            return validCGWindowIDs.contains(cgWindowID)
                || record.hasStickyBinding
                || record.spaceRecovery != nil
        })
        windowRecordsByCGWindowID = windowRecordsByCGWindowID.filter {
            retainedCGWindowIDs.contains($0.key)
        }
        let currentAXToCG = exactMatchesByAXWindowID
        let currentCGToAX = Dictionary(uniqueKeysWithValues: currentAXToCG.map { ($1, $0) })
        let nextState = RuntimeWindowMappingState(
            windowRecordsByCGWindowID: windowRecordsByCGWindowID,
            currentAXToCG: currentAXToCG,
            currentCGToAX: currentCGToAX,
            validCGWindowIDs: validCGWindowIDs,
            lastAXWindowIDs: Set(axWindows.map(\.id)),
            hasObservedAXWindowHandle: hasObservedAXWindowHandle,
            consecutiveSnapshotsWithoutAXWindows: consecutiveSnapshotsWithoutAXWindows
        )
        if nextState.isEmpty {
            windowMappingStateByPID.removeValue(forKey: pid)
        } else {
            windowMappingStateByPID[pid] = nextState
        }

        let unmatchedAXCount = max(0, axWindows.count - exactMatchesByAXWindowID.count)
        let unmatchedCGCount = max(0, validCGWindows.count - Set(exactMatchesByAXWindowID.values).count)
        let stickyCount = windowRecordsByCGWindowID.values.filter(\.hasStickyBinding).count
        RuntimeLog.info(
            "AXMatch",
            "\(appName) records=\(windowRecordsByCGWindowID.count) sticky=\(stickyCount) exact=\(exactMatchesByAXWindowID.count) unmatchedAX=\(unmatchedAXCount) unmatchedCG=\(unmatchedCGCount)"
        )
        if allowSpaceOneWithoutCurrentAXHandle {
            RuntimeLog.info(
                "AXMatch",
                "\(appName) transient-ax-rebuild suspected; keeping space-1 windows missingAXSnapshots=\(consecutiveSnapshotsWithoutAXWindows)/\(runtimeAXRebuildGraceMissingSnapshotLimit)"
            )
        }
        return RuntimeWindowMappingResolution(
            exactMatchesByAXWindowID: exactMatchesByAXWindowID,
            windowRecordsByCGWindowID: windowRecordsByCGWindowID,
            validCGWindows: validCGWindows,
            allowSpaceOneWithoutCurrentAXHandle: allowSpaceOneWithoutCurrentAXHandle
        )
    }

    private func applyExactMatches(
        _ matches: [String: CGWindowID],
        source: WindowBindingConfirmationSource,
        pid: pid_t,
        currentAXWindowsByID: [String: AXWindowEntry],
        knownCGWindowsByID: [CGWindowID: CGWindowEntry],
        appName: String,
        observedAt: TimeInterval,
        windowRecordsByCGWindowID: inout [CGWindowID: RuntimeWindowRecord],
        exactMatchesByAXWindowID: inout [String: CGWindowID]
    ) {
        for (axWindowID, cgWindowID) in matches {
            guard let axWindow = currentAXWindowsByID[axWindowID] else { continue }
            var record = windowRecordsByCGWindowID[cgWindowID]
                ?? RuntimeWindowRecord(
                    cgWindowID: cgWindowID,
                    stableWindowID: Self.makeCGWindowID(pid: pid, cgWindowID: cgWindowID),
                    firstSeenAt: observedAt
                )
            let resolvedTitle = resolveStableWindowTitle(
                sourceTitle: axWindow.sourceTitle,
                matchedCGTitle: knownCGWindowsByID[cgWindowID]?.title,
                appName: appName,
                fallbackIndex: axWindow.index,
                refreshedAXTitle: nil
            )
            record.applyExactMatch(
                axWindow: axWindow,
                resolvedTitle: resolvedTitle,
                confirmationSource: source,
                observedAt: observedAt,
                matchedCGWindow: knownCGWindowsByID[cgWindowID]
            )
            windowRecordsByCGWindowID[cgWindowID] = record
            exactMatchesByAXWindowID[axWindowID] = cgWindowID
        }
    }

    private func deduplicateUnmatchedAXEntriesBySpace(
        _ entries: [WindowListEntry],
        knownCGWindowsByID: [CGWindowID: CGWindowEntry],
        appName: String
    ) -> [WindowListEntry] {
        var deduplicatedEntries: [WindowListEntry] = []
        deduplicatedEntries.reserveCapacity(entries.count)

        var seenSpaceKeys: Set<String> = []
        var droppedCount = 0

        for entry in entries {
            guard let cgWindowID = entry.cgWindowID else {
                deduplicatedEntries.append(entry)
                continue
            }
            let rawSpaceIDs = knownCGWindowsByID[cgWindowID]?.spaceIDs ?? []
            let normalizedSpaceIDs = RuntimeWindowTopologyClassifier.normalizedSpaceIDs(rawSpaceIDs)
            guard !normalizedSpaceIDs.isEmpty else {
                deduplicatedEntries.append(entry)
                continue
            }
            let spaceKey = normalizedSpaceIDs.map(String.init).joined(separator: ",")
            if seenSpaceKeys.insert(spaceKey).inserted {
                deduplicatedEntries.append(entry)
            } else {
                droppedCount += 1
            }
        }

        if droppedCount > 0 {
            RuntimeLog.info(
                "AXMatch",
                "\(appName) dedupe-unmatched-ax-by-space dropped=\(droppedCount)"
            )
        }

        return deduplicatedEntries
    }

    private func resolveStickyAXWindow(
        for record: RuntimeWindowRecord,
        axWindows: [AXWindowEntry],
        assignedAXWindowIDs: Set<String>
    ) -> AXWindowEntry? {
        if
            let lastKnownAXWindowID = record.lastExactAXWindowID,
            let exactIDMatch = axWindows.first(where: {
                $0.id == lastKnownAXWindowID && !assignedAXWindowIDs.contains($0.id)
            }),
            stickyBindingCanReuse(record, axWindow: exactIDMatch)
        {
            return exactIDMatch
        }

        guard let previousAXWindow = record.lastExactAXWindow else { return nil }
        return axWindows.first { axWindow in
            guard !assignedAXWindowIDs.contains(axWindow.id) else { return false }
            guard CFEqual(axWindow.window, previousAXWindow) else { return false }
            // Title changes are expected for a stable AX window handle. Once the
            // underlying AX element identity matches, prefer continuity and let
            // the current snapshot refresh title/frame in binding state.
            return true
        }
    }

    private static func resolvePrivateExactBridgeMatches(
        axWindows: [AXWindowEntry],
        validCGWindowIDs: Set<CGWindowID>,
        assignedCGWindowIDs: Set<CGWindowID>
    ) -> [String: CGWindowID] {
        guard !axWindows.isEmpty, !validCGWindowIDs.isEmpty else { return [:] }

        var candidateAXWindowIDsByCGWindowID: [CGWindowID: [String]] = [:]
        for axWindow in axWindows {
            guard let cgWindowID = AXWindowInspector.cgWindowID(for: axWindow.window) else { continue }
            guard validCGWindowIDs.contains(cgWindowID) else { continue }
            guard !assignedCGWindowIDs.contains(cgWindowID) else { continue }
            candidateAXWindowIDsByCGWindowID[cgWindowID, default: []].append(axWindow.id)
        }

        var matches: [String: CGWindowID] = [:]
        for (cgWindowID, axWindowIDs) in candidateAXWindowIDsByCGWindowID {
            guard axWindowIDs.count == 1, let axWindowID = axWindowIDs.first else { continue }
            matches[axWindowID] = cgWindowID
        }
        return matches
    }

    static func recoverAXWindowFromPublicSources(
        targetCGWindowID: CGWindowID?,
        expectedTitle: String,
        expectedFrame: CGRect?,
        windows: [AXWindowEntry],
        cgWindows: [CGWindowEntry],
        appName: String?
    ) -> AXWindowEntry? {
        recoverAXWindowFromPublicSourcesWithDiagnostics(
            targetCGWindowID: targetCGWindowID,
            expectedTitle: expectedTitle,
            expectedFrame: expectedFrame,
            windows: windows,
            cgWindows: cgWindows,
            appName: appName
        )?.window
    }

    struct AXWindowRecoveryDiagnosticResult {
        let window: AXWindowEntry
        let reason: String
    }

    static func recoverAXWindowFromPublicSourcesWithDiagnostics(
        targetCGWindowID: CGWindowID?,
        expectedTitle: String,
        expectedFrame: CGRect?,
        windows: [AXWindowEntry],
        cgWindows: [CGWindowEntry],
        appName: String?
    ) -> AXWindowRecoveryDiagnosticResult? {
        RuntimeLog.info(
            "Activation",
            "ax-recovery candidates app=\(runtimeAXRecoveryLogValue(appName)) targetCG=\(targetCGWindowID.map(String.init) ?? "nil") expectedTitle=\(runtimeAXRecoveryLogValue(expectedTitle)) expectedFrame=\(runtimeAXRecoveryFrameDescription(expectedFrame)) ax=\(runtimeAXRecoveryAXWindowSummary(windows)) cg=\(runtimeAXRecoveryCGWindowSummary(cgWindows, targetCGWindowID: targetCGWindowID))"
        )

        if let targetCGWindowID {
            let exactBridgeMatches = windows.filter {
                AXWindowInspector.cgWindowID(for: $0.window) == targetCGWindowID
            }
            RuntimeLog.info(
                "Activation",
                "ax-recovery exact-bridge targetCG=\(targetCGWindowID) matches=\(exactBridgeMatches.count) ids=\(runtimeAXRecoveryWindowIDs(exactBridgeMatches))"
            )
            if exactBridgeMatches.count == 1 {
                return AXWindowRecoveryDiagnosticResult(
                    window: exactBridgeMatches[0],
                    reason: "exact-bridge"
                )
            }
        }

        if let targetCGWindowID, cgWindows.contains(where: { $0.id == targetCGWindowID }) {
            let matchedWindowIDs = matchCGWindowAssignments(
                axWindows: windows,
                cgWindows: cgWindows,
                appName: appName
            )
            RuntimeLog.info(
                "Activation",
                "ax-recovery public-assignments targetCG=\(targetCGWindowID) matches=\(runtimeAXRecoveryAssignmentSummary(matchedWindowIDs))"
            )
            if
                let matchedWindowID = matchedWindowIDs.first(where: { $0.value == targetCGWindowID })?.key,
                let matchedWindow = windows.first(where: { $0.id == matchedWindowID })
            {
                return AXWindowRecoveryDiagnosticResult(
                    window: matchedWindow,
                    reason: "public-assignment"
                )
            }
        } else if let targetCGWindowID {
            RuntimeLog.info(
                "Activation",
                "ax-recovery target-cg-not-current targetCG=\(targetCGWindowID)"
            )
        }

        let publicFallback = publicUniqueAXWindowMatch(
            expectedTitle: expectedTitle,
            expectedFrame: expectedFrame,
            windows: windows
        )
        if publicFallback == nil {
            RuntimeLog.info(
                "Activation",
                "ax-recovery no-public-match targetCG=\(targetCGWindowID.map(String.init) ?? "nil")"
            )
        }
        return publicFallback
    }

    private static func publicUniqueAXWindowMatch(
        expectedTitle: String,
        expectedFrame: CGRect?,
        windows: [AXWindowEntry]
    ) -> AXWindowRecoveryDiagnosticResult? {
        let normalizedExpectedTitle = normalizedRuntimeWindowTitle(expectedTitle)
        if let normalizedExpectedTitle {
            let exactTitleAndFrameMatches = windows.filter { window in
                guard
                    let windowTitle = normalizedRuntimeWindowTitle(window.sourceTitle ?? window.title),
                    windowTitle.caseInsensitiveCompare(normalizedExpectedTitle) == .orderedSame
                else {
                    return false
                }
                guard let expectedFrame, let windowFrame = window.frame else { return true }
                return RuntimeWindowTopologyClassifier.framesApproximatelyMatch(windowFrame, expectedFrame)
            }
            RuntimeLog.info(
                "Activation",
                "ax-recovery public-fallback title-frame matches=\(exactTitleAndFrameMatches.count) ids=\(runtimeAXRecoveryWindowIDs(exactTitleAndFrameMatches))"
            )
            if exactTitleAndFrameMatches.count == 1 {
                return AXWindowRecoveryDiagnosticResult(
                    window: exactTitleAndFrameMatches[0],
                    reason: "title-frame"
                )
            }

            let exactTitleMatches = windows.filter { window in
                guard let windowTitle = normalizedRuntimeWindowTitle(window.sourceTitle ?? window.title) else {
                    return false
                }
                return windowTitle.caseInsensitiveCompare(normalizedExpectedTitle) == .orderedSame
            }
            RuntimeLog.info(
                "Activation",
                "ax-recovery public-fallback title matches=\(exactTitleMatches.count) ids=\(runtimeAXRecoveryWindowIDs(exactTitleMatches))"
            )
            if exactTitleMatches.count == 1 {
                return AXWindowRecoveryDiagnosticResult(
                    window: exactTitleMatches[0],
                    reason: "title"
                )
            }
        }

        if let expectedFrame {
            let exactFrameMatches = windows.filter { window in
                guard let windowFrame = window.frame else { return false }
                return RuntimeWindowTopologyClassifier.framesApproximatelyMatch(windowFrame, expectedFrame)
            }
            RuntimeLog.info(
                "Activation",
                "ax-recovery public-fallback frame matches=\(exactFrameMatches.count) ids=\(runtimeAXRecoveryWindowIDs(exactFrameMatches))"
            )
            if exactFrameMatches.count == 1 {
                return AXWindowRecoveryDiagnosticResult(
                    window: exactFrameMatches[0],
                    reason: "frame"
                )
            }
        }

        return nil
    }
}

private func runtimeKnownCGWindowsByID(
    windowRecordsByCGWindowID: [CGWindowID: RuntimeWindowRecord],
    validCGWindows: [RuntimeSnapshotProvider.CGWindowEntry]
) -> [CGWindowID: RuntimeSnapshotProvider.CGWindowEntry] {
    var knownCGWindowsByID = Dictionary(uniqueKeysWithValues: validCGWindows.map { ($0.id, $0) })
    for (cgWindowID, record) in windowRecordsByCGWindowID {
        guard knownCGWindowsByID[cgWindowID] == nil else { continue }
        guard let knownCGWindow = record.synthesizedKnownCGWindowEntry() else { continue }
        knownCGWindowsByID[cgWindowID] = knownCGWindow
    }
    return knownCGWindowsByID
}

private func stickyBindingCanReuse(
    _ record: RuntimeWindowRecord,
    axWindow: RuntimeSnapshotProvider.AXWindowEntry
) -> Bool {
    let normalizedBindingTitle = normalizedRuntimeWindowTitle(record.displayTitle)
    let normalizedAXTitle = normalizedRuntimeWindowTitle(axWindow.sourceTitle ?? axWindow.title)
    let titleMatches: Bool
    switch (normalizedBindingTitle, normalizedAXTitle) {
    case let (bindingTitle?, axTitle?):
        titleMatches = bindingTitle.caseInsensitiveCompare(axTitle) == .orderedSame
    case (nil, _):
        titleMatches = true
    default:
        titleMatches = false
    }

    let frameMatches: Bool
    switch (record.displayFrame, axWindow.frame) {
    case let (bindingFrame?, axFrame?):
        frameMatches = RuntimeWindowTopologyClassifier.framesApproximatelyMatch(axFrame, bindingFrame)
    case (nil, _):
        frameMatches = true
    default:
        frameMatches = false
    }

    return titleMatches && frameMatches
}

func normalizedRuntimeWindowTitle(_ title: String?) -> String? {
    guard let title else { return nil }
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func runtimeTitleLooksLikeAppNameFallback(_ title: String?, appName: String) -> Bool {
    guard let normalizedTitle = normalizedRuntimeWindowTitle(title) else { return false }
    guard let normalizedAppName = normalizedRuntimeWindowTitle(appName) else { return false }
    return normalizedTitle.caseInsensitiveCompare(normalizedAppName) == .orderedSame
}

private func runtimeSupplementalCGWindowTitle(
    appName: String,
    cgWindow: RuntimeSnapshotProvider.CGWindowEntry
) -> String {
    normalizedRuntimeWindowTitle(cgWindow.title)
        ?? normalizedRuntimeWindowTitle(appName)
        ?? appName
}

private func runtimeAXRecoveryAXWindowSummary(
    _ windows: [RuntimeSnapshotProvider.AXWindowEntry]
) -> String {
    let sample = windows.prefix(12).map { window in
        let bridgedCGWindowID = AXWindowInspector.cgWindowID(for: window.window).map(String.init) ?? "nil"
        let title = runtimeAXRecoveryLogValue(window.sourceTitle ?? window.title)
        let role = runtimeAXRecoveryLogValue(AXWindowInspector.role(for: window.window))
        let subrole = runtimeAXRecoveryLogValue(AXWindowInspector.subrole(for: window.window))
        return "\(window.id):idx=\(window.index):title=\(title):cg=\(bridgedCGWindowID):frame=\(runtimeAXRecoveryFrameDescription(window.frame)):min=\(window.isMinimized ? 1 : 0):role=\(role):subrole=\(subrole)"
    }.joined(separator: ",")
    return "count=\(windows.count) sample=[\(sample)]"
}

private func runtimeAXRecoveryCGWindowSummary(
    _ windows: [RuntimeSnapshotProvider.CGWindowEntry],
    targetCGWindowID: CGWindowID?
) -> String {
    let sample = windows.prefix(12).map { window in
        let marker = window.id == targetCGWindowID ? "*" : ""
        let title = runtimeAXRecoveryLogValue(window.title)
        let onscreen = window.isOnscreen ? "on" : "off"
        let alpha = String(format: "%.2f", window.alpha)
        return "\(marker)\(window.id):title=\(title):\(onscreen):alpha=\(alpha):store=\(window.storeType):spaces=\(window.spaceIDs):frame=\(runtimeAXRecoveryFrameDescription(window.bounds))"
    }.joined(separator: ",")
    return "count=\(windows.count) sample=[\(sample)]"
}

private func runtimeAXRecoveryWindowIDs(
    _ windows: [RuntimeSnapshotProvider.AXWindowEntry]
) -> String {
    windows
        .map { window in
            let bridgedCGWindowID = AXWindowInspector.cgWindowID(for: window.window).map(String.init) ?? "nil"
            return "\(window.id)(cg=\(bridgedCGWindowID),title=\(runtimeAXRecoveryLogValue(window.sourceTitle ?? window.title)),frame=\(runtimeAXRecoveryFrameDescription(window.frame)))"
        }
        .joined(separator: ",")
}

private func runtimeAXRecoveryAssignmentSummary(_ assignments: [String: CGWindowID]) -> String {
    assignments
        .sorted { lhs, rhs in
            if lhs.key == rhs.key {
                return lhs.value < rhs.value
            }
            return lhs.key < rhs.key
        }
        .map { "\($0.key)->\($0.value)" }
        .joined(separator: ",")
}

private func runtimeAXRecoveryFrameDescription(_ frame: CGRect?) -> String {
    guard let frame else { return "nil" }
    return "\(Int(frame.origin.x)),\(Int(frame.origin.y)),\(Int(frame.size.width))x\(Int(frame.size.height))"
}

private func runtimeAXRecoveryLogValue(_ value: String?) -> String {
    guard let value else { return "nil" }
    let trimmed = value
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "empty" : trimmed
}

private func resolveStableWindowTitle(
    sourceTitle: String?,
    matchedCGTitle: String?,
    appName: String,
    fallbackIndex: Int,
    refreshedAXTitle: String?
) -> String {
    let normalizedSourceTitle = normalizedRuntimeWindowTitle(sourceTitle)
    let normalizedMatchedCGTitle = normalizedRuntimeWindowTitle(matchedCGTitle)
    let normalizedRefreshedAXTitle = normalizedRuntimeWindowTitle(refreshedAXTitle)
    let sourceLooksLikeAppNameFallback = runtimeTitleLooksLikeAppNameFallback(
        normalizedSourceTitle,
        appName: appName
    )

    if !sourceLooksLikeAppNameFallback, let normalizedSourceTitle {
        return normalizedSourceTitle
    }

    if let normalizedMatchedCGTitle,
        !runtimeTitleLooksLikeAppNameFallback(normalizedMatchedCGTitle, appName: appName)
    {
        return normalizedMatchedCGTitle
    }

    if let normalizedRefreshedAXTitle,
        !runtimeTitleLooksLikeAppNameFallback(normalizedRefreshedAXTitle, appName: appName)
    {
        RuntimeLog.info("AX", "\(appName) untitled[\(fallbackIndex)] recovered-from-ax")
        return normalizedRefreshedAXTitle
    }

    if let normalizedMatchedCGTitle {
        return normalizedMatchedCGTitle
    }
    if let normalizedRefreshedAXTitle {
        return normalizedRefreshedAXTitle
    }
    if let normalizedSourceTitle {
        return normalizedSourceTitle
    }

    RuntimeLog.info("AX", "\(appName) untitled[\(fallbackIndex)] use app-name fallback")
    return appName
}
