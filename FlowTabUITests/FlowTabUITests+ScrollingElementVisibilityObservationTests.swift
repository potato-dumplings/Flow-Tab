import Foundation
import XCTest

private enum FlowTabUITestScrollingVisibilityTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let pressureIterations = 100
}

extension FlowTabUITests {
    func testScrollingVisibilityObserverUsesInitialEvidenceWithoutScrolling() {
        var scheduledReadbacks: [() -> Void] = []
        var cancellationCount = 0
        var scrolls: [(String, CGFloat)] = []
        let owner =
            FlowTabUITestScrollingElementVisibilityObservationOwner(
                oneShotRegistration: { readback in
                    scheduledReadbacks.append(readback)
                    return FlowTabUITestObservationCancellation {
                        cancellationCount += 1
                    }
                },
                readback: {
                    self.scrollingVisibilityTestSnapshot(
                        elementHittable: true
                    )
                },
                scroll: { container, deltaY in
                    scrolls.append((container, deltaY))
                }
            )
        owner.start()
        defer { owner.cancel() }

        let evidence = owner.waitForResolution(
            timeout:
                FlowTabUITestScrollingVisibilityTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .initialReadback)
        XCTAssertEqual(evidence?.value.resolvedElement, "row")
        XCTAssertEqual(scheduledReadbacks.count, 1)
        XCTAssertEqual(cancellationCount, 1)
        XCTAssertTrue(scrolls.isEmpty)
    }

    func testScrollingVisibilitySelectsPreferredOrSmallestFallbackContainer() {
        let preferred =
            FlowTabUITestScrollingContainerCandidate(
                source:
                    FlowTabUITestScrollingContainerSource
                        .preferred,
                element: "preferred",
                frame: .zero
            )
        let fallbacks = [
            FlowTabUITestScrollingContainerCandidate(
                source: .fallback(index: 0),
                element: "large",
                frame: CGRect(
                    x: 0,
                    y: 0,
                    width: 400,
                    height: 400
                )
            ),
            FlowTabUITestScrollingContainerCandidate(
                source: .fallback(index: 1),
                element: "small",
                frame: CGRect(
                    x: 0,
                    y: 0,
                    width: 200,
                    height: 200
                )
            ),
            FlowTabUITestScrollingContainerCandidate(
                source: .fallback(index: 2),
                element: "unrelated",
                frame: CGRect(
                    x: 500,
                    y: 0,
                    width: 100,
                    height: 100
                )
            ),
        ]
        let elementFrame =
            CGRect(x: 50, y: 20, width: 100, height: 40)

        XCTAssertEqual(
            FlowTabUITestScrollingContainerSelection.select(
                elementFrame: nil,
                preferred: preferred,
                fallbacks: fallbacks
            )?.source,
            .preferred
        )
        let fallback =
            FlowTabUITestScrollingContainerSelection.select(
                elementFrame: elementFrame,
                preferred: nil,
                fallbacks: fallbacks
            )
        XCTAssertEqual(fallback?.source, .fallback(index: 1))
        XCTAssertEqual(fallback?.element, "small")
        XCTAssertNil(
            FlowTabUITestScrollingContainerSelection.select(
                elementFrame: nil,
                preferred: nil,
                fallbacks: fallbacks
            )
        )
    }

    func testScrollingVisibilitySnapshotComputesDeterministicScrollPlan() {
        XCTAssertEqual(
            scrollingVisibilityTestSnapshot(
                elementFrame: CGRect(
                    x: 0,
                    y: 500,
                    width: 100,
                    height: 40
                )
            ).nextScrollDeltaY(stepIndex: 0),
            -288
        )
        XCTAssertEqual(
            scrollingVisibilityTestSnapshot(
                elementFrame: CGRect(
                    x: 0,
                    y: -220,
                    width: 100,
                    height: 40
                )
            ).nextScrollDeltaY(stepIndex: 0),
            268
        )
        XCTAssertEqual(
            scrollingVisibilityTestSnapshot(
                elementFrame: nil
            ).nextScrollDeltaY(stepIndex: 0),
            280
        )
        XCTAssertEqual(
            scrollingVisibilityTestSnapshot(
                elementFrame: nil
            ).nextScrollDeltaY(stepIndex: 1),
            -280
        )
        XCTAssertEqual(
            scrollingVisibilityTestSnapshot(
                elementHittable: false
            ).nextScrollDeltaY(stepIndex: 0),
            80
        )
        XCTAssertEqual(
            scrollingVisibilityTestSnapshot(
                elementHittable: false
            ).nextScrollDeltaY(stepIndex: 1),
            -80
        )
        XCTAssertNil(
            scrollingVisibilityTestSnapshot(
                elementHittable: true,
                scrollContainerSource: .unavailable,
                scrollContainer: nil,
                scrollContainerFrame: nil
            ).nextScrollDeltaY(stepIndex: 0)
        )
        XCTAssertEqual(
            scrollingVisibilityTestSnapshot(
                elementHittable: true,
                scrollContainerSource: .unavailable,
                scrollContainer: nil,
                scrollContainerFrame: nil
            ).resolvedElement,
            "row"
        )
    }

