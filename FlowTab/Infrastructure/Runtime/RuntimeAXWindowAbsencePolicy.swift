import Foundation

enum RuntimeAXWindowAbsencePolicy {
    static let transientRebuildGraceMissingSnapshotLimit = 3

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

    static func consecutiveMissingSnapshotCount(
        hasAXWindowsInCurrentSnapshot: Bool,
        previousMissingSnapshotCount: Int,
        absenceIsAuthoritative: Bool
    ) -> Int {
        if hasAXWindowsInCurrentSnapshot {
            return 0
        }
        if absenceIsAuthoritative {
            return previousMissingSnapshotCount + 1
        }
        return previousMissingSnapshotCount
    }

    static func allowsSpaceOneWithoutCurrentAXHandle(
        hasObservedAXWindowHandle: Bool,
        hasAXWindowsInCurrentSnapshot: Bool,
        absenceIsAuthoritative: Bool,
        consecutiveMissingSnapshotCount: Int
    ) -> Bool {
        hasObservedAXWindowHandle
            && !hasAXWindowsInCurrentSnapshot
            && (
                !absenceIsAuthoritative
                    || consecutiveMissingSnapshotCount <= transientRebuildGraceMissingSnapshotLimit
            )
    }

    static func isLikelyTransientRebuild(
        hasObservedAXWindowHandle: Bool,
        consecutiveMissingSnapshotCount: Int
    ) -> Bool {
        guard hasObservedAXWindowHandle else { return false }
        return consecutiveMissingSnapshotCount > 0
            && consecutiveMissingSnapshotCount <= transientRebuildGraceMissingSnapshotLimit
    }
}
