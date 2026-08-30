import Combine
import SwiftUI
import XCTest
@testable import FlowTab

extension FlowTabTests {
    @MainActor
    func testHomeRetainedTabPagePresentationPublishesOnlyChangedSnapshots() {
        let lifecycle = HomeRetainedTabLifecycle()
        let presentation = HomeRetainedTabPagePresentation(
            tab: .home,
            lifecycle: lifecycle,
            contentRevision: "revision-1"
        ) { _, _ in
            AnyView(EmptyView())
        }
        var observedSnapshots: [
            HomeRetainedTabPagePresentation.Snapshot
        ] = []
        let observation = presentation.$snapshot
            .dropFirst()
            .sink { observedSnapshots.append($0) }
        var observedLifecycleStates: [
            HomeRetainedTabLifecycle.State
        ] = []
        let lifecycleObservation = lifecycle.transitions.sink {
            observedLifecycleStates.append($0)
        }
        defer {
            observation.cancel()
            lifecycleObservation.cancel()
        }

        presentation.updateContentProvider { _, _ in
            AnyView(Text("latest"))
        }
        XCTAssertFalse(
            presentation.update(contentRevision: "revision-1")
        )
        XCTAssertTrue(lifecycle.transition(to: .active))
        XCTAssertFalse(lifecycle.transition(to: .active))
        XCTAssertTrue(lifecycle.transition(to: .inactive))
        XCTAssertTrue(
            presentation.update(contentRevision: "revision-2")
        )

        XCTAssertEqual(
            observedSnapshots,
            [
                .init(contentRevision: "revision-2")
            ]
        )
        XCTAssertEqual(observedLifecycleStates, [.active, .inactive])
    }
}
