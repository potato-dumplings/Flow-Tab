import Foundation
import XCTest

private enum SpaceFixtureMinimizedAXPropagationTestPolicy {
    static let watchdog: TimeInterval = 0.01
    static let eventWatchdog: TimeInterval = 1
    static let slowEvidenceLatency: TimeInterval = 0.05
    static let pressureIterations = 200
}

private final class ManualMinimizedAXPropagationLogSource {
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
    func testMinimizedAXPropagationPolicyUsesNamedWatchdog() {
        let watchdog =
            SpaceFixtureMinimizedAXPropagationObservationPolicy
            .evidenceWatchdog
        XCTAssertEqual(watchdog, 8)
        XCTAssertTrue(watchdog.isFinite && watchdog > 0)
    }

    func testMinimizedAXPropagationUsesInitialSourceAndPostTriggerProjection() {
        let source = ManualMinimizedAXPropagationLogSource()
        source.replaceContents(
            minimizedAXSourceLine(),
            fileEventGeneration: 11
        )
        let owner = makeMinimizedAXPropagationOwner(source: source)
        owner.start()
        defer { owner.cancel() }

        XCTAssertNil(owner.resolvedEvidence)
        owner.bindTarget(processIdentifier: 4_321)
        XCTAssertNil(owner.resolvedEvidence)
        owner.performPreviewTrigger {
            source.replaceContents(
                self.minimizedAXSourceLine()
                    + self.minimizedAXProjectionLine(),
                fileEventGeneration: 12
            )
            source.notifyActiveRegistrations()
        }

        XCTAssertEqual(
            owner.resolvedEvidence?.source,
            .triggerReadback
        )
        XCTAssertEqual(
            owner.resolvedEvidence?.value,
            minimizedAXPropagationEvidence()
        )
    }

    func testMinimizedAXPropagationRejectsProjectionObservedBeforeTrigger() {
        let source = ManualMinimizedAXPropagationLogSource()
        let preTrigger = minimizedAXSourceLine()
            + minimizedAXProjectionLine(timestamp: "[00:00:00.100]")
        source.replaceContents(preTrigger, fileEventGeneration: 11)
        let owner = makeMinimizedAXPropagationOwner(source: source)
        owner.start()
        defer { owner.cancel() }
        owner.bindTarget(processIdentifier: 4_321)

        owner.performPreviewTrigger {}
        XCTAssertNil(owner.resolvedEvidence)

        source.replaceContents(
            preTrigger
                + minimizedAXProjectionLine(
                    timestamp: "[00:00:00.200]"
                ),
            fileEventGeneration: 12
        )
        source.notifyActiveRegistrations()
        XCTAssertEqual(
            owner.resolvedEvidence?.value,
            minimizedAXPropagationEvidence()
        )
    }

    func testMinimizedAXPropagationRequiresOrderedBoundRecordsDespiteDuplicateEvents() {
        let source = ManualMinimizedAXPropagationLogSource()
        let owner = makeMinimizedAXPropagationOwner(source: source)
        owner.start()
        defer { owner.cancel() }
        owner.bindTarget(processIdentifier: 4_321)
        owner.performPreviewTrigger {}

        let projection = minimizedAXProjectionLine()
        source.replaceContents(projection, fileEventGeneration: 11)
        source.notifyActiveRegistrations()
        source.notifyActiveRegistrations()
        XCTAssertNil(owner.resolvedEvidence)

        let outOfOrder = projection + minimizedAXSourceLine()
        source.replaceContents(outOfOrder, fileEventGeneration: 12)
        source.notifyActiveRegistrations()
        XCTAssertNil(owner.resolvedEvidence)

        source.replaceContents(
            outOfOrder
                + minimizedAXProjectionLine(
                    timestamp: "[00:00:00.300]"
                ),
            fileEventGeneration: 13
        )
        source.notifyActiveRegistrations()
        XCTAssertEqual(
            owner.resolvedEvidence?.value,
            minimizedAXPropagationEvidence()
        )
    }

    func testMinimizedAXPropagationRejectsWrongPIDAndWindowIdentity() {
        let source = ManualMinimizedAXPropagationLogSource()
        let owner = makeMinimizedAXPropagationOwner(source: source)
        owner.start()
        defer { owner.cancel() }
        owner.bindTarget(processIdentifier: 4_321)
        owner.performPreviewTrigger {}

        source.replaceContents(
            minimizedAXSourceLine(processIdentifier: 4_322)
                + minimizedAXProjectionLine(
                    processIdentifier: 4_322
                )
                + minimizedAXSourceLine(cgWindowID: 7_655)
                + minimizedAXProjectionLine(cgWindowID: 7_656),
            fileEventGeneration: 11
        )
        source.notifyActiveRegistrations()
        XCTAssertNil(owner.resolvedEvidence)

        source.replaceContents(
            source.snapshot.contents
                + minimizedAXSourceLine(
                    timestamp: "[00:00:00.400]"
                )
                + minimizedAXProjectionLine(
                    timestamp: "[00:00:00.500]"
                ),
            fileEventGeneration: 12
        )
        source.notifyActiveRegistrations()
        XCTAssertEqual(
            owner.resolvedEvidence?.value,
            minimizedAXPropagationEvidence()
        )
    }

