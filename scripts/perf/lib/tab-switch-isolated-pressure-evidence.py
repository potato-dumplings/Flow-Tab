#!/usr/bin/env python3
import argparse
import csv
import json
import math
import os
import sys

from tab_switch_real_pressure_windows import (
    ACTIVE_RESOURCE_COVERAGE_MINIMUM,
    LOG_CAPACITY,
    active_log_volume,
    log_volume,
    select_resource_windows,
    summarize_resources,
)


SCHEMA_VERSION = 5
MEASUREMENT_WINDOW = "active_tab_switch"
MEASUREMENT_SOURCE = "active-window-v2"


def gate(name, passed, observed, expected):
    return {
        "name": name,
        "passed": bool(passed),
        "observed": observed,
        "expected": expected,
    }


def numeric_value(value, fallback=0):
    if value is None or isinstance(value, bool):
        return fallback
    return value


def integer_value(value, fallback=0):
    try:
        return int(numeric_value(value, fallback))
    except (TypeError, ValueError):
        return fallback


def optional_integer(value):
    if value is None or isinstance(value, bool):
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def float_value(value, fallback=0.0):
    try:
        return float(numeric_value(value, fallback))
    except (TypeError, ValueError):
        return fallback


def load_json_or_empty(path):
    try:
        with open(path, encoding="utf-8") as handle:
            value = json.load(handle)
        if not isinstance(value, dict):
            return {}, "runner_status_not_object"
        return value, None
    except (OSError, json.JSONDecodeError) as error:
        return {}, str(error)


def load_samples(path):
    samples = []
    try:
        with open(path, newline="", encoding="utf-8") as handle:
            rows = list(csv.DictReader(handle))
        for row in rows:
            samples.append(
                {
                    "sample": int(row["sample"]),
                    "timestamp": row["timestamp"],
                    "pid": int(row["pid"]),
                    "interval_started_uptime_nanoseconds": int(
                        row["interval_started_uptime_nanoseconds"]
                    ),
                    "interval_completed_uptime_nanoseconds": int(
                        row["interval_completed_uptime_nanoseconds"]
                    ),
                    "cpu": float(row["cpu_percent"]),
                    "rss_kb": float(row["rss_kb"]),
                }
            )
    except (OSError, KeyError, TypeError, ValueError) as error:
        return [], str(error)
    return samples, None


def sample_integrity(samples, expected_pid, load_error):
    if load_error is not None:
        return False, {"condition": "load_failed", "error": load_error}
    if not samples:
        return False, {"condition": "empty", "sample_count": 0}

    previous_completed = None
    for expected_index, sample in enumerate(samples, start=1):
        started = sample["interval_started_uptime_nanoseconds"]
        completed = sample["interval_completed_uptime_nanoseconds"]
        cpu = sample["cpu"]
        rss_kb = sample["rss_kb"]
        if (
            sample["sample"] != expected_index
            or sample["pid"] != expected_pid
            or not sample["timestamp"]
            or started <= 0
            or completed <= started
            or (previous_completed is not None and started < previous_completed)
            or not math.isfinite(cpu)
            or cpu < 0
            or not math.isfinite(rss_kb)
            or rss_kb <= 0
        ):
            return False, {
                "condition": "invalid_sample",
                "sample": sample["sample"],
            }
        previous_completed = completed
    return True, {
        "condition": "valid",
        "sample_count": len(samples),
        "pid": expected_pid,
    }


def with_retention_estimate(volume):
    result = dict(volume)
    rate = result.get("bytes_per_second", 0)
    result["estimated_20mb_retention_minutes"] = (
        20_000_000 / rate / 60 if rate > 0 else None
    )
    return result


def unavailable_log_volume():
    return {
        "file_count": None,
        "line_count": None,
        "retained_bytes": None,
        "bytes_per_second": None,
        "megabytes_per_minute": None,
        "bytes_per_completed_switch": None,
        "capacity_saturated": None,
        "started_marker_count": None,
        "completed_marker_count": None,
        "window_satisfied": None,
        "dominant_categories": [],
        "dominant_events": [],
        "estimated_20mb_retention_minutes": None,
    }


