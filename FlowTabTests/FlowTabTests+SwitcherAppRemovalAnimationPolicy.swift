import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabTests {
    func testSwitcherAppRemovalAnimationPolicyKeepsNamedVisualContract() {
        let policy = SwitcherAppRemovalAnimationPolicy.default

        XCTAssertEqual(policy.duration, 0.14)
        XCTAssertEqual(policy.maximumAnimatedAppCount, 16)
        XCTAssertEqual(
            policy.animationDuration(appCount: 0),
            policy.duration
        )
        XCTAssertEqual(
            policy.animationDuration(
                appCount: policy.maximumAnimatedAppCount
            ),
            policy.duration
        )
        XCTAssertNil(policy.animationDuration(appCount: -1))
        XCTAssertNil(
            policy.animationDuration(
                appCount: policy.maximumAnimatedAppCount + 1
            )
        )
    }

    func testSwitcherAppRemovalAnimationPolicyUsesInjectedDurationAndBoundary() {
        let injectedDuration = 0.6
        let policy = SwitcherAppRemovalAnimationPolicy(
            duration: injectedDuration,
            maximumAnimatedAppCount: 2
        )

        XCTAssertEqual(
            policy.animationDuration(appCount: 1),
            injectedDuration
        )
        XCTAssertEqual(
            policy.animationDuration(appCount: 2),
            injectedDuration
        )
        XCTAssertNil(policy.animationDuration(appCount: 3))
    }

    func testSwitcherAppListChangeClassifiesOnlyStableOrderStrictSubsetAsRemoval() {
        XCTAssertEqual(
            SwitcherAppListChange.classify(
                previousAppIDs: ["a", "b", "c", "d"],
                currentAppIDs: ["a", "c", "d"]
            ),
            .appRemoval
        )
        XCTAssertEqual(
            SwitcherAppListChange.classify(
                previousAppIDs: nil,
                currentAppIDs: ["c", "a", "b"]
            ),
            .none
        )
        XCTAssertEqual(
            SwitcherAppListChange.classify(
                previousAppIDs: ["a", "b", "c"],
                currentAppIDs: ["c", "a", "b"]
            ),
            .none
        )
        XCTAssertEqual(
            SwitcherAppListChange.classify(
                previousAppIDs: ["a", "b", "c"],
                currentAppIDs: ["a", "b", "c", "d"]
            ),
            .none
        )
        XCTAssertEqual(
            SwitcherAppListChange.classify(
                previousAppIDs: ["a", "b", "c", "d"],
                currentAppIDs: ["a", "c", "x"]
            ),
            .none
        )
    }

    @MainActor
    func testSwitcherAppSnapshotSeparatesCrossSessionReorderFromActiveRemoval() {
        let model = LiveSwitcherModel(
            runtimeProjectionService:
                RecordingRuntimeProjectionService()
        )
        let apps = terminateScenarioApps()
        model.session = SwitcherSession(apps: apps)
        XCTAssertEqual(
            model.appLayerRenderSnapshot?.listChange,
            SwitcherAppListChange.none
        )

        model.session = SwitcherSession(
            apps: [apps[1], apps[2], apps[0]]
        )
        XCTAssertEqual(
            model.appLayerRenderSnapshot?.listChange,
            SwitcherAppListChange.none
        )

        model.session = nil
        model.session = SwitcherSession(
            apps: [apps[2], apps[0], apps[1]]
        )
        XCTAssertEqual(
            model.appLayerRenderSnapshot?.listChange,
            SwitcherAppListChange.none
        )

        model.session = SwitcherSession(
            apps: [apps[2], apps[1]]
        )
        XCTAssertEqual(
            model.appLayerRenderSnapshot?.listChange,
            .appRemoval
        )
    }

    func testSwitcherAppRemovalAnimationRequiresRemovalAndRespectsSixteenAppBoundary() {
        let policy = SwitcherAppRemovalAnimationPolicy.default

        XCTAssertNil(
            policy.animationDuration(
                appCount: 16,
                listChange: .none
            )
        )
        XCTAssertEqual(
            policy.animationDuration(
                appCount: 16,
                listChange: .appRemoval
            ),
            policy.duration
        )
        XCTAssertNil(
            policy.animationDuration(
                appCount: 17,
                listChange: .appRemoval
            )
        )
    }
}