    func testMinimizedAXPropagationRequiresMinimizedSourceAndProjectionState() {
        let source = ManualMinimizedAXPropagationLogSource()
        let owner = makeMinimizedAXPropagationOwner(source: source)
        owner.start()
        defer { owner.cancel() }
        owner.bindTarget(processIdentifier: 4_321)
        owner.performPreviewTrigger {}

        let invalidRecords =
            minimizedAXSourceLine(
                timestamp: "[00:00:00.100]",
                isMinimized: false
            )
            + minimizedAXProjectionLine(
                timestamp: "[00:00:00.200]"
            )
            + minimizedAXSourceLine(
                timestamp: "[00:00:00.300]",
                isOnscreen: true
            )
            + minimizedAXProjectionLine(
                timestamp: "[00:00:00.400]"
            )
            + minimizedAXSourceLine(
                timestamp: "[00:00:00.500]"
            )
            + minimizedAXProjectionLine(
                timestamp: "[00:00:00.600]",
                isMinimized: false
            )
        source.replaceContents(
            invalidRecords,
            fileEventGeneration: 11
        )
        source.notifyActiveRegistrations()
        XCTAssertNil(owner.resolvedEvidence)

        source.replaceContents(
            invalidRecords
                + minimizedAXSourceLine(
                    timestamp: "[00:00:00.700]"
                )
                + minimizedAXProjectionLine(
                    timestamp: "[00:00:00.800]"
                ),
            fileEventGeneration: 12
        )
        source.notifyActiveRegistrations()
        XCTAssertEqual(
            owner.resolvedEvidence?.value,
            minimizedAXPropagationEvidence()
        )
    }

