import datetime


def synthetic_inputs(
    open_stage_columns,
    event_stage_columns,
    open_ms=12.0,
    highlight_ms=8.0,
    rss_growth_kb=1024,
    cooldown_cpu=1.0,
):
    start = 2_000_000_000.0
    metrics = []
    for kind, timestamp in (
        ("measurement_start", start),
        ("cooldown_start", start + 120),
        ("cooldown_end", start + 135),
    ):
        marker = {
            "kind": kind,
            "cycle": "0",
            "epoch_seconds": str(timestamp),
            "elapsed_ms": "0",
            "sequence": "0",
            "panel_presented": "0",
            "user_visible": "0",
            "selected_app_id": "none",
            "app_count": "0",
            "selected_window_count": "0",
            "panel_width": "0",
            "visible_frame_width": "0",
            "visible_home_window_count": "0",
        }
        marker.update({column: "0" for column in open_stage_columns})
        marker.update({column: "0" for column in event_stage_columns})
        metrics.append(marker)
    base_open_stages = {
        "session_directory_refresh_ms": 0.85,
        "session_invalidation_ms": 0.05,
        "session_state_reset_ms": 0.03,
        "session_projection_ms": 1.0,
        "session_recency_ms": 0.5,
        "session_build_ms": 1.0,
        "session_index_ms": 0.2,
        "session_publish_ms": 0.3,
        "session_load_wrapper_ms": 0.02,
        "session_maintenance_request_ms": 0.04,
        "session_controller_wrapper_ms": 0.01,
        "screen_resolve_ms": 0.2,
        "panel_size_ms": 1.0,
        "panel_center_ms": 0.3,
        "accessibility_sync_ms": 0.5,
        "presentation_level_ms": 0.3,
        "hide_non_panel_windows_ms": 0.1,
        "initial_visibility_tracking_ms": 0.3,
        "monitor_install_ms": 0.5,
        "make_key_and_order_front_ms": 0.7,
        "order_front_regardless_ms": 0.1,
        "first_make_key_and_order_front_ms": 0.6,
        "first_order_front_regardless_ms": 0.05,
        "second_make_key_and_order_front_ms": 0.1,
        "second_order_front_regardless_ms": 0.05,
        "presentation_visibility_readback_ms": 0.3,
        "auto_enter_schedule_ms": 0.2,
        "presentation_wrapper_ms": 0.2,
        "next_main_turn_ms": 0.8,
        "layout_ms": 0.2,
        "display_ms": 0.3,
        "visibility_poll_wait_ms": 1.2,
        "visibility_readback_ms": 0.1,
        "visibility_wait_ms": 0.2,
    }
    diagnostic_stage_columns = {
        "make_key_and_order_front_ms",
        "order_front_regardless_ms",
    }
    partition_total = sum(
        value
        for column, value in base_open_stages.items()
        if column not in diagnostic_stage_columns
    )
    open_stage_scale = open_ms / partition_total
    sequence = 0
    for cycle in range(1, 41):
        for kind, elapsed, selected_index, windows, visible in (
            ("opened", open_ms, 1, 5, "1"),
            ("highlighted", highlight_ms, 2, 5, "1"),
            ("closed", 4.0, -1, 0, "0"),
        ):
            sequence += 1
            metric = {
                "kind": kind,
                "cycle": str(cycle),
                "epoch_seconds": str(start + cycle),
                "elapsed_ms": str(elapsed),
                "sequence": str(sequence),
                "panel_presented": visible,
                "user_visible": visible,
                "selected_app_id": (
                    f"com.flowtab.pressure.app.{selected_index:04d}"
                    if selected_index >= 0
                    else "none"
                ),
                "app_count": "24" if visible == "1" else "0",
                "selected_window_count": str(windows),
                "panel_width": "1120" if visible == "1" else "0",
                "visible_frame_width": "1440",
                "visible_home_window_count": "0",
            }
            metric.update({column: "0" for column in open_stage_columns})
            metric.update({column: "0" for column in event_stage_columns})
            if kind == "opened":
                metric["trigger_dispatch_ms"] = "0.2"
                metric["main_preparation_ms"] = "0.3"
                metric.update(
                    {
                        column: str(value * open_stage_scale)
                        for column, value in base_open_stages.items()
                    }
                )
                metric.update(
                    {
                        "command_return_ms": "3",
                        "first_content_draw_ms": "9",
                        "panel_expose_ms": "10",
                        "occlusion_visible_ms": "12",
                    }
                )
            elif kind == "highlighted":
                metric.update(
                    {
                        "command_return_ms": "1",
                        "first_content_draw_ms": "8",
                        "window_readiness_read_ms": "1.5",
                        "window_maintenance_wait_ms": "0",
                        "window_session_switch_ms": "3",
                        "window_content_draw_ms": "8",
                        "search_debounce_ms": "2",
                        "search_computation_ms": "1",
                        "search_results_publish_ms": "4",
                        "search_first_row_draw_ms": "8",
                    }
                )
            metrics.append(metric)
    samples = []
    base_rss = 120 * 1024
    for offset in range(0, 136):
        rss = base_rss + (rss_growth_kb if offset >= 96 else 0)
        cpu = cooldown_cpu if offset >= 128 else 40.0
        timestamp = datetime.datetime.fromtimestamp(
            start + offset,
            tz=datetime.timezone.utc,
        ).strftime("%Y-%m-%dT%H:%M:%SZ")
        samples.append(
            {
                "timestamp": timestamp,
                "cpu_percent": str(cpu),
                "rss_kb": str(rss),
            }
        )
    return metrics, samples


