import Foundation
import XCTest

private enum SpaceFixtureFocusedPublicStateObservationTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let eventWatchdog: TimeInterval = 1
    static let slowEvidenceLatency: TimeInterval = 0.05
    static let pressureIterations = 200
}

private final class ManualFocusedPublicStateLogSource {
    private(set) var snapshot = FlowTabUITestRuntimeLogSnapshot(
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
    func testFocusedPublicStatePolicyAndParserRequireExactEvidence() {
        let watchdog =
            SpaceFixtureFocusedPublicStateObservationPolicy
                .evidenceWatchdog
        XCTAssertEqual(watchdog, 8)
        XCTAssertTrue(watchdog.isFinite && watchdog > 0)

        XCTAssertEqual(
            SpaceFixtureFocusedPublicStateEvidence.records(
                in: focusedPublicStateTieBreakLine()
            ),
            [focusedPublicStateEvidence(source: .focusedTieBreak)]
        )
        XCTAssertEqual(
            SpaceFixtureFocusedPublicStateEvidence.records(
                in: focusedPublicExactBindingLines()
            ),
            [focusedPublicStateEvidence(source: .publicExactBinding)]
        )
        XCTAssertEqual(
            SpaceFixtureFocusedPublicStateEvidence.records(
                in: focusedPublicExactBindingLines(
                    sourceTransition: "none->publicExactMatch",
                    confidenceTransition: "provisional->exact"
                )
            ),
            [focusedPublicStateEvidence(source: .publicExactBinding)]
        )
        XCTAssertTrue(
            SpaceFixtureFocusedPublicStateEvidence.records(
                in: focusedPublicStateTieBreakLine(state: "main")
            ).isEmpty
        )
        XCTAssertTrue(
            SpaceFixtureFocusedPublicStateEvidence.records(
                in: focusedPublicExactBindingLines(
                    sourceTransition:
                        "privateExactBridge->stickyBinding"
                )
            ).isEmpty
        )
        XCTAssertTrue(
            SpaceFixtureFocusedPublicStateEvidence.records(
                in: focusedPublicExactBindingLines(
                    confidenceTransition: "inferred->sticky"
                )
            ).isEmpty
        )
    }

    func testFocusedPublicStateUsesEvidenceObservedBeforePIDBinding() {
        let source = ManualFocusedPublicStateLogSource()
        source.replaceContents(
            focusedPublicStateTieBreakLine(),
            fileEventGeneration: 11
        )
        let owner = makeFocusedPublicStateOwner(source: source)
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(owner.resolvedEvidence)
        owner.bindTarget(processIdentifier: 4_321)

        XCTAssertEqual(owner.resolvedEvidence?.source, .triggerReadback)
        XCTAssertEqual(
            owner.resolvedEvidence?.value,
            focusedPublicStateEvidence(source: .focusedTieBreak)
        )
        owner.cancel()
        owner.cancel()
        XCTAssertEqual(source.cancellationCount, 1)
    }

    func testFocusedPublicStateWaitsForExactPIDEvent() {
        let source = ManualFocusedPublicStateLogSource()
        let owner = makeFocusedPublicStateOwner(source: source)
        owner.start()
        defer { owner.cancel() }
        owner.bindTarget(processIdentifier: 4_321)

        source.replaceContents(
            focusedPublicStateTieBreakLine(
                processIdentifier: 4_322
            ),
            fileEventGeneration: 11
        )
        source.notifyActiveRegistrations()
        XCTAssertNil(owner.resolvedEvidence)

        source.replaceContents(
            focusedPublicStateTieBreakLine(),
            fileEventGeneration: 12
        )
        source.notifyActiveRegistrations()
        XCTAssertEqual(
            owner.resolvedEvidence?.value,
            focusedPublicStateEvidence(source: .focusedTieBreak)
        )
    }

    func testFocusedPublicStateResolvesAfterLogFileReplacement() {
        let source = ManualFocusedPublicStateLogSource()
        let owner = makeFocusedPublicStateOwner(source: source)
        owner.start()
        defer { owner.cancel() }
        owner.bindTarget(processIdentifier: 4_321)

        source.replaceContents(
            focusedPublicExactBindingLines(),
            fileEventGeneration: 27
        )
        source.notifyActiveRegistrations()

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .notificationReadback
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value,
            focusedPublicStateEvidence(source: .publicExactBinding)
        )
    }

    func testFocusedPublicStateSlowSchedulingOnlyChangesLatency() {
        let source = ManualFocusedPublicStateLogSource()
        let owner = makeFocusedPublicStateOwner(source: source)
        owner.start()
        defer { owner.cancel() }
        owner.bindTarget(processIdentifier: 4_321)

        DispatchQueue.main.asyncAfter(
            deadline: .now()
                + SpaceFixtureFocusedPublicStateObservationTestPolicy
                    .slowEvidenceLatency
        ) {
            source.replaceContents(
                self.focusedPublicExactBindingLines(),
                fileEventGeneration: 11
            )
            source.notifyActiveRegistrations()
        }

        XCTAssertEqual(
            owner.waitForResolution(
                timeout:
                    SpaceFixtureFocusedPublicStateObservationTestPolicy
                        .eventWatchdog
            )?.value,
            focusedPublicStateEvidence(source: .publicExactBinding)
        )
    }