    func testMinimizedAXPropagationCancellationRejectsLaterEvents() {
        let source = ManualMinimizedAXPropagationLogSource()
        let owner = makeMinimizedAXPropagationOwner(source: source)
        owner.start()
        owner.bindTarget(processIdentifier: 4_321)
        owner.performPreviewTrigger {}
        owner.cancel()

        source.replaceContents(
            minimizedAXSourceLine()
                + minimizedAXProjectionLine(),
            fileEventGeneration: 11
        )
        source.notifyRegistration(at: 0)

        XCTAssertNil(owner.resolvedEvidence)
        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    SpaceFixtureMinimizedAXPropagationTestPolicy
                    .eventWatchdog
            )
        )
        XCTAssertEqual(source.cancellationCount, 1)
    }

    func testMinimizedAXPropagationWatchdogReportsBothMissingStages() {
        let source = ManualMinimizedAXPropagationLogSource()
        let owner = makeMinimizedAXPropagationOwner(source: source)
        owner.start()
        defer { owner.cancel() }
        owner.bindTarget(processIdentifier: 4_321)
        owner.performPreviewTrigger {}

        XCTAssertNil(
            owner.waitForResolution(
                timeout:
                    SpaceFixtureMinimizedAXPropagationTestPolicy
                    .watchdog
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "missingSourceEvidence=1"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains(
                "missingPostTriggerProjection=1"
            )
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("expectedPID=4321")
        )
        XCTAssertTrue(
            owner.diagnosticSummary.contains("source=watchdogReadback")
        )
    }

    func testMinimizedAXPropagationSlowSchedulingOnlyChangesLatency() {
        let source = ManualMinimizedAXPropagationLogSource()
        let owner = makeMinimizedAXPropagationOwner(source: source)
        owner.start()
        defer { owner.cancel() }
        owner.bindTarget(processIdentifier: 4_321)
        owner.performPreviewTrigger {}

        DispatchQueue.main.asyncAfter(
            deadline: .now()
                + SpaceFixtureMinimizedAXPropagationTestPolicy
                .slowEvidenceLatency
        ) {
            source.replaceContents(
                self.minimizedAXSourceLine()
                    + self.minimizedAXProjectionLine(),
                fileEventGeneration: 11
            )
            source.notifyActiveRegistrations()
        }

        XCTAssertEqual(
            owner.waitForResolution(
                timeout:
                    SpaceFixtureMinimizedAXPropagationTestPolicy
                    .eventWatchdog
            )?.value,
            minimizedAXPropagationEvidence()
        )
    }

    func testMinimizedAXPropagationRejectsStaleCallbacksUnderPressure() {
        for iteration in
            0..<SpaceFixtureMinimizedAXPropagationTestPolicy
                .pressureIterations
        {
            let source = ManualMinimizedAXPropagationLogSource()
            let owner = makeMinimizedAXPropagationOwner(source: source)
            owner.start()
            owner.bindTarget(processIdentifier: 4_321)
            owner.performPreviewTrigger {}
            owner.cancel()

            owner.start()
            owner.bindTarget(processIdentifier: 4_322)
            owner.performPreviewTrigger {}
            source.replaceContents(
                minimizedAXSourceLine()
                    + minimizedAXProjectionLine(),
                fileEventGeneration: 11
            )
            source.notifyRegistration(at: 0)
            XCTAssertNil(owner.resolvedEvidence, "iteration=\(iteration)")

            source.replaceContents(
                minimizedAXSourceLine(processIdentifier: 4_322)
                    + minimizedAXProjectionLine(
                        processIdentifier: 4_322
                    ),
                fileEventGeneration: 12
            )
            source.notifyActiveRegistrations()
            XCTAssertEqual(
                owner.resolvedEvidence?.value,
                minimizedAXPropagationEvidence(
                    processIdentifier: 4_322
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

    private func makeMinimizedAXPropagationOwner(
        source: ManualMinimizedAXPropagationLogSource
    ) -> SpaceFixtureMinimizedAXPropagationObservationOwner {
        SpaceFixtureMinimizedAXPropagationObservationOwner(
            appName: "Chrome Fixture",
            expectedWindowTitle: "Shared Docs",
            observationRegistration: source.register,
            readback: { source.snapshot }
        )
    }

    private func minimizedAXPropagationEvidence(
        processIdentifier: pid_t = 4_321,
        cgWindowID: UInt32 = 7_654
    ) -> SpaceFixtureMinimizedAXPropagationEvidence {
        SpaceFixtureMinimizedAXPropagationEvidence(
            source: SpaceFixtureMinimizedAXSourceEvidence(
                appName: "Chrome Fixture",
                processIdentifier: processIdentifier,
                axWindowID: "ax:\(processIdentifier):1",
                cgWindowID: cgWindowID,
                title: "Shared Docs"
            ),
            projection: SpaceFixtureMinimizedAXProjectionEvidence(
                appName: "Chrome Fixture",
                processIdentifier: processIdentifier,
                axWindowID: "ax:\(processIdentifier):1",
                cgWindowID: cgWindowID,
                title: "Shared Docs"
            )
        )
    }

    private func minimizedAXSourceLine(
        timestamp: String = "[00:00:00.100]",
        processIdentifier: pid_t = 4_321,
        cgWindowID: UInt32 = 7_654,
        isMinimized: Bool = true,
        isOnscreen: Bool = false
    ) -> String {
        let minimized = isMinimized ? 1 : 0
        let onscreen = isOnscreen ? "on" : "off"
        return timestamp + " [DEBUG] [RuntimeFacts] chrome-topology "
            + "app=Chrome Fixture pid=\(processIdentifier) "
            + "ax=[ax:\(processIdentifier):0:Shared Docs:frame=1,2,3x4:bridgeCG=7653:min=0:focused=1:main=1,"
            + "ax:\(processIdentifier):1:Shared Docs:frame=1,2,3x4:bridgeCG=\(cgWindowID):min=\(minimized):focused=0:main=0] "
            + "cg=[\(cgWindowID):Shared Docs:\(onscreen):spaces=[1]:frame=1,2,3x4]\n"
    }

    private func minimizedAXProjectionLine(
        timestamp: String = "[00:00:00.200]",
        processIdentifier: pid_t = 4_321,
        cgWindowID: UInt32 = 7_654,
        isMinimized: Bool = true,
        isOnscreen: Bool = false
    ) -> String {
        let minimized = isMinimized ? 1 : 0
        let onscreen = isOnscreen ? "on" : "off"
        return timestamp + " [DEBUG] [RuntimeFacts] window-entries "
            + "app=Chrome Fixture pid=\(processIdentifier) ax=2 entries=2 detail=["
            + "0:id=cg:\(processIdentifier):7653:title=Shared Docs:mode=normal:identity=ax:ax:\(processIdentifier):0:handle=ax:\(processIdentifier):0:ax=1:cg=7653:sticky=1:source=publicExactMatch:spaceEvidence=observed:spaces=[1]:on:minimized=0:frame=1,2,3x4,"
            + "1:id=cg:\(processIdentifier):\(cgWindowID):title=Shared Docs:mode=normal:identity=ax:ax:\(processIdentifier):1:handle=ax:\(processIdentifier):1:ax=1:cg=\(cgWindowID):sticky=1:source=publicExactMatch:spaceEvidence=observed:spaces=[1]:\(onscreen):minimized=\(minimized):frame=1,2,3x4]\n"
    }
}
