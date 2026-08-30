#!/usr/bin/env python3
import argparse
import csv
import json
import math
import os
import re
import sys
import tempfile


LOG_CAPACITY = 20
RSS_ABSOLUTE_GROWTH_ALLOWANCE_KB = 32 * 1024
RSS_RELATIVE_GROWTH_ALLOWANCE = 0.15
OBSERVER_INSTALL_EVENT_NAMES = (
    "runtimeAXObserverInstall",
    "homeAXObserverInstall",
)
OBSERVER_RETRY_EVENT_NAMES = (
    "runtimeAXObserverRetry",
    "homeAXObserverRetry",
)
TAB_SWITCH_WARMUP_MARKER = (
    "FlowTabTabSwitchStressEvidence phase=started"
)


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


def runtime_log_paths(runtime_home):
    directory = os.path.join(
        runtime_home,
        "Library",
        "Application Support",
        "FlowTab",
        "logs",
    )
    if not os.path.isdir(directory):
        return []
    return [
        os.path.join(directory, name)
        for name in sorted(os.listdir(directory))
        if name.endswith(".log")
    ]


def log_volume(runtime_home, elapsed_seconds, completed_switches):
    paths = runtime_log_paths(runtime_home)
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


def observer_install_evidence(runtime_home):
    marker_count = 0
    after_warmup = False
    all_successful_installs = 0
    successful_installs = 0
    current_install_events = 0
    historical_install_events = 0
    retry_events = 0
    retry_installs = 0
    rebind_events = 0
    identities = set()
    app_ids_by_pid = {}

    for path in runtime_log_paths(runtime_home):
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                if TAB_SWITCH_WARMUP_MARKER in line:
                    marker_count += 1
                    after_warmup = True
                    continue
                install_event_name = next(
                    (
                        name
                        for name in OBSERVER_INSTALL_EVENT_NAMES
                        if name in line and "result=installed" in line
                    ),
                    None,
                )
                if install_event_name is not None:
                    all_successful_installs += 1
                    if not after_warmup:
                        continue
                    successful_installs += 1
                    if install_event_name == OBSERVER_INSTALL_EVENT_NAMES[0]:
                        current_install_events += 1
                    else:
                        historical_install_events += 1
                    app_id_match = re.search(r"(?:^| )appID=([^ ]+)", line)
                    pid_match = re.search(r"(?:^| )pid=([0-9]+)", line)
                    retry_match = re.search(
                        r"(?:^| )retryAttempt=([0-9]+)", line
                    )
                    if app_id_match and pid_match:
                        app_id = app_id_match.group(1)
                        pid = int(pid_match.group(1))
                        identities.add((app_id, pid))
                        app_ids_by_pid.setdefault(pid, set()).add(app_id)
                    if retry_match and int(retry_match.group(1)) > 0:
                        retry_installs += 1
                if after_warmup and any(
                    name in line for name in OBSERVER_RETRY_EVENT_NAMES
                ):
                    retry_events += 1
                if after_warmup and "runtimeAXObserverRebind" in line:
                    rebind_events += 1

    unique_bindings = len(identities)
    replacement_pids = sum(
        1 for app_ids in app_ids_by_pid.values() if len(app_ids) > 1
    )
    allowed_successful_installs = unique_bindings + retry_installs
    return {
        "warmup_marker_count": marker_count,
        "all_successful_install_count": all_successful_installs,
        "post_warmup_successful_install_count": successful_installs,
        "post_warmup_unique_binding_count": unique_bindings,
        "post_warmup_retry_install_count": retry_installs,
        "post_warmup_retry_event_count": retry_events,
        "post_warmup_rebind_event_count": rebind_events,
        "post_warmup_replacement_pid_count": replacement_pids,
        "post_warmup_current_install_event_count": current_install_events,
        "post_warmup_historical_install_event_count": (
            historical_install_events
        ),
        "allowed_successful_install_count": allowed_successful_installs,
        "structure_satisfied": (
            marker_count == 1
            and successful_installs <= allowed_successful_installs
        ),
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
    observer_evidence = observer_install_evidence(runtime_home)

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
        gate(
            "runtime_ax_observer_structure",
            runtime_log_level != "DEBUG"
            or observer_evidence["structure_satisfied"],
            (
                observer_evidence
                if runtime_log_level == "DEBUG"
                else "not_evaluated_at_error_log_level"
            ),
            (
                "one warm-up marker and successful installs <= "
                "unique bindings + retry installs"
                if runtime_log_level == "DEBUG"
                else "evaluated by paired DEBUG run"
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
        "runtime_ax_observer": observer_evidence,
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
        "runtime_ax_observer="
        + f"warmup_markers:{result['runtime_ax_observer']['warmup_marker_count']},"
        + "post_warmup_installs:"
        + str(
            result["runtime_ax_observer"][
                "post_warmup_successful_install_count"
            ]
        )
        + ",unique_bindings:"
        + str(
            result["runtime_ax_observer"][
                "post_warmup_unique_binding_count"
            ]
        )
        + ",retry_installs:"
        + str(
            result["runtime_ax_observer"][
                "post_warmup_retry_install_count"
            ]
        ),
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
        log_directory = os.path.join(
            runtime_home,
            "Library",
            "Application Support",
            "FlowTab",
            "logs",
        )
        os.makedirs(log_directory)
        with open(
            os.path.join(log_directory, "Flow_Tab_test.log"),
            "w",
            encoding="utf-8",
        ) as handle:
            handle.write(
                "homeAXObserverInstall result=installed "
                "appID=com.example.prewarm pid=1 retryAttempt=0\n"
                + TAB_SWITCH_WARMUP_MARKER
                + "\n"
                + "runtimeAXObserverInstall result=installed "
                "appID=com.example.current pid=2 retryAttempt=0\n"
                + "homeAXObserverInstall result=installed "
                "appID=com.example.historical pid=3 retryAttempt=0\n"
                + "runtimeAXObserverInstall result=installed "
                "appID=com.example.current pid=2 retryAttempt=1\n"
                + "runtimeAXObserverRetry result=succeeded "
                "appID=com.example.current pid=2\n"
            )
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
