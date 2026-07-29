import AppKit
import CoreGraphics
import Darwin
import Foundation

@MainActor
protocol SpaceFixtureWindowing: AnyObject {
    var plan: SpaceFixtureWindowPlan { get }
    var applicationAccessibilityElement: Any { get }
    func show(isKey: Bool)
    func close()
    func windowCloseTopologySnapshot(
        remainingWindowPlanIndices: [Int]
    ) -> SpaceFixtureWindowCloseTopologySnapshot
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
    typealias ApplicationIdentityProvider =
        () -> SpaceFixtureApplicationIdentity
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
    private let applicationAXSuppressionOwner:
        SpaceFixtureApplicationAXSuppressionOwner
    private let windowCloseFaultOwner:
        SpaceFixtureWindowCloseFaultOwner
    private let workflowReadinessOwner:
        SpaceFixtureWorkflowReadinessOwner
    private let activateApplication: ActivationHandler
    private let applicationAccessibilityElementsPublisher: ApplicationAccessibilityElementsPublisher
    private let applicationIdentityProvider:
        ApplicationIdentityProvider

    private(set) var windows: [any SpaceFixtureWindowing] = []
    private var suppressesApplicationAccessibilityElements = false

    var lastDesktopRefocusWatchdogFailure:
        SpaceFixtureDesktopRefocusWatchdogFailure?
    {
        desktopRefocusOwner.lastFailure
    }

    var lastApplicationAXSuppressionWatchdogFailure:
        SpaceFixtureApplicationAXSuppressionWatchdogFailure?
    {
        applicationAXSuppressionOwner.lastFailure
    }

    var lastWindowCloseFaultEvidence:
        SpaceFixtureWindowCloseFaultEvidence?
    {
        windowCloseFaultOwner.lastEvidence
    }

    var lastWindowCloseFaultWatchdogFailure:
        SpaceFixtureWindowCloseFaultWatchdogFailure?
    {
        windowCloseFaultOwner.lastFailure
    }

    var lastWorkflowReadinessEvidence:
        SpaceFixtureWorkflowReadinessEvidence?
    {
        workflowReadinessOwner.lastEvidence
    }

