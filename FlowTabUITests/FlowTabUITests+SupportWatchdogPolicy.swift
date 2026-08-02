import Foundation
import XCTest

enum FlowTabUITestSupportWatchdogPolicy {
    static let foregroundActivation: TimeInterval = 12
    static let fallbackForegroundActivation: TimeInterval = 4
    static let switcherCommandDelivery: TimeInterval = 4
    static let tabNavigation: TimeInterval = 6
    static let settingsControlDiscovery: TimeInterval = 6
    static let briefElementDiscovery: TimeInterval = 1
    static let scopedOptionDiscovery: TimeInterval = 2
    static let genericOptionDiscovery: TimeInterval = 3
}

extension FlowTabUITests {
    func testSupportWatchdogPolicyPreservesCompatibleOperationBounds() {
        XCTAssertEqual(
            FlowTabUITestSupportWatchdogPolicy.foregroundActivation,
            12
        )
        XCTAssertEqual(
            FlowTabUITestSupportWatchdogPolicy.fallbackForegroundActivation,
            4
        )
        XCTAssertEqual(
            FlowTabUITestSupportWatchdogPolicy.switcherCommandDelivery,
            4
        )
        XCTAssertEqual(
            FlowTabUITestSupportWatchdogPolicy.tabNavigation,
            6
        )
        XCTAssertEqual(
            FlowTabUITestSupportWatchdogPolicy.settingsControlDiscovery,
            6
        )
        XCTAssertEqual(
            FlowTabUITestSupportWatchdogPolicy.briefElementDiscovery,
            1
        )
        XCTAssertEqual(
            FlowTabUITestSupportWatchdogPolicy.scopedOptionDiscovery,
            2
        )
        XCTAssertEqual(
            FlowTabUITestSupportWatchdogPolicy.genericOptionDiscovery,
            3
        )

        let operationBounds = [
            FlowTabUITestSupportWatchdogPolicy.foregroundActivation,
            FlowTabUITestSupportWatchdogPolicy.fallbackForegroundActivation,
            FlowTabUITestSupportWatchdogPolicy.switcherCommandDelivery,
            FlowTabUITestSupportWatchdogPolicy.tabNavigation,
            FlowTabUITestSupportWatchdogPolicy.settingsControlDiscovery,
            FlowTabUITestSupportWatchdogPolicy.briefElementDiscovery,
            FlowTabUITestSupportWatchdogPolicy.scopedOptionDiscovery,
            FlowTabUITestSupportWatchdogPolicy.genericOptionDiscovery
        ]
        XCTAssertTrue(
            operationBounds.allSatisfy { $0.isFinite && $0 > 0 }
        )
        XCTAssertLessThanOrEqual(
            FlowTabUITestSupportWatchdogPolicy.fallbackForegroundActivation,
            FlowTabUITestSupportWatchdogPolicy.foregroundActivation
        )
    }
}
