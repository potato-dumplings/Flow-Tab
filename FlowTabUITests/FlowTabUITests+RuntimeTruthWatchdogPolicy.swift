import Foundation
import XCTest

enum FlowTabUITestRuntimeTruthWatchdogPolicy {
    static let optionTabInitialTopology: TimeInterval = 12
    static let optionTabInitialWindowStateTopology: TimeInterval = 4
    static let optionTabConfirmedWindowActivation: TimeInterval = 12
    static let optionTabSwitcherDismissal: TimeInterval = 4
    static let optionTabRelaunchWindowTopology: TimeInterval = 4
    static let windowSearchInitialTopology: TimeInterval = 12
}

extension FlowTabUITests {
    func testRuntimeTruthWatchdogPolicyPreservesCompatibleBounds() {
        let initialTopology =
            FlowTabUITestRuntimeTruthWatchdogPolicy
                .optionTabInitialTopology
        XCTAssertEqual(initialTopology, 12)
        XCTAssertTrue(initialTopology.isFinite && initialTopology > 0)

        let initialWindowStateTopology =
            FlowTabUITestRuntimeTruthWatchdogPolicy
                .optionTabInitialWindowStateTopology
        XCTAssertEqual(initialWindowStateTopology, 4)
        XCTAssertTrue(initialWindowStateTopology.isFinite && initialWindowStateTopology > 0)

        let confirmedWindowActivation =
            FlowTabUITestRuntimeTruthWatchdogPolicy
                .optionTabConfirmedWindowActivation
        XCTAssertEqual(confirmedWindowActivation, 12)
        XCTAssertTrue(confirmedWindowActivation.isFinite && confirmedWindowActivation > 0)

        let switcherDismissal =
            FlowTabUITestRuntimeTruthWatchdogPolicy
                .optionTabSwitcherDismissal
        XCTAssertEqual(switcherDismissal, 4)
        XCTAssertTrue(switcherDismissal.isFinite && switcherDismissal > 0)

        let relaunchWindowTopology =
            FlowTabUITestRuntimeTruthWatchdogPolicy
                .optionTabRelaunchWindowTopology
        XCTAssertEqual(relaunchWindowTopology, 4)
        XCTAssertTrue(relaunchWindowTopology.isFinite && relaunchWindowTopology > 0)

        let windowSearchInitialTopology =
            FlowTabUITestRuntimeTruthWatchdogPolicy
                .windowSearchInitialTopology
        XCTAssertEqual(windowSearchInitialTopology, 12)
        XCTAssertTrue(windowSearchInitialTopology.isFinite && windowSearchInitialTopology > 0)
    }
}
