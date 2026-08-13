import Foundation
import XCTest

enum FlowTabUITestApplicationTerminationPolicy {
    static let watchdogFailureObservationTimeout: TimeInterval = 5
    static let delayedEvidenceOverrideWatchdog: TimeInterval = 9
    static let statusItemMenuQuitWatchdog: TimeInterval = 8
    static let runtimeLifecycleFixtureWatchdog: TimeInterval = 8
}

private enum FlowTabUITestApplicationCleanupTestPolicy {
    static let compatibleWatchdog: TimeInterval = 6
}

protocol FlowTabUITestApplicationTerminationTarget: AnyObject {
    var state: XCUIApplication.State { get }

    func terminate()
    func wait(
        for state: XCUIApplication.State,
        timeout: TimeInterval
    ) -> Bool
}

extension XCUIApplication:
    FlowTabUITestApplicationTerminationTarget
{}

private extension XCUIApplication.State {
    var flowTabTerminationDiagnosticLabel: String {
        switch self {
        case .unknown:
            return "unknown"
        case .notRunning:
            return "notRunning"
        case .runningBackground:
            return "runningBackground"
        case .runningForeground:
            return "runningForeground"
        @unknown default:
            return String(describing: self)
        }
    }
}

struct FlowTabUITestApplicationTerminationEvidence {
    let target: String
    let initialState: XCUIApplication.State
    let didRequestTermination: Bool
    let postTriggerState: XCUIApplication.State
    let waiterCompleted: Bool?
    let finalState: XCUIApplication.State

    var isSatisfied: Bool {
        finalState == .notRunning
    }

    var diagnosticSummary: String {
        "target=\(target) "
            + "initialState="
            + initialState.flowTabTerminationDiagnosticLabel
            + " "
            + "didRequestTermination=\(didRequestTermination) "
            + "postTriggerState="
            + postTriggerState.flowTabTerminationDiagnosticLabel
            + " "
            + "waiterCompleted="
            + (waiterCompleted.map { String($0) }
                ?? "not-needed")
            + " finalState="
            + finalState.flowTabTerminationDiagnosticLabel
    }
}

struct FlowTabUITestApplicationCleanupEvidence {
    let gracefulExit: FlowTabUITestApplicationTerminationEvidence
    let forcedExit: FlowTabUITestApplicationTerminationEvidence?

    var isSatisfied: Bool {
        forcedExit?.isSatisfied ?? gracefulExit.isSatisfied
    }

    var diagnosticSummary: String {
        let forcedSummary = forcedExit?.diagnosticSummary ?? "not-needed"
        return "graceful{\(gracefulExit.diagnosticSummary)} "
            + "forced{\(forcedSummary)}"
    }
}

func observeFlowTabUITestApplicationTermination(
    _ target: any FlowTabUITestApplicationTerminationTarget,
    targetDescription: String,
    timeout: TimeInterval,
    requestTermination: () -> Void
) -> FlowTabUITestApplicationTerminationEvidence {
    let initialState = target.state
    guard initialState != .notRunning else {
        return FlowTabUITestApplicationTerminationEvidence(
            target: targetDescription,
            initialState: initialState,
            didRequestTermination: false,
            postTriggerState: initialState,
            waiterCompleted: nil,
            finalState: initialState
        )
    }

    requestTermination()
    let postTriggerState = target.state
    guard postTriggerState != .notRunning else {
        return FlowTabUITestApplicationTerminationEvidence(
            target: targetDescription,
            initialState: initialState,
            didRequestTermination: true,
            postTriggerState: postTriggerState,
            waiterCompleted: nil,
            finalState: postTriggerState
        )
    }

    let waiterCompleted = target.wait(
        for: .notRunning,
        timeout: timeout
    )
    return FlowTabUITestApplicationTerminationEvidence(
        target: targetDescription,
        initialState: initialState,
        didRequestTermination: true,
        postTriggerState: postTriggerState,
        waiterCompleted: waiterCompleted,
        finalState: target.state
    )
}

func terminateFlowTabUITestApplication(
    _ target: any FlowTabUITestApplicationTerminationTarget,
    targetDescription: String,
    timeout: TimeInterval =
        FlowTabUITestApplicationTerminationPolicy
            .watchdogFailureObservationTimeout
) -> FlowTabUITestApplicationTerminationEvidence {
    observeFlowTabUITestApplicationTermination(
        target,
        targetDescription: targetDescription,
        timeout: timeout
    ) {
        target.terminate()
    }
}

