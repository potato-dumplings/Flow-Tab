import Foundation

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
}
