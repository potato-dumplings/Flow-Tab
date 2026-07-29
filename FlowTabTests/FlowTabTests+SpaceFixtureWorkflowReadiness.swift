import CoreGraphics
import Darwin
import Foundation
import XCTest

extension FlowTabTests {
    func testSpaceFixtureWorkflowReadinessTransportParsesExactReadyEvidence() {
        let notification = Notification(
            name: Notification.Name("workflow-readiness"),
            userInfo: [
                "observationGeneration": NSNumber(value: 3),
                "transitionGeneration": NSNumber(value: 8),
                "stage": "ready",
                "bundleIdentifier": "fixture.bundle",
                "processIdentifier": NSNumber(value: 4321),
                "expectedWindowPlanIndices": [
                    NSNumber(value: 1),
                    NSNumber(value: 2)
                ],
                "observedWindowPlanIndices": [
                    NSNumber(value: 1),
                    NSNumber(value: 2)
                ],
                "expectedFullscreenWindowPlanIndices": [
                    NSNumber(value: 2)
                ],
                "completedFullscreenWindowPlanIndices": [
                    NSNumber(value: 2)
                ],
                "desktopAnchorWindowPlanIndex":
                    NSNumber(value: 1),
                "desktopPresentationResolved":
                    NSNumber(value: true),
                "applicationAXSuppressionRequired":
                    NSNumber(value: true),
                "applicationAXExposureResolved":
                    NSNumber(value: true),
                "windowTitles": ["Docs", "Mail"]
            ]
        )

        let evidence =
            SpaceFixtureWorkflowReadinessTransport
                .evidence(from: notification)
        XCTAssertEqual(
            evidence,
            SpaceFixtureWorkflowReadinessEvidence(
                observationGeneration: 3,
                transitionGeneration: 8,
                stage: .ready,
                identity:
                    SpaceFixtureWorkflowReadinessIdentity(
                        bundleIdentifier: "fixture.bundle",
                        processIdentifier: 4321
                    ),
                snapshot:
                    SpaceFixtureWorkflowReadinessSnapshot(
                        expectedWindowPlanIndices: [1, 2],
                        observedWindowPlanIndices: [1, 2],
                        expectedFullscreenWindowPlanIndices:
                            [2],
                        completedFullscreenWindowPlanIndices:
                            [2],
                        desktopAnchorWindowPlanIndex: 1,
                        desktopPresentationResolved: true,
                        applicationAXSuppressionRequired:
                            true,
                        applicationAXExposureResolved: true,
                        windowTitles: ["Docs", "Mail"]
                    )
            )
        )

        var unresolvedUserInfo =
            notification.userInfo ?? [:]
        unresolvedUserInfo[
            "desktopPresentationResolved"
        ] = NSNumber(value: false)
        XCTAssertNil(
            SpaceFixtureWorkflowReadinessTransport
                .evidence(
                    from: Notification(
                        name: notification.name,
                        userInfo: unresolvedUserInfo
                    )
                )
        )

        var unorderedUserInfo =
            notification.userInfo ?? [:]
        unorderedUserInfo[
            "observedWindowPlanIndices"
        ] = [
            NSNumber(value: 2),
            NSNumber(value: 1)
        ]
        XCTAssertNil(
            SpaceFixtureWorkflowReadinessTransport
                .evidence(
                    from: Notification(
                        name: notification.name,
                        userInfo: unorderedUserInfo
                    )
                )
        )
    }

