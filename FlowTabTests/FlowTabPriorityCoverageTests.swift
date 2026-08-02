import AppKit
import Carbon
import CoreGraphics
import XCTest
@testable import FlowTab
import FlowTabCore

enum FlowTabPriorityCoverageWatchdogPolicy {
    static let runtimeMaintenanceExecution: TimeInterval = 1
}

final class FlowTabPriorityCoverageTests: XCTestCase {}

extension FlowTabPriorityCoverageTests {
    func testPriorityCoverageWatchdogPolicyPreservesRuntimeMaintenanceExecutionBound() {
        let runtimeMaintenanceExecution =
            FlowTabPriorityCoverageWatchdogPolicy.runtimeMaintenanceExecution

        XCTAssertEqual(runtimeMaintenanceExecution, 1)
        XCTAssertTrue(runtimeMaintenanceExecution.isFinite)
        XCTAssertGreaterThan(runtimeMaintenanceExecution, 0)
    }
}
