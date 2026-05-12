import AppKit
import CoreGraphics
import Foundation

@MainActor
protocol SpaceFixtureWindowing: AnyObject {
    var plan: SpaceFixtureWindowPlan { get }
    var applicationAccessibilityElement: Any { get }
    func show(isKey: Bool)
    func enterFullScreen(completion: @escaping @MainActor () -> Void)
    func updateWorkflowReadiness(windowTitles: [String])
}

@MainActor
final class SpaceFixtureWindowCoordinator {
    typealias VisibleFrameProvider = () -> CGRect
    typealias WindowFactory = (SpaceFixtureWindowPlan) -> any SpaceFixtureWindowing
    typealias FullscreenScheduler = (Int, @escaping @MainActor () -> Void) -> Void
    typealias ActivationHandler = () -> Void
    typealias ApplicationAccessibilityElementsPublisher = ([Any]) -> Void

    private static let defaultApplicationAccessibilitySuppressionDelayMilliseconds = 5_000
    private static let fullscreenAccessibilitySuppressionSettleDelayMilliseconds = 8_000
    private static let desktopRefocusDelayMilliseconds = 1_200
    private static let additionalFullscreenTransitionSpacingMilliseconds = 1_400

    private let configuration: SpaceFixtureLaunchConfiguration
    private let visibleFrameProvider: VisibleFrameProvider
    private let windowFactory: WindowFactory
    private let fullscreenScheduler: FullscreenScheduler
    private let activateApplication: ActivationHandler
    private let applicationAccessibilityElementsPublisher: ApplicationAccessibilityElementsPublisher

    private(set) var windows: [any SpaceFixtureWindowing] = []
    private var suppressesApplicationAccessibilityElements = false

