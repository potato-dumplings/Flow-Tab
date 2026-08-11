import Foundation
import XCTest

enum FlowTabUITestRuntimeTruthWatchdogPolicy {
    static let optionTabInitialTopology: TimeInterval = 12
    static let optionTabInitialWindowStateTopology: TimeInterval = 4
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
    }
}
