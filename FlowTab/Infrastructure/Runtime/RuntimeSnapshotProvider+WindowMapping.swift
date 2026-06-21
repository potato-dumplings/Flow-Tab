import AppKit
import ApplicationServices
import Foundation

struct RuntimeWindowMappingResolution {
    let exactMatchesByAXWindowID: [String: CGWindowID]
    let windowRecordsByCGWindowID: [CGWindowID: RuntimeWindowRecord]
    let validCGWindows: [RuntimeCGWindowEntry]
    let allowSpaceOneWithoutCurrentAXHandle: Bool
    let bindingDiagnostics: [WindowBindingDiagnostic]

    var knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry] {
        runtimeKnownCGWindowsByID(
            windowRecordsByCGWindowID: windowRecordsByCGWindowID,
            validCGWindows: validCGWindows
        )
    }

    var windowLayerCGWindows: [RuntimeCGWindowEntry] {
        let knownCGWindowsByID = knownCGWindowsByID
        let validCGWindowIDs = Set(validCGWindows.map(\.id))
        let synthesizedWindows: [RuntimeCGWindowEntry] =
            windowRecordsByCGWindowID.keys.sorted().compactMap { cgWindowID in
                guard !validCGWindowIDs.contains(cgWindowID) else { return nil }
                return knownCGWindowsByID[cgWindowID]
            }
        return validCGWindows + synthesizedWindows
    }
}

private func runtimeWindowEntryUsesDesktopSpace(
    _ entry: RuntimeWindowListEntry
) -> Bool {
    RuntimeWindowTopologyClassifier.isDesktopOnlySpaceWindow(spaceIDs: entry.spaceIDs)
}

struct RuntimeWindowAssignmentMatchResult {
    let matches: [String: CGWindowID]
    let bindingDiagnostics: [WindowBindingDiagnostic]
}

extension RuntimeSnapshotProvider {
    func isLikelyTransientAXRebuild(for pid: pid_t) -> Bool {
        guard let state = windowMappingStateByPID[pid] else { return false }
        return RuntimeAXWindowAbsencePolicy.isLikelyTransientRebuild(
            hasObservedAXWindowHandle: state.hasObservedAXWindowHandle,
            consecutiveMissingSnapshotCount: state.consecutiveSnapshotsWithoutAXWindows
        )
    }

    func cleanupWindowMappingState(for runningApps: [NSRunningApplication]) {
        let runningPIDs = Set(runningApps.map(\.processIdentifier))
        windowMappingStateByPID = windowMappingStateByPID.filter { runningPIDs.contains($0.key) }
    }

    func clearWindowMappingState(for pid: pid_t) {
        windowMappingStateByPID.removeValue(forKey: pid)
    }

