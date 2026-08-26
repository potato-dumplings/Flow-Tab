import Foundation
import XCTest

enum SpaceFixtureCurrentAppProjectionAcceptancePolicy {
    static let baselineWatchdog: TimeInterval = 8
    static let terminalWatchdog: TimeInterval = 15
    static let readbackCadence: TimeInterval = 0.1
}

struct SpaceFixtureCurrentAppProjectionAcceptanceRoute:
    Equatable
{
    let notificationName: Notification.Name
    let readbackURL: URL
    let bundleIdentifier: String

    var flowTabLaunchArguments: [String] {
        [
            "--flowtab-ui-current-app-projection-evidence-route",
            notificationName.rawValue,
            bundleIdentifier,
            readbackURL.path
        ]
    }

    func removeReadback() {
        try? FileManager.default.removeItem(at: readbackURL)
    }
}

struct SpaceFixtureCurrentAppProjectionSourceGeneration:
    Codable,
    Equatable
{
    let appLifecycle: UInt64
    let cg: UInt64
    let space: UInt64
    let axDirty: UInt64
    let projection: UInt64

    func isStrictlyLater(
        than other:
            SpaceFixtureCurrentAppProjectionSourceGeneration
    ) -> Bool {
        appLifecycle >= other.appLifecycle
            && cg >= other.cg
            && space >= other.space
            && axDirty >= other.axDirty
            && projection >= other.projection
            && self != other
    }

    var diagnosticSummary: String {
        "app=\(appLifecycle),cg=\(cg),space=\(space),"
            + "ax=\(axDirty),projection=\(projection)"
    }
}

struct SpaceFixtureCurrentAppProjectionAcceptanceEvidence:
    Codable,
    Equatable
{
    let evidenceGeneration: UInt64
    let bundleIdentifier: String
    let appID: String
    let processIdentifier: pid_t
    let windowIDs: [String]
    let isCompleteForScope: Bool
    let sourceGeneration:
        SpaceFixtureCurrentAppProjectionSourceGeneration

    var diagnosticSummary: String {
        "evidenceGeneration=\(evidenceGeneration) "
            + "bundleID=\(bundleIdentifier) "
            + "appID=\(appID) pid=\(processIdentifier) "
            + "windows=\(windowIDs) "
            + "complete=\(isCompleteForScope ? 1 : 0) "
            + "sourceGeneration={"
            + sourceGeneration.diagnosticSummary
            + "}"
    }
}

struct SpaceFixtureCurrentAppProjectionEvidenceReadback {
    let path: String
    let fileExists: Bool
    let evidence:
        SpaceFixtureCurrentAppProjectionAcceptanceEvidence?
    let errorDescription: String?

    static func read(
        from url: URL
    ) -> Self {
        guard FileManager.default.fileExists(
            atPath: url.path
        ) else {
            return Self(
                path: url.path,
                fileExists: false,
                evidence: nil,
                errorDescription: nil
            )
        }
        do {
            return Self(
                path: url.path,
                fileExists: true,
                evidence: try JSONDecoder().decode(
                    SpaceFixtureCurrentAppProjectionAcceptanceEvidence
                        .self,
                    from: Data(contentsOf: url)
                ),
                errorDescription: nil
            )
        } catch {
            return Self(
                path: url.path,
                fileExists: true,
                evidence: nil,
                errorDescription: String(describing: error)
            )
        }
    }

    var diagnosticSummary: String {
        if let evidence {
            return "path=\(path) \(evidence.diagnosticSummary)"
        }
        return "path=\(path) fileExists=\(fileExists) "
            + "error=\(errorDescription ?? "nil")"
    }
}

struct SpaceFixtureCurrentAppProjectionAcceptanceSnapshot {
    let baseline:
        SpaceFixtureCurrentAppProjectionAcceptanceEvidence?
    let lastObserved:
        SpaceFixtureCurrentAppProjectionAcceptanceEvidence?
    let accepted:
        SpaceFixtureCurrentAppProjectionAcceptanceEvidence?
    let lastReadback:
        SpaceFixtureCurrentAppProjectionEvidenceReadback?

