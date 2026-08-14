import CoreGraphics
import Foundation

enum RuntimeWindowPresentationFilter {
    private static let fullscreenSiblingArtifactMinimumWidth: CGFloat = 500
    private static let fullscreenSiblingArtifactMaximumHeight: CGFloat = 560
    private static let fullscreenContentSiblingMinimumWidth: CGFloat = 900
    private static let fullscreenContentSiblingMinimumHeight: CGFloat = 600
    private static let fullscreenContentSiblingOriginTolerance: CGFloat = 90
    private static let fullscreenContentSiblingTopInsetLimit: CGFloat = 260
    private static let auxiliaryOverlayMaximumWidth: CGFloat = 720
    private static let auxiliaryOverlayMaximumHeight: CGFloat = 180
    private static let auxiliaryOverlayContainmentTolerance: CGFloat = 8

    static func filterFullscreenHostArtifactEntries(
        _ entries: [RuntimeWindowListEntry],
        allEntries: [RuntimeWindowListEntry],
        knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
        appName: String,
        hasFullscreenTopology: Bool,
        stage: String
    ) -> [RuntimeWindowListEntry] {
        guard hasFullscreenTopology, !entries.isEmpty else { return entries }

        let activationSurfaces = allEntries.filter {
            entryLooksLikeAXBackedFullscreenContentSurface(
                $0,
                knownCGWindowsByID: knownCGWindowsByID,
                appName: appName
            )
        }
        guard !activationSurfaces.isEmpty else { return entries }

        var droppedEntries: [RuntimeWindowListEntry] = []
        let filteredEntries = entries.filter { entry in
            let isArtifact = entryLooksLikeFullscreenHostArtifact(
                entry,
                activationSurfaces: activationSurfaces,
                knownCGWindowsByID: knownCGWindowsByID,
                appName: appName
            )
            if isArtifact {
                droppedEntries.append(entry)
            }
            return !isArtifact
        }

        RuntimeWindowFilteredArtifactLogRecord.publish(
            appName: appName,
            kind: .fullscreenHostArtifacts,
            stage: stage,
            droppedEntries: droppedEntries
        )
        return filteredEntries
    }

    static func filterFullscreenSiblingArtifactEntries(
        _ entries: [RuntimeWindowListEntry],
        allEntries: [RuntimeWindowListEntry],
        knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
        appName: String,
        hasFullscreenTopology: Bool,
        stage: String
    ) -> [RuntimeWindowListEntry] {
        guard !entries.isEmpty else { return entries }
        let hasFullscreenPresentationGeometry = allEntries.contains {
            entryLooksLikeFullscreenPresentationSurface(
                $0,
                knownCGWindowsByID: knownCGWindowsByID,
                appName: appName
            )
        }
        guard hasFullscreenTopology || hasFullscreenPresentationGeometry else { return entries }

        let strongTitles = Set(
            allEntries.compactMap { entry -> String? in
                guard entryLooksLikeStrongUserWindow(
                    entry,
                    knownCGWindowsByID: knownCGWindowsByID,
                    appName: appName
                ) else {
                    return nil
                }
                return normalizedTitleKey(entry.title)
            }
        )
        guard !strongTitles.isEmpty else { return entries }

        var droppedEntries: [RuntimeWindowListEntry] = []
        let filteredEntries = entries.filter { entry in
            let isArtifact = entryLooksLikeFullscreenSiblingArtifact(
                entry,
                knownCGWindowsByID: knownCGWindowsByID,
                appName: appName,
                strongTitles: strongTitles
            )
            if isArtifact {
                droppedEntries.append(entry)
            }
            return !isArtifact
        }

        RuntimeWindowFilteredArtifactLogRecord.publish(
            appName: appName,
            kind: .fullscreenSiblingArtifacts,
            stage: stage,
            droppedEntries: droppedEntries
        )
        return filteredEntries
    }

