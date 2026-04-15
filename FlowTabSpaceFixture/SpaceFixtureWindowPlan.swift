import CoreGraphics

enum SpaceFixtureWorkflowStatus {
    static let readyAccessibilityIdentifier = "flowtab.spacefixture.workflow.ready"
    static let summaryAccessibilityIdentifier = "flowtab.spacefixture.workflow.summary"
    static let launchingText = "Launching"
    static let readyText = "Ready"

    static func summaryText(for windowTitles: [String]) -> String {
        windowTitles.joined(separator: " | ")
    }
}

struct SpaceFixtureWindowPlan: Equatable {
    let index: Int
    let totalWindowCount: Int
    let title: String
    let frame: CGRect
    let isFullscreenTarget: Bool

    var rootAccessibilityIdentifier: String {
        "flowtab.spacefixture.window.root.\(index)"
    }

    var titleAccessibilityIdentifier: String {
        "flowtab.spacefixture.window.title.\(index)"
    }

    var subtitleAccessibilityIdentifier: String {
        "flowtab.spacefixture.window.subtitle.\(index)"
    }

    var modeAccessibilityIdentifier: String {
        "flowtab.spacefixture.window.mode.\(index)"
    }

    var windowAccessibilityIdentifier: String {
        "flowtab.spacefixture.window.\(index)"
    }

    var subtitleText: String {
        "Window \(index) of \(totalWindowCount)"
    }

    var modeText: String {
        isFullscreenTarget ? "Fullscreen Target" : "Standard Window"
    }
}

enum SpaceFixtureWindowPlanner {
    private static let defaultWindowSize = CGSize(width: 960, height: 640)
    private static let staggerStep = CGSize(width: 36, height: 32)

    static func makePlans(
        configuration: SpaceFixtureLaunchConfiguration,
        visibleFrame: CGRect
    ) -> [SpaceFixtureWindowPlan] {
        let baseOrigin = centeredOrigin(
            visibleFrame: visibleFrame,
            windowSize: defaultWindowSize
        )

        return (1...configuration.windowCount).map { index in
            let offsetMultiplier = configuration.usesStaggeredLayout ? CGFloat(index - 1) : 0
            let origin = CGPoint(
                x: clamped(
                    value: baseOrigin.x + staggerStep.width * offsetMultiplier,
                    lowerBound: visibleFrame.minX,
                    upperBound: visibleFrame.maxX - defaultWindowSize.width
                ),
                y: clamped(
                    value: baseOrigin.y - staggerStep.height * offsetMultiplier,
                    lowerBound: visibleFrame.minY,
                    upperBound: visibleFrame.maxY - defaultWindowSize.height
                )
            )

            return SpaceFixtureWindowPlan(
                index: index,
                totalWindowCount: configuration.windowCount,
                title: configuration.title(forWindowIndex: index),
                frame: CGRect(origin: origin, size: defaultWindowSize),
                isFullscreenTarget: configuration.fullscreenWindowIndex == index
            )
        }
    }

    private static func centeredOrigin(
        visibleFrame: CGRect,
        windowSize: CGSize
    ) -> CGPoint {
        CGPoint(
            x: visibleFrame.midX - (windowSize.width / 2),
            y: visibleFrame.midY - (windowSize.height / 2)
        )
    }

    private static func clamped(
        value: CGFloat,
        lowerBound: CGFloat,
        upperBound: CGFloat
    ) -> CGFloat {
        max(lowerBound, min(value, upperBound))
    }
}