    init(
        configuration: SpaceFixtureLaunchConfiguration,
        visibleFrameProvider: VisibleFrameProvider? = nil,
        windowFactory: WindowFactory? = nil,
        fullscreenScheduler: FullscreenScheduler? = nil,
        activateApplication: ActivationHandler? = nil,
        applicationAccessibilityElementsPublisher: ApplicationAccessibilityElementsPublisher? = nil
    ) {
        self.configuration = configuration
        self.visibleFrameProvider = visibleFrameProvider ?? Self.defaultVisibleFrame
        self.windowFactory = windowFactory ?? { AppKitSpaceFixtureWindow(plan: $0) }
        self.fullscreenScheduler = fullscreenScheduler ?? Self.defaultFullscreenScheduler
        self.activateApplication = activateApplication ?? {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        self.applicationAccessibilityElementsPublisher = applicationAccessibilityElementsPublisher ?? {
            NSApplication.shared.setAccessibilityChildren($0)
            NSApplication.shared.setAccessibilityWindows($0)
        }
    }

    func launch() {
        let windowPlans = SpaceFixtureWindowPlanner.makePlans(
            configuration: configuration,
            visibleFrame: visibleFrameProvider()
        )
        windows = windowPlans.map(windowFactory)
        let windowTitles = windowPlans.map(\.title)

        let keyWindowIndex = configuration.fullscreenWindowIndex ?? 1
        for window in windows where window.plan.index != keyWindowIndex {
            window.show(isKey: false)
        }
        windows.first(where: { $0.plan.index == keyWindowIndex })?.show(isKey: true)

        activateApplication()
        windows.forEach { $0.updateWorkflowReadiness(windowTitles: windowTitles) }
        publishApplicationAccessibilityElements()

        guard !configuration.fullscreenWindowIndices.isEmpty else {
            scheduleApplicationAccessibilitySuppressionIfNeeded()
            return
        }
        let fullscreenWindows = orderedFullscreenWindowsForTransition()
        guard !fullscreenWindows.isEmpty else {
            scheduleApplicationAccessibilitySuppressionIfNeeded()
            return
        }
        scheduleFullscreenTransitions(fullscreenWindows)
    }

    private func orderedFullscreenWindowsForTransition() -> [any SpaceFixtureWindowing] {
        let fullscreenWindows = windows.filter(\.plan.isFullscreenTarget)
        guard
            fullscreenWindows.count > 1,
            let primaryFullscreenIndex = configuration.fullscreenWindowIndex,
            let primaryWindow = fullscreenWindows.first(where: { $0.plan.index == primaryFullscreenIndex })
        else {
            return fullscreenWindows
        }

        return fullscreenWindows.filter { $0.plan.index != primaryFullscreenIndex } + [primaryWindow]
    }

    private func scheduleFullscreenTransitions(_ fullscreenWindows: [any SpaceFixtureWindowing]) {
        let desktopAnchorWindow = configuration.preservesDesktopAfterFullscreen
            ? windows.first(where: { !$0.plan.isFullscreenTarget })
            : nil

        scheduleFullscreenTransition(
            fullscreenWindows,
            currentIndex: 0,
            delayMilliseconds: configuration.enterFullscreenDelayMilliseconds,
            desktopAnchorWindow: desktopAnchorWindow
        )
    }

    private func scheduleFullscreenTransition(
        _ fullscreenWindows: [any SpaceFixtureWindowing],
        currentIndex: Int,
        delayMilliseconds: Int,
        desktopAnchorWindow: (any SpaceFixtureWindowing)?
    ) {
        guard fullscreenWindows.indices.contains(currentIndex) else {
            scheduleDesktopRefocusIfNeeded(desktopAnchorWindow)
            scheduleApplicationAccessibilitySuppressionAfterFullscreenSettleIfNeeded()
            return
        }

        let fullscreenWindow = fullscreenWindows[currentIndex]
        fullscreenScheduler(delayMilliseconds) {
            if fullscreenWindows.count > 1 {
                self.activateApplication()
                fullscreenWindow.show(isKey: true)
            }
            fullscreenWindow.enterFullScreen {
                let nextIndex = currentIndex + 1
                self.publishApplicationAccessibilityElements()
                self.scheduleFullscreenTransition(
                    fullscreenWindows,
                    currentIndex: nextIndex,
                    delayMilliseconds: Self.additionalFullscreenTransitionSpacingMilliseconds,
                    desktopAnchorWindow: desktopAnchorWindow
                )
            }
        }
    }

    private func scheduleDesktopRefocusIfNeeded(_ desktopAnchorWindow: (any SpaceFixtureWindowing)?) {
        guard let desktopAnchorWindow else { return }

        fullscreenScheduler(Self.desktopRefocusDelayMilliseconds) {
            self.activateApplication()
            desktopAnchorWindow.show(isKey: true)
            self.publishApplicationAccessibilityElements()
        }
    }

    private func scheduleApplicationAccessibilitySuppressionAfterFullscreenSettleIfNeeded() {
        guard !configuration.fullscreenWindowIndices.isEmpty else {
            scheduleApplicationAccessibilitySuppressionIfNeeded()
            return
        }
        scheduleApplicationAccessibilitySuppressionIfNeeded(
            delayMilliseconds: Self.fullscreenAccessibilitySuppressionSettleDelayMilliseconds
        )
    }

    private func publishApplicationAccessibilityElements() {
        guard !suppressesApplicationAccessibilityElements else {
            applicationAccessibilityElementsPublisher([])
            return
        }
        applicationAccessibilityElementsPublisher(
            windows
                .filter(\.plan.publishesApplicationAXWindow)
                .map(\.applicationAccessibilityElement)
        )
    }

    private func scheduleApplicationAccessibilitySuppressionIfNeeded(delayMilliseconds: Int? = nil) {
        guard !configuration.publishesApplicationAccessibilityChildren else { return }
        fullscreenScheduler(delayMilliseconds ?? applicationAccessibilitySuppressionDelayMilliseconds()) {
            self.suppressesApplicationAccessibilityElements = true
            self.publishApplicationAccessibilityElements()
        }
    }

    private func applicationAccessibilitySuppressionDelayMilliseconds() -> Int {
        guard !configuration.fullscreenWindowIndices.isEmpty else {
            return Self.defaultApplicationAccessibilitySuppressionDelayMilliseconds
        }
        return max(
            Self.defaultApplicationAccessibilitySuppressionDelayMilliseconds,
            lastFullscreenTransitionDelayMilliseconds()
                + Self.fullscreenAccessibilitySuppressionSettleDelayMilliseconds
        )
    }

    private func lastFullscreenTransitionDelayMilliseconds() -> Int {
        fullscreenTransitionDelayMilliseconds(
            offset: max(0, configuration.fullscreenWindowIndices.count - 1)
        )
    }

    private func fullscreenTransitionDelayMilliseconds(offset: Int) -> Int {
        configuration.enterFullscreenDelayMilliseconds
            + max(0, offset) * Self.additionalFullscreenTransitionSpacingMilliseconds
    }

    private static func defaultVisibleFrame() -> CGRect {
        NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private static func defaultFullscreenScheduler(
        delayMilliseconds: Int,
        action: @escaping @MainActor () -> Void
    ) {
        let deadline = DispatchTime.now() + .milliseconds(max(0, delayMilliseconds))
        DispatchQueue.main.asyncAfter(deadline: deadline) {
            Task { @MainActor in
                action()
            }
        }
    }
}
