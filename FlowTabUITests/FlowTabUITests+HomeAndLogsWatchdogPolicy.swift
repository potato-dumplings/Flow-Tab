import Foundation
import XCTest

enum FlowTabUITestHomeAndLogsWatchdogPolicy {
    static let applicationForegroundReadiness: TimeInterval = 8
    static let frontmostApplicationActivation: TimeInterval = 5
    static let homeTabTriggerReadiness: TimeInterval = 5
    static let homeTabProjectionReadiness: TimeInterval = 5
    static let liveApplicationDirectoryReadiness: TimeInterval = 2
}

struct FlowTabUITestHomeAndLogsReadinessEvidence: Equatable {
    let targetDescription: String
    let waitCompleted: Bool
    let finalState: XCUIApplication.State

    var isSatisfied: Bool {
        waitCompleted || finalState == .runningForeground
    }

    var diagnosticSummary: String {
        "target=\(targetDescription) "
            + "unmetCondition=runningForeground "
            + "waitCompleted=\(waitCompleted ? 1 : 0) "
            + "finalState=\(String(describing: finalState))"
    }
}

extension FlowTabUITests {
    @discardableResult
    func assertHomeAndLogsLiveApplicationDirectoryAfterNavigation(
        in app: XCUIApplication,
        targetDescription: String = #function,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let identifierPrefix = "flowtab.home.app."
        let firstLiveAppRow = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                identifierPrefix
            )
        ).firstMatch
        let observation =
            FlowTabUITestElementExistenceObservationOwner(
                elementIdentifier: "\(identifierPrefix)*",
                readback: { firstLiveAppRow.exists }
            )
        observation.start()
        defer { observation.cancel() }

        let didNavigate =
            assertHomeAndLogsHomeTabProjectionAfterNavigation(
                in: app,
                targetDescription: targetDescription,
                file: file,
                line: line
            )
        observation.markTriggerCompleted()
        guard didNavigate else { return false }

        guard observation.waitForResolution(
            timeout:
                FlowTabUITestHomeAndLogsWatchdogPolicy
                    .liveApplicationDirectoryReadiness
        ) != nil else {
            XCTFail(
                "Home live application directory watchdog expired. "
                    + "target=\(targetDescription) "
                    + "identifierPrefix=\(identifierPrefix) "
                    + observation.diagnosticSummary,
                file: file,
                line: line
            )
            return false
        }
        return true
    }

    @discardableResult
    func assertHomeAndLogsHomeTabProjectionAfterNavigation(
        in app: XCUIApplication,
        targetDescription: String = #function,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let didProject = assertSidebarTabProjectionAfterNavigation(
            in: app,
            target: .home,
            triggerWatchdog:
                FlowTabUITestHomeAndLogsWatchdogPolicy
                    .homeTabTriggerReadiness,
            projectionWatchdog:
                FlowTabUITestHomeAndLogsWatchdogPolicy
                    .homeTabProjectionReadiness
        )
        XCTAssertTrue(
            didProject,
            "Home/Logs Home-tab projection watchdog expired. "
                + "target=\(targetDescription)",
            file: file,
            line: line
        )
        return didProject
    }

    @discardableResult
    func assertHomeAndLogsHomeTabTriggerReady(
        in app: XCUIApplication,
        targetDescription: String = #function,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let query = app.buttons.matching(
            identifier: Identifier.homeTabButton
        )
        let didTap = tapFirstHittable(
            in: query,
            timeout:
                FlowTabUITestHomeAndLogsWatchdogPolicy
                    .homeTabTriggerReadiness
        )
        XCTAssertTrue(
            didTap,
            "Home/Logs Home-tab trigger watchdog expired. "
                + "target=\(targetDescription) "
                + "identifier=\(Identifier.homeTabButton) "
                + "finalCandidateCount=\(query.count)",
            file: file,
            line: line
        )
        return didTap
    }

    @discardableResult
    func assertHomeAndLogsApplicationIsForegroundReady(
        _ app: XCUIApplication,
        targetDescription: String = #function,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> FlowTabUITestHomeAndLogsReadinessEvidence {
        let waitCompleted =
            waitForFlowTabUITestApplicationToBecomeReady(
                app,
                timeout:
                    FlowTabUITestHomeAndLogsWatchdogPolicy
                        .applicationForegroundReadiness,
                traceLabel: targetDescription
            )
        let evidence = FlowTabUITestHomeAndLogsReadinessEvidence(
            targetDescription: targetDescription,
            waitCompleted: waitCompleted,
            finalState: app.state
        )
        XCTAssertTrue(
            evidence.isSatisfied,
            "Home/Logs application readiness watchdog expired. "
                + evidence.diagnosticSummary,
            file: file,
            line: line
        )
        return evidence
    }

    func testHomeAndLogsWatchdogPolicyAndReadinessEvidence() {
        XCTAssertEqual(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .applicationForegroundReadiness,
            8
        )
        XCTAssertTrue(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .applicationForegroundReadiness.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .applicationForegroundReadiness,
            0
        )
        XCTAssertEqual(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .frontmostApplicationActivation,
            5
        )
        XCTAssertTrue(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .frontmostApplicationActivation.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .frontmostApplicationActivation,
            0
        )
        XCTAssertEqual(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .homeTabTriggerReadiness,
            5
        )
        XCTAssertTrue(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .homeTabTriggerReadiness.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .homeTabTriggerReadiness,
            0
        )
        XCTAssertEqual(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .homeTabProjectionReadiness,
            5
        )
        XCTAssertTrue(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .homeTabProjectionReadiness.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .homeTabProjectionReadiness,
            0
        )
        XCTAssertEqual(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .liveApplicationDirectoryReadiness,
            2
        )
        XCTAssertTrue(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .liveApplicationDirectoryReadiness.isFinite
        )
        XCTAssertGreaterThan(
            FlowTabUITestHomeAndLogsWatchdogPolicy
                .liveApplicationDirectoryReadiness,
            0
        )

        XCTAssertTrue(
            FlowTabUITestHomeAndLogsReadinessEvidence(
                targetDescription: "delivered",
                waitCompleted: true,
                finalState: .runningBackground
            ).isSatisfied
        )
        XCTAssertTrue(
            FlowTabUITestHomeAndLogsReadinessEvidence(
                targetDescription: "boundary-readback",
                waitCompleted: false,
                finalState: .runningForeground
            ).isSatisfied
        )

        let missing = FlowTabUITestHomeAndLogsReadinessEvidence(
            targetDescription: "missing",
            waitCompleted: false,
            finalState: .runningBackground
        )
        XCTAssertFalse(missing.isSatisfied)
        XCTAssertTrue(
            missing.diagnosticSummary.contains(
                "target=missing unmetCondition=runningForeground "
                    + "waitCompleted=0 finalState="
            )
        )
    }
}
