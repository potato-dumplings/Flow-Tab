import Foundation
import XCTest

struct AppPanelPressureUITestEvidence {
    let sequence: UInt64
    let phase: String
    let elapsedMilliseconds: Double
    let panelPresented: Bool
    let userVisible: Bool
    let selectedAppID: String
    let appCount: Int
    let selectedWindowCount: Int
    let panelWidth: Double
    let visibleFrameWidth: Double
    let visibleHomeWindowCount: Int
    let satisfied: Bool
    let stageMetrics: [String: Double]

    static func parse(
        _ notification: Notification
    ) -> AppPanelPressureUITestEvidence? {
        guard let info = notification.userInfo,
              let sequence =
                (info["sequence"] as? NSNumber)?
                    .uint64Value,
              let phase = info["phase"] as? String,
              let elapsed =
                (info["elapsedMilliseconds"] as? NSNumber)?
                    .doubleValue,
              let panelPresented =
                (info["panelPresented"] as? NSNumber)?
                    .boolValue,
              let userVisible =
                (info["userVisible"] as? NSNumber)?
                    .boolValue,
              let selectedAppID =
                info["selectedAppID"] as? String,
              let appCount =
                (info["appCount"] as? NSNumber)?
                    .intValue,
              let selectedWindowCount =
                (info["selectedWindowCount"] as? NSNumber)?
                    .intValue,
              let panelWidth =
                (info["panelWidth"] as? NSNumber)?
                    .doubleValue,
              let visibleFrameWidth =
                (info["visibleFrameWidth"] as? NSNumber)?
                    .doubleValue,
              let visibleHomeWindowCount =
                (info["visibleHomeWindowCount"] as? NSNumber)?
                    .intValue,
              let satisfied =
                (info["satisfied"] as? NSNumber)?
                    .boolValue
        else {
            return nil
        }
        let stageMetrics =
            (info["stageMetrics"] as? [String: NSNumber])?
                .mapValues(\.doubleValue) ?? [:]
        return AppPanelPressureUITestEvidence(
            sequence: sequence,
            phase: phase,
            elapsedMilliseconds: elapsed,
            panelPresented: panelPresented,
            userVisible: userVisible,
            selectedAppID: selectedAppID,
            appCount: appCount,
            selectedWindowCount: selectedWindowCount,
            panelWidth: panelWidth,
            visibleFrameWidth: visibleFrameWidth,
            visibleHomeWindowCount: visibleHomeWindowCount,
            satisfied: satisfied,
            stageMetrics: stageMetrics
        )
    }
}

final class AppPanelPressureUITestObserver {
    let notificationName = Notification.Name(
        "io.github.potato-dumplings.flowtab."
            + "app-panel-pressure."
            + UUID().uuidString
    )
    let commandNotificationName = Notification.Name(
        "io.github.potato-dumplings.flowtab."
            + "app-panel-pressure-command."
            + UUID().uuidString
    )
    let evidenceAcknowledgementNotificationName = Notification.Name(
        "io.github.potato-dumplings.flowtab."
            + "app-panel-pressure-evidence-acknowledgement."
            + UUID().uuidString
    )
    let commandAcknowledgementNotificationName = Notification.Name(
        "io.github.potato-dumplings.flowtab."
            + "app-panel-pressure-command-acknowledgement."
            + UUID().uuidString
    )

    private let condition = NSCondition()
    private let deliveryQueue = OperationQueue()
    private var evidenceToken: NSObjectProtocol?
    private var commandAcknowledgementToken: NSObjectProtocol?
    private var evidence: [AppPanelPressureUITestEvidence] = []
    private var acknowledgedEvidenceSequences: Set<UInt64> = []
    private var acknowledgedCommandSequences: Set<UInt64> = []
    private var nextCommandSequence: UInt64 = 0

    init() {
        deliveryQueue.maxConcurrentOperationCount = 1
    }

