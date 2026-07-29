import AppKit
import CoreGraphics
import Foundation

@MainActor
protocol SpaceFixtureWindowing: AnyObject {
    var plan: SpaceFixtureWindowPlan { get }
    var applicationAccessibilityElement: Any { get }
    func show(isKey: Bool)
    func close()
    func enterFullScreen(
        completion: @escaping @MainActor () -> Void
    ) -> any SpaceFixtureCancellable
    func desktopPresentationSnapshot()
        -> SpaceFixtureDesktopPresentationSnapshot
    func observeDesktopPresentationChanges(
        _ onChange:
            @escaping @MainActor (
                SpaceFixtureDesktopPresentationEvidenceSource
            ) -> Void
    ) -> any SpaceFixtureCancellable
    func updateWorkflowReadiness(windowTitles: [String])
}

@MainActor
final class SpaceFixtureWindowCoordinator {
    typealias VisibleFrameProvider = () -> CGRect
    typealias WindowFactory = (SpaceFixtureWindowPlan) -> any SpaceFixtureWindowing
    typealias ActivationHandler = () -> Void
    typealias ApplicationAccessibilityElementsPublisher = ([Any]) -> Void

    private static let defaultApplicationAccessibilitySuppressionDelayMilliseconds = 5_000
    private static let fullscreenAccessibilitySuppressionSettleDelayMilliseconds = 8_000
    private static let desktopRefocusWatchdogMilliseconds =
        15_000
    private static let desktopRefocusRetryIntervalMilliseconds =
        100

    private let configuration: SpaceFixtureLaunchConfiguration
    private let visibleFrameProvider: VisibleFrameProvider
    private let windowFactory: WindowFactory
    private let scheduler: any SpaceFixtureScheduling
    private let fullscreenTransitionOwner:
        SpaceFixtureFullscreenTransitionOwner
    private let desktopRefocusOwner:
        SpaceFixtureDesktopRefocusOwner
    private let activateApplication: ActivationHandler
    private let applicationAccessibilityElementsPublisher: ApplicationAccessibilityElementsPublisher

    private(set) var windows: [any SpaceFixtureWindowing] = []
    private var suppressesApplicationAccessibilityElements = false
    private var windowCloseToken: (any SpaceFixtureCancellable)?
    private var accessibilitySuppressionToken:
        (any SpaceFixtureCancellable)?

    var lastDesktopRefocusWatchdogFailure:
        SpaceFixtureDesktopRefocusWatchdogFailure?
    {
        desktopRefocusOwner.lastFailure
    }

