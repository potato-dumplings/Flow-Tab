#!/usr/bin/env python3
import argparse
import csv
import json
import math
import os
import sys
import tempfile


LOG_CAPACITY = 20
RSS_ABSOLUTE_GROWTH_ALLOWANCE_KB = 32 * 1024
RSS_RELATIVE_GROWTH_ALLOWANCE = 0.15


def percentile(values, value):
    ordered = sorted(values)
    if not ordered:
        return None
    index = math.ceil(len(ordered) * value / 100.0) - 1
    return ordered[max(0, min(index, len(ordered) - 1))]


def load_json(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def load_json_or(path, fallback):
    return load_json(path) if os.path.isfile(path) else fallback


def load_samples(path):
    with open(path, newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    return [
        {
            "cpu": float(row["cpu_percent"]),
            "rss_kb": float(row["rss_kb"]),
        }
        for row in rows
    ]


def load_samples_or_empty(path):
    return load_samples(path) if os.path.isfile(path) else []


def log_volume(runtime_home, elapsed_seconds, completed_switches):
    directory = os.path.join(
        runtime_home,
        "Library",
        "Application Support",
        "FlowTab",
        "logs",
    )
    paths = []
    if os.path.isdir(directory):
        paths = [
            os.path.join(directory, name)
            for name in sorted(os.listdir(directory))
            if name.endswith(".log")
        ]
    retained_bytes = sum(os.path.getsize(path) for path in paths)
    line_count = 0
    for path in paths:
        with open(path, "rb") as handle:
            line_count += sum(1 for _ in handle)
    seconds = max(elapsed_seconds, 0.000001)
    switches = max(completed_switches, 1)
    return {
        "file_count": len(paths),
        "line_count": line_count,
        "retained_bytes": retained_bytes,
        "bytes_per_second": retained_bytes / seconds,
        "megabytes_per_minute": (
            retained_bytes * 60 / seconds / 1_000_000
        ),
        "bytes_per_completed_switch": retained_bytes / switches,
        "capacity_saturated": len(paths) >= LOG_CAPACITY,
    }


def gate(name, passed, observed, expected):
    return {
        "name": name,
        "passed": bool(passed),
        "observed": observed,
        "expected": expected,
    }


def evaluate(
    ui_status,
    runtime_status,
    samples,
    runtime_home,
    runtime_log_level,
    runtime_log_budget,
    duration_seconds,
    interval_milliseconds,
    runtime_exit_code,
):
    ui_state = ui_status.get("state")
    environment_blocked = ui_state in {
        "environment_blocked",
        "permission_blocked",
        "fixture_projection_blocked",
    }
    elapsed_nanoseconds = int(
        ui_status.get("elapsed_nanoseconds", 0)
    )
    elapsed_seconds = elapsed_nanoseconds / 1_000_000_000
    completed_switches = int(
        ui_status.get("completed_switches", 0)
    )
    required_switches = int(ui_status.get("required_switches", 0))
    home_switches = int(ui_status.get("home_switches", 0))
    logs_switches = int(ui_status.get("logs_switches", 0))
    settings_switches = int(ui_status.get("settings_switches", 0))
    volume = log_volume(
        runtime_home,
        elapsed_seconds,
        completed_switches,
    )

    cpu_values = [row["cpu"] for row in samples]
    rss_values = [row["rss_kb"] for row in samples]
    warmup_index = min(len(samples), math.ceil(len(samples) * 0.2))
    plateau = samples[warmup_index:]
    middle_start = math.floor(len(plateau) * 0.25)
    middle_end = max(middle_start + 1, math.ceil(len(plateau) * 0.5))
    late_start = math.floor(len(plateau) * 0.75)
    middle_rss = [
        row["rss_kb"] for row in plateau[middle_start:middle_end]
    ]
    late_rss = [row["rss_kb"] for row in plateau[late_start:]]
    middle_rss_p95 = percentile(middle_rss, 95)
    late_rss_p95 = percentile(late_rss, 95)
    rss_growth_kb = (
        late_rss_p95 - middle_rss_p95
        if middle_rss_p95 is not None and late_rss_p95 is not None
        else math.inf
    )
    rss_growth_limit_kb = (
        max(
            RSS_ABSOLUTE_GROWTH_ALLOWANCE_KB,
            middle_rss_p95 * RSS_RELATIVE_GROWTH_ALLOWANCE,
        )
        if middle_rss_p95 is not None
        else 0
    )
    rss_growth_observed = (
        rss_growth_kb if math.isfinite(rss_growth_kb) else None
    )
    log_budget_satisfied = (
        runtime_log_budget is None
        or volume["megabytes_per_minute"] <= runtime_log_budget
    )

    gates = [
        gate(
            "ui_preflight_and_completion",
            ui_status.get("state") == "completed",
            ui_status.get("state"),
            "completed",
        ),
        gate(
            "accessibility_permission",
            ui_status.get("accessibility_authorized") is True,
            ui_status.get("accessibility_authorized"),
            True,
        ),
        gate(
            "screen_recording_permission",
            ui_status.get("screen_recording_authorized") is True,
            ui_status.get("screen_recording_authorized"),
            True,
        ),
        gate(
            "fixture_home_projection",
            ui_status.get("fixture_hit") is True
            and int(ui_status.get("home_application_count", 0)) > 0
            and int(ui_status.get("home_window_count", 0)) > 0,
            {
                "fixture_hit": ui_status.get("fixture_hit"),
                "applications": ui_status.get("home_application_count"),
                "windows": ui_status.get("home_window_count"),
            },
            "fixture=true, applications>0, windows>0",
        ),
        gate(
            "page_warmup",
            all(
                ui_status.get(key) is True
                for key in (
                    "home_warmed",
                    "logs_warmed",
                    "settings_warmed",
                )
            ),
            {
                key: ui_status.get(key)
                for key in (
                    "home_warmed",
                    "logs_warmed",
                    "settings_warmed",
                )
            },
            "all true",
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
            "duration",
            ui_status.get("duration_satisfied") is True
            and elapsed_seconds >= duration_seconds,
            elapsed_seconds,
            f">={duration_seconds}",
        ),
        gate(
            "workload",
            ui_status.get("workload_satisfied") is True,
            ui_status.get("workload_satisfied"),
            True,
        ),
        gate(
            "runtime_log_level",
            ui_status.get("runtime_log_level") == runtime_log_level,
            ui_status.get("runtime_log_level"),
            runtime_log_level,
        ),
        gate(
            "runtime_pressure",
            runtime_exit_code == 0
            and runtime_status.get("final_exit_code") == 0
            and runtime_status.get("identity_verdict") == "matched"
            and runtime_status.get("ui_result_bundle_valid") is True,
            {
                "exit_code": runtime_exit_code,
                "status_exit_code": runtime_status.get(
                    "final_exit_code"
                ),
                "identity": runtime_status.get("identity_verdict"),
                "xcresult": runtime_status.get(
                    "ui_result_bundle_valid"
                ),
            },
            "all passed",
        ),
        gate("resource_samples", len(samples) >= 3, len(samples), ">=3"),
        gate(
            "rss_plateau",
            len(middle_rss) >= 2
            and len(late_rss) >= 2
            and rss_growth_kb <= rss_growth_limit_kb,
            rss_growth_observed,
            f"<={rss_growth_limit_kb}",
        ),
        gate(
            "runtime_log_capacity",
            not volume["capacity_saturated"],
            volume["file_count"],
            f"<{LOG_CAPACITY}",
        ),
        gate(
            "runtime_log_budget",
            log_budget_satisfied,
            volume["megabytes_per_minute"],
            (
                f"<={runtime_log_budget}"
                if runtime_log_budget is not None
                else "disabled"
            ),
        ),
    ]
    return {
        "schema_version": 1,
        "runner_kind": "tab_switch_real_pressure",
        "lane": "real_permissions",
        "verdict": (
            "environment_blocked"
            if environment_blocked
            else (
                "passed"
                if all(item["passed"] for item in gates)
                else "failed"
            )
        ),
        "environment_block_reason": (
            ui_state if environment_blocked else None
        ),
        "duration_seconds": duration_seconds,
        "switch_interval_milliseconds": interval_milliseconds,
        "runtime_log_level": runtime_log_level,
        "max_runtime_log_mb_per_minute": runtime_log_budget,
        "permissions": {
            "accessibility": ui_status.get(
                "accessibility_authorized", False
            ),
            "screen_recording": ui_status.get(
                "screen_recording_authorized", False
            ),
        },
        "home_application_count": ui_status.get(
            "home_application_count", 0
        ),
        "home_window_count": ui_status.get("home_window_count", 0),
        "fixture_bundle_identifier": ui_status.get(
            "fixture_bundle_identifier", ""
        ),
        "fixture_hit": ui_status.get("fixture_hit", False),
        "page_warmup": {
            "home": ui_status.get("home_warmed", False),
            "logs": ui_status.get("logs_warmed", False),
            "settings": ui_status.get("settings_warmed", False),
        },
        "required_switches": required_switches,
        "completed_switches": completed_switches,
        "home_switches": home_switches,
        "logs_switches": logs_switches,
        "settings_switches": settings_switches,
        "elapsed_seconds": elapsed_seconds,
        "sample_count": len(samples),
        "cpu_percent": {
            "average": (
                sum(cpu_values) / len(cpu_values) if cpu_values else None
            ),
            "p95": percentile(cpu_values, 95),
            "max": max(cpu_values) if cpu_values else None,
        },
        "rss_mb": {
            "average": (
                sum(rss_values) / len(rss_values) / 1024
                if rss_values
                else None
            ),
            "p95": (
                percentile(rss_values, 95) / 1024
                if rss_values
                else None
            ),
            "max": max(rss_values) / 1024 if rss_values else None,
            "middle_p95": (
                middle_rss_p95 / 1024
                if middle_rss_p95 is not None
                else None
            ),
            "late_p95": (
                late_rss_p95 / 1024
                if late_rss_p95 is not None
                else None
            ),
            "plateau_growth": (
                rss_growth_kb / 1024
                if math.isfinite(rss_growth_kb)
                else None
            ),
        },
        "runtime_logs": volume,
        "runtime_pressure": runtime_status,
        "gates": gates,
    }


def write_atomically(path, content):
    temporary = path + ".tmp"
    with open(temporary, "x", encoding="utf-8") as handle:
        handle.write(content)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, path)


def render_summary(result):
    cpu = result["cpu_percent"]
    rss = result["rss_mb"]
    lines = [
        "FlowTab real-permission Tab pressure",
        f"verdict={result['verdict']}",
        f"duration_seconds={result['duration_seconds']}",
        f"switch_interval_milliseconds={result['switch_interval_milliseconds']}",
        f"completed_switches={result['completed_switches']}",
        "tab_switches="
        + f"home:{result['home_switches']},"
        + f"logs:{result['logs_switches']},"
        + f"settings:{result['settings_switches']}",
        "cpu_percent="
        + f"avg:{cpu['average']},p95:{cpu['p95']},max:{cpu['max']}",
        "rss_mb="
        + f"avg:{rss['average']},p95:{rss['p95']},max:{rss['max']},"
        + f"plateau_growth:{rss['plateau_growth']}",
    ]
    lines.extend(
        f"gate.{item['name']}={'passed' if item['passed'] else 'failed'}"
        for item in result["gates"]
    )
    return "\n".join(lines) + "\n"


def self_test():
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
        {"cpu": 10.0, "rss_kb": 100_000 + index * 10}
        for index in range(20)
    ]
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
    print("Real Tab pressure permission, fixture, tab, RSS, and log gates passed.")