    func start() {
        let center = DistributedNotificationCenter.default()
        evidenceToken = center
            .addObserver(
                forName: notificationName,
                object: nil,
                queue: deliveryQueue
            ) { [weak self] notification in
                guard let self else { return }
                guard let parsed =
                        AppPanelPressureUITestEvidence
                            .parse(notification)
                else {
                    return
                }
                center.postNotificationName(
                    self.evidenceAcknowledgementNotificationName,
                    object: nil,
                    userInfo: [
                        "sequence": NSNumber(
                            value: parsed.sequence
                        )
                    ],
                    deliverImmediately: true
                )
                self.condition.lock()
                if self.acknowledgedEvidenceSequences
                    .insert(parsed.sequence).inserted
                {
                    self.evidence.append(parsed)
                }
                self.condition.broadcast()
                self.condition.unlock()
            }
        commandAcknowledgementToken = center.addObserver(
            forName: commandAcknowledgementNotificationName,
            object: nil,
            queue: deliveryQueue
        ) { [weak self] notification in
            guard
                let self,
                let sequence = (
                    notification.userInfo?["sequence"]
                        as? NSNumber
                )?.uint64Value
            else {
                return
            }
            self.condition.lock()
            self.acknowledgedCommandSequences.insert(sequence)
            self.condition.broadcast()
            self.condition.unlock()
        }
    }

    func wait(
        phase: String,
        after sequence: UInt64,
        timeout: TimeInterval
    ) -> AppPanelPressureUITestEvidence? {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while true {
            if let match = evidence.first(where: {
                $0.sequence > sequence && $0.phase == phase
            }) {
                return match
            }
            guard condition.wait(until: deadline) else {
                return nil
            }
        }
    }

    func post(
        trigger: FlowTabUITestSwitcherTrigger,
        traceLabel: String
    ) -> Bool {
        let action: String
        switch trigger {
        case .global:
            action = "openGlobal"
        case .search:
            action = "openSearch"
        case .inApp:
            XCTFail(
                "In-app trigger is outside app-panel pressure flows"
            )
            return false
        }
        return post(action: action, traceLabel: traceLabel)
    }

    func post(
        command: FlowTabUITestSwitcherCommand,
        traceLabel: String
    ) -> Bool {
        let action: String
        switch command {
        case .advanceDown:
            action = "advanceDown"
        case .advanceRight:
            action = "advanceRight"
        case .searchQuery:
            action = "searchQuery"
        case .cancel:
            action = "cancel"
        default:
            XCTFail(
                "Unsupported app-panel pressure command: "
                    + "\(command)"
            )
            return false
        }
        return post(action: action, traceLabel: traceLabel)
    }

    func cancel() {
        let center = DistributedNotificationCenter.default()
        if let evidenceToken {
            center.removeObserver(evidenceToken)
            self.evidenceToken = nil
        }
        if let commandAcknowledgementToken {
            center.removeObserver(
                commandAcknowledgementToken
            )
            self.commandAcknowledgementToken = nil
        }
        deliveryQueue.cancelAllOperations()
    }

    deinit {
        cancel()
    }

    private func post(
        action: String,
        traceLabel _: String
    ) -> Bool {
        condition.lock()
        nextCommandSequence &+= 1
        let sequence = nextCommandSequence
        condition.unlock()
        let deadline = Date().addingTimeInterval(
            AppPanelPressureUITestPolicy
                .eventWatchdogSeconds
        )
        var attempt = 0
        repeat {
            attempt += 1
            DistributedNotificationCenter.default()
                .postNotificationName(
                    commandNotificationName,
                    object: nil,
                    userInfo: [
                        "sequence": NSNumber(value: sequence),
                        "action": action
                    ],
                    deliverImmediately: true
                )
            if waitForCommandAcknowledgement(
                sequence: sequence,
                deadline: min(
                    deadline,
                    Date().addingTimeInterval(
                        AppPanelPressureUITestPolicy
                            .commandReceiptRetrySeconds
                    )
                )
            ) {
                return true
            }
        } while Date() < deadline

        XCTFail(
            "App-panel pressure command receipt watchdog "
                + "expired action=\(action) "
                + "sequence=\(sequence) attempts=\(attempt)"
        )
        return false
    }

    private func waitForCommandAcknowledgement(
        sequence: UInt64,
        deadline: Date
    ) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        if acknowledgedCommandSequences.contains(sequence) {
            return true
        }
        _ = condition.wait(until: deadline)
        return acknowledgedCommandSequences.contains(sequence)
    }
}

