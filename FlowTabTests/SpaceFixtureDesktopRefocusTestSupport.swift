import CoreGraphics

@MainActor
final class SpaceFixtureDesktopPresentationProbe {
    private struct Observation {
        let token: ManualSpaceFixtureCancellable
        let onChange:
            @MainActor (
                SpaceFixtureDesktopPresentationEvidenceSource
            ) -> Void
    }

    var snapshot: SpaceFixtureDesktopPresentationSnapshot
    private var observations: [Observation] = []

    private(set) var observeCallCount = 0

    init(windowPlanIndex: Int) {
        snapshot = Self.waitingSnapshot(
            windowPlanIndex: windowPlanIndex
        )
    }

    var activeObservationCount: Int {
        observations.filter { !$0.token.isCancelled }.count
    }

    func observe(
        _ onChange:
            @escaping @MainActor (
                SpaceFixtureDesktopPresentationEvidenceSource
            ) -> Void
    ) -> any SpaceFixtureCancellable {
        observeCallCount += 1
        let token = ManualSpaceFixtureCancellable()
        observations.append(
            Observation(token: token, onChange: onChange)
        )
        return token
    }

    func emit(
        _ source: SpaceFixtureDesktopPresentationEvidenceSource,
        includingCancelled: Bool = false
    ) {
        for observation in observations {
            guard includingCancelled
                    || !observation.token.isCancelled
            else {
                continue
            }
            observation.onChange(source)
        }
    }

    static func waitingSnapshot(
        windowPlanIndex: Int
    ) -> SpaceFixtureDesktopPresentationSnapshot {
        SpaceFixtureDesktopPresentationSnapshot(
            windowPlanIndex: windowPlanIndex,
            windowNumber: CGWindowID(windowPlanIndex),
            applicationIsActive: false,
            isKeyWindow: false,
            isMainWindow: false,
            isVisible: true,
            isMiniaturized: false,
            isOnActiveSpace: false,
            isOcclusionVisible: false,
            isCGWindowOnScreen: false
        )
    }

    static func presentedSnapshot(
        windowPlanIndex: Int
    ) -> SpaceFixtureDesktopPresentationSnapshot {
        SpaceFixtureDesktopPresentationSnapshot(
            windowPlanIndex: windowPlanIndex,
            windowNumber: CGWindowID(windowPlanIndex),
            applicationIsActive: true,
            isKeyWindow: true,
            isMainWindow: true,
            isVisible: true,
            isMiniaturized: false,
            isOnActiveSpace: true,
            isOcclusionVisible: true,
            isCGWindowOnScreen: true
        )
    }
}

extension FlowTabTests {
    @MainActor
    static func makeDesktopRefocusWindow()
        -> SpaceFixtureWindowSpy
    {
        SpaceFixtureWindowSpy(
            plan: SpaceFixtureWindowPlan(
                index: 1,
                totalWindowCount: 2,
                configuredTitle: "Desktop Anchor",
                fixtureAppName: "Fixture",
                title: "Desktop Anchor",
                frame: CGRect(
                    x: 20,
                    y: 30,
                    width: 900,
                    height: 600
                ),
                isFullscreenTarget: false,
                tabs: [],
                noisyCGSiblings: false
            )
        )
    }
}