    var diagnosticSummary: String {
        "baseline={"
            + (baseline?.diagnosticSummary ?? "unobserved")
            + "} accepted={"
            + (accepted?.diagnosticSummary ?? "unobserved")
            + "} lastObserved={"
            + (lastObserved?.diagnosticSummary ?? "unobserved")
            + "} readback={"
            + (lastReadback?.diagnosticSummary ?? "unobserved")
            + "}"
    }
}

struct SpaceFixtureCurrentAppProjectionAcceptanceExpectation:
    Equatable
{
    enum Mutation: Equatable {
        case created
        case closed
        case closedWithSurvivorRebind
    }

    let baselineWindowCount: Int
    let targetWindowCount: Int
    let mutation: Mutation

    static let closedTwoToOne = Self(
        baselineWindowCount: 2,
        targetWindowCount: 1,
        mutation: .closed
    )

    static let createdTwoToThree = Self(
        baselineWindowCount: 2,
        targetWindowCount: 3,
        mutation: .created
    )

    static let closedThreeToTwo = Self(
        baselineWindowCount: 3,
        targetWindowCount: 2,
        mutation: .closedWithSurvivorRebind
    )
}

final class SpaceFixtureCurrentAppProjectionAcceptanceState {
    enum Phase {
        case baseline
        case target
    }

    private var nextGeneration: UInt64 = 1
    private var activeGeneration: UInt64?
    private var baseline:
        SpaceFixtureCurrentAppProjectionAcceptanceEvidence?
    private var lastObserved:
        SpaceFixtureCurrentAppProjectionAcceptanceEvidence?
    private var accepted:
        SpaceFixtureCurrentAppProjectionAcceptanceEvidence?
    private var lastReadback:
        SpaceFixtureCurrentAppProjectionEvidenceReadback?

    func beginBaseline() -> UInt64 {
        baseline = nil
        lastObserved = nil
        accepted = nil
        lastReadback = nil
        return beginPhase()
    }

    func beginTarget() -> UInt64? {
        guard baseline != nil else { return nil }
        return beginPhase()
    }

    func cancel() {
        activeGeneration = nil
    }

    @discardableResult
    func observe(
        _ evidence:
            SpaceFixtureCurrentAppProjectionAcceptanceEvidence,
        phase: Phase,
        route:
            SpaceFixtureCurrentAppProjectionAcceptanceRoute,
        expectedPID: pid_t,
        expectation:
            SpaceFixtureCurrentAppProjectionAcceptanceExpectation =
                .closedTwoToOne,
        generation: UInt64
    ) -> Bool {
        guard activeGeneration == generation else {
            return false
        }
        lastObserved = evidence
        guard exactIdentity(
            evidence,
            route: route,
            expectedPID: expectedPID
        ),
        evidence.isCompleteForScope,
        Set(evidence.windowIDs).count
            == evidence.windowIDs.count
        else {
            return false
        }
        switch phase {
        case .baseline:
            guard evidence.windowIDs.count
                    == expectation.baselineWindowCount
            else {
                return false
            }
            baseline = evidence
            return true
        case .target:
            guard accepted == nil,
                  let baseline,
                  evidence.evidenceGeneration
                    > baseline.evidenceGeneration,
                  evidence.sourceGeneration
                    .isStrictlyLater(
                        than: baseline.sourceGeneration
                    ),
                  evidence.windowIDs.count
                    == expectation.targetWindowCount,
                  acceptsMutation(
                    expectation.mutation,
                    baselineWindowIDs: baseline.windowIDs,
                    targetWindowIDs: evidence.windowIDs
                  )
            else {
                return false
            }
            accepted = evidence
            return true
        }
    }

    func recordReadback(
        _ readback:
            SpaceFixtureCurrentAppProjectionEvidenceReadback,
        phase: Phase,
        route:
            SpaceFixtureCurrentAppProjectionAcceptanceRoute,
        expectedPID: pid_t,
        expectation:
            SpaceFixtureCurrentAppProjectionAcceptanceExpectation =
                .closedTwoToOne,
        generation: UInt64
    ) {
        guard activeGeneration == generation else { return }
        lastReadback = readback
        if let evidence = readback.evidence {
            _ = observe(
                evidence,
                phase: phase,
                route: route,
                expectedPID: expectedPID,
                expectation: expectation,
                generation: generation
            )
        }
    }

