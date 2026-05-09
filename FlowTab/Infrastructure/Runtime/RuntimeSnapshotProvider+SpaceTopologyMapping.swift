import CoreGraphics
import Foundation

struct RuntimeWindowMatchResolution {
    var directMatches: [String: CGWindowID] = [:]
    var reboundMatches: [String: CGWindowID] = [:]
}

extension RuntimeSnapshotProvider {
    static func resolveFullscreenContentRebindings(
        matches: [String: CGWindowID],
        axWindows: [AXWindowEntry],
        cgWindows: [CGWindowEntry],
        assignedCGWindowIDs: Set<CGWindowID>,
        appName: String
    ) -> RuntimeWindowMatchResolution {
        guard !matches.isEmpty else { return RuntimeWindowMatchResolution() }
        let fullscreenContentWindows = cgWindows.filter {
            RuntimeWindowTopologyClassifier.isLikelyOffDesktopFullscreenContent(
                bounds: $0.bounds,
                spaceIDs: $0.spaceIDs
            )
        }
        let fullscreenContentBounds = fullscreenContentWindows.compactMap(\.bounds)
        guard !fullscreenContentBounds.isEmpty else {
            return RuntimeWindowMatchResolution(directMatches: matches)
        }

        let axWindowsByID = Dictionary(uniqueKeysWithValues: axWindows.map { ($0.id, $0) })
        let cgWindowsByID = Dictionary(uniqueKeysWithValues: cgWindows.map { ($0.id, $0) })
        let currentMatchedCGWindowIDs = Set(matches.values)
        var directMatches: [String: CGWindowID] = [:]
        var reboundMatches: [String: CGWindowID] = [:]
        var reservedContentWindowIDs: Set<CGWindowID> = []

        for (axWindowID, cgWindowID) in matches.sorted(by: { $0.key < $1.key }) {
            guard
                let wrapperCGWindow = cgWindowsByID[cgWindowID],
                RuntimeWindowTopologyClassifier.isLikelyDesktopWrapper(
                    bounds: wrapperCGWindow.bounds,
                    spaceIDs: wrapperCGWindow.spaceIDs,
                    fullscreenContentBounds: fullscreenContentBounds
                )
            else {
                directMatches[axWindowID] = cgWindowID
                continue
            }

            let axWindow = axWindowsByID[axWindowID]
            let candidates = fullscreenContentWindows.filter { contentWindow in
                guard !assignedCGWindowIDs.contains(contentWindow.id) else { return false }
                guard !currentMatchedCGWindowIDs.contains(contentWindow.id) else { return false }
                guard !reservedContentWindowIDs.contains(contentWindow.id) else { return false }
                guard topologyTitlesAreCompatible(
                    axWindow?.sourceTitle ?? axWindow?.title,
                    contentWindow.title,
                    appName: appName
                ) else {
                    return false
                }
                return topologyTitlesAreCompatible(
                    wrapperCGWindow.title,
                    contentWindow.title,
                    appName: appName
                )
            }

            if candidates.count == 1, let contentWindow = candidates.first {
                reboundMatches[axWindowID] = contentWindow.id
                reservedContentWindowIDs.insert(contentWindow.id)
            } else {
                directMatches[axWindowID] = cgWindowID
            }
        }

        return RuntimeWindowMatchResolution(
            directMatches: directMatches,
            reboundMatches: reboundMatches
        )
    }

