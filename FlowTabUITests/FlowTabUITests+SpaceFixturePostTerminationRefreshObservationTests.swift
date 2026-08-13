import Foundation
import XCTest

private enum SpaceFixturePostTerminationRefreshObservationTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let eventWatchdog: TimeInterval = 1
    static let slowEvidenceInjectionLatency: TimeInterval = 0.05
    static let pressureIterations = 200
}

private final class ManualSpaceFixturePostTerminationRefreshLogSource {
    private(set) var snapshot =
        FlowTabUITestRuntimeLogSnapshot(
            baselineFileEventGeneration: 10,
            fileEventGeneration: 10,
            contents: ""
        )
    private(set) var registrations:
        [(FlowTabUITestConditionObservationSource) -> Void] = []
    private var activeRegistrationIndices: Set<Int> = []
    private(set) var cancellationCount = 0

    func register(
        _ callback: @escaping (
            FlowTabUITestConditionObservationSource
        ) -> Void
    ) -> FlowTabUITestObservationCancellation? {
        let index = registrations.count
        registrations.append(callback)
        activeRegistrationIndices.insert(index)
        return FlowTabUITestObservationCancellation {
            [weak self] in
            guard let self,
                  activeRegistrationIndices.remove(index) != nil
            else {
                return
            }
            cancellationCount += 1
        }
    }

    func replaceContents(
        _ contents: String,
        fileEventGeneration: UInt64
    ) {
        snapshot = FlowTabUITestRuntimeLogSnapshot(
            baselineFileEventGeneration: 10,
            fileEventGeneration: fileEventGeneration,
            contents: contents
        )
    }

    func notifyActiveRegistrations() {
        for index in activeRegistrationIndices.sorted() {
            registrations[index](.notificationReadback)
        }
    }

    func notifyRegistration(at index: Int) {
        registrations[index](.notificationReadback)
    }
}

extension FlowTabUITests {
    func testPostTerminationRefreshPolicyAndParserRequireExactRecord() {
        let watchdog =
            SpaceFixturePostTerminationRefreshObservationPolicy
                .evidenceWatchdog
        XCTAssertEqual(watchdog, 10)
        XCTAssertTrue(watchdog.isFinite && watchdog > 0)

        let exact = postTerminationRefreshEvidence(
            generation: 17
        )
        let exactLine = postTerminationRefreshLogLine(
            generation: 17
        )
        XCTAssertEqual(
            SpaceFixturePostTerminationRefreshEvidence.records(
                in: exactLine
            ),
            [exact]
        )
        XCTAssertTrue(
            SpaceFixturePostTerminationRefreshEvidence.records(
                in:
                    "terminate post-refresh reason=workspace_notification "
                    + "appID=io.github.flowtab.fixture\n"
                    + "pid=4321 matchedPending=1 "
                    + "pendingGeneration=17 refreshed=true\n"
            ).isEmpty
        )
        XCTAssertTrue(
            SpaceFixturePostTerminationRefreshEvidence.records(
                in: exactLine.dropLast() + " extra=1\n"
            ).isEmpty
        )
    }

