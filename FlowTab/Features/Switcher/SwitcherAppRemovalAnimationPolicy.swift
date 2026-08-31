import Foundation

enum SwitcherAppListChange: Equatable {
    case none
    case appRemoval

    static func classify(
        previousAppIDs: [String]?,
        currentAppIDs: [String]
    ) -> SwitcherAppListChange {
        guard let previousAppIDs,
              previousAppIDs.count > currentAppIDs.count,
              Set(previousAppIDs).count == previousAppIDs.count,
              Set(currentAppIDs).count == currentAppIDs.count
        else {
            return .none
        }
        let currentIDSet = Set(currentAppIDs)
        let retainedPreviousIDs = previousAppIDs.filter(
            currentIDSet.contains
        )
        return retainedPreviousIDs == currentAppIDs
            ? .appRemoval
            : .none
    }
}

struct SwitcherAppRemovalAnimationPolicy: Equatable {
    let duration: TimeInterval
    let maximumAnimatedAppCount: Int

    static let `default` = SwitcherAppRemovalAnimationPolicy(
        duration: 0.14,
        maximumAnimatedAppCount: 16
    )

    func animationDuration(appCount: Int) -> TimeInterval? {
        guard appCount >= 0 else { return nil }
        guard appCount <= maximumAnimatedAppCount else { return nil }
        return duration
    }

    func animationDuration(
        appCount: Int,
        listChange: SwitcherAppListChange
    ) -> TimeInterval? {
        guard listChange == .appRemoval else { return nil }
        return animationDuration(appCount: appCount)
    }
}
