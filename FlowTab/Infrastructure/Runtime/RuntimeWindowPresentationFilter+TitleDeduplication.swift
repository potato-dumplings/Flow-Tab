import CoreGraphics

extension RuntimeWindowPresentationFilter {
    static func filterCGOnlyEntriesCoveredByActivationEntries(
        _ entries: [RuntimeWindowListEntry],
        knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
        appName: String,
        hasFullscreenTopology: Bool,
        stage: String
    ) -> [RuntimeWindowListEntry] {
        guard entries.count > 1 else { return entries }
        let hasKnownFullscreenTopology = knownCGWindowsByID.values.contains { cgWindow in
            RuntimeWindowTopologyClassifier.hasOffDesktopSpace(spaceIDs: cgWindow.spaceIDs)
                && boundsLookLikeFullscreenContentSurface(cgWindow.bounds)
        }
        guard hasFullscreenTopology || hasKnownFullscreenTopology else { return entries }

        let activationTitleKeys = Set(
            entries.compactMap { entry -> String? in
                guard entry.activationHandleID != nil || entry.axWindow != nil else { return nil }
                guard !RuntimeWindowTitleResolver.titleLooksLikeAppNameFallback(
                    entry.title,
                    appName: appName
                ) else {
                    return nil
                }
                return normalizedTitleKey(entry.title)
            }
        )
        guard !activationTitleKeys.isEmpty else { return entries }

        let uniqueCGWindowIDs = uniquelyRepresentedCGWindowIDs(in: entries)
        var droppedEntries: [RuntimeWindowListEntry] = []
        let filteredEntries = entries.filter { entry in
            guard entry.activationHandleID == nil, entry.axWindow == nil else { return true }

            let isCoveredByActivationTitle = normalizedTitleKey(entry.title).map {
                activationTitleKeys.contains($0)
            } ?? false
            let isFullscreenFallbackArtifact = RuntimeWindowTitleResolver.titleLooksLikeAppNameFallback(
                entry.title,
                appName: appName
            )
            let hasDistinctUserWindowEvidence = entryRepresentsDistinctUserWindow(
                entry,
                uniqueCGWindowIDs: uniqueCGWindowIDs,
                knownCGWindowsByID: knownCGWindowsByID,
                appName: appName
            )
            let shouldDrop = (isCoveredByActivationTitle || isFullscreenFallbackArtifact)
                && !hasDistinctUserWindowEvidence
            if shouldDrop {
                droppedEntries.append(entry)
            }
            return !shouldDrop
        }

        RuntimeWindowFilteredArtifactLogRecord.publish(
            appName: appName,
            kind: .cgOnlyCoveredByActivation,
            stage: stage,
            droppedEntries: droppedEntries
        )
        return filteredEntries
    }

    static func filterRepeatedFullscreenPresentationTitles(
        _ entries: [RuntimeWindowListEntry],
        knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
        appName: String,
        hasFullscreenTopology: Bool,
        stage: String
    ) -> [RuntimeWindowListEntry] {
        guard entries.count > 1 else { return entries }
        let hasKnownFullscreenTopology = knownCGWindowsByID.values.contains { cgWindow in
            RuntimeWindowTopologyClassifier.hasOffDesktopSpace(spaceIDs: cgWindow.spaceIDs)
                && boundsLookLikeFullscreenContentSurface(cgWindow.bounds)
        }
        let hasFullscreenPresentationGeometry = entries.contains {
            entryLooksLikeFullscreenPresentationSurface(
                $0,
                knownCGWindowsByID: knownCGWindowsByID,
                appName: appName
            )
        }
        let repeatedUserTitleKeys = repeatedUserTitleKeys(in: entries, appName: appName)
        let hasFallbackPresentationNoise = entries.contains {
            RuntimeWindowTitleResolver.titleLooksLikeAppNameFallback($0.title, appName: appName)
        } && !repeatedUserTitleKeys.isEmpty
        guard hasFullscreenTopology
            || hasKnownFullscreenTopology
            || hasFullscreenPresentationGeometry
            || hasFallbackPresentationNoise
        else {
            return entries
        }
        let hasUserTitle = entries.contains { entry in
            !RuntimeWindowTitleResolver.titleLooksLikeAppNameFallback(entry.title, appName: appName)
                && normalizedTitleKey(entry.title) != nil
        }
        guard hasUserTitle else { return entries }

        let retainedRepeatedFullscreenWindowIDsByTitle = repeatedFullscreenPresentationWindowIDsToRetain(
            entries,
            knownCGWindowsByID: knownCGWindowsByID,
            appName: appName,
            collapsesFallbackNoiseTitleKeys: hasFallbackPresentationNoise ? repeatedUserTitleKeys : []
        )
        let uniqueCGWindowIDs = uniquelyRepresentedCGWindowIDs(in: entries)
        var seenFullscreenTitleKeys: Set<String> = []
        var droppedCount = 0
        let filteredEntries = entries.filter { entry in
            let hasDistinctUserWindowEvidence = entryRepresentsDistinctUserWindow(
                entry,
                uniqueCGWindowIDs: uniqueCGWindowIDs,
                knownCGWindowsByID: knownCGWindowsByID,
                appName: appName
            )
            if RuntimeWindowTitleResolver.titleLooksLikeAppNameFallback(entry.title, appName: appName) {
                guard !hasDistinctUserWindowEvidence else { return true }
                droppedCount += 1
                return false
            }
            guard let titleKey = normalizedTitleKey(entry.title) else { return true }
            guard !hasDistinctUserWindowEvidence else { return true }
            if let retainedWindowID = retainedRepeatedFullscreenWindowIDsByTitle[titleKey] {
                if entry.windowID != retainedWindowID {
                    droppedCount += 1
                    return false
                }
                seenFullscreenTitleKeys.insert(titleKey)
                return true
            }
            let hasActivationHandle = entry.activationHandleID != nil || entry.axWindow != nil
            let looksLikeFullscreenSurface = entryLooksLikeFullscreenPresentationSurface(
                entry,
                knownCGWindowsByID: knownCGWindowsByID,
                appName: appName
            )
            if seenFullscreenTitleKeys.contains(titleKey), !hasActivationHandle {
                droppedCount += 1
                return false
            }
            guard looksLikeFullscreenSurface else {
                return true
            }
            if seenFullscreenTitleKeys.contains(titleKey) {
                droppedCount += 1
                return false
            }
            seenFullscreenTitleKeys.insert(titleKey)
            return true
        }

        if droppedCount > 0 {
            RuntimeLog.debug(
                .axMatch,
                "\(appName) filtered-repeated-fullscreen-presentation-titles stage=\(stage) dropped=\(droppedCount)"
            )
        }
        return filteredEntries
    }

