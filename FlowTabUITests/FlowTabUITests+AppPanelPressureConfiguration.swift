import Foundation

enum AppPanelPressureUITestEnvironment {
    static let flow =
        "FLOWTAB_APP_PANEL_PRESSURE_FLOW"
    static let scenario =
        "FLOWTAB_APP_PANEL_PRESSURE_SCENARIO"
    static let durationSeconds =
        "FLOWTAB_APP_PANEL_PRESSURE_DURATION_SECONDS"
    static let cooldownSeconds =
        "FLOWTAB_APP_PANEL_PRESSURE_COOLDOWN_SECONDS"
    static let metricsPath =
        "FLOWTAB_APP_PANEL_PRESSURE_METRICS_PATH"
}

enum AppPanelPressureUITestFlow: String {
    case application
    case applicationToWindow = "app-to-window"
    case search

    static func configured(
        environment: [String: String]
    ) -> AppPanelPressureUITestFlow {
        AppPanelPressureUITestFlow(
            rawValue:
                environment[
                    AppPanelPressureUITestEnvironment.flow
                ] ?? ""
        ) ?? .application
    }

    var interactionP95LimitMilliseconds: Double? {
        switch self {
        case .application:
            return 33.334
        case .applicationToWindow:
            return 35
        case .search:
            return nil
        }
    }
}

struct AppPanelPressureUITestScenario {
    let variant: String?
    let expectedAppCount: Int?
    let expectedOpenedWindowCount: Int?
    let expectedHighlightedWindowCount: Int?

    static func configured(
        environment: [String: String]
    ) -> AppPanelPressureUITestScenario {
        switch environment[
            AppPanelPressureUITestEnvironment.scenario
        ] {
        case "local":
            return AppPanelPressureUITestScenario(
                variant: nil,
                expectedAppCount: nil,
                expectedOpenedWindowCount: nil,
                expectedHighlightedWindowCount: nil
            )
        case "extreme":
            return AppPanelPressureUITestScenario(
                variant: "app-panel-pressure-extreme",
                expectedAppCount: 120,
                expectedOpenedWindowCount: 100,
                expectedHighlightedWindowCount: 5
            )
        default:
            return AppPanelPressureUITestScenario(
                variant: "app-panel-pressure-realistic",
                expectedAppCount: 24,
                expectedOpenedWindowCount: 5,
                expectedHighlightedWindowCount: 5
            )
        }
    }

    var runtimeArguments: [String] {
        guard let variant else { return [] }
        return [
            "--flowtab-ui-mock-runtime",
            "--flowtab-ui-mock-runtime-variant",
            variant,
            "--flowtab-ui-mock-window-previews"
        ]
    }

    func expectedAppID(index: Int) -> String? {
        guard variant != nil else { return nil }
        return String(
            format: "com.flowtab.pressure.app.%04d",
            index
        )
    }

    var searchQuery: String {
        variant == nil ? "Chrome" : "0001"
    }
}

enum AppPanelPressureUITestPolicy {
    static let warmupCycleCount = 5
    static let defaultDurationSeconds = 2.0
    static let defaultCooldownSeconds = 2.0
    static let eventWatchdogSeconds = 5.0
    static let commandReceiptRetrySeconds = 0.05
    static let projectionWatchdogSeconds = 5.0
    static let openP95LimitMilliseconds = 50.0

    static func duration(
        environment: [String: String]
    ) -> TimeInterval {
        max(
            1,
            Double(
                environment[
                    AppPanelPressureUITestEnvironment
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
                    AppPanelPressureUITestEnvironment
                        .cooldownSeconds
                ] ?? ""
            ) ?? defaultCooldownSeconds
        )
    }

    static func percentile95(_ values: [Double]) -> Double {
        precondition(!values.isEmpty)
        let ordered = values.sorted()
        let index = Int(
            ceil(Double(ordered.count) * 0.95)
        ) - 1
        return ordered[max(0, min(index, ordered.count - 1))]
    }
}

private enum AppPanelPressureStageMetricColumn {
    static let all = [
        "trigger_dispatch_ms",
        "main_preparation_ms",
        "session_directory_refresh_ms",
        "session_invalidation_ms",
        "session_state_reset_ms",
        "session_projection_ms",
        "session_recency_ms",
        "session_build_ms",
        "session_index_ms",
        "session_publish_ms",
        "session_load_wrapper_ms",
        "session_maintenance_request_ms",
        "session_controller_wrapper_ms",
        "screen_resolve_ms",
        "panel_size_ms",
        "panel_center_ms",
        "accessibility_sync_ms",
        "presentation_level_ms",
        "hide_non_panel_windows_ms",
        "initial_visibility_tracking_ms",
        "monitor_install_ms",
        "make_key_and_order_front_ms",
        "order_front_regardless_ms",
        "first_make_key_and_order_front_ms",
        "first_order_front_regardless_ms",
        "second_make_key_and_order_front_ms",
        "second_order_front_regardless_ms",
        "presentation_visibility_readback_ms",
        "auto_enter_schedule_ms",
        "presentation_wrapper_ms",
        "next_main_turn_ms",
        "layout_ms",
        "display_ms",
        "visibility_poll_wait_ms",
        "visibility_readback_ms",
        "visibility_wait_ms",
        "command_return_ms",
        "first_content_draw_ms",
        "panel_expose_ms",
        "occlusion_visible_ms",
        "window_readiness_read_ms",
        "window_maintenance_wait_ms",
        "window_session_switch_ms",
        "window_content_draw_ms",
        "search_debounce_ms",
        "search_computation_ms",
        "search_results_publish_ms",
        "search_shell_draw_ms",
        "search_first_row_draw_ms"
    ]
}

struct AppPanelPressureMetrics {
    private(set) var rows: [String] = [
        "kind,cycle,epoch_seconds,elapsed_ms,sequence,"
            + "panel_presented,user_visible,selected_app_id,"
            + "app_count,selected_window_count,"
            + AppPanelPressureStageMetricColumn.all
                .joined(separator: ",")
    ]

    mutating func mark(_ kind: String) {
        let base = [
            kind,
            "0",
            epochSeconds(),
            "0",
            "0",
            "0",
            "0",
            "none",
            "0",
            "0"
        ]
        rows.append(
            (base
                + Array(
                    repeating: "0",
                    count:
                        AppPanelPressureStageMetricColumn
                            .all.count
                ))
                .joined(separator: ",")
        )
    }

    mutating func append(
        _ evidence: AppPanelPressureUITestEvidence,
        cycle: Int
    ) {
        let base = [
                evidence.phase,
                String(cycle),
                epochSeconds(),
                String(
                    format: "%.6f",
                    evidence.elapsedMilliseconds
                ),
                String(evidence.sequence),
                evidence.panelPresented ? "1" : "0",
                evidence.userVisible ? "1" : "0",
                evidence.selectedAppID,
                String(evidence.appCount),
                String(evidence.selectedWindowCount)
            ]
        let stageValues =
            AppPanelPressureStageMetricColumn.all.map {
                String(
                    format: "%.6f",
                    evidence.stageMetrics[$0] ?? 0
                )
            }
        rows.append(
            (base + stageValues).joined(separator: ",")
        )
    }

    func write(to url: URL) throws {
        try rows.joined(separator: "\n")
            .appending("\n")
            .write(
                to: url,
                atomically: true,
                encoding: .utf8
            )
    }

    private func epochSeconds() -> String {
        String(
            format: "%.6f",
            Date().timeIntervalSince1970
        )
    }
}