def evaluate(runner_status, samples, runtime_home, sample_load_error=None):
    required_switches_value = optional_integer(
        runner_status.get("required_switches")
    )
    completed_switches_value = optional_integer(
        runner_status.get("completed_switches")
    )
    home_switches_value = optional_integer(
        runner_status.get("home_switches")
    )
    logs_switches_value = optional_integer(
        runner_status.get("logs_switches")
    )
    settings_switches_value = optional_integer(
        runner_status.get("settings_switches")
    )
    elapsed_nanoseconds_value = optional_integer(
        runner_status.get("elapsed_nanoseconds")
    )
    required_switches = required_switches_value or 0
    completed_switches = completed_switches_value or 0
    home_switches = home_switches_value or 0
    logs_switches = logs_switches_value or 0
    settings_switches = settings_switches_value or 0
    elapsed_nanoseconds = elapsed_nanoseconds_value or 0
    elapsed_seconds = elapsed_nanoseconds / 1_000_000_000
    stress_started_value = optional_integer(
        runner_status.get("stress_started_uptime_nanoseconds")
    )
    stress_completed_value = optional_integer(
        runner_status.get("stress_completed_uptime_nanoseconds")
    )
    stress_started = stress_started_value or 0
    stress_completed = stress_completed_value or 0
    observed_window_duration = stress_completed - stress_started
    active_window_timing_satisfied = (
        stress_started > 0
        and stress_completed > stress_started
        and observed_window_duration == elapsed_nanoseconds
    )
    expected_pid = integer_value(runner_status.get("app_pid"))
    samples_satisfied, sample_evidence = sample_integrity(
        samples,
        expected_pid,
        sample_load_error,
    )

    completion_evidence_valid = (
        runner_status.get("completion_evidence") == "valid"
    )
    resource_windows = select_resource_windows(
        samples,
        stress_started if completion_evidence_valid else 0,
        stress_completed if completion_evidence_valid else 0,
    )
    active_resources = summarize_resources(resource_windows["active"])
    preflight_resources = summarize_resources(
        resource_windows["preflight"]
    )
    postflight_resources = summarize_resources(
        resource_windows["postflight"]
    )
    whole_run_resources = summarize_resources(samples)
    active_covered_duration = active_resources[
        "covered_duration_nanoseconds"
    ]
    active_resource_coverage = (
        active_covered_duration / elapsed_nanoseconds
        if elapsed_nanoseconds > 0
        else 0
    )
    cpu_time_per_completed_switch = (
        active_resources["processor_time_milliseconds"]
        / completed_switches
        if completed_switches > 0
        else None
    )

    runtime_log_level = str(
        runner_status.get("runtime_log_level", "ERROR")
    )
    runtime_log_budget = runner_status.get(
        "max_runtime_log_mb_per_minute"
    )
    if runtime_log_budget is not None:
        runtime_log_budget = float_value(runtime_log_budget)
    active_volume = with_retention_estimate(
        active_log_volume(
            runtime_home,
            elapsed_seconds,
            completed_switches,
        )
    )
    whole_run_volume = with_retention_estimate(
        log_volume(
            runtime_home,
            elapsed_seconds,
            completed_switches,
        )
    )
    formal_active_volume = (
        active_volume
        if completion_evidence_valid
        else unavailable_log_volume()
    )
    log_budget_satisfied = (
        runtime_log_budget is None
        or active_volume["megabytes_per_minute"] <= runtime_log_budget
    )

    app_exit_code = runner_status.get("app_exit_code")
    runner_execution = {
        "final_exit_code": runner_status.get("final_exit_code"),
        "xcodebuild_exit_code": runner_status.get(
            "xcodebuild_exit_code"
        ),
        "build_log_exit_code": runner_status.get(
            "build_log_exit_code"
        ),
        "app_exit_code": app_exit_code,
        "sampling_failed": runner_status.get("sampling_failed", True),
        "evidence_parse_exit_code": runner_status.get(
            "evidence_parse_exit_code"
        ),
    }
    identity_evidence = {
        "pid": expected_pid if expected_pid > 0 else None,
        "start_identity_captured": runner_status.get(
            "start_identity_captured", False
        ),
        "check_count": integer_value(
            runner_status.get("identity_check_count")
        ),
        "verdict": runner_status.get(
            "identity_verdict", "not_evaluated"
        ),
    }
    active_rss = active_resources["rss_mb"]

    gates = [
        gate(
            "runner_execution",
            runner_status.get("final_exit_code") == 0
            and runner_status.get("xcodebuild_exit_code") == 0
            and runner_status.get("build_log_exit_code") == 0
            and app_exit_code == 0
            and runner_status.get("sampling_failed") is False
            and runner_status.get("evidence_parse_exit_code") == 0,
            runner_execution,
            "build, app, sampling, and evidence parsing passed",
        ),
        gate(
            "process_identity",
            identity_evidence["start_identity_captured"] is True
            and identity_evidence["check_count"] > 0
            and identity_evidence["verdict"] == "matched",
            identity_evidence,
            "one stable launched process identity",
        ),
        gate(
            "completion_evidence",
            runner_status.get("completion_evidence") == "valid",
            runner_status.get("completion_evidence"),
            "valid",
        ),
        gate(
            "completed_switches",
            required_switches > 0
            and completed_switches == required_switches,
            completed_switches,
            required_switches,
        ),
        gate(
            "per_tab_switches",
            home_switches > 0
            and logs_switches > 0
            and settings_switches > 0
            and home_switches + logs_switches + settings_switches
            == completed_switches,
            {
                "home": home_switches,
                "logs": logs_switches,
                "settings": settings_switches,
            },
            "each > 0 and sum == completed",
        ),
        gate(
            "active_resource_window",
            active_window_timing_satisfied,
            {
                "started_uptime_nanoseconds": stress_started,
                "completed_uptime_nanoseconds": stress_completed,
                "elapsed_nanoseconds": elapsed_nanoseconds,
                "observed_duration_nanoseconds": observed_window_duration,
            },
            "valid monotonic bounds with duration matching elapsed",
        ),
        gate(
            "sample_integrity",
            samples_satisfied,
            sample_evidence,
            "sequential finite intervals from the launched pid",
        ),
        gate(
            "resource_samples",
            active_resources["sample_count"] >= 3,
            active_resources["sample_count"],
            ">=3 active samples",
        ),
        gate(
            "active_resource_coverage",
            active_resource_coverage
            >= ACTIVE_RESOURCE_COVERAGE_MINIMUM,
            active_resource_coverage,
            f">={ACTIVE_RESOURCE_COVERAGE_MINIMUM}",
        ),
        gate(
            "rss_plateau",
            active_rss["middle_sample_count"] >= 2
            and active_rss["late_sample_count"] >= 2
            and active_rss["plateau_growth"] is not None
            and active_rss["plateau_growth"]
            <= active_rss["plateau_growth_limit"],
            active_rss["plateau_growth"],
            f"<={active_rss['plateau_growth_limit']} MB",
        ),
        gate(
            "runtime_log_window",
            runtime_log_level != "DEBUG"
            or active_volume["window_satisfied"],
            {
                "started_markers": active_volume[
                    "started_marker_count"
                ],
                "completed_markers": active_volume[
                    "completed_marker_count"
                ],
            },
            (
                "exactly one started marker and one completed marker"
                if runtime_log_level == "DEBUG"
                else "evaluated by paired DEBUG run"
            ),
        ),
        gate(
            "runtime_log_capacity",
            not whole_run_volume["capacity_saturated"],
            whole_run_volume["file_count"],
            f"<{LOG_CAPACITY}",
        ),
        gate(
            "runtime_log_budget",
            log_budget_satisfied,
            active_volume["megabytes_per_minute"],
            (
                f"<={runtime_log_budget}"
                if runtime_log_budget is not None
                else "disabled"
            ),
        ),
    ]
    verdict = "passed" if all(item["passed"] for item in gates) else "failed"

    return {
        "schema_version": SCHEMA_VERSION,
        "runner_kind": "tab_switch_stress",
        "lane": "isolated_state_log",
        "stage": "completed" if verdict == "passed" else runner_status.get(
            "stage", "evidence_failed"
        ),
        "measurement_window": MEASUREMENT_WINDOW,
        "measurement_source": MEASUREMENT_SOURCE,
        "verdict": verdict,
        "duration_seconds": float_value(
            runner_status.get("duration_seconds")
        ),
        "switch_interval_milliseconds": float_value(
            runner_status.get("switch_interval_milliseconds")
        ),
        "sample_interval_seconds": float_value(
            runner_status.get("sample_interval_seconds")
        ),
        "runtime_log_level": runtime_log_level,
        "max_runtime_log_mb_per_minute": runtime_log_budget,
        "permissions": {
            "accessibility": False,
            "screen_recording": None,
        },
        "completion_evidence": runner_status.get(
            "completion_evidence", "not_read"
        ),
        "required_switches": required_switches_value,
        "completed_switches": completed_switches_value,
        "home_switches": home_switches_value,
        "logs_switches": logs_switches_value,
        "settings_switches": settings_switches_value,
        "elapsed_seconds": (
            elapsed_seconds
            if elapsed_nanoseconds_value is not None
            else None
        ),
        "stress_started_uptime_nanoseconds": stress_started_value,
        "stress_completed_uptime_nanoseconds": stress_completed_value,
        "throughput_switches_per_second": (
            completed_switches / elapsed_seconds
            if elapsed_seconds > 0
            else None
        ),
        "active_resource_coverage": {
            "ratio": (
                active_resource_coverage
                if completion_evidence_valid
                and elapsed_nanoseconds_value is not None
                else None
            ),
            "covered_duration_nanoseconds": (
                active_covered_duration
                if completion_evidence_valid
                else None
            ),
            "required_ratio": ACTIVE_RESOURCE_COVERAGE_MINIMUM,
        },
        "sample_count": active_resources["sample_count"],
        "whole_run_sample_count": len(samples),
        "cpu_percent": active_resources["cpu_percent"],
        "cpu_time_milliseconds_per_completed_switch": (
            cpu_time_per_completed_switch
        ),
        "rss_mb": active_rss,
        "runtime_logs": formal_active_volume,
        "diagnostic_runtime_logs": {"whole_run": whole_run_volume},
        "diagnostic_resource_windows": {
            "preflight": preflight_resources,
            "postflight": postflight_resources,
            "whole_run": whole_run_resources,
            "unclassified_sample_count": (
                len(samples)
                - preflight_resources["sample_count"]
                - active_resources["sample_count"]
                - postflight_resources["sample_count"]
            ),
        },
        "process_identity": identity_evidence,
        "runner_execution": runner_execution,
        "gates": gates,
    }


