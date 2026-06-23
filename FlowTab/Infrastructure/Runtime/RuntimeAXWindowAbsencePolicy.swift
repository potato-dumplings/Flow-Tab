import Foundation

enum RuntimeAXWindowAbsencePolicy {
    static let transientRebuildGraceAXCollectionMissLimit = 3

    static func isAbsenceAuthoritative(
        remoteScanCompleteness: RuntimeAXRemoteWindowResolver.RemoteScanCompleteness?
    ) -> Bool {
        switch remoteScanCompleteness {
        case nil, .some(.complete(_)):
            true
        case .some(.partialTimedOut(_, _)), .some(.unavailable):
            false
        }
    }

    static func consecutiveAXCollectionMissCount(
        hasAXWindowsInCurrentCollection: Bool,
        previousAXCollectionMissCount: Int,
        absenceIsAuthoritative: Bool
    ) -> Int {
        if hasAXWindowsInCurrentCollection {
            return 0
        }
        if absenceIsAuthoritative {
            return previousAXCollectionMissCount + 1
        }
        return previousAXCollectionMissCount
    }

    static func allowsSpaceOneWithoutCurrentAXHandle(
        hasObservedAXWindowHandle: Bool,
        hasAXWindowsInCurrentCollection: Bool,
        absenceIsAuthoritative: Bool,
        consecutiveAXCollectionMissCount: Int
    ) -> Bool {
        hasObservedAXWindowHandle
            && !hasAXWindowsInCurrentCollection
            && (
                !absenceIsAuthoritative
                    || consecutiveAXCollectionMissCount <= transientRebuildGraceAXCollectionMissLimit
            )
    }

    static func isLikelyTransientRebuild(
        hasObservedAXWindowHandle: Bool,
        consecutiveAXCollectionMissCount: Int
    ) -> Bool {
        guard hasObservedAXWindowHandle else { return false }
        return consecutiveAXCollectionMissCount > 0
            && consecutiveAXCollectionMissCount <= transientRebuildGraceAXCollectionMissLimit
    }
}
