#!/usr/bin/env python3
import argparse
import json
import os
import re
import sys

from tab_switch_real_pressure_evidence_self_test import run_self_test
from tab_switch_real_pressure_windows import (
    ACTIVE_RESOURCE_COVERAGE_MINIMUM,
    LOG_CAPACITY,
    TAB_SWITCH_WARMUP_MARKER,
    active_log_volume,
    load_samples_or_empty,
    log_volume,
    runtime_log_paths,
    select_resource_windows,
    summarize_resources,
)


OBSERVER_INSTALL_EVENT_NAMES = (
    "runtimeAXObserverInstall",
    "homeAXObserverInstall",
)
OBSERVER_RETRY_EVENT_NAMES = (
    "runtimeAXObserverRetry",
    "homeAXObserverRetry",
)


def load_json(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def load_json_or(path, fallback):
    return load_json(path) if os.path.isfile(path) else fallback


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
    stress_started = int(
        ui_status.get("stress_started_uptime_nanoseconds", 0)
    )
    stress_completed = int(
        ui_status.get("stress_completed_uptime_nanoseconds", 0)
    )
    active_window_duration = stress_completed - stress_started
    active_window_timing_satisfied = (
        stress_started > 0
        and stress_completed > stress_started
        and active_window_duration == elapsed_nanoseconds
    )
    resource_windows = select_resource_windows(
        samples,
        stress_started,
        stress_completed,
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
    active_volume = active_log_volume(
        runtime_home,
        elapsed_seconds,
        completed_switches,
    )
    whole_run_volume = log_volume(
        runtime_home,
        elapsed_seconds,
        completed_switches,
    )
    observer_evidence = observer_install_evidence(runtime_home)
    active_rss = active_resources["rss_mb"]
    log_budget_satisfied = (
        runtime_log_budget is None
        or active_volume["megabytes_per_minute"] <= runtime_log_budget
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
        gate(
            "active_resource_window",
            active_window_timing_satisfied,
            {
                "started_uptime_nanoseconds": stress_started,
                "completed_uptime_nanoseconds": stress_completed,
                "elapsed_nanoseconds": elapsed_nanoseconds,
                "observed_duration_nanoseconds": active_window_duration,
            },
            "valid monotonic bounds with duration matching elapsed",
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
        "schema_version": 2,
        "runner_kind": "tab_switch_real_pressure",
        "lane": "real_permissions",
        "measurement_window": "active_tab_switch",
        "measurement_source": (
            "active-window-v2"
            if active_window_timing_satisfied
            else "whole-run-legacy-v1"
        ),
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
        "stress_started_uptime_nanoseconds": stress_started,
        "stress_completed_uptime_nanoseconds": stress_completed,
        "active_resource_coverage": {
            "ratio": active_resource_coverage,
            "covered_duration_nanoseconds": active_covered_duration,
            "required_ratio": ACTIVE_RESOURCE_COVERAGE_MINIMUM,
        },
        "sample_count": active_resources["sample_count"],
        "whole_run_sample_count": len(samples),
        "cpu_percent": active_resources["cpu_percent"],
        "cpu_time_milliseconds_per_completed_switch": (
            cpu_time_per_completed_switch
        ),
        "rss_mb": active_rss,
        "runtime_logs": active_volume,
        "diagnostic_runtime_logs": {
            "whole_run": whole_run_volume,
        },
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
    coverage = result["active_resource_coverage"]
    logs = result["runtime_logs"]
    lines = [
        "FlowTab real-permission Tab pressure",
        f"verdict={result['verdict']}",
        f"schema_version={result['schema_version']}",
        f"measurement_window={result['measurement_window']}",
        f"measurement_source={result['measurement_source']}",
        f"duration_seconds={result['duration_seconds']}",
        f"switch_interval_milliseconds={result['switch_interval_milliseconds']}",
        f"completed_switches={result['completed_switches']}",
        "tab_switches="
        + f"home:{result['home_switches']},"
        + f"logs:{result['logs_switches']},"
        + f"settings:{result['settings_switches']}",
        "cpu_percent="
        + f"avg:{cpu['average']},p95:{cpu['p95']},max:{cpu['max']}",
        "active_resource_coverage="
        + f"ratio:{coverage['ratio']},"
        + f"samples:{result['sample_count']},"
        + f"whole_run_samples:{result['whole_run_sample_count']}",
        "cpu_time_milliseconds_per_completed_switch="
        + str(result["cpu_time_milliseconds_per_completed_switch"]),
        "rss_mb="
        + f"avg:{rss['average']},p95:{rss['p95']},max:{rss['max']},"
        + f"plateau_growth:{rss['plateau_growth']}",
        "active_runtime_logs="
        + f"bytes:{logs['retained_bytes']},"
        + f"megabytes_per_minute:{logs['megabytes_per_minute']},"
        + f"started_markers:{logs['started_marker_count']},"
        + f"completed_markers:{logs['completed_marker_count']}",
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
    run_self_test(evaluate, observer_install_evidence)


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
