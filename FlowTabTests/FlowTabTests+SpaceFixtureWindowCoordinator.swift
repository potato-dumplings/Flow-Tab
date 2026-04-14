import CoreGraphics
import XCTest

@MainActor
private final class SpaceFixtureWindowSpy: SpaceFixtureWindowing {
    let plan: SpaceFixtureWindowPlan

    private(set) var showCalls: [Bool] = []
    private(set) var enterFullScreenCallCount = 0

    init(plan: SpaceFixtureWindowPlan) {
        self.plan = plan
    }

    func show(isKey: Bool) {
        showCalls.append(isKey)
    }

    func enterFullScreen() {
        enterFullScreenCallCount += 1
    }
}

extension FlowTabTests {
    @MainActor
    func testSpaceFixtureWindowCoordinatorLaunchesWindowsAndSchedulesFullscreenTarget() {
        let configuration = SpaceFixtureLaunchConfiguration(
            windowCount: 3,
            fullscreenWindowIndex: 2,
            windowTitlePrefix: "Fixture",
            usesStaggeredLayout: true,
            enterFullscreenDelayMilliseconds: 1200
        )

        var windowSpies: [SpaceFixtureWindowSpy] = []
        var scheduledDelay: Int?
        var scheduledAction: (@MainActor () -> Void)?
        var activationCallCount = 0

        let coordinator = SpaceFixtureWindowCoordinator(
            configuration: configuration,
            visibleFrameProvider: { CGRect(x: 0, y: 0, width: 1440, height: 900) },
            windowFactory: { plan in
                let spy = SpaceFixtureWindowSpy(plan: plan)
                windowSpies.append(spy)
                return spy
            },
            fullscreenScheduler: { delay, action in
                scheduledDelay = delay
                scheduledAction = action
            },
            activateApplication: {
                activationCallCount += 1
            }
        )

        coordinator.launch()

        XCTAssertEqual(windowSpies.count, 3)
        XCTAssertEqual(windowSpies.map(\.plan.title), ["Fixture 1", "Fixture 2", "Fixture 3"])
        XCTAssertEqual(windowSpies[0].showCalls, [false])
        XCTAssertEqual(windowSpies[1].showCalls, [true])
        XCTAssertEqual(windowSpies[2].showCalls, [false])
        XCTAssertEqual(activationCallCount, 1)
        XCTAssertEqual(scheduledDelay, 1200)

        scheduledAction?()

        XCTAssertEqual(windowSpies[1].enterFullScreenCallCount, 1)
        XCTAssertEqual(windowSpies[0].enterFullScreenCallCount, 0)
        XCTAssertEqual(windowSpies[2].enterFullScreenCallCount, 0)
    }

    @MainActor
    func testSpaceFixtureWindowCoordinatorSkipsFullscreenSchedulingWhenNoTargetConfigured() {
        let configuration = SpaceFixtureLaunchConfiguration(
            windowCount: 2,
            fullscreenWindowIndex: nil,
            windowTitlePrefix: "Fixture",
            usesStaggeredLayout: false,
            enterFullscreenDelayMilliseconds: 500
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
        XCTAssertEqual(scheduledCallCount, 0)
    }
}