func cleanupFlowTabUITestApplication(
    _ target: any FlowTabUITestApplicationTerminationTarget,
    targetDescription: String,
    gracefulTimeout: TimeInterval,
    forcedTimeout: TimeInterval,
    requestGracefulTermination: () -> Void
) -> FlowTabUITestApplicationCleanupEvidence {
    let gracefulExit = observeFlowTabUITestApplicationTermination(
        target,
        targetDescription: "\(targetDescription):graceful",
        timeout: gracefulTimeout,
        requestTermination: requestGracefulTermination
    )
    guard !gracefulExit.isSatisfied else {
        return FlowTabUITestApplicationCleanupEvidence(
            gracefulExit: gracefulExit,
            forcedExit: nil
        )
    }

    let forcedExit = terminateFlowTabUITestApplication(
        target,
        targetDescription: "\(targetDescription):forced",
        timeout: forcedTimeout
    )
    return FlowTabUITestApplicationCleanupEvidence(
        gracefulExit: gracefulExit,
        forcedExit: forcedExit
    )
}

extension FlowTabUITests {
    func testApplicationTerminationPolicyPreservesStatusItemMenuQuitWatchdog() {
        XCTAssertEqual(
            FlowTabUITestApplicationTerminationPolicy
                .statusItemMenuQuitWatchdog,
            8
        )
        XCTAssertTrue(
            FlowTabUITestApplicationTerminationPolicy
                .statusItemMenuQuitWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestApplicationTerminationPolicy
                .statusItemMenuQuitWatchdog,
            0
        )
    }

    func testApplicationTerminationPolicyPreservesRuntimeLifecycleFixtureWatchdog() {
        XCTAssertEqual(
            FlowTabUITestApplicationTerminationPolicy
                .runtimeLifecycleFixtureWatchdog,
            8
        )
        XCTAssertTrue(
            FlowTabUITestApplicationTerminationPolicy
                .runtimeLifecycleFixtureWatchdog.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestApplicationTerminationPolicy
                .runtimeLifecycleFixtureWatchdog,
            0
        )
    }

    func testApplicationCleanupAcceptsAlreadyStoppedInitialState() {
        let target =
            FlowTabUITestApplicationTerminationTargetStub(
                initialState: .notRunning
            )
        var gracefulRequestCount = 0

        let evidence = cleanupFlowTabUITestApplication(
            target,
            targetDescription: "already-stopped-cleanup",
            gracefulTimeout:
                FlowTabUITestApplicationCleanupTestPolicy
                    .compatibleWatchdog,
            forcedTimeout:
                FlowTabUITestApplicationCleanupTestPolicy
                    .compatibleWatchdog
        ) {
            gracefulRequestCount += 1
        }

        XCTAssertTrue(evidence.isSatisfied)
        XCTAssertTrue(evidence.gracefulExit.isSatisfied)
        XCTAssertNil(evidence.forcedExit)
        XCTAssertEqual(gracefulRequestCount, 0)
        XCTAssertEqual(target.terminateCallCount, 0)
        XCTAssertEqual(target.waitCallCount, 0)
    }

    func testApplicationCleanupAcceptsGracefulExactExit() {
        let target =
            FlowTabUITestApplicationTerminationTargetStub(
                initialState: .runningForeground,
                postTerminateState: .notRunning
            )

        let evidence = cleanupFlowTabUITestApplication(
            target,
            targetDescription: "graceful-cleanup",
            gracefulTimeout:
                FlowTabUITestApplicationCleanupTestPolicy
                    .compatibleWatchdog,
            forcedTimeout:
                FlowTabUITestApplicationCleanupTestPolicy
                    .compatibleWatchdog
        ) {
            target.terminate()
        }

        XCTAssertTrue(evidence.isSatisfied)
        XCTAssertTrue(evidence.gracefulExit.isSatisfied)
        XCTAssertNil(evidence.forcedExit)
        XCTAssertEqual(target.terminateCallCount, 1)
        XCTAssertEqual(target.waitCallCount, 0)
    }

    func testApplicationCleanupEscalatesAfterUnmetGracefulEvidence() {
        let target =
            FlowTabUITestApplicationTerminationTargetStub(
                initialState: .runningBackground,
                postTerminateState: .notRunning,
                waitResult: false,
                postWaitState: .runningBackground
            )
        var gracefulRequestCount = 0

        let evidence = cleanupFlowTabUITestApplication(
            target,
            targetDescription: "forced-cleanup",
            gracefulTimeout:
                FlowTabUITestApplicationCleanupTestPolicy
                    .compatibleWatchdog,
            forcedTimeout:
                FlowTabUITestApplicationCleanupTestPolicy
                    .compatibleWatchdog
        ) {
            gracefulRequestCount += 1
        }

        XCTAssertTrue(evidence.isSatisfied)
        XCTAssertFalse(evidence.gracefulExit.isSatisfied)
        XCTAssertTrue(evidence.forcedExit?.isSatisfied == true)
        XCTAssertEqual(gracefulRequestCount, 1)
        XCTAssertEqual(target.terminateCallCount, 1)
        XCTAssertEqual(target.waitCallCount, 1)
        XCTAssertEqual(target.lastWaitState, .notRunning)
        XCTAssertEqual(
            target.lastWaitTimeout,
            FlowTabUITestApplicationCleanupTestPolicy
                .compatibleWatchdog
        )
    }

