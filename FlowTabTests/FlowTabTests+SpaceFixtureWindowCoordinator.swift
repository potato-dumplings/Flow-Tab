import AppKit
import CoreGraphics
import XCTest

@MainActor
private final class SpaceFixtureWindowSpy: SpaceFixtureWindowing {
    let plan: SpaceFixtureWindowPlan
    let applicationAccessibilityElement: Any

    private(set) var showCalls: [Bool] = []
    private(set) var closeCallCount = 0
    private(set) var enterFullScreenCallCount = 0
    private(set) var enterFullScreenCompletions: [(@MainActor () -> Void)] = []
    private(set) var workflowReadyCalls: [[String]] = []
    private let showRecorder: @MainActor (Int, Bool) -> Void

    init(plan: SpaceFixtureWindowPlan, showRecorder: @escaping @MainActor (Int, Bool) -> Void = { _, _ in }) {
        self.plan = plan
        self.applicationAccessibilityElement = "ax-element-\(plan.index)"
        self.showRecorder = showRecorder
    }

    func show(isKey: Bool) {
        showCalls.append(isKey)
        showRecorder(plan.index, isKey)
    }

    func close() {
        closeCallCount += 1
    }

    func enterFullScreen(completion: @escaping @MainActor () -> Void) {
        enterFullScreenCallCount += 1
        enterFullScreenCompletions.append(completion)
    }

    func updateWorkflowReadiness(windowTitles: [String]) {
        workflowReadyCalls.append(windowTitles)
    }

    func completeFullScreenTransition(at index: Int = 0) {
        let completion = enterFullScreenCompletions.remove(at: index)
        completion()
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
        XCTAssertEqual(scheduledDelays, [1200])
        XCTAssertEqual(
            publishedAccessibilityElements,
            [
                ["ax-element-1", "ax-element-2", "ax-element-3"]
            ]
        )

        windowSpies[1].completeFullScreenTransition()

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
                ["ax-element-1", "ax-element-2", "ax-element-3"]
            ]
        )

        windowSpies[1].completeFullScreenTransition()

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
        XCTAssertEqual(scheduledDelays, [1_000])
        XCTAssertEqual(publishedAccessibilityElements, [["ax-element-1", "ax-element-2", "ax-element-3"]])
        XCTAssertEqual(activationCallCount, 1)

        scheduledActions[0]()

        XCTAssertEqual(windowSpies[2].showCalls, [false, true])
        XCTAssertEqual(windowSpies[2].enterFullScreenCallCount, 1)
        XCTAssertEqual(windowSpies[1].enterFullScreenCallCount, 0)
        XCTAssertEqual(activationCallCount, 2)

        windowSpies[2].completeFullScreenTransition()

        XCTAssertEqual(scheduledDelays, [1_000, 1_400])
        XCTAssertEqual(publishedAccessibilityElements, [
            ["ax-element-1", "ax-element-2", "ax-element-3"],
            ["ax-element-1", "ax-element-2", "ax-element-3"]
        ])

        scheduledActions[1]()

        XCTAssertEqual(windowSpies[1].showCalls, [true, true])
        XCTAssertEqual(windowSpies[1].enterFullScreenCallCount, 1)
        XCTAssertEqual(activationCallCount, 3)
        XCTAssertEqual(publishedAccessibilityElements, [
            ["ax-element-1", "ax-element-2", "ax-element-3"],
            ["ax-element-1", "ax-element-2", "ax-element-3"]
        ])

        windowSpies[1].completeFullScreenTransition()

        XCTAssertEqual(scheduledDelays, [1_000, 1_400, 8_000])
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

        XCTAssertEqual(scheduledDelays, [4_000])
        XCTAssertEqual(publishedAccessibilityElements, [["ax-element-1", "ax-element-2"]])

        scheduledActions[0]()

        XCTAssertEqual(windowSpies[1].enterFullScreenCallCount, 1)
        XCTAssertEqual(publishedAccessibilityElements, [
            ["ax-element-1", "ax-element-2"]
        ])

        windowSpies[1].completeFullScreenTransition()

        XCTAssertEqual(scheduledDelays, [4_000, 8_000])
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
        var scheduledCallCount = 0
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
            fullscreenScheduler: { _, _ in
                scheduledCallCount += 1
            },
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
        XCTAssertEqual(scheduledCallCount, 0)
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
        XCTAssertEqual(scheduledDelays, [1_300])
        XCTAssertEqual(publishedAccessibilityElements, [["ax-element-1", "ax-element-2"]])

        scheduledActions[0]()

        XCTAssertEqual(windowSpies[0].closeCallCount, 0)
        XCTAssertEqual(windowSpies[1].closeCallCount, 1)
        XCTAssertEqual(publishedAccessibilityElements, [["ax-element-1", "ax-element-2"], ["ax-element-1"]])
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
