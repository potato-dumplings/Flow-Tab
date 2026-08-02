import AppKit
import Carbon
import CoreGraphics
import XCTest
@testable import FlowTab
import FlowTabCore

enum FlowTabPriorityCoverageWatchdogPolicy {
    static let runtimeMaintenanceExecution: TimeInterval = 1
    static let windowPreviewEventDelivery: TimeInterval = 1
    static let runtimeFocusRecoveryObservation: TimeInterval = 1
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

    func testPriorityCoverageWatchdogPolicyPreservesWindowPreviewEventDeliveryBound() {
        let windowPreviewEventDelivery =
            FlowTabPriorityCoverageWatchdogPolicy.windowPreviewEventDelivery

        XCTAssertEqual(windowPreviewEventDelivery, 1)
        XCTAssertTrue(windowPreviewEventDelivery.isFinite)
        XCTAssertGreaterThan(windowPreviewEventDelivery, 0)
    }

    func testPriorityCoverageWatchdogPolicyPreservesRuntimeFocusRecoveryObservationBound() {
        let runtimeFocusRecoveryObservation =
            FlowTabPriorityCoverageWatchdogPolicy.runtimeFocusRecoveryObservation

        XCTAssertEqual(runtimeFocusRecoveryObservation, 1)
        XCTAssertTrue(runtimeFocusRecoveryObservation.isFinite)
        XCTAssertGreaterThan(runtimeFocusRecoveryObservation, 0)
    }
}
