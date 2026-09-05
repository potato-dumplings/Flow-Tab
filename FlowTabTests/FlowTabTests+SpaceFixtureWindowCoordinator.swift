import AppKit
import CoreGraphics
import XCTest

@MainActor
final class SpaceFixtureWindowSpy: SpaceFixtureWindowing {
    let plan: SpaceFixtureWindowPlan
    let applicationAccessibilityElement: Any
    let desktopPresentationProbe:
        SpaceFixtureDesktopPresentationProbe
    let currentCGWindowID: CGWindowID

    private(set) var showCalls: [Bool] = []
    private(set) var closeCallCount = 0
    private(set) var createdAccessibilityPostCount = 0
    private(set) var destroyedAccessibilityPostCount = 0
    private(set) var isVisibleForCloseReadback = true
    private(set) var isCGWindowOnScreenForCloseReadback =
        true
    private(set) var enterFullScreenCallCount = 0
    private(set) var enterFullScreenCompletions: [(@MainActor () -> Void)] = []
    private(set) var enterFullScreenTokens:
        [ManualSpaceFixtureCancellable] = []
    private(set) var workflowReadyCalls: [[String]] = []
    private let showRecorder: @MainActor (Int, Bool) -> Void
    private let completesFullScreenImmediately: Bool

    init(
        plan: SpaceFixtureWindowPlan,
        currentCGWindowID: CGWindowID? = nil,
        completesFullScreenImmediately: Bool = false,
        showRecorder:
            @escaping @MainActor (Int, Bool) -> Void = { _, _ in }
    ) {
        self.plan = plan
        self.currentCGWindowID = currentCGWindowID
            ?? CGWindowID(1_000 + plan.index)
        self.applicationAccessibilityElement = "ax-element-\(plan.index)"
        self.desktopPresentationProbe =
            SpaceFixtureDesktopPresentationProbe(
                windowPlanIndex: plan.index
            )
        self.completesFullScreenImmediately =
            completesFullScreenImmediately
        self.showRecorder = showRecorder
    }

    func show(isKey: Bool) {
        showCalls.append(isKey)
        showRecorder(plan.index, isKey)
    }

    func close() {
        closeCallCount += 1
        isVisibleForCloseReadback = false
        isCGWindowOnScreenForCloseReadback = false
    }

    func postCreatedAccessibilityNotification() {
        createdAccessibilityPostCount += 1
    }

    func postDestroyedAccessibilityNotification() {
        destroyedAccessibilityPostCount += 1
    }

    func windowCloseTopologySnapshot(
        remainingWindowPlanIndices: [Int]
    ) -> SpaceFixtureWindowCloseTopologySnapshot {
        SpaceFixtureWindowCloseTopologySnapshot(
            targetWindowPlanIndex: plan.index,
            targetWindowNumber: currentCGWindowID,
            targetWindowIsVisible:
                isVisibleForCloseReadback,
            targetCGWindowIsOnScreen:
                isCGWindowOnScreenForCloseReadback,
            remainingWindowPlanIndices:
                remainingWindowPlanIndices.sorted()
        )
    }

    func enterFullScreen(
        completion: @escaping @MainActor () -> Void
    ) -> any SpaceFixtureCancellable {
        enterFullScreenCallCount += 1
        enterFullScreenCompletions.append(completion)
        let token = ManualSpaceFixtureCancellable()
        enterFullScreenTokens.append(token)
        if completesFullScreenImmediately {
            completion()
        }
        return token
    }

    func desktopPresentationSnapshot()
        -> SpaceFixtureDesktopPresentationSnapshot
    {
        desktopPresentationProbe.snapshot
    }

    func observeDesktopPresentationChanges(
        _ onChange:
            @escaping @MainActor (
                SpaceFixtureDesktopPresentationEvidenceSource
            ) -> Void
    ) -> any SpaceFixtureCancellable {
        desktopPresentationProbe.observe(onChange)
    }

    func updateWorkflowReadiness(windowTitles: [String]) {
        workflowReadyCalls.append(windowTitles)
    }

    @discardableResult
    func completeFullScreenTransition(
        at index: Int = 0,
        includingCancelled: Bool = false
    ) -> Bool {
        let completion = enterFullScreenCompletions.remove(at: index)
        let token = enterFullScreenTokens.remove(at: index)
        guard includingCancelled || !token.isCancelled else {
            return false
        }
        completion()
        return true
    }
}

