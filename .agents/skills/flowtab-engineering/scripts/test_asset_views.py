#!/usr/bin/env python3
"""Canonical scopes, references, and projections for test-asset records."""

from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path, PurePosixPath
from typing import Any, Iterable

from test_asset_model import (
    RECORD_IDS,
    RecordValidationError,
    canonical_json,
    canonical_jsonl,
    normalize_path_intent,
    sha256_bytes,
)


def _within_scope(intent: str, scopes: list[str]) -> bool:
    path_parts = PurePosixPath(intent).parts
    return any(
        path_parts[: len(PurePosixPath(scope).parts)] == PurePosixPath(scope).parts
        for scope in scopes
    )


def filter_assets(records: Iterable[dict[str, Any]], scopes: list[str]) -> list[dict[str, Any]]:
    normalized = [normalize_path_intent(scope) for scope in scopes]
    return [
        record
        for record in records
        if _within_scope(record["asset_locator"]["relative_path_intent"], normalized)
    ]


def build_projection(
    ledger: list[dict[str, Any]],
    plan: list[dict[str, Any]],
    observations: list[dict[str, Any]],
) -> dict[str, Any]:
    return {
        "asset_counts": dict(sorted(Counter(row["asset_type"] for row in ledger).items())),
        "execution_status_counts": dict(
            sorted(Counter(row["execution_status"] for row in observations).items())
        ),
        "record_kind": "derived_test_asset_projection",
        "requiredness_counts": dict(
            sorted(Counter(row["requiredness"] for row in plan).items())
        ),
        "source_record_counts": {
            "execution_observation": len(observations),
            "test_asset": len(ledger),
            "validation_plan_row": len(plan),
        },
    }


def record_references(
    rows: list[dict[str, Any]],
    record_kind: str,
    selected_ids: list[str],
) -> dict[str, Any]:
    id_field = RECORD_IDS[record_kind]
    by_id = {row[id_field]: row for row in rows}
    requested = sorted(set(selected_ids)) if selected_ids else sorted(by_id)
    missing = sorted(set(requested) - set(by_id))
    if missing:
        raise RecordValidationError(f"requested record IDs are unavailable: {missing}")
    references = [
        {
            "record_id": record_id,
            "sha256": sha256_bytes(canonical_json(by_id[record_id]).encode("utf-8")),
        }
        for record_id in requested
    ]
    return {
        "aggregate_sha256": sha256_bytes(canonical_json(references).encode("utf-8")),
        "record_kind": "canonical_record_references",
        "records": references,
        "source_sha256": sha256_bytes(canonical_jsonl(rows).encode("utf-8")),
        "source_record_kind": record_kind,
    }


def write_output(path: str, text: str) -> None:
    if path == "-":
        sys.stdout.write(text)
        return
    output = Path(path)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text, encoding="utf-8")


def projection_text(projection: dict[str, Any]) -> str:
    return json.dumps(projection, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
