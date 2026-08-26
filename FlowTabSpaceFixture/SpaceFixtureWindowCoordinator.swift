import AppKit
import CoreGraphics
import Darwin
import Foundation

@MainActor
protocol SpaceFixtureWindowing: AnyObject {
    var plan: SpaceFixtureWindowPlan { get }
    var applicationAccessibilityElement: Any { get }
    var currentCGWindowID: CGWindowID { get }
    func show(isKey: Bool)
    func close()
    func postDestroyedAccessibilityNotification()
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
    typealias WindowOpenMutationTriggerObservationFactory =
        (
            SpaceFixtureWindowOpenMutationRoute,
            @escaping @MainActor (
                SpaceFixtureWindowOpenMutationTrigger
            ) -> Void
        ) -> any SpaceFixtureCancellable
    typealias WindowOpenMutationEvidencePublisher =
        (
            SpaceFixtureWindowOpenMutationEvidence,
            SpaceFixtureWindowOpenMutationRoute
        ) -> Void
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
    private let windowOpenMutationTriggerObservationFactory:
        WindowOpenMutationTriggerObservationFactory
    private let windowOpenMutationEvidencePublisher:
        WindowOpenMutationEvidencePublisher

    private(set) var windows: [any SpaceFixtureWindowing] = []
    private var suppressesApplicationAccessibilityElements = false
    private var deferredWindowPlan: SpaceFixtureWindowPlan?
    private var windowOpenMutationTriggerObservation:
        (any SpaceFixtureCancellable)?
    private var windowOpenMutationRequestGeneration = 0
    private var windowMutationNoiseTokens:
        [any SpaceFixtureCancellable] = []
    private var windowMutationNoiseWindows:
        [any SpaceFixtureWindowing] = []

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
            ApplicationIdentityProvider? = nil,
        windowOpenMutationTriggerObservationFactory:
            WindowOpenMutationTriggerObservationFactory? = nil,
        windowOpenMutationEvidencePublisher:
            WindowOpenMutationEvidencePublisher? = nil
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
        self.windowOpenMutationTriggerObservationFactory =
            windowOpenMutationTriggerObservationFactory
            ?? { route, onTrigger in
                SpaceFixtureWindowOpenMutationTriggerObservation(
                    route: route,
                    onTrigger: onTrigger
                )
            }
        self.windowOpenMutationEvidencePublisher =
            windowOpenMutationEvidencePublisher
            ?? { evidence, route in
                SpaceFixtureWindowOpenMutationTransport.publish(
                    evidence,
                    route: route
                )
            }
    }

    func launch() {
        cancelScheduledWork()
        suppressesApplicationAccessibilityElements = false
        let allWindowPlans = SpaceFixtureWindowPlanner.makePlans(
            configuration: configuration,
            visibleFrame: visibleFrameProvider()
        )
        deferredWindowPlan = configuration
            .deferredOpenWindowIndex.flatMap { deferredIndex in
                allWindowPlans.first {
                    $0.index == deferredIndex
                }
            }
        let windowPlans = allWindowPlans.filter {
            $0.index != deferredWindowPlan?.index
        }
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
        startWindowOpenMutationIfNeeded(
            applicationIdentity: applicationIdentity
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
                let targetSnapshot =
                    targetWindow.windowCloseTopologySnapshot(
                    remainingWindowPlanIndices:
                        self?.windows
                            .map(\.plan.index) ?? []
                )
                let currentWindows = self?.windows ?? []
                return SpaceFixtureWindowCloseTopologySnapshot(
                    targetWindowPlanIndex:
                        targetSnapshot.targetWindowPlanIndex,
                    targetWindowNumber:
                        targetSnapshot.targetWindowNumber,
                    targetWindowIsVisible:
                        targetSnapshot.targetWindowIsVisible,
                    targetCGWindowIsOnScreen:
                        targetSnapshot.targetCGWindowIsOnScreen,
                    remainingWindowPlanIndices:
                        targetSnapshot.remainingWindowPlanIndices,
                    remainingWindowTitlesByPlanIndex:
                        self?.configuration
                            .usesChromeLikeWindowMutationNoise == true
                        ? Dictionary(
                            uniqueKeysWithValues:
                                currentWindows.map {
                                    ($0.plan.index, $0.plan.title)
                                }
                        ) : [:],
                    remainingCGWindowIDsByPlanIndex:
                        self?.configuration
                            .usesChromeLikeWindowMutationNoise == true
                        ? Dictionary(
                            uniqueKeysWithValues:
                                currentWindows.compactMap {
                                    let windowID =
                                        $0.currentCGWindowID
                                    guard windowID > 0 else {
                                        return nil
                                    }
                                    return ($0.plan.index, windowID)
                                }
                        ) : [:]
                )
            },
            applyClose: { [weak self, targetWindow] in
                self?.applyWindowClose(targetWindow)
            },
            onWatchdog: { failure in
                NSLog(
                    "SpaceFixture window close watchdog failed: %@",
                    failure.logFields
                )
            }
        )
    }

    private func startWindowOpenMutationIfNeeded(
        applicationIdentity: SpaceFixtureApplicationIdentity
    ) {
        guard let route = configuration.windowOpenMutationRoute,
              let deferredWindowPlan
        else {
            return
        }
        windowOpenMutationRequestGeneration &+= 1
        let requestGeneration =
            windowOpenMutationRequestGeneration
        windowOpenMutationTriggerObservation =
            windowOpenMutationTriggerObservationFactory(
                route
            ) { [weak self] trigger in
                self?.applyWindowOpenMutation(
                    trigger,
                    route: route
                )
            }
        publishWindowOpenMutationEvidence(
            phase: .ready,
            requestGeneration: requestGeneration,
            identity: applicationIdentity,
            targetPlan: deferredWindowPlan,
            route: route
        )
    }

    private func applyWindowOpenMutation(
        _ trigger: SpaceFixtureWindowOpenMutationTrigger,
        route: SpaceFixtureWindowOpenMutationRoute
    ) {
        guard trigger.requestGeneration
                == windowOpenMutationRequestGeneration,
              trigger.identity == applicationIdentityProvider(),
              let deferredWindowPlan,
              trigger.targetWindowPlanIndex
                == deferredWindowPlan.index,
              !windows.contains(where: {
                $0.plan.index == deferredWindowPlan.index
              })
        else {
            return
        }

        windowOpenMutationTriggerObservation?.cancel()
        windowOpenMutationTriggerObservation = nil
        if configuration.usesChromeLikeWindowMutationNoise {
            beginChromeLikeWindowOpenNoise(
                trigger: trigger,
                route: route,
                targetPlan: deferredWindowPlan
            )
            return
        }
        finishWindowOpenMutation(
            trigger: trigger,
            route: route,
            targetPlan: deferredWindowPlan
        )
    }

    private func finishWindowOpenMutation(
        trigger: SpaceFixtureWindowOpenMutationTrigger,
        route: SpaceFixtureWindowOpenMutationRoute,
        targetPlan: SpaceFixtureWindowPlan
    ) {
        guard trigger.requestGeneration
                == windowOpenMutationRequestGeneration,
              deferredWindowPlan?.index == targetPlan.index
        else {
            return
        }
        let openedWindow = windowFactory(targetPlan)
        self.deferredWindowPlan = nil
        windows.append(openedWindow)
        windows.sort { $0.plan.index < $1.plan.index }
        activateApplication()
        openedWindow.show(isKey: true)
        publishApplicationAccessibilityElements()
        publishWindowOpenMutationEvidence(
            phase: .applied,
            requestGeneration: trigger.requestGeneration,
            identity: trigger.identity,
            targetPlan: targetPlan,
            route: route
        )
    }

    private func beginChromeLikeWindowOpenNoise(
        trigger: SpaceFixtureWindowOpenMutationTrigger,
        route: SpaceFixtureWindowOpenMutationRoute,
        targetPlan: SpaceFixtureWindowPlan
    ) {
        let transientPlan = SpaceFixtureWindowPlan(
            index: targetPlan.index + 10_000,
            totalWindowCount: targetPlan.totalWindowCount,
            configuredTitle: "AX Transient",
            fixtureAppName: targetPlan.fixtureAppName,
            title: "\(targetPlan.title) AX Transient",
            frame: targetPlan.frame.offsetBy(dx: 18, dy: -18),
            isFullscreenTarget: false,
            tabs: [],
            noisyCGSiblings: false,
            publishesApplicationAXWindow: true
        )
        let transientWindow = windowFactory(transientPlan)
        windowMutationNoiseWindows = [transientWindow]
        windows.append(transientWindow)
        activateApplication()
        transientWindow.show(isKey: false)
        publishApplicationAccessibilityElements()
        let token = scheduler.schedule(afterMilliseconds: 35) {
            [weak self, weak transientWindow] in
            guard let self, let transientWindow else { return }
            transientWindow.close()
            transientWindow.postDestroyedAccessibilityNotification()
            self.windows.removeAll {
                $0 === transientWindow
            }
            self.windowMutationNoiseWindows.removeAll()
            self.publishApplicationAccessibilityElements()
            self.finishWindowOpenMutation(
                trigger: trigger,
                route: route,
                targetPlan: targetPlan
            )
        }
        windowMutationNoiseTokens.append(token)
    }

    private func applyWindowClose(
        _ targetWindow: any SpaceFixtureWindowing
    ) {
        guard let targetIndex = windows.firstIndex(where: {
            $0 === targetWindow
        }) else {
            return
        }
        guard configuration.usesChromeLikeWindowMutationNoise,
              let retiredSurvivor = windows.first(where: {
                $0.plan.index > targetWindow.plan.index
              })
        else {
            targetWindow.close()
            windows.remove(at: targetIndex)
            publishApplicationAccessibilityElements()
            return
        }

        let survivorPlan = retiredSurvivor.plan
        targetWindow.close()
        windows.removeAll { $0 === targetWindow }
        windows.reverse()
        publishApplicationAccessibilityElements()

        retiredSurvivor.close()
        windows.removeAll { $0 === retiredSurvivor }
        publishApplicationAccessibilityElements()
        targetWindow.postDestroyedAccessibilityNotification()
        targetWindow.postDestroyedAccessibilityNotification()
        retiredSurvivor.postDestroyedAccessibilityNotification()

        let rebuiltSurvivor = windowFactory(survivorPlan)
        windows.insert(rebuiltSurvivor, at: 0)
        activateApplication()
        rebuiltSurvivor.show(isKey: true)
        publishApplicationAccessibilityElements()
    }

    private func publishWindowOpenMutationEvidence(
        phase: SpaceFixtureWindowOpenMutationPhase,
        requestGeneration: Int,
        identity: SpaceFixtureApplicationIdentity,
        targetPlan: SpaceFixtureWindowPlan,
        route: SpaceFixtureWindowOpenMutationRoute
    ) {
        windowOpenMutationEvidencePublisher(
            SpaceFixtureWindowOpenMutationEvidence(
                requestGeneration: requestGeneration,
                phase: phase,
                identity: identity,
                snapshot: SpaceFixtureWindowOpenMutationSnapshot(
                    targetWindowPlanIndex: targetPlan.index,
                    targetWindowTitle: targetPlan.title,
                    activeWindowPlanIndices:
                        windows.map(\.plan.index).sorted(),
                    activeWindowTitlesByPlanIndex:
                        configuration.usesChromeLikeWindowMutationNoise
                        ? Dictionary(
                            uniqueKeysWithValues: windows.map {
                                ($0.plan.index, $0.plan.title)
                            }
                        ) : [:],
                    activeCGWindowIDsByPlanIndex:
                        configuration.usesChromeLikeWindowMutationNoise
                        ? Dictionary(
                            uniqueKeysWithValues:
                                windows.compactMap {
                                    let windowID =
                                        $0.currentCGWindowID
                                    guard windowID > 0 else {
                                        return nil
                                    }
                                    return ($0.plan.index, windowID)
                                }
                        ) : [:]
                )
            ),
            route
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
                windows.count,
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
        windowOpenMutationTriggerObservation?.cancel()
        windowOpenMutationTriggerObservation = nil
        windowMutationNoiseTokens.forEach { $0.cancel() }
        windowMutationNoiseTokens.removeAll()
        windowMutationNoiseWindows.forEach { $0.close() }
        windowMutationNoiseWindows.removeAll()
        deferredWindowPlan = nil
        SpaceFixtureWorkflowReadinessTransport
            .removeReadbackEvidence(
                route:
                    configuration.workflowReadinessRoute
            )
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
