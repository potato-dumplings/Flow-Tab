import CoreGraphics
import Foundation

extension RuntimeSnapshotProvider {
    static func matchCGWindowAssignments(
        axWindows: [AXWindowEntry],
        cgWindows: [RuntimeCGWindowEntry],
        appName: String? = nil,
        previousMatches: [String: CGWindowID] = [:]
    ) -> [String: CGWindowID] {
        matchCGWindowAssignmentsWithDiagnostics(
            axWindows: axWindows,
            cgWindows: cgWindows,
            appName: appName,
            previousMatches: previousMatches
        ).matches
    }

    static func matchCGWindowAssignmentsWithDiagnostics(
        axWindows: [AXWindowEntry],
        cgWindows: [RuntimeCGWindowEntry],
        appName: String? = nil,
        previousMatches: [String: CGWindowID] = [:]
    ) -> RuntimeWindowAssignmentMatchResult {
        _ = previousMatches
        guard !axWindows.isEmpty, !cgWindows.isEmpty else {
            return RuntimeWindowAssignmentMatchResult(matches: [:], bindingDiagnostics: [])
        }

        var candidateCGIDsByAXWindowID: [String: Set<CGWindowID>] = [:]
        var candidateAXWindowIDsByCGWindowID: [CGWindowID: Set<String>] = [:]

        for axWindow in axWindows {
            let candidateCGWindowIDs = Set(cgWindows.compactMap { cgWindow -> CGWindowID? in
                guard exactCandidateMatch(
                    axWindow: axWindow,
                    cgWindow: cgWindow,
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

        for cgWindow in cgWindows {
            let candidateAXWindowIDs = Set(axWindows.compactMap { axWindow -> String? in
                guard exactCandidateMatch(
                    axWindow: axWindow,
                    cgWindow: cgWindow,
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

        refineCandidateAssignmentsWithPublicAXState(
            axWindows: axWindows,
            cgWindows: cgWindows,
            candidateCGIDsByAXWindowID: &candidateCGIDsByAXWindowID,
            candidateAXWindowIDsByCGWindowID: &candidateAXWindowIDsByCGWindowID
        )

        var remainingCGIDsByAXWindowID = candidateCGIDsByAXWindowID
        var remainingAXIDsByCGWindowID = candidateAXWindowIDsByCGWindowID
        var matchedByWindowID: [String: CGWindowID] = [:]

        while true {
            let exactPairs = remainingCGIDsByAXWindowID.compactMap { axWindowID, candidateCGWindowIDs -> (String, CGWindowID)? in
                guard candidateCGWindowIDs.count == 1, let cgWindowID = candidateCGWindowIDs.first else {
                    return nil
                }
                guard remainingAXIDsByCGWindowID[cgWindowID]?.count == 1 else { return nil }
                return (axWindowID, cgWindowID)
            }
            if exactPairs.isEmpty {
                break
            }

            for (axWindowID, cgWindowID) in exactPairs.sorted(by: { lhs, rhs in
                if lhs.0 == rhs.0 {
                    return lhs.1 < rhs.1
                }
                return lhs.0 < rhs.0
            }) {
                matchedByWindowID[axWindowID] = cgWindowID
                remainingCGIDsByAXWindowID.removeValue(forKey: axWindowID)
                remainingAXIDsByCGWindowID.removeValue(forKey: cgWindowID)
                for key in remainingCGIDsByAXWindowID.keys {
                    remainingCGIDsByAXWindowID[key]?.remove(cgWindowID)
                }
                for key in remainingAXIDsByCGWindowID.keys {
                    remainingAXIDsByCGWindowID[key]?.remove(axWindowID)
                }
            }
        }

        let bindingDiagnostics = unresolvedAssignmentDiagnostics(
            remainingCGIDsByAXWindowID: remainingCGIDsByAXWindowID,
            remainingAXIDsByCGWindowID: remainingAXIDsByCGWindowID,
            matchedByWindowID: matchedByWindowID
        )
        for diagnostic in bindingDiagnostics {
            RuntimeLog.debug(
                .axMatch,
                "binding-assignment ambiguous ax=\(diagnostic.axWindowID ?? "nil") candidates=\(diagnostic.candidateCount) candidateCG=\(diagnostic.cgWindowID.map(String.init) ?? "nil") allowedActions=\(diagnostic.allowedActions.map(\.rawValue).sorted().joined(separator: ","))"
            )
        }
        return RuntimeWindowAssignmentMatchResult(
            matches: matchedByWindowID,
            bindingDiagnostics: bindingDiagnostics
        )
    }

    private static func refineCandidateAssignmentsWithPublicAXState(
        axWindows: [AXWindowEntry],
        cgWindows: [RuntimeCGWindowEntry],
        candidateCGIDsByAXWindowID: inout [String: Set<CGWindowID>],
        candidateAXWindowIDsByCGWindowID: inout [CGWindowID: Set<String>]
    ) {
        let focusedAXWindows = axWindows.filter {
            $0.isFocused && candidateCGIDsByAXWindowID[$0.id]?.isEmpty == false
        }
        if
            focusedAXWindows.count == 1,
            let focusedAXWindow = focusedAXWindows.first,
            let frontmostCGWindowID = frontmostOnscreenCGWindowID(
                for: focusedAXWindow,
                cgWindows: cgWindows,
                candidateCGIDsByAXWindowID: candidateCGIDsByAXWindowID
            )
        {
            claimPublicStateAssignment(
                state: "focused",
                axWindowID: focusedAXWindow.id,
                cgWindowID: frontmostCGWindowID,
                candidateCGIDsByAXWindowID: &candidateCGIDsByAXWindowID,
                candidateAXWindowIDsByCGWindowID: &candidateAXWindowIDsByCGWindowID
            )
        }

        let mainAXWindows = axWindows.filter {
            $0.isMain && candidateCGIDsByAXWindowID[$0.id]?.isEmpty == false
        }
        if
            mainAXWindows.count == 1,
            let mainAXWindow = mainAXWindows.first,
            let frontmostCGWindowID = frontmostOnscreenCGWindowID(
                for: mainAXWindow,
                cgWindows: cgWindows,
                candidateCGIDsByAXWindowID: candidateCGIDsByAXWindowID
            )
        {
            claimPublicStateAssignment(
                state: "main",
                axWindowID: mainAXWindow.id,
                cgWindowID: frontmostCGWindowID,
                candidateCGIDsByAXWindowID: &candidateCGIDsByAXWindowID,
                candidateAXWindowIDsByCGWindowID: &candidateAXWindowIDsByCGWindowID
            )
        }

        for axWindow in axWindows where axWindow.isMinimized {
            guard let candidateCGWindowIDs = candidateCGIDsByAXWindowID[axWindow.id] else {
                continue
            }
            let offscreenCandidateIDs = cgWindows.compactMap { cgWindow -> CGWindowID? in
                guard candidateCGWindowIDs.contains(cgWindow.id) else { return nil }
                return cgWindow.isOnscreen ? nil : cgWindow.id
            }
            guard offscreenCandidateIDs.count == 1, let offscreenCandidateID = offscreenCandidateIDs.first else {
                continue
            }
            guard candidateAXWindowIDsByCGWindowID[offscreenCandidateID]?.count == 1 else {
                continue
            }
            claimPublicStateAssignment(
                state: "minimized",
                axWindowID: axWindow.id,
                cgWindowID: offscreenCandidateID,
                candidateCGIDsByAXWindowID: &candidateCGIDsByAXWindowID,
                candidateAXWindowIDsByCGWindowID: &candidateAXWindowIDsByCGWindowID
            )
        }
    }

    private static func frontmostOnscreenCGWindowID(
        for axWindow: AXWindowEntry,
        cgWindows: [RuntimeCGWindowEntry],
        candidateCGIDsByAXWindowID: [String: Set<CGWindowID>]
    ) -> CGWindowID? {
        guard let candidateCGWindowIDs = candidateCGIDsByAXWindowID[axWindow.id] else {
            return nil
        }
        return cgWindows.first {
            candidateCGWindowIDs.contains($0.id) && $0.isOnscreen
        }?.id
    }

    private static func claimPublicStateAssignment(
        state: String,
        axWindowID: String,
        cgWindowID: CGWindowID,
        candidateCGIDsByAXWindowID: inout [String: Set<CGWindowID>],
        candidateAXWindowIDsByCGWindowID: inout [CGWindowID: Set<String>]
    ) {
        let axCandidateCount = candidateCGIDsByAXWindowID[axWindowID]?.count ?? 0
        let cgCandidateCount = candidateAXWindowIDsByCGWindowID[cgWindowID]?.count ?? 0
        let resolvesPublicAmbiguity = axCandidateCount > 1 || cgCandidateCount > 1

        candidateCGIDsByAXWindowID[axWindowID] = [cgWindowID]
        candidateAXWindowIDsByCGWindowID[cgWindowID] = [axWindowID]

        for otherAXWindowID in candidateCGIDsByAXWindowID.keys where otherAXWindowID != axWindowID {
            candidateCGIDsByAXWindowID[otherAXWindowID]?.remove(cgWindowID)
        }
        for otherCGWindowID in candidateAXWindowIDsByCGWindowID.keys where otherCGWindowID != cgWindowID {
            candidateAXWindowIDsByCGWindowID[otherCGWindowID]?.remove(axWindowID)
        }

        if resolvesPublicAmbiguity {
            RuntimeLog.debug(
                .axMatch,
                "binding-assignment public-state-tiebreak state=\(state) ax=\(axWindowID) cg=\(cgWindowID) axCandidates=\(axCandidateCount) cgCandidates=\(cgCandidateCount)"
            )
        }
    }

    private static func unresolvedAssignmentDiagnostics(
        remainingCGIDsByAXWindowID: [String: Set<CGWindowID>],
        remainingAXIDsByCGWindowID: [CGWindowID: Set<String>],
        matchedByWindowID: [String: CGWindowID]
    ) -> [WindowBindingDiagnostic] {
        remainingCGIDsByAXWindowID.compactMap { axWindowID, candidateCGWindowIDs in
            guard matchedByWindowID[axWindowID] == nil else { return nil }
            guard !candidateCGWindowIDs.isEmpty else { return nil }
            let candidateCount = candidateCGWindowIDs.count
            let conflictedCGCount = candidateCGWindowIDs.filter {
                (remainingAXIDsByCGWindowID[$0]?.count ?? 0) > 1
            }.count
            let totalCandidateCount = max(candidateCount, conflictedCGCount)
            return WindowBindingDiagnostic(
                stableWindowID: axWindowID,
                axWindowID: axWindowID,
                cgWindowID: candidateCount == 1 ? candidateCGWindowIDs.first : nil,
                confidence: .ambiguous,
                source: nil,
                reason: .publicAssignmentAmbiguous,
                candidateCount: totalCandidateCount,
                allowedActions: WindowBindingConfidence.ambiguous.allowedActions
            )
        }
        .sorted { lhs, rhs in
            lhs.stableWindowID < rhs.stableWindowID
        }
    }

    private static func normalizedMatchingTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func exactCandidateMatch(
        axWindow: AXWindowEntry,
        cgWindow: RuntimeCGWindowEntry,
        appName: String?
    ) -> Bool {
        guard cgWindowPassesValidityConstraints(cgWindow) else { return false }
        guard
            let normalizedAXTitle = exactMatchingTitle(axWindow.sourceTitle ?? axWindow.title, appName: appName),
            let normalizedCGTitle = exactMatchingTitle(cgWindow.title, appName: appName),
            normalizedAXTitle.caseInsensitiveCompare(normalizedCGTitle) == .orderedSame
        else {
            return false
        }
        if let axFrame = axWindow.frame, let cgFrame = cgWindow.bounds {
            return framesApproximatelyMatch(axFrame: axFrame, cgFrame: cgFrame)
        }
        return true
    }

    private static func exactMatchingTitle(_ title: String?, appName: String?) -> String? {
        guard let normalizedTitle = normalizedMatchingTitle(title) else { return nil }
        guard let appName else { return normalizedTitle }
        guard let normalizedAppName = normalizedMatchingTitle(appName) else { return normalizedTitle }
        if normalizedTitle.caseInsensitiveCompare(normalizedAppName) == .orderedSame {
            return nil
        }
        return normalizedTitle
    }

    private static func framesApproximatelyMatch(axFrame: CGRect, cgFrame: CGRect) -> Bool {
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
        return abs(normalizedAXFrame.minX - normalizedCGFrame.minX) <= 24
            && abs(normalizedAXFrame.minY - normalizedCGFrame.minY) <= 24
            && abs(normalizedAXFrame.width - normalizedCGFrame.width) <= 40
            && abs(normalizedAXFrame.height - normalizedCGFrame.height) <= 40
    }
}
