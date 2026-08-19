import Foundation
import XCTest

private enum SpaceFixtureCurrentAppProjectionAcceptanceTestPolicy {
    static let watchdog: TimeInterval = 0.01
}

extension FlowTabUITests {
    func testSpaceFixtureCurrentAppProjectionAcceptanceParsesExactEvidence() {
        let exact = currentAppProjectionEvidence(
            evidenceGeneration: 7,
            projectionGeneration: 12,
            windowIDs: ["window-1"]
        )
        let notification = Notification(
            name: Notification.Name("accepted"),
            userInfo: currentAppProjectionUserInfo(exact)
        )
        XCTAssertEqual(
            SpaceFixtureCurrentAppProjectionAcceptanceOwner
                .evidence(from: notification),
            exact
        )

        var invalid = notification.userInfo ?? [:]
        invalid["processIdentifier"] = NSNumber(value: 0)
        XCTAssertNil(
            SpaceFixtureCurrentAppProjectionAcceptanceOwner
                .evidence(
                    from: Notification(
                        name: notification.name,
                        userInfo: invalid
                    )
                )
        )
    }

    func testSpaceFixtureCurrentAppProjectionAcceptanceUsesInitialReadback() throws {
        let route = currentAppProjectionRoute()
        route.removeReadback()
        defer { route.removeReadback() }
        let baseline = currentAppProjectionEvidence(
            evidenceGeneration: 4,
            projectionGeneration: 8,
            windowIDs: ["window-1", "window-2"]
        )
        try writeCurrentAppProjectionEvidence(
            baseline,
            to: route.readbackURL
        )
        let owner = SpaceFixtureCurrentAppProjectionAcceptanceOwner(
            route: route,
            expectedPID: 43_001,
            eventRegistration: { _ in nil },
            scheduledRegistration: { _ in nil }
        )

        owner.start()
        XCTAssertEqual(
            owner.waitForBaseline(
                timeout:
                    SpaceFixtureCurrentAppProjectionAcceptanceTestPolicy
                        .watchdog
            ),
            baseline
        )

        let target = currentAppProjectionEvidence(
            evidenceGeneration: 5,
            projectionGeneration: 9,
            windowIDs: ["window-1"],
            isCompleteForScope: false
        )
        try writeCurrentAppProjectionEvidence(
            target,
            to: route.readbackURL
        )
        XCTAssertTrue(owner.startTargetObservation())
        XCTAssertEqual(
            owner.waitForAcceptedProjection(
                timeout:
                    SpaceFixtureCurrentAppProjectionAcceptanceTestPolicy
                        .watchdog
            ),
            target
        )
        XCTAssertFalse(target.isCompleteForScope)
    }

    func testSpaceFixtureCurrentAppProjectionAcceptanceResolvesSynchronousRegistration() {
        let route = currentAppProjectionRoute()
        let baseline = currentAppProjectionEvidence(
            evidenceGeneration: 1,
            projectionGeneration: 20,
            windowIDs: ["window-1", "window-2"]
        )
        let target = currentAppProjectionEvidence(
            evidenceGeneration: 2,
            projectionGeneration: 21,
            windowIDs: ["window-1"]
        )
        var registrationCount = 0
        var cancellationCount = 0
        let owner = currentAppProjectionOwner(
            route: route,
            eventRegistration: { callback in
                registrationCount += 1
                callback(registrationCount == 1 ? baseline : target)
                return FlowTabUITestObservationCancellation {
                    cancellationCount += 1
                }
            }
        )

        owner.start()
        XCTAssertEqual(
            owner.waitForBaseline(
                timeout:
                    SpaceFixtureCurrentAppProjectionAcceptanceTestPolicy
                        .watchdog
            ),
            baseline
        )
        XCTAssertTrue(owner.startTargetObservation())
        XCTAssertEqual(
            owner.waitForAcceptedProjection(
                timeout:
                    SpaceFixtureCurrentAppProjectionAcceptanceTestPolicy
                        .watchdog
            ),
            target
        )
        XCTAssertEqual(cancellationCount, 2)
    }