def write_atomically(path, content):
    temporary = path + ".tmp"
    try:
        os.unlink(temporary)
    except FileNotFoundError:
        pass
    with open(temporary, "x", encoding="utf-8") as handle:
        handle.write(content)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, path)


def render_summary(result):
    cpu = result["cpu_percent"]
    rss = result["rss_mb"]
    coverage = result["active_resource_coverage"]
    active_logs = result["runtime_logs"]
    whole_resources = result["diagnostic_resource_windows"]["whole_run"]
    whole_logs = result["diagnostic_runtime_logs"]["whole_run"]
    lines = [
        "FlowTab isolated-state/log Tab pressure",
        f"verdict={result['verdict']}",
        f"schema_version={result['schema_version']}",
        f"measurement_window={result['measurement_window']}",
        f"measurement_source={result['measurement_source']}",
        f"duration_seconds={result['duration_seconds']}",
        "switch_interval_milliseconds="
        + str(result["switch_interval_milliseconds"]),
        f"completed_switches={result['completed_switches']}",
        "tab_switches="
        + f"home:{result['home_switches']},"
        + f"logs:{result['logs_switches']},"
        + f"settings:{result['settings_switches']}",
        "active_cpu_percent="
        + f"avg:{cpu['average']},p95:{cpu['p95']},max:{cpu['max']}",
        "active_resource_coverage="
        + f"ratio:{coverage['ratio']},"
        + f"samples:{result['sample_count']},"
        + f"whole_run_samples:{result['whole_run_sample_count']}",
        "active_rss_mb="
        + f"avg:{rss['average']},p95:{rss['p95']},max:{rss['max']},"
        + f"plateau_growth:{rss['plateau_growth']}",
        "active_runtime_logs="
        + f"bytes:{active_logs['retained_bytes']},"
        + "megabytes_per_minute:"
        + str(active_logs["megabytes_per_minute"]),
        "whole_run_diagnostics="
        + f"cpu_max:{whole_resources['cpu_percent']['max']},"
        + f"rss_max:{whole_resources['rss_mb']['max']},"
        + f"log_bytes:{whole_logs['retained_bytes']}",
    ]
    lines.extend(
        f"gate.{item['name']}={'passed' if item['passed'] else 'failed'}"
        for item in result["gates"]
    )
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    evaluate_parser = subparsers.add_parser("evaluate")
    evaluate_parser.add_argument("--runner-status", required=True)
    evaluate_parser.add_argument("--samples", required=True)
    evaluate_parser.add_argument("--runtime-home", required=True)
    evaluate_parser.add_argument("--output", required=True)
    evaluate_parser.add_argument("--summary", required=True)
    subparsers.add_parser("self-test")
    arguments = parser.parse_args()

    if arguments.command == "self-test":
        from tab_switch_isolated_pressure_evidence_self_test import (
            run_self_test,
        )

        run_self_test(evaluate)
        return 0

    runner_status, runner_load_error = load_json_or_empty(
        arguments.runner_status
    )
    samples, sample_load_error = load_samples(arguments.samples)
    if runner_load_error is not None:
        runner_status["stage"] = "runner_status_unavailable"
        runner_status["runner_status_load_error"] = runner_load_error
    result = evaluate(
        runner_status,
        samples,
        os.path.abspath(arguments.runtime_home),
        sample_load_error,
    )
    try:
        write_atomically(
            arguments.output,
            json.dumps(result, indent=2, sort_keys=True) + "\n",
        )
        write_atomically(arguments.summary, render_summary(result))
    except OSError as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0 if result["verdict"] == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())
