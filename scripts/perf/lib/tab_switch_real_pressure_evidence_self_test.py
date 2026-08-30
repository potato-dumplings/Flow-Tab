import os
import tempfile

from tab_switch_real_pressure_windows import (
    TAB_SWITCH_COMPLETION_MARKER,
    TAB_SWITCH_WARMUP_MARKER,
    select_resource_windows,
)


def run_self_test(evaluate, observer_install_evidence):
    stress_started = 1_000_000_000
    stress_completed = 2_000_000_000
    ui_status = {
        "state": "completed",
        "runtime_log_level": "ERROR",
        "accessibility_authorized": True,
        "screen_recording_authorized": True,
        "home_application_count": 3,
        "home_window_count": 2,
        "fixture_hit": True,
        "home_warmed": True,
        "logs_warmed": True,
        "settings_warmed": True,
        "required_switches": 3,
        "completed_switches": 3,
        "home_switches": 1,
        "logs_switches": 1,
        "settings_switches": 1,
        "stress_started_uptime_nanoseconds": stress_started,
        "stress_completed_uptime_nanoseconds": stress_completed,
        "elapsed_nanoseconds": 1_000_000_000,
        "duration_satisfied": True,
        "workload_satisfied": True,
    }
    runtime_status = {
        "final_exit_code": 0,
        "identity_verdict": "matched",
        "ui_result_bundle_valid": True,
    }
    samples = [
        {
            "cpu": 90.0,
            "rss_kb": 99_000,
            "interval_started_uptime_nanoseconds": 800_000_000,
            "interval_completed_uptime_nanoseconds": 900_000_000,
        }
    ]
    samples.extend(
        {
            "cpu": 10.0,
            "rss_kb": 100_000 + index * 10,
            "interval_started_uptime_nanoseconds": (
                stress_started + index * 50_000_000
            ),
            "interval_completed_uptime_nanoseconds": (
                stress_started + (index + 1) * 50_000_000
            ),
        }
        for index in range(20)
    )
    samples.append(
        {
            "cpu": 80.0,
            "rss_kb": 101_000,
            "interval_started_uptime_nanoseconds": 2_000_000_000,
            "interval_completed_uptime_nanoseconds": 2_100_000_000,
        }
    )
    with tempfile.TemporaryDirectory(
        prefix="flowtab-tab-real-evidence-"
    ) as runtime_home:
        result = evaluate(
            ui_status,
            runtime_status,
            samples,
            runtime_home,
            "ERROR",
            1.0,
            1,
            333.333,
            0,
        )
        assert result["verdict"] == "passed"
        assert result["schema_version"] == 2
        assert result["measurement_source"] == "active-window-v2"
        assert result["sample_count"] == 20
        assert result["whole_run_sample_count"] == 22
        assert result["cpu_percent"]["average"] == 10.0
        assert result["active_resource_coverage"]["ratio"] == 1.0
        assert result["diagnostic_resource_windows"][
            "preflight"
        ]["sample_count"] == 1
        assert result["diagnostic_resource_windows"][
            "postflight"
        ]["sample_count"] == 1

        boundary_samples = samples + [
            {
                "cpu": 100.0,
                "rss_kb": 100_000,
                "interval_started_uptime_nanoseconds": 950_000_000,
                "interval_completed_uptime_nanoseconds": 1_050_000_000,
            },
            {
                "cpu": 100.0,
                "rss_kb": 100_000,
                "interval_started_uptime_nanoseconds": 1_950_000_000,
                "interval_completed_uptime_nanoseconds": 2_050_000_000,
            },
        ]
        boundary_windows = select_resource_windows(
            boundary_samples,
            stress_started,
            stress_completed,
        )
        assert len(boundary_windows["active"]) == 20

        legacy_status = dict(ui_status)
        legacy_status.pop("stress_started_uptime_nanoseconds")
        legacy_status.pop("stress_completed_uptime_nanoseconds")
        legacy_samples = [
            {"cpu": row["cpu"], "rss_kb": row["rss_kb"]}
            for row in samples
        ]
        legacy_result = evaluate(
            legacy_status,
            runtime_status,
            legacy_samples,
            runtime_home,
            "ERROR",
            None,
            1,
            333.333,
            0,
        )
        assert legacy_result["measurement_source"] == (
            "whole-run-legacy-v1"
        )
        assert legacy_result["sample_count"] == 0
        assert legacy_result["whole_run_sample_count"] == 22
        assert legacy_result["verdict"] == "failed"

        denied = dict(ui_status)
        denied["state"] = "permission_blocked"
        denied["screen_recording_authorized"] = False
        assert evaluate(
            denied,
            runtime_status,
            samples,
            runtime_home,
            "ERROR",
            None,
            1,
            333.333,
            0,
        )["verdict"] == "environment_blocked"

        log_directory = os.path.join(
            runtime_home,
            "Library",
            "Application Support",
            "FlowTab",
            "logs",
        )
        os.makedirs(log_directory)
        with open(
            os.path.join(log_directory, "Flow_Tab_1.log"),
            "w",
            encoding="utf-8",
        ) as handle:
            handle.write(
                "homeAXObserverInstall result=installed "
                "appID=com.example.prewarm pid=1 retryAttempt=0\n"
                "[2026-08-30] [DEBUG] [performance] "
                + TAB_SWITCH_WARMUP_MARKER
                + "\n"
                + "[2026-08-30] [DEBUG] [performance] "
                + "tabSwitchLayout phase=active\n"
            )
        with open(
            os.path.join(log_directory, "Flow_Tab_2.log"),
            "w",
            encoding="utf-8",
        ) as handle:
            handle.write(
                "runtimeAXObserverInstall result=installed "
                "appID=com.example.current pid=2 retryAttempt=0\n"
                + "homeAXObserverInstall result=installed "
                "appID=com.example.historical pid=3 retryAttempt=0\n"
                + "runtimeAXObserverInstall result=installed "
                "appID=com.example.current pid=2 retryAttempt=1\n"
                + "runtimeAXObserverRetry result=succeeded "
                "appID=com.example.current pid=2\n"
                + "[2026-08-30] [DEBUG] [performance] "
                + TAB_SWITCH_COMPLETION_MARKER
                + "\n"
                + "[2026-08-30] [DEBUG] [performance] "
                + "postflightEvent value=ignored\n"
            )
        debug_status = dict(ui_status)
        debug_status["runtime_log_level"] = "DEBUG"
        debug_result = evaluate(
            debug_status,
            runtime_status,
            samples,
            runtime_home,
            "DEBUG",
            100.0,
            1,
            333.333,
            0,
        )
        assert debug_result["verdict"] == "passed"
        assert debug_result["runtime_logs"]["window_satisfied"] is True
        assert debug_result["runtime_logs"]["file_count"] == 2
        assert debug_result["runtime_logs"]["line_count"] == 7
        assert debug_result["runtime_logs"]["dominant_categories"]
        assert debug_result["runtime_logs"]["dominant_events"]
        assert debug_result["diagnostic_runtime_logs"][
            "whole_run"
        ]["retained_bytes"] > debug_result["runtime_logs"][
            "retained_bytes"
        ]

        observer_evidence = observer_install_evidence(runtime_home)
        assert observer_evidence["warmup_marker_count"] == 1
        assert observer_evidence["all_successful_install_count"] == 4
        assert observer_evidence[
            "post_warmup_successful_install_count"
        ] == 3
        assert observer_evidence[
            "post_warmup_unique_binding_count"
        ] == 2
        assert observer_evidence[
            "post_warmup_retry_install_count"
        ] == 1
        assert observer_evidence[
            "post_warmup_current_install_event_count"
        ] == 2
        assert observer_evidence[
            "post_warmup_historical_install_event_count"
        ] == 1
        assert observer_evidence["structure_satisfied"] is True

    print(
        "Real Tab pressure active-window resource, log, permission, "
        "fixture, tab, and RSS gates passed."
    )
