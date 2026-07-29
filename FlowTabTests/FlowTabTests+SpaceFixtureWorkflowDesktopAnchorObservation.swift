import Darwin
import Foundation
import XCTest

extension FlowTabTests {
    func testWorkflowDesktopAnchorCompletesFromExactInitialReadback() {
        let expectation =
            workflowDesktopAnchorExpectation()
        let owner =
            SpaceFixtureWorkflowDesktopAnchorOwner()
        var resolved:
            [SpaceFixtureWorkflowDesktopAnchorEvidence] = []
        let generation = owner.start(
            expectation: expectation,
            watchdogSeconds: 15,
            onResolved: { resolved.append($0) },
            onWatchdog: { _ in
                XCTFail("Exact initial state must resolve.")
            }
        )

        XCTAssertTrue(
            owner.observe(
                snapshot:
                    workflowDesktopAnchorSnapshot(),
                source: .initialReadback,
                observationGeneration: generation
            )
        )

        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved[0].source, .initialReadback)
        XCTAssertFalse(owner.isObserving)
    }

    func testWorkflowDesktopAnchorRequiresExactProcessWindowAndDesktopSpace() {
        let expectation =
            workflowDesktopAnchorExpectation()
        let owner =
            SpaceFixtureWorkflowDesktopAnchorOwner()
        var resolved:
            [SpaceFixtureWorkflowDesktopAnchorEvidence] = []
        let generation = owner.start(
            expectation: expectation,
            watchdogSeconds: 15,
            onResolved: { resolved.append($0) },
            onWatchdog: { _ in }
        )

        XCTAssertFalse(
            owner.observe(
                snapshot:
                    workflowDesktopAnchorSnapshot(
                        frontmostProcessIdentifier: 2_002
                    ),
                source: .applicationDidActivate,
                observationGeneration: generation
            )
        )
        XCTAssertEqual(
            owner.lastEvidence?.snapshot.unmetConditions(
                expectation: expectation
            ),
            ["frontmostProcessIdentity"]
        )
        XCTAssertFalse(
            owner.observe(
                snapshot:
                    workflowDesktopAnchorSnapshot(
                        identifiedWindowPlanIndex: 3
                    ),
                source: .activeSpaceDidChange,
                observationGeneration: generation
            )
        )
        XCTAssertEqual(
            owner.lastEvidence?.snapshot.unmetConditions(
                expectation: expectation
            ),
            ["windowPlanIdentity"]
        )
        XCTAssertFalse(
            owner.observe(
                snapshot: workflowDesktopAnchorSnapshot(
                    topmostCGWindowFrame:
                        CGRect(
                            x: 300,
                            y: 300,
                            width: 960,
                            height: 640
                        )
                ),
                source: .conditionPollReadback,
                observationGeneration: generation
            )
        )
        XCTAssertEqual(
            owner.lastEvidence?.snapshot.unmetConditions(
                expectation: expectation
            ),
            ["exactCGWindowIdentity"]
        )
        XCTAssertFalse(
            owner.observe(
                snapshot:
                    workflowDesktopAnchorSnapshot(
                        topmostCGWindowIsFullscreenSpaceSized:
                            true
                    ),
                source: .conditionPollReadback,
                observationGeneration: generation
            )
        )
        XCTAssertTrue(resolved.isEmpty)

        XCTAssertTrue(
            owner.observe(
                snapshot:
                    workflowDesktopAnchorSnapshot(),
                source: .conditionPollReadback,
                observationGeneration: generation
            )
        )
        XCTAssertEqual(resolved.count, 1)
    }

    func testWorkflowDesktopAnchorCancellationAndReplacementRejectStaleEvidence() {
        let expectation =
            workflowDesktopAnchorExpectation()
        let owner =
            SpaceFixtureWorkflowDesktopAnchorOwner()
        var resolvedGenerations: [Int] = []
        let firstGeneration = owner.start(
            expectation: expectation,
            watchdogSeconds: 15,
            onResolved: {
                resolvedGenerations.append(
                    $0.observationGeneration
                )
            },
            onWatchdog: { _ in }
        )
        owner.cancel()
        let secondGeneration = owner.start(
            expectation: expectation,
            watchdogSeconds: 15,
            onResolved: {
                resolvedGenerations.append(
                    $0.observationGeneration
                )
            },
            onWatchdog: { _ in }
        )

        XCTAssertFalse(
            owner.observe(
                snapshot:
                    workflowDesktopAnchorSnapshot(),
                source: .conditionPollReadback,
                observationGeneration: firstGeneration
            )
        )
        XCTAssertTrue(resolvedGenerations.isEmpty)
        XCTAssertTrue(
            owner.observe(
                snapshot:
                    workflowDesktopAnchorSnapshot(),
                source: .applicationDidActivate,
                observationGeneration:
                    secondGeneration
            )
        )
        XCTAssertEqual(resolvedGenerations, [secondGeneration])
        XCTAssertFalse(
            owner.observe(
                snapshot: workflowDesktopAnchorSnapshot(),
                source: .activeSpaceDidChange,
                observationGeneration:
                    secondGeneration
            )
        )
        XCTAssertEqual(resolvedGenerations, [secondGeneration])
    }

    func testWorkflowDesktopAnchorSupportsSynchronousReplacement() {
        let expectation =
            workflowDesktopAnchorExpectation()
        var owner:
            SpaceFixtureWorkflowDesktopAnchorOwner!
        var replacementGeneration: Int?
        owner = SpaceFixtureWorkflowDesktopAnchorOwner()
        let firstGeneration = owner.start(
            expectation: expectation,
            watchdogSeconds: 15
        ) { _ in
            replacementGeneration = owner.start(
                expectation: expectation,
                watchdogSeconds: 15,
                onResolved: { _ in },
                onWatchdog: { _ in }
            )
        } onWatchdog: { _ in }

        _ = owner.observe(
            snapshot: workflowDesktopAnchorSnapshot(),
            source: .triggerReturnReadback,
            observationGeneration: firstGeneration
        )

        XCTAssertNotNil(replacementGeneration)
        XCTAssertTrue(owner.isObserving)
        _ = owner.observe(
            snapshot: workflowDesktopAnchorSnapshot(),
            source: .conditionPollReadback,
            observationGeneration:
                replacementGeneration!
        )
        XCTAssertFalse(owner.isObserving)
    }

    func testWorkflowDesktopAnchorWatchdogReportsLastAndFinalEvidence() {
        let expectation =
            workflowDesktopAnchorExpectation()
        let owner =
            SpaceFixtureWorkflowDesktopAnchorOwner()
        var failures:
            [SpaceFixtureWorkflowDesktopAnchorWatchdogFailure] = []
        let generation = owner.start(
            expectation: expectation,
            watchdogSeconds: 15,
            onResolved: { _ in
                XCTFail("Incomplete evidence must not resolve.")
            },
            onWatchdog: { failures.append($0) }
        )
        _ = owner.observe(
            snapshot:
                workflowDesktopAnchorSnapshot(
                    xcuiRunningForeground: false
                ),
            source: .conditionPollReadback,
            observationGeneration: generation
        )

        XCTAssertFalse(
            owner.expireWatchdog(
                finalSnapshot:
                    workflowDesktopAnchorSnapshot(
                        frontmostProcessIdentifier: 2_002
                    ),
                observationGeneration: generation
            )
        )

        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures[0].lastEvidence.source, .conditionPollReadback)
        XCTAssertEqual(failures[0].finalEvidence.source, .watchdogReadback)
        XCTAssertTrue(
            failures[0].logFields.contains(
                "unmet=[frontmostProcessIdentity]"
            )
        )
        XCTAssertFalse(owner.isObserving)
    }

    func testWorkflowDesktopAnchorLifecyclePressureKeepsFinalGenerationOracle() {
        let expectation =
            workflowDesktopAnchorExpectation()
        let owner =
            SpaceFixtureWorkflowDesktopAnchorOwner()
        var resolvedGenerations: [Int] = []
        var generations: [Int] = []

        for _ in 0..<500 {
            generations.append(
                owner.start(
                    expectation: expectation,
                    watchdogSeconds: 15
                ) {
                    resolvedGenerations.append(
                        $0.observationGeneration
                    )
                } onWatchdog: { _ in }
            )
        }
        for generation in generations.dropLast() {
            _ = owner.observe(
                snapshot:
                    workflowDesktopAnchorSnapshot(),
                source: .applicationDidActivate,
                observationGeneration: generation
            )
        }
        let finalGeneration = generations.last!
        for _ in 0..<50 {
            _ = owner.observe(
                snapshot:
                    workflowDesktopAnchorSnapshot(
                        xcuiRunningForeground: false
                    ),
                source: .conditionPollReadback,
                observationGeneration: finalGeneration
            )
        }
        _ = owner.observe(
            snapshot: workflowDesktopAnchorSnapshot(),
            source: .conditionPollReadback,
            observationGeneration: finalGeneration
        )

        XCTAssertEqual(resolvedGenerations, [finalGeneration])
        XCTAssertFalse(owner.isObserving)
    }

    private func workflowDesktopAnchorExpectation()
        -> SpaceFixtureWorkflowDesktopAnchorExpectation
    {
        SpaceFixtureWorkflowDesktopAnchorExpectation(
            bundleIdentifier: "fixture.finder",
            processIdentifier: 1_001,
            windows: [
                SpaceFixtureWorkflowDesktopAnchorWindowExpectation(
                    planIndex: 1,
                    title: "Finder Main",
                    accessibilityIdentifier:
                        "fixture.title.1"
                ),
                SpaceFixtureWorkflowDesktopAnchorWindowExpectation(
                    planIndex: 2,
                    title: "Finder Downloads",
                    accessibilityIdentifier:
                        "fixture.title.2"
                )
            ]
        )
    }

    private func workflowDesktopAnchorSnapshot(
        runningBundleIdentifier: String? =
            "fixture.finder",
        runningProcessIdentifier: pid_t? = 1_001,
        applicationIsActive: Bool = true,
        applicationIsTerminated: Bool = false,
        xcuiRunningForeground: Bool = true,
        frontmostBundleIdentifier: String? =
            "fixture.finder",
        frontmostProcessIdentifier: pid_t? = 1_001,
        identifiedXCUIWindowFrame: CGRect? =
            CGRect(x: 100, y: 100, width: 960, height: 640),
        identifiedWindowPlanIndex: Int? = 1,
        identifiedWindowTitle: String? = "Finder Main",
        identifiedAccessibilityIdentifier: String? =
            "fixture.title.1",
        observedXCUIWindowFrames: [CGRect] = [
            CGRect(x: 100, y: 100, width: 960, height: 640)
        ],
        topmostCGWindowNumber: CGWindowID? = 42,
        topmostCGWindowTitle: String? = "Finder Main",
        topmostCGWindowFrame: CGRect? =
            CGRect(x: 100, y: 100, width: 960, height: 640),
        topmostCGWindowIsFullscreenSpaceSized: Bool =
            false
    ) -> SpaceFixtureWorkflowDesktopAnchorSnapshot {
        SpaceFixtureWorkflowDesktopAnchorSnapshot(
            runningBundleIdentifier:
                runningBundleIdentifier,
            runningProcessIdentifier:
                runningProcessIdentifier,
            applicationIsActive: applicationIsActive,
            applicationIsTerminated:
                applicationIsTerminated,
            xcuiRunningForeground:
                xcuiRunningForeground,
            frontmostBundleIdentifier:
                frontmostBundleIdentifier,
            frontmostProcessIdentifier:
                frontmostProcessIdentifier,
            identifiedXCUIWindowFrame:
                identifiedXCUIWindowFrame,
            identifiedWindowPlanIndex:
                identifiedWindowPlanIndex,
            identifiedWindowTitle:
                identifiedWindowTitle,
            identifiedAccessibilityIdentifier:
                identifiedAccessibilityIdentifier,
            observedXCUIWindowFrames:
                observedXCUIWindowFrames,
            topmostCGWindowNumber:
                topmostCGWindowNumber,
            topmostCGWindowTitle:
                topmostCGWindowTitle,
            topmostCGWindowFrame:
                topmostCGWindowFrame,
            topmostCGWindowIsFullscreenSpaceSized:
                topmostCGWindowIsFullscreenSpaceSized
        )
    }
}
