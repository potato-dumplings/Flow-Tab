import AppKit
import CoreGraphics
import XCTest

@MainActor
private final class SpaceFixtureWindowSpy: SpaceFixtureWindowing {
    let plan: SpaceFixtureWindowPlan
    let applicationAccessibilityElement: Any

    private(set) var showCalls: [Bool] = []
    private(set) var enterFullScreenCallCount = 0
    private(set) var workflowReadyCalls: [[String]] = []

    init(plan: SpaceFixtureWindowPlan) {
        self.plan = plan
        self.applicationAccessibilityElement = "ax-element-\(plan.index)"
    }

    func show(isKey: Bool) {
        showCalls.append(isKey)
    }

    func enterFullScreen() {
        enterFullScreenCallCount += 1
    }

    func updateWorkflowReadiness(windowTitles: [String]) {
        workflowReadyCalls.append(windowTitles)
    }
}

extension FlowTabTests {
    @MainActor
    func testAppKitSpaceFixtureWindowDisablesStateRestoration() {
        let plan = SpaceFixtureWindowPlan(
            index: 1,
            totalWindowCount: 1,
            configuredTitle: "Chrome Window",
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
        var scheduledDelays: [Int] = []
        var scheduledActions: [(@MainActor () -> Void)] = []
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
            fullscreenScheduler: { delay, action in
                scheduledDelays.append(delay)
                scheduledActions.append(action)
            },
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
        XCTAssertEqual(windowSpies[0].workflowReadyCalls, [["Fixture 1", "Fixture 2", "Fixture 3"]])
        XCTAssertEqual(windowSpies[1].workflowReadyCalls, [["Fixture 1", "Fixture 2", "Fixture 3"]])
        XCTAssertEqual(windowSpies[2].workflowReadyCalls, [["Fixture 1", "Fixture 2", "Fixture 3"]])
        XCTAssertEqual(activationCallCount, 1)
        XCTAssertEqual(scheduledDelays, [1200])
        XCTAssertEqual(publishedAccessibilityElements, [["ax-element-1", "ax-element-2", "ax-element-3"]])

        scheduledActions[0]()

        XCTAssertEqual(windowSpies[1].enterFullScreenCallCount, 1)
        XCTAssertEqual(windowSpies[0].enterFullScreenCallCount, 0)
        XCTAssertEqual(windowSpies[2].enterFullScreenCallCount, 0)
        XCTAssertEqual(scheduledDelays, [1200, 1200])
        XCTAssertEqual(
            publishedAccessibilityElements,
            [
                ["ax-element-1", "ax-element-2", "ax-element-3"],
                ["ax-element-1", "ax-element-2", "ax-element-3"]
            ]
        )

        scheduledActions[1]()

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
        var scheduledDelays: [Int] = []
        var scheduledActions: [(@MainActor () -> Void)] = []
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
            fullscreenScheduler: { delay, action in
                scheduledDelays.append(delay)
                scheduledActions.append(action)
            },
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
        XCTAssertEqual(scheduledDelays, [800])

        scheduledActions[0]()

        XCTAssertEqual(windowSpies[1].enterFullScreenCallCount, 1)
        XCTAssertEqual(windowSpies[0].showCalls, [false])
        XCTAssertEqual(windowSpies[1].showCalls, [true])
        XCTAssertEqual(windowSpies[2].showCalls, [false])
        XCTAssertEqual(activationCallCount, 1)
        XCTAssertEqual(
            publishedAccessibilityElements,
            [
                ["ax-element-1", "ax-element-2", "ax-element-3"],
                ["ax-element-1", "ax-element-2", "ax-element-3"]
            ]
        )
    }

    @MainActor
    func testSpaceFixtureWindowCoordinatorSchedulesMultipleFullscreenTargetsAndSuppressesAfterLastTransition() {
        let configuration = SpaceFixtureLaunchConfiguration(
            windows: [
                SpaceFixtureConfiguredWindow(
                    configuredTitle: "Chrome Window 1",
                    windowTitle: "Normal Tab",
                    mode: .standard,
                    tabs: []
                ),
                SpaceFixtureConfiguredWindow(
                    configuredTitle: "Chrome Window 2",
                    windowTitle: "Fullscreen Tab",
                    mode: .fullscreen,
                    tabs: []
                ),
                SpaceFixtureConfiguredWindow(
                    configuredTitle: "Chrome Window 3",
                    windowTitle: "Second Fullscreen Tab",
                    mode: .fullscreen,
                    tabs: []
                )
            ],
            windowTitlePrefix: SpaceFixtureLaunchConfiguration.defaultWindowTitlePrefix,
            usesStaggeredLayout: true,
            enterFullscreenDelayMilliseconds: 1_000,
            preservesDesktopAfterFullscreen: false,
            publishesApplicationAccessibilityChildren: false
        )

        var windowSpies: [SpaceFixtureWindowSpy] = []
        var scheduledDelays: [Int] = []
        var scheduledActions: [(@MainActor () -> Void)] = []
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
            fullscreenScheduler: { delay, action in
                scheduledDelays.append(delay)
                scheduledActions.append(action)
            },
            activateApplication: {
                activationCallCount += 1
            },
            applicationAccessibilityElementsPublisher: { elements in
                publishedAccessibilityElements.append(elements.compactMap { $0 as? String })
            }
        )

        coordinator.launch()

        XCTAssertEqual(windowSpies.map(\.showCalls), [[false], [true], [false]])
        XCTAssertEqual(scheduledDelays, [1_000, 2_400, 10_400])
        XCTAssertEqual(publishedAccessibilityElements, [["ax-element-1", "ax-element-2", "ax-element-3"]])
        XCTAssertEqual(activationCallCount, 1)

        scheduledActions[0]()

        XCTAssertEqual(windowSpies[2].showCalls, [false, true])
        XCTAssertEqual(windowSpies[2].enterFullScreenCallCount, 1)
        XCTAssertEqual(windowSpies[1].enterFullScreenCallCount, 0)
        XCTAssertEqual(activationCallCount, 2)

        scheduledActions[1]()

        XCTAssertEqual(windowSpies[1].showCalls, [true, true])
        XCTAssertEqual(windowSpies[1].enterFullScreenCallCount, 1)
        XCTAssertEqual(activationCallCount, 3)
        XCTAssertEqual(publishedAccessibilityElements, [
            ["ax-element-1", "ax-element-2", "ax-element-3"],
            ["ax-element-1", "ax-element-2", "ax-element-3"],
            ["ax-element-1", "ax-element-2", "ax-element-3"]
        ])

        scheduledActions[2]()

        XCTAssertEqual(publishedAccessibilityElements, [
            ["ax-element-1", "ax-element-2", "ax-element-3"],
            ["ax-element-1", "ax-element-2", "ax-element-3"],
            ["ax-element-1", "ax-element-2", "ax-element-3"],
            []
        ])
    }

