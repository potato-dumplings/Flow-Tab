import Foundation
import XCTest
@testable import FlowTab

private enum RuntimeAXRemoteWindowScanLifecycleWatchdogPolicy {
    static let eventDelivery: TimeInterval = 1
}

extension FlowTabPriorityCoverageTests {
    func testRuntimeAXRemoteWindowResolverCancellationKeepsPartialScanNonAuthoritative() {
        var visitedElementIDs: [UInt64] = []
        var isCancelled = false

        let result = RuntimeAXRemoteWindowResolverForTesting.scan(
            for: .interactive,
            isCancelled: { isCancelled }
        ) { elementID in
            visitedElementIDs.append(elementID)
            if elementID == 24 {
                isCancelled = true
            }
            return nil
        }

        XCTAssertEqual(visitedElementIDs, Array(UInt64(0)...24))
        XCTAssertEqual(
            result.completeness,
            .cancelled(scanned: 25, maximum: 750)
        )
        XCTAssertFalse(
            RuntimeAXWindowAbsencePolicy.isAbsenceAuthoritative(
                remoteScanCompleteness: result.completeness
            )
        )
        XCTAssertEqual(
            AXWindowInspectorForTesting.remoteScanLogDescription(result.completeness),
            "cancelled scanned=25 maximum=750"
        )
    }

    func testRuntimeAXRemoteWindowScanLifecycleWatchdogPolicyPreservesEventDeliveryBound() {
        let eventDelivery =
            RuntimeAXRemoteWindowScanLifecycleWatchdogPolicy
                .eventDelivery

        XCTAssertEqual(eventDelivery, 1)
        XCTAssertTrue(eventDelivery.isFinite)
        XCTAssertGreaterThan(eventDelivery, 0)
    }

    func testRuntimeAXRemoteWindowResolverCompletesConfiguredRangeAfterResolverSuspension() {
        let lifecycle = RuntimeAXRemoteWindowScanLifecycleObservation()
        let suspension = RuntimeAXRemoteWindowScanSuspension()
        let scanCompleted = DispatchSemaphore(value: 0)
        let workItem = DispatchWorkItem {
            lifecycle.beginScan()
            let result = RuntimeAXRemoteWindowResolverForTesting.scan(
                for: .interactive
            ) { elementID in
                lifecycle.recordVisit(elementID)
                if elementID == 24 {
                    lifecycle.recordSuspension(at: elementID)
                    suspension.publishSuspended()
                    suspension.waitForResume()
                    lifecycle.recordResume(at: elementID)
                }
                return nil
            }
            lifecycle.recordCompletion(result.completeness)
            scanCompleted.signal()
        }
        defer {
            suspension.cancel()
            workItem.cancel()
        }

        XCTAssertEqual(
            lifecycle.snapshot,
            RuntimeAXRemoteWindowScanLifecycleObservation.Snapshot(
                phase: .idle,
                visitedElementIDs: [],
                completeness: nil,
                violations: []
            )
        )
        XCTAssertEqual(
            suspension.snapshot,
            RuntimeAXRemoteWindowScanSuspension.Snapshot(
                didResume: false,
                resumeSignalCount: 0
            )
        )

        DispatchQueue(
            label: "FlowTabTests.RemoteAXDeterministicScan"
        ).async(execute: workItem)

        let suspensionResult = suspension.waitUntilSuspended(
            timeout:
                RuntimeAXRemoteWindowScanLifecycleWatchdogPolicy
                    .eventDelivery
        )
        XCTAssertEqual(
            suspensionResult,
            .success,
            "unmetCondition=remoteAXScanSuspendedAtElement24 "
                + "lastObservation=\(lifecycle.snapshot.diagnosticDescription)"
        )
        XCTAssertEqual(
            lifecycle.snapshot,
            RuntimeAXRemoteWindowScanLifecycleObservation.Snapshot(
                phase: .suspended(elementID: 24),
                visitedElementIDs: Array(UInt64(0)...24),
                completeness: nil,
                violations: []
            )
        )

        suspension.resume()
        XCTAssertEqual(
            suspension.snapshot,
            RuntimeAXRemoteWindowScanSuspension.Snapshot(
                didResume: true,
                resumeSignalCount: 1
            )
        )

        let completionResult = scanCompleted.wait(
            timeout:
                .now()
                + RuntimeAXRemoteWindowScanLifecycleWatchdogPolicy
                    .eventDelivery
        )
        XCTAssertEqual(
            completionResult,
            .success,
            "unmetCondition=remoteAXScanCompletedConfiguredRange "
                + "lastObservation=\(lifecycle.snapshot.diagnosticDescription)"
        )
        XCTAssertEqual(
            lifecycle.snapshot,
            RuntimeAXRemoteWindowScanLifecycleObservation.Snapshot(
                phase: .completed,
                visitedElementIDs: Array(UInt64(0)..<750),
                completeness: .complete(scanned: 750),
                violations: []
            )
        )
        suspension.cancel()
        XCTAssertEqual(
            suspension.snapshot,
            RuntimeAXRemoteWindowScanSuspension.Snapshot(
                didResume: true,
                resumeSignalCount: 1
            )
        )
    }
}