    var snapshot:
        SpaceFixtureCurrentAppProjectionAcceptanceSnapshot
    {
        SpaceFixtureCurrentAppProjectionAcceptanceSnapshot(
            baseline: baseline,
            lastObserved: lastObserved,
            accepted: accepted,
            lastReadback: lastReadback
        )
    }

    private func beginPhase() -> UInt64 {
        let generation = nextGeneration
        nextGeneration &+= 1
        activeGeneration = generation
        return generation
    }

    private func acceptsMutation(
        _ mutation:
            SpaceFixtureCurrentAppProjectionAcceptanceExpectation
                .Mutation,
        baselineWindowIDs: [String],
        targetWindowIDs: [String]
    ) -> Bool {
        let baseline = Set(baselineWindowIDs)
        let target = Set(targetWindowIDs)
        switch mutation {
        case .created:
            return baseline.isSubset(of: target)
                && target.count - baseline.count == 1
        case .closed:
            return target.isSubset(of: baseline)
                && baseline.count - target.count == 1
        case .closedWithSurvivorRebind:
            return !baseline.isDisjoint(with: target)
                && !baseline.subtracting(target).isEmpty
                && !target.subtracting(baseline).isEmpty
        }
    }

    private func exactIdentity(
        _ evidence:
            SpaceFixtureCurrentAppProjectionAcceptanceEvidence,
        route:
            SpaceFixtureCurrentAppProjectionAcceptanceRoute,
        expectedPID: pid_t
    ) -> Bool {
        evidence.bundleIdentifier == route.bundleIdentifier
            && evidence.appID == route.bundleIdentifier
            && evidence.processIdentifier == expectedPID
    }
}

typealias SpaceFixtureCurrentAppProjectionEventRegistration =
    (
        @escaping (
            SpaceFixtureCurrentAppProjectionAcceptanceEvidence
        ) -> Void
    ) -> FlowTabUITestObservationCancellation?

final class SpaceFixtureCurrentAppProjectionAcceptanceOwner {
    private let route:
        SpaceFixtureCurrentAppProjectionAcceptanceRoute
    private let expectedPID: pid_t
    private let expectation:
        SpaceFixtureCurrentAppProjectionAcceptanceExpectation
    private let eventRegistration:
        SpaceFixtureCurrentAppProjectionEventRegistration
    private let scheduledRegistration:
        FlowTabUITestConditionObservationRegistration
    private let evidenceReadback:
        () -> SpaceFixtureCurrentAppProjectionEvidenceReadback
    private let state =
        SpaceFixtureCurrentAppProjectionAcceptanceState()
    private var baselineOwner:
        FlowTabUITestConditionObservationOwner<
            SpaceFixtureCurrentAppProjectionAcceptanceSnapshot
        >?
    private var targetOwner:
        FlowTabUITestConditionObservationOwner<
            SpaceFixtureCurrentAppProjectionAcceptanceSnapshot
        >?

    init(
        route:
            SpaceFixtureCurrentAppProjectionAcceptanceRoute,
        expectedPID: pid_t,
        expectation:
            SpaceFixtureCurrentAppProjectionAcceptanceExpectation =
                .closedTwoToOne,
        center: DistributedNotificationCenter = .default(),
        eventRegistration:
            SpaceFixtureCurrentAppProjectionEventRegistration? = nil,
        scheduledRegistration:
            FlowTabUITestConditionObservationRegistration? = nil,
        evidenceReadback:
            (() -> SpaceFixtureCurrentAppProjectionEvidenceReadback)? = nil
    ) {
        self.route = route
        self.expectedPID = expectedPID
        self.expectation = expectation
        self.eventRegistration = eventRegistration
            ?? Self.distributedRegistration(
                route: route,
                center: center
            )
        self.scheduledRegistration = scheduledRegistration
            ?? FlowTabUITestConditionReadbackScheduler
                .mainRunLoopRegistration(
                    cadence:
                        SpaceFixtureCurrentAppProjectionAcceptancePolicy
                            .readbackCadence
                )
        self.evidenceReadback = evidenceReadback
            ?? {
                SpaceFixtureCurrentAppProjectionEvidenceReadback
                    .read(from: route.readbackURL)
            }
    }