    init(
        configuration: SpaceFixtureLaunchConfiguration,
        visibleFrameProvider: VisibleFrameProvider? = nil,
        windowFactory: WindowFactory? = nil,
        scheduler: (any SpaceFixtureScheduling)? = nil,
        activateApplication: ActivationHandler? = nil,
        applicationAccessibilityElementsPublisher: ApplicationAccessibilityElementsPublisher? = nil,
        applicationAXSuppressionOwner:
            SpaceFixtureApplicationAXSuppressionOwner? = nil,
        windowCloseFaultOwner:
            SpaceFixtureWindowCloseFaultOwner? = nil,
        workflowReadinessOwner:
            SpaceFixtureWorkflowReadinessOwner? = nil,
        applicationIdentityProvider:
            ApplicationIdentityProvider? = nil
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
        self.applicationAXSuppressionOwner =
            applicationAXSuppressionOwner
            ?? SpaceFixtureApplicationAXSuppressionOwner(
                scheduler: resolvedScheduler,
                exposureProvider: {
                    Self.applicationAccessibilityExposure()
                }
            )
        self.windowCloseFaultOwner =
            windowCloseFaultOwner
            ?? SpaceFixtureWindowCloseFaultOwner(
                scheduler: resolvedScheduler,
                evidencePublisher: { evidence in
                    SpaceFixtureWindowCloseFaultEvidenceTransport
                        .publish(
                            evidence,
                            route:
                                configuration
                                    .windowCloseFaultEvidenceRoute
                        )
                }
            )
        self.workflowReadinessOwner =
            workflowReadinessOwner
            ?? SpaceFixtureWorkflowReadinessOwner(
                evidencePublisher: { evidence in
                    SpaceFixtureWorkflowReadinessTransport
                        .publish(
                            evidence,
                            route:
                                configuration
                                    .workflowReadinessRoute
                        )
                }
            )
        self.activateApplication = activateApplication ?? {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        self.applicationAccessibilityElementsPublisher = applicationAccessibilityElementsPublisher ?? {
            NSApplication.shared.setAccessibilityChildren($0)
            NSApplication.shared.setAccessibilityWindows($0)
        }
        self.applicationIdentityProvider =
            applicationIdentityProvider ?? {
                SpaceFixtureApplicationIdentity(
                    bundleIdentifier:
                        Bundle.main.bundleIdentifier
                        ?? ProcessInfo.processInfo.processName,
                    processIdentifier: getpid()
                )
            }
    }

    func launch() {
        cancelScheduledWork()
        suppressesApplicationAccessibilityElements = false
        let windowPlans = SpaceFixtureWindowPlanner.makePlans(
            configuration: configuration,
            visibleFrame: visibleFrameProvider()
        )
        windows = windowPlans.map(windowFactory)
        let fullscreenWindows =
            orderedFullscreenWindowsForTransition()
        let desktopAnchorWindow =
            desktopAnchorWindow(
                for: fullscreenWindows
            )
        let applicationIdentity =
            applicationIdentityProvider()
        let readinessGeneration =
            startWorkflowReadiness(
                windowPlans: windowPlans,
                fullscreenWindows: fullscreenWindows,
                desktopAnchorWindow:
                    desktopAnchorWindow,
                applicationIdentity:
                    applicationIdentity
            )
        prepareApplicationAXSuppressionIfNeeded(
            readinessGeneration:
                readinessGeneration,
            applicationIdentity:
                applicationIdentity
        )

        let deferredPanelWindows = showInitialWindows()
        activateApplication()
        for panelWindow in deferredPanelWindows {
            panelWindow.show(isKey: true)
        }
        publishApplicationAccessibilityElements()
        workflowReadinessOwner
            .windowTopologyDidResolve(
                planIndices:
                    windows.map(\.plan.index),
                observationGeneration:
                    readinessGeneration
            )
        startWindowCloseFaultIfNeeded(
            applicationIdentity: applicationIdentity
        )

        guard !configuration.fullscreenWindowIndices.isEmpty else {
            applicationAXSuppressionOwner
                .localTopologyStageDidResolve()
            return
        }
        guard !fullscreenWindows.isEmpty else {
            applicationAXSuppressionOwner
                .localTopologyStageDidResolve()
            return
        }
        scheduleFullscreenTransitions(
            fullscreenWindows,
            desktopAnchorWindow:
                desktopAnchorWindow,
            readinessGeneration:
                readinessGeneration
        )
    }

    func cancel() {
        cancelScheduledWork()
    }

    private func startWorkflowReadiness(
        windowPlans: [SpaceFixtureWindowPlan],
        fullscreenWindows:
            [any SpaceFixtureWindowing],
        desktopAnchorWindow:
            (any SpaceFixtureWindowing)?,
        applicationIdentity:
            SpaceFixtureApplicationIdentity
    ) -> Int {
        workflowReadinessOwner.start(
            expectation:
                SpaceFixtureWorkflowReadinessExpectation(
                    identity:
                        SpaceFixtureWorkflowReadinessIdentity(
                            bundleIdentifier:
                                applicationIdentity
                                    .bundleIdentifier,
                            processIdentifier:
                                applicationIdentity
                                    .processIdentifier
                        ),
                    windowPlanIndices:
                        windowPlans.map(\.index),
                    fullscreenWindowPlanIndices:
                        fullscreenWindows
                            .map(\.plan.index)
                            .sorted(),
                    desktopAnchorWindowPlanIndex:
                        desktopAnchorWindow?
                            .plan.index,
                    requiresApplicationAXSuppression:
                        !configuration
                            .publishesApplicationAccessibilityChildren,
                    windowTitles:
                        windowPlans.map(\.title)
                ),
            onReady: { [weak self] evidence in
                guard let self else { return }
                self.windows.forEach {
                    $0.updateWorkflowReadiness(
                        windowTitles:
                            evidence.snapshot.windowTitles
                    )
                }
            }
        )
    }

    private func startWindowCloseFaultIfNeeded(
        applicationIdentity:
            SpaceFixtureApplicationIdentity
    ) {
        guard let closeWindowIndex =
                configuration.closeWindowIndex,
              let policy =
                SpaceFixtureWindowCloseFaultPolicy(
                    targetWindowPlanIndex:
                        closeWindowIndex,
                    delayMilliseconds:
                        configuration
                            .closeWindowDelayMilliseconds
                ),
              let targetWindow =
                windows.first(where: {
                    $0.plan.index == closeWindowIndex
                })
        else {
            return
        }
        windowCloseFaultOwner.start(
            policy: policy,
            identity:
                SpaceFixtureWindowCloseFaultIdentity(
                    bundleIdentifier:
                        applicationIdentity
                            .bundleIdentifier,
                    processIdentifier:
                        applicationIdentity
                            .processIdentifier
                ),
            triggerRoute:
                configuration
                    .windowCloseFaultTriggerRoute,
            snapshotProvider: { [weak self, targetWindow] in
                targetWindow.windowCloseTopologySnapshot(
                    remainingWindowPlanIndices:
                        self?.windows
                            .map(\.plan.index) ?? []
                )
            },
            applyClose: { [weak self, targetWindow] in
                guard let self,
                      let index = self.windows.firstIndex(
                        where: {
                            $0.plan.index
                                == targetWindow.plan.index
                        }
                      )
                else {
                    return
                }
                targetWindow.close()
                self.windows.remove(at: index)
                self.publishApplicationAccessibilityElements()
            },
            onWatchdog: { failure in
                NSLog(
                    "SpaceFixture window close watchdog failed: %@",
                    failure.logFields
                )
            }
        )
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

    private func desktopAnchorWindow(
        for fullscreenWindows:
            [any SpaceFixtureWindowing]
    ) -> (any SpaceFixtureWindowing)? {
        guard configuration
                .preservesDesktopAfterFullscreen,
              !fullscreenWindows.isEmpty
        else {
            return nil
        }
        return windows.first {
            !$0.plan.isFullscreenTarget
        }
    }

    private func scheduleFullscreenTransitions(
        _ fullscreenWindows:
            [any SpaceFixtureWindowing],
        desktopAnchorWindow:
            (any SpaceFixtureWindowing)?,
        readinessGeneration: Int
    ) {
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
            onComplete: { [weak self] completion in
                guard let self else { return }
                self.workflowReadinessOwner
                    .fullscreenTopologyDidResolve(
                        completion,
                        observationGeneration:
                            readinessGeneration
                    )
                self.resolveApplicationAXSuppressionTopology(
                    desktopAnchorWindow,
                    readinessGeneration:
                        readinessGeneration
                )
            }
        )
    }

    private func resolveApplicationAXSuppressionTopology(
        _ desktopAnchorWindow:
            (any SpaceFixtureWindowing)?,
        readinessGeneration: Int
    ) {
        guard let desktopAnchorWindow else {
            applicationAXSuppressionOwner
                .localTopologyStageDidResolve()
            return
        }

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
            onResolved: { [weak self] evidence in
                guard let self else { return }
                self.publishApplicationAccessibilityElements()
                self.workflowReadinessOwner
                    .desktopPresentationDidResolve(
                        evidence,
                        observationGeneration:
                            readinessGeneration
                    )
                self.applicationAXSuppressionOwner
                    .localTopologyStageDidResolve()
            },
            onWatchdog: { failure in
                NSLog(
                    "SpaceFixture desktop refocus watchdog failed: %@",
                    failure.logFields
                )
            }
        )
    }