private final class RuntimeAXRemoteWindowScanSuspension:
    @unchecked Sendable
{
    struct Snapshot: Equatable {
        let didResume: Bool
        let resumeSignalCount: Int
    }

    private let lock = NSLock()
    private let suspended = DispatchSemaphore(value: 0)
    private let resumeSignal = DispatchSemaphore(value: 0)
    private var didResume = false
    private var resumeSignalCount = 0

    var snapshot: Snapshot {
        lock.lock()
        let result = Snapshot(
            didResume: didResume,
            resumeSignalCount: resumeSignalCount
        )
        lock.unlock()
        return result
    }

    func publishSuspended() {
        suspended.signal()
    }

    func waitUntilSuspended(
        timeout: TimeInterval
    ) -> DispatchTimeoutResult {
        suspended.wait(timeout: .now() + timeout)
    }

    func waitForResume() {
        resumeSignal.wait()
    }

    func resume() {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }
        didResume = true
        resumeSignalCount += 1
        lock.unlock()
        resumeSignal.signal()
    }

    func cancel() {
        resume()
    }
}

private final class RuntimeAXRemoteWindowScanLifecycleObservation:
    @unchecked Sendable
{
    enum Phase: Equatable {
        case idle
        case scanning
        case suspended(elementID: UInt64)
        case resumed(elementID: UInt64)
        case completed
    }

    struct Snapshot: Equatable {
        let phase: Phase
        let visitedElementIDs: [UInt64]
        let completeness:
            RuntimeAXRemoteWindowResolver.RemoteScanCompleteness?
        let violations: [String]

        var diagnosticDescription: String {
            let firstElementID = visitedElementIDs.first
                .map(String.init) ?? "nil"
            let lastElementID = visitedElementIDs.last
                .map(String.init) ?? "nil"
            return "phase=\(phase) "
                + "visitedCount=\(visitedElementIDs.count) "
                + "firstElementID=\(firstElementID) "
                + "lastElementID=\(lastElementID) "
                + "completeness=\(String(describing: completeness)) "
                + "violations=\(violations)"
        }
    }

    private let lock = NSLock()
    private var storedPhase: Phase = .idle
    private var storedVisitedElementIDs: [UInt64] = []
    private var storedCompleteness:
        RuntimeAXRemoteWindowResolver.RemoteScanCompleteness?
    private var storedViolations: [String] = []

    var snapshot: Snapshot {
        lock.lock()
        let result = Snapshot(
            phase: storedPhase,
            visitedElementIDs: storedVisitedElementIDs,
            completeness: storedCompleteness,
            violations: storedViolations
        )
        lock.unlock()
        return result
    }

    func beginScan() {
        lock.lock()
        if storedPhase != .idle {
            storedViolations.append(
                "beginScan expected=idle actual=\(storedPhase)"
            )
        }
        storedPhase = .scanning
        lock.unlock()
    }

    func recordVisit(_ elementID: UInt64) {
        lock.lock()
        switch storedPhase {
        case .scanning, .resumed:
            break
        case .idle, .suspended, .completed:
            storedViolations.append(
                "recordVisit elementID=\(elementID) phase=\(storedPhase)"
            )
        }
        storedVisitedElementIDs.append(elementID)
        lock.unlock()
    }

    func recordSuspension(at elementID: UInt64) {
        lock.lock()
        if storedPhase != .scanning {
            storedViolations.append(
                "recordSuspension elementID=\(elementID) phase=\(storedPhase)"
            )
        }
        storedPhase = .suspended(elementID: elementID)
        lock.unlock()
    }

    func recordResume(at elementID: UInt64) {
        lock.lock()
        if storedPhase != .suspended(elementID: elementID) {
            storedViolations.append(
                "recordResume elementID=\(elementID) phase=\(storedPhase)"
            )
        }
        storedPhase = .resumed(elementID: elementID)
        lock.unlock()
    }

    func recordCompletion(
        _ completeness:
            RuntimeAXRemoteWindowResolver.RemoteScanCompleteness
    ) {
        lock.lock()
        if storedPhase != .resumed(elementID: 24) {
            storedViolations.append(
                "recordCompletion expected=resumed24 actual=\(storedPhase)"
            )
        }
        storedCompleteness = completeness
        storedPhase = .completed
        lock.unlock()
    }
}
