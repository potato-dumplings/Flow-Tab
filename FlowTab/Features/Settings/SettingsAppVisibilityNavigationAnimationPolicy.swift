import Foundation

struct SettingsAppVisibilityNavigationAnimationPolicy: Equatable {
    let duration: TimeInterval

    static let `default` = SettingsAppVisibilityNavigationAnimationPolicy(
        duration: 0.18
    )
}
