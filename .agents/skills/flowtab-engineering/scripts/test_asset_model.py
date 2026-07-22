#!/usr/bin/env python3
"""Canonical FlowTab test-asset records, schemas, and serialization."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path, PurePosixPath
from typing import Any, Iterable


ASSET_TYPES = [
    "capability_probe",
    "configuration",
    "fixture",
    "pressure_scenario",
    "runner",
    "scheme",
    "target",
    "test_declaration",
    "test_file",
    "testing_support",
]
LAYERS = ["behavior", "pressure", "process_tooling", "ui_mock", "ui_real_topology", "unit"]
REQUIREDNESS = ["not_applicable", "optional", "required"]
EXECUTION_STATUSES = ["blocked", "failed", "flaky", "not_run", "passed", "skipped", "unknown"]
CHANGE_KINDS = ["added", "merged", "modified", "moved", "renamed", "retired", "split"]
LINEAGE_BASES = [
    "deterministic_identity",
    "snapshot_absence",
    "type_and_fingerprint_candidates",
    "unique_type_and_fingerprint",
]
LINEAGE_CONFIDENCES = ["confirmed", "inferred", "unresolved"]
PROTECTED_BEHAVIOR_STATUSES = ["ambiguous", "confirmed", "inferred"]
ORACLE_KINDS = [
    "documented_contract",
    "explicit_input",
    "independent_observation",
    "independent_specification",
    "platform_api",
    "stable_fixture",
]
ORACLE_STATUSES = ["conflicting", "missing", "provisional", "valid"]
SCHEMA_FILENAMES = {
    "asset_delta": "asset-delta.schema.json",
    "execution_observation": "execution-observation.schema.json",
    "test_asset": "test-asset.schema.json",
    "validation_plan_row": "validation-plan-row.schema.json",
}


def _string_or_null() -> dict[str, Any]:
    return {"type": ["string", "null"]}


def _source_ref() -> dict[str, Any]:
    return {
        "type": "object",
        "additionalProperties": False,
        "required": ["resource_boundary", "relative_path_intent", "line", "qualified_symbol"],
        "properties": {
            "resource_boundary": {"type": "string"},
            "relative_path_intent": {"type": "string"},
            "line": {"type": ["integer", "null"]},
            "qualified_symbol": _string_or_null(),
        },
    }


def _locator() -> dict[str, Any]:
    return {
        "type": "object",
        "additionalProperties": False,
        "required": [
            "resource_boundary",
            "relative_path_intent",
            "declared_name",
            "qualified_symbol",
            "target",
        ],
        "properties": {
            "resource_boundary": {"type": "string"},
            "relative_path_intent": {"type": "string"},
            "declared_name": _string_or_null(),
            "qualified_symbol": _string_or_null(),
            "target": _string_or_null(),
        },
    }


TEST_ASSET_SCHEMA: dict[str, Any] = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "additionalProperties": False,
    "required": [
        "record_kind",
        "asset_id",
        "asset_type",
        "identity_key",
        "asset_locator",
        "asset_fingerprint",
        "owner",
        "layer_capabilities",
        "execution_entry",
        "dependencies",
        "observed_test_semantics",
        "provenance",
    ],
    "properties": {
        "record_kind": {"const": "test_asset"},
        "asset_id": {"type": "string"},
        "asset_type": {"enum": ASSET_TYPES},
        "identity_key": {
            "type": "object",
            "minProperties": 1,
            "additionalProperties": {"type": ["string", "null"]},
        },
        "asset_locator": _locator(),
        "asset_fingerprint": {"type": "string", "pattern": "^sha256:[0-9a-f]{64}$"},
        "owner": {"type": "string"},
        "layer_capabilities": {"type": "array", "items": {"enum": LAYERS}},
        "execution_entry": {
            "type": ["object", "null"],
            "additionalProperties": False,
            "required": ["runner_ref", "interface", "selector"],
            "properties": {
                "runner_ref": _string_or_null(),
                "interface": {"type": "string"},
                "selector": _string_or_null(),
            },
        },
        "dependencies": {"type": "array", "items": {"type": "string"}},
        "observed_test_semantics": {
            "type": ["object", "null"],
            "additionalProperties": False,
            "required": ["input_refs", "fixture_refs", "assertion_refs", "extraction_status"],
            "properties": {
                "input_refs": {"type": "array", "items": _source_ref()},
                "fixture_refs": {"type": "array", "items": _source_ref()},
                "assertion_refs": {"type": "array", "items": _source_ref()},
                "extraction_status": {"enum": ["references_only", "unsupported"]},
            },
        },
        "provenance": {"type": "array", "items": _source_ref(), "minItems": 1},
    },
}


VALIDATION_PLAN_SCHEMA: dict[str, Any] = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "additionalProperties": False,
    "required": [
        "record_kind",
        "record_lifecycle",
        "scope_kind",
        "plan_row_id",
        "scope_id",
        "asset_id",
        "scenario_ref",
        "requiredness",
        "layer",
        "runner_ref",
        "prerequisite_refs",
        "protected_behavior",
        "oracle",
        "provenance",
    ],
    "properties": {
        "record_kind": {"const": "validation_plan_row"},
        "record_lifecycle": {"const": "transient"},
        "scope_kind": {"enum": ["reconstruction", "task"]},
        "plan_row_id": {"type": "string"},
        "scope_id": {"type": "string"},
        "asset_id": _string_or_null(),
        "scenario_ref": {
            "type": "object",
            "additionalProperties": False,
            "required": ["statement", "source_refs"],
            "properties": {
                "statement": {"type": "string"},
                "source_refs": {"type": "array", "items": _source_ref()},
            },
        },
        "requiredness": {"enum": REQUIREDNESS},
        "layer": {"enum": LAYERS},
        "runner_ref": _string_or_null(),
        "prerequisite_refs": {"type": "array", "items": {"type": "string"}},
        "protected_behavior": {
            "type": "object",
            "additionalProperties": False,
            "required": ["statement", "status", "source_refs"],
            "properties": {
                "statement": {"type": "string"},
                "status": {"enum": PROTECTED_BEHAVIOR_STATUSES},
                "source_refs": {"type": "array", "items": _source_ref()},
            },
        },
        "oracle": {
            "type": "object",
            "additionalProperties": False,
            "required": ["kind", "status", "evidence_refs", "independence_basis"],
            "properties": {
                "kind": {"enum": ORACLE_KINDS},
                "status": {"enum": ORACLE_STATUSES},
                "evidence_refs": {"type": "array", "items": _source_ref()},
                "independence_basis": {"type": ["string", "null"]},
            },
        },
        "provenance": {"type": "array", "items": _source_ref(), "minItems": 1},
    },
}


EXECUTION_OBSERVATION_SCHEMA: dict[str, Any] = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "additionalProperties": False,
    "required": [
        "record_kind",
        "attempt_id",
        "plan_row_id",
        "execution_status",
        "evidence_refs",
        "environment_identity",
        "blocked_reason",
        "started_at",
    ],
    "properties": {
        "record_kind": {"const": "execution_observation"},
        "attempt_id": {"type": "string"},
        "plan_row_id": {"type": "string"},
        "execution_status": {"enum": EXECUTION_STATUSES},
        "evidence_refs": {"type": "array", "items": _source_ref()},
        "environment_identity": {
            "type": "object",
            "minProperties": 1,
            "additionalProperties": {"type": ["string", "null"]},
        },
        "blocked_reason": _string_or_null(),
        "started_at": _string_or_null(),
    },
}


ASSET_DELTA_SCHEMA: dict[str, Any] = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "additionalProperties": False,
    "required": [
        "record_kind",
        "delta_id",
        "change_kind",
        "before_ref",
        "before_fingerprint",
        "after_record",
        "lineage_basis",
        "lineage_candidates",
        "lineage_confidence",
        "lineage_evidence",
    ],
    "properties": {
        "record_kind": {"const": "asset_delta"},
        "delta_id": {"type": "string"},
        "change_kind": {"enum": CHANGE_KINDS},
        "before_ref": _string_or_null(),
        "before_fingerprint": {
            "type": ["string", "null"],
            "pattern": "^sha256:[0-9a-f]{64}$",
        },
        "after_record": {
            "oneOf": [
                {"type": "null"},
                {"$ref": "test-asset.schema.json"},
            ]
        },
        "lineage_basis": {"enum": LINEAGE_BASES},
        "lineage_candidates": {"type": "array", "items": {"type": "string"}},
        "lineage_confidence": {"enum": LINEAGE_CONFIDENCES},
        "lineage_evidence": {
            "type": "array",
            "items": {"type": "string"},
            "minItems": 1,
        },
    },
}

SCHEMAS = {
    "asset_delta": ASSET_DELTA_SCHEMA,
    "execution_observation": EXECUTION_OBSERVATION_SCHEMA,
    "test_asset": TEST_ASSET_SCHEMA,
    "validation_plan_row": VALIDATION_PLAN_SCHEMA,
}
RECORD_IDS = {
    "asset_delta": "delta_id",
    "execution_observation": "attempt_id",
    "test_asset": "asset_id",
    "validation_plan_row": "plan_row_id",
}
UNORDERED_ARRAY_FIELDS = {
    "assertion_refs",
    "dependencies",
    "evidence_refs",
    "fixture_refs",
    "input_refs",
    "layer_capabilities",
    "lineage_candidates",
    "lineage_evidence",
    "prerequisite_refs",
    "provenance",
    "source_refs",
}


class RecordValidationError(ValueError):
    """A record does not satisfy its canonical structure."""


def normalize_path_intent(value: str) -> str:
    path = PurePosixPath(value.replace("\\", "/"))
    if path.is_absolute() or ".." in path.parts:
        raise RecordValidationError(f"path intent must stay relative to its resource boundary: {value}")
    normalized = path.as_posix()
    return "" if normalized == "." else normalized.removeprefix("./")


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def normalize_value(value: Any, field: str | None = None) -> Any:
    if isinstance(value, dict):
        normalized = {key: normalize_value(item, key) for key, item in value.items()}
        return dict(sorted(normalized.items()))
    if isinstance(value, list):
        normalized = [normalize_value(item) for item in value]
        if field in UNORDERED_ARRAY_FIELDS:
            normalized.sort(key=canonical_json)
        return normalized
    if field == "relative_path_intent" and isinstance(value, str):
        return normalize_path_intent(value)
    return value


def _type_matches(expected: str, value: Any) -> bool:
    return {
        "array": isinstance(value, list),
        "integer": isinstance(value, int) and not isinstance(value, bool),
        "null": value is None,
        "object": isinstance(value, dict),
        "string": isinstance(value, str),
    }.get(expected, False)


def _validate(schema: dict[str, Any], value: Any, path: str) -> None:
    expected_types = schema.get("type")
    if expected_types is not None:
        choices = [expected_types] if isinstance(expected_types, str) else expected_types
        if not any(_type_matches(choice, value) for choice in choices):
            raise RecordValidationError(f"{path}: expected {choices}, found {type(value).__name__}")
        if value is None:
            return
    if "const" in schema and value != schema["const"]:
        raise RecordValidationError(f"{path}: expected {schema['const']!r}")
    if "enum" in schema and value not in schema["enum"]:
        raise RecordValidationError(f"{path}: unsupported value {value!r}")
    if isinstance(value, str) and "pattern" in schema:
        import re

        if re.fullmatch(schema["pattern"], value) is None:
            raise RecordValidationError(f"{path}: value does not match {schema['pattern']}")
    if isinstance(value, list):
        if len(value) < schema.get("minItems", 0):
            raise RecordValidationError(f"{path}: too few items")
        for index, item in enumerate(value):
            _validate(schema.get("items", {}), item, f"{path}[{index}]")
    if isinstance(value, dict):
        if len(value) < schema.get("minProperties", 0):
            raise RecordValidationError(f"{path}: too few properties")
        required = set(schema.get("required", []))
        missing = sorted(required - set(value))
        if missing:
            raise RecordValidationError(f"{path}: missing properties {missing}")
        properties = schema.get("properties", {})
        additional = schema.get("additionalProperties", True)
        extras = sorted(set(value) - set(properties))
        if extras and additional is False:
            raise RecordValidationError(f"{path}: unexpected properties {extras}")
        for key, item in value.items():
            child_schema = properties.get(key, additional if isinstance(additional, dict) else {})
            _validate(child_schema, item, f"{path}.{key}")


def validate_record(record: dict[str, Any], expected_kind: str | None = None) -> dict[str, Any]:
    normalized = normalize_value(record)
    kind = normalized.get("record_kind")
    if kind not in SCHEMAS:
        raise RecordValidationError(f"unsupported record_kind: {kind!r}")
    if expected_kind is not None and kind != expected_kind:
        raise RecordValidationError(f"expected {expected_kind}, found {kind}")
    _validate(SCHEMAS[kind], normalized, kind)
    if kind == "test_asset":
        expected_asset_id = make_id(normalized["asset_type"], normalized["identity_key"])
        if normalized["asset_id"] != expected_asset_id:
            raise RecordValidationError(
                f"test_asset.asset_id does not match its type-specific identity key: {normalized['asset_id']}"
            )
    if kind == "asset_delta" and normalized["after_record"] is not None:
        validate_record(normalized["after_record"], "test_asset")
    if kind == "asset_delta":
        after = normalized["after_record"]
        identity = {
            "after": after["asset_id"] if after else None,
            "after_fingerprint": after["asset_fingerprint"] if after else None,
            "before": normalized["before_ref"],
            "before_fingerprint": normalized["before_fingerprint"],
            "change_kind": normalized["change_kind"],
            "lineage_basis": normalized["lineage_basis"],
            "lineage_confidence": normalized["lineage_confidence"],
        }
        if (normalized["before_ref"] is None) != (normalized["before_fingerprint"] is None):
            raise RecordValidationError(
                "asset_delta before_ref and before_fingerprint must appear together"
            )
        expected_delta_id = make_id("asset_delta", identity)
        if normalized["delta_id"] != expected_delta_id:
            raise RecordValidationError("asset_delta.delta_id does not match its lineage identity")
        if normalized["lineage_confidence"] == "unresolved" and not normalized["lineage_candidates"]:
            raise RecordValidationError("unresolved asset lineage requires candidate asset IDs")
        if normalized["lineage_confidence"] != "unresolved" and normalized["lineage_candidates"]:
            raise RecordValidationError("resolved asset lineage cannot retain candidate asset IDs")
        if (
            normalized["lineage_basis"] == "type_and_fingerprint_candidates"
        ) != (normalized["lineage_confidence"] == "unresolved"):
            raise RecordValidationError(
                "candidate lineage basis and unresolved confidence must appear together"
            )
    return normalized


def canonical_jsonl(records: Iterable[dict[str, Any]]) -> str:
    normalized = [validate_record(record) for record in records]
    normalized.sort(key=lambda row: (row["record_kind"], str(row[RECORD_IDS[row["record_kind"]]])))
    return "".join(f"{canonical_json(row)}\n" for row in normalized)


def aggregate_required_status(
    plan_rows: Iterable[dict[str, Any]],
    observations: Iterable[dict[str, Any]],
) -> str:
    plans = [validate_record(row, "validation_plan_row") for row in plan_rows]
    latest = {
        row["plan_row_id"]: validate_record(row, "execution_observation")
        for row in observations
    }
    required = [row for row in plans if row["requiredness"] == "required"]
    if not required:
        return "not relevant"
    statuses: list[str] = []
    for row in required:
        observation = latest.get(row["plan_row_id"])
        status = observation["execution_status"] if observation else "not_run"
        if status in {"flaky", "skipped", "unknown"}:
            raise RecordValidationError(
                f"Required row {row['plan_row_id']} has unresolved execution status {status}"
            )
        statuses.append(status)
    for status in ("failed", "blocked", "not_run", "passed"):
        if status in statuses:
            return status
    raise RecordValidationError(f"cannot aggregate statuses: {statuses}")


def load_jsonl(path: Path, expected_kind: str | None = None) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        try:
            value = json.loads(line)
        except json.JSONDecodeError as error:
            raise RecordValidationError(f"{path}:{line_number}: {error}") from error
        if not isinstance(value, dict):
            raise RecordValidationError(f"{path}:{line_number}: row must be an object")
        rows.append(validate_record(value, expected_kind))
    return rows


def sha256_bytes(value: bytes) -> str:
    return f"sha256:{hashlib.sha256(value).hexdigest()}"


def make_id(prefix: str, identity: Any) -> str:
    digest = hashlib.sha256(canonical_json(normalize_value(identity)).encode("utf-8")).hexdigest()
    return f"{prefix}:{digest}"


def target_identity(project_identity: str, target: str) -> dict[str, str]:
    return {"project": project_identity, "target": target}


def target_id(project_identity: str, target: str) -> str:
    return make_id("target", target_identity(project_identity, target))


def runner_identity(intent: str, interface: str) -> dict[str, str]:
    return {"interface": interface, "relative_path_intent": intent}


def runner_id(intent: str, interface: str) -> str:
    return make_id("runner", runner_identity(intent, interface))


def configuration_identity(owner: str, intent: str, key: str) -> dict[str, str]:
    return {
        "configuration_key": key,
        "owner": owner,
        "relative_path_intent": intent,
    }


def schema_text(kind: str) -> str:
    return json.dumps(SCHEMAS[kind], ensure_ascii=False, sort_keys=True, indent=2) + "\n"


def rule_snapshot(skill_root: Path, manifest_path: Path) -> dict[str, Any]:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    resources: list[dict[str, str]] = []
    for entry in manifest.get("resources", []):
        intent = normalize_path_intent(entry["relative_path_intent"])
        resource = (skill_root / intent).resolve()
        if skill_root.resolve() not in resource.parents or not resource.is_file():
            raise RecordValidationError(f"shared rule resource is unavailable: {intent}")
        resources.append(
            {
                "role": entry["role"],
                "relative_path_intent": intent,
                "sha256": sha256_bytes(resource.read_bytes()),
            }
        )
    resources.sort(key=lambda row: (row["role"], row["relative_path_intent"]))
    return {
        "source_skill": "flowtab-engineering",
        "resources": resources,
        "aggregate_sha256": sha256_bytes(canonical_json(resources).encode("utf-8")),
    }