    @MainActor
    func testSpaceFixtureWindowCoordinatorDelaysAccessibilitySuppressionUntilAfterFullscreenTransition() {
        let configuration = SpaceFixtureLaunchConfiguration(
            windowCount: 2,
            fullscreenWindowIndex: 2,
            windowTitlePrefix: "Fixture",
            usesStaggeredLayout: true,
            enterFullscreenDelayMilliseconds: 4_000,
            preservesDesktopAfterFullscreen: false,
            publishesApplicationAccessibilityChildren: false
        )

        var windowSpies: [SpaceFixtureWindowSpy] = []
        var scheduledDelays: [Int] = []
        var scheduledActions: [(@MainActor () -> Void)] = []
        var publishedAccessibilityElements: [[String]] = []

        let coordinator = SpaceFixtureWindowCoordinator(
            configuration: configuration,
            visibleFrameProvider: { CGRect(x: 0, y: 0, width: 1280, height: 800) },
            windowFactory: { plan in
                let spy = SpaceFixtureWindowSpy(plan: plan)
                windowSpies.append(spy)
                return spy
            },
            fullscreenScheduler: { delay, action in
                scheduledDelays.append(delay)
                scheduledActions.append(action)
            },
            applicationAccessibilityElementsPublisher: { elements in
                publishedAccessibilityElements.append(elements.compactMap { $0 as? String })
            }
        )

        coordinator.launch()

        XCTAssertEqual(scheduledDelays, [4_000, 12_000])
        XCTAssertEqual(publishedAccessibilityElements, [["ax-element-1", "ax-element-2"]])

        scheduledActions[0]()

        XCTAssertEqual(windowSpies[1].enterFullScreenCallCount, 1)
        XCTAssertEqual(publishedAccessibilityElements, [
            ["ax-element-1", "ax-element-2"],
            ["ax-element-1", "ax-element-2"]
        ])

        scheduledActions[1]()

        XCTAssertEqual(publishedAccessibilityElements, [
            ["ax-element-1", "ax-element-2"],
            ["ax-element-1", "ax-element-2"],
            []
        ])
    }