extension FlowTabTests {
    @MainActor
    func testAppKitSpaceFixtureWindowDisablesStateRestoration() {
        let plan = SpaceFixtureWindowPlan(
            index: 1,
            totalWindowCount: 1,
            configuredTitle: "Chrome Window",
            fixtureAppName: "Chrome Fixture",
            title: "Mail",
            frame: CGRect(x: 20, y: 30, width: 960, height: 640),
            isFullscreenTarget: true,
            tabs: [],
            noisyCGSiblings: false
        )

        let fixtureWindow = AppKitSpaceFixtureWindow(plan: plan)
        let window = fixtureWindow.applicationAccessibilityElement as? NSWindow

        XCTAssertNotNil(window)
        XCTAssertFalse(window?.isRestorable ?? true)
    }

    @MainActor
    func testSpaceFixtureWindowCoordinatorLaunchesWindowsAndSchedulesFullscreenTarget() {
        let configuration = SpaceFixtureLaunchConfiguration(
            windowCount: 3,
            fullscreenWindowIndex: 2,
            windowTitlePrefix: "Fixture",
            usesStaggeredLayout: true,
            enterFullscreenDelayMilliseconds: 1200,
            preservesDesktopAfterFullscreen: true
        )

        var windowSpies: [SpaceFixtureWindowSpy] = []
        let scheduler = ManualSpaceFixtureScheduler()
        var activationCallCount = 0
        var publishedAccessibilityElements: [[String]] = []

        let coordinator = SpaceFixtureWindowCoordinator(
            configuration: configuration,
            visibleFrameProvider: { CGRect(x: 0, y: 0, width: 1440, height: 900) },
            windowFactory: { plan in
                let spy = SpaceFixtureWindowSpy(plan: plan)
                windowSpies.append(spy)
                return spy
            },
            scheduler: scheduler,
            activateApplication: {
                activationCallCount += 1
            },
            applicationAccessibilityElementsPublisher: { elements in
                publishedAccessibilityElements.append(elements.compactMap { $0 as? String })
            }
        )

        coordinator.launch()

        XCTAssertEqual(windowSpies.count, 3)
        XCTAssertEqual(windowSpies.map(\.plan.title), ["Fixture 1", "Fixture 2", "Fixture 3"])
        XCTAssertEqual(windowSpies[0].showCalls, [false])
        XCTAssertEqual(windowSpies[1].showCalls, [true])
        XCTAssertEqual(windowSpies[2].showCalls, [false])
        XCTAssertTrue(windowSpies[0].workflowReadyCalls.isEmpty)
        XCTAssertTrue(windowSpies[1].workflowReadyCalls.isEmpty)
        XCTAssertTrue(windowSpies[2].workflowReadyCalls.isEmpty)
        XCTAssertEqual(activationCallCount, 1)
        XCTAssertEqual(scheduler.scheduledDelays, [1200])
        XCTAssertEqual(publishedAccessibilityElements, [["ax-element-1", "ax-element-2", "ax-element-3"]])

        XCTAssertTrue(scheduler.fire(at: 0))

        XCTAssertEqual(windowSpies[1].enterFullScreenCallCount, 1)
        XCTAssertEqual(windowSpies[0].enterFullScreenCallCount, 0)
        XCTAssertEqual(windowSpies[2].enterFullScreenCallCount, 0)
        XCTAssertEqual(scheduler.scheduledDelays, [1200])
        XCTAssertEqual(
            publishedAccessibilityElements,
            [
                ["ax-element-1", "ax-element-2", "ax-element-3"]
            ]
        )

        windowSpies[1].completeFullScreenTransition()

        XCTAssertTrue(windowSpies[0].workflowReadyCalls.isEmpty)
        XCTAssertTrue(windowSpies[1].workflowReadyCalls.isEmpty)
        XCTAssertTrue(windowSpies[2].workflowReadyCalls.isEmpty)
        XCTAssertEqual(
            scheduler.scheduledDelays,
            [1200, 15_000, 100]
        )
        XCTAssertEqual(windowSpies[0].showCalls, [false, true])
        XCTAssertEqual(windowSpies[1].showCalls, [true])
        XCTAssertEqual(windowSpies[2].showCalls, [false])
        XCTAssertEqual(activationCallCount, 2)
        XCTAssertEqual(
            publishedAccessibilityElements,
            [
                ["ax-element-1", "ax-element-2", "ax-element-3"],
                ["ax-element-1", "ax-element-2", "ax-element-3"]
            ]
        )

        windowSpies[0].desktopPresentationProbe.snapshot =
            SpaceFixtureDesktopPresentationProbe.presentedSnapshot(
                windowPlanIndex: 1
            )
        windowSpies[0].desktopPresentationProbe.emit(
            .activeSpaceDidChange
        )

        XCTAssertEqual(windowSpies[0].workflowReadyCalls, [["Fixture 1", "Fixture 2", "Fixture 3"]])
        XCTAssertEqual(windowSpies[1].workflowReadyCalls, [["Fixture 1", "Fixture 2", "Fixture 3"]])
        XCTAssertEqual(windowSpies[2].workflowReadyCalls, [["Fixture 1", "Fixture 2", "Fixture 3"]])
        XCTAssertEqual(
            coordinator.lastWorkflowReadinessEvidence?
                .stage,
            .ready
        )
        XCTAssertEqual(windowSpies[0].showCalls, [false, true])
        XCTAssertEqual(windowSpies[1].showCalls, [true])
        XCTAssertEqual(windowSpies[2].showCalls, [false])
        XCTAssertEqual(activationCallCount, 2)
        XCTAssertEqual(
            publishedAccessibilityElements,
            [
                ["ax-element-1", "ax-element-2", "ax-element-3"],
                ["ax-element-1", "ax-element-2", "ax-element-3"],
                ["ax-element-1", "ax-element-2", "ax-element-3"]
            ]
        )
        XCTAssertFalse(scheduler.fire(at: 1))
        XCTAssertFalse(scheduler.fire(at: 2))
        XCTAssertNil(
            coordinator.lastDesktopRefocusWatchdogFailure
        )
    }