    init(
        configuration: SpaceFixtureLaunchConfiguration,
        visibleFrameProvider: VisibleFrameProvider? = nil,
        windowFactory: WindowFactory? = nil,
        scheduler: (any SpaceFixtureScheduling)? = nil,
        activateApplication: ActivationHandler? = nil,
        applicationAccessibilityElementsPublisher: ApplicationAccessibilityElementsPublisher? = nil
    ) {
        let resolvedScheduler = scheduler ?? SpaceFixtureScheduler()
        self.configuration = configuration
        self.visibleFrameProvider = visibleFrameProvider ?? Self.defaultVisibleFrame
        self.windowFactory = windowFactory ?? { AppKitSpaceFixtureWindow(plan: $0) }
        self.scheduler = resolvedScheduler
        fullscreenTransitionOwner =
            SpaceFixtureFullscreenTransitionOwner(
                scheduler: resolvedScheduler
            )
        desktopRefocusOwner =
            SpaceFixtureDesktopRefocusOwner(
                scheduler: resolvedScheduler
            )
        self.activateApplication = activateApplication ?? {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        self.applicationAccessibilityElementsPublisher = applicationAccessibilityElementsPublisher ?? {
            NSApplication.shared.setAccessibilityChildren($0)
            NSApplication.shared.setAccessibilityWindows($0)
        }
    }

    func launch() {
        cancelScheduledWork()
        let windowPlans = SpaceFixtureWindowPlanner.makePlans(
            configuration: configuration,
            visibleFrame: visibleFrameProvider()
        )
        windows = windowPlans.map(windowFactory)
        let windowTitles = windowPlans.map(\.title)

        let deferredPanelWindows = showInitialWindows()
        activateApplication()
        for panelWindow in deferredPanelWindows {
            panelWindow.show(isKey: true)
        }
        windows.forEach { $0.updateWorkflowReadiness(windowTitles: windowTitles) }
        publishApplicationAccessibilityElements()
        scheduleWindowCloseIfNeeded()

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

    private func scheduleWindowCloseIfNeeded() {
        guard let closeWindowIndex = configuration.closeWindowIndex else { return }
        windowCloseToken = scheduler.schedule(
            afterMilliseconds:
                configuration.closeWindowDelayMilliseconds
        ) {
            guard let index = self.windows.firstIndex(where: { $0.plan.index == closeWindowIndex }) else {
                return
            }
            let window = self.windows.remove(at: index)
            window.close()
            self.publishApplicationAccessibilityElements()
        }
    }

    private func showInitialWindows() -> [any SpaceFixtureWindowing] {
        let panelWindows = windows.filter { $0.plan.kind == .panel }
        guard !panelWindows.isEmpty else {
            let keyWindowIndex = configuration.fullscreenWindowIndex ?? 1
            for window in windows where window.plan.index != keyWindowIndex {
                window.show(isKey: false)
            }
            windows.first(where: { $0.plan.index == keyWindowIndex })?.show(isKey: true)
            return []
        }

        let primaryMainWindowIndex = configuration.fullscreenWindowIndex
            ?? windows.first(where: { $0.plan.kind != .panel })?.plan.index
            ?? 1
        for window in windows where window.plan.index != primaryMainWindowIndex && window.plan.kind != .panel {
            window.show(isKey: false)
        }
        windows.first(where: { $0.plan.index == primaryMainWindowIndex })?.show(isKey: true)
        return panelWindows
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

        fullscreenTransitionOwner.start(
            windows: fullscreenWindows,
            initialDelayMilliseconds:
                configuration.enterFullscreenDelayMilliseconds,
            onWillEnter: { [weak self] window, _, totalWindowCount in
                guard let self else { return }
                if totalWindowCount > 1 {
                    self.activateApplication()
                    window.show(isKey: true)
                }
            },
            onDidEnter: { [weak self] _ in
                self?.publishApplicationAccessibilityElements()
            },
            onComplete: { [weak self] _ in
                guard let self else { return }
                self.scheduleDesktopRefocusIfNeeded(
                    desktopAnchorWindow
                )
                self
                    .scheduleApplicationAccessibilitySuppressionAfterFullscreenSettleIfNeeded()
            }
        )
    }

    private func scheduleDesktopRefocusIfNeeded(_ desktopAnchorWindow: (any SpaceFixtureWindowing)?) {
        guard let desktopAnchorWindow else { return }

        desktopRefocusOwner.start(
            window: desktopAnchorWindow,
            watchdogMilliseconds:
                Self.desktopRefocusWatchdogMilliseconds,
            retryIntervalMilliseconds:
                Self.desktopRefocusRetryIntervalMilliseconds,
            trigger: { [weak self] in
                guard let self else { return }
                self.activateApplication()
                desktopAnchorWindow.show(isKey: true)
            },
            onResolved: { [weak self] _ in
                self?.publishApplicationAccessibilityElements()
            },
            onWatchdog: { failure in
                NSLog(
                    "SpaceFixture desktop refocus watchdog failed: %@",
                    failure.logFields
                )
            }
        )
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
        accessibilitySuppressionToken?.cancel()
        accessibilitySuppressionToken = scheduler.schedule(
            afterMilliseconds:
                delayMilliseconds
                ?? applicationAccessibilitySuppressionDelayMilliseconds()
        ) {
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
            configuration.enterFullscreenDelayMilliseconds
                + Self.fullscreenAccessibilitySuppressionSettleDelayMilliseconds
        )
    }

    private func cancelScheduledWork() {
        fullscreenTransitionOwner.cancel()
        desktopRefocusOwner.cancel()
        windowCloseToken?.cancel()
        windowCloseToken = nil
        accessibilitySuppressionToken?.cancel()
        accessibilitySuppressionToken = nil
    }

    private static func defaultVisibleFrame() -> CGRect {
        NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }
}