    @MainActor
    func testSpaceFixtureWindowCoordinatorSuppressesApplicationAccessibilityChildrenWhenConfigured() {
        let configuration = SpaceFixtureLaunchConfiguration(
            windowCount: 2,
            fullscreenWindowIndex: nil,
            windowTitlePrefix: "Fixture",
            usesStaggeredLayout: false,
            enterFullscreenDelayMilliseconds: 500,
            preservesDesktopAfterFullscreen: false,
            publishesApplicationAccessibilityChildren: false
        )

        var windowSpies: [SpaceFixtureWindowSpy] = []
        var scheduledDelays: [Int] = []
        var scheduledActions: [(@MainActor () -> Void)] = []
        var publishedAccessibilityElements: [[String]] = []

        let coordinator = SpaceFixtureWindowCoordinator(
            configuration: configuration,
            visibleFrameProvider: { CGRect(x: 0, y: 0, width: 1280, height: 800) },
            windowFactory: { plan in
                let spy = SpaceFixtureWindowSpy(plan: plan)
                windowSpies.append(spy)
                return spy
            },
            fullscreenScheduler: { delay, action in
                scheduledDelays.append(delay)
                scheduledActions.append(action)
            },
            applicationAccessibilityElementsPublisher: { elements in
                publishedAccessibilityElements.append(elements.compactMap { $0 as? String })
            }
        )

        coordinator.launch()

        XCTAssertEqual(windowSpies.count, 2)
        XCTAssertEqual(publishedAccessibilityElements, [["ax-element-1", "ax-element-2"]])
        XCTAssertEqual(scheduledDelays, [5000])

        scheduledActions[0]()

        XCTAssertEqual(publishedAccessibilityElements, [["ax-element-1", "ax-element-2"], []])
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
        var scheduledCallCount = 0

        let coordinator = SpaceFixtureWindowCoordinator(
            configuration: configuration,
            visibleFrameProvider: { CGRect(x: 0, y: 0, width: 1280, height: 800) },
            windowFactory: { plan in
                let spy = SpaceFixtureWindowSpy(plan: plan)
                windowSpies.append(spy)
                return spy
            },
            fullscreenScheduler: { _, _ in
                scheduledCallCount += 1
            }
        )

        coordinator.launch()

        XCTAssertEqual(windowSpies.count, 2)
        XCTAssertEqual(windowSpies[0].showCalls, [true])
        XCTAssertEqual(windowSpies[1].showCalls, [false])
        XCTAssertEqual(windowSpies[0].workflowReadyCalls, [["Fixture 1", "Fixture 2"]])
        XCTAssertEqual(windowSpies[1].workflowReadyCalls, [["Fixture 1", "Fixture 2"]])
        XCTAssertEqual(scheduledCallCount, 0)
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

        let coordinator = SpaceFixtureWindowCoordinator(
            configuration: configuration,
            visibleFrameProvider: { CGRect(x: 0, y: 0, width: 1440, height: 900) },
            windowFactory: { plan in
                let spy = SpaceFixtureWindowSpy(plan: plan)
                windowSpies.append(spy)
                return spy
            },
            fullscreenScheduler: { _, _ in }
        )

        coordinator.launch()

        XCTAssertEqual(windowSpies.count, 2)
        XCTAssertEqual(windowSpies[0].plan.title, "Docs")
        XCTAssertEqual(windowSpies[0].plan.subtitleText, "Chrome Window 1")
        XCTAssertEqual(windowSpies[1].plan.title, "Mail")
        XCTAssertEqual(windowSpies[0].workflowReadyCalls, [["Docs", "Mail"]])
        XCTAssertEqual(windowSpies[1].workflowReadyCalls, [["Docs", "Mail"]])
    }
}