    func testPostTerminationRefreshUsesRecordObservedBeforeTargetBinding() {
        let source =
            ManualSpaceFixturePostTerminationRefreshLogSource()
        source.replaceContents(
            postTerminationRefreshLogLine(generation: 19),
            fileEventGeneration: 11
        )
        let owner = makePostTerminationRefreshObservationOwner(
            source: source
        )
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(owner.resolvedEvidence)
        owner.bindTarget(
            processIdentifier: 4_321,
            requestGeneration: 19
        )

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .triggerReadback
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value,
            postTerminationRefreshEvidence(generation: 19)
        )
        owner.cancel()
        owner.cancel()
        XCTAssertEqual(source.cancellationCount, 1)
    }

    func testPostTerminationRefreshWaitsForExactEventAfterOutOfOrderRecords() {
        let source =
            ManualSpaceFixturePostTerminationRefreshLogSource()
        let owner = makePostTerminationRefreshObservationOwner(
            source: source
        )
        owner.start()
        defer { owner.cancel() }
        owner.bindTarget(
            processIdentifier: 4_321,
            requestGeneration: 23
        )
        let wrongRecords = [
            postTerminationRefreshLogLine(
                reason: "manual",
                generation: 23
            ),
            postTerminationRefreshLogLine(
                bundleIdentifier: "io.github.flowtab.other",
                generation: 23
            ),
            postTerminationRefreshLogLine(
                processIdentifier: 4_322,
                generation: 23
            ),
            postTerminationRefreshLogLine(
                matchedPending: false,
                generation: 23
            ),
            postTerminationRefreshLogLine(generation: 22),
            postTerminationRefreshLogLine(
                generation: 23,
                refreshed: false
            )
        ].joined()
        source.replaceContents(
            wrongRecords,
            fileEventGeneration: 11
        )
        source.notifyActiveRegistrations()
        XCTAssertNil(owner.resolvedEvidence)

        DispatchQueue.main.async {
            let exact = self.postTerminationRefreshLogLine(
                generation: 23
            )
            source.replaceContents(
                wrongRecords + exact + exact,
                fileEventGeneration: 12
            )
            source.notifyActiveRegistrations()
        }

        let evidence = owner.waitForResolution(
            timeout:
                SpaceFixturePostTerminationRefreshObservationTestPolicy
                    .eventWatchdog
        )
        XCTAssertEqual(evidence?.source, .notificationReadback)
        XCTAssertEqual(
            evidence?.value,
            postTerminationRefreshEvidence(generation: 23)
        )
    }

    func testPostTerminationRefreshSlowSchedulingChangesOnlyEvidenceLatency() {
        let source =
            ManualSpaceFixturePostTerminationRefreshLogSource()
        let owner = makePostTerminationRefreshObservationOwner(
            source: source
        )
        owner.start()
        defer { owner.cancel() }
        owner.bindTarget(
            processIdentifier: 4_321,
            requestGeneration: 29
        )

        DispatchQueue.main.asyncAfter(
            deadline: .now()
                + SpaceFixturePostTerminationRefreshObservationTestPolicy
                    .slowEvidenceInjectionLatency
        ) {
            source.replaceContents(
                self.postTerminationRefreshLogLine(
                    generation: 29
                ),
                fileEventGeneration: 11
            )
            source.notifyActiveRegistrations()
        }

        XCTAssertEqual(
            owner.waitForResolution(
                timeout:
                    SpaceFixturePostTerminationRefreshObservationTestPolicy
                        .eventWatchdog
            )?.value,
            postTerminationRefreshEvidence(generation: 29)
        )
    }

    func testPostTerminationRefreshCancellationRejectsLaterEvent() {
        let source =
            ManualSpaceFixturePostTerminationRefreshLogSource()
        let owner = makePostTerminationRefreshObservationOwner(
            source: source
        )
        owner.start()
        owner.bindTarget(
            processIdentifier: 4_321,
            requestGeneration: 31
        )

        owner.cancel()
        source.replaceContents(
            postTerminationRefreshLogLine(generation: 31),
            fileEventGeneration: 11
        )
        source.notifyRegistration(at: 0)

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    SpaceFixturePostTerminationRefreshObservationTestPolicy
                        .eventWatchdog
            )
        )
        XCTAssertEqual(source.cancellationCount, 1)
    }

    func testPostTerminationRefreshWatchdogReportsLastObservedEvidence() {
        let source =
            ManualSpaceFixturePostTerminationRefreshLogSource()
        source.replaceContents(
            postTerminationRefreshLogLine(
                matchedPending: false,
                generation: 36,
                refreshed: false
            ),
            fileEventGeneration: 11
        )
        let owner = makePostTerminationRefreshObservationOwner(
            source: source
        )
        owner.start()
        defer { owner.cancel() }
        owner.bindTarget(
            processIdentifier: 4_321,
            requestGeneration: 37
        )

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    SpaceFixturePostTerminationRefreshObservationTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "expectedPID=4321"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "expectedPendingGeneration=37"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "matchedPending=0 pendingGeneration=36 refreshed=false"
            )
        )
    }

    func testPostTerminationRefreshRejectsStaleCallbacksUnderPressure() {
        for iteration in
            0..<SpaceFixturePostTerminationRefreshObservationTestPolicy
                .pressureIterations
        {
            let source =
                ManualSpaceFixturePostTerminationRefreshLogSource()
            let owner = makePostTerminationRefreshObservationOwner(
                source: source
            )
            let staleGeneration = iteration * 2 + 1
            let currentGeneration = staleGeneration + 1
            owner.start()
            owner.bindTarget(
                processIdentifier: 4_321,
                requestGeneration: staleGeneration
            )
            owner.cancel()
            owner.start()
            owner.bindTarget(
                processIdentifier: 4_322,
                requestGeneration: currentGeneration
            )

            source.replaceContents(
                postTerminationRefreshLogLine(
                    processIdentifier: 4_321,
                    generation: staleGeneration
                ),
                fileEventGeneration: 11
            )
            source.notifyRegistration(at: 0)
            XCTAssertNil(
                owner.resolvedEvidence,
                "iteration=\(iteration)"
            )

            source.replaceContents(
                postTerminationRefreshLogLine(
                    processIdentifier: 4_322,
                    generation: currentGeneration
                ),
                fileEventGeneration: 12
            )
            source.notifyActiveRegistrations()
            XCTAssertEqual(
                owner.resolvedEvidence?.value,
                postTerminationRefreshEvidence(
                    processIdentifier: 4_322,
                    generation: currentGeneration
                ),
                "iteration=\(iteration)"
            )
            owner.cancel()
            XCTAssertEqual(
                source.cancellationCount,
                2,
                "iteration=\(iteration)"
            )
        }
    }

    private func makePostTerminationRefreshObservationOwner(
        source: ManualSpaceFixturePostTerminationRefreshLogSource
    ) -> SpaceFixturePostTerminationRefreshObservationOwner {
        SpaceFixturePostTerminationRefreshObservationOwner(
            bundleIdentifier: "io.github.flowtab.fixture",
            observationRegistration: source.register,
            readback: { source.snapshot }
        )
    }

    private func postTerminationRefreshEvidence(
        reason: String = "workspace_notification",
        bundleIdentifier: String = "io.github.flowtab.fixture",
        processIdentifier: pid_t = 4_321,
        matchedPending: Bool = true,
        generation: Int?,
        refreshed: Bool = true
    ) -> SpaceFixturePostTerminationRefreshEvidence {
        SpaceFixturePostTerminationRefreshEvidence(
            reason: reason,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier,
            matchedPending: matchedPending,
            pendingGeneration: generation,
            refreshed: refreshed
        )
    }

    private func postTerminationRefreshLogLine(
        reason: String = "workspace_notification",
        bundleIdentifier: String = "io.github.flowtab.fixture",
        processIdentifier: pid_t = 4_321,
        matchedPending: Bool = true,
        generation: Int?,
        refreshed: Bool = true
    ) -> String {
        "[INFO] [Session] terminate post-refresh "
            + "reason=\(reason) appID=\(bundleIdentifier) "
            + "pid=\(processIdentifier) "
            + "matchedPending=\(matchedPending ? 1 : 0) "
            + "pendingGeneration="
            + "\(generation.map(String.init) ?? "nil") "
            + "refreshed=\(refreshed)\n"
    }
}
