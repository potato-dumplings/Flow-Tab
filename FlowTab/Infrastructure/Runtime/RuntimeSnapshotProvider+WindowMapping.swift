import AppKit
import ApplicationServices
import Foundation

extension RuntimeSnapshotProvider {
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
        let hostFilteredUnmatchedAXEntries = RuntimeWindowPresentationFilter.filterFullscreenHostArtifactEntries(
            rawUnmatchedAXEntries,
            allEntries: exactEntries + rawUnmatchedAXEntries,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName,
            hasFullscreenTopology: !fullscreenContentBounds.isEmpty,
            stage: "pre-dedupe"
        )
        let prefilteredUnmatchedAXEntries = RuntimeWindowPresentationFilter.filterFullscreenSiblingArtifactEntries(
            hostFilteredUnmatchedAXEntries,
            allEntries: exactEntries + hostFilteredUnmatchedAXEntries,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName,
            hasFullscreenTopology: !fullscreenContentBounds.isEmpty,
            stage: "pre-dedupe"
        )
        let deduplicatedUnmatchedAXEntries = RuntimeWindowListDeduplicator.suppressUnmatchedEntriesCoveredByStickySpace(
            prefilteredUnmatchedAXEntries,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName
        )

        let hostFilteredPresentationEntries = RuntimeWindowPresentationFilter.filterFullscreenHostArtifactEntries(
            exactEntries + deduplicatedUnmatchedAXEntries,
            allEntries: exactEntries + rawUnmatchedAXEntries,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName,
            hasFullscreenTopology: !fullscreenContentBounds.isEmpty,
            stage: "presentation"
        )
        let presentationEntries = RuntimeWindowPresentationFilter.filterFullscreenSiblingArtifactEntries(
            hostFilteredPresentationEntries,
            allEntries: hostFilteredPresentationEntries,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName,
            hasFullscreenTopology: !fullscreenContentBounds.isEmpty,
            stage: "presentation"
        )
        let overlayFilteredPresentationEntries = RuntimeWindowPresentationFilter.filterAuxiliaryOverlayEntries(
            presentationEntries,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName,
            stage: "presentation"
        )
        let duplicateFilteredPresentationEntries = RuntimeWindowPresentationFilter.filterDuplicateFullscreenContentEntries(
            overlayFilteredPresentationEntries,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName,
            stage: "presentation-final"
        )

        return RuntimeWindowPresentationFilter.orderWindowEntriesForPresentation(
            duplicateFilteredPresentationEntries,
            prioritizesOnscreen: !fullscreenContentBounds.isEmpty,
            cgWindowOrderByID: cgWindowOrderByID,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName
        )
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
        let previousState = windowRecordStore.state(for: pid) ?? RuntimeWindowMappingState()
        let observedAt = Date.timeIntervalSinceReferenceDate
        let hasAXWindowsInCurrentCollection = !axWindows.isEmpty
        let axWindowAbsenceIsAuthoritative = RuntimeAXWindowAbsencePolicy.isAbsenceAuthoritative(
            remoteScanCompleteness: remoteScanCompleteness
        )
        let hasObservedAXWindowHandle = previousState.hasObservedAXWindowHandle || hasAXWindowsInCurrentCollection
        let consecutiveAXCollectionMisses = RuntimeAXWindowAbsencePolicy.consecutiveAXCollectionMissCount(
            hasAXWindowsInCurrentCollection: hasAXWindowsInCurrentCollection,
            previousAXCollectionMissCount: previousState.consecutiveAXCollectionMisses,
            absenceIsAuthoritative: axWindowAbsenceIsAuthoritative
        )
        let allowSpaceOneWithoutCurrentAXHandle =
            RuntimeAXWindowAbsencePolicy.allowsSpaceOneWithoutCurrentAXHandle(
                hasObservedAXWindowHandle: hasObservedAXWindowHandle,
                hasAXWindowsInCurrentCollection: hasAXWindowsInCurrentCollection,
                absenceIsAuthoritative: axWindowAbsenceIsAuthoritative,
                consecutiveAXCollectionMissCount: consecutiveAXCollectionMisses
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

        let knownCGWindowsByID = RuntimeWindowRecord.knownCGWindowsByID(
            windowRecordsByCGWindowID: windowRecordsByCGWindowID,
            validCGWindows: validCGWindows
        )
        var exactMatchesByAXWindowID: [String: CGWindowID] = [:]
        var assignedAXWindowIDs: Set<String> = []

        for cgWindowID in windowRecordsByCGWindowID.keys.sorted() {
            guard var record = windowRecordsByCGWindowID[cgWindowID] else { continue }
            let reusedAXWindow = record.reusableStickyAXWindow(
                from: axWindows,
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
        if hasAXWindowsInCurrentCollection {
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
            consecutiveAXCollectionMisses: consecutiveAXCollectionMisses
        )
        if nextState.isEmpty {
            windowRecordStore.removeState(for: pid)
        } else {
            windowRecordStore.setState(nextState, for: pid)
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
                    "\(appName) transient-ax-rebuild suspected; keeping space-1 windows axCollectionMisses=\(consecutiveAXCollectionMisses)/\(RuntimeAXWindowAbsencePolicy.transientRebuildGraceAXCollectionMissLimit)"
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
