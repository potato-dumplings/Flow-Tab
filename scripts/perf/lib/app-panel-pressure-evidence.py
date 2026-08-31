#!/usr/bin/env python3
import argparse
import csv
import datetime
import json
import math
import os
import sys

from app_panel_pressure_contract import (
    CPU_IDLE_ABSOLUTE_LIMIT,
    CPU_IDLE_ACTIVE_RATIO,
    EVENT_STAGE_COLUMNS,
    FLOWS,
    MIN_RESOURCE_SAMPLES,
    OPEN_DIAGNOSTIC_STAGE_COLUMNS,
    OPEN_PARTITION_STAGE_COLUMNS,
    OPEN_P95_LIMIT_MS,
    OPEN_PREFLIGHT_STAGE_COLUMNS,
    OPEN_STAGE_COLUMNS,
    OPEN_STAGE_GROUPS,
    RSS_ABSOLUTE_GROWTH_ALLOWANCE_KB,
    RSS_RELATIVE_GROWTH_ALLOWANCE,
    SCENARIOS,
)


def percentile(values, percentile_value):
    ordered = sorted(values)
    if not ordered:
        raise ValueError("percentile requires at least one value")
    index = math.ceil(len(ordered) * percentile_value / 100.0) - 1
    return ordered[max(0, min(index, len(ordered) - 1))]


def parse_sample_timestamp(value):
    return datetime.datetime.strptime(
        value, "%Y-%m-%dT%H:%M:%SZ"
    ).replace(tzinfo=datetime.timezone.utc).timestamp()