    func testScrollingVisibilitySlowReadbacksOnlyDelayExactResolution() {
        var scheduledReadbacks: [() -> Void] = []
        var scrolls: [(String, CGFloat)] = []
        var snapshot = scrollingVisibilityTestSnapshot(
            elementFrame:
                CGRect(x: 0, y: 500, width: 100, height: 40)
        )
        let owner =
            FlowTabUITestScrollingElementVisibilityObservationOwner(
                oneShotRegistration: { readback in
                    scheduledReadbacks.append(readback)
                    return FlowTabUITestObservationCancellation {}
                },
                readback: {
                    snapshot
                },
                scroll: { container, deltaY in
                    scrolls.append((container, deltaY))
                    if scrolls.count == 5 {
                        snapshot =
                            self.scrollingVisibilityTestSnapshot(
                                elementHittable: true
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
                FlowTabUITestScrollingVisibilityTestPolicy
                    .watchdog
        )

        XCTAssertEqual(evidence?.source, .scheduledReadback)
        XCTAssertEqual(evidence?.value.resolvedElement, "row")
        XCTAssertEqual(scrolls.count, 5)
    }

    func testScrollingVisibilityRejectsCancelledSchedulesUnderPressure() {
        for _ in 0..<FlowTabUITestScrollingVisibilityTestPolicy
            .pressureIterations
        {
            var scheduledReadbacks: [() -> Void] = []
            var snapshot = scrollingVisibilityTestSnapshot(
                elementFrame:
                    CGRect(
                        x: 0,
                        y: 500,
                        width: 100,
                        height: 40
                    )
            )
            let owner =
                FlowTabUITestScrollingElementVisibilityObservationOwner(
                    oneShotRegistration: { readback in
                        scheduledReadbacks.append(readback)
                        return FlowTabUITestObservationCancellation {}
                    },
                    readback: {
                        snapshot
                    },
                    scroll: { _, _ in }
                )

            owner.start()
            let staleReadback = scheduledReadbacks[0]
            owner.cancel()
            owner.start()
            snapshot = scrollingVisibilityTestSnapshot(
                elementHittable: true
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

    func testScrollingVisibilityWatchdogReportsFinalReadback() {
        var readbackCount = 0
        let owner =
            FlowTabUITestScrollingElementVisibilityObservationOwner(
                oneShotRegistration: { _ in
                    FlowTabUITestObservationCancellation {}
                },
                readback: {
                    defer { readbackCount += 1 }
                    return self.scrollingVisibilityTestSnapshot(
                        elementHittable: readbackCount > 0
                    )
                },
                scroll: { _, _ in }
            )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    FlowTabUITestScrollingVisibilityTestPolicy
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
                "isFullyVisible=Optional(true)"
            )
        )
    }

    private func scrollingVisibilityTestSnapshot(
        elementHittable: Bool = false,
        elementFrame: CGRect? = CGRect(
            x: 20,
            y: 20,
            width: 100,
            height: 40
        ),
        scrollContainerSource:
            FlowTabUITestScrollingContainerSource = .preferred,
        scrollContainer: String? = "preferred",
        scrollContainerFrame: CGRect? = CGRect(
            x: 0,
            y: 0,
            width: 140,
            height: 300
        )
    ) -> FlowTabUITestScrollingElementVisibilitySnapshot<
        String
    > {
        FlowTabUITestScrollingElementVisibilitySnapshot(
            element: "row",
            elementExists: true,
            elementHittable: elementHittable,
            elementFrame: elementFrame,
            scrollContainerSource:
                scrollContainerSource,
            scrollContainer: scrollContainer,
            scrollContainerFrame: scrollContainerFrame
        )
    }
}
