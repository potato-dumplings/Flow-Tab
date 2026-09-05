#!/usr/bin/env python3
from __future__ import annotations

import csv
import platform
from pathlib import Path
from typing import Any

from control_tab_pressure_span_schema import (
    PROTOCOL_VERSION,
    REQUIRED_COMPONENTS,
    SCHEMA_DIGEST,
    schema_failures,
    span_rows,
)

LATENCY_LIMITS_MS = {
    "ready_open": 50.0,
    "forward": 33.334,
    "reverse": 33.334,
    "cancel": 50.0,
    "commit_activation_request": 50.0,
}
LIFECYCLE_PHASES = (
    "open",
    "forward",
    "reverse",
    "commit",
    "cancel",
    "cooldown",
)
OPEN_PARTITIONS = {
    "invalidation_ms",
    "projection_read_ms",
    "freshness_wait_ms",
    "recency_ms",
    "session_build_ms",
    "session_publish_ms",
    "preview_prewarm_ms",
    "screen_resolve_ms",
    "panel_size_ms",
    "panel_center_ms",
    "accessibility_ms",
    "panel_presentation_ms",
    "unattributed_ms",
}
OPEN_MILESTONES = {
    "session_ready_ms",
    "panel_presented_ms",
    "first_window_content_draw_ms",
    "visibility_readback_ms",
    "first_visible_frame_ms",
    "cached_first_frame_ms",
    "cached_first_frame_cpu_time_ms",
    "fresh_visible_previews_complete_ms",
    "fresh_visible_previews_complete_cpu_time_ms",
    "command_return_ms",
}
COMMAND_PATH_PARTITIONS = {"command_execution_ms"}
COMMAND_PATH_MILESTONES = {"command_return_ms"}
COMMIT_MILESTONES = {
    "activation_request_ms",
    "panel_hidden_ms",
    "focus_verified_ms",
    "cleanup_complete_ms",
}
CANCEL_MILESTONES = {
    "panel_hidden_ms",
    "cleanup_complete_ms",
}


def load_phase_metrics(
    path: Path,
) -> tuple[
    list[dict[str, str]],
    dict[str, int],
    dict[tuple[str, str], dict[str, float]],
    list[dict[str, str]],
    list[dict[str, str]],
    list[str],
]:
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    events = [
        row
        for row in rows
        if row.get("record_kind") == "event"
        and row.get("metric_kind") == "event"
    ]
    markers: dict[str, int] = {}
    metric_index: dict[tuple[str, str], dict[str, float]] = {}
    for row in rows:
        if row.get("record_kind") == "marker":
            markers[row["phase"]] = int(
                row["started_uptime_nanoseconds"]
            )
        metric_kind = row.get("metric_kind", "")
        if metric_kind in {"partition", "milestone"}:
            key = (row["sequence"], metric_kind)
            metric_index.setdefault(key, {})[row["metric_name"]] = float(
                row["metric_ms"]
            )
    proofs = [row for row in rows if row.get("record_kind") == "proof"]
    return (
        events,
        markers,
        metric_index,
        proofs,
        span_rows(rows),
        schema_failures(rows),
    )


def environment_identity(lane: str, scenario: str) -> dict[str, str | int]:
    return {
        "protocol_version": PROTOCOL_VERSION,
        "machine": platform.node(),
        "system": platform.platform(),
        "architecture": platform.machine(),
        "build_configuration": "Release",
        "lane": lane,
        "scenario": scenario,
        "schema_digest": SCHEMA_DIGEST,
        "required_span_set": ";".join(
            f"{phase}:{','.join(sorted(names))}"
            for phase, names in sorted(REQUIRED_COMPONENTS.items())
        ),
    }


def compatible_identity(left: dict[str, Any], right: dict[str, Any]) -> bool:
    if any(identity.get("protocol_version") != PROTOCOL_VERSION
           or identity.get("schema_digest") != SCHEMA_DIGEST for identity in (left, right)):
        return False
    return all(
        left.get(key) == right.get(key)
        for key in environment_identity("", "")
    )
