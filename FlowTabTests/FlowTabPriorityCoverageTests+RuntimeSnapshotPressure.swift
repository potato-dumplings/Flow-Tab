import Foundation
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    func testRuntimeAXAppCollectionCoordinatorPressureUsesBoundedConcurrencyAndKeepsOrder() {
        let taskCount = 28
        let configuredConcurrency = min(
            RuntimeAXAppCollectionCoordinator.maxConcurrentCollections,
            taskCount
        )
        let workloadGate = RuntimeAXCollectionWorkloadGate(
            saturationCount: configuredConcurrency
        )
        let collectionCompletion = DispatchGroup()
        let resultEvidence = RuntimeAXCollectionResultEvidence()
        defer { workloadGate.cancel() }

        collectionCompletion.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let results: [Int] = RuntimeAXAppCollectionCoordinator.collect(
                count: taskCount
            ) { index in
                workloadGate.perform(index: index)
            }
            resultEvidence.record(results: results)
            collectionCompletion.leave()
        }

        let saturationResult = workloadGate.waitForSaturation(
            timeout: .now()
                + RuntimeAXCollectionPressureTestPolicy.saturationWatchdog
        )
        XCTAssertEqual(
            saturationResult,
            .success,
            "Configured AX concurrency was not observed. \(workloadGate.diagnosticSummary)"
        )
        let saturatedSnapshot = workloadGate.snapshot
        XCTAssertEqual(saturatedSnapshot.inFlight, configuredConcurrency)
        XCTAssertEqual(saturatedSnapshot.enteredIndices.count, configuredConcurrency)
        XCTAssertFalse(saturatedSnapshot.released)

        workloadGate.release()

        let completionResult = collectionCompletion.wait(
            timeout: .now()
                + RuntimeAXCollectionPressureTestPolicy.completionWatchdog
        )
        XCTAssertEqual(
            completionResult,
            .success,
            """
            AX collection did not complete after explicit workload release. \
            \(workloadGate.diagnosticSummary) \(resultEvidence.diagnosticSummary)
            """
        )

        let finalSnapshot = workloadGate.snapshot
        XCTAssertEqual(resultEvidence.results, Array(0..<taskCount))
        XCTAssertEqual(finalSnapshot.maxInFlight, configuredConcurrency)
        XCTAssertEqual(finalSnapshot.enteredIndices.sorted(), Array(0..<taskCount))
        XCTAssertEqual(finalSnapshot.inFlight, 0)
        XCTAssertTrue(finalSnapshot.released)
        XCTAssertFalse(finalSnapshot.cancelled)
    }

    func testRuntimeAXCollectionPressureGateCancellationReleasesBlockedWork() {
        let taskCount = RuntimeAXAppCollectionCoordinator.maxConcurrentCollections
        let workloadGate = RuntimeAXCollectionWorkloadGate(
            saturationCount: taskCount
        )
        let collectionCompletion = DispatchGroup()
        let resultEvidence = RuntimeAXCollectionResultEvidence()
        defer { workloadGate.cancel() }

        collectionCompletion.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let results: [Int] = RuntimeAXAppCollectionCoordinator.collect(
                count: taskCount
            ) { index in
                workloadGate.perform(index: index)
            }
            resultEvidence.record(results: results)
            collectionCompletion.leave()
        }

        XCTAssertEqual(
            workloadGate.waitForSaturation(
                timeout: .now()
                    + RuntimeAXCollectionPressureTestPolicy.saturationWatchdog
            ),
            .success,
            workloadGate.diagnosticSummary
        )

        workloadGate.cancel()

        XCTAssertEqual(
            collectionCompletion.wait(
                timeout: .now()
                    + RuntimeAXCollectionPressureTestPolicy.completionWatchdog
            ),
            .success,
            "\(workloadGate.diagnosticSummary) \(resultEvidence.diagnosticSummary)"
        )
        XCTAssertEqual(resultEvidence.results, Array(0..<taskCount))
        XCTAssertEqual(workloadGate.snapshot.inFlight, 0)
        XCTAssertTrue(workloadGate.snapshot.cancelled)
    }
}

private enum RuntimeAXCollectionPressureTestPolicy {
    static let saturationWatchdog: DispatchTimeInterval = .seconds(2)
    static let completionWatchdog: DispatchTimeInterval = .seconds(2)
}

private struct RuntimeAXCollectionWorkloadSnapshot {
    let enteredIndices: [Int]
    let inFlight: Int
    let maxInFlight: Int
    let released: Bool
    let cancelled: Bool
}

private final class RuntimeAXCollectionWorkloadGate: @unchecked Sendable {
    private let condition = NSCondition()
    private let saturationCount: Int
    private let saturationReached = DispatchSemaphore(value: 0)
    private var enteredIndices: [Int] = []
    private var inFlight = 0
    private var maxInFlight = 0
    private var released = false
    private var cancelled = false
    private var didSignalSaturation = false

    init(saturationCount: Int) {
        self.saturationCount = saturationCount
    }

    var snapshot: RuntimeAXCollectionWorkloadSnapshot {
        condition.lock()
        defer { condition.unlock() }
        return RuntimeAXCollectionWorkloadSnapshot(
            enteredIndices: enteredIndices,
            inFlight: inFlight,
            maxInFlight: maxInFlight,
            released: released,
            cancelled: cancelled
        )
    }

    var diagnosticSummary: String {
        let snapshot = snapshot
        return """
        entered=\(snapshot.enteredIndices.sorted()) inFlight=\(snapshot.inFlight) \
        maxInFlight=\(snapshot.maxInFlight) released=\(snapshot.released) \
        cancelled=\(snapshot.cancelled)
        """
    }

    func waitForSaturation(timeout: DispatchTime) -> DispatchTimeoutResult {
        saturationReached.wait(timeout: timeout)
    }

    func perform(index: Int) -> Int {
        condition.lock()
        enteredIndices.append(index)
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        if inFlight == saturationCount, !didSignalSaturation {
            didSignalSaturation = true
            saturationReached.signal()
        }
        while !released && !cancelled {
            condition.wait()
        }
        inFlight -= 1
        condition.unlock()
        return index
    }

    func release() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }

    func cancel() {
        condition.lock()
        cancelled = true
        condition.broadcast()
        condition.unlock()
    }
}

private final class RuntimeAXCollectionResultEvidence: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedResults: [Int]?

    var results: [Int]? {
        lock.lock()
        defer { lock.unlock() }
        return recordedResults
    }

    var diagnosticSummary: String {
        "results=\(String(describing: results))"
    }

    func record(results: [Int]) {
        lock.lock()
        recordedResults = results
        lock.unlock()
    }
}
