import Foundation
import XCTest

enum FlowTabUITestRuntimeTruthWatchdogPolicy {
    static let optionTabInitialTopology: TimeInterval = 12
    static let optionTabInitialWindowStateTopology: TimeInterval = 4
    static let optionTabConfirmedWindowActivation: TimeInterval = 12
    static let optionTabSwitcherDismissal: TimeInterval = 4
    static let optionTabRelaunchWindowTopology: TimeInterval = 4
    static let windowSearchInitialTopology: TimeInterval = 12
    static let windowSearchInitialPresentationTopology: TimeInterval = 4
    static let windowSearchConfirmedWindowActivation: TimeInterval = 12
    static let windowSearchInputDismissal: TimeInterval = 4
    static let windowSearchRelaunchWindowTopology: TimeInterval = 4
    static let windowSearchDiagnosticsPublication: TimeInterval = 12
    static let windowSearchCommittedProjectionPublication: TimeInterval = 8
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

        let windowSearchInitialPresentationTopology =
            FlowTabUITestRuntimeTruthWatchdogPolicy
                .windowSearchInitialPresentationTopology
        XCTAssertEqual(windowSearchInitialPresentationTopology, 4)
        XCTAssertTrue(windowSearchInitialPresentationTopology.isFinite && windowSearchInitialPresentationTopology > 0)

        let windowSearchConfirmedWindowActivation =
            FlowTabUITestRuntimeTruthWatchdogPolicy
                .windowSearchConfirmedWindowActivation
        XCTAssertEqual(windowSearchConfirmedWindowActivation, 12)
        XCTAssertTrue(windowSearchConfirmedWindowActivation.isFinite && windowSearchConfirmedWindowActivation > 0)

        let windowSearchInputDismissal =
            FlowTabUITestRuntimeTruthWatchdogPolicy
                .windowSearchInputDismissal
        XCTAssertEqual(windowSearchInputDismissal, 4)
        XCTAssertTrue(windowSearchInputDismissal.isFinite && windowSearchInputDismissal > 0)

        let windowSearchRelaunchWindowTopology =
            FlowTabUITestRuntimeTruthWatchdogPolicy
                .windowSearchRelaunchWindowTopology
        XCTAssertEqual(windowSearchRelaunchWindowTopology, 4)
        XCTAssertTrue(windowSearchRelaunchWindowTopology.isFinite && windowSearchRelaunchWindowTopology > 0)

        let windowSearchDiagnosticsPublication =
            FlowTabUITestRuntimeTruthWatchdogPolicy
                .windowSearchDiagnosticsPublication
        XCTAssertEqual(windowSearchDiagnosticsPublication, 12)
        XCTAssertTrue(windowSearchDiagnosticsPublication.isFinite && windowSearchDiagnosticsPublication > 0)

        let windowSearchCommittedProjectionPublication =
            FlowTabUITestRuntimeTruthWatchdogPolicy
                .windowSearchCommittedProjectionPublication
        XCTAssertEqual(windowSearchCommittedProjectionPublication, 8)
        XCTAssertTrue(
            windowSearchCommittedProjectionPublication.isFinite
                && windowSearchCommittedProjectionPublication > 0
        )
    }
}