    private static func entryRepresentsDistinctUserWindow(
        _ entry: RuntimeWindowListEntry,
        uniqueCGWindowIDs: Set<CGWindowID>,
        knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
        appName: String
    ) -> Bool {
        guard let cgWindowID = entry.cgWindowID, uniqueCGWindowIDs.contains(cgWindowID) else {
            return false
        }
        guard let cgWindow = knownCGWindowsByID[cgWindowID] else { return false }
        guard RuntimeCGWindowFacts.passesValidityConstraints(cgWindow) else { return false }
        let hasExactBinding = entry.lastConfirmationSource?.bindingConfidence == .exact
        if hasExactBinding,
           RuntimeWindowTopologyClassifier.classify(spaceIDs: cgWindow.spaceIDs) == .unknown
        {
            return true
        }
        guard RuntimeWindowTopologyClassifier.isDesktopOnlySpaceWindow(spaceIDs: cgWindow.spaceIDs) else {
            return false
        }
        let hasCurrentActivationHandle = entry.activationHandleID != nil
            || entry.axWindow != nil
        if hasExactBinding,
           hasCurrentActivationHandle,
           entry.isOnscreen,
           !entryLooksLikeDesktopFullscreenSiblingSurface(
                entry,
                knownCGWindowsByID: knownCGWindowsByID,
                appName: appName
           )
        {
            return true
        }
        guard boundsLookLikeNormalWindowSurface(cgWindow.bounds) else { return false }
        if hasExactBinding || entry.lastConfirmationSource == .desktopSiblingBinding {
            return true
        }
        guard entry.activationHandleID == nil, entry.axWindow == nil else { return false }
        guard !RuntimeWindowTitleResolver.titleLooksLikeAppNameFallback(
            entry.title,
            appName: appName
        ) else {
            return false
        }
        return true
    }

    private static func uniquelyRepresentedCGWindowIDs(
        in entries: [RuntimeWindowListEntry]
    ) -> Set<CGWindowID> {
        var countsByCGWindowID: [CGWindowID: Int] = [:]
        for cgWindowID in entries.compactMap(\.cgWindowID) {
            countsByCGWindowID[cgWindowID, default: 0] += 1
        }
        return Set(countsByCGWindowID.compactMap { cgWindowID, count in
            count == 1 ? cgWindowID : nil
        })
    }

    private static func repeatedFullscreenPresentationWindowIDsToRetain(
        _ entries: [RuntimeWindowListEntry],
        knownCGWindowsByID: [CGWindowID: RuntimeCGWindowEntry],
        appName: String,
        collapsesFallbackNoiseTitleKeys: Set<String>
    ) -> [String: String] {
        let entriesByTitle = Dictionary(grouping: entries) { entry in
            normalizedTitleKey(entry.title) ?? ""
        }
        var retainedWindowIDsByTitle: [String: String] = [:]
        for (titleKey, titleEntries) in entriesByTitle {
            guard !titleKey.isEmpty, titleEntries.count > 1 else { continue }
            let fullscreenEntries = titleEntries.filter {
                entryLooksLikeFullscreenPresentationSurface(
                    $0,
                    knownCGWindowsByID: knownCGWindowsByID,
                    appName: appName
                )
            }
            if !fullscreenEntries.isEmpty {
                retainedWindowIDsByTitle[titleKey] = fullscreenEntries[0].windowID
            } else if collapsesFallbackNoiseTitleKeys.contains(titleKey) {
                retainedWindowIDsByTitle[titleKey] = titleEntries[0].windowID
            }
        }
        return retainedWindowIDsByTitle
    }

    private static func repeatedUserTitleKeys(
        in entries: [RuntimeWindowListEntry],
        appName: String
    ) -> Set<String> {
        var titleCounts: [String: Int] = [:]
        for entry in entries {
            guard !RuntimeWindowTitleResolver.titleLooksLikeAppNameFallback(entry.title, appName: appName),
                  let titleKey = normalizedTitleKey(entry.title)
            else {
                continue
            }
            titleCounts[titleKey, default: 0] += 1
        }
        return Set(titleCounts.compactMap { titleKey, count in
            count > 1 ? titleKey : nil
        })
    }
}