    func start() {
        cancel()
        let generation = state.beginBaseline()
        baselineOwner = makeOwner(
            phase: .baseline,
            generation: generation
        )
        baselineOwner?.start()
    }

    func waitForBaseline(
        timeout: TimeInterval =
            SpaceFixtureCurrentAppProjectionAcceptancePolicy
                .baselineWatchdog
    ) -> SpaceFixtureCurrentAppProjectionAcceptanceEvidence? {
        baselineOwner?
            .waitForResolution(timeout: timeout)?
            .value.baseline
    }

    func startTargetObservation() -> Bool {
        baselineOwner?.cancel()
        baselineOwner = nil
        guard let generation = state.beginTarget() else {
            return false
        }
        targetOwner = makeOwner(
            phase: .target,
            generation: generation
        )
        targetOwner?.start()
        return true
    }

    func waitForAcceptedProjection(
        timeout: TimeInterval =
            SpaceFixtureCurrentAppProjectionAcceptancePolicy
                .terminalWatchdog
    ) -> SpaceFixtureCurrentAppProjectionAcceptanceEvidence? {
        targetOwner?
            .waitForResolution(timeout: timeout)?
            .value.accepted
    }

    var diagnosticSummary: String {
        "expectedBundleID=\(route.bundleIdentifier) "
            + "expectedPID=\(expectedPID) baselineOwner={"
            + (baselineOwner?.diagnosticSummary ?? "inactive")
            + "} targetOwner={"
            + (targetOwner?.diagnosticSummary ?? "inactive")
            + "} state={\(state.snapshot.diagnosticSummary)}"
    }

    func cancel() {
        state.cancel()
        baselineOwner?.cancel()
        targetOwner?.cancel()
        baselineOwner = nil
        targetOwner = nil
    }

    deinit {
        cancel()
    }

    static func evidence(
        from notification: Notification
    ) -> SpaceFixtureCurrentAppProjectionAcceptanceEvidence? {
        let info = notification.userInfo
        guard let evidenceGeneration =
                (info?["evidenceGeneration"] as? NSNumber)?
                    .uint64Value,
              evidenceGeneration > 0,
              let bundleIdentifier =
                info?["bundleIdentifier"] as? String,
              !bundleIdentifier.isEmpty,
              let appID = info?["appID"] as? String,
              !appID.isEmpty,
              let processIdentifier =
                (info?["processIdentifier"] as? NSNumber)?
                    .int32Value,
              processIdentifier > 0,
              let windowIDs = info?["windowIDs"] as? [String],
              let isCompleteForScope =
                (info?["isCompleteForScope"] as? NSNumber)?
                    .boolValue,
              let appLifecycle =
                (info?["appLifecycleGeneration"] as? NSNumber)?
                    .uint64Value,
              let cg = (info?["cgGeneration"] as? NSNumber)?
                .uint64Value,
              let space =
                (info?["spaceGeneration"] as? NSNumber)?
                    .uint64Value,
              let axDirty =
                (info?["axDirtyGeneration"] as? NSNumber)?
                    .uint64Value,
              let projection =
                (info?["projectionGeneration"] as? NSNumber)?
                    .uint64Value
        else {
            return nil
        }
        return SpaceFixtureCurrentAppProjectionAcceptanceEvidence(
            evidenceGeneration: evidenceGeneration,
            bundleIdentifier: bundleIdentifier,
            appID: appID,
            processIdentifier: processIdentifier,
            windowIDs: windowIDs,
            isCompleteForScope: isCompleteForScope,
            sourceGeneration:
                SpaceFixtureCurrentAppProjectionSourceGeneration(
                    appLifecycle: appLifecycle,
                    cg: cg,
                    space: space,
                    axDirty: axDirty,
                    projection: projection
                )
        )
    }

