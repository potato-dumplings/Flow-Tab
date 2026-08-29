import Foundation
import XCTest

struct TabSwitchStressUITestRoute {
    static let notificationArgument =
        "--flowtab-tab-stress-evidence-notification-name"

    let notificationName: Notification.Name

    init() {
        notificationName = Notification.Name(
            "io.github.potato-dumplings.flowtab."
                + "tab-switch-stress."
                + UUID().uuidString
        )
    }

    var launchArguments: [String] {
        [
            Self.notificationArgument,
            notificationName.rawValue
        ]
    }
}

struct TabSwitchStressUITestEvidence:
    Equatable
{
    let ownerGeneration: UInt64
    let transitionGeneration: UInt64
    let phase: String
    let durationNanoseconds: UInt64
    let cadenceNanoseconds: UInt64
    let requiredSwitches: UInt64
    let attempts: UInt64
    let switches: UInt64
    let homeSwitches: UInt64
    let logsSwitches: UInt64
    let settingsSwitches: UInt64
    let runtimeLogLevel: String
    let requested: String
    let observed: String
    let elapsedNanoseconds: UInt64
    let durationSatisfied: Bool
    let workloadSatisfied: Bool

    var diagnosticSummary: String {
        "phase=\(phase) "
            + "ownerGeneration=\(ownerGeneration) "
            + "transitionGeneration="
            + "\(transitionGeneration) "
            + "durationNanoseconds="
            + "\(durationNanoseconds) "
            + "cadenceNanoseconds="
            + "\(cadenceNanoseconds) "
            + "requiredSwitches="
            + "\(requiredSwitches) "
            + "attempts=\(attempts) "
            + "switches=\(switches) "
            + "homeSwitches=\(homeSwitches) "
            + "logsSwitches=\(logsSwitches) "
            + "settingsSwitches=\(settingsSwitches) "
            + "runtimeLogLevel=\(runtimeLogLevel) "
            + "requested=\(requested) "
            + "observed=\(observed) "
            + "elapsedNanoseconds="
            + "\(elapsedNanoseconds) "
            + "durationSatisfied="
            + "\(durationSatisfied) "
            + "workloadSatisfied="
            + "\(workloadSatisfied)"
    }
}

final class TabSwitchStressUITestObservationOwner {
    private enum UserInfoKey {
        static let ownerGeneration =
            "ownerGeneration"
        static let transitionGeneration =
            "transitionGeneration"
        static let phase = "phase"
        static let durationNanoseconds =
            "durationNanoseconds"
        static let cadenceNanoseconds =
            "cadenceNanoseconds"
        static let requiredSwitches =
            "requiredSwitches"
        static let attempts = "attempts"
        static let switches = "switches"
        static let homeSwitches = "homeSwitches"
        static let logsSwitches = "logsSwitches"
        static let settingsSwitches = "settingsSwitches"
        static let runtimeLogLevel = "runtimeLogLevel"
        static let requested = "requested"
        static let observed = "observed"
        static let elapsedNanoseconds =
            "elapsedNanoseconds"
        static let durationSatisfied =
            "durationSatisfied"
        static let workloadSatisfied =
            "workloadSatisfied"
    }

    private let route: TabSwitchStressUITestRoute
    private let center: DistributedNotificationCenter
    private let completedExpectation =
        XCTestExpectation(
            description:
                "tab-switch stress completion evidence"
        )
    private var token: NSObjectProtocol?
    private var evidence:
        [TabSwitchStressUITestEvidence] = []

    init(
        route: TabSwitchStressUITestRoute,
        center:
            DistributedNotificationCenter =
                .default()
    ) {
        self.route = route
        self.center = center
        completedExpectation.assertForOverFulfill = true
    }

    func start() {
        cancel()
        evidence.removeAll()
        token = center.addObserver(
            forName: route.notificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.observe(notification)
        }
    }

    func waitForCompletion(
        timeout: TimeInterval
    ) -> TabSwitchStressUITestEvidence? {
        if let completed = evidence.last(
            where: {
                $0.phase == "completed"
            }
        ) {
            return completed
        }
        guard XCTWaiter.wait(
            for: [completedExpectation],
            timeout: timeout
        ) == .completed
        else {
            return nil
        }
        return evidence.last(
            where: {
                $0.phase == "completed"
            }
        )
    }