extension FlowTabUITests {
    func testApplicationPanelReleasePressureGate() throws {
        let environment = ProcessInfo.processInfo.environment
        let flow = AppPanelPressureUITestFlow.configured(
            environment: environment
        )
        let scenario =
            AppPanelPressureUITestScenario.configured(
                environment: environment
            )
        let duration =
            AppPanelPressureUITestPolicy.duration(
                environment: environment
            )
        let cooldown =
            AppPanelPressureUITestPolicy.cooldown(
                environment: environment
            )
        let metricsURL = URL(
            fileURLWithPath:
                environment[
                    AppPanelPressureUITestEnvironment
                        .metricsPath
                ]
                ?? FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "flowtab-app-panel-pressure-"
                            + UUID().uuidString
                            + ".csv"
                    ).path
        )
        let observer = AppPanelPressureUITestObserver()
        observer.start()
        defer { observer.cancel() }

        var metrics = AppPanelPressureMetrics()
        defer { try? metrics.write(to: metricsURL) }
        let launchArguments = [
            "--flowtab-ui-reset-defaults"
        ] + scenario.runtimeArguments + [
            "--flowtab-ui-listen-switcher-trigger",
            "--flowtab-ui-suppress-home-on-launch",
            "-showPermissionReminder",
            "NO",
            "-windowLayerAutoEnterDelay",
            "600",
            FlowTabTestRouteArgument.appPanelPressure,
            observer.notificationName.rawValue,
            FlowTabTestRouteArgument
                .appPanelPressureEvidenceAcknowledgement,
            observer
                .evidenceAcknowledgementNotificationName
                .rawValue,
            FlowTabTestRouteArgument.appPanelPressureCommand,
            observer.commandNotificationName.rawValue,
            FlowTabTestRouteArgument
                .appPanelPressureCommandAcknowledgement,
            observer
                .commandAcknowledgementNotificationName
                .rawValue
        ] + FlowTabUITestSwitcherCommandPayload
            .launchArguments
        let app = makeApp(
            additionalArguments: launchArguments
        )
        launchFlowTabUITestApplication(app)
        XCTAssertTrue(
            waitForFlowTabUITestApplicationToBecomeReady(
                app,
                timeout: 10
            )
        )

        var lastSequence: UInt64 = 0
        for cycle in 1...AppPanelPressureUITestPolicy
            .warmupCycleCount
        {
            guard let result = runAppPanelPressureCycle(
                observer: observer,
                application: app,
                flow: flow,
                scenario: scenario,
                cycle: -cycle,
                capturesVisualCheckpoint: cycle == 1,
                lastSequence: &lastSequence,
                metrics: &metrics
            ) else {
                return
            }
            XCTAssertTrue(result.opened.satisfied)
            XCTAssertTrue(result.highlighted.satisfied)
            XCTAssertTrue(result.closed.satisfied)
        }

        metrics.mark("measurement_start")
        let measurementStartedAt = Date()
        var openMeasurements: [Double] = []
        var highlightMeasurements: [Double] = []
        var measuredCycle = 0
        repeat {
            measuredCycle += 1
            guard let result = runAppPanelPressureCycle(
                observer: observer,
                application: app,
                flow: flow,
                scenario: scenario,
                cycle: measuredCycle,
                capturesVisualCheckpoint: false,
                lastSequence: &lastSequence,
                metrics: &metrics
            ) else {
                return
            }
            openMeasurements.append(
                result.opened.elapsedMilliseconds
            )
            highlightMeasurements.append(
                result.highlighted.elapsedMilliseconds
            )
        } while Date().timeIntervalSince(measurementStartedAt)
            < duration

        metrics.mark("cooldown_start")
        try metrics.write(to: metricsURL)
        let cooldownCompleted = expectation(
            description: "app-panel pressure cooldown"
        )
        DispatchQueue.global().asyncAfter(
            deadline: .now() + cooldown
        ) {
            cooldownCompleted.fulfill()
        }
        wait(
            for: [cooldownCompleted],
            timeout: cooldown + 5
        )
        metrics.mark("cooldown_end")
        try metrics.write(to: metricsURL)