    @MainActor
    func testSpaceFixtureWindowCoordinatorLeavesFullscreenFocusUntouchedWhenDesktopPreservationDisabled() {
        let configuration = SpaceFixtureLaunchConfiguration(
            windowCount: 3,
            fullscreenWindowIndex: 2,
            windowTitlePrefix: "Fixture",
            usesStaggeredLayout: true,
            enterFullscreenDelayMilliseconds: 800,
            preservesDesktopAfterFullscreen: false
        )

        var windowSpies: [SpaceFixtureWindowSpy] = []
        let scheduler = ManualSpaceFixtureScheduler()
        var activationCallCount = 0
        var publishedAccessibilityElements: [[String]] = []

        let coordinator = SpaceFixtureWindowCoordinator(
            configuration: configuration,
            visibleFrameProvider: { CGRect(x: 0, y: 0, width: 1440, height: 900) },
            windowFactory: { plan in
                let spy = SpaceFixtureWindowSpy(plan: plan)
                windowSpies.append(spy)
                return spy
            },
            scheduler: scheduler,
            activateApplication: {
                activationCallCount += 1
            },
            applicationAccessibilityElementsPublisher: { elements in
                publishedAccessibilityElements.append(elements.compactMap { $0 as? String })
            }
        )

        coordinator.launch()

        XCTAssertEqual(windowSpies.count, 3)
        XCTAssertEqual(windowSpies[0].showCalls, [false])
        XCTAssertEqual(windowSpies[1].showCalls, [true])
        XCTAssertEqual(windowSpies[2].showCalls, [false])
        XCTAssertEqual(activationCallCount, 1)
        XCTAssertEqual(scheduler.scheduledDelays, [800])
        XCTAssertTrue(windowSpies[0].workflowReadyCalls.isEmpty)
        XCTAssertTrue(windowSpies[1].workflowReadyCalls.isEmpty)
        XCTAssertTrue(windowSpies[2].workflowReadyCalls.isEmpty)

        XCTAssertTrue(scheduler.fire(at: 0))

        XCTAssertEqual(windowSpies[1].enterFullScreenCallCount, 1)
        XCTAssertEqual(windowSpies[0].showCalls, [false])
        XCTAssertEqual(windowSpies[1].showCalls, [true])
        XCTAssertEqual(windowSpies[2].showCalls, [false])
        XCTAssertEqual(activationCallCount, 1)
        XCTAssertEqual(
            publishedAccessibilityElements,
            [
                ["ax-element-1", "ax-element-2", "ax-element-3"]
            ]
        )

        windowSpies[1].completeFullScreenTransition()

        XCTAssertEqual(windowSpies[0].workflowReadyCalls, [["Fixture 1", "Fixture 2", "Fixture 3"]])
        XCTAssertEqual(windowSpies[1].workflowReadyCalls, [["Fixture 1", "Fixture 2", "Fixture 3"]])
        XCTAssertEqual(windowSpies[2].workflowReadyCalls, [["Fixture 1", "Fixture 2", "Fixture 3"]])
        XCTAssertEqual(
            publishedAccessibilityElements,
            [
                ["ax-element-1", "ax-element-2", "ax-element-3"],
                ["ax-element-1", "ax-element-2", "ax-element-3"]
            ]
        )
    }