def load_csv(path):
    with open(path, newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def unique_marker_epoch(metrics, kind):
    matches = [row for row in metrics if row["kind"] == kind]
    if len(matches) != 1:
        raise ValueError(
            f"expected one {kind} marker, observed {len(matches)}"
        )
    return float(matches[0]["epoch_seconds"])


def timed_samples(samples, start, end):
    result = []
    for row in samples:
        timestamp = parse_sample_timestamp(row["timestamp"])
        if start <= timestamp <= end:
            result.append(
                {
                    "timestamp": timestamp,
                    "cpu": float(row["cpu_percent"]),
                    "rss_kb": float(row["rss_kb"]),
                }
            )
    return result


def gate(name, passed, observed, limit):
    return {
        "name": name,
        "passed": bool(passed),
        "observed": observed,
        "limit": limit,
    }


def summarize_stage_values(values, open_values):
    total_open = sum(open_values)
    return {
        "mean_ms": sum(values) / len(values),
        "p50_ms": percentile(values, 50),
        "p95_ms": percentile(values, 95),
        "max_ms": max(values),
        "mean_share_percent": (
            sum(values) / total_open * 100.0 if total_open else math.inf
        ),
    }


def evaluate_open_stage_breakdown(opened, open_values):
    if not opened or OPEN_STAGE_COLUMNS[0] not in opened[0]:
        return {
            "available": False,
            "complete_cycle_count": 0,
            "preflight": {},
            "groups": {},
            "stages": {},
            "dominant_stages": [],
            "reconciliation": {},
        }

    stage_rows = []
    for row in opened:
        if any(column not in row for column in OPEN_STAGE_COLUMNS):
            raise ValueError("open-stage metric columns are incomplete")
        values = {
            column: float(row[column])
            for column in OPEN_STAGE_COLUMNS
        }
        if any(
            not math.isfinite(value) or value < 0
            for value in values.values()
        ):
            raise ValueError("open-stage metrics must be finite and non-negative")
        stage_rows.append(values)

    stages = {
        column: summarize_stage_values(
            [row[column] for row in stage_rows],
            open_values,
        )
        for column in OPEN_PARTITION_STAGE_COLUMNS
    }
    preflight = {
        column: summarize_stage_values(
            [row[column] for row in stage_rows],
            open_values,
        )
        for column in OPEN_PREFLIGHT_STAGE_COLUMNS
    }
    groups = {}
    for name, columns in OPEN_STAGE_GROUPS.items():
        values = [
            sum(row[column] for column in columns)
            for row in stage_rows
        ]
        groups[name] = summarize_stage_values(values, open_values)

    differences = []
    for stage_row, open_value in zip(stage_rows, open_values):
        partition_total = sum(
            stage_row[column]
            for column in OPEN_PARTITION_STAGE_COLUMNS
        )
        differences.append(open_value - partition_total)
    absolute_differences = [abs(value) for value in differences]
    dominant_stages = sorted(
        (
            {"name": name, **summary}
            for name, summary in stages.items()
        ),
        key=lambda item: (
            item["mean_share_percent"],
            item["p95_ms"],
        ),
        reverse=True,
    )
    return {
        "available": True,
        "complete_cycle_count": len(stage_rows),
        "preflight": preflight,
        "groups": groups,
        "stages": stages,
        "dominant_stages": dominant_stages,
        "reconciliation": {
            "difference_p50_ms": percentile(differences, 50),
            "absolute_difference_p95_ms": percentile(
                absolute_differences, 95
            ),
            "absolute_difference_max_ms": max(absolute_differences),
        },
    }


def evaluate_event_stage_breakdown(opened, highlighted, flow_name):
    rows = opened + highlighted
    if not rows or any(
        column not in rows[0] for column in EVENT_STAGE_COLUMNS
    ):
        return {"available": False, "open": {}, "interaction": {}}

    open_columns = [
        "command_return_ms",
        "first_content_draw_ms",
        "panel_expose_ms",
        "occlusion_visible_ms",
    ]
    interaction_columns = {
        "application": [
            "command_return_ms",
            "first_content_draw_ms",
        ],
        "app-to-window": [
            "command_return_ms",
            "window_readiness_read_ms",
            "window_maintenance_wait_ms",
            "window_session_switch_ms",
            "window_content_draw_ms",
        ],
        "search": [
            "command_return_ms",
            "search_debounce_ms",
            "search_computation_ms",
            "search_results_publish_ms",
            "search_first_row_draw_ms",
        ],
    }[flow_name]

    def summarize(source_rows, columns):
        result = {}
        for column in columns:
            values = [float(row[column]) for row in source_rows]
            if any(
                not math.isfinite(value) or value < 0
                for value in values
            ):
                raise ValueError(
                    "event-stage metrics must be finite and non-negative"
                )
            result[column] = {
                "p50_ms": percentile(values, 50),
                "p95_ms": percentile(values, 95),
                "max_ms": max(values),
            }
        return result

    return {
        "available": True,
        "open": summarize(opened, open_columns),
        "interaction": summarize(
            highlighted,
            interaction_columns,
        ),
    }


def evaluate(
    metrics,
    samples,
    flow_name,
    scenario_name,
    required_duration,
    required_cooldown,
):
    flow = FLOWS[flow_name]
    scenario = SCENARIOS[scenario_name]
    measurement_start = unique_marker_epoch(metrics, "measurement_start")
    cooldown_start = unique_marker_epoch(metrics, "cooldown_start")
    cooldown_end = unique_marker_epoch(metrics, "cooldown_end")
    measured_duration = cooldown_start - measurement_start
    measured_cooldown = cooldown_end - cooldown_start

    measured_rows = [
        row
        for row in metrics
        if int(row["cycle"]) > 0
        and row["kind"] in {"opened", "highlighted", "closed"}
    ]
    all_opened = [row for row in metrics if row["kind"] == "opened"]
    opened = [row for row in measured_rows if row["kind"] == "opened"]
    highlighted = [
        row for row in measured_rows if row["kind"] == "highlighted"
    ]
    closed = [row for row in measured_rows if row["kind"] == "closed"]
    opened_cycles = {int(row["cycle"]) for row in opened}
    highlighted_cycles = {int(row["cycle"]) for row in highlighted}
    closed_cycles = {int(row["cycle"]) for row in closed}
    cycle_contract = (
        opened_cycles
        and opened_cycles == highlighted_cycles == closed_cycles
        and len(opened) == len(opened_cycles)
        and len(highlighted) == len(opened_cycles)
        and len(closed) == len(opened_cycles)
    )

    open_values = [float(row["elapsed_ms"]) for row in opened]
    highlight_values = [float(row["elapsed_ms"]) for row in highlighted]
    close_values = [float(row["elapsed_ms"]) for row in closed]
    open_p50 = percentile(open_values, 50) if open_values else math.inf
    open_p95 = percentile(open_values, 95) if open_values else math.inf
    highlight_p50 = (
        percentile(highlight_values, 50) if highlight_values else math.inf
    )
    highlight_p95 = (
        percentile(highlight_values, 95) if highlight_values else math.inf
    )
    close_p50 = percentile(close_values, 50) if close_values else math.inf
    close_p95 = percentile(close_values, 95) if close_values else math.inf
    if scenario["app_count"] is None:
        opened_by_cycle = {int(row["cycle"]): row for row in opened}
        opened_state_valid = all(
            row["panel_presented"] == "1"
            and row["user_visible"] == "1"
            and row["selected_app_id"] != "none"
            and int(row["app_count"]) > 1
            and int(row["selected_window_count"]) >= 0
            for row in opened
        )
        def local_interaction_is_valid(row):
            opened_row = opened_by_cycle.get(int(row["cycle"]))
            if opened_row is None:
                return False
            base_valid = (
                row["panel_presented"] == "1"
                and row["user_visible"] == "1"
                and row["selected_app_id"] != "none"
                and int(row["app_count"]) > 1
            )
            if flow_name == "application":
                return base_valid and (
                    row["selected_app_id"]
                    != opened_row["selected_app_id"]
                )
            if flow_name == "app-to-window":
                return base_valid and int(row["selected_window_count"]) >= 2
            return base_valid and (
                row["selected_app_id"] == opened_row["selected_app_id"]
            )

        highlighted_state_valid = all(
            local_interaction_is_valid(row) for row in highlighted
        )
    else:
        opened_by_cycle = {int(row["cycle"]): row for row in opened}
        opened_state_valid = all(
            row["panel_presented"] == "1"
            and row["user_visible"] == "1"
            and int(row["app_count"]) == scenario["app_count"]
            and int(row["selected_window_count"])
            == scenario["opened_windows"]
            for row in opened
        )
        def deterministic_interaction_is_valid(row):
            opened_row = opened_by_cycle.get(int(row["cycle"]))
            if opened_row is None:
                return False
            expected_windows = (
                scenario["highlighted_windows"]
                if flow_name == "application"
                else scenario["opened_windows"]
            )
            base_valid = (
                row["panel_presented"] == "1"
                and row["user_visible"] == "1"
                and int(row["app_count"]) == scenario["app_count"]
                and int(row["selected_window_count"])
                == expected_windows
            )
            if flow_name == "application":
                return base_valid
            return base_valid and (
                row["selected_app_id"] == opened_row["selected_app_id"]
            )

        highlighted_state_valid = all(
            deterministic_interaction_is_valid(row)
            for row in highlighted
        )
    closed_state_valid = all(
        row["panel_presented"] == "0"
        and row["user_visible"] == "0"
        and row["selected_app_id"] == "none"
        for row in closed
    )
    active_rows = opened + highlighted
    panel_geometry_valid = all(
        float(row["visible_frame_width"]) > 0
        and float(row["panel_width"]) >= 440
        and float(row["panel_width"])
        <= max(440, float(row["visible_frame_width"]) - 80) + 0.5
        for row in active_rows
    )
    home_lifecycle_valid = all(
        int(row["visible_home_window_count"]) == 0
        for row in measured_rows
    )
    opened_width_by_cycle = {
        int(row["cycle"]): float(row["panel_width"])
        for row in opened
    }
    shared_width_valid = flow_name == "app-to-window" or all(
        abs(
            float(row["panel_width"])
            - opened_width_by_cycle.get(
                int(row["cycle"]),
                math.inf,
            )
        ) <= 0.5
        for row in highlighted
    )
    first_frame_violations = (
        0
        if flow_name == "search"
        else sum(
            float(row["first_content_draw_ms"])
            > float(row["occlusion_visible_ms"])
            for row in all_opened
        )
    )

    active = timed_samples(samples, measurement_start, cooldown_start)
    cooldown_settle = cooldown_start + measured_cooldown * 0.5
    cooldown = timed_samples(samples, cooldown_settle, cooldown_end)
    active_cpu = [row["cpu"] for row in active]
    cooldown_cpu = [row["cpu"] for row in cooldown]
    active_cpu_average = (
        sum(active_cpu) / len(active_cpu) if active_cpu else math.inf
    )
    cooldown_cpu_p95 = (
        percentile(cooldown_cpu, 95) if cooldown_cpu else math.inf
    )
    cooldown_cpu_limit = max(
        CPU_IDLE_ABSOLUTE_LIMIT,
        active_cpu_average * CPU_IDLE_ACTIVE_RATIO,
    )

    middle_start = measurement_start + measured_duration * 0.4
    middle_end = measurement_start + measured_duration * 0.6
    late_start = measurement_start + measured_duration * 0.8
    middle = timed_samples(samples, middle_start, middle_end)
    late = timed_samples(samples, late_start, cooldown_start)
    middle_rss = [row["rss_kb"] for row in middle]
    late_rss = [row["rss_kb"] for row in late]
    middle_rss_p95 = (
        percentile(middle_rss, 95) if middle_rss else math.inf
    )
    late_rss_p95 = percentile(late_rss, 95) if late_rss else math.inf
    rss_growth_kb = late_rss_p95 - middle_rss_p95
    rss_growth_limit_kb = max(
        RSS_ABSOLUTE_GROWTH_ALLOWANCE_KB,
        middle_rss_p95 * RSS_RELATIVE_GROWTH_ALLOWANCE,
    )

    interaction_gates = []
    if flow["interaction_limit_ms"] is not None:
        interaction_gates.append(
            gate(
                flow["interaction_gate"],
                highlight_p95 <= flow["interaction_limit_ms"],
                highlight_p95,
                f"<={flow['interaction_limit_ms']}",
            )
        )

    gates = [
        gate(
            "duration",
            measured_duration >= required_duration,
            measured_duration,
            f">={required_duration}",
        ),
        gate(
            "cooldown",
            measured_cooldown >= required_cooldown,
            measured_cooldown,
            f">={required_cooldown}",
        ),
        gate("exact_cycle_evidence", cycle_contract, len(opened_cycles), ">=1"),
        gate("opened_state", opened_state_valid, len(opened), "all"),
        gate(
            "highlighted_state",
            highlighted_state_valid,
            len(highlighted),
            "all",
        ),
        gate("closed_state", closed_state_valid, len(closed), "all"),
        gate(
            "panel_geometry",
            panel_geometry_valid,
            len(active_rows),
            "all",
        ),
        gate(
            "shared_application_search_width",
            shared_width_valid,
            len(highlighted),
            "all",
        ),
        gate(
            "suppressed_home_window_count",
            home_lifecycle_valid,
            len(measured_rows),
            "all-zero",
        ),
        gate(
            "open_p95_ms",
            open_p95 <= OPEN_P95_LIMIT_MS,
            open_p95,
            f"<={OPEN_P95_LIMIT_MS}",
        ),
        gate(
            "initial_app_content_draw_before_visibility",
            first_frame_violations == 0,
            first_frame_violations,
            "0",
        ),
    ] + interaction_gates + [
        gate(
            "active_resource_samples",
            len(active) >= MIN_RESOURCE_SAMPLES,
            len(active),
            f">={MIN_RESOURCE_SAMPLES}",
        ),
        gate(
            "cooldown_resource_samples",
            len(cooldown) >= 3,
            len(cooldown),
            ">=3",
        ),
        gate(
            "cpu_return_p95_percent",
            cooldown_cpu_p95 <= cooldown_cpu_limit,
            cooldown_cpu_p95,
            f"<={cooldown_cpu_limit:.3f}",
        ),
        gate(
            "rss_plateau_growth_kb",
            len(middle_rss) >= 3
            and len(late_rss) >= 3
            and rss_growth_kb <= rss_growth_limit_kb,
            rss_growth_kb,
            f"<={rss_growth_limit_kb:.3f}",
        ),
    ]
    app_counts = [int(row["app_count"]) for row in opened + highlighted]
    opened_window_counts = [
        int(row["selected_window_count"]) for row in opened
    ]
    highlighted_window_counts = [
        int(row["selected_window_count"]) for row in highlighted
    ]
    selected_app_ids = {
        row["selected_app_id"] for row in opened + highlighted
    }
    open_stage_breakdown = evaluate_open_stage_breakdown(
        opened,
        open_values,
    )
    event_stage_breakdown = evaluate_event_stage_breakdown(
        opened,
        highlighted,
        flow_name,
    )

    return {
        "schema_version": 7,
        "flow": flow_name,
        "scenario": scenario_name,
        "verdict": "passed" if all(item["passed"] for item in gates) else "failed",
        "cycle_count": len(opened_cycles),
        "app_count_min": min(app_counts) if app_counts else None,
        "app_count_max": max(app_counts) if app_counts else None,
        "opened_window_count_min": (
            min(opened_window_counts) if opened_window_counts else None
        ),
        "opened_window_count_max": (
            max(opened_window_counts) if opened_window_counts else None
        ),
        "highlighted_window_count_min": (
            min(highlighted_window_counts)
            if highlighted_window_counts
            else None
        ),
        "highlighted_window_count_max": (
            max(highlighted_window_counts)
            if highlighted_window_counts
            else None
        ),
        "observed_selected_app_count": len(selected_app_ids),
        "panel_width_min": min(
            (float(row["panel_width"]) for row in active_rows),
            default=None,
        ),
        "panel_width_max": max(
            (float(row["panel_width"]) for row in active_rows),
            default=None,
        ),
        "visible_frame_width_min": min(
            (
                float(row["visible_frame_width"])
                for row in active_rows
            ),
            default=None,
        ),
        "visible_frame_width_max": max(
            (
                float(row["visible_frame_width"])
                for row in active_rows
            ),
            default=None,
        ),
        "visible_home_window_count_max": max(
            (
                int(row["visible_home_window_count"])
                for row in measured_rows
            ),
            default=None,
        ),
        "measured_duration_seconds": measured_duration,
        "measured_cooldown_seconds": measured_cooldown,
        "open_p50_ms": open_p50,
        "open_p95_ms": open_p95,
        "interaction_p50_ms": highlight_p50,
        "interaction_p95_ms": highlight_p95,
        "close_p50_ms": close_p50,
        "close_p95_ms": close_p95,
        "highlight_p95_ms": highlight_p95,
        "active_cpu_average_percent": active_cpu_average,
        "cooldown_cpu_p95_percent": cooldown_cpu_p95,
        "middle_rss_p95_mb": middle_rss_p95 / 1024.0,
        "late_rss_p95_mb": late_rss_p95 / 1024.0,
        "rss_p95_growth_mb": rss_growth_kb / 1024.0,
        "open_stage_breakdown": open_stage_breakdown,
        "event_stage_breakdown": event_stage_breakdown,
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
    lines = [
        "FlowTab real-UI pressure gate",
        f"flow={result['flow']}",
        f"scenario={result['scenario']}",
        f"verdict={result['verdict']}",
        f"cycles={result['cycle_count']}",
        f"appCountRange={result['app_count_min']}..{result['app_count_max']}",
        "openedWindowCountRange="
        f"{result['opened_window_count_min']}..{result['opened_window_count_max']}",
        "highlightedWindowCountRange="
        f"{result['highlighted_window_count_min']}..{result['highlighted_window_count_max']}",
        f"observedSelectedApps={result['observed_selected_app_count']}",
        f"durationSeconds={result['measured_duration_seconds']:.3f}",
        f"cooldownSeconds={result['measured_cooldown_seconds']:.3f}",
        f"openP50Ms={result['open_p50_ms']:.3f}",
        f"openP95Ms={result['open_p95_ms']:.3f}",
        f"interactionP50Ms={result['interaction_p50_ms']:.3f}",
        f"interactionP95Ms={result['interaction_p95_ms']:.3f}",
        f"closeP50Ms={result['close_p50_ms']:.3f}",
        f"closeP95Ms={result['close_p95_ms']:.3f}",
        f"activeCPUAverage={result['active_cpu_average_percent']:.3f}",
        f"cooldownCPUP95={result['cooldown_cpu_p95_percent']:.3f}",
        f"middleRSSP95MB={result['middle_rss_p95_mb']:.3f}",
        f"lateRSSP95MB={result['late_rss_p95_mb']:.3f}",
        f"rssP95GrowthMB={result['rss_p95_growth_mb']:.3f}",
    ]
    breakdown = result["open_stage_breakdown"]
    lines.append(
        "openStageBreakdown="
        + ("available" if breakdown["available"] else "unavailable")
    )
    if breakdown["available"]:
        reconciliation = breakdown["reconciliation"]
        lines.append(
            "openStageReconciliationAbsP95Ms="
            f"{reconciliation['absolute_difference_p95_ms']:.6f}"
        )
        for name, summary in breakdown["preflight"].items():
            lines.append(
                f"openPreflight.{name} "
                f"p50Ms={summary['p50_ms']:.3f} "
                f"p95Ms={summary['p95_ms']:.3f}"
            )
        for name, summary in breakdown["groups"].items():
            lines.append(
                f"openStageGroup.{name} "
                f"p50Ms={summary['p50_ms']:.3f} "
                f"p95Ms={summary['p95_ms']:.3f} "
                f"meanShare={summary['mean_share_percent']:.2f}%"
            )
        for item in breakdown["dominant_stages"]:
            lines.append(
                f"openStage.{item['name']} "
                f"p50Ms={item['p50_ms']:.3f} "
                f"p95Ms={item['p95_ms']:.3f} "
                f"meanShare={item['mean_share_percent']:.2f}%"
            )
    event_breakdown = result["event_stage_breakdown"]
    lines.append(
        "eventStageBreakdown="
        + (
            "available"
            if event_breakdown["available"]
            else "unavailable"
        )
    )
    if event_breakdown["available"]:
        for phase in ("open", "interaction"):
            for name, summary in event_breakdown[phase].items():
                lines.append(
                    f"eventStage.{phase}.{name} "
                    f"p50Ms={summary['p50_ms']:.3f} "
                    f"p95Ms={summary['p95_ms']:.3f}"
                )
    lines.extend(
        f"gate.{item['name']}={'passed' if item['passed'] else 'failed'} "
        f"observed={item['observed']} limit={item['limit']}"
        for item in result["gates"]
    )
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    evaluate_parser = subparsers.add_parser("evaluate")
    evaluate_parser.add_argument("--metrics", required=True)
    evaluate_parser.add_argument("--samples", required=True)
    evaluate_parser.add_argument("--flow", choices=sorted(FLOWS), required=True)
    evaluate_parser.add_argument("--scenario", choices=sorted(SCENARIOS), required=True)
    evaluate_parser.add_argument("--duration-seconds", type=float, required=True)
    evaluate_parser.add_argument("--cooldown-seconds", type=float, required=True)
    evaluate_parser.add_argument("--summary", required=True)
    evaluate_parser.add_argument("--json", required=True)
    subparsers.add_parser("self-test")
    arguments = parser.parse_args()
    if arguments.command == "self-test":
        from app_panel_pressure_evidence_self_test import run_self_test

        run_self_test(
            evaluate,
            OPEN_STAGE_COLUMNS,
            EVENT_STAGE_COLUMNS,
        )
        return
    result = evaluate(
        load_csv(arguments.metrics),
        load_csv(arguments.samples),
        arguments.flow,
        arguments.scenario,
        arguments.duration_seconds,
        arguments.cooldown_seconds,
    )
    write_atomically(arguments.summary, render_summary(result))
    write_atomically(
        arguments.json,
        json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n",
    )
    print(render_summary(result), end="")
    if result["verdict"] != "passed":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
