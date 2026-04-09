import AppKit
import ApplicationServices
import Foundation

struct RuntimeStickyWindowBinding {
    let stableWindowID: String
    let cgWindowID: CGWindowID
    var lastKnownAXWindowID: String?
    var axWindow: AXUIElement?
    var title: String?
    var frame: CGRect?
    var isMinimized: Bool
    var lastConfirmationSource: WindowBindingConfirmationSource
    var hasCurrentActivationHandle: Bool
}

struct RuntimeWindowMappingState {
    var bindingsByCGWindowID: [CGWindowID: RuntimeStickyWindowBinding] = [:]
    var lastKnownCGWindowsByID: [CGWindowID: RuntimeSnapshotProvider.CGWindowEntry] = [:]

    var isEmpty: Bool {
        bindingsByCGWindowID.isEmpty && lastKnownCGWindowsByID.isEmpty
    }
}

struct RuntimeWindowMappingResolution {
    let exactMatchesByAXWindowID: [String: CGWindowID]
    let bindingsByCGWindowID: [CGWindowID: RuntimeStickyWindowBinding]
    let validCGWindows: [RuntimeSnapshotProvider.CGWindowEntry]
    let knownCGWindowsByID: [CGWindowID: RuntimeSnapshotProvider.CGWindowEntry]
}

private let runtimeCGFrameOriginTolerance: CGFloat = 24
private let runtimeCGFrameSizeTolerance: CGFloat = 40
private let runtimeSpaceIDRequiringAXHandle = 1