    func testApplicationCleanupWatchdogReportsBothFinalStates() {
        let target =
            FlowTabUITestApplicationTerminationTargetStub(
                initialState: .runningBackground,
                postTerminateState: .runningBackground,
                waitResult: false,
                postWaitState: .runningBackground
            )

        let evidence = cleanupFlowTabUITestApplication(
            target,
            targetDescription: "stuck-cleanup",
            gracefulTimeout:
                FlowTabUITestApplicationCleanupTestPolicy
                    .compatibleWatchdog,
            forcedTimeout:
                FlowTabUITestApplicationCleanupTestPolicy
                    .compatibleWatchdog
        ) {}

        XCTAssertFalse(evidence.isSatisfied)
        XCTAssertEqual(target.terminateCallCount, 1)
        XCTAssertEqual(target.waitCallCount, 2)
        XCTAssertEqual(
            evidence.diagnosticSummary,
            "graceful{target=stuck-cleanup:graceful "
                + "initialState=runningBackground "
                + "didRequestTermination=true "
                + "postTriggerState=runningBackground "
                + "waiterCompleted=false "
                + "finalState=runningBackground} "
                + "forced{target=stuck-cleanup:forced "
                + "initialState=runningBackground "
                + "didRequestTermination=true "
                + "postTriggerState=runningBackground "
                + "waiterCompleted=false "
                + "finalState=runningBackground}"
        )
    }

    func testApplicationCleanupLifecycleUnderPressure() {
        for iteration in 0..<100 {
            let target =
                FlowTabUITestApplicationTerminationTargetStub(
                    initialState: .runningBackground,
                    postTerminateState: .notRunning,
                    waitResult: false,
                    postWaitState: .runningBackground
                )

            let evidence = cleanupFlowTabUITestApplication(
                target,
                targetDescription: "cleanup-pressure-\(iteration)",
                gracefulTimeout:
                    FlowTabUITestApplicationCleanupTestPolicy
                        .compatibleWatchdog,
                forcedTimeout:
                    FlowTabUITestApplicationCleanupTestPolicy
                        .compatibleWatchdog
            ) {
                if iteration.isMultiple(of: 2) {
                    target.terminate()
                }
            }

            XCTAssertTrue(
                evidence.isSatisfied,
                evidence.diagnosticSummary
            )
            XCTAssertEqual(target.terminateCallCount, 1)
            XCTAssertEqual(
                evidence.forcedExit == nil,
                iteration.isMultiple(of: 2)
            )
        }
    }

    func testApplicationTerminationAcceptsAlreadyStoppedInitialState() {
        let target =
            FlowTabUITestApplicationTerminationTargetStub(
                initialState: .notRunning
            )

        let evidence = terminateFlowTabUITestApplication(
            target,
            targetDescription: "already-stopped"
        )

        XCTAssertTrue(evidence.isSatisfied)
        XCTAssertFalse(evidence.didRequestTermination)
        XCTAssertNil(evidence.waiterCompleted)
        XCTAssertEqual(target.terminateCallCount, 0)
        XCTAssertEqual(target.waitCallCount, 0)
    }

    func testApplicationTerminationAcceptsImmediatePostTriggerState() {
        let target =
            FlowTabUITestApplicationTerminationTargetStub(
                initialState: .runningForeground,
                postTerminateState: .notRunning
            )

        let evidence = terminateFlowTabUITestApplication(
            target,
            targetDescription: "immediate"
        )

        XCTAssertTrue(evidence.isSatisfied)
        XCTAssertTrue(evidence.didRequestTermination)
        XCTAssertEqual(evidence.postTriggerState, .notRunning)
        XCTAssertNil(evidence.waiterCompleted)
        XCTAssertEqual(target.terminateCallCount, 1)
        XCTAssertEqual(target.waitCallCount, 0)
    }