def main():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    evaluate_parser = subparsers.add_parser("evaluate")
    evaluate_parser.add_argument("--ui-status", required=True)
    evaluate_parser.add_argument("--runtime-status", required=True)
    evaluate_parser.add_argument("--samples", required=True)
    evaluate_parser.add_argument("--runtime-home", required=True)
    evaluate_parser.add_argument("--runtime-log-level", required=True)
    evaluate_parser.add_argument("--runtime-log-budget", type=float)
    evaluate_parser.add_argument("--duration-seconds", type=float, required=True)
    evaluate_parser.add_argument(
        "--interval-milliseconds",
        type=float,
        required=True,
    )
    evaluate_parser.add_argument("--runtime-exit-code", type=int, required=True)
    evaluate_parser.add_argument("--output", required=True)
    evaluate_parser.add_argument("--summary", required=True)
    subparsers.add_parser("self-test")
    arguments = parser.parse_args()
    if arguments.command == "self-test":
        self_test()
        return 0
    try:
        result = evaluate(
            load_json_or(
                arguments.ui_status,
                {"state": "environment_blocked"},
            ),
            load_json_or(
                arguments.runtime_status,
                {
                    "final_exit_code": arguments.runtime_exit_code,
                    "identity_verdict": "not_evaluated",
                    "ui_result_bundle_valid": False,
                },
            ),
            load_samples_or_empty(arguments.samples),
            os.path.abspath(arguments.runtime_home),
            arguments.runtime_log_level,
            arguments.runtime_log_budget,
            arguments.duration_seconds,
            arguments.interval_milliseconds,
            arguments.runtime_exit_code,
        )
        write_atomically(
            arguments.output,
            json.dumps(result, indent=2, sort_keys=True) + "\n",
        )
        write_atomically(arguments.summary, render_summary(result))
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0 if result["verdict"] == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())