    static func resolveDesktopSiblingAXBindings(
        axWindows: [AXWindowEntry],
        cgWindows: [CGWindowEntry],
        assignedCGWindowIDs: Set<CGWindowID>,
        appName: String
    ) -> [String: CGWindowID] {
        guard !axWindows.isEmpty else { return [:] }
        let fullscreenContentBounds = cgWindows.compactMap { cgWindow -> CGRect? in
            guard RuntimeWindowTopologyClassifier.isLikelyOffDesktopFullscreenContent(
                bounds: cgWindow.bounds,
                spaceIDs: cgWindow.spaceIDs
            ) else {
                return nil
            }
            return cgWindow.bounds
        }
        guard !fullscreenContentBounds.isEmpty else { return [:] }

        let desktopCGWindows = cgWindows.filter { cgWindow in
            guard !assignedCGWindowIDs.contains(cgWindow.id) else { return false }
            guard RuntimeWindowTopologyClassifier.isDesktopOnlySpaceWindow(spaceIDs: cgWindow.spaceIDs) else {
                return false
            }
            return !RuntimeWindowTopologyClassifier.isLikelyDesktopWrapper(
                bounds: cgWindow.bounds,
                spaceIDs: cgWindow.spaceIDs,
                fullscreenContentBounds: fullscreenContentBounds
            )
        }
        guard !desktopCGWindows.isEmpty else { return [:] }

        var candidateCGIDsByAXWindowID: [String: Set<CGWindowID>] = [:]
        var candidateAXWindowIDsByCGWindowID: [CGWindowID: Set<String>] = [:]
        for axWindow in axWindows {
            guard let axFrame = axWindow.frame else { continue }
            let candidateCGWindowIDs = Set(desktopCGWindows.compactMap { cgWindow -> CGWindowID? in
                guard let cgFrame = cgWindow.bounds else { return nil }
                guard RuntimeWindowTopologyClassifier.framesApproximatelyMatch(axFrame, cgFrame) else {
                    return nil
                }
                guard topologyTitlesAreCompatible(
                    axWindow.sourceTitle ?? axWindow.title,
                    cgWindow.title,
                    appName: appName
                ) else {
                    return nil
                }
                return cgWindow.id
            })
            if !candidateCGWindowIDs.isEmpty {
                candidateCGIDsByAXWindowID[axWindow.id] = candidateCGWindowIDs
            }
        }

        for cgWindow in desktopCGWindows {
            guard let cgFrame = cgWindow.bounds else { continue }
            let candidateAXWindowIDs = Set(axWindows.compactMap { axWindow -> String? in
                guard let axFrame = axWindow.frame else { return nil }
                guard RuntimeWindowTopologyClassifier.framesApproximatelyMatch(axFrame, cgFrame) else {
                    return nil
                }
                guard topologyTitlesAreCompatible(
                    axWindow.sourceTitle ?? axWindow.title,
                    cgWindow.title,
                    appName: appName
                ) else {
                    return nil
                }
                return axWindow.id
            })
            if !candidateAXWindowIDs.isEmpty {
                candidateAXWindowIDsByCGWindowID[cgWindow.id] = candidateAXWindowIDs
            }
        }

        var matches: [String: CGWindowID] = [:]
        for (axWindowID, candidateCGWindowIDs) in candidateCGIDsByAXWindowID {
            guard candidateCGWindowIDs.count == 1, let cgWindowID = candidateCGWindowIDs.first else {
                continue
            }
            guard candidateAXWindowIDsByCGWindowID[cgWindowID]?.count == 1 else { continue }
            matches[axWindowID] = cgWindowID
        }

        let unmatchedAXWindows = axWindows.filter { matches[$0.id] == nil }
        let matchedCGWindowIDs = Set(matches.values)
        let unmatchedDesktopCGWindows = desktopCGWindows.filter {
            !matchedCGWindowIDs.contains($0.id)
        }
        if
            unmatchedAXWindows.count == 1,
            unmatchedDesktopCGWindows.count == 1,
            let axWindow = unmatchedAXWindows.first,
            let cgWindow = unmatchedDesktopCGWindows.first,
            let axFrame = axWindow.frame,
            let cgFrame = cgWindow.bounds,
            RuntimeWindowTopologyClassifier.framesApproximatelyMatch(axFrame, cgFrame),
            topologyTitlesAreCompatible(
                axWindow.sourceTitle ?? axWindow.title,
                cgWindow.title,
                appName: appName
            )
        {
            matches[axWindow.id] = cgWindow.id
        }

        return matches
    }

