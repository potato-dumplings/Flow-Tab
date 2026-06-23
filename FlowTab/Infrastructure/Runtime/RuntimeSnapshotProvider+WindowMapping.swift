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
