import Foundation
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    func testRuntimeAXAppCollectionCoordinatorPressureUsesBoundedConcurrencyAndKeepsOrder() {
        let taskCount = 28
        let delayNanoseconds: UInt64 = 25_000_000

        let result = RuntimeAXAppCollectionCoordinator.pressureResultForTesting(
            taskCount: taskCount,
            delayNanoseconds: delayNanoseconds
        )
        let serialExpectedMs = Double(taskCount * Int(delayNanoseconds)) / 1_000_000.0

        print(
            String(
                format: "[RuntimeAXAppCollectionPressure] tasks=%d configuredConcurrency=%d maxInFlight=%d elapsed=%.2fms serialExpected=%.2fms",
                taskCount,
                result.configuredConcurrency,
                result.maxInFlight,
                result.elapsedMs,
                serialExpectedMs
            )
        )

        XCTAssertEqual(result.orderedResults, Array(0..<taskCount))
        XCTAssertEqual(result.maxInFlight, result.configuredConcurrency)
        XCTAssertLessThan(result.elapsedMs, serialExpectedMs * 0.70)
    }
}