    @MainActor
    func testSpaceFixtureWindowCoordinatorSkipsFullscreenSchedulingWhenNoTargetConfigured() {
        let configuration = SpaceFixtureLaunchConfiguration(
            windowCount: 2,
            fullscreenWindowIndex: nil,
            windowTitlePrefix: "Fixture",
            usesStaggeredLayout: false,
            enterFullscreenDelayMilliseconds: 500,
            preservesDesktopAfterFullscreen: false
        )

        var windowSpies: [SpaceFixtureWindowSpy] = []
        let scheduler = ManualSpaceFixtureScheduler()

        let coordinator = SpaceFixtureWindowCoordinator(
            configuration: configuration,
            visibleFrameProvider: { CGRect(x: 0, y: 0, width: 1280, height: 800) },
            windowFactory: { plan in
                let spy = SpaceFixtureWindowSpy(plan: plan)
                windowSpies.append(spy)
                return spy
            },
            scheduler: scheduler
        )

        coordinator.launch()

        XCTAssertEqual(windowSpies.count, 2)
        XCTAssertEqual(windowSpies[0].showCalls, [true])
        XCTAssertEqual(windowSpies[1].showCalls, [false])
        XCTAssertEqual(windowSpies[0].workflowReadyCalls, [["Fixture 1", "Fixture 2"]])
        XCTAssertEqual(windowSpies[1].workflowReadyCalls, [["Fixture 1", "Fixture 2"]])
        XCTAssertEqual(scheduler.scheduledCount, 0)
    }

    @MainActor
    func testSpaceFixtureWindowCoordinatorLaunchesPanelAfterMainDocumentWindow() {
        let configuration = SpaceFixtureLaunchConfiguration(
            windows: [
                SpaceFixtureConfiguredWindow(
                    configuredTitle: "Document",
                    windowTitle: "Shared Docs",
                    mode: .standard,
                    tabs: []
                ),
                SpaceFixtureConfiguredWindow(
                    configuredTitle: "Inspector",
                    windowTitle: "Shared Docs",
                    mode: .standard,
                    tabs: [],
                    kind: .panel
                ),
                SpaceFixtureConfiguredWindow(
                    configuredTitle: "Reference",
                    windowTitle: "Reference",
                    mode: .standard,
                    tabs: []
                )
            ],
            windowTitlePrefix: SpaceFixtureLaunchConfiguration.defaultWindowTitlePrefix,
            usesStaggeredLayout: false,
            enterFullscreenDelayMilliseconds: 0,
            preservesDesktopAfterFullscreen: false
        )

        var windowSpies: [SpaceFixtureWindowSpy] = []
        var showEvents: [(Int, Bool)] = []
        var launchEvents: [String] = []
        let scheduler = ManualSpaceFixtureScheduler()
        var publishedAccessibilityElements: [[String]] = []

        let coordinator = SpaceFixtureWindowCoordinator(
            configuration: configuration,
            visibleFrameProvider: { CGRect(x: 0, y: 0, width: 1440, height: 900) },
            windowFactory: { plan in
                let spy = SpaceFixtureWindowSpy(plan: plan) { index, isKey in
                    showEvents.append((index, isKey))
                    launchEvents.append("show:\(index):\(isKey)")
                }
                windowSpies.append(spy)
                return spy
            },
            scheduler: scheduler,
            activateApplication: {
                launchEvents.append("activate")
            },
            applicationAccessibilityElementsPublisher: { elements in
                publishedAccessibilityElements.append(elements.compactMap { $0 as? String })
            }
        )

        coordinator.launch()

        XCTAssertEqual(windowSpies.map(\.plan.kind), [.standard, .panel, .standard])
        XCTAssertEqual(windowSpies.map(\.plan.title), ["Shared Docs", "Shared Docs", "Reference"])
        XCTAssertEqual(windowSpies.map(\.showCalls), [[true], [true], [false]])
        XCTAssertEqual(showEvents.map { "\($0.0):\($0.1)" }, ["3:false", "1:true", "2:true"])
        XCTAssertEqual(launchEvents, ["show:3:false", "show:1:true", "activate", "show:2:true"])
        XCTAssertEqual(windowSpies[0].workflowReadyCalls, [["Shared Docs", "Shared Docs", "Reference"]])
        XCTAssertEqual(windowSpies[1].workflowReadyCalls, [["Shared Docs", "Shared Docs", "Reference"]])
        XCTAssertEqual(windowSpies[2].workflowReadyCalls, [["Shared Docs", "Shared Docs", "Reference"]])
        XCTAssertEqual(publishedAccessibilityElements, [["ax-element-1", "ax-element-2", "ax-element-3"]])
        XCTAssertEqual(scheduler.scheduledCount, 0)
    }