def run_self_test(evaluate, open_stage_columns, event_stage_columns):
    metrics, samples = synthetic_inputs(
        open_stage_columns,
        event_stage_columns,
    )
    passing = evaluate(
        metrics, samples, "application", "realistic", 120, 15
    )
    assert passing["verdict"] == "passed"
    breakdown = passing["open_stage_breakdown"]
    assert breakdown["available"]
    assert breakdown["complete_cycle_count"] == 40
    assert breakdown["reconciliation"][
        "absolute_difference_p95_ms"
    ] < 0.001
    assert passing["event_stage_breakdown"]["available"]
    assert abs(
        sum(
            group["mean_share_percent"]
            for group in breakdown["groups"].values()
        )
        - 100.0
    ) < 0.001
    for options in (
        {"open_ms": 51.0},
        {"rss_growth_kb": 40 * 1024},
        {"cooldown_cpu": 20.0},
    ):
        failing_metrics, failing_samples = synthetic_inputs(
            open_stage_columns,
            event_stage_columns,
            **options,
        )
        assert evaluate(
            failing_metrics,
            failing_samples,
            "application",
            "realistic",
            120,
            15,
        )["verdict"] == "failed"
    invalid_panel_metrics, invalid_panel_samples = synthetic_inputs(
        open_stage_columns,
        event_stage_columns,
    )
    invalid_panel_metrics[3]["panel_width"] = "1400"
    assert evaluate(
        invalid_panel_metrics,
        invalid_panel_samples,
        "application",
        "realistic",
        120,
        15,
    )["verdict"] == "failed"
    visible_home_metrics, visible_home_samples = synthetic_inputs(
        open_stage_columns,
        event_stage_columns,
    )
    visible_home_metrics[3]["visible_home_window_count"] = "1"
    assert evaluate(
        visible_home_metrics,
        visible_home_samples,
        "application",
        "realistic",
        120,
        15,
    )["verdict"] == "failed"
    flow_metrics, flow_samples = synthetic_inputs(
        open_stage_columns,
        event_stage_columns,
    )
    opened_by_cycle = {
        int(row["cycle"]): row
        for row in flow_metrics
        if row["kind"] == "opened"
    }
    for row in flow_metrics:
        if row["kind"] == "highlighted":
            opened = opened_by_cycle[int(row["cycle"])]
            row["selected_app_id"] = opened["selected_app_id"]
            row["selected_window_count"] = opened[
                "selected_window_count"
            ]
    for flow in ("app-to-window", "search"):
        assert evaluate(
            flow_metrics,
            flow_samples,
            flow,
            "realistic",
            120,
            15,
        )["verdict"] == "passed"
    local_metrics, local_samples = synthetic_inputs(
        open_stage_columns,
        event_stage_columns,
    )
    for row in local_metrics:
        cycle = int(row["cycle"])
        if cycle <= 0 or row["kind"] == "closed":
            continue
        row["app_count"] = str(6 + cycle % 3)
        row["selected_window_count"] = str(
            cycle % 4
            if row["kind"] == "opened"
            else 1 + cycle % 5
        )
    local = evaluate(
        local_metrics,
        local_samples,
        "application",
        "local",
        120,
        15,
    )
    assert local["verdict"] == "passed"
    assert local["app_count_min"] == 6
    assert local["app_count_max"] == 8
    invalid = [dict(row) for row in local_metrics]
    invalid[4]["selected_app_id"] = invalid[3]["selected_app_id"]
    assert evaluate(
        invalid,
        local_samples,
        "application",
        "local",
        120,
        15,
    )["verdict"] == "failed"
    print("Real-UI evidence gates latency, RSS plateau, and CPU return.")
