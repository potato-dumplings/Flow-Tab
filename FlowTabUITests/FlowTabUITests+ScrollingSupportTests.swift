import Foundation
import XCTest

private enum FlowTabUITestScrollingSupportTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testScrollingHittableObserverUsesInitialEvidenceWithoutScrolling() {
        var scheduledReadbacks: [() -> Void] = []
        var cancellationCount = 0
        var scrollDeltas: [CGFloat] = []
        let owner =
            FlowTabUITestScrollingHittableElementObservationOwner(
                oneShotRegistration: { readback in
                    scheduledReadbacks.append(readback)
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    self.scrollingSupportTestSnapshot(
                        firstHittableElement: "z"
                    )
                },
                scroll: { deltaY in
                    scrollDeltas.append(deltaY)
                }
            )
        owner.start()
        defer { owner.cancel() }

        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestScrollingSupportTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .initialReadback)
        XCTAssertEqual(
            evidence?.value.firstHittableElement,
            "z"
        )
        XCTAssertEqual(scheduledReadbacks.count, 1)
        XCTAssertEqual(cancellationCount, 1)
        XCTAssertTrue(scrollDeltas.isEmpty)
    }

    func testScrollingHittableSnapshotComputesDeterministicScrollPlan() {
        XCTAssertEqual(
            scrollingSupportTestSnapshot(
                firstExistingFrame:
                    CGRect(x: 0, y: 500, width: 100, height: 40),
                scrollContainerFrame:
                    CGRect(x: 0, y: 0, width: 140, height: 300)
            ).nextScrollDeltaY,
            -420
        )
        XCTAssertEqual(
            scrollingSupportTestSnapshot(
                firstExistingFrame:
                    CGRect(x: 0, y: -220, width: 100, height: 40),
                scrollContainerFrame:
                    CGRect(x: 0, y: 0, width: 140, height: 300)
            ).nextScrollDeltaY,
            420
        )
        XCTAssertEqual(
            scrollingSupportTestSnapshot(
                scrollContainerFrame:
                    CGRect(x: 0, y: 0, width: 140, height: 300)
            ).nextScrollDeltaY,
            -420
        )
        XCTAssertNil(
            scrollingSupportTestSnapshot(
                scrollContainerExists: false,
                scrollContainerFrame: nil
            ).nextScrollDeltaY
        )
    }

    func testScrollingHittableObserverSlowReadbacksOnlyDelayExactResolution() {
        var scheduledReadbacks: [() -> Void] = []
        var scrollDeltas: [CGFloat] = []
        var snapshot = scrollingSupportTestSnapshot(
            firstExistingFrame:
                CGRect(x: 0, y: 500, width: 100, height: 40),
            scrollContainerFrame:
                CGRect(x: 0, y: 0, width: 140, height: 300)
        )
        let owner =
            FlowTabUITestScrollingHittableElementObservationOwner(
                oneShotRegistration: { readback in
                    scheduledReadbacks.append(readback)
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    snapshot
                },
                scroll: { deltaY in
                    scrollDeltas.append(deltaY)
                    if scrollDeltas.count == 5 {
                        snapshot =
                            self.scrollingSupportTestSnapshot(
                                firstHittableElement: "z"
                            )
                    }
                }
            )
        owner.start()
        defer { owner.cancel() }

        for _ in 0..<6 {
            scheduledReadbacks.removeFirst()()
        }
        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestScrollingSupportTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .scheduledReadback)
        XCTAssertEqual(
            evidence?.value.firstHittableElement,
            "z"
        )
        XCTAssertEqual(scrollDeltas.count, 5)
    }

    func testScrollingHittableObserverRejectsCancelledSchedulesUnderPressure() {
        for _ in 0..<FlowTabUITestScrollingSupportTestPolicy
            .pressureIterations
        {
            var scheduledReadbacks: [() -> Void] = []
            var snapshot = scrollingSupportTestSnapshot(
                firstExistingFrame:
                    CGRect(
                        x: 0,
                        y: 500,
                        width: 100,
                        height: 40
                    ),
                scrollContainerFrame:
                    CGRect(
                        x: 0,
                        y: 0,
                        width: 140,
                        height: 300
                    )
            )
            let owner =
                FlowTabUITestScrollingHittableElementObservationOwner(
                    oneShotRegistration: { readback in
                        scheduledReadbacks.append(readback)
                        return FlowTabUITestObservationCancellation {}
                    },
                    readback: {
                        snapshot
                    },
                    scroll: { _ in }
                )

            owner.start()
            let staleReadback = scheduledReadbacks[0]
            owner.cancel()
            owner.start()
            snapshot = scrollingSupportTestSnapshot(
                firstHittableElement: "z"
            )

            staleReadback()
            XCTAssertNil(owner.resolvedEvidence)
            scheduledReadbacks[1]()
            scheduledReadbacks[1]()
            XCTAssertEqual(
                owner.resolvedEvidence?.generation,
                2
            )
            owner.cancel()
        }
    }

    func testScrollingHittableWatchdogReportsFinalReadback() {
        var readbackCount = 0
        let owner =
            FlowTabUITestScrollingHittableElementObservationOwner(
                oneShotRegistration: { _ in
                    FlowTabUITestObservationCancellation {}
                },
                readback: {
                    defer { readbackCount += 1 }
                    return self.scrollingSupportTestSnapshot(
                        firstHittableElement:
                            readbackCount == 0 ? nil : "z"
                    )
                },
                scroll: { _ in }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestScrollingSupportTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "firstHittableIndex=0"
            )
        )
    }

    private func scrollingSupportTestSnapshot(
        firstExistingFrame: CGRect? = nil,
        firstHittableElement: String? = nil,
        scrollContainerExists: Bool = true,
        scrollContainerFrame: CGRect? = CGRect(
            x: 0,
            y: 0,
            width: 140,
            height: 300
        )
    ) -> FlowTabUITestScrollingHittableElementSnapshot<
        String
    > {
        let hasExistingElement =
            firstExistingFrame != nil
                || firstHittableElement != nil
        return FlowTabUITestScrollingHittableElementSnapshot(
            candidateCount: hasExistingElement ? 1 : 0,
            observedExistingIndices:
                hasExistingElement ? [0] : [],
            firstExistingIndex:
                hasExistingElement ? 0 : nil,
            firstExistingFrame:
                firstExistingFrame
                ?? firstHittableElement.map { _ in
                    CGRect(
                        x: 0,
                        y: 20,
                        width: 100,
                        height: 40
                    )
                },
            firstHittableIndex:
                firstHittableElement == nil ? nil : 0,
            firstHittableElement:
                firstHittableElement,
            scrollContainerExists:
                scrollContainerExists,
            scrollContainerFrame:
                scrollContainerFrame
        )
    }
}