    func testSpaceFixtureCurrentAppProjectionAcceptanceIgnoresUnrelatedOrderingPressure() {
        let route = currentAppProjectionRoute()
        let state = SpaceFixtureCurrentAppProjectionAcceptanceState()
        let baselineGeneration = state.beginBaseline()
        let baseline = currentAppProjectionEvidence(
            evidenceGeneration: 20,
            projectionGeneration: 30,
            windowIDs: ["window-1", "window-2"]
        )
        XCTAssertTrue(
            state.observe(
                baseline,
                phase: .baseline,
                route: route,
                expectedPID: baseline.processIdentifier,
                generation: baselineGeneration
            )
        )
        let targetGeneration = state.beginTarget()!
        XCTAssertFalse(
            state.observe(
                currentAppProjectionEvidence(
                    evidenceGeneration: 99,
                    projectionGeneration: 99,
                    bundleIdentifier: "com.example.other",
                    windowIDs: ["window-1"]
                ),
                phase: .target,
                route: route,
                expectedPID: baseline.processIdentifier,
                generation: targetGeneration
            )
        )
        XCTAssertFalse(
            state.observe(
                currentAppProjectionEvidence(
                    evidenceGeneration: 21,
                    projectionGeneration: 29,
                    windowIDs: ["window-1"]
                ),
                phase: .target,
                route: route,
                expectedPID: baseline.processIdentifier,
                generation: targetGeneration
            )
        )
        XCTAssertFalse(
            state.observe(
                currentAppProjectionEvidence(
                    evidenceGeneration: 22,
                    projectionGeneration: 31,
                    windowIDs: ["replacement-window"]
                ),
                phase: .target,
                route: route,
                expectedPID: baseline.processIdentifier,
                generation: targetGeneration
            )
        )
        XCTAssertTrue(
            state.observe(
                currentAppProjectionEvidence(
                    evidenceGeneration: 23,
                    projectionGeneration: 31,
                    windowIDs: ["window-1"]
                ),
                phase: .target,
                route: route,
                expectedPID: baseline.processIdentifier,
                generation: targetGeneration
            )
        )
    }

    func testSpaceFixtureCurrentAppProjectionAcceptanceRejectsDuplicateStaleAndCancelledEvents() {
        let route = currentAppProjectionRoute()
        let state = SpaceFixtureCurrentAppProjectionAcceptanceState()
        let baselineGeneration = state.beginBaseline()
        let baseline = currentAppProjectionEvidence(
            evidenceGeneration: 4,
            projectionGeneration: 10,
            windowIDs: ["window-1", "window-2"]
        )
        XCTAssertTrue(
            state.observe(
                baseline,
                phase: .baseline,
                route: route,
                expectedPID: baseline.processIdentifier,
                generation: baselineGeneration
            )
        )
        let targetGeneration = state.beginTarget()!
        let target = currentAppProjectionEvidence(
            evidenceGeneration: 5,
            projectionGeneration: 11,
            windowIDs: ["window-1"]
        )
        XCTAssertTrue(
            state.observe(
                target,
                phase: .target,
                route: route,
                expectedPID: target.processIdentifier,
                generation: targetGeneration
            )
        )
        XCTAssertFalse(
            state.observe(
                target,
                phase: .target,
                route: route,
                expectedPID: target.processIdentifier,
                generation: targetGeneration
            )
        )
        state.cancel()
        XCTAssertFalse(
            state.observe(
                currentAppProjectionEvidence(
                    evidenceGeneration: 6,
                    projectionGeneration: 12,
                    windowIDs: ["window-1"]
                ),
                phase: .target,
                route: route,
                expectedPID: target.processIdentifier,
                generation: targetGeneration
            )
        )
    }