    static func resolveFullscreenContentFallbackBindings(
        axWindows: [AXWindowEntry],
        cgWindows: [CGWindowEntry],
        assignedCGWindowIDs: Set<CGWindowID>,
        appName: String
    ) -> [String: CGWindowID] {
        guard !axWindows.isEmpty else { return [:] }
        let contentCGWindows = cgWindows.filter {
            !assignedCGWindowIDs.contains($0.id)
                && RuntimeWindowTopologyClassifier.isLikelyOffDesktopFullscreenContent(
                    bounds: $0.bounds,
                    spaceIDs: $0.spaceIDs
                )
        }
        guard !contentCGWindows.isEmpty else { return [:] }

        var candidateCGIDsByAXWindowID: [String: Set<CGWindowID>] = [:]
        var candidateAXWindowIDsByCGWindowID: [CGWindowID: Set<String>] = [:]
        for axWindow in axWindows {
            let candidateCGWindowIDs = Set(contentCGWindows.compactMap { cgWindow -> CGWindowID? in
                guard topologyFramesAreCompatible(axWindow.frame, cgWindow.bounds) else {
                    return nil
                }
                guard topologyTitlesAreCompatible(
                    axWindow.sourceTitle ?? axWindow.title,
                    cgWindow.title,
                    appName: appName
                ) else {
                    return nil
                }
                return cgWindow.id
            })
            if !candidateCGWindowIDs.isEmpty {
                candidateCGIDsByAXWindowID[axWindow.id] = candidateCGWindowIDs
            }
        }

        for cgWindow in contentCGWindows {
            let candidateAXWindowIDs = Set(axWindows.compactMap { axWindow -> String? in
                guard topologyFramesAreCompatible(axWindow.frame, cgWindow.bounds) else {
                    return nil
                }
                guard topologyTitlesAreCompatible(
                    axWindow.sourceTitle ?? axWindow.title,
                    cgWindow.title,
                    appName: appName
                ) else {
                    return nil
                }
                return axWindow.id
            })
            if !candidateAXWindowIDs.isEmpty {
                candidateAXWindowIDsByCGWindowID[cgWindow.id] = candidateAXWindowIDs
            }
        }

        var matches: [String: CGWindowID] = [:]
        for (axWindowID, candidateCGWindowIDs) in candidateCGIDsByAXWindowID {
            guard candidateCGWindowIDs.count == 1, let cgWindowID = candidateCGWindowIDs.first else {
                continue
            }
            guard candidateAXWindowIDsByCGWindowID[cgWindowID]?.count == 1 else { continue }
            matches[axWindowID] = cgWindowID
        }

        if
            matches.isEmpty,
            axWindows.count == 1,
            contentCGWindows.count == 1,
            let axWindow = axWindows.first,
            let cgWindow = contentCGWindows.first,
            topologyFramesAreCompatible(axWindow.frame, cgWindow.bounds),
            topologyTitlesAreCompatible(
                axWindow.sourceTitle ?? axWindow.title,
                cgWindow.title,
                appName: appName
            )
        {
            matches[axWindow.id] = cgWindow.id
        }

        return matches
    }
}

private func topologyFramesAreCompatible(_ axFrame: CGRect?, _ cgFrame: CGRect?) -> Bool {
    switch (axFrame, cgFrame) {
    case let (axFrame?, cgFrame?):
        return RuntimeWindowTopologyClassifier.framesApproximatelyMatch(axFrame, cgFrame)
    case (nil, _), (_, nil):
        return true
    }
}

func runtimeWindowCanBeExposedWithoutCurrentAXHandle(
    spaceIDs: [Int],
    isLikelyDesktopWrapper: Bool,
    hasFullscreenTopology: Bool,
    allowSpaceOneWithoutCurrentAXHandle: Bool
) -> Bool {
    let normalizedSpaceIDs = RuntimeWindowTopologyClassifier.normalizedSpaceIDs(spaceIDs)
    guard !normalizedSpaceIDs.isEmpty else { return true }
    guard RuntimeWindowTopologyClassifier.isDesktopOnlySpaceWindow(spaceIDs: normalizedSpaceIDs) else {
        return true
    }
    if isLikelyDesktopWrapper { return false }
    if hasFullscreenTopology { return true }
    return allowSpaceOneWithoutCurrentAXHandle
}

private func topologyTitlesAreCompatible(
    _ lhs: String?,
    _ rhs: String?,
    appName: String
) -> Bool {
    let left = normalizedNonFallbackTopologyTitle(lhs, appName: appName)
    let right = normalizedNonFallbackTopologyTitle(rhs, appName: appName)
    switch (left, right) {
    case let (left?, right?):
        return left.caseInsensitiveCompare(right) == .orderedSame
    default:
        return true
    }
}

private func normalizedNonFallbackTopologyTitle(_ title: String?, appName: String) -> String? {
    guard let normalizedTitle = normalizedRuntimeWindowTitle(title) else { return nil }
    guard let normalizedAppName = normalizedRuntimeWindowTitle(appName) else {
        return normalizedTitle
    }
    guard normalizedTitle.caseInsensitiveCompare(normalizedAppName) != .orderedSame else {
        return nil
    }
    return normalizedTitle
}