    @MainActor
    func testSpaceFixtureWindowCoordinatorSchedulesConfiguredWindowClose() {
        let configuration = SpaceFixtureLaunchConfiguration(
            windowCount: 2,
            fullscreenWindowIndex: nil,
            windowTitlePrefix: "Fixture",
            usesStaggeredLayout: false,
            enterFullscreenDelayMilliseconds: 500,
            preservesDesktopAfterFullscreen: false,
            closeWindowIndex: 2,
            closeWindowDelayMilliseconds: 1_300
        )

        var windowSpies: [SpaceFixtureWindowSpy] = []
        let scheduler = ManualSpaceFixtureScheduler()
        var publishedAccessibilityElements: [[String]] = []

        let coordinator = SpaceFixtureWindowCoordinator(
            configuration: configuration,
            visibleFrameProvider: { CGRect(x: 0, y: 0, width: 1280, height: 800) },
            windowFactory: { plan in
                let spy = SpaceFixtureWindowSpy(plan: plan)
                windowSpies.append(spy)
                return spy
            },
            scheduler: scheduler,
            applicationAccessibilityElementsPublisher: { elements in
                publishedAccessibilityElements.append(elements.compactMap { $0 as? String })
            }
        )

        coordinator.launch()

        XCTAssertEqual(windowSpies.count, 2)
        XCTAssertEqual(scheduler.scheduledDelays, [1_300])
        XCTAssertEqual(publishedAccessibilityElements, [["ax-element-1", "ax-element-2"]])
        XCTAssertEqual(
            coordinator.lastWindowCloseFaultEvidence,
            SpaceFixtureWindowCloseFaultEvidence(
                requestGeneration: 1,
                phase: .scheduled,
                source: .initialReadback,
                delayMilliseconds: 1_300,
                awaitsExplicitTrigger: false,
                identity: SpaceFixtureWindowCloseFaultIdentity(
                    bundleIdentifier:
                        Bundle.main.bundleIdentifier
                        ?? ProcessInfo.processInfo
                            .processName,
                    processIdentifier: getpid()
                ),
                snapshot:
                    SpaceFixtureWindowCloseTopologySnapshot(
                        targetWindowPlanIndex: 2,
                        targetWindowNumber: 1_002,
                        targetWindowIsVisible: true,
                        targetCGWindowIsOnScreen: true,
                        remainingWindowPlanIndices: [1, 2]
                    )
            )
        )

        XCTAssertTrue(scheduler.fire(at: 0))

        XCTAssertEqual(windowSpies[0].closeCallCount, 0)
        XCTAssertEqual(windowSpies[1].closeCallCount, 1)
        XCTAssertEqual(publishedAccessibilityElements, [["ax-element-1", "ax-element-2"], ["ax-element-1"]])
        XCTAssertEqual(
            coordinator.lastWindowCloseFaultEvidence?
                .phase,
            .applied
        )
        XCTAssertEqual(
            coordinator.lastWindowCloseFaultEvidence?
                .snapshot,
            SpaceFixtureWindowCloseTopologySnapshot(
                targetWindowPlanIndex: 2,
                targetWindowNumber: 1_002,
                targetWindowIsVisible: false,
                targetCGWindowIsOnScreen: false,
                remainingWindowPlanIndices: [1]
            )
        )
        XCTAssertNil(
            coordinator
                .lastWindowCloseFaultWatchdogFailure
        )
    }