    func testSpaceFixtureCurrentAppProjectionAcceptanceWatchdogReportsLastEvidence() {
        let route = currentAppProjectionRoute()
        let baseline = currentAppProjectionEvidence(
            evidenceGeneration: 1,
            projectionGeneration: 40,
            windowIDs: ["window-1", "window-2"]
        )
        var registrationCount = 0
        let owner = currentAppProjectionOwner(
            route: route,
            eventRegistration: { callback in
                registrationCount += 1
                callback(
                    registrationCount == 1
                        ? baseline
                        : self.currentAppProjectionEvidence(
                            evidenceGeneration: 2,
                            projectionGeneration: 41,
                            processIdentifier: 43_009,
                            windowIDs: ["window-1"]
                        )
                )
                return nil
            }
        )
        owner.start()
        XCTAssertNotNil(
            owner.waitForBaseline(
                timeout:
                    SpaceFixtureCurrentAppProjectionAcceptanceTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(owner.startTargetObservation())
        XCTAssertNil(
            owner.waitForAcceptedProjection(
                timeout:
                    SpaceFixtureCurrentAppProjectionAcceptanceTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(owner.diagnosticSummary.contains("pid=43009"))
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "waitResult=timedOut"
            )
        )
    }

    func testSpaceFixtureCurrentAppProjectionAcceptanceLifecyclePressureIsDeterministic() {
        let route = currentAppProjectionRoute()
        let state = SpaceFixtureCurrentAppProjectionAcceptanceState()
        for cycle in 1...2_000 {
            let baselineGeneration = state.beginBaseline()
            let baseline = currentAppProjectionEvidence(
                evidenceGeneration: UInt64(cycle * 2 - 1),
                projectionGeneration: UInt64(cycle * 2),
                windowIDs: ["window-1", "window-2"]
            )
            XCTAssertTrue(
                state.observe(
                    baseline,
                    phase: .baseline,
                    route: route,
                    expectedPID: baseline.processIdentifier,
                    generation: baselineGeneration
                )
            )
            let targetGeneration = state.beginTarget()!
            XCTAssertFalse(
                state.observe(
                    currentAppProjectionEvidence(
                        evidenceGeneration: UInt64(cycle * 2),
                        projectionGeneration: UInt64(cycle * 2 + 1),
                        windowIDs: ["replacement"]
                    ),
                    phase: .target,
                    route: route,
                    expectedPID: baseline.processIdentifier,
                    generation: targetGeneration
                )
            )
            XCTAssertTrue(
                state.observe(
                    currentAppProjectionEvidence(
                        evidenceGeneration: UInt64(cycle * 2),
                        projectionGeneration: UInt64(cycle * 2 + 1),
                        windowIDs: ["window-1"]
                    ),
                    phase: .target,
                    route: route,
                    expectedPID: baseline.processIdentifier,
                    generation: targetGeneration
                )
            )
            state.cancel()
        }
    }

    private func currentAppProjectionRoute()
        -> SpaceFixtureCurrentAppProjectionAcceptanceRoute
    {
        SpaceFixtureCurrentAppProjectionAcceptanceRoute(
            notificationName: Notification.Name(
                "test.current-app-projection"
            ),
            readbackURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "test-current-app-projection-\(UUID().uuidString).json"
                ),
            bundleIdentifier: "com.example.fixture"
        )
    }

    private func currentAppProjectionEvidence(
        evidenceGeneration: UInt64,
        projectionGeneration: UInt64,
        bundleIdentifier: String = "com.example.fixture",
        processIdentifier: pid_t = 43_001,
        windowIDs: [String],
        isCompleteForScope: Bool = true
    ) -> SpaceFixtureCurrentAppProjectionAcceptanceEvidence {
        SpaceFixtureCurrentAppProjectionAcceptanceEvidence(
            evidenceGeneration: evidenceGeneration,
            bundleIdentifier: bundleIdentifier,
            appID: bundleIdentifier,
            processIdentifier: processIdentifier,
            windowIDs: windowIDs,
            isCompleteForScope: isCompleteForScope,
            sourceGeneration:
                SpaceFixtureCurrentAppProjectionSourceGeneration(
                    appLifecycle: projectionGeneration,
                    cg: projectionGeneration,
                    space: projectionGeneration,
                    axDirty: projectionGeneration,
                    projection: projectionGeneration
                )
        )
    }

    private func currentAppProjectionOwner(
        route:
            SpaceFixtureCurrentAppProjectionAcceptanceRoute,
        eventRegistration:
            @escaping SpaceFixtureCurrentAppProjectionEventRegistration
    ) -> SpaceFixtureCurrentAppProjectionAcceptanceOwner {
        SpaceFixtureCurrentAppProjectionAcceptanceOwner(
            route: route,
            expectedPID: 43_001,
            eventRegistration: eventRegistration,
            scheduledRegistration: { _ in nil },
            evidenceReadback: {
                SpaceFixtureCurrentAppProjectionEvidenceReadback(
                    path: route.readbackURL.path,
                    fileExists: false,
                    evidence: nil,
                    errorDescription: nil
                )
            }
        )
    }

    private func writeCurrentAppProjectionEvidence(
        _ evidence:
            SpaceFixtureCurrentAppProjectionAcceptanceEvidence,
        to url: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(evidence).write(
            to: url,
            options: .atomic
        )
    }

    private func currentAppProjectionUserInfo(
        _ evidence:
            SpaceFixtureCurrentAppProjectionAcceptanceEvidence
    ) -> [String: Any] {
        [
            "evidenceGeneration":
                NSNumber(value: evidence.evidenceGeneration),
            "bundleIdentifier": evidence.bundleIdentifier,
            "appID": evidence.appID,
            "processIdentifier":
                NSNumber(value: evidence.processIdentifier),
            "windowIDs": evidence.windowIDs,
            "isCompleteForScope":
                NSNumber(value: evidence.isCompleteForScope),
            "appLifecycleGeneration":
                NSNumber(value: evidence.sourceGeneration.appLifecycle),
            "cgGeneration":
                NSNumber(value: evidence.sourceGeneration.cg),
            "spaceGeneration":
                NSNumber(value: evidence.sourceGeneration.space),
            "axDirtyGeneration":
                NSNumber(value: evidence.sourceGeneration.axDirty),
            "projectionGeneration":
                NSNumber(value: evidence.sourceGeneration.projection)
        ]
    }
}