    func testFocusedPublicStateCancellationRejectsLaterEvent() {
        let source = ManualFocusedPublicStateLogSource()
        let owner = makeFocusedPublicStateOwner(source: source)
        owner.start()
        owner.bindTarget(processIdentifier: 4_321)
        owner.cancel()

        source.replaceContents(
            focusedPublicStateTieBreakLine(),
            fileEventGeneration: 11
        )
        source.notifyRegistration(at: 0)

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    SpaceFixtureFocusedPublicStateObservationTestPolicy
                        .eventWatchdog
            )
        )
        XCTAssertEqual(source.cancellationCount, 1)
    }

    func testFocusedPublicStateWatchdogReportsLastEvidence() {
        let source = ManualFocusedPublicStateLogSource()
        source.replaceContents(
            focusedPublicStateTieBreakLine(
                processIdentifier: 4_322
            ),
            fileEventGeneration: 11
        )
        let owner = makeFocusedPublicStateOwner(source: source)
        owner.start()
        defer { owner.cancel() }
        owner.bindTarget(processIdentifier: 4_321)

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    SpaceFixtureFocusedPublicStateObservationTestPolicy
                        .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "expectedAppID=com.example.fixture.chrome"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("expectedPID=4321")
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "source=watchdogReadback"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("pid=4322")
        )
    }

    func testFocusedPublicStateRejectsStaleCallbacksUnderPressure() {
        for iteration in
            0..<SpaceFixtureFocusedPublicStateObservationTestPolicy
                .pressureIterations
        {
            let source = ManualFocusedPublicStateLogSource()
            let owner = makeFocusedPublicStateOwner(source: source)
            owner.start()
            owner.bindTarget(processIdentifier: 4_321)
            owner.cancel()
            owner.start()
            owner.bindTarget(processIdentifier: 4_322)

            source.replaceContents(
                focusedPublicStateTieBreakLine(
                    processIdentifier: 4_321
                ),
                fileEventGeneration: 11
            )
            source.notifyRegistration(at: 0)
            XCTAssertNil(
                owner.resolvedEvidence,
                "iteration=\(iteration)"
            )

            source.replaceContents(
                focusedPublicStateTieBreakLine(
                    processIdentifier: 4_322
                ),
                fileEventGeneration: 12
            )
            source.notifyActiveRegistrations()
            XCTAssertEqual(
                owner.resolvedEvidence?.value,
                focusedPublicStateEvidence(
                    processIdentifier: 4_322,
                    source: .focusedTieBreak
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

    private func makeFocusedPublicStateOwner(
        source: ManualFocusedPublicStateLogSource
    ) -> SpaceFixtureFocusedPublicStateObservationOwner {
        SpaceFixtureFocusedPublicStateObservationOwner(
            bundleIdentifier: "com.example.fixture.chrome",
            observationRegistration: source.register,
            readback: { source.snapshot }
        )
    }

    private func focusedPublicStateEvidence(
        processIdentifier: pid_t = 4_321,
        cgWindowID: UInt32 = 7_654,
        source: SpaceFixtureFocusedPublicStateEvidenceSource
    ) -> SpaceFixtureFocusedPublicStateEvidence {
        SpaceFixtureFocusedPublicStateEvidence(
            processIdentifier: processIdentifier,
            axWindowID: "ax:\(processIdentifier):0",
            cgWindowID: cgWindowID,
            source: source
        )
    }

    private func focusedPublicStateTieBreakLine(
        state: String = "focused",
        processIdentifier: pid_t = 4_321,
        cgWindowID: UInt32 = 7_654
    ) -> String {
        "[DEBUG] [AXMatch] binding-assignment "
            + "public-state-tiebreak state=\(state) "
            + "ax=ax:\(processIdentifier):0 "
            + "cg=\(cgWindowID) axCandidates=2 cgCandidates=2\n"
    }

    private func focusedPublicExactBindingLines(
        processIdentifier: pid_t = 4_321,
        cgWindowID: UInt32 = 7_654,
        sourceTransition: String =
            "publicExactMatch->stickyBinding",
        confidenceTransition: String = "exact->sticky"
    ) -> String {
        let nextCGWindowID = cgWindowID + 1
        return "[DEBUG] [RuntimeFacts] chrome-topology "
            + "app=Chrome Fixture pid=\(processIdentifier) "
            + "ax=[ax:\(processIdentifier):0:Shared Docs:"
            + "frame=384,258,960x640:bridgeCG=\(cgWindowID):"
            + "min=0:focused=1:main=1,"
            + "ax:\(processIdentifier):1:Shared Docs:"
            + "frame=384,258,960x640:bridgeCG=\(nextCGWindowID):"
            + "min=1:focused=0:main=0] cg=[]\n"
            + "[DEBUG] [AXMatch] binding-confidence-change "
            + "windowID=cg:\(processIdentifier):\(cgWindowID) "
            + "cg=\(cgWindowID) ax=ax:\(processIdentifier):0 "
            + "confidence=\(confidenceTransition) "
            + "source=\(sourceTransition) "
            + "verifiedFocusFallbackAX=0\n"
    }
}