    func cancel() {
        guard let token else { return }
        center.removeObserver(token)
        self.token = nil
    }

    var diagnosticSummary: String {
        evidence.isEmpty
            ? "unobserved"
            : evidence
                .map(\.diagnosticSummary)
                .joined(separator: " | ")
    }

    deinit {
        if let token {
            center.removeObserver(token)
        }
    }

    private func observe(
        _ notification: Notification
    ) {
        guard let parsed = Self.evidence(
            from: notification
        ) else {
            return
        }
        evidence.append(parsed)
        if parsed.phase == "completed" {
            completedExpectation.fulfill()
        }
    }

    private static func evidence(
        from notification: Notification
    ) -> TabSwitchStressUITestEvidence? {
        guard let userInfo = notification.userInfo,
              let ownerGeneration =
                number(
                    UserInfoKey.ownerGeneration,
                    in: userInfo
                )?.uint64Value,
              ownerGeneration > 0,
              let transitionGeneration =
                number(
                    UserInfoKey.transitionGeneration,
                    in: userInfo
                )?.uint64Value,
              transitionGeneration > 0,
              let phase =
                userInfo[UserInfoKey.phase] as? String,
              let durationNanoseconds =
                number(
                    UserInfoKey.durationNanoseconds,
                    in: userInfo
                )?.uint64Value,
              let cadenceNanoseconds =
                number(
                    UserInfoKey.cadenceNanoseconds,
                    in: userInfo
                )?.uint64Value,
              let requiredSwitches =
                number(
                    UserInfoKey.requiredSwitches,
                    in: userInfo
                )?.uint64Value,
              let attempts =
                number(
                    UserInfoKey.attempts,
                    in: userInfo
                )?.uint64Value,
              let switches =
                number(
                    UserInfoKey.switches,
                    in: userInfo
                )?.uint64Value,
              let homeSwitches =
                number(
                    UserInfoKey.homeSwitches,
                    in: userInfo
                )?.uint64Value,
              let logsSwitches =
                number(
                    UserInfoKey.logsSwitches,
                    in: userInfo
                )?.uint64Value,
              let settingsSwitches =
                number(
                    UserInfoKey.settingsSwitches,
                    in: userInfo
                )?.uint64Value,
              let runtimeLogLevel =
                userInfo[UserInfoKey.runtimeLogLevel]
                    as? String,
              let requested =
                userInfo[UserInfoKey.requested]
                    as? String,
              let observed =
                userInfo[UserInfoKey.observed]
                    as? String,
              let elapsedNanoseconds =
                number(
                    UserInfoKey.elapsedNanoseconds,
                    in: userInfo
                )?.uint64Value,
              let durationSatisfied =
                number(
                    UserInfoKey.durationSatisfied,
                    in: userInfo
                )?.boolValue,
              let workloadSatisfied =
                number(
                    UserInfoKey.workloadSatisfied,
                    in: userInfo
                )?.boolValue
        else {
            return nil
        }
        return TabSwitchStressUITestEvidence(
            ownerGeneration: ownerGeneration,
            transitionGeneration:
                transitionGeneration,
            phase: phase,
            durationNanoseconds:
                durationNanoseconds,
            cadenceNanoseconds:
                cadenceNanoseconds,
            requiredSwitches:
                requiredSwitches,
            attempts: attempts,
            switches: switches,
            homeSwitches: homeSwitches,
            logsSwitches: logsSwitches,
            settingsSwitches: settingsSwitches,
            runtimeLogLevel: runtimeLogLevel,
            requested: requested,
            observed: observed,
            elapsedNanoseconds:
                elapsedNanoseconds,
            durationSatisfied:
                durationSatisfied,
            workloadSatisfied:
                workloadSatisfied
        )
    }

    private static func number(
        _ key: String,
        in userInfo: [AnyHashable: Any]
    ) -> NSNumber? {
        userInfo[key] as? NSNumber
    }
}

