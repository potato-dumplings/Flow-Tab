import CoreGraphics
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    func testRuntimeWindowMappingStateDerivesReverseAXCGIndex() {
        let state = RuntimeWindowMappingState(
            currentAXToCG: [
                "ax:18405:0": 240_001,
                "ax:18405:1": 243_747
            ],
            validCGWindowIDs: Set<CGWindowID>([240_001, 243_747, 250_000]),
            lastAXWindowIDs: Set(["ax:18405:0", "ax:18405:1"])
        )

        XCTAssertEqual(state.currentCGToAX[240_001], "ax:18405:0")
        XCTAssertEqual(state.currentCGToAX[243_747], "ax:18405:1")
        XCTAssertNil(state.currentCGToAX[250_000])
        XCTAssertEqual(state.validCGWindowIDs, Set<CGWindowID>([240_001, 243_747, 250_000]))
        XCTAssertEqual(state.lastAXWindowIDs, Set(["ax:18405:0", "ax:18405:1"]))
    }

    func testRuntimeWindowRecordLifecycleKeepsRecoverableMissingEvidenceDuringGraceWindow() {
        let policy = RuntimeWindowRecordLifecyclePolicy(evidenceGraceInterval: 1.0)
        let cgWindow = RuntimeSnapshotProvider.CGWindowEntry(
            id: 240_001,
            title: "Recovered Window",
            bounds: CGRect(x: 20, y: 30, width: 800, height: 600),
            isOnscreen: false,
            alpha: 1.0,
            storeType: 1,
            spaceIDs: [11_679]
        )
        var record = RuntimeWindowRecord(
            cgWindowID: cgWindow.id,
            stableWindowID: "cg:18405:240001",
            firstSeenAt: 10
        )
        record.refreshCGState(from: cgWindow, observedAt: 10)

        let firstMissingDecision = record.reconcileLifecycle(
            validCGWindowIDs: [],
            observedAt: 11,
            policy: policy
        )
        let secondMissingDecision = record.reconcileLifecycle(
            validCGWindowIDs: [],
            observedAt: 11.5,
            policy: policy
        )
        let expiredDecision = record.reconcileLifecycle(
            validCGWindowIDs: [],
            observedAt: 12,
            policy: policy
        )

        XCTAssertEqual(firstMissingDecision, .keep)
        XCTAssertEqual(secondMissingDecision, .keep)
        XCTAssertEqual(expiredDecision, .delete)
        XCTAssertEqual(record.suspectDeletedAt, 11)
        XCTAssertEqual(record.spaceRecovery?.invalidatedAt, 11)
    }

    func testRuntimeWindowRecordLifecycleClearsSuspectStateWhenCGEvidenceReturns() {
        let cgWindow = RuntimeSnapshotProvider.CGWindowEntry(
            id: 243_747,
            title: "Recovered Window",
            bounds: CGRect(x: 0, y: 124, width: 1_728, height: 993),
            isOnscreen: false,
            alpha: 1.0,
            storeType: 1,
            spaceIDs: [11_680]
        )
        var record = RuntimeWindowRecord(
            cgWindowID: cgWindow.id,
            stableWindowID: "cg:18405:243747",
            firstSeenAt: 20
        )
        record.refreshCGState(from: cgWindow, observedAt: 20)

        XCTAssertEqual(
            record.reconcileLifecycle(validCGWindowIDs: [], observedAt: 21),
            .keep
        )
        XCTAssertEqual(record.suspectDeletedAt, 21)

        record.refreshCGState(from: cgWindow, observedAt: 21.2)
        XCTAssertEqual(
            record.reconcileLifecycle(validCGWindowIDs: [cgWindow.id], observedAt: 21.2),
            .keep
        )
        XCTAssertNil(record.suspectDeletedAt)
        XCTAssertNil(record.spaceRecovery?.invalidatedAt)
    }

    func testRuntimeSnapshotProviderDropsWindowRecordAfterLifecycleGraceExpires() {
        let provider = RuntimeSnapshotProvider()
        let pid: pid_t = 18_405
        let now = Date.timeIntervalSinceReferenceDate
        var staleRecord = RuntimeWindowRecord(
            cgWindowID: 250_000,
            stableWindowID: "cg:18405:250000",
            firstSeenAt: now - 3
        )
        staleRecord.spaceRecovery = RuntimeSpaceRecoveryState(
            cgWindowID: 250_000,
            spaceIDs: [11_681],
            hasConfirmedActivationRoute: true,
            lastValidatedAt: now - 3,
            invalidatedAt: now - 2
        )
        staleRecord.suspectDeletedAt = now - 2
        provider.windowMappingStateByPID[pid] = RuntimeWindowMappingState(
            windowRecordsByCGWindowID: [250_000: staleRecord]
        )

        let resolution = provider.resolveStableWindowMapping(
            axWindows: [],
            cgWindows: [],
            pid: pid,
            appName: "Google Chrome"
        )

        XCTAssertTrue(resolution.windowRecordsByCGWindowID.isEmpty)
        XCTAssertNil(provider.windowMappingStateByPID[pid])
    }
}
