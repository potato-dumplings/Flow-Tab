import Foundation

struct SpaceFixtureLaunchConfiguration: Equatable {
    static let defaultWindowCount = 3
    static let defaultWindowTitlePrefix = "Fixture"
    static let defaultEnterFullscreenDelayMilliseconds = 400
    static let minimumWindowCount = 1

    let windowCount: Int
    let fullscreenWindowIndex: Int?
    let windowTitlePrefix: String
    let usesStaggeredLayout: Bool
    let enterFullscreenDelayMilliseconds: Int

    func title(forWindowIndex index: Int) -> String {
        "\(windowTitlePrefix) \(index)"
    }
}

extension SpaceFixtureLaunchConfiguration {
    init(arguments: [String]) {
        let normalizedWindowCount = max(
            Self.minimumWindowCount,
            Self.intValue(after: "--window-count", in: arguments) ?? Self.defaultWindowCount
        )
        let rawFullscreenWindowIndex = Self.intValue(after: "--fullscreen-window-index", in: arguments)
        let normalizedFullscreenWindowIndex: Int?
        if let rawFullscreenWindowIndex, (1...normalizedWindowCount).contains(rawFullscreenWindowIndex) {
            normalizedFullscreenWindowIndex = rawFullscreenWindowIndex
        } else {
            normalizedFullscreenWindowIndex = nil
        }
        let normalizedWindowTitlePrefix = Self.stringValue(after: "--window-title-prefix", in: arguments)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDelayMilliseconds = max(
            0,
            Self.intValue(after: "--enter-fullscreen-delay-ms", in: arguments)
                ?? Self.defaultEnterFullscreenDelayMilliseconds
        )

        self.init(
            windowCount: normalizedWindowCount,
            fullscreenWindowIndex: normalizedFullscreenWindowIndex,
            windowTitlePrefix: normalizedWindowTitlePrefix?.isEmpty == false
                ? normalizedWindowTitlePrefix!
                : Self.defaultWindowTitlePrefix,
            usesStaggeredLayout: arguments.contains("--staggered-layout"),
            enterFullscreenDelayMilliseconds: normalizedDelayMilliseconds
        )
    }

    private static func stringValue(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let nextIndex = arguments.index(after: index)
        guard nextIndex < arguments.endIndex else { return nil }
        return arguments[nextIndex]
    }

    private static func intValue(after flag: String, in arguments: [String]) -> Int? {
        guard let value = stringValue(after: flag, in: arguments) else { return nil }
        return Int(value)
    }
}
