#!/usr/bin/env python3
from __future__ import annotations

from collections import Counter, defaultdict
from statistics import median
from typing import Any

from control_tab_pressure_metrics import measured_events, stats
from control_tab_pressure_span_schema import (
    COMPONENT_SCOPE,
    PHASE_CPU_LIMIT_PERCENT,
    PROTOCOL_VERSION,
    REQUIRED_COMPONENTS,
    SCHEMA_DIGEST,
    TIMELINE_SCOPE,
    schema_failures,
    span_rows,
)


def validate_spans(
    events: list[dict[str, str]],
    spans: list[dict[str, str]],
    tolerance_ms: float = 0.5,
) -> dict[str, list[str]]:
    indexed: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in spans:
        indexed[row["sequence"]].append(row)
    missing: list[str] = []
    invalid_timing: list[str] = []
    stale_generation: list[str] = []
    invalid_outcome: list[str] = []
    reconciliation: list[str] = []

    for event in measured_events(events):
        sequence = event["sequence"]
        phase = event["phase"]
        event_spans = indexed.get(sequence, [])
        components = [
            row
            for row in event_spans
            if row["span_scope"] == COMPONENT_SCOPE
        ]
        timeline = sorted(
            (
                row
                for row in event_spans
                if row["span_scope"] == TIMELINE_SCOPE
            ),
            key=lambda row: (
                int(row["span_started_uptime_nanoseconds"]),
                int(row["span_completed_uptime_nanoseconds"]),
            ),
        )
        present = {row["metric_name"] for row in components}
        if not REQUIRED_COMPONENTS.get(phase, set()).issubset(present):
            missing.append(sequence)
        if not timeline:
            missing.append(sequence)
            reconciliation.append(sequence)
            continue
        if any(
            row.get("span_timing_valid") != "1"
            or float(row["span_wall_ms"]) < 0
            or float(row["span_cpu_time_ms"]) < 0
            for row in event_spans
        ):
            invalid_timing.append(sequence)
        if any(
            row.get("span_outcome")
            in {"stale_generation", "incomplete"}
            for row in components
        ):
            stale_generation.append(sequence)
        if any(
            row.get("span_outcome") in {"failed", "timed_out"}
            or (
                row.get("span_outcome") == "cancelled"
                and phase not in {"commit", "cancel"}
            )
            for row in components
        ):
            invalid_outcome.append(sequence)

        expected_start = int(event["started_uptime_nanoseconds"])
        expected_end = int(event["completed_uptime_nanoseconds"])
        continuous = (
            int(timeline[0]["span_started_uptime_nanoseconds"])
            == expected_start
            and int(timeline[-1]["span_completed_uptime_nanoseconds"])
            == expected_end
            and all(
                int(left["span_completed_uptime_nanoseconds"])
                == int(right["span_started_uptime_nanoseconds"])
                for left, right in zip(timeline, timeline[1:])
            )
        )
        timeline_wall = sum(float(row["span_wall_ms"]) for row in timeline)
        timeline_cpu = sum(
            float(row["span_cpu_time_ms"]) for row in timeline
        )
        if (
            not continuous
            or abs(timeline_wall - float(event["wall_ms"])) > tolerance_ms
            or abs(timeline_cpu - float(event["cpu_time_ms"])) > tolerance_ms
            or event.get("timeline_reconciled") != "1"
        ):
            reconciliation.append(sequence)

    numeric = lambda values: sorted(set(values), key=int)
    return {
        "missing": numeric(missing),
        "invalid_timing": numeric(invalid_timing),
        "stale_generation": numeric(stale_generation),
        "invalid_outcome": numeric(invalid_outcome),
        "reconciliation": numeric(reconciliation),
    }


def span_summary(
    events: list[dict[str, str]],
    spans: list[dict[str, str]],
) -> dict[str, Any]:
    measured_sequences = {
        row["sequence"] for row in measured_events(events)
    }
    grouped: dict[
        str, dict[str, dict[str, list[dict[str, str]]]]
    ] = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))
    for row in spans:
        if row["sequence"] not in measured_sequences:
            continue
        grouped[row["phase"]][row["span_scope"]][
            row["metric_name"]
        ].append(row)
    overlapping_components = _overlapping_component_keys(spans)

    result: dict[str, Any] = {}
    for phase, scopes in sorted(grouped.items()):
        result[phase] = {}
        for scope, names in sorted(scopes.items()):
            result[phase][scope] = {}
            for name, rows in sorted(names.items()):
                wall = [float(row["span_wall_ms"]) for row in rows]
                cpu = [float(row["span_cpu_time_ms"]) for row in rows]
                wall_total = sum(wall)
                result[phase][scope][name] = {
                    "count": len(rows),
                    "wall_ms": stats(wall),
                    "cpu_time_ms": stats(cpu),
                    "cpu_percent": (
                        100.0 * sum(cpu) / wall_total
                        if wall_total > 0
                        else 0.0
                    ),
                    "work_units": sum(
                        int(row.get("span_work_units", "0"))
                        for row in rows
                    ),
                    "outcomes": dict(
                        sorted(
                            Counter(
                                row.get("span_outcome", "unknown")
                                for row in rows
                            ).items()
                        )
                    ),
                    "overlap": (
                        scope == COMPONENT_SCOPE
                        and (phase, name) in overlapping_components
                    ),
                }
    return result


