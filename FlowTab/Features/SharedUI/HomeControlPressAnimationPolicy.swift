import Foundation

struct HomeControlPressAnimationPolicy: Equatable {
    let duration: TimeInterval

    static let `default` = HomeControlPressAnimationPolicy(duration: 0.12)
}
