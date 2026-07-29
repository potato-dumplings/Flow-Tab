import CoreGraphics
import XCTest

extension FlowTabTests {
    @MainActor
    func testSpaceFixtureWindowCoordinatorPreservesRouteLessAccessibilitySuppressionConfiguration() {
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

        XCTAssertEqual(windowSpies.count, 2)
        XCTAssertEqual(scheduler.scheduledDelays, [])
        XCTAssertEqual(
            publishedAccessibilityElements,
            [["ax-element-1", "ax-element-2"], []]
        )
        XCTAssertTrue(
            suppressionScheduler.token(at: 0).isCancelled
        )
    }

    @MainActor
    func testApplicationAXSuppressionWaitsForExactDesktopRefocusAfterFullscreen() {
        let configuration = SpaceFixtureLaunchConfiguration(
            windowCount: 2,
            fullscreenWindowIndex: 2,
            windowTitlePrefix: "Fixture",
            usesStaggeredLayout: true,
            enterFullscreenDelayMilliseconds: 700,
            preservesDesktopAfterFullscreen: true,
            publishesApplicationAccessibilityChildren: false,
            applicationAXSuppressionRoute:
                SpaceFixtureApplicationAXSuppressionTestSupport
                    .route
        )
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
        var windowSpies: [SpaceFixtureWindowSpy] = []
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
        XCTAssertTrue(scheduler.fire(at: 0))
        windowSpies[1].completeFullScreenTransition()

        XCTAssertEqual(
            publishedAccessibilityElements,
            [
                ["ax-element-1", "ax-element-2"],
                ["ax-element-1", "ax-element-2"]
            ]
        )
        XCTAssertTrue(completionProbe.completions.isEmpty)

        windowSpies[0].desktopPresentationProbe.snapshot =
            SpaceFixtureDesktopPresentationProbe
                .presentedSnapshot(windowPlanIndex: 1)
        windowSpies[0].desktopPresentationProbe.emit(
            .activeSpaceDidChange
        )

        XCTAssertEqual(
            publishedAccessibilityElements,
            [
                ["ax-element-1", "ax-element-2"],
                ["ax-element-1", "ax-element-2"],
                ["ax-element-1", "ax-element-2"],
                []
            ]
        )
        XCTAssertEqual(completionProbe.completions.count, 1)
        XCTAssertNil(
            coordinator
                .lastApplicationAXSuppressionWatchdogFailure
        )
        XCTAssertTrue(
            suppressionScheduler.token(at: 0).isCancelled
        )
    }
}
