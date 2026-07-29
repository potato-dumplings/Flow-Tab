import CoreGraphics
import XCTest

extension FlowTabTests {
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
            windowTitlePrefix:
                SpaceFixtureLaunchConfiguration
                    .defaultWindowTitlePrefix,
            usesStaggeredLayout: true,
            enterFullscreenDelayMilliseconds: 1_000,
            preservesDesktopAfterFullscreen: false,
            publishesApplicationAccessibilityChildren: false,
            applicationAXSuppressionRoute:
                SpaceFixtureApplicationAXSuppressionTestSupport
                    .route
        )
        var windowSpies: [SpaceFixtureWindowSpy] = []
        let scheduler = ManualSpaceFixtureScheduler()
        let suppressionScheduler =
            ManualSpaceFixtureScheduler()
        let suppressionObservation =
            ManualSpaceFixtureProjectionAcknowledgementObservation()
        let exposure =
            SpaceFixtureApplicationAXExposureProbe(
                childWindowCount: 0,
                windowsAttributeCount: 0
            )
        let completionProbe =
            SpaceFixtureApplicationAXSuppressionCompletionProbe()
        let suppressionOwner =
            SpaceFixtureApplicationAXSuppressionTestSupport
                .makeOwner(
                    scheduler: suppressionScheduler,
                    observation: suppressionObservation,
                    exposure: exposure,
                    completionProbe: completionProbe
                )
        var activationCallCount = 0
        var publishedAccessibilityElements: [[String]] = []
        let coordinator = SpaceFixtureWindowCoordinator(
            configuration: configuration,
            visibleFrameProvider: {
                CGRect(
                    x: 0,
                    y: 0,
                    width: 1_440,
                    height: 900
                )
            },
            windowFactory: { plan in
                let spy = SpaceFixtureWindowSpy(plan: plan)
                windowSpies.append(spy)
                return spy
            },
            scheduler: scheduler,
            activateApplication: {
                activationCallCount += 1
            },
            applicationAccessibilityElementsPublisher: {
                elements in
                let published =
                    elements.compactMap { $0 as? String }
                exposure.set(windowCount: published.count)
                publishedAccessibilityElements.append(published)
            },
            applicationAXSuppressionOwner:
                suppressionOwner,
            applicationIdentityProvider: {
                SpaceFixtureApplicationAXSuppressionTestSupport
                    .identity
            }
        )

        coordinator.launch()
        suppressionObservation.emit(
            SpaceFixtureApplicationAXSuppressionTestSupport
                .acknowledgement(windowCount: 3)
        )

        XCTAssertEqual(
            windowSpies.map(\.showCalls),
            [[false], [true], [false]]
        )
        XCTAssertEqual(scheduler.scheduledDelays, [1_000])
        XCTAssertEqual(
            publishedAccessibilityElements,
            [["ax-element-1", "ax-element-2", "ax-element-3"]]
        )
        XCTAssertEqual(activationCallCount, 1)
        XCTAssertTrue(
            windowSpies.allSatisfy {
                $0.workflowReadyCalls.isEmpty
            }
        )

        XCTAssertTrue(scheduler.fire(at: 0))

        XCTAssertEqual(windowSpies[2].showCalls, [false, true])
        XCTAssertEqual(
            windowSpies[2].enterFullScreenCallCount,
            1
        )
        XCTAssertEqual(
            windowSpies[1].enterFullScreenCallCount,
            0
        )
        XCTAssertEqual(activationCallCount, 2)

        windowSpies[2].completeFullScreenTransition()

        XCTAssertEqual(scheduler.scheduledDelays, [1_000])
        XCTAssertEqual(
            publishedAccessibilityElements,
            [
                [
                    "ax-element-1",
                    "ax-element-2",
                    "ax-element-3"
                ],
                [
                    "ax-element-1",
                    "ax-element-2",
                    "ax-element-3"
                ]
            ]
        )
        XCTAssertEqual(windowSpies[1].showCalls, [true, true])
        XCTAssertEqual(
            windowSpies[1].enterFullScreenCallCount,
            1
        )
        XCTAssertEqual(activationCallCount, 3)

        windowSpies[1].completeFullScreenTransition()

        XCTAssertEqual(scheduler.scheduledDelays, [1_000])
        XCTAssertEqual(
            publishedAccessibilityElements,
            [
                [
                    "ax-element-1",
                    "ax-element-2",
                    "ax-element-3"
                ],
                [
                    "ax-element-1",
                    "ax-element-2",
                    "ax-element-3"
                ],
                [
                    "ax-element-1",
                    "ax-element-2",
                    "ax-element-3"
                ],
                []
            ]
        )
        XCTAssertEqual(completionProbe.completions.count, 1)
        XCTAssertEqual(
            windowSpies.map(\.workflowReadyCalls),
            Array(
                repeating: [
                    [
                        "Normal Tab",
                        "Fullscreen Tab",
                        "Second Fullscreen Tab"
                    ]
                ],
                count: 3
            )
        )
        XCTAssertTrue(
            suppressionScheduler.token(at: 0).isCancelled
        )
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
            publishesApplicationAccessibilityChildren: false,
            applicationAXSuppressionRoute:
                SpaceFixtureApplicationAXSuppressionTestSupport
                    .route
        )
        var windowSpies: [SpaceFixtureWindowSpy] = []
        let scheduler = ManualSpaceFixtureScheduler()
        let suppressionScheduler =
            ManualSpaceFixtureScheduler()
        let suppressionObservation =
            ManualSpaceFixtureProjectionAcknowledgementObservation()
        let exposure =
            SpaceFixtureApplicationAXExposureProbe(
                childWindowCount: 0,
                windowsAttributeCount: 0
            )
        let suppressionOwner =
            SpaceFixtureApplicationAXSuppressionTestSupport
                .makeOwner(
                    scheduler: suppressionScheduler,
                    observation: suppressionObservation,
                    exposure: exposure
                )
        var publishedAccessibilityElements: [[String]] = []
        let coordinator = SpaceFixtureWindowCoordinator(
            configuration: configuration,
            visibleFrameProvider: {
                CGRect(
                    x: 0,
                    y: 0,
                    width: 1_280,
                    height: 800
                )
            },
            windowFactory: { plan in
                let spy = SpaceFixtureWindowSpy(plan: plan)
                windowSpies.append(spy)
                return spy
            },
            scheduler: scheduler,
            applicationAccessibilityElementsPublisher: {
                elements in
                let published =
                    elements.compactMap { $0 as? String }
                exposure.set(windowCount: published.count)
                publishedAccessibilityElements.append(published)
            },
            applicationAXSuppressionOwner:
                suppressionOwner,
            applicationIdentityProvider: {
                SpaceFixtureApplicationAXSuppressionTestSupport
                    .identity
            }
        )

        coordinator.launch()
        suppressionObservation.emit(
            SpaceFixtureApplicationAXSuppressionTestSupport
                .acknowledgement()
        )

        XCTAssertEqual(scheduler.scheduledDelays, [4_000])
        XCTAssertEqual(
            publishedAccessibilityElements,
            [["ax-element-1", "ax-element-2"]]
        )

        XCTAssertTrue(scheduler.fire(at: 0))
        XCTAssertEqual(
            windowSpies[1].enterFullScreenCallCount,
            1
        )
        XCTAssertEqual(
            publishedAccessibilityElements,
            [["ax-element-1", "ax-element-2"]]
        )

        windowSpies[1].completeFullScreenTransition()

        XCTAssertEqual(scheduler.scheduledDelays, [4_000])
        XCTAssertEqual(
            publishedAccessibilityElements,
            [
                ["ax-element-1", "ax-element-2"],
                ["ax-element-1", "ax-element-2"],
                []
            ]
        )
        XCTAssertTrue(
            suppressionScheduler.token(at: 0).isCancelled
        )
    }
}
