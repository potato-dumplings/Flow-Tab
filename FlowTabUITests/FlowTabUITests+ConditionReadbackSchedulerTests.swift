import Foundation
import XCTest

private enum FlowTabUITestConditionReadbackSchedulerTestPolicy {
    static let watchdog: TimeInterval = 0.01
}

extension FlowTabUITests {
    func testUIConditionObserverSuppressesScheduledReadbackReentrancy() {
        var scheduledReadback:
            ((FlowTabUITestConditionObservationSource) -> Void)?
        var readbackCount = 0
        var readbackDepth = 0
        var maximumReadbackDepth = 0
        var cancellationCount = 0
        let owner = FlowTabUITestConditionObservationOwner(
            observationRegistration: { callback in
                scheduledReadback = callback
                return FlowTabUITestObservationCancellation {
                    cancellationCount += 1
                }
            },
            readback: {
                readbackDepth += 1
                maximumReadbackDepth = max(
                    maximumReadbackDepth,
                    readbackDepth
                )
                readbackCount += 1
                if readbackCount == 1 {
                    scheduledReadback?(.scheduledReadback)
                }
                readbackDepth -= 1
                return readbackCount > 1
            },
            isSatisfied: { $0 },
            describe: { "satisfied=\($0)" }
        )
        owner.start()
        defer { owner.cancel() }

        XCTAssertEqual(readbackCount, 1)
        XCTAssertEqual(maximumReadbackDepth, 1)
        XCTAssertNil(owner.resolvedEvidence)

        scheduledReadback?(.scheduledReadback)
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestConditionReadbackSchedulerTestPolicy
                    .watchdog
        )

        XCTAssertEqual(readbackCount, 2)
        XCTAssertEqual(maximumReadbackDepth, 1)
        XCTAssertEqual(evidence?.source, .scheduledReadback)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testUIConditionReadbackSchedulerRearmsAfterCallbackAndCancels() {
        var pendingCallbacks: [() -> Void] = []
        var oneShotCancellationCount = 0
        let registration =
            FlowTabUITestConditionReadbackScheduler
                .serialRegistration { callback in
                    pendingCallbacks.append(callback)
                    return FlowTabUITestObservationCancellation {
                        oneShotCancellationCount += 1
                    }
                }
        var callbackCount = 0
        var callbackDepth = 0
        var maximumCallbackDepth = 0
        var pendingCountsDuringCallback: [Int] = []
        let cancellation = registration { source in
            XCTAssertEqual(source, .scheduledReadback)
            callbackDepth += 1
            maximumCallbackDepth = max(
                maximumCallbackDepth,
                callbackDepth
            )
            pendingCountsDuringCallback.append(
                pendingCallbacks.count
            )
            callbackCount += 1
            callbackDepth -= 1
        }

        XCTAssertEqual(pendingCallbacks.count, 1)
        let firstCallback = pendingCallbacks.removeFirst()
        firstCallback()

        XCTAssertEqual(callbackCount, 1)
        XCTAssertEqual(maximumCallbackDepth, 1)
        XCTAssertEqual(pendingCountsDuringCallback, [0])
        XCTAssertEqual(pendingCallbacks.count, 1)

        let cancelledCallback =
            pendingCallbacks.removeFirst()
        cancellation?.cancel()
        cancelledCallback()

        XCTAssertEqual(callbackCount, 1)
        XCTAssertTrue(pendingCallbacks.isEmpty)
        XCTAssertEqual(oneShotCancellationCount, 2)
    }
}