    static func filterAuxiliaryOverlayEntries(
        _ entries: [RuntimeWindowListEntry],
        knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
        appName: String,
        stage: String
    ) -> [RuntimeWindowListEntry] {
        guard entries.count > 1 else { return entries }

        let primarySurfaces = entries.filter {
            entryLooksLikeStrongUserWindow(
                $0,
                knownCGWindowsByID: knownCGWindowsByID,
                appName: appName
            )
        }
        guard !primarySurfaces.isEmpty else { return entries }

        var droppedCount = 0
        let filteredEntries = entries.filter { entry in
            let isOverlay = entryLooksLikeContainedAuxiliaryOverlay(
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

    static func filterDuplicateFullscreenContentEntries(
        _ entries: [RuntimeWindowListEntry],
        knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
        appName: String,
        stage: String
    ) -> [RuntimeWindowListEntry] {
        guard entries.count > 1 else { return entries }

        let contentSurfaces = entries.filter {
            entryLooksLikeTopologyFullscreenContentSurface(
                $0,
                knownCGWindowsByID: knownCGWindowsByID,
                appName: appName
            )
        }
        guard !contentSurfaces.isEmpty else { return entries }

        var droppedEntries: [RuntimeWindowListEntry] = []
        let filteredEntries = entries.filter { entry in
            let isDuplicateHost = entryLooksLikeDuplicateFullscreenGeometryHost(
                entry,
                contentSurfaces: contentSurfaces,
                knownCGWindowsByID: knownCGWindowsByID,
                appName: appName
            )
            if isDuplicateHost {
                droppedEntries.append(entry)
            }
            return !isDuplicateHost
        }

        RuntimeWindowFilteredArtifactLogRecord.publish(
            appName: appName,
            kind: .fullscreenDuplicateSurfaces,
            stage: stage,
            droppedEntries: droppedEntries
        )
        return filteredEntries
    }

    static func orderWindowEntriesForPresentation(
        _ entries: [RuntimeWindowListEntry],
        prioritizesOnscreen: Bool = false,
        cgWindowOrderByID: [CGWindowID: Int] = [:],
        knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry] = [:],
        appName: String = ""
    ) -> [RuntimeWindowListEntry] {
        let presentationEntries = filterDuplicateFullscreenContentEntries(
            entries,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName,
            stage: "ordering"
        )
        let hasRelatedFullscreenTopology = prioritizesOnscreen
            || knownCGWindowsByID.values.contains { cgWindow in
                RuntimeWindowTopologyClassifier.hasOffDesktopSpace(spaceIDs: cgWindow.spaceIDs)
                    && boundsLookLikeFullscreenContentSurface(cgWindow.bounds)
            }
        let hasOnscreenPrimarySurface = presentationEntries.contains { entry in
            entry.isOnscreen
                && !entryLooksLikeDesktopFullscreenSiblingSurface(
                    entry,
                    knownCGWindowsByID: knownCGWindowsByID,
                    appName: appName
                )
        }
        let orderedEntries = presentationEntries.enumerated().sorted { lhs, rhs in
            let lhsHasActivationHandle = lhs.element.activationHandleID != nil || lhs.element.axWindow != nil
            let rhsHasActivationHandle = rhs.element.activationHandleID != nil || rhs.element.axWindow != nil
            if prioritizesOnscreen, lhs.element.isOnscreen != rhs.element.isOnscreen {
                return lhs.element.isOnscreen
            }
            if hasRelatedFullscreenTopology, hasOnscreenPrimarySurface {
                if !lhs.element.isOnscreen, !rhs.element.isOnscreen {
                    let lhsIsDesktop = entryUsesDesktopSpace(lhs.element)
                    let rhsIsDesktop = entryUsesDesktopSpace(rhs.element)
                    if lhsIsDesktop != rhsIsDesktop {
                        return lhsIsDesktop
                    }
                }
                let lhsLooksLikeSibling = entryLooksLikeDesktopFullscreenSiblingSurface(
                    lhs.element,
                    knownCGWindowsByID: knownCGWindowsByID,
                    appName: appName
                )
                let rhsLooksLikeSibling = entryLooksLikeDesktopFullscreenSiblingSurface(
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

    static func filteredAndOrderedEntriesForPresentation(
        _ entries: [RuntimeWindowListEntry],
        allEntriesForHostArtifacts: [RuntimeWindowListEntry]? = nil,
        knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
        appName: String,
        hasFullscreenTopology: Bool,
        cgWindowOrderByID: [CGWindowID: Int],
        stage: String,
        finalStage: String
    ) -> [RuntimeWindowListEntry] {
        let hostFilteredEntries = filterFullscreenHostArtifactEntries(
            entries,
            allEntries: allEntriesForHostArtifacts ?? entries,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName,
            hasFullscreenTopology: hasFullscreenTopology,
            stage: stage
        )
        let siblingFilteredEntries = filterFullscreenSiblingArtifactEntries(
            hostFilteredEntries,
            allEntries: hostFilteredEntries,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName,
            hasFullscreenTopology: hasFullscreenTopology,
            stage: stage
        )
        let overlayFilteredEntries = filterAuxiliaryOverlayEntries(
            siblingFilteredEntries,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName,
            stage: stage
        )
        let activationCoveredEntries = filterCGOnlyEntriesCoveredByActivationEntries(
            overlayFilteredEntries,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName,
            hasFullscreenTopology: hasFullscreenTopology,
            stage: stage
        )
        let duplicateFilteredEntries = filterDuplicateFullscreenContentEntries(
            activationCoveredEntries,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName,
            stage: finalStage
        )
        let titleFilteredEntries = filterRepeatedFullscreenPresentationTitles(
            duplicateFilteredEntries,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName,
            hasFullscreenTopology: hasFullscreenTopology,
            stage: finalStage
        )

        return orderWindowEntriesForPresentation(
            titleFilteredEntries,
            prioritizesOnscreen: hasFullscreenTopology,
            cgWindowOrderByID: cgWindowOrderByID,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName
        )
    }

    private static func entryUsesDesktopSpace(_ entry: RuntimeWindowListEntry) -> Bool {
        RuntimeWindowTopologyClassifier.isDesktopOnlySpaceWindow(spaceIDs: entry.spaceIDs)
    }

    private static func entryLooksLikeFullscreenHostArtifact(
        _ entry: RuntimeWindowListEntry,
        activationSurfaces: [RuntimeWindowListEntry],
        knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
        appName: String
    ) -> Bool {
        guard RuntimeWindowTopologyClassifier.hasOffDesktopSpace(spaceIDs: entry.spaceIDs) else { return false }
        guard let hostBounds = entryBounds(entry, knownCGWindowsByID: knownCGWindowsByID)?.standardized else {
            return false
        }
        guard RuntimeWindowTopologyClassifier.isLikelyFullscreenContent(bounds: hostBounds) else {
            return false
        }

        return activationSurfaces.contains { activationSurface in
            guard activationSurface.cgWindowID != entry.cgWindowID else { return false }
            guard titlesCanRepresentSameFullscreenSurface(
                entry.title,
                activationSurface.title,
                appName: appName
            ) else {
                return false
            }
            guard let contentBounds = entryBounds(
                activationSurface,
                knownCGWindowsByID: knownCGWindowsByID
            )?.standardized else {
                return false
            }
            return fullscreenHostBounds(hostBounds, containContentSurfaceBounds: contentBounds)
        }
    }

    private static func entryLooksLikeAXBackedFullscreenContentSurface(
        _ entry: RuntimeWindowListEntry,
        knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
        appName: String
    ) -> Bool {
        guard entry.activationHandleID != nil || entry.axWindow != nil else { return false }
        guard !RuntimeWindowTitleResolver.titleLooksLikeAppNameFallback(entry.title, appName: appName) else { return false }
        return entryLooksLikeStrongUserWindow(
            entry,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName
        )
    }

    private static func entryLooksLikeDesktopFullscreenSiblingSurface(
        _ entry: RuntimeWindowListEntry,
        knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
        appName: String
    ) -> Bool {
        guard entry.isOnscreen else { return false }
        let bounds = entryBounds(entry, knownCGWindowsByID: knownCGWindowsByID)
        guard boundsLookLikeFullscreenContentSurface(bounds) else {
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
            guard boundsLookLikeFullscreenContentSurface(relatedBounds) else {
                return false
            }
            if let bounds, RuntimeWindowTopologyClassifier.framesApproximatelyMatch(bounds, relatedBounds) {
                return true
            }
            return titlesCanRepresentSameFullscreenSurface(
                entry.title,
                cgWindow.title,
                appName: appName
            )
        }
    }

    static func boundsLookLikeFullscreenContentSurface(_ bounds: CGRect?) -> Bool {
        if RuntimeWindowTopologyClassifier.isLikelyFullscreenContent(bounds: bounds) {
            return true
        }
        guard let bounds = bounds?.standardized else { return false }
        guard bounds.width >= fullscreenContentSiblingMinimumWidth else { return false }
        guard bounds.height >= fullscreenContentSiblingMinimumHeight else { return false }
        guard abs(bounds.minX) <= fullscreenContentSiblingOriginTolerance else { return false }
        return bounds.minY >= 0 && bounds.minY <= fullscreenContentSiblingTopInsetLimit
    }

    static func boundsLookLikeNormalWindowSurface(_ bounds: CGRect?) -> Bool {
        guard let bounds = bounds?.standardized else { return false }
        return bounds.width >= fullscreenSiblingArtifactMinimumWidth
            && bounds.height > fullscreenSiblingArtifactMaximumHeight
            && !boundsLookLikeFullscreenContentSurface(bounds)
    }

    private static func entryLooksLikeFullscreenSiblingArtifact(
        _ entry: RuntimeWindowListEntry,
        knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
        appName: String,
        strongTitles: Set<String>
    ) -> Bool {
        guard entryLooksLikeShallowFullscreenSibling(entry, knownCGWindowsByID: knownCGWindowsByID) else {
            return false
        }

        if RuntimeWindowTitleResolver.titleLooksLikeAppNameFallback(entry.title, appName: appName) {
            return true
        }

        guard let titleKey = normalizedTitleKey(entry.title) else { return false }
        return strongTitles.contains(titleKey)
            && !entryLooksLikeStrongUserWindow(
                entry,
                knownCGWindowsByID: knownCGWindowsByID,
                appName: appName
            )
    }

    private static func entryLooksLikeStrongUserWindow(
        _ entry: RuntimeWindowListEntry,
        knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
        appName: String
    ) -> Bool {
        let bounds = entryBounds(entry, knownCGWindowsByID: knownCGWindowsByID)
        if RuntimeWindowTopologyClassifier.isLikelyFullscreenContent(bounds: bounds) {
            return true
        }

        guard !RuntimeWindowTitleResolver.titleLooksLikeAppNameFallback(entry.title, appName: appName) else {
            return false
        }
        guard let bounds = bounds?.standardized else { return false }
        return bounds.width >= fullscreenSiblingArtifactMinimumWidth
            && bounds.height > fullscreenSiblingArtifactMaximumHeight
    }

    private static func entryLooksLikeShallowFullscreenSibling(
        _ entry: RuntimeWindowListEntry,
        knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry]
    ) -> Bool {
        guard let bounds = entryBounds(entry, knownCGWindowsByID: knownCGWindowsByID)?.standardized else {
            return false
        }
        guard !RuntimeWindowTopologyClassifier.isLikelyFullscreenContent(bounds: bounds) else {
            return false
        }
        return bounds.width >= fullscreenSiblingArtifactMinimumWidth
            && bounds.height <= fullscreenSiblingArtifactMaximumHeight
    }

    private static func entryLooksLikeTopologyFullscreenContentSurface(
        _ entry: RuntimeWindowListEntry,
        knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
        appName: String
    ) -> Bool {
        guard entryLooksLikeStrongUserWindow(
            entry,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName
        ) else {
            return false
        }
        guard !RuntimeWindowTitleResolver.titleLooksLikeAppNameFallback(entry.title, appName: appName) else {
            return false
        }
        guard RuntimeWindowTopologyClassifier.hasOffDesktopSpace(spaceIDs: entry.spaceIDs) else {
            return false
        }
        return boundsLookLikeFullscreenContentSurface(entryBounds(entry, knownCGWindowsByID: knownCGWindowsByID))
    }

    static func entryLooksLikeFullscreenPresentationSurface(
        _ entry: RuntimeWindowListEntry,
        knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
        appName: String
    ) -> Bool {
        if entryLooksLikeTopologyFullscreenContentSurface(
            entry,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName
        ) {
            return true
        }
        if entryLooksLikeDesktopFullscreenSiblingSurface(
            entry,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName
        ) {
            return true
        }
        return boundsLookLikeFullscreenContentSurface(
            entryBounds(entry, knownCGWindowsByID: knownCGWindowsByID)
        )
    }

    private static func entryLooksLikeDuplicateFullscreenGeometryHost(
        _ entry: RuntimeWindowListEntry,
        contentSurfaces: [RuntimeWindowListEntry],
        knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
        appName: String
    ) -> Bool {
        guard entry.activationHandleID == nil, entry.axWindow == nil else { return false }
        guard let hostBounds = entryBounds(entry, knownCGWindowsByID: knownCGWindowsByID)?.standardized else {
            return false
        }
        guard RuntimeWindowTopologyClassifier.hasOffDesktopSpace(spaceIDs: entry.spaceIDs) else {
            return false
        }
        guard RuntimeWindowTopologyClassifier.isLikelyFullscreenContent(bounds: hostBounds) else {
            return false
        }

        return contentSurfaces.contains { contentSurface in
            guard contentSurface.cgWindowID != entry.cgWindowID else { return false }
            guard entriesShareAnySpace(entry, contentSurface) else { return false }
            guard titlesCanRepresentSameFullscreenSurface(
                entry.title,
                contentSurface.title,
                appName: appName
            ) else {
                return false
            }
            guard let contentBounds = entryBounds(
                contentSurface,
                knownCGWindowsByID: knownCGWindowsByID
            )?.standardized else {
                return false
            }
            return fullscreenHostBounds(hostBounds, containContentSurfaceBounds: contentBounds)
        }
    }

    private static func entryLooksLikeContainedAuxiliaryOverlay(
        _ entry: RuntimeWindowListEntry,
        primarySurfaces: [RuntimeWindowListEntry],
        knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
        appName: String
    ) -> Bool {
        guard !entryLooksLikeStrongUserWindow(
            entry,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName
        ) else {
            return false
        }
        guard let bounds = entryBounds(entry, knownCGWindowsByID: knownCGWindowsByID)?.standardized else {
            return false
        }
        guard bounds.width > 0, bounds.height > 0 else { return false }
        guard bounds.width <= auxiliaryOverlayMaximumWidth else { return false }
        guard bounds.height <= auxiliaryOverlayMaximumHeight else { return false }

        return primarySurfaces.contains { primarySurface in
            guard primarySurface.cgWindowID != entry.cgWindowID else { return false }
            guard entriesShareAnySpace(entry, primarySurface) else { return false }
            guard let primaryBounds = entryBounds(
                primarySurface,
                knownCGWindowsByID: knownCGWindowsByID
            )?.standardized else {
                return false
            }
            let containmentBounds = primaryBounds.insetBy(
                dx: -auxiliaryOverlayContainmentTolerance,
                dy: -auxiliaryOverlayContainmentTolerance
            )
            return containmentBounds.contains(bounds)
        }
    }

    private static func entriesShareAnySpace(
        _ lhs: RuntimeWindowListEntry,
        _ rhs: RuntimeWindowListEntry
    ) -> Bool {
        let lhsSpaces = Set(RuntimeWindowTopologyClassifier.normalizedSpaceIDs(lhs.spaceIDs))
        let rhsSpaces = Set(RuntimeWindowTopologyClassifier.normalizedSpaceIDs(rhs.spaceIDs))
        guard !lhsSpaces.isEmpty, !rhsSpaces.isEmpty else { return false }
        return !lhsSpaces.isDisjoint(with: rhsSpaces)
    }

    private static func entryBounds(
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

    private static func titlesCanRepresentSameFullscreenSurface(
        _ lhs: String?,
        _ rhs: String?,
        appName: String
    ) -> Bool {
        let leftLooksLikeAppFallback = RuntimeWindowTitleResolver.titleLooksLikeAppNameFallback(lhs, appName: appName)
        let rightLooksLikeAppFallback = RuntimeWindowTitleResolver.titleLooksLikeAppNameFallback(rhs, appName: appName)
        let left = leftLooksLikeAppFallback ? nil : normalizedTitleKey(lhs)
        let right = rightLooksLikeAppFallback ? nil : normalizedTitleKey(rhs)
        switch (left, right) {
        case let (left?, right?):
            return left == right
        case (nil, _?):
            return true
        default:
            return false
        }
    }

    private static func fullscreenHostBounds(
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

    static func normalizedTitleKey(_ title: String?) -> String? {
        normalizedRuntimeWindowTitle(title)?.lowercased()
    }
}
