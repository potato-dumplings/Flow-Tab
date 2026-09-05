import Foundation
import XCTest

enum ControlTabPressureUITestEnvironment {
    static let lane = "FLOWTAB_CONTROL_TAB_LANE"
    static let scenario = "FLOWTAB_CONTROL_TAB_SCENARIO"
    static let durationSeconds =
        "FLOWTAB_CONTROL_TAB_DURATION_SECONDS"
    static let cooldownSeconds =
        "FLOWTAB_CONTROL_TAB_COOLDOWN_SECONDS"
    static let metricsPath =
        "FLOWTAB_CONTROL_TAB_METRICS_PATH"
    static let samplerReadyPath =
        "FLOWTAB_CONTROL_TAB_SAMPLER_READY_PATH"
    static let recorderMode =
        "FLOWTAB_CONTROL_TAB_RECORDER_MODE"
}

struct ControlTabPressureUITestScenario {
    let name: String
    let variant: String
    let expectedAppCount: Int
    let expectedWindowCount: Int
    let focusedAppID: String

    static func configured(
        environment: [String: String]
    ) -> ControlTabPressureUITestScenario {
        if environment[
            ControlTabPressureUITestEnvironment.scenario
        ] == "extreme" {
            return ControlTabPressureUITestScenario(
                name: "extreme",
                variant: "app-panel-pressure-extreme",
                expectedAppCount: 120,
                expectedWindowCount: 100,
                focusedAppID:
                    String(
                        format: "com.flowtab.pressure.app.%04d",
                        1
                    )
            )
        }
        return ControlTabPressureUITestScenario(
            name: "realistic",
            variant: "app-panel-pressure-realistic",
            expectedAppCount: 24,
            expectedWindowCount: 5,
            focusedAppID:
                String(
                    format: "com.flowtab.pressure.app.%04d",
                    1
                )
        )
    }

    var launchArguments: [String] {
        [
            "--flowtab-ui-reset-defaults",
            "--flowtab-ui-mock-runtime",
            "--flowtab-ui-mock-runtime-variant",
            variant,
            "--flowtab-ui-mock-window-previews",
            "--flowtab-ui-frontmost-bundle-id",
            focusedAppID,
            "--flowtab-ui-suppress-home-on-launch",
            "--flowtab-ui-enable-shortcut-event-injection",
            "--flowtab-ui-runtime-log-level",
            "DEBUG",
            "--flowtab-ui-enable-verbose-logs",
            "--flowtab-ui-ax-trusted",
            "YES",
            "--flowtab-ui-screen-trusted",
            "YES",
            "-showPermissionReminder",
            "NO"
        ]
    }
}

enum ControlTabPressureUITestPolicy {
    static let warmupCycles = 3
    static let eventWatchdogSeconds: TimeInterval = 5
    static let commandRetrySeconds: TimeInterval = 0.05
    static let samplerReadinessWatchdogSeconds: TimeInterval = 45
    static let defaultDurationSeconds: TimeInterval = 2
    static let defaultCooldownSeconds: TimeInterval = 2

    static func duration(
        environment: [String: String]
    ) -> TimeInterval {
        max(
            1,
            Double(
                environment[
                    ControlTabPressureUITestEnvironment
                        .durationSeconds
                ] ?? ""
            ) ?? defaultDurationSeconds
        )
    }

    static func cooldown(
        environment: [String: String]
    ) -> TimeInterval {
        max(
            1,
            Double(
                environment[
                    ControlTabPressureUITestEnvironment
                        .cooldownSeconds
                ] ?? ""
            ) ?? defaultCooldownSeconds
        )
    }
}

struct ControlTabTopologyPressureCyclePlan: Equatable {
    static let executionsPerWindow = 2

    let windowIndex: Int
    let commits: Bool

    init(cycle: Int, windowCount: Int) {
        precondition(cycle > 0)
        precondition(windowCount > 0)
        let zeroBasedCycle = cycle - 1
        windowIndex =
            (zeroBasedCycle / Self.executionsPerWindow)
            % windowCount
        commits = zeroBasedCycle.isMultiple(of: 2)
    }

    static func minimumCycleCount(windowCount: Int) -> Int {
        precondition(windowCount > 0)
        return windowCount * executionsPerWindow
    }
}

extension FlowTabUITests {
    func testControlTabTopologyCyclePlanCoversEveryWindowTerminalPath() {
        let plans = (1...8).map {
            ControlTabTopologyPressureCyclePlan(
                cycle: $0,
                windowCount: 4
            )
        }
        XCTAssertEqual(
            plans.filter(\.commits).map(\.windowIndex),
            [0, 1, 2, 3]
        )
        XCTAssertEqual(
            plans.filter { !$0.commits }.map(\.windowIndex),
            [0, 1, 2, 3]
        )
        XCTAssertEqual(
            ControlTabTopologyPressureCyclePlan.minimumCycleCount(
                windowCount: 4
            ),
            8
        )
    }
}
