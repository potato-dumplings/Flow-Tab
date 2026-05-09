import AppKit
import CoreGraphics
import Foundation

@MainActor
protocol SpaceFixtureWindowing: AnyObject {
    var plan: SpaceFixtureWindowPlan { get }
    var applicationAccessibilityElement: Any { get }
    func show(isKey: Bool)
    func enterFullScreen()
    func updateWorkflowReadiness(windowTitles: [String])
}

@MainActor
final class SpaceFixtureWindowCoordinator {
    typealias VisibleFrameProvider = () -> CGRect
    typealias WindowFactory = (SpaceFixtureWindowPlan) -> any SpaceFixtureWindowing
    typealias FullscreenScheduler = (Int, @escaping @MainActor () -> Void) -> Void
    typealias ActivationHandler = () -> Void
    typealias ApplicationAccessibilityElementsPublisher = ([Any]) -> Void

    private static let desktopRefocusDelayMilliseconds = 1_200

    private let configuration: SpaceFixtureLaunchConfiguration
    private let visibleFrameProvider: VisibleFrameProvider
    private let windowFactory: WindowFactory
    private let fullscreenScheduler: FullscreenScheduler
    private let activateApplication: ActivationHandler
    private let applicationAccessibilityElementsPublisher: ApplicationAccessibilityElementsPublisher

    private(set) var windows: [any SpaceFixtureWindowing] = []

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

        guard let fullscreenWindowIndex = configuration.fullscreenWindowIndex else { return }
        guard let fullscreenWindow = windows.first(where: { $0.plan.index == fullscreenWindowIndex }) else {
            return
        }
        let desktopAnchorWindow = configuration.preservesDesktopAfterFullscreen
            ? windows.first(where: { $0.plan.index != fullscreenWindowIndex })
            : nil

        fullscreenScheduler(configuration.enterFullscreenDelayMilliseconds) {
            fullscreenWindow.enterFullScreen()
            self.publishApplicationAccessibilityElements()

            guard let desktopAnchorWindow else { return }
            // Keep the post-launch topology anchored on the normal desktop so
            // runtime sampling can still observe the app's non-fullscreen windows.
            self.fullscreenScheduler(Self.desktopRefocusDelayMilliseconds) {
                self.activateApplication()
                desktopAnchorWindow.show(isKey: true)
                self.publishApplicationAccessibilityElements()
            }
        }
    }

    private func publishApplicationAccessibilityElements() {
        guard configuration.publishesApplicationAccessibilityChildren else {
            applicationAccessibilityElementsPublisher([])
            return
        }
        applicationAccessibilityElementsPublisher(windows.map(\.applicationAccessibilityElement))
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