    @MainActor
    func testSpaceFixtureWindowCoordinatorPublishesResolvedWorkflowWindowTitles() {
        let configuration = SpaceFixtureLaunchConfiguration(
            windows: [
                SpaceFixtureConfiguredWindow(
                    configuredTitle: "Chrome Window 1",
                    windowTitle: "Docs",
                    mode: .standard,
                    tabs: [
                        SpaceFixtureConfiguredTab(title: "Docs", identifier: "tab-1", isSelected: true),
                        SpaceFixtureConfiguredTab(title: "PR", identifier: "tab-2", isSelected: false)
                    ]
                ),
                SpaceFixtureConfiguredWindow(
                    configuredTitle: "Chrome Window 2",
                    windowTitle: "Mail",
                    mode: .fullscreen,
                    tabs: [
                        SpaceFixtureConfiguredTab(title: "Mail", identifier: "tab-1", isSelected: true),
                        SpaceFixtureConfiguredTab(title: "Calendar", identifier: "tab-2", isSelected: false)
                    ]
                )
            ],
            windowTitlePrefix: SpaceFixtureLaunchConfiguration.defaultWindowTitlePrefix,
            usesStaggeredLayout: true,
            enterFullscreenDelayMilliseconds: 750,
            preservesDesktopAfterFullscreen: false,
            workflowName: "multi-app-space-topology",
            workflowAppID: "chrome"
        )

        var windowSpies: [SpaceFixtureWindowSpy] = []
        let scheduler = ManualSpaceFixtureScheduler()

        let coordinator = SpaceFixtureWindowCoordinator(
            configuration: configuration,
            visibleFrameProvider: { CGRect(x: 0, y: 0, width: 1440, height: 900) },
            windowFactory: { plan in
                let spy = SpaceFixtureWindowSpy(plan: plan)
                windowSpies.append(spy)
                return spy
            },
            scheduler: scheduler
        )

        coordinator.launch()

        XCTAssertEqual(windowSpies.count, 2)
        XCTAssertEqual(windowSpies[0].plan.title, "Docs")
        XCTAssertEqual(windowSpies[0].plan.subtitleText, "Chrome Window 1")
        XCTAssertEqual(windowSpies[1].plan.title, "Mail")
        XCTAssertTrue(windowSpies[0].workflowReadyCalls.isEmpty)
        XCTAssertTrue(windowSpies[1].workflowReadyCalls.isEmpty)
        XCTAssertTrue(scheduler.fire(at: 0))
        XCTAssertTrue(
            windowSpies[1]
                .completeFullScreenTransition()
        )
        XCTAssertEqual(windowSpies[0].workflowReadyCalls, [["Docs", "Mail"]])
        XCTAssertEqual(windowSpies[1].workflowReadyCalls, [["Docs", "Mail"]])
    }

    @MainActor
    func testSpaceFixtureWindowCoordinatorDefersAndAcknowledgesWindowOpenMutation() {
        let route = SpaceFixtureWindowOpenMutationRoute(
            evidenceNotificationName:
                Notification.Name("test.window-open.evidence"),
            triggerNotificationName:
                Notification.Name("test.window-open.trigger")
        )
        let identity = SpaceFixtureApplicationIdentity(
            bundleIdentifier: "test.fixture",
            processIdentifier: 4_321
        )
        let configuration = SpaceFixtureLaunchConfiguration(
            windowCount: 2,
            fullscreenWindowIndex: nil,
            windowTitlePrefix: "Mutation",
            usesStaggeredLayout: true,
            enterFullscreenDelayMilliseconds: 0,
            preservesDesktopAfterFullscreen: false,
            windowOpenMutationRoute: route,
            deferredOpenWindowIndex: 2
        )
        var windowSpies: [SpaceFixtureWindowSpy] = []
        var publishedAccessibilityElements: [[String]] = []
        var observedEvidence:
            [SpaceFixtureWindowOpenMutationEvidence] = []
        var triggerHandler:
            (@MainActor (
                SpaceFixtureWindowOpenMutationTrigger
            ) -> Void)?
        let triggerToken = ManualSpaceFixtureCancellable()

        let coordinator = SpaceFixtureWindowCoordinator(
            configuration: configuration,
            visibleFrameProvider: {
                CGRect(x: 0, y: 0, width: 1440, height: 900)
            },
            windowFactory: { plan in
                let spy = SpaceFixtureWindowSpy(plan: plan)
                windowSpies.append(spy)
                return spy
            },
            applicationAccessibilityElementsPublisher: { elements in
                publishedAccessibilityElements.append(
                    elements.compactMap { $0 as? String }
                )
            },
            applicationIdentityProvider: { identity },
            windowOpenMutationTriggerObservationFactory: {
                observedRoute,
                onTrigger in
                XCTAssertEqual(observedRoute, route)
                triggerHandler = onTrigger
                return triggerToken
            },
            windowOpenMutationEvidencePublisher: {
                evidence,
                observedRoute in
                XCTAssertEqual(observedRoute, route)
                observedEvidence.append(evidence)
            }
        )

        coordinator.launch()

        XCTAssertEqual(windowSpies.map(\.plan.index), [1])
        XCTAssertEqual(coordinator.windows.map(\.plan.index), [1])
        XCTAssertEqual(
            publishedAccessibilityElements.last,
            ["ax-element-1"]
        )
        XCTAssertEqual(
            observedEvidence,
            [
                SpaceFixtureWindowOpenMutationEvidence(
                    requestGeneration: 1,
                    phase: .ready,
                    identity: identity,
                    snapshot:
                        SpaceFixtureWindowOpenMutationSnapshot(
                            targetWindowPlanIndex: 2,
                            targetWindowTitle: "Mutation 2",
                            activeWindowPlanIndices: [1]
                        )
                )
            ]
        )

        triggerHandler?(
            SpaceFixtureWindowOpenMutationTrigger(
                requestGeneration: 1,
                identity: identity,
                targetWindowPlanIndex: 2
            )
        )

        XCTAssertEqual(windowSpies.map(\.plan.index), [1, 2])
        XCTAssertEqual(coordinator.windows.map(\.plan.index), [1, 2])
        XCTAssertEqual(windowSpies[1].showCalls, [true])
        XCTAssertEqual(
            publishedAccessibilityElements.last,
            ["ax-element-1", "ax-element-2"]
        )
        XCTAssertEqual(observedEvidence.map(\.phase), [.ready, .applied])
        XCTAssertEqual(
            observedEvidence.last?.snapshot.activeWindowPlanIndices,
            [1, 2]
        )
        XCTAssertTrue(triggerToken.isCancelled)

        triggerHandler?(
            SpaceFixtureWindowOpenMutationTrigger(
                requestGeneration: 1,
                identity: identity,
                targetWindowPlanIndex: 2
            )
        )
        XCTAssertEqual(windowSpies.count, 2)
        XCTAssertEqual(observedEvidence.count, 2)
    }

