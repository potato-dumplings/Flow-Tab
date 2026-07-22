#!/usr/bin/env python3
"""Validate the repository-local composition of the two FlowTab Skills."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


COVERAGE = "COVERAGE"
LEGACY_TERMS = {
    "TEST_" + COVERAGE + "_MATRIX",
    "TEST_" + COVERAGE + "_CHECKLIST",
    "UNIT_AND_BEHAVIOR_TEST_" + COVERAGE,
    "UI_AUTOMATION_TEST_" + COVERAGE,
    "test-coverage-" + "matrix-workflow",
    COVERAGE + "_EVIDENCE_PROJECTION",
}
LEGACY_FILES = {
    f"docs/{term}.md"
    for term in LEGACY_TERMS
    if term.isupper() and not term.endswith("PROJECTION")
}
LEGACY_FILES.add(
    ".agents/skills/flowtab-engineering/references/test-coverage-" + "matrix-workflow.md"
)
TEXT_SUFFIXES = {".json", ".jsonl", ".md", ".py", ".sh", ".swift", ".yaml", ".yml"}
AUDIT_ROOT_INTENT = "docs/test-audit"
PER_CAMPAIGN_ROOT_INTENT = "/".join((AUDIT_ROOT_INTENT, "campaigns")) + "/"
DERIVED_DATASET_NAMES = (
    "TEST_ASSET_LEDGER.jsonl",
    "VALIDATION_PLAN.jsonl",
    "EXECUTION_OBSERVATIONS.jsonl",
)
CAMPAIGN_DATASET_MODELS = {
    "ASSET_DELTAS.jsonl": "asset_delta",
    "EXECUTION_OBSERVATIONS.jsonl": "execution_observation",
    "TEST_ASSET_LEDGER.jsonl": "test_asset",
    "VALIDATION_PLAN.jsonl": "validation_plan_row",
}


def tracked_files(repository_root: Path) -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=repository_root,
        check=True,
        capture_output=True,
    )
    return [
        repository_root / value.decode("utf-8")
        for value in result.stdout.split(b"\0")
        if value
    ]


def main() -> int:
    repository_root = Path(__file__).resolve().parents[2]
    engineering = repository_root / ".agents/skills/flowtab-engineering"
    audit = repository_root / ".agents/skills/flowtab-test-audit"
    errors: list[str] = []

    for root in (engineering, audit):
        if not (root / "SKILL.md").is_file():
            errors.append(f"missing Skill: {root}")

    audit_text = (audit / "SKILL.md").read_text(encoding="utf-8")
    if "$flowtab-engineering" not in audit_text:
        errors.append("flowtab-test-audit does not invoke $flowtab-engineering")
    if "shared-test-asset-rules.json" not in audit_text:
        errors.append("flowtab-test-audit does not load the shared rule manifest")
    if "test-asset-boundaries.json" not in audit_text:
        errors.append("flowtab-test-audit does not load the shared replacement boundary")
    if ".build-local/test-audit/rebuild/" not in audit_text:
        errors.append("flowtab-test-audit does not own one transient reconstruction root")
    if PER_CAMPAIGN_ROOT_INTENT in audit_text:
        errors.append("flowtab-test-audit contains an accumulated Campaign asset root")
    for current_anchor in (
        "docs/test-audit/C0_HANDOFF.json",
        "docs/test-audit/C2_HANDOFF.json",
        "docs/test-audit/slices/<slice-id>/SLICE_HANDOFF.json",
    ):
        if current_anchor not in audit_text:
            errors.append(f"flowtab-test-audit is missing current anchor {current_anchor}")
    for dataset_name in DERIVED_DATASET_NAMES:
        tracked_dataset = "/".join((AUDIT_ROOT_INTENT, dataset_name))
        if tracked_dataset in audit_text:
            errors.append(f"flowtab-test-audit tracks derived dataset {tracked_dataset}")

    manifest_path = engineering / "references/shared-test-asset-rules.json"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        errors.append(f"invalid shared rule manifest: {error}")
        manifest = {"resources": []}

    roles: set[str] = set()
    for entry in manifest.get("resources", []):
        if set(entry) != {"relative_path_intent", "role"}:
            errors.append(f"invalid manifest entry: {entry!r}")
            continue
        role = entry["role"]
        intent = entry["relative_path_intent"]
        if role in roles:
            errors.append(f"duplicate shared rule role: {role}")
        roles.add(role)
        resource = engineering / intent
        if not resource.is_file():
            errors.append(f"missing shared rule resource: {intent}")

    required_roles = {
        "asset_contract",
        "asset_boundaries",
        "asset_delta_schema",
        "asset_discovery",
        "asset_model",
        "asset_schema",
        "asset_views",
        "boundary_enforcement",
        "execution_observation_schema",
        "layer_assignment",
        "pressure",
        "reconstruction_safety",
        "requiredness",
        "validation_plan_schema",
    }
    missing_roles = sorted(required_roles - roles)
    if missing_roles:
        errors.append(f"missing shared rule roles: {missing_roles}")

    scripts_root = engineering / "scripts"
    sys.path.insert(0, str(scripts_root))
    try:
        from test_asset_boundary import assert_boundary_closure, load_boundary_manifest
        from test_asset_index import discover_assets
        from test_asset_model import (
            SCHEMA_FILENAMES,
            SCHEMAS,
            canonical_jsonl,
            rule_snapshot,
            schema_text,
            validate_record,
        )

        rule_snapshot(engineering, manifest_path)
        load_boundary_manifest(engineering / "references/test-asset-boundaries.json")
        for kind, filename in SCHEMA_FILENAMES.items():
            schema_path = engineering / "references" / filename
            if schema_path.read_text(encoding="utf-8") != schema_text(kind):
                errors.append(f"stale generated schema: {filename}")
        records = discover_assets(repository_root)
        assert_boundary_closure(repository_root, records)
        round_trip = [
            validate_record(json.loads(line), "test_asset")
            for line in canonical_jsonl(records).splitlines()
        ]
        if canonical_jsonl(records) != canonical_jsonl(round_trip):
            errors.append("audit ledger does not round-trip through engineering's canonical model")
        if not any(record["asset_type"] == "target" for record in records):
            errors.append("canonical discovery does not expose test-owned Target assets")
        if set(CAMPAIGN_DATASET_MODELS.values()) != set(SCHEMAS):
            errors.append("audit datasets and engineering record models have diverged")
        for dataset in CAMPAIGN_DATASET_MODELS:
            if dataset not in audit_text:
                errors.append(f"audit Skill does not route canonical dataset {dataset}")
    except Exception as error:
        errors.append(f"shared rule loading failed: {error}")

    audit_references = sorted((audit / "references").glob("*.md"))
    if {path.name for path in audit_references} != {
        "stage-01-empty-boundary-and-reconstruction-plan.md",
        "stage-02-dependency-slice-reconstruction.md",
        "stage-03-reconstruction-scheduling-and-full-closure.md",
    }:
        errors.append("audit references must contain only the three Stage contracts")
    for path in audit_references:
        text = path.read_text(encoding="utf-8")
        if ".codex/hooks/test_semantic_guard.py authorize" in text:
            errors.append(f"{path.name} duplicates engineering's semantic guard")
        for term in LEGACY_TERMS:
            if term in text:
                errors.append(f"{path.name} contains legacy coverage term {term}")
    stage_one = audit / "references/stage-01-empty-boundary-and-reconstruction-plan.md"
    stage_one_text = stage_one.read_text(encoding="utf-8")
    if "assert-reconstruction-empty" not in stage_one_text:
        errors.append("Stage 01 does not enforce the empty-boundary gate")
    if "reconstruction-clear-plan" not in stage_one_text:
        errors.append("Stage 01 does not enforce the pre-clear safety plan")
    stage_two_text = (
        audit / "references/stage-02-dependency-slice-reconstruction.md"
    ).read_text(encoding="utf-8")
    if "VALIDATION_PLAN_REFS.json" not in stage_two_text:
        errors.append("Stage 02 does not bind C1 to canonical validation-plan rows")
    stage_three_text = (
        audit / "references/stage-03-reconstruction-scheduling-and-full-closure.md"
    ).read_text(encoding="utf-8")
    if "assert-boundary-closure" not in stage_three_text:
        errors.append("Stage 03 does not enforce final asset-boundary closure")

    for script in sorted((engineering / "scripts").glob("*.py")):
        line_count = len(script.read_text(encoding="utf-8").splitlines())
        if line_count > 800:
            errors.append(f"oversized Skill script ({line_count} lines): {script.name}")

    audit_root = repository_root / AUDIT_ROOT_INTENT
    if (audit_root / "campaigns").exists():
        errors.append("current tree contains accumulated Campaign asset roots")
    disallowed_datasets = {
        "ASSET_DELTAS.jsonl",
        "BASELINE_RESULTS.jsonl",
        "EXECUTION_OBSERVATIONS.jsonl",
        "TEST_ASSET_LEDGER.jsonl",
        "VALIDATION_PLAN.jsonl",
    }
    if audit_root.is_dir():
        for path in audit_root.rglob("*"):
            if path.is_file() and path.name in disallowed_datasets:
                errors.append(f"derived audit dataset is tracked in the current tree: {path.relative_to(repository_root)}")

    for intent in LEGACY_FILES:
        if (repository_root / intent).exists():
            errors.append(f"legacy tracked document still exists: {intent}")

    try:
        files = tracked_files(repository_root)
    except subprocess.CalledProcessError as error:
        errors.append(f"git ls-files failed: {error}")
        files = []
    for path in files:
        relative = path.relative_to(repository_root).as_posix()
        if not path.is_file() or path.suffix not in TEXT_SUFFIXES:
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for term in LEGACY_TERMS:
            if term in text:
                errors.append(f"active legacy reference {term} in {relative}")

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print("PASS: repository-local FlowTab Skill composition")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