    func testApplicationTerminationWaitsForDelayedNotRunningEvidence() {
        XCTAssertEqual(
            FlowTabUITestApplicationTerminationPolicy
                .delayedEvidenceOverrideWatchdog,
            9
        )
        let target =
            FlowTabUITestApplicationTerminationTargetStub(
                initialState: .runningBackground,
                postTerminateState: .runningBackground,
                waitResult: true,
                postWaitState: .notRunning
            )

        let evidence = terminateFlowTabUITestApplication(
            target,
            targetDescription: "delayed",
            timeout:
                FlowTabUITestApplicationTerminationPolicy
                    .delayedEvidenceOverrideWatchdog
        )

        XCTAssertTrue(evidence.isSatisfied)
        XCTAssertEqual(evidence.waiterCompleted, true)
        XCTAssertEqual(target.waitCallCount, 1)
        XCTAssertEqual(target.lastWaitState, .notRunning)
        XCTAssertEqual(
            target.lastWaitTimeout,
            FlowTabUITestApplicationTerminationPolicy
                .delayedEvidenceOverrideWatchdog
        )
    }

    func testApplicationTerminationAcceptsFinalReadbackAfterWaitBoundary() {
        let target =
            FlowTabUITestApplicationTerminationTargetStub(
                initialState: .runningForeground,
                postTerminateState: .runningBackground,
                waitResult: false,
                postWaitState: .notRunning
            )

        let evidence = terminateFlowTabUITestApplication(
            target,
            targetDescription: "boundary"
        )

        XCTAssertTrue(evidence.isSatisfied)
        XCTAssertEqual(evidence.waiterCompleted, false)
        XCTAssertEqual(evidence.finalState, .notRunning)
        XCTAssertEqual(target.waitCallCount, 1)
    }

    func testApplicationTerminationRepeatedLifecycleUsesEachExactTargetState() {
        for iteration in 0..<100 {
            let target =
                FlowTabUITestApplicationTerminationTargetStub(
                    initialState: .runningBackground,
                    postTerminateState:
                        iteration.isMultiple(of: 2)
                        ? .notRunning
                        : .runningBackground,
                    waitResult:
                        !iteration.isMultiple(of: 2),
                    postWaitState: .notRunning
                )

            let evidence = terminateFlowTabUITestApplication(
                target,
                targetDescription:
                    "pressure-\(iteration)"
            )

            XCTAssertTrue(
                evidence.isSatisfied,
                evidence.diagnosticSummary
            )
            XCTAssertEqual(
                target.terminateCallCount,
                1
            )
            XCTAssertEqual(
                target.waitCallCount,
                iteration.isMultiple(of: 2) ? 0 : 1
            )
        }
    }

    func testApplicationTerminationWatchdogReportsFinalState() {
        let target =
            FlowTabUITestApplicationTerminationTargetStub(
                initialState: .runningBackground,
                postTerminateState: .runningBackground,
                waitResult: false,
                postWaitState: .runningBackground
            )

        let evidence = terminateFlowTabUITestApplication(
            target,
            targetDescription: "stuck"
        )

        XCTAssertFalse(evidence.isSatisfied)
        XCTAssertEqual(evidence.waiterCompleted, false)
        XCTAssertEqual(
            evidence.diagnosticSummary,
            "target=stuck initialState=runningBackground "
                + "didRequestTermination=true "
                + "postTriggerState=runningBackground "
                + "waiterCompleted=false "
                + "finalState=runningBackground"
        )
    }
}

private final class
    FlowTabUITestApplicationTerminationTargetStub:
    FlowTabUITestApplicationTerminationTarget
{
    private(set) var state: XCUIApplication.State
    private let postTerminateState: XCUIApplication.State
    private let waitResult: Bool
    private let postWaitState: XCUIApplication.State

    private(set) var terminateCallCount = 0
    private(set) var waitCallCount = 0
    private(set) var lastWaitState: XCUIApplication.State?
    private(set) var lastWaitTimeout: TimeInterval?

    init(
        initialState: XCUIApplication.State,
        postTerminateState: XCUIApplication.State? = nil,
        waitResult: Bool = false,
        postWaitState: XCUIApplication.State? = nil
    ) {
        state = initialState
        self.postTerminateState =
            postTerminateState ?? initialState
        self.waitResult = waitResult
        self.postWaitState =
            postWaitState
            ?? self.postTerminateState
    }

    func terminate() {
        terminateCallCount += 1
        state = postTerminateState
    }

    func wait(
        for state: XCUIApplication.State,
        timeout: TimeInterval
    ) -> Bool {
        waitCallCount += 1
        lastWaitState = state
        lastWaitTimeout = timeout
        self.state = postWaitState
        return waitResult
    }
}