        XCTAssertGreaterThanOrEqual(
            Date().timeIntervalSince(measurementStartedAt),
            duration
        )
        XCTAssertFalse(openMeasurements.isEmpty)
        XCTAssertFalse(highlightMeasurements.isEmpty)
        XCTAssertLessThanOrEqual(
            AppPanelPressureUITestPolicy.percentile95(
                openMeasurements
            ),
            AppPanelPressureUITestPolicy
                .openP95LimitMilliseconds
        )
        if let interactionLimit =
            flow.interactionP95LimitMilliseconds
        {
            XCTAssertLessThanOrEqual(
                AppPanelPressureUITestPolicy.percentile95(
                    highlightMeasurements
                ),
                interactionLimit
            )
        }
    }

    private func runAppPanelPressureCycle(
        observer: AppPanelPressureUITestObserver,
        application: XCUIApplication,
        flow: AppPanelPressureUITestFlow,
        scenario: AppPanelPressureUITestScenario,
        cycle: Int,
        capturesVisualCheckpoint: Bool,
        lastSequence: inout UInt64,
        metrics: inout AppPanelPressureMetrics
    ) -> (
        opened: AppPanelPressureUITestEvidence,
        highlighted: AppPanelPressureUITestEvidence,
        closed: AppPanelPressureUITestEvidence
    )? {
        let trigger: FlowTabUITestSwitcherTrigger =
            flow == .search ? .search : .global
        guard observer.post(
            trigger: trigger,
            traceLabel:
                "app-panel-pressure.\(flow.rawValue)."
                + "\(cycle).open"
        ) else {
            return nil
        }
        guard let opened = observer.wait(
            phase: "opened",
            after: lastSequence,
            timeout:
                AppPanelPressureUITestPolicy
                    .eventWatchdogSeconds
        ) else {
            XCTFail("App-panel open evidence watchdog expired")
            return nil
        }
        lastSequence = opened.sequence
        metrics.append(opened, cycle: cycle)
        guard assertAppPanelPressureEvidence(
            opened,
            expectedAppID: scenario.expectedAppID(index: 1),
            expectedAppCount: scenario.expectedAppCount,
            expectedWindowCount: nil,
            excludingAppID: nil
        ) else {
            return nil
        }
        if capturesVisualCheckpoint, flow == .application {
            captureAppPanelVisualCheckpoint(
                application: application,
                flow: flow,
                scenario: scenario,
                evidence: opened
            )
        }
        guard let highlighted =
            runAppPanelPressureInteraction(
                observer: observer,
                flow: flow,
                scenario: scenario,
                cycle: cycle,
                opened: opened,
                lastSequence: &lastSequence
            )
        else {
            return nil
        }
        lastSequence = highlighted.sequence
        metrics.append(highlighted, cycle: cycle)
        let expectedHighlightedAppID: String?
        let expectedHighlightedWindowCount: Int?
        let excludedAppID: String?
        switch flow {
        case .application:
            expectedHighlightedAppID =
                scenario.expectedAppID(index: 2)
            expectedHighlightedWindowCount = nil
            excludedAppID = scenario.variant == nil
                ? opened.selectedAppID
                : nil
        case .applicationToWindow:
            expectedHighlightedAppID =
                scenario.expectedAppID(index: 1)
            expectedHighlightedWindowCount =
                scenario.variant == nil
                    ? nil
                    : scenario.expectedOpenedWindowCount
            excludedAppID = nil
        case .search:
            expectedHighlightedAppID = opened.selectedAppID
            expectedHighlightedWindowCount =
                opened.selectedWindowCount
            excludedAppID = nil
        }
        guard assertAppPanelPressureEvidence(
            highlighted,
            expectedAppID: expectedHighlightedAppID,
            expectedAppCount: scenario.expectedAppCount,
            expectedWindowCount:
                expectedHighlightedWindowCount,
            excludingAppID: excludedAppID
        ) else {
            return nil
        }
        if flow == .applicationToWindow,
           highlighted.selectedWindowCount < 2
        {
            XCTFail(
                "Window-panel pressure requires at least two windows"
            )
            return nil
        }
        if capturesVisualCheckpoint, flow != .application {
            captureAppPanelVisualCheckpoint(
                application: application,
                flow: flow,
                scenario: scenario,
                evidence: highlighted
            )
        }
        guard observer.post(
            command: .cancel,
            traceLabel: "app-panel-pressure.\(cycle).close"
        ) else {
            return nil
        }
        guard let closed = observer.wait(
            phase: "closed",
            after: lastSequence,
            timeout:
                AppPanelPressureUITestPolicy
                    .eventWatchdogSeconds
        ) else {
            XCTFail("App-panel close evidence watchdog expired")
            return nil
        }
        lastSequence = closed.sequence
        metrics.append(closed, cycle: cycle)
        guard closed.satisfied,
              !closed.panelPresented,
              !closed.userVisible,
              closed.selectedAppID == "none"
        else {
            XCTFail("App-panel close evidence was not satisfied")
            return nil
        }
        return (opened, highlighted, closed)
    }

    private func assertAppPanelPressureEvidence(
        _ evidence: AppPanelPressureUITestEvidence,
        expectedAppID: String?,
        expectedAppCount: Int?,
        expectedWindowCount: Int?,
        excludingAppID: String?
    ) -> Bool {
        let appIDMatches = expectedAppID.map {
            evidence.selectedAppID == $0
        } ?? (evidence.selectedAppID != "none")
        let appCountMatches = expectedAppCount.map {
            evidence.appCount == $0
        } ?? (evidence.appCount > 1)
        let windowCountMatches = expectedWindowCount.map {
            evidence.selectedWindowCount == $0
        } ?? (evidence.selectedWindowCount >= 0)
        let excludedAppIsAbsent = excludingAppID.map {
            evidence.selectedAppID != $0
        } ?? true
        let widthLimit = max(
            440,
            evidence.visibleFrameWidth - 80
        )
        guard evidence.satisfied,
              evidence.panelPresented,
              evidence.userVisible,
              evidence.panelWidth >= 440,
              evidence.panelWidth <= widthLimit + 0.5,
              evidence.visibleHomeWindowCount == 0,
              appIDMatches,
              appCountMatches,
              windowCountMatches,
              excludedAppIsAbsent
        else {
            let diagnosticStageKeys = [
                "command_return_ms",
                "next_main_turn_ms",
                "search_shell_draw_ms",
                "search_first_row_draw_ms",
                "occlusion_visible_ms"
            ]
            let diagnosticStages = diagnosticStageKeys.map {
                key in
                key + "=" + String(
                    format: "%.3f",
                    evidence.stageMetrics[key] ?? 0
                )
            }.joined(separator: ",")
            XCTFail(
                "App-panel evidence mismatch phase="
                    + "\(evidence.phase) selected="
                    + "\(evidence.selectedAppID) apps="
                    + "\(evidence.appCount) windows="
                    + "\(evidence.selectedWindowCount) "
                    + "presented="
                    + "\(evidence.panelPresented ? 1 : 0) "
                    + "userVisible="
                    + "\(evidence.userVisible ? 1 : 0) "
                    + "panelWidth="
                    + "\(evidence.panelWidth) visibleFrameWidth="
                    + "\(evidence.visibleFrameWidth) visibleHomeWindows="
                    + "\(evidence.visibleHomeWindowCount) "
                    + "satisfied="
                    + "\(evidence.satisfied ? 1 : 0) "
                    + "elapsedMs="
                    + String(
                        format: "%.3f",
                        evidence.elapsedMilliseconds
                    )
                    + " stages{" + diagnosticStages + "}"
            )
            return false
        }
        return true
    }

}

private enum FlowTabTestRouteArgument {
    static let appPanelPressure =
        "--flowtab-app-panel-pressure-evidence-notification-name"
    static let appPanelPressureEvidenceAcknowledgement =
        "--flowtab-app-panel-pressure-evidence-acknowledgement-notification-name"
    static let appPanelPressureCommand =
        "--flowtab-app-panel-pressure-command-notification-name"
    static let appPanelPressureCommandAcknowledgement =
        "--flowtab-app-panel-pressure-command-acknowledgement-notification-name"
}