extension RuntimeSnapshotProvider {
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
        let exactEntries = axWindows.compactMap { axEntry -> WindowListEntry? in
            guard
                let cgWindowID = mappingResolution.exactMatchesByAXWindowID[axEntry.id],
                let binding = mappingResolution.bindingsByCGWindowID[cgWindowID]
            else {
                return nil
            }
            let matchedCGTitle = mappingResolution.knownCGWindowsByID[cgWindowID]?.title ?? binding.title
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
                windowID: binding.stableWindowID,
                title: title,
                isMinimized: axEntry.isMinimized,
                ownerPID: pid,
                cgWindowID: cgWindowID,
                activationHandleID: axEntry.id,
                axWindow: axEntry.window,
                frame: axEntry.frame ?? binding.frame,
                allowsPublicAXRecovery: true,
                hasStickyBinding: true,
                lastConfirmationSource: binding.lastConfirmationSource
            )
        }

        let exactCGWindowIDs = Set(exactEntries.compactMap(\.cgWindowID))
        let stickyCGEntries = mappingResolution.validCGWindows.compactMap { cgWindow -> WindowListEntry? in
            guard !exactCGWindowIDs.contains(cgWindow.id) else { return nil }
            guard let binding = mappingResolution.bindingsByCGWindowID[cgWindow.id] else {
                return nil
            }
            let rawSpaceIDs = mappingResolution.knownCGWindowsByID[cgWindow.id]?.spaceIDs ?? cgWindow.spaceIDs
            let normalizedSpaceIDs = Array(Set(rawSpaceIDs)).sorted()
            guard runtimeWindowCanBeExposedWithoutCurrentAXHandle(spaceIDs: normalizedSpaceIDs) else {
                return nil
            }
            return WindowListEntry(
                windowID: binding.stableWindowID,
                title: binding.title
                    ?? runtimeSupplementalCGWindowTitle(appName: appName, cgWindow: cgWindow),
                isMinimized: false,
                ownerPID: pid,
                cgWindowID: cgWindow.id,
                activationHandleID: nil,
                axWindow: nil,
                frame: binding.frame ?? cgWindow.bounds,
                allowsPublicAXRecovery: true,
                hasStickyBinding: true,
                lastConfirmationSource: binding.lastConfirmationSource
            )
        }

        let stickyCGWindowIDs = Set(stickyCGEntries.compactMap(\.cgWindowID))
        var hiddenProvisionalCGOnlyCount = 0
        let unmatchedCGEntries = mappingResolution.validCGWindows.compactMap { cgWindow -> WindowListEntry? in
            guard !exactCGWindowIDs.contains(cgWindow.id) else { return nil }
            guard !stickyCGWindowIDs.contains(cgWindow.id) else { return nil }
            let rawSpaceIDs = mappingResolution.knownCGWindowsByID[cgWindow.id]?.spaceIDs ?? cgWindow.spaceIDs
            let normalizedSpaceIDs = Array(Set(rawSpaceIDs)).sorted()
            guard !normalizedSpaceIDs.isEmpty else {
                hiddenProvisionalCGOnlyCount += 1
                return nil
            }
            guard runtimeWindowCanBeExposedWithoutCurrentAXHandle(spaceIDs: normalizedSpaceIDs) else {
                hiddenProvisionalCGOnlyCount += 1
                return nil
            }
            return WindowListEntry(
                windowID: Self.makeCGWindowID(pid: pid, cgWindowID: cgWindow.id),
                title: runtimeSupplementalCGWindowTitle(appName: appName, cgWindow: cgWindow),
                isMinimized: false,
                ownerPID: pid,
                cgWindowID: cgWindow.id,
                activationHandleID: nil,
                axWindow: nil,
                frame: cgWindow.bounds,
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
            knownCGWindowsByID: mappingResolution.knownCGWindowsByID,
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

        var knownCGWindowsByID = previousState.lastKnownCGWindowsByID
        for cgWindow in validCGWindows {
            knownCGWindowsByID[cgWindow.id] = cgWindow
        }

        var bindingsByCGWindowID = previousState.bindingsByCGWindowID
        var exactMatchesByAXWindowID: [String: CGWindowID] = [:]
        var assignedAXWindowIDs: Set<String> = []

        for cgWindowID in bindingsByCGWindowID.keys.sorted() {
            guard var binding = bindingsByCGWindowID[cgWindowID] else { continue }
            let reusedAXWindow = resolveStickyAXWindow(
                for: binding,
                axWindows: axWindows,
                assignedAXWindowIDs: assignedAXWindowIDs
            )

            if let reusedAXWindow {
                binding.lastKnownAXWindowID = reusedAXWindow.id
                binding.axWindow = reusedAXWindow.window
                binding.title = resolveStableWindowTitle(
                    sourceTitle: reusedAXWindow.sourceTitle,
                    matchedCGTitle: knownCGWindowsByID[cgWindowID]?.title ?? binding.title,
                    appName: appName,
                    fallbackIndex: reusedAXWindow.index,
                    refreshedAXTitle: nil
                )
                binding.frame = reusedAXWindow.frame ?? binding.frame ?? knownCGWindowsByID[cgWindowID]?.bounds
                binding.isMinimized = reusedAXWindow.isMinimized
                binding.lastConfirmationSource = .stickyBinding
                binding.hasCurrentActivationHandle = true
                exactMatchesByAXWindowID[reusedAXWindow.id] = cgWindowID
                assignedAXWindowIDs.insert(reusedAXWindow.id)
            } else {
                binding.hasCurrentActivationHandle = false
                if binding.title == nil, let cgTitle = normalizedRuntimeWindowTitle(knownCGWindowsByID[cgWindowID]?.title) {
                    binding.title = cgTitle
                }
                if binding.frame == nil {
                    binding.frame = knownCGWindowsByID[cgWindowID]?.bounds
                }
            }

            bindingsByCGWindowID[cgWindowID] = binding
        }

        let unresolvedAXWindows = axWindows.filter { !assignedAXWindowIDs.contains($0.id) }
        let unresolvedCGWindows = validCGWindows.filter { cgWindow in
            bindingsByCGWindowID[cgWindow.id]?.hasCurrentActivationHandle != true
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
            bindingsByCGWindowID: &bindingsByCGWindowID,
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
            bindingsByCGWindowID: &bindingsByCGWindowID,
            exactMatchesByAXWindowID: &exactMatchesByAXWindowID
        )

        for cgWindow in validCGWindows {
            guard var binding = bindingsByCGWindowID[cgWindow.id] else { continue }
            if binding.title == nil, let cgTitle = normalizedRuntimeWindowTitle(cgWindow.title) {
                binding.title = cgTitle
            }
            if binding.frame == nil {
                binding.frame = cgWindow.bounds
            }
            bindingsByCGWindowID[cgWindow.id] = binding
        }

        let retainedCGWindowIDs = Set(bindingsByCGWindowID.keys).union(validCGWindowIDs)
        knownCGWindowsByID = knownCGWindowsByID.filter { retainedCGWindowIDs.contains($0.key) }
        let nextState = RuntimeWindowMappingState(
            bindingsByCGWindowID: bindingsByCGWindowID,
            lastKnownCGWindowsByID: knownCGWindowsByID
        )
        if nextState.isEmpty {
            windowMappingStateByPID.removeValue(forKey: pid)
        } else {
            windowMappingStateByPID[pid] = nextState
        }

        let unmatchedAXCount = max(0, axWindows.count - exactMatchesByAXWindowID.count)
        let unmatchedCGCount = max(0, validCGWindows.count - Set(exactMatchesByAXWindowID.values).count)
        RuntimeLog.info(
            "AXMatch",
            "\(appName) sticky=\(bindingsByCGWindowID.count) exact=\(exactMatchesByAXWindowID.count) unmatchedAX=\(unmatchedAXCount) unmatchedCG=\(unmatchedCGCount)"
        )
        return RuntimeWindowMappingResolution(
            exactMatchesByAXWindowID: exactMatchesByAXWindowID,
            bindingsByCGWindowID: bindingsByCGWindowID,
            validCGWindows: validCGWindows,
            knownCGWindowsByID: knownCGWindowsByID
        )
    }

    private func applyExactMatches(
        _ matches: [String: CGWindowID],
        source: WindowBindingConfirmationSource,
        pid: pid_t,
        currentAXWindowsByID: [String: AXWindowEntry],
        knownCGWindowsByID: [CGWindowID: CGWindowEntry],
        appName: String,
        bindingsByCGWindowID: inout [CGWindowID: RuntimeStickyWindowBinding],
        exactMatchesByAXWindowID: inout [String: CGWindowID]
    ) {
        for (axWindowID, cgWindowID) in matches {
            guard let axWindow = currentAXWindowsByID[axWindowID] else { continue }
            var binding = bindingsByCGWindowID[cgWindowID]
                ?? RuntimeStickyWindowBinding(
                    stableWindowID: Self.makeCGWindowID(pid: pid, cgWindowID: cgWindowID),
                    cgWindowID: cgWindowID,
                    lastKnownAXWindowID: nil,
                    axWindow: nil,
                    title: nil,
                    frame: nil,
                    isMinimized: false,
                    lastConfirmationSource: source,
                    hasCurrentActivationHandle: false
                )
            binding.lastKnownAXWindowID = axWindowID
            binding.axWindow = axWindow.window
            binding.title = resolveStableWindowTitle(
                sourceTitle: axWindow.sourceTitle,
                matchedCGTitle: knownCGWindowsByID[cgWindowID]?.title,
                appName: appName,
                fallbackIndex: axWindow.index,
                refreshedAXTitle: nil
            )
            binding.frame = axWindow.frame ?? binding.frame ?? knownCGWindowsByID[cgWindowID]?.bounds
            binding.isMinimized = axWindow.isMinimized
            binding.lastConfirmationSource = source
            binding.hasCurrentActivationHandle = true
            bindingsByCGWindowID[cgWindowID] = binding
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
        for binding: RuntimeStickyWindowBinding,
        axWindows: [AXWindowEntry],
        assignedAXWindowIDs: Set<String>
    ) -> AXWindowEntry? {
        if
            let lastKnownAXWindowID = binding.lastKnownAXWindowID,
            let exactIDMatch = axWindows.first(where: {
                $0.id == lastKnownAXWindowID && !assignedAXWindowIDs.contains($0.id)
            }),
            stickyBindingCanReuse(binding, axWindow: exactIDMatch)
        {
            return exactIDMatch
        }

        guard let previousAXWindow = binding.axWindow else { return nil }
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

private func stickyBindingCanReuse(
    _ binding: RuntimeStickyWindowBinding,
    axWindow: RuntimeSnapshotProvider.AXWindowEntry
) -> Bool {
    let normalizedBindingTitle = normalizedRuntimeWindowTitle(binding.title)
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
    switch (binding.frame, axWindow.frame) {
    case let (bindingFrame?, axFrame?):
        frameMatches = runtimeFramesApproximatelyMatch(axFrame: axFrame, cgFrame: bindingFrame)
    case (nil, _):
        frameMatches = true
    default:
        frameMatches = false
    }

    return titleMatches && frameMatches
}

private func normalizedRuntimeWindowTitle(_ title: String?) -> String? {
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

private func runtimeWindowCanBeExposedWithoutCurrentAXHandle(spaceIDs: [Int]) -> Bool {
    let normalizedSpaceIDs = Array(Set(spaceIDs)).sorted()
    guard !normalizedSpaceIDs.isEmpty else { return true }
    return normalizedSpaceIDs != [runtimeSpaceIDRequiringAXHandle]
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
