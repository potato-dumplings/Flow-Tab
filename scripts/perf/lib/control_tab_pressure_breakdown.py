#!/usr/bin/env python3
from __future__ import annotations

from collections import defaultdict
from typing import Any

from control_tab_pressure_metrics import measured_events, stats
from control_tab_pressure_spans import COMPONENT_SCOPE, span_summary


def event_breakdowns(
    events: list[dict[str, str]],
    spans: list[dict[str, str]],
    lane: str,
) -> list[dict[str, Any]]:
    measured = measured_events(events)
    grouped: dict[tuple[Any, ...], list[dict[str, str]]] = defaultdict(list)
    for event in measured:
        grouped[_group_key(event, lane)].append(event)
    spans_by_sequence: dict[str, list[dict[str, str]]] = defaultdict(list)
    for span in spans:
        spans_by_sequence[span["sequence"]].append(span)

    result: list[dict[str, Any]] = []
    for key, group_events in sorted(grouped.items(), key=lambda item: item[0]):
        sequences = {event["sequence"] for event in group_events}
        group_spans = [
            span
            for sequence in sequences
            for span in spans_by_sequence.get(sequence, [])
        ]
        wall = [float(event["wall_ms"]) for event in group_events]
        cpu = [float(event["cpu_time_ms"]) for event in group_events]
        phase = group_events[0]["phase"]
        summarized = span_summary(group_events, group_spans)
        result.append(
            {
                "lane": lane,
                "phase": phase,
                "app_count": int(group_events[0]["projected_app_count"]),
                "window_count": int(group_events[0]["selected_window_count"]),
                "projection_generation": (
                    int(group_events[0]["projection_generation"])
                    if lane == "mutation"
                    else None
                ),
                "target_pid": (
                    int(group_events[0].get("activation_target_pid", "0"))
                    if lane == "topology" and phase == "commit"
                    else None
                ),
                "target_window_id": (
                    group_events[0].get("activation_target_window_id", "none")
                    if lane == "topology" and phase == "commit"
                    else None
                ),
                "target_cg_window_id": (
                    int(
                        group_events[0].get(
                            "activation_target_cg_window_id", "0"
                        )
                    )
                    if lane == "topology" and phase == "commit"
                    else None
                ),
                "event_count": len(group_events),
                "wall_ms": stats(wall),
                "cpu_time_ms": stats(cpu),
                "cpu_percent": (
                    100.0 * sum(cpu) / sum(wall)
                    if sum(wall) > 0
                    else 0.0
                ),
                "components": summarized.get(phase, {}).get(
                    COMPONENT_SCOPE, {}
                ),
            }
        )
    return result


def mutation_generation_evidence(
    proofs: list[dict[str, str]],
) -> list[dict[str, Any]]:
    values = {
        (
            int(row.get("proof_generation", "0")),
            row.get("proof_detail", ""),
            int(row.get("proof_pid", "0")),
        )
        for row in proofs
        if row.get("proof_kind") == "mutation_generation"
    }
    return [
        {"generation": generation, "detail": detail, "pid": pid}
        for generation, detail, pid in sorted(values)
    ]


def topology_target_evidence(
    events: list[dict[str, str]],
) -> list[dict[str, Any]]:
    targets = {
        (
            int(row.get("activation_target_pid", "0")),
            row.get("activation_target_window_id", "none"),
            int(row.get("activation_target_cg_window_id", "0")),
        )
        for row in measured_events(events)
        if row.get("phase") == "commit"
        and row.get("activation_verified") == "1"
    }
    return [
        {"pid": pid, "window_id": window_id, "cg_window_id": cg_window_id}
        for pid, window_id, cg_window_id in sorted(targets)
    ]


def _group_key(event: dict[str, str], lane: str) -> tuple[Any, ...]:
    phase = event["phase"]
    base: tuple[Any, ...] = (
        phase,
        int(event["projected_app_count"]),
        int(event["selected_window_count"]),
    )
    if lane == "mutation":
        return base + (int(event["projection_generation"]),)
    if lane == "topology" and phase == "commit":
        return base + (
            int(event.get("activation_target_pid", "0")),
            event.get("activation_target_window_id", "none"),
            int(event.get("activation_target_cg_window_id", "0")),
        )
    return base
