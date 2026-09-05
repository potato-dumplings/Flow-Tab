#!/usr/bin/env python3
from __future__ import annotations

import csv
import math
from collections import defaultdict
from pathlib import Path
from statistics import median
from typing import Any, Iterable


def percentile(values: Iterable[float], quantile: float) -> float:
    ordered = sorted(values)
    if not ordered:
        raise ValueError("percentile requires at least one value")
    index = max(
        0,
        min(
            len(ordered) - 1,
            math.ceil(len(ordered) * quantile) - 1,
        ),
    )
    return ordered[index]


def stats(values: Iterable[float]) -> dict[str, float]:
    materialized = list(values)
    if not materialized:
        raise ValueError("statistics require at least one value")
    return {
        "avg": sum(materialized) / len(materialized),
        "p50": percentile(materialized, 0.50),
        "p95": percentile(materialized, 0.95),
        "p99": percentile(materialized, 0.99),
        "max": max(materialized),
    }


def measured_events(events: list[dict[str, str]]) -> list[dict[str, str]]:
    return [
        row
        for row in events
        if int(row["cycle"]) > 0 or row["phase"] == "cooldown"
    ]


def phase_summary(events: list[dict[str, str]]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    measured = measured_events(events)
    for phase in sorted({row["phase"] for row in measured}):
        rows = [row for row in measured if row["phase"] == phase]
        wall = [float(row["wall_ms"]) for row in rows]
        cpu = [float(row["cpu_time_ms"]) for row in rows]
        result[phase] = {
            "count": len(rows),
            "wall_ms": stats(wall),
            "cpu_time_ms": stats(cpu),
            "cpu_percent": (
                100.0 * sum(cpu) / sum(wall) if sum(wall) > 0 else 0.0
            ),
        }
    return result


def path_summary(
    events: list[dict[str, str]],
    metric_index: dict[tuple[str, str], dict[str, float]],
) -> dict[str, dict[str, dict[str, dict[str, float]]]]:
    values: dict[str, dict[str, dict[str, list[float]]]] = defaultdict(
        lambda: defaultdict(lambda: defaultdict(list))
    )
    for row in measured_events(events):
        phase = row["phase"]
        sequence = row["sequence"]
        wall_ms = float(row["wall_ms"])
        partitions = metric_index.get((sequence, "partition"), {})
        milestones = metric_index.get((sequence, "milestone"), {})
        for name, value in partitions.items():
            values[phase]["partitions"][name].append(value)
        for name, value in milestones.items():
            values[phase]["milestones"][name].append(value)

        command_return = milestones.get("command_return_ms")
        if command_return is not None:
            values[phase]["derived"][
                "readback_after_command_ms"
            ].append(max(0.0, wall_ms - command_return))
        if phase == "open":
            panel = milestones.get("panel_presented_ms")
            first_draw = milestones.get("first_window_content_draw_ms")
            visibility = milestones.get("visibility_readback_ms")
            first_visible = milestones.get("first_visible_frame_ms")
            cached_first_frame = milestones.get(
                "cached_first_frame_ms"
            )
            fresh_complete = milestones.get(
                "fresh_visible_previews_complete_ms"
            )
            if panel is not None and first_draw is not None:
                values[phase]["derived"][
                    "draw_after_panel_ms"
                ].append(max(0.0, first_draw - panel))
            if panel is not None and visibility is not None:
                values[phase]["derived"][
                    "visibility_after_panel_ms"
                ].append(max(0.0, visibility - panel))
            if panel is not None and first_visible is not None:
                values[phase]["derived"][
                    "first_visible_after_panel_ms"
                ].append(max(0.0, first_visible - panel))
            if first_visible is not None:
                values[phase]["derived"][
                    "readback_after_first_visible_ms"
                ].append(max(0.0, wall_ms - first_visible))
            if (
                cached_first_frame is not None
                and fresh_complete is not None
            ):
                values[phase]["derived"][
                    "fresh_after_cached_first_frame_ms"
                ].append(
                    max(0.0, fresh_complete - cached_first_frame)
                )
        if phase == "commit":
            activation_request = milestones.get("activation_request_ms")
            if activation_request is not None and command_return is not None:
                values[phase]["derived"][
                    "activation_request_to_command_return_ms"
                ].append(max(0.0, command_return - activation_request))
            focus_verified = milestones.get("focus_verified_ms")
            cleanup_complete = milestones.get("cleanup_complete_ms")
            if focus_verified is not None and cleanup_complete is not None:
                values[phase]["derived"][
                    "focus_and_cleanup_complete_ms"
                ].append(max(focus_verified, cleanup_complete))

    return {
        phase: {
            kind: {
                name: stats(metric_values)
                for name, metric_values in sorted(names.items())
            }
            for kind, names in sorted(kinds.items())
        }
        for phase, kinds in sorted(values.items())
    }


def metric_reconciliation_failures(
    events: list[dict[str, str]],
    metric_index: dict[tuple[str, str], dict[str, float]],
    tolerance_ms: float = 0.5,
) -> list[str]:
    failures: list[str] = []
    for row in measured_events(events):
        sequence = row["sequence"]
        phase = row["phase"]
        wall_ms = float(row["wall_ms"])
        partitions = metric_index.get((sequence, "partition"), {})
        milestones = metric_index.get((sequence, "milestone"), {})
        command_return = milestones.get("command_return_ms")
        if command_return is not None and command_return > wall_ms + tolerance_ms:
            failures.append(sequence)
            continue
        if phase == "open":
            panel = milestones.get("panel_presented_ms")
            first_draw = milestones.get("first_window_content_draw_ms")
            visibility = milestones.get("visibility_readback_ms")
            first_visible = milestones.get("first_visible_frame_ms")
            session_ready = milestones.get("session_ready_ms")
            if None in (
                panel,
                first_draw,
                visibility,
                first_visible,
                session_ready,
            ):
                continue
            partition_total = sum(partitions.values())
            if (
                abs(partition_total - panel) > tolerance_ms
                or abs(first_visible - max(first_draw, visibility))
                > tolerance_ms
                or first_visible + tolerance_ms < panel
                or session_ready > panel + tolerance_ms
            ):
                failures.append(sequence)
        else:
            command_execution = partitions.get("command_execution_ms")
            if (
                command_return is not None
                and command_execution is not None
                and abs(command_execution - command_return) > tolerance_ms
            ):
                failures.append(sequence)
                continue
            if phase == "commit":
                activation_request = milestones.get("activation_request_ms")
                if (
                    activation_request is not None
                    and command_return is not None
                    and activation_request > command_return + tolerance_ms
                ):
                    failures.append(sequence)
        for milestone_name in (
            "cached_first_frame_ms",
            "fresh_visible_previews_complete_ms",
            "panel_hidden_ms",
            "focus_verified_ms",
            "cleanup_complete_ms",
        ):
            milestone = milestones.get(milestone_name)
            if (
                milestone is not None
                and milestone > wall_ms + tolerance_ms
            ):
                failures.append(sequence)
                break
    return sorted(set(failures), key=int)


def load_samples(path: Path) -> list[dict[str, float]]:
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    return [
        {
            "start": float(row["interval_started_uptime_nanoseconds"]),
            "end": float(row["interval_completed_uptime_nanoseconds"]),
            "cpu": float(row["cpu_percent"]),
            "rss_kb": float(row["rss_kb"]),
        }
        for row in rows
    ]


def samples_in_window(
    samples: list[dict[str, float]], start: int, end: int
) -> list[dict[str, float]]:
    return [
        row
        for row in samples
        if row["start"] >= start and row["end"] <= end
    ]


def coverage(samples: list[dict[str, float]], start: int, end: int) -> float:
    if end <= start:
        return 0.0
    intervals = sorted(
        (max(start, int(row["start"])), min(end, int(row["end"])))
        for row in samples
        if row["end"] > start and row["start"] < end
    )
    merged: list[tuple[int, int]] = []
    for interval_start, interval_end in intervals:
        if interval_end <= interval_start:
            continue
        if not merged or interval_start > merged[-1][1]:
            merged.append((interval_start, interval_end))
        else:
            merged[-1] = (
                merged[-1][0],
                max(merged[-1][1], interval_end),
            )
    covered = sum(end_value - start_value for start_value, end_value in merged)
    return min(1.0, covered / (end - start))


def median_paths(attempts: list[dict[str, Any]]) -> dict[str, Any]:
    if not attempts or not all(isinstance(item.get("paths"), dict) for item in attempts):
        return {}
    result: dict[str, Any] = {}
    phases = set.intersection(*(set(item["paths"]) for item in attempts))
    for phase in sorted(phases):
        result[phase] = {}
        kinds = set.intersection(
            *(set(item["paths"][phase]) for item in attempts)
        )
        for kind in sorted(kinds):
            result[phase][kind] = {}
            names = set.intersection(
                *(set(item["paths"][phase][kind]) for item in attempts)
            )
            for name in sorted(names):
                result[phase][kind][name] = {
                    statistic: median(
                        item["paths"][phase][kind][name][statistic]
                        for item in attempts
                    )
                    for statistic in ("p50", "p95", "max")
                }
    return result
