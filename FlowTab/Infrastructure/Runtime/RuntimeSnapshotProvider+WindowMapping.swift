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

private let runtimeCGFrameOriginTolerance: CGFloat = 24
private let runtimeCGFrameSizeTolerance: CGFloat = 40
private let runtimeSpaceIDRequiringAXHandle = 1
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
            let normalizedSpaceIDs = Array(Set(rawSpaceIDs)).sorted()
            guard runtimeWindowCanBeExposedWithoutCurrentAXHandle(
                spaceIDs: normalizedSpaceIDs,
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
            let normalizedSpaceIDs = Array(Set(rawSpaceIDs)).sorted()
            guard !normalizedSpaceIDs.isEmpty else {
                hiddenProvisionalCGOnlyCount += 1
                return nil
            }
            guard runtimeWindowCanBeExposedWithoutCurrentAXHandle(
                spaceIDs: normalizedSpaceIDs,
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

        return exactEntries + deduplicatedUnmatchedAXEntries
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

        applyExactMatches(
            publicMatches,
            source: .publicExactMatch,
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
        applyExactMatches(
            privateExactBridgeMatches,
            source: .privateExactBridge,
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
            let normalizedSpaceIDs = Array(Set(rawSpaceIDs)).sorted()
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
        if let targetCGWindowID, cgWindows.contains(where: { $0.id == targetCGWindowID }) {
            let matchedWindowIDs = matchCGWindowAssignments(
                axWindows: windows,
                cgWindows: cgWindows,
                appName: appName
            )
            if
                let matchedWindowID = matchedWindowIDs.first(where: { $0.value == targetCGWindowID })?.key,
                let matchedWindow = windows.first(where: { $0.id == matchedWindowID })
            {
                return matchedWindow
            }
        }

        if let targetCGWindowID {
            let exactBridgeMatches = windows.filter {
                AXWindowInspector.cgWindowID(for: $0.window) == targetCGWindowID
            }
            if exactBridgeMatches.count == 1 {
                return exactBridgeMatches[0]
            }
        }

        return publicUniqueAXWindowMatch(
            expectedTitle: expectedTitle,
            expectedFrame: expectedFrame,
            windows: windows
        )
    }

    private static func publicUniqueAXWindowMatch(
        expectedTitle: String,
        expectedFrame: CGRect?,
        windows: [AXWindowEntry]
    ) -> AXWindowEntry? {
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
                return runtimeFramesApproximatelyMatch(axFrame: windowFrame, cgFrame: expectedFrame)
            }
            if exactTitleAndFrameMatches.count == 1 {
                return exactTitleAndFrameMatches[0]
            }

            let exactTitleMatches = windows.filter { window in
                guard let windowTitle = normalizedRuntimeWindowTitle(window.sourceTitle ?? window.title) else {
                    return false
                }
                return windowTitle.caseInsensitiveCompare(normalizedExpectedTitle) == .orderedSame
            }
            if exactTitleMatches.count == 1 {
                return exactTitleMatches[0]
            }
        }

        if let expectedFrame {
            let exactFrameMatches = windows.filter { window in
                guard let windowFrame = window.frame else { return false }
                return runtimeFramesApproximatelyMatch(axFrame: windowFrame, cgFrame: expectedFrame)
            }
            if exactFrameMatches.count == 1 {
                return exactFrameMatches[0]
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
        frameMatches = runtimeFramesApproximatelyMatch(axFrame: axFrame, cgFrame: bindingFrame)
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

private func runtimeWindowCanBeExposedWithoutCurrentAXHandle(
    spaceIDs: [Int],
    allowSpaceOneWithoutCurrentAXHandle: Bool
) -> Bool {
    let normalizedSpaceIDs = Array(Set(spaceIDs)).sorted()
    guard !normalizedSpaceIDs.isEmpty else { return true }
    if normalizedSpaceIDs == [runtimeSpaceIDRequiringAXHandle] {
        return allowSpaceOneWithoutCurrentAXHandle
    }
    return true
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

private func runtimeFramesApproximatelyMatch(axFrame: CGRect, cgFrame: CGRect) -> Bool {
    let normalizedAXFrame = axFrame.standardized
    let normalizedCGFrame = cgFrame.standardized
    guard
        normalizedAXFrame.width > 0,
        normalizedAXFrame.height > 0,
        normalizedCGFrame.width > 0,
        normalizedCGFrame.height > 0
    else {
        return false
    }
    return abs(normalizedAXFrame.minX - normalizedCGFrame.minX) <= runtimeCGFrameOriginTolerance
        && abs(normalizedAXFrame.minY - normalizedCGFrame.minY) <= runtimeCGFrameOriginTolerance
        && abs(normalizedAXFrame.width - normalizedCGFrame.width) <= runtimeCGFrameSizeTolerance
        && abs(normalizedAXFrame.height - normalizedCGFrame.height) <= runtimeCGFrameSizeTolerance
}
