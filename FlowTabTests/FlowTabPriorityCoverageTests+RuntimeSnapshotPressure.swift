import Foundation
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    func testRuntimeAXAppCollectionCoordinatorPressureUsesBoundedConcurrencyAndKeepsOrder() {
        let taskCount = 28
        let delayNanoseconds: UInt64 = 25_000_000
        let configuredConcurrency = min(
            RuntimeAXAppCollectionCoordinator.maxConcurrentCollections,
            taskCount
        )
        let inFlightLock = NSLock()
        var inFlight = 0
        var maxInFlight = 0
        let startNs = DispatchTime.now().uptimeNanoseconds

        let orderedResults: [Int] = RuntimeAXAppCollectionCoordinator.collect(count: taskCount) { index in
            inFlightLock.lock()
            inFlight += 1
            maxInFlight = max(maxInFlight, inFlight)
            inFlightLock.unlock()

            Thread.sleep(forTimeInterval: Double(delayNanoseconds) / 1_000_000_000.0)

            inFlightLock.lock()
            inFlight -= 1
            inFlightLock.unlock()
            return index
        }
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startNs) / 1_000_000.0
        let serialExpectedMs = Double(taskCount * Int(delayNanoseconds)) / 1_000_000.0

        print(
            String(
                format: "[RuntimeAXAppCollectionPressure] tasks=%d configuredConcurrency=%d maxInFlight=%d elapsed=%.2fms serialExpected=%.2fms",
                taskCount,
                configuredConcurrency,
                maxInFlight,
                elapsedMs,
                serialExpectedMs
            )
        )

        XCTAssertEqual(orderedResults, Array(0..<taskCount))
        XCTAssertEqual(maxInFlight, configuredConcurrency)
        XCTAssertLessThan(elapsedMs, serialExpectedMs * 0.70)
    }
}