extension FlowTabUITests {
    func testTabSwitchStressCPUAndMemory() throws {
        let options = XCTMeasureOptions()
        options.iterationCount = TabSwitchStressUITestPolicy.measurementIterations

        measure(
            metrics: [
                XCTClockMetric(),
                XCTCPUMetric(),
                XCTMemoryMetric()
            ],
            options: options
        ) { [self] in
            let route =
                TabSwitchStressUITestRoute()
            let observation =
                TabSwitchStressUITestObservationOwner(
                    route: route
                )
            observation.start()
            defer { observation.cancel() }

            let app = makeApp(
                additionalArguments: [
                    "--flowtab-ui-reset-defaults",
                    "--flowtab-ui-mock-runtime",
                    "--flowtab-tab-stress",
                    "--flowtab-tab-stress-duration",
                    TabSwitchStressUITestPolicy.workloadDurationArgument,
                    "--flowtab-tab-stress-interval-ms",
                    TabSwitchStressUITestPolicy.switchCadenceArgument,
                    "-showPermissionReminder",
                    "NO"
                ] + route.launchArguments
            )
            defer { assertTabSwitchStressApplicationCleanup(app) }
            launchFlowTabUITestApplication(app)
            let readinessWaitCompleted =
                waitForFlowTabUITestApplicationToBecomeReady(
                    app,
                    timeout: TabSwitchStressUITestPolicy.applicationReadinessWatchdog
                )
            let readinessState = app.state
            XCTAssertEqual(
                readinessState,
                .runningForeground,
                "Tab-switch stress readiness watchdog expired. "
                    + "waiterCompleted=\(readinessWaitCompleted) "
                    + "finalState=\(String(describing: readinessState))"
            )

            let completed =
                observation.waitForCompletion(
                    timeout:
                        TabSwitchStressUITestPolicy.completionEvidenceWatchdog
                )
            XCTAssertNotNil(
                completed,
                observation.diagnosticSummary
            )
            XCTAssertEqual(
                completed?.durationNanoseconds,
                TabSwitchStressUITestPolicy.workloadDurationNanoseconds
            )
            XCTAssertEqual(
                completed?.cadenceNanoseconds,
                TabSwitchStressUITestPolicy.switchCadenceNanoseconds
            )
            XCTAssertEqual(
                completed?.requiredSwitches,
                TabSwitchStressUITestPolicy.requiredSwitches
            )
            XCTAssertEqual(
                completed?.attempts,
                TabSwitchStressUITestPolicy.requiredSwitches
            )
            XCTAssertEqual(
                completed?.switches,
                TabSwitchStressUITestPolicy.requiredSwitches
            )
            XCTAssertGreaterThan(completed?.homeSwitches ?? 0, 0)
            XCTAssertGreaterThan(completed?.logsSwitches ?? 0, 0)
            XCTAssertGreaterThan(completed?.settingsSwitches ?? 0, 0)
            XCTAssertEqual(
                completed?.runtimeLogLevel,
                "ERROR"
            )
            XCTAssertEqual(
                (completed?.homeSwitches ?? 0)
                    + (completed?.logsSwitches ?? 0)
                    + (completed?.settingsSwitches ?? 0),
                completed?.switches
            )
            XCTAssertEqual(
                completed?.requested,
                "logs"
            )
            XCTAssertEqual(
                completed?.observed,
                "logs"
            )
            XCTAssertTrue(
                completed?.durationSatisfied == true
            )
            XCTAssertTrue(
                completed?.workloadSatisfied == true
            )
            XCTAssertGreaterThanOrEqual(
                completed?.elapsedNanoseconds ?? 0,
                TabSwitchStressUITestPolicy.workloadDurationNanoseconds
            )
            let terminationWaitCompleted =
                app.wait(
                    for: .notRunning,
                    timeout: TabSwitchStressUITestPolicy.naturalTerminationWatchdog
                )
            let terminationState = app.state
            XCTAssertEqual(
                terminationState,
                .notRunning,
                "Tab-switch stress natural-termination watchdog "
                    + "expired. waiterCompleted="
                    + "\(terminationWaitCompleted) finalState="
                    + "\(String(describing: terminationState)) "
                    + observation.diagnosticSummary
            )
        }
    }
}