    func resolvedStableWindowEntries(
        axWindows: [RuntimeAXWindowEntry],
        cgWindows: [RuntimeCGWindowEntry],
        pid: pid_t,
        appName: String,
        remoteScanCompleteness: RuntimeAXRemoteWindowResolver.RemoteScanCompleteness? = nil
    ) -> [RuntimeWindowListEntry] {
        let mappingResolution = resolveStableWindowMapping(
            axWindows: axWindows,
            cgWindows: cgWindows,
            pid: pid,
            appName: appName,
            remoteScanCompleteness: remoteScanCompleteness
        )
        let windowLayerCGWindows = mappingResolution.windowLayerCGWindows
        let cgWindowOrderByID = Dictionary(
            uniqueKeysWithValues: windowLayerCGWindows.enumerated().map { offset, window in
                (window.id, offset)
            }
        )
        let knownCGWindowsByID = mappingResolution.knownCGWindowsByID
        let fullscreenContentBounds = windowLayerCGWindows.compactMap { cgWindow -> CGRect? in
            guard RuntimeWindowTopologyClassifier.isLikelyOffDesktopFullscreenContent(
                bounds: cgWindow.bounds,
                spaceIDs: cgWindow.spaceIDs
            ) else { return nil }
            return cgWindow.bounds
        }
        let exactEntries = axWindows.compactMap { axEntry -> RuntimeWindowListEntry? in
            guard
                let cgWindowID = mappingResolution.exactMatchesByAXWindowID[axEntry.id],
                let record = mappingResolution.windowRecordsByCGWindowID[cgWindowID]
            else {
                return nil
            }
            let matchedCGTitle = knownCGWindowsByID[cgWindowID]?.title ?? record.displayTitle
            let sourceLooksLikeAppNameFallback = RuntimeWindowTitleResolver.titleLooksLikeAppNameFallback(
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
            let title = RuntimeWindowTitleResolver.stableWindowTitle(
                sourceTitle: axEntry.sourceTitle,
                matchedCGTitle: matchedCGTitle,
                appName: appName,
                fallbackIndex: axEntry.index,
                refreshedAXTitle: refreshedAXTitle
            )
            let entryFrame = axEntry.frame ?? record.displayFrame
            let entrySpaceIDs = knownCGWindowsByID[cgWindowID]?.spaceIDs
                ?? record.spaceRecovery?.spaceIDs
                ?? []
            let spaceEvidence = RuntimeWindowTopologyClassifier.spaceEvidence(
                cgWindowID: cgWindowID,
                spaceIDs: entrySpaceIDs,
                bounds: entryFrame,
                source: "window-mapping-exact"
            )
            return RuntimeWindowListEntry(
                windowID: record.stableWindowID,
                title: title,
                isMinimized: axEntry.isMinimized,
                ownerPID: pid,
                cgWindowID: cgWindowID,
                activationHandleID: axEntry.id,
                axWindow: axEntry.window,
                frame: entryFrame,
                spaceIDs: entrySpaceIDs,
                isOnscreen: knownCGWindowsByID[cgWindowID]?.isOnscreen ?? false,
                allowsPublicAXRecovery: spaceEvidence.allowsPublicAXRecovery,
                hasStickyBinding: true,
                lastConfirmationSource: record.lastConfirmationSource,
                spaceEvidence: spaceEvidence
            )
        }

        let exactCGWindowIDs = Set(exactEntries.compactMap(\.cgWindowID))
        let stickyCGEntries = windowLayerCGWindows.compactMap { cgWindow -> RuntimeWindowListEntry? in
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
            let entryFrame = record.displayFrame ?? cgWindow.bounds
            let spaceEvidence = RuntimeWindowTopologyClassifier.spaceEvidence(
                cgWindowID: cgWindow.id,
                spaceIDs: normalizedSpaceIDs,
                bounds: entryFrame,
                source: "window-mapping-sticky-cg"
            )
            guard RuntimeWindowTopologyClassifier.canExposeWithoutCurrentAXHandle(
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
            return RuntimeWindowListEntry(
                windowID: record.stableWindowID,
                title: record.displayTitle
                    ?? RuntimeWindowTitleResolver.supplementalCGWindowTitle(appName: appName, cgWindow: cgWindow),
                isMinimized: record.isMinimized,
                ownerPID: pid,
                cgWindowID: cgWindow.id,
                activationHandleID: nil,
                axWindow: nil,
                frame: entryFrame,
                spaceIDs: normalizedSpaceIDs,
                isOnscreen: cgWindow.isOnscreen,
                allowsPublicAXRecovery: spaceEvidence.allowsPublicAXRecovery,
                hasStickyBinding: true,
                lastConfirmationSource: record.lastConfirmationSource,
                spaceEvidence: spaceEvidence
            )
        }

        let stickyCGWindowIDs = Set(stickyCGEntries.compactMap(\.cgWindowID))
        var hiddenProvisionalCGOnlyCount = 0
        let unmatchedCGEntries = windowLayerCGWindows.compactMap { cgWindow -> RuntimeWindowListEntry? in
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
            let entryFrame = record?.displayFrame ?? cgWindow.bounds
            let spaceEvidence = RuntimeWindowTopologyClassifier.spaceEvidence(
                cgWindowID: cgWindow.id,
                spaceIDs: normalizedSpaceIDs,
                bounds: entryFrame,
                source: "window-mapping-provisional-cg"
            )
            guard RuntimeWindowTopologyClassifier.canExposeWithoutCurrentAXHandle(
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
            return RuntimeWindowListEntry(
                windowID: record?.stableWindowID ?? RuntimeWindowListEntry.cgStableWindowID(
                    pid: pid,
                    cgWindowID: cgWindow.id
                ),
                title: record?.displayTitle
                    ?? RuntimeWindowTitleResolver.supplementalCGWindowTitle(appName: appName, cgWindow: cgWindow),
                isMinimized: false,
                ownerPID: pid,
                cgWindowID: cgWindow.id,
                activationHandleID: nil,
                axWindow: nil,
                frame: entryFrame,
                spaceIDs: normalizedSpaceIDs,
                isOnscreen: cgWindow.isOnscreen,
                allowsPublicAXRecovery: spaceEvidence.allowsPublicAXRecovery,
                hasStickyBinding: false,
                lastConfirmationSource: nil,
                bindingConfidenceOverride: .inferred,
                spaceEvidence: spaceEvidence
            )
        }
        if hiddenProvisionalCGOnlyCount > 0 {
            RuntimeLog.debug(
                .axMatch,
                "\(appName) hidden-provisional-cg windows=\(hiddenProvisionalCGOnlyCount)"
            )
        }

        let rawUnmatchedAXEntries = stickyCGEntries + unmatchedCGEntries
        let hostFilteredUnmatchedAXEntries = filterFullscreenHostArtifactEntries(
            rawUnmatchedAXEntries,
            allEntries: exactEntries + rawUnmatchedAXEntries,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName,
            hasFullscreenTopology: !fullscreenContentBounds.isEmpty,
            stage: "pre-dedupe"
        )
        let prefilteredUnmatchedAXEntries = filterFullscreenSiblingArtifactEntries(
            hostFilteredUnmatchedAXEntries,
            allEntries: exactEntries + hostFilteredUnmatchedAXEntries,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName,
            hasFullscreenTopology: !fullscreenContentBounds.isEmpty,
            stage: "pre-dedupe"
        )
        let deduplicatedUnmatchedAXEntries = suppressUnmatchedAXEntriesCoveredByStickySpace(
            prefilteredUnmatchedAXEntries,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName
        )

        let hostFilteredPresentationEntries = filterFullscreenHostArtifactEntries(
            exactEntries + deduplicatedUnmatchedAXEntries,
            allEntries: exactEntries + rawUnmatchedAXEntries,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName,
            hasFullscreenTopology: !fullscreenContentBounds.isEmpty,
            stage: "presentation"
        )
        let presentationEntries = filterFullscreenSiblingArtifactEntries(
            hostFilteredPresentationEntries,
            allEntries: hostFilteredPresentationEntries,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName,
            hasFullscreenTopology: !fullscreenContentBounds.isEmpty,
            stage: "presentation"
        )
        let overlayFilteredPresentationEntries = filterAuxiliaryOverlayEntries(
            presentationEntries,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName,
            stage: "presentation"
        )

        return orderWindowEntriesForPresentation(
            overlayFilteredPresentationEntries,
            prioritizesOnscreen: !fullscreenContentBounds.isEmpty,
            cgWindowOrderByID: cgWindowOrderByID,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName
        )
    }

    private func filterFullscreenHostArtifactEntries(
        _ entries: [RuntimeWindowListEntry],
        allEntries: [RuntimeWindowListEntry],
        knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
        appName: String,
        hasFullscreenTopology: Bool,
        stage: String
    ) -> [RuntimeWindowListEntry] {
        guard hasFullscreenTopology, !entries.isEmpty else { return entries }

        let activationSurfaces = allEntries.filter {
            runtimeWindowEntryLooksLikeAXBackedFullscreenContentSurface(
                $0,
                knownCGWindowsByID: knownCGWindowsByID,
                appName: appName
            )
        }
        guard !activationSurfaces.isEmpty else { return entries }

        var droppedCount = 0
        let filteredEntries = entries.filter { entry in
            let isArtifact = runtimeWindowEntryLooksLikeFullscreenHostArtifact(
                entry,
                activationSurfaces: activationSurfaces,
                knownCGWindowsByID: knownCGWindowsByID,
                appName: appName
            )
            if isArtifact {
                droppedCount += 1
            }
            return !isArtifact
        }

        if droppedCount > 0 {
            RuntimeLog.debug(
                .axMatch,
                "\(appName) filtered-fullscreen-host-artifacts stage=\(stage) dropped=\(droppedCount)"
            )
        }
        return filteredEntries
    }

    private func filterFullscreenSiblingArtifactEntries(
        _ entries: [RuntimeWindowListEntry],
        allEntries: [RuntimeWindowListEntry],
        knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
        appName: String,
        hasFullscreenTopology: Bool,
        stage: String
    ) -> [RuntimeWindowListEntry] {
        guard hasFullscreenTopology, !entries.isEmpty else { return entries }

        let strongTitles = Set(
            allEntries.compactMap { entry -> String? in
                guard runtimeWindowEntryLooksLikeStrongUserWindow(
                    entry,
                    knownCGWindowsByID: knownCGWindowsByID,
                    appName: appName
                ) else {
                    return nil
                }
                return runtimeNormalizedTitleKey(entry.title)
            }
        )
        guard !strongTitles.isEmpty else { return entries }

        var droppedCount = 0
        let filteredEntries = entries.filter { entry in
            let isArtifact = runtimeWindowEntryLooksLikeFullscreenSiblingArtifact(
                entry,
                knownCGWindowsByID: knownCGWindowsByID,
                appName: appName,
                strongTitles: strongTitles
            )
            if isArtifact {
                droppedCount += 1
            }
            return !isArtifact
        }

        if droppedCount > 0 {
            RuntimeLog.debug(
                .axMatch,
                "\(appName) filtered-fullscreen-sibling-artifacts stage=\(stage) dropped=\(droppedCount)"
            )
        }
        return filteredEntries
    }

    private func filterAuxiliaryOverlayEntries(
        _ entries: [RuntimeWindowListEntry],
        knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
        appName: String,
        stage: String
    ) -> [RuntimeWindowListEntry] {
        guard entries.count > 1 else { return entries }

        let primarySurfaces = entries.filter {
            runtimeWindowEntryLooksLikeStrongUserWindow(
                $0,
                knownCGWindowsByID: knownCGWindowsByID,
                appName: appName
            )
        }
        guard !primarySurfaces.isEmpty else { return entries }

        var droppedCount = 0
        let filteredEntries = entries.filter { entry in
            let isOverlay = runtimeWindowEntryLooksLikeContainedAuxiliaryOverlay(
                entry,
                primarySurfaces: primarySurfaces,
                knownCGWindowsByID: knownCGWindowsByID,
                appName: appName
            )
            if isOverlay {
                droppedCount += 1
            }
            return !isOverlay
        }

        if droppedCount > 0 {
            RuntimeLog.debug(
                .axMatch,
                "\(appName) filtered-auxiliary-overlays stage=\(stage) dropped=\(droppedCount)"
            )
        }
        return filteredEntries
    }

    private func orderWindowEntriesForPresentation(
        _ entries: [RuntimeWindowListEntry],
        prioritizesOnscreen: Bool = false,
        cgWindowOrderByID: [CGWindowID: Int] = [:],
        knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry] = [:],
        appName: String = ""
    ) -> [RuntimeWindowListEntry] {
        let hasRelatedFullscreenTopology = prioritizesOnscreen
            || knownCGWindowsByID.values.contains { cgWindow in
                RuntimeWindowTopologyClassifier.hasOffDesktopSpace(spaceIDs: cgWindow.spaceIDs)
                    && runtimeWindowBoundsLookLikeFullscreenContentSurface(cgWindow.bounds)
            }
        let hasOnscreenPrimarySurface = entries.contains { entry in
            entry.isOnscreen
                && !runtimeWindowEntryLooksLikeDesktopFullscreenSiblingSurface(
                    entry,
                    knownCGWindowsByID: knownCGWindowsByID,
                    appName: appName
                )
        }
        let orderedEntries = entries.enumerated().sorted { lhs, rhs in
            let lhsHasActivationHandle = lhs.element.activationHandleID != nil || lhs.element.axWindow != nil
            let rhsHasActivationHandle = rhs.element.activationHandleID != nil || rhs.element.axWindow != nil
            if prioritizesOnscreen, lhs.element.isOnscreen != rhs.element.isOnscreen {
                return lhs.element.isOnscreen
            }
            if hasRelatedFullscreenTopology, hasOnscreenPrimarySurface {
                if !lhs.element.isOnscreen, !rhs.element.isOnscreen {
                    let lhsIsDesktop = runtimeWindowEntryUsesDesktopSpace(lhs.element)
                    let rhsIsDesktop = runtimeWindowEntryUsesDesktopSpace(rhs.element)
                    if lhsIsDesktop != rhsIsDesktop {
                        return lhsIsDesktop
                    }
                }
                let lhsLooksLikeSibling = runtimeWindowEntryLooksLikeDesktopFullscreenSiblingSurface(
                    lhs.element,
                    knownCGWindowsByID: knownCGWindowsByID,
                    appName: appName
                )
                let rhsLooksLikeSibling = runtimeWindowEntryLooksLikeDesktopFullscreenSiblingSurface(
                    rhs.element,
                    knownCGWindowsByID: knownCGWindowsByID,
                    appName: appName
                )
                if lhsLooksLikeSibling != rhsLooksLikeSibling {
                    return !lhsLooksLikeSibling
                }
            }
            if lhsHasActivationHandle != rhsHasActivationHandle {
                return lhsHasActivationHandle
            }
            if !prioritizesOnscreen, lhs.element.isOnscreen != rhs.element.isOnscreen {
                return lhs.element.isOnscreen
            }
            if lhs.element.isOnscreen == rhs.element.isOnscreen {
                let lhsOrder = lhs.element.cgWindowID.flatMap { cgWindowOrderByID[$0] }
                let rhsOrder = rhs.element.cgWindowID.flatMap { cgWindowOrderByID[$0] }
                switch (lhsOrder, rhsOrder) {
                case let (lhsOrder?, rhsOrder?) where lhsOrder != rhsOrder:
                    return lhsOrder < rhsOrder
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    break
                }
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
        return orderedEntries
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
        let previousState = windowMappingStateByPID[pid] ?? RuntimeWindowMappingState()
        let observedAt = Date.timeIntervalSinceReferenceDate
        let hasAXWindowsInCurrentSnapshot = !axWindows.isEmpty
        let axWindowAbsenceIsAuthoritative = RuntimeAXWindowAbsencePolicy.isAbsenceAuthoritative(
            remoteScanCompleteness: remoteScanCompleteness
        )
        let hasObservedAXWindowHandle = previousState.hasObservedAXWindowHandle || hasAXWindowsInCurrentSnapshot
        let consecutiveSnapshotsWithoutAXWindows = RuntimeAXWindowAbsencePolicy.consecutiveMissingSnapshotCount(
            hasAXWindowsInCurrentSnapshot: hasAXWindowsInCurrentSnapshot,
            previousMissingSnapshotCount: previousState.consecutiveSnapshotsWithoutAXWindows,
            absenceIsAuthoritative: axWindowAbsenceIsAuthoritative
        )
        let allowSpaceOneWithoutCurrentAXHandle =
            RuntimeAXWindowAbsencePolicy.allowsSpaceOneWithoutCurrentAXHandle(
                hasObservedAXWindowHandle: hasObservedAXWindowHandle,
                hasAXWindowsInCurrentSnapshot: hasAXWindowsInCurrentSnapshot,
                absenceIsAuthoritative: axWindowAbsenceIsAuthoritative,
                consecutiveMissingSnapshotCount: consecutiveSnapshotsWithoutAXWindows
            )

        var windowRecordsByCGWindowID = previousState.windowRecordsByCGWindowID
        var bindingDiagnostics: [WindowBindingDiagnostic] = []
        for cgWindow in validCGWindows {
            var record = windowRecordsByCGWindowID[cgWindow.id]
                ?? RuntimeWindowRecord(
                    cgWindowID: cgWindow.id,
                    stableWindowID: RuntimeWindowListEntry.cgStableWindowID(pid: pid, cgWindowID: cgWindow.id),
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
                if let diagnostic = RuntimeAXWindowRecovery.stickyBindingConflictDiagnostic(
                    record: record,
                    reusedAXWindow: reusedAXWindow,
                    validCGWindowIDs: validCGWindowIDs
                ) {
                    bindingDiagnostics.append(diagnostic)
                    RuntimeLog.debug(
                        .axMatch,
                        "binding-assignment conflict reason=\(diagnostic.reason?.rawValue ?? "unknown") ax=\(reusedAXWindow.id) stickyCG=\(cgWindowID) exactCG=\(diagnostic.cgWindowID.map(String.init) ?? "nil") allowedActions=\(diagnostic.allowedActions.map(\.rawValue).sorted().joined(separator: ","))"
                    )
                    record.updateFallbackDisplayStateIfNeeded()
                    windowRecordsByCGWindowID[cgWindowID] = record
                    continue
                }
                let resolvedTitle = RuntimeWindowTitleResolver.stableWindowTitle(
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
        let desktopSiblingMatches = RuntimeWindowTopologyBindingResolver.resolveDesktopSiblingAXBindings(
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
        let fullscreenContentFallbackResult = RuntimeWindowTopologyBindingResolver.resolveFullscreenContentFallbackBindingsWithDiagnostics(
            axWindows: remainingAXWindowsForContentFallback,
            cgWindows: validCGWindows,
            assignedCGWindowIDs: Set(exactMatchesByAXWindowID.values),
            appName: appName
        )
        bindingDiagnostics.append(contentsOf: fullscreenContentFallbackResult.bindingDiagnostics)
        applyExactMatches(
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

        for cgWindowID in windowRecordsByCGWindowID.keys.sorted() {
            guard var record = windowRecordsByCGWindowID[cgWindowID] else { continue }
            record.updateFallbackDisplayStateIfNeeded()
            windowRecordsByCGWindowID[cgWindowID] = record
        }

        for cgWindowID in windowRecordsByCGWindowID.keys.sorted() {
            guard var record = windowRecordsByCGWindowID[cgWindowID] else { continue }
            let lifecycleDecision = record.reconcileLifecycle(
                validCGWindowIDs: validCGWindowIDs,
                observedAt: observedAt
            )
            switch lifecycleDecision {
            case .keep:
                windowRecordsByCGWindowID[cgWindowID] = record
            case .delete:
                windowRecordsByCGWindowID.removeValue(forKey: cgWindowID)
            }
        }
        let currentAXToCG = exactMatchesByAXWindowID
        let lastAXWindowIDs: Set<String>
        if hasAXWindowsInCurrentSnapshot {
            lastAXWindowIDs = Set(axWindows.map(\.id))
        } else if axWindowAbsenceIsAuthoritative {
            lastAXWindowIDs = []
        } else {
            lastAXWindowIDs = previousState.lastAXWindowIDs
        }
        let nextState = RuntimeWindowMappingState(
            windowRecordsByCGWindowID: windowRecordsByCGWindowID,
            currentAXToCG: currentAXToCG,
            validCGWindowIDs: validCGWindowIDs,
            lastAXWindowIDs: lastAXWindowIDs,
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
                    "\(appName) transient-ax-rebuild suspected; keeping space-1 windows missingAXSnapshots=\(consecutiveSnapshotsWithoutAXWindows)/\(RuntimeAXWindowAbsencePolicy.transientRebuildGraceMissingSnapshotLimit)"
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

    private func applyExactMatches(
        _ matches: [String: CGWindowID],
        source: WindowBindingConfirmationSource,
        pid: pid_t,
        currentAXWindowsByID: [String: RuntimeAXWindowEntry],
        knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
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
                    stableWindowID: RuntimeWindowListEntry.cgStableWindowID(pid: pid, cgWindowID: cgWindowID),
                    firstSeenAt: observedAt
                )
            let resolvedTitle = RuntimeWindowTitleResolver.stableWindowTitle(
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

    private func suppressUnmatchedAXEntriesCoveredByStickySpace(
        _ entries: [RuntimeWindowListEntry],
        knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
        appName: String
    ) -> [RuntimeWindowListEntry] {
        let stickySpaceKeys = Set(entries.compactMap { entry -> String? in
            guard
                entry.hasStickyBinding,
                let cgWindowID = entry.cgWindowID
            else {
                return nil
            }
            let rawSpaceIDs = knownCGWindowsByID[cgWindowID]?.spaceIDs ?? []
            let normalizedSpaceIDs = RuntimeWindowTopologyClassifier.normalizedSpaceIDs(rawSpaceIDs)
            guard !normalizedSpaceIDs.isEmpty else { return nil }
            return normalizedSpaceIDs.map(String.init).joined(separator: ",")
        })

        var deduplicatedEntries: [RuntimeWindowListEntry] = []
        deduplicatedEntries.reserveCapacity(entries.count)
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
            if entry.hasStickyBinding {
                deduplicatedEntries.append(entry)
                continue
            }
            if stickySpaceKeys.contains(spaceKey) {
                droppedCount += 1
                continue
            }
            deduplicatedEntries.append(entry)
        }

        if droppedCount > 0 {
            RuntimeLog.debug(
                .axMatch,
                "\(appName) suppress-unmatched-ax-covered-by-sticky-space dropped=\(droppedCount)"
            )
        }

        return deduplicatedEntries
    }

    private func resolveStickyAXWindow(
        for record: RuntimeWindowRecord,
        axWindows: [RuntimeAXWindowEntry],
        assignedAXWindowIDs: Set<String>
    ) -> RuntimeAXWindowEntry? {
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

}

private let runtimeFullscreenSiblingArtifactMinimumWidth: CGFloat = 500
private let runtimeFullscreenSiblingArtifactMaximumHeight: CGFloat = 560
private let runtimeFullscreenContentSiblingMinimumWidth: CGFloat = 900
private let runtimeFullscreenContentSiblingMinimumHeight: CGFloat = 600
private let runtimeFullscreenContentSiblingOriginTolerance: CGFloat = 90
private let runtimeFullscreenContentSiblingTopInsetLimit: CGFloat = 260
private let runtimeAuxiliaryOverlayMaximumWidth: CGFloat = 720
private let runtimeAuxiliaryOverlayMaximumHeight: CGFloat = 180
private let runtimeAuxiliaryOverlayContainmentTolerance: CGFloat = 8

private func runtimeWindowEntryLooksLikeFullscreenHostArtifact(
    _ entry: RuntimeWindowListEntry,
    activationSurfaces: [RuntimeWindowListEntry],
    knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
    appName: String
) -> Bool {
    guard RuntimeWindowTopologyClassifier.hasOffDesktopSpace(spaceIDs: entry.spaceIDs) else { return false }
    guard let hostBounds = runtimeWindowEntryBounds(entry, knownCGWindowsByID: knownCGWindowsByID)?.standardized else {
        return false
    }
    guard RuntimeWindowTopologyClassifier.isLikelyFullscreenContent(bounds: hostBounds) else {
        return false
    }

    return activationSurfaces.contains { activationSurface in
        guard activationSurface.cgWindowID != entry.cgWindowID else { return false }
        guard runtimeWindowTitlesCanRepresentSameFullscreenSurface(
            entry.title,
            activationSurface.title,
            appName: appName
        ) else {
            return false
        }
        guard let contentBounds = runtimeWindowEntryBounds(
            activationSurface,
            knownCGWindowsByID: knownCGWindowsByID
        )?.standardized else {
            return false
        }
        return runtimeFullscreenHostBounds(hostBounds, containContentSurfaceBounds: contentBounds)
    }
}

private func runtimeWindowEntryLooksLikeAXBackedFullscreenContentSurface(
    _ entry: RuntimeWindowListEntry,
    knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
    appName: String
) -> Bool {
    guard entry.activationHandleID != nil || entry.axWindow != nil else { return false }
    guard !RuntimeWindowTitleResolver.titleLooksLikeAppNameFallback(entry.title, appName: appName) else { return false }
    return runtimeWindowEntryLooksLikeStrongUserWindow(
        entry,
        knownCGWindowsByID: knownCGWindowsByID,
        appName: appName
    )
}

private func runtimeWindowEntryLooksLikeDesktopFullscreenSiblingSurface(
    _ entry: RuntimeWindowListEntry,
    knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
    appName: String
) -> Bool {
    guard entry.isOnscreen else { return false }
    let bounds = runtimeWindowEntryBounds(entry, knownCGWindowsByID: knownCGWindowsByID)
    guard runtimeWindowBoundsLookLikeFullscreenContentSurface(bounds) else {
        return false
    }
    let currentSpaceIDs = entry.cgWindowID.flatMap { knownCGWindowsByID[$0]?.spaceIDs } ?? entry.spaceIDs
    guard RuntimeWindowTopologyClassifier.isDesktopOnlySpaceWindow(spaceIDs: currentSpaceIDs) else {
        return false
    }

    return knownCGWindowsByID.values.contains { cgWindow in
        guard cgWindow.id != entry.cgWindowID else { return false }
        guard RuntimeWindowTopologyClassifier.hasOffDesktopSpace(spaceIDs: cgWindow.spaceIDs) else {
            return false
        }
        guard let relatedBounds = cgWindow.bounds else { return false }
        guard runtimeWindowBoundsLookLikeFullscreenContentSurface(relatedBounds) else {
            return false
        }
        if let bounds, RuntimeWindowTopologyClassifier.framesApproximatelyMatch(bounds, relatedBounds) {
            return true
        }
        return runtimeWindowTitlesCanRepresentSameFullscreenSurface(
            entry.title,
            cgWindow.title,
            appName: appName
        )
    }
}

private func runtimeWindowBoundsLookLikeFullscreenContentSurface(_ bounds: CGRect?) -> Bool {
    if RuntimeWindowTopologyClassifier.isLikelyFullscreenContent(bounds: bounds) {
        return true
    }
    guard let bounds = bounds?.standardized else { return false }
    guard bounds.width >= runtimeFullscreenContentSiblingMinimumWidth else { return false }
    guard bounds.height >= runtimeFullscreenContentSiblingMinimumHeight else { return false }
    guard abs(bounds.minX) <= runtimeFullscreenContentSiblingOriginTolerance else { return false }
    return bounds.minY >= 0 && bounds.minY <= runtimeFullscreenContentSiblingTopInsetLimit
}

private func runtimeWindowEntryLooksLikeFullscreenSiblingArtifact(
    _ entry: RuntimeWindowListEntry,
    knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
    appName: String,
    strongTitles: Set<String>
) -> Bool {
    guard runtimeWindowEntryLooksLikeShallowFullscreenSibling(entry, knownCGWindowsByID: knownCGWindowsByID) else {
        return false
    }

    if RuntimeWindowTitleResolver.titleLooksLikeAppNameFallback(entry.title, appName: appName) {
        return true
    }

    guard let titleKey = runtimeNormalizedTitleKey(entry.title) else { return false }
    return strongTitles.contains(titleKey)
        && !runtimeWindowEntryLooksLikeStrongUserWindow(
            entry,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName
        )
}

private func runtimeWindowEntryLooksLikeStrongUserWindow(
    _ entry: RuntimeWindowListEntry,
    knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
    appName: String
) -> Bool {
    let bounds = runtimeWindowEntryBounds(entry, knownCGWindowsByID: knownCGWindowsByID)
    if RuntimeWindowTopologyClassifier.isLikelyFullscreenContent(bounds: bounds) {
        return true
    }

    guard !RuntimeWindowTitleResolver.titleLooksLikeAppNameFallback(entry.title, appName: appName) else {
        return false
    }
    guard let bounds = bounds?.standardized else { return false }
    return bounds.width >= runtimeFullscreenSiblingArtifactMinimumWidth
        && bounds.height > runtimeFullscreenSiblingArtifactMaximumHeight
}

private func runtimeWindowEntryLooksLikeShallowFullscreenSibling(
    _ entry: RuntimeWindowListEntry,
    knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry]
) -> Bool {
    guard let bounds = runtimeWindowEntryBounds(entry, knownCGWindowsByID: knownCGWindowsByID)?.standardized else {
        return false
    }
    guard !RuntimeWindowTopologyClassifier.isLikelyFullscreenContent(bounds: bounds) else {
        return false
    }
    return bounds.width >= runtimeFullscreenSiblingArtifactMinimumWidth
        && bounds.height <= runtimeFullscreenSiblingArtifactMaximumHeight
}

private func runtimeWindowEntryLooksLikeContainedAuxiliaryOverlay(
    _ entry: RuntimeWindowListEntry,
    primarySurfaces: [RuntimeWindowListEntry],
    knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
    appName: String
) -> Bool {
    guard !runtimeWindowEntryLooksLikeStrongUserWindow(
        entry,
        knownCGWindowsByID: knownCGWindowsByID,
        appName: appName
    ) else {
        return false
    }
    guard let bounds = runtimeWindowEntryBounds(entry, knownCGWindowsByID: knownCGWindowsByID)?.standardized else {
        return false
    }
    guard bounds.width > 0, bounds.height > 0 else { return false }
    guard bounds.width <= runtimeAuxiliaryOverlayMaximumWidth else { return false }
    guard bounds.height <= runtimeAuxiliaryOverlayMaximumHeight else { return false }

    return primarySurfaces.contains { primarySurface in
        guard primarySurface.cgWindowID != entry.cgWindowID else { return false }
        guard runtimeWindowEntriesShareAnySpace(entry, primarySurface) else { return false }
        guard let primaryBounds = runtimeWindowEntryBounds(
            primarySurface,
            knownCGWindowsByID: knownCGWindowsByID
        )?.standardized else {
            return false
        }
        let containmentBounds = primaryBounds.insetBy(
            dx: -runtimeAuxiliaryOverlayContainmentTolerance,
            dy: -runtimeAuxiliaryOverlayContainmentTolerance
        )
        return containmentBounds.contains(bounds)
    }
}

private func runtimeWindowEntriesShareAnySpace(
    _ lhs: RuntimeWindowListEntry,
    _ rhs: RuntimeWindowListEntry
) -> Bool {
    let lhsSpaces = Set(RuntimeWindowTopologyClassifier.normalizedSpaceIDs(lhs.spaceIDs))
    let rhsSpaces = Set(RuntimeWindowTopologyClassifier.normalizedSpaceIDs(rhs.spaceIDs))
    guard !lhsSpaces.isEmpty, !rhsSpaces.isEmpty else { return false }
    return !lhsSpaces.isDisjoint(with: rhsSpaces)
}

private func runtimeWindowEntryBounds(
    _ entry: RuntimeWindowListEntry,
    knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry]
) -> CGRect? {
    if let cgWindowID = entry.cgWindowID,
        let cgBounds = knownCGWindowsByID[cgWindowID]?.bounds
    {
        return cgBounds
    }
    return entry.frame
}

private func runtimeWindowTitlesCanRepresentSameFullscreenSurface(
    _ lhs: String?,
    _ rhs: String?,
    appName: String
) -> Bool {
    let leftLooksLikeAppFallback = RuntimeWindowTitleResolver.titleLooksLikeAppNameFallback(lhs, appName: appName)
    let rightLooksLikeAppFallback = RuntimeWindowTitleResolver.titleLooksLikeAppNameFallback(rhs, appName: appName)
    let left = leftLooksLikeAppFallback ? nil : runtimeNormalizedTitleKey(lhs)
    let right = rightLooksLikeAppFallback ? nil : runtimeNormalizedTitleKey(rhs)
    switch (left, right) {
    case let (left?, right?):
        return left == right
    case (nil, _?):
        return true
    default:
        return false
    }
}

private func runtimeFullscreenHostBounds(
    _ hostBounds: CGRect,
    containContentSurfaceBounds contentBounds: CGRect
) -> Bool {
    guard contentBounds.width >= hostBounds.width * 0.7 else { return false }
    guard contentBounds.height >= hostBounds.height * 0.45 else { return false }
    guard contentBounds.height <= hostBounds.height else { return false }
    guard abs(contentBounds.minX - hostBounds.minX) <= 120 else { return false }
    guard contentBounds.minY >= hostBounds.minY else { return false }
    guard contentBounds.maxY <= hostBounds.maxY + 80 else { return false }
    return contentBounds.minY > hostBounds.minY + 20
        || contentBounds.height < hostBounds.height - 40
}

private func runtimeNormalizedTitleKey(_ title: String?) -> String? {
    normalizedRuntimeWindowTitle(title)?.lowercased()
}

private func runtimeKnownCGWindowsByID(
    windowRecordsByCGWindowID: [CGWindowID: RuntimeWindowRecord],
    validCGWindows: [RuntimeCGWindowEntry]
) -> [CGWindowID: RuntimeCGWindowEntry] {
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
    axWindow: RuntimeAXWindowEntry
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