def component_phase_coverage(
    events: list[dict[str, str]],
    spans: list[dict[str, str]],
) -> dict[str, dict[str, float]]:
    event_by_sequence = {
        row["sequence"]: row for row in measured_events(events)
    }
    intervals: dict[str, list[tuple[int, int]]] = defaultdict(list)
    inclusive_wall: dict[str, float] = defaultdict(float)
    for row in spans:
        if (
            row["span_scope"] != COMPONENT_SCOPE
            or row["sequence"] not in event_by_sequence
        ):
            continue
        phase = row["phase"]
        start = int(row["span_started_uptime_nanoseconds"])
        end = int(row["span_completed_uptime_nanoseconds"])
        if end > start:
            intervals[phase].append((start, end))
        inclusive_wall[phase] += float(row["span_wall_ms"])
    result: dict[str, dict[str, float]] = {}
    for phase in sorted({row["phase"] for row in event_by_sequence.values()}):
        phase_wall = sum(
            float(row["wall_ms"])
            for row in event_by_sequence.values()
            if row["phase"] == phase
        )
        union_ms = _union_nanoseconds(intervals[phase]) / 1_000_000
        result[phase] = {
            "union_wall_ms": union_ms,
            "inclusive_wall_ms": inclusive_wall[phase],
            "overlap_wall_ms": max(0.0, inclusive_wall[phase] - union_ms),
            "union_coverage": union_ms / phase_wall if phase_wall > 0 else 0.0,
        }
    return result


def root_cause_rankings(span_metrics: dict[str, Any]) -> dict[str, Any]:
    rankings: dict[str, Any] = {}
    for phase, scopes in span_metrics.items():
        components = scopes.get(COMPONENT_SCOPE, {})
        rows = [
            {
                "name": name,
                "cpu_time_p95_ms": values["cpu_time_ms"]["p95"],
                "cpu_percent": values["cpu_percent"],
                "wall_p95_ms": values["wall_ms"]["p95"],
                "overlap": values["overlap"],
            }
            for name, values in components.items()
            if values["count"] > 0
        ]
        rankings[phase] = {
            "by_cpu_time": sorted(
                rows, key=lambda row: row["cpu_time_p95_ms"], reverse=True
            ),
            "by_cpu_percent": sorted(
                rows, key=lambda row: row["cpu_percent"], reverse=True
            ),
            "by_wall": sorted(
                rows, key=lambda row: row["wall_p95_ms"], reverse=True
            ),
        }
    return rankings


def median_span_summaries(
    attempts: list[dict[str, Any]],
) -> dict[str, Any]:
    if not attempts or not all(isinstance(item.get("spans"), dict) for item in attempts):
        return {}
    result: dict[str, Any] = {}
    phases = set.intersection(*(set(item["spans"]) for item in attempts))
    for phase in sorted(phases):
        result[phase] = {}
        scopes = set.intersection(
            *(set(item["spans"][phase]) for item in attempts)
        )
        for scope in sorted(scopes):
            result[phase][scope] = {}
            names = set.intersection(
                *(set(item["spans"][phase][scope]) for item in attempts)
            )
            for name in sorted(names):
                result[phase][scope][name] = {
                    metric: {
                        statistic: median(
                            item["spans"][phase][scope][name][metric][statistic]
                            for item in attempts
                        )
                        for statistic in ("p50", "p95", "max")
                    }
                    for metric in ("wall_ms", "cpu_time_ms")
                }
                result[phase][scope][name]["cpu_percent"] = median(
                    item["spans"][phase][scope][name]["cpu_percent"]
                    for item in attempts
                )
                result[phase][scope][name]["count"] = median(
                    item["spans"][phase][scope][name]["count"]
                    for item in attempts
                )
                result[phase][scope][name]["overlap"] = any(
                    item["spans"][phase][scope][name]["overlap"]
                    for item in attempts
                )
    return result


def _overlapping_component_keys(
    spans: list[dict[str, str]],
) -> set[tuple[str, str]]:
    indexed: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in spans:
        if row.get("span_scope") != COMPONENT_SCOPE:
            continue
        start = int(row["span_started_uptime_nanoseconds"])
        end = int(row["span_completed_uptime_nanoseconds"])
        if end > start:
            indexed[row["sequence"]].append(row)

    overlapping: set[tuple[str, str]] = set()
    for rows in indexed.values():
        active: list[dict[str, str]] = []
        for row in sorted(
            rows,
            key=lambda item: (
                int(item["span_started_uptime_nanoseconds"]),
                int(item["span_completed_uptime_nanoseconds"]),
            ),
        ):
            start = int(row["span_started_uptime_nanoseconds"])
            active = [
                item
                for item in active
                if int(item["span_completed_uptime_nanoseconds"])
                > start
            ]
            for other in active:
                if other["metric_name"] == row["metric_name"]:
                    continue
                overlapping.add((row["phase"], row["metric_name"]))
                overlapping.add(
                    (other["phase"], other["metric_name"])
                )
            active.append(row)
    return overlapping


def _union_nanoseconds(intervals: list[tuple[int, int]]) -> int:
    merged: list[tuple[int, int]] = []
    for start, end in sorted(intervals):
        if not merged or start > merged[-1][1]:
            merged.append((start, end))
        else:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
    return sum(end - start for start, end in merged)