    private func makeOwner(
        phase: SpaceFixtureCurrentAppProjectionAcceptanceState.Phase,
        generation: UInt64
    ) -> FlowTabUITestConditionObservationOwner<
        SpaceFixtureCurrentAppProjectionAcceptanceSnapshot
    > {
        let state = self.state
        let route = self.route
        let expectedPID = self.expectedPID
        let expectation = self.expectation
        let eventRegistration = self.eventRegistration
        let scheduledRegistration = self.scheduledRegistration
        let evidenceReadback = self.evidenceReadback
        return FlowTabUITestConditionObservationOwner(
            observationRegistration: { readback in
                let eventCancellation =
                    eventRegistration { evidence in
                        _ = state.observe(
                            evidence,
                            phase: phase,
                            route: route,
                            expectedPID: expectedPID,
                            expectation: expectation,
                            generation: generation
                        )
                        readback(.notificationReadback)
                    }
                let scheduledCancellation =
                    scheduledRegistration(readback)
                return FlowTabUITestObservationCancellation {
                    eventCancellation?.cancel()
                    scheduledCancellation?.cancel()
                }
            },
            readback: {
                state.recordReadback(
                    evidenceReadback(),
                    phase: phase,
                    route: route,
                    expectedPID: expectedPID,
                    expectation: expectation,
                    generation: generation
                )
                return state.snapshot
            },
            isSatisfied: {
                switch phase {
                case .baseline:
                    $0.baseline != nil
                case .target:
                    $0.accepted != nil
                }
            },
            describe: \.diagnosticSummary
        )
    }

    private static func distributedRegistration(
        route:
            SpaceFixtureCurrentAppProjectionAcceptanceRoute,
        center: DistributedNotificationCenter
    ) -> SpaceFixtureCurrentAppProjectionEventRegistration {
        { callback in
            let token = center.addObserver(
                forName: route.notificationName,
                object: nil,
                queue: .main
            ) { notification in
                guard let evidence = evidence(
                    from: notification
                ) else {
                    return
                }
                callback(evidence)
            }
            return FlowTabUITestObservationCancellation {
                center.removeObserver(token)
            }
        }
    }
}

extension FlowTabUITests {
    func makeSpaceFixtureCurrentAppProjectionAcceptanceRoute(
        bundleIdentifier: String,
        temporaryDirectory: URL =
            FileManager.default.temporaryDirectory
    ) -> SpaceFixtureCurrentAppProjectionAcceptanceRoute {
        let identifier = UUID().uuidString
        return SpaceFixtureCurrentAppProjectionAcceptanceRoute(
            notificationName: Notification.Name(
                "io.github.potato-dumplings.flowtab."
                    + "ui-test.current-app-projection."
                    + identifier
            ),
            readbackURL: temporaryDirectory.appendingPathComponent(
                "flowtab-current-app-projection-\(identifier).json",
                isDirectory: false
            ),
            bundleIdentifier: bundleIdentifier
        )
    }

    @discardableResult
    func assertSpaceFixtureCurrentAppProjectionBaseline(
        from owner:
            SpaceFixtureCurrentAppProjectionAcceptanceOwner,
        identity: SpaceFixtureAppIdentity,
        expectedPID: pid_t
    ) -> Bool {
        guard let baseline = owner.waitForBaseline() else {
            XCTFail(
                "Missing exact two-window projection baseline: "
                    + owner.diagnosticSummary
            )
            return false
        }
        XCTAssertEqual(baseline.bundleIdentifier, identity.bundleIdentifier)
        XCTAssertEqual(baseline.appID, identity.bundleIdentifier)
        XCTAssertEqual(baseline.processIdentifier, expectedPID)
        XCTAssertEqual(baseline.windowIDs.count, 2)
        return true
    }

    @discardableResult
    func assertSpaceFixtureCurrentAppProjectionAccepted(
        by owner:
            SpaceFixtureCurrentAppProjectionAcceptanceOwner,
        identity: SpaceFixtureAppIdentity,
        expectedPID: pid_t
    ) -> Bool {
        guard let evidence =
                owner.waitForAcceptedProjection()
        else {
            XCTFail(
                "Missing exact post-close current-app projection: "
                    + owner.diagnosticSummary
            )
            return false
        }
        XCTAssertEqual(evidence.bundleIdentifier, identity.bundleIdentifier)
        XCTAssertEqual(evidence.appID, identity.bundleIdentifier)
        XCTAssertEqual(evidence.processIdentifier, expectedPID)
        XCTAssertEqual(evidence.windowIDs.count, 1)
        return true
    }
}
