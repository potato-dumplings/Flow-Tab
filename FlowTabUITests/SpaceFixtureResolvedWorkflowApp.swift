import Foundation

extension SpaceFixtureResolvedWorkflow {
    struct App: Equatable {
        let appID: String
        let appName: String
        let identity: SpaceFixtureAppIdentity
        let launchOrder: Int
        let windowCount: Int
        let expectedWindowTitles: [String]
        let expectedContentTitles: [String]
        var expectedHomeWindowTitles: [String] = []
        let visibleFrameWindowIndices: [Int]
        let fullscreenWindowIndices: [Int]
        let fullscreenWindowTitles: [String]

        var fullscreenWindowIndex: Int? {
            fullscreenWindowIndices.first
        }

        init(
            appID: String,
            appName: String,
            identity: SpaceFixtureAppIdentity,
            launchOrder: Int,
            windowCount: Int,
            expectedWindowTitles: [String],
            expectedContentTitles: [String]? = nil,
            expectedHomeWindowTitles: [String] = [],
            visibleFrameWindowIndices: [Int] = [],
            fullscreenWindowIndex: Int?,
            fullscreenWindowIndices: [Int]? = nil,
            fullscreenWindowTitles: [String]? = nil
        ) {
            let resolvedFullscreenWindowIndices =
                fullscreenWindowIndices
                ?? fullscreenWindowIndex.map { [$0] }
                ?? []
            precondition(
                resolvedFullscreenWindowIndices
                    == Array(
                        Set(resolvedFullscreenWindowIndices)
                    ).sorted()
            )
            precondition(
                resolvedFullscreenWindowIndices.allSatisfy {
                    $0 > 0 && $0 <= windowCount
                }
            )
            precondition(
                fullscreenWindowIndex == nil
                    || fullscreenWindowIndex
                        == resolvedFullscreenWindowIndices.first
            )
            precondition(
                visibleFrameWindowIndices
                    == Array(Set(visibleFrameWindowIndices)).sorted()
            )
            precondition(
                visibleFrameWindowIndices.allSatisfy {
                    $0 > 0 && $0 <= windowCount
                }
            )

            self.appID = appID
            self.appName = appName
            self.identity = identity
            self.launchOrder = launchOrder
            self.windowCount = windowCount
            self.expectedWindowTitles = expectedWindowTitles
            self.expectedContentTitles =
                expectedContentTitles ?? expectedWindowTitles
            self.expectedHomeWindowTitles =
                expectedHomeWindowTitles
            self.visibleFrameWindowIndices =
                visibleFrameWindowIndices
            self.fullscreenWindowIndices =
                resolvedFullscreenWindowIndices
            if let fullscreenWindowTitles {
                precondition(
                    fullscreenWindowTitles.count
                        == resolvedFullscreenWindowIndices.count
                )
                self.fullscreenWindowTitles =
                    fullscreenWindowTitles
            } else {
                self.fullscreenWindowTitles =
                    resolvedFullscreenWindowIndices
                        .compactMap {
                            let titleIndex = $0 - 1
                            return expectedWindowTitles.indices
                                .contains(titleIndex)
                                ? expectedWindowTitles[titleIndex]
                                : nil
                        }
            }
        }

        var isFullscreenOnlyInHome: Bool {
            !fullscreenWindowIndices.isEmpty
                && expectedHomeWindowTitles.isEmpty
        }
    }
}
