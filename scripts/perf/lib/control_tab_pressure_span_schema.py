#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
from pathlib import Path

SCHEMA = json.loads(Path(__file__).with_name("control_tab_pressure_v6_schema.json").read_text(encoding="utf-8"))
PROTOCOL_VERSION = SCHEMA["protocol_version"]
SCHEMA_DIGEST = hashlib.sha256(json.dumps(
    SCHEMA, sort_keys=True, ensure_ascii=False, separators=(",", ":")
).encode("utf-8")).hexdigest()
COMPONENT_NAMES = {item["name"] for item in SCHEMA["components"]}
COMPONENT_SCOPE = "component_inclusive"
TIMELINE_SCOPE = "timeline_exclusive"
PHASE_CPU_LIMIT_PERCENT = 50.0
SPAN_REQUIRED_FIELDS = {
    "phase",
    "sequence",
    "metric_name",
    "span_parent",
    "span_started_uptime_nanoseconds",
    "span_completed_uptime_nanoseconds",
    "span_wall_ms",
    "span_cpu_time_ms",
    "span_cpu_percent",
    "span_timing_valid",
    "span_scope",
    "span_outcome",
    "span_work_units",
}

REQUIRED_COMPONENTS = {phase: set(names) for phase, names in SCHEMA["required_components"].items()}


def span_rows(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    return [
        row
        for row in rows
        if row.get("record_kind") == "span"
        and row.get("span_scope") in {COMPONENT_SCOPE, TIMELINE_SCOPE}
        and _span_shape_valid(row)
    ]


def schema_failures(rows: list[dict[str, str]]) -> list[str]:
    failures: list[str] = []
    for row in rows:
        sequence = row.get("sequence", "unknown")
        if row.get("protocol_version") != str(PROTOCOL_VERSION):
            failures.append(f"protocol:{sequence}")
        if row.get("schema_digest") != SCHEMA_DIGEST:
            failures.append(f"schema:{sequence}")
        if row.get("record_kind") == "span":
            missing = sorted(
                field
                for field in SPAN_REQUIRED_FIELDS
                if row.get(field, "") == ""
            )
            if missing:
                failures.append(
                    f"span-fields:{sequence}:{','.join(missing)}"
                )
            elif not _span_shape_valid(row):
                failures.append(f"span-values:{sequence}")
    return sorted(set(failures))


def _span_shape_valid(row: dict[str, str]) -> bool:
    if any(row.get(field, "") == "" for field in SPAN_REQUIRED_FIELDS):
        return False
    try:
        int(row["sequence"])
        int(row["span_started_uptime_nanoseconds"])
        int(row["span_completed_uptime_nanoseconds"])
        int(row["span_work_units"])
        float(row["span_wall_ms"])
        float(row["span_cpu_time_ms"])
        float(row["span_cpu_percent"])
    except (KeyError, TypeError, ValueError):
        return False
    return row["span_timing_valid"] in {"0", "1"} and (
        row.get("span_scope") != COMPONENT_SCOPE or row.get("metric_name") in COMPONENT_NAMES
    )
