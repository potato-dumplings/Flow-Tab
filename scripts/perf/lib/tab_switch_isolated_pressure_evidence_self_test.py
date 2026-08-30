import os
import tempfile

from tab_switch_real_pressure_windows import (
    TAB_SWITCH_COMPLETION_MARKER,
    TAB_SWITCH_WARMUP_MARKER,
    select_resource_windows,
)


def runner_status(**overrides):
    status = {
        "stage": "evaluating",
        "duration_seconds": 1,
        "switch_interval_milliseconds": 100,
        "sample_interval_seconds": 0.05,
        "runtime_log_level": "ERROR",
        "max_runtime_log_mb_per_minute": None,
        "completion_evidence": "valid",
        "required_switches": 30,
        "completed_switches": 30,
        "home_switches": 10,
        "logs_switches": 10,
        "settings_switches": 10,
        "elapsed_nanoseconds": 1_000_000_000,
        "stress_started_uptime_nanoseconds": 1_000_000_000,
        "stress_completed_uptime_nanoseconds": 2_000_000_000,
        "app_pid": 42,
        "start_identity_captured": True,
        "identity_check_count": 22,
        "identity_verdict": "matched",
        "final_exit_code": 0,
        "xcodebuild_exit_code": 0,
        "build_log_exit_code": 0,
        "app_exit_code": 0,
        "sampling_failed": False,
        "evidence_parse_exit_code": 0,
    }
    status.update(overrides)
    return status


def sample(index, started, completed, cpu, rss_kb=140_000):
    return {
        "sample": index,
        "timestamp": f"2026-08-30T00:00:{index:02d}Z",
        "pid": 42,
        "interval_started_uptime_nanoseconds": started,
        "interval_completed_uptime_nanoseconds": completed,
        "cpu": cpu,
        "rss_kb": rss_kb,
    }


def resource_samples():
    values = [
        sample(1, 800_000_000, 900_000_000, 99),
    ]
    for index in range(20):
        values.append(
            sample(
                index + 2,
                1_000_000_000 + index * 50_000_000,
                1_050_000_000 + index * 50_000_000,
                10,
                140_000 + index * 10,
            )
        )
    values.append(sample(22, 2_100_000_000, 2_200_000_000, 88))
    return values


def run_self_test(evaluate):
    samples = resource_samples()
    with tempfile.TemporaryDirectory(
        prefix="flowtab-tab-isolated-evidence-"
    ) as runtime_home:
        result = evaluate(runner_status(), samples, runtime_home)
        assert result["verdict"] == "passed"
        assert result["schema_version"] == 5
        assert result["measurement_source"] == "active-window-v2"
        assert result["sample_count"] == 20
        assert result["whole_run_sample_count"] == 22
        assert result["cpu_percent"]["average"] == 10
        assert result["cpu_percent"]["max"] == 10
        assert result["diagnostic_resource_windows"]["whole_run"][
            "cpu_percent"
        ]["max"] == 99
        assert result["active_resource_coverage"]["ratio"] == 1

        weighted = [dict(item) for item in samples]
        weighted[1] = sample(
            2,
            1_000_000_000,
            1_010_000_000,
            100,
        )
        for index in range(2, 21):
            weighted[index][
                "interval_started_uptime_nanoseconds"
            ] = 1_010_000_000 + (index - 2) * 52_105_263
            weighted[index][
                "interval_completed_uptime_nanoseconds"
            ] = (
                1_010_000_000 + (index - 1) * 52_105_263
                if index < 20
                else 2_000_000_000
            )
            weighted[index]["cpu"] = 0
        weighted_result = evaluate(
            runner_status(), weighted, runtime_home
        )
        assert weighted_result["cpu_percent"]["average"] == 1

        boundary_samples = samples + [
            sample(23, 950_000_000, 1_050_000_000, 100),
            sample(24, 1_950_000_000, 2_050_000_000, 100),
        ]
        windows = select_resource_windows(
            boundary_samples,
            1_000_000_000,
            2_000_000_000,
        )
        assert len(windows["active"]) == 20

        sparse = [
            sample(1, 1_000_000_000, 1_200_000_000, 10),
            sample(2, 1_200_000_000, 1_400_000_000, 10),
            sample(3, 1_400_000_000, 1_600_000_000, 10),
        ]
        assert evaluate(runner_status(), sparse, runtime_home)[
            "verdict"
        ] == "failed"

        timing_failure = runner_status(
            stress_completed_uptime_nanoseconds=2_000_000_001
        )
        assert evaluate(timing_failure, samples, runtime_home)[
            "verdict"
        ] == "failed"

        identity_failure = runner_status(identity_verdict="changed")
        assert evaluate(identity_failure, samples, runtime_home)[
            "verdict"
        ] == "failed"
        assert evaluate(runner_status(), [], runtime_home)[
            "verdict"
        ] == "failed"

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
                "[2026-08-30] [DEBUG] [performance] "
                + TAB_SWITCH_WARMUP_MARKER
                + "\n"
                + "[2026-08-30] [DEBUG] [projection] activeEvent value=1\n"
                + "[2026-08-30] [DEBUG] [performance] "
                + TAB_SWITCH_COMPLETION_MARKER
                + "\n"
                + "[2026-08-30] [DEBUG] [projection] postflight value=1\n"
            )
        debug_result = evaluate(
            runner_status(runtime_log_level="DEBUG"),
            samples,
            runtime_home,
        )
        assert debug_result["verdict"] == "passed", [
            item for item in debug_result["gates"] if not item["passed"]
        ]
        assert debug_result["runtime_logs"]["window_satisfied"] is True
        assert debug_result["runtime_logs"]["line_count"] == 3
        assert debug_result["diagnostic_runtime_logs"]["whole_run"][
            "line_count"
        ] == 4

    print(
        "Isolated Tab pressure schema-v5 active-window resource, log, "
        "timing, coverage, and identity gates passed."
    )