    @MainActor
    func testSpaceFixtureWorkflowReadinessWaitsForEveryExactTopologyStage() {
        var published:
            [SpaceFixtureWorkflowReadinessEvidence] = []
        var ready:
            [SpaceFixtureWorkflowReadinessEvidence] = []
        let owner =
            SpaceFixtureWorkflowReadinessOwner {
                published.append($0)
            }
        let generation = owner.start(
            expectation:
                workflowReadinessExpectation(),
            onReady: { ready.append($0) }
        )

        owner.desktopPresentationDidResolve(
            workflowDesktopEvidence(
                windowPlanIndex: 1,
                isPresented: true
            ),
            observationGeneration: generation
        )
        owner.windowTopologyDidResolve(
            planIndices: [1],
            observationGeneration: generation
        )
        owner.windowTopologyDidResolve(
            planIndices: [1, 1, 2],
            observationGeneration: generation
        )
        owner.fullscreenTopologyDidResolve(
            SpaceFixtureFullscreenTransitionCompletion(
                observationGeneration: 1,
                windowPlanIndices: [1]
            ),
            observationGeneration: generation
        )
        owner.applicationAXExposureDidResolve(
            SpaceFixtureApplicationAXExposure(
                childWindowCount: 1,
                windowsAttributeCount: 0
            ),
            observationGeneration: generation
        )
        XCTAssertTrue(ready.isEmpty)
        XCTAssertEqual(
            owner.lastEvidence?.snapshot.unmetConditions,
            [
                "windowTopology",
                "fullscreenTopology",
                "desktopPresentation",
                "applicationAXExposure"
            ]
        )

        owner.windowTopologyDidResolve(
            planIndices: [2, 1],
            observationGeneration: generation
        )
        owner.fullscreenTopologyDidResolve(
            SpaceFixtureFullscreenTransitionCompletion(
                observationGeneration: 1,
                windowPlanIndices: [2, 2]
            ),
            observationGeneration: generation
        )
        owner.fullscreenTopologyDidResolve(
            SpaceFixtureFullscreenTransitionCompletion(
                observationGeneration: 1,
                windowPlanIndices: [2]
            ),
            observationGeneration: generation
        )
        XCTAssertTrue(ready.isEmpty)
        XCTAssertEqual(
            owner.lastEvidence?.snapshot.unmetConditions,
            [
                "desktopPresentation",
                "applicationAXExposure"
            ]
        )

        owner.desktopPresentationDidResolve(
            workflowDesktopEvidence(
                windowPlanIndex: 1,
                isPresented: true
            ),
            observationGeneration: generation
        )
        XCTAssertTrue(ready.isEmpty)
        XCTAssertEqual(
            owner.lastEvidence?.snapshot.unmetConditions,
            ["applicationAXExposure"]
        )

        owner.applicationAXExposureDidResolve(
            SpaceFixtureApplicationAXExposure(
                childWindowCount: 0,
                windowsAttributeCount: 0
            ),
            observationGeneration: generation
        )

        XCTAssertEqual(ready.count, 1)
        XCTAssertEqual(ready[0].stage, .ready)
        XCTAssertTrue(ready[0].snapshot.isReady)
        XCTAssertFalse(owner.isObserving)
        XCTAssertEqual(
            published.map(\.transitionGeneration),
            Array(1...UInt64(published.count))
        )
        XCTAssertEqual(
            published.last,
            ready.last
        )

        owner.applicationAXExposureDidResolve(
            SpaceFixtureApplicationAXExposure(
                childWindowCount: 0,
                windowsAttributeCount: 0
            ),
            observationGeneration: generation
        )
        XCTAssertEqual(ready.count, 1)
    }

    @MainActor
    func testSpaceFixtureWorkflowReadinessCancellationAndReplacementRejectStaleEvidence() {
        var readyGenerations: [Int] = []
        let owner =
            SpaceFixtureWorkflowReadinessOwner { _ in }
        let firstGeneration = owner.start(
            expectation:
                workflowReadinessExpectation(
                    fullscreenWindowPlanIndices: [],
                    desktopAnchorWindowPlanIndex: nil,
                    requiresAXSuppression: false
                ),
            onReady: {
                readyGenerations.append(
                    $0.observationGeneration
                )
            }
        )
        owner.cancel()

        let secondGeneration = owner.start(
            expectation:
                workflowReadinessExpectation(
                    fullscreenWindowPlanIndices: [],
                    desktopAnchorWindowPlanIndex: nil,
                    requiresAXSuppression: false
                ),
            onReady: {
                readyGenerations.append(
                    $0.observationGeneration
                )
            }
        )
        owner.windowTopologyDidResolve(
            planIndices: [1, 2],
            observationGeneration: firstGeneration
        )
        XCTAssertTrue(readyGenerations.isEmpty)

        owner.windowTopologyDidResolve(
            planIndices: [1, 2],
            observationGeneration: secondGeneration
        )
        XCTAssertEqual(
            readyGenerations,
            [secondGeneration]
        )
    }

