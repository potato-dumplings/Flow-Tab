import AppKit
import ApplicationServices
import Foundation

enum RuntimeWindowMappingPresentationAssembler {
    static func resolvedStableWindowEntries(
        windowRecordStore: RuntimeWindowRecordStore,
        axWindows: [RuntimeAXWindowEntry],
        cgWindows: [RuntimeCGWindowEntry],
        pid: pid_t,
        appName: String,
        remoteScanCompleteness: RuntimeAXRemoteWindowResolver.RemoteScanCompleteness? = nil,
        axCollectionIsComplete: Bool = true,
        cgCollectionIsComplete: Bool = true
    ) -> [RuntimeWindowListEntry] {
        let mappingResolution = windowRecordStore.resolveStableWindowMapping(
            axWindows: axWindows,
            cgWindows: cgWindows,
            pid: pid,
            appName: appName,
            remoteScanCompleteness: remoteScanCompleteness,
            axCollectionIsComplete: axCollectionIsComplete,
            cgCollectionIsComplete: cgCollectionIsComplete
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

        return RuntimeWindowPresentationFilter.filteredAndOrderedEntriesForPresentation(
            exactEntries + deduplicatedUnmatchedAXEntries,
            allEntriesForHostArtifacts: exactEntries + rawUnmatchedAXEntries,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName,
            hasFullscreenTopology: !fullscreenContentBounds.isEmpty,
            cgWindowOrderByID: cgWindowOrderByID,
            stage: "presentation",
            finalStage: "presentation-final"
        )
    }
}