    @MainActor
    func testSpaceFixtureWindowCoordinatorChromeLikeOpenNoisePublishesFinalThreeWindowReceipt() {
        let route = SpaceFixtureWindowOpenMutationRoute(
            evidenceNotificationName:
                Notification.Name("test.noisy-window-open.evidence"),
            triggerNotificationName:
                Notification.Name("test.noisy-window-open.trigger")
        )
        let identity = SpaceFixtureApplicationIdentity(
            bundleIdentifier: "test.noisy-open.fixture",
            processIdentifier: 4_331
        )
        let configuration = SpaceFixtureLaunchConfiguration(
            windowCount: 3,
            fullscreenWindowIndex: nil,
            windowTitlePrefix: "Noisy Open",
            usesStaggeredLayout: true,
            enterFullscreenDelayMilliseconds: 0,
            preservesDesktopAfterFullscreen: false,
            windowOpenMutationRoute: route,
            deferredOpenWindowIndex: 3,
            usesChromeLikeWindowMutationNoise: true
        )
        let scheduler = ManualSpaceFixtureScheduler()
        var nextCGWindowID: CGWindowID = 2_100
        var windowSpies: [SpaceFixtureWindowSpy] = []
        var observedEvidence:
            [SpaceFixtureWindowOpenMutationEvidence] = []
        var triggerHandler:
            (@MainActor (SpaceFixtureWindowOpenMutationTrigger) -> Void)?

        let coordinator = SpaceFixtureWindowCoordinator(
            configuration: configuration,
            visibleFrameProvider: {
                CGRect(x: 0, y: 0, width: 1440, height: 900)
            },
            windowFactory: { plan in
                defer { nextCGWindowID += 1 }
                let spy = SpaceFixtureWindowSpy(
                    plan: plan,
                    currentCGWindowID: nextCGWindowID
                )
                windowSpies.append(spy)
                return spy
            },
            scheduler: scheduler,
            applicationIdentityProvider: { identity },
            windowOpenMutationTriggerObservationFactory: {
                _, onTrigger in
                triggerHandler = onTrigger
                return ManualSpaceFixtureCancellable()
            },
            windowOpenMutationEvidencePublisher: {
                evidence, _ in observedEvidence.append(evidence)
            }
        )

        coordinator.launch()
        XCTAssertEqual(
            observedEvidence.first?.snapshot
                .activeWindowTitlesByPlanIndex,
            [1: "Noisy Open 1", 2: "Noisy Open 2"]
        )
        XCTAssertEqual(
            observedEvidence.first?.snapshot
                .activeCGWindowIDsByPlanIndex,
            [1: 2_100, 2: 2_101]
        )

        triggerHandler?(
            SpaceFixtureWindowOpenMutationTrigger(
                requestGeneration: 1,
                identity: identity,
                targetWindowPlanIndex: 3
            )
        )
        XCTAssertEqual(
            coordinator.windows.map(\.plan.index),
            [1, 2, 10_003]
        )
        XCTAssertEqual(scheduler.scheduledDelays, [35])
        XCTAssertEqual(observedEvidence.map(\.phase), [.ready])

        XCTAssertTrue(scheduler.fire(at: 0))
        XCTAssertEqual(coordinator.windows.map(\.plan.index), [1, 2, 3])
        XCTAssertEqual(windowSpies[2].closeCallCount, 1)
        XCTAssertEqual(
            windowSpies[2].destroyedAccessibilityPostCount,
            1
        )
        XCTAssertEqual(observedEvidence.map(\.phase), [.ready, .applied])
        XCTAssertEqual(
            observedEvidence.last?.snapshot
                .activeWindowTitlesByPlanIndex,
            [
                1: "Noisy Open 1",
                2: "Noisy Open 2",
                3: "Noisy Open 3"
            ]
        )
        XCTAssertEqual(
            observedEvidence.last?.snapshot
                .activeCGWindowIDsByPlanIndex,
            [1: 2_100, 2: 2_101, 3: 2_103]
        )
    }