    @MainActor
    func testSpaceFixtureWorkflowReadinessSupportsSynchronousReplacementFromReadyPublication() {
        var owner:
            SpaceFixtureWorkflowReadinessOwner!
        var replacementGeneration: Int?
        let expectation =
            workflowReadinessExpectation(
                fullscreenWindowPlanIndices: [],
                desktopAnchorWindowPlanIndex: nil,
                requiresAXSuppression: false
            )
        owner =
            SpaceFixtureWorkflowReadinessOwner {
                evidence in
                guard evidence.stage == .ready,
                      replacementGeneration == nil
                else {
                    return
                }
                replacementGeneration = owner.start(
                    expectation: expectation,
                    onReady: { _ in }
                )
            }
        let firstGeneration = owner.start(
            expectation: expectation,
            onReady: { _ in }
        )

        owner.windowTopologyDidResolve(
            planIndices: [1, 2],
            observationGeneration: firstGeneration
        )

        XCTAssertNotNil(replacementGeneration)
        XCTAssertTrue(owner.isObserving)
        owner.windowTopologyDidResolve(
            planIndices: [1, 2],
            observationGeneration:
                replacementGeneration!
        )
        XCTAssertFalse(owner.isObserving)
    }

    @MainActor
    func testSpaceFixtureWorkflowReadinessLifecyclePressure() {
        var readyGenerations: [Int] = []
        let owner =
            SpaceFixtureWorkflowReadinessOwner { _ in }
        var generations: [Int] = []

        for _ in 0..<500 {
            generations.append(
                owner.start(
                    expectation:
                        workflowReadinessExpectation(
                            fullscreenWindowPlanIndices: [],
                            desktopAnchorWindowPlanIndex: nil,
                            requiresAXSuppression: false
                        ),
                    onReady: {
                        readyGenerations.append(
                            $0.observationGeneration
                        )
                    }
                )
            )
        }
        for generation in generations.dropLast() {
            owner.windowTopologyDidResolve(
                planIndices: [1, 2],
                observationGeneration: generation
            )
        }
        let finalGeneration = generations.last!
        owner.windowTopologyDidResolve(
            planIndices: [1, 2],
            observationGeneration: finalGeneration
        )

        XCTAssertEqual(
            readyGenerations,
            [finalGeneration]
        )
        XCTAssertFalse(owner.isObserving)
    }

    private func workflowReadinessExpectation(
        fullscreenWindowPlanIndices: [Int] = [2],
        desktopAnchorWindowPlanIndex: Int? = 1,
        requiresAXSuppression: Bool = true
    ) -> SpaceFixtureWorkflowReadinessExpectation {
        SpaceFixtureWorkflowReadinessExpectation(
            identity:
                SpaceFixtureWorkflowReadinessIdentity(
                    bundleIdentifier: "fixture.bundle",
                    processIdentifier: 4321
                ),
            windowPlanIndices: [1, 2],
            fullscreenWindowPlanIndices:
                fullscreenWindowPlanIndices,
            desktopAnchorWindowPlanIndex:
                desktopAnchorWindowPlanIndex,
            requiresApplicationAXSuppression:
                requiresAXSuppression,
            windowTitles: ["Docs", "Mail"]
        )
    }

    @MainActor
    private func workflowDesktopEvidence(
        windowPlanIndex: Int,
        isPresented: Bool
    ) -> SpaceFixtureDesktopPresentationEvidence {
        let snapshot =
            SpaceFixtureDesktopPresentationProbe
                .presentedSnapshot(
                    windowPlanIndex: windowPlanIndex
                )
        return SpaceFixtureDesktopPresentationEvidence(
            source: .activeSpaceDidChange,
            observationGeneration: 1,
            snapshot:
                isPresented
                ? snapshot
                : SpaceFixtureDesktopPresentationSnapshot(
                    windowPlanIndex: windowPlanIndex,
                    windowNumber:
                        snapshot.windowNumber,
                    applicationIsActive: false,
                    isKeyWindow: false,
                    isMainWindow: false,
                    isVisible: true,
                    isMiniaturized: false,
                    isOnActiveSpace: true,
                    isOcclusionVisible: true,
                    isCGWindowOnScreen: true
                )
        )
    }
}