    private func prepareApplicationAXSuppressionIfNeeded(
        readinessGeneration: Int,
        applicationIdentity:
            SpaceFixtureApplicationIdentity
    ) {
        guard
            !configuration
                .publishesApplicationAccessibilityChildren
        else {
            return
        }
        applicationAXSuppressionOwner.start(
            route: configuration.applicationAXSuppressionRoute,
            identity: applicationIdentity,
            expectedProjectionWindowCount:
                configuration.windowCount,
            expectedPublishedAXWindowCount:
                windows.filter(
                    \.plan.publishesApplicationAXWindow
                ).count,
            suppress: { [weak self] in
                guard let self else { return }
                self.suppressesApplicationAccessibilityElements =
                    true
                self.publishApplicationAccessibilityElements()
            },
            onResolved: { [weak self] exposure in
                self?.workflowReadinessOwner
                    .applicationAXExposureDidResolve(
                        exposure,
                        observationGeneration:
                            readinessGeneration
                    )
            }
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

    private func cancelScheduledWork() {
        fullscreenTransitionOwner.cancel()
        desktopRefocusOwner.cancel()
        applicationAXSuppressionOwner.cancel()
        windowCloseFaultOwner.cancel()
        workflowReadinessOwner.cancel()
    }

    private static func applicationAccessibilityExposure()
        -> SpaceFixtureApplicationAXExposure
    {
        SpaceFixtureApplicationAXExposure(
            childWindowCount:
                NSApplication.shared
                    .accessibilityChildren()?.count ?? 0,
            windowsAttributeCount:
                NSApplication.shared
                    .accessibilityWindows()?.count ?? 0
        )
    }

    private static func defaultVisibleFrame() -> CGRect {
        NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }
}