    @MainActor
    func testSpaceFixtureWindowCoordinatorChromeLikeCloseNoiseRebuildsSurvivorAndRepeatsDestroyed() {
        let configuration = SpaceFixtureLaunchConfiguration(
            windowCount: 3,
            fullscreenWindowIndex: nil,
            windowTitlePrefix: "Noisy Close",
            usesStaggeredLayout: true,
            enterFullscreenDelayMilliseconds: 0,
            preservesDesktopAfterFullscreen: false,
            closeWindowIndex: 2,
            closeWindowDelayMilliseconds: 0,
            usesChromeLikeWindowMutationNoise: true
        )
        let scheduler = ManualSpaceFixtureScheduler()
        var nextCGWindowID: CGWindowID = 3_100
        var windowSpies: [SpaceFixtureWindowSpy] = []

        let coordinator = SpaceFixtureWindowCoordinator(
            configuration: configuration,
            visibleFrameProvider: {
                CGRect(x: 0, y: 0, width: 1440, height: 900)
            },
            windowFactory: { plan in
                defer { nextCGWindowID += 1 }
                let spy = SpaceFixtureWindowSpy(
                    plan: plan,
                    currentCGWindowID: nextCGWindowID
                )
                windowSpies.append(spy)
                return spy
            },
            scheduler: scheduler
        )

        coordinator.launch()
        XCTAssertEqual(
            coordinator.lastWindowCloseFaultEvidence?.snapshot
                .remainingCGWindowIDsByPlanIndex,
            [1: 3_100, 2: 3_101, 3: 3_102]
        )
        XCTAssertTrue(scheduler.fire(at: 0))

        XCTAssertEqual(coordinator.windows.map(\.plan.index), [3, 1])
        XCTAssertEqual(windowSpies.map(\.plan.index), [1, 2, 3, 3])
        XCTAssertEqual(windowSpies[1].destroyedAccessibilityPostCount, 2)
        XCTAssertEqual(windowSpies[2].destroyedAccessibilityPostCount, 1)
        XCTAssertEqual(
            coordinator.lastWindowCloseFaultEvidence?.snapshot
                .remainingWindowTitlesByPlanIndex,
            [1: "Noisy Close 1", 3: "Noisy Close 3"]
        )
        XCTAssertEqual(
            coordinator.lastWindowCloseFaultEvidence?.snapshot
                .remainingCGWindowIDsByPlanIndex,
            [1: 3_100, 3: 3_103]
        )
        XCTAssertFalse(
            coordinator.lastWindowCloseFaultEvidence?.snapshot
                .remainingCGWindowIDsByPlanIndex.values
                .contains(3_101) ?? true
        )
    }
}

@MainActor
final class ManualSpaceFixtureScheduler: SpaceFixtureScheduling {
    private struct ScheduledAction {
        let delayMilliseconds: Int
        let token: ManualSpaceFixtureCancellable
        let action: @MainActor @Sendable () -> Void
    }

    private var scheduled: [ScheduledAction] = []

    var scheduledDelays: [Int] {
        scheduled.map(\.delayMilliseconds)
    }

    var scheduledCount: Int {
        scheduled.count
    }

    func schedule(
        afterMilliseconds delayMilliseconds: Int,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> any SpaceFixtureCancellable {
        let token = ManualSpaceFixtureCancellable()
        scheduled.append(
            ScheduledAction(
                delayMilliseconds: delayMilliseconds,
                token: token,
                action: action
            )
        )
        return token
    }

    func token(at index: Int) -> ManualSpaceFixtureCancellable {
        scheduled[index].token
    }

    @discardableResult
    func fire(
        at index: Int,
        includingCancelled: Bool = false
    ) -> Bool {
        guard scheduled.indices.contains(index) else { return false }
        let item = scheduled[index]
        guard !item.token.didFire else { return false }
        guard includingCancelled || !item.token.isCancelled else {
            return false
        }
        item.token.didFire = true
        item.action()
        return true
    }
}

@MainActor
final class ManualSpaceFixtureCancellable: SpaceFixtureCancellable {
    private(set) var isCancelled = false
    var didFire = false

    func cancel() {
        isCancelled = true
    }
}
