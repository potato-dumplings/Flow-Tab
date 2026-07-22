#!/usr/bin/env python3
"""Validate FlowTab Skill routing and asset-workflow evaluation cases."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


ID_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
ROUTES = {"flowtab-engineering", "flowtab-test-audit", "none"}
ASSET_SCOPES = {"none", "paths", "replace_all", "stage_owned"}
REQUIRED_KEYS = {
    "id",
    "prompt",
    "expected_route",
    "expected_references",
    "asset_scope",
    "expectations",
}


def main() -> int:
    repository_root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "cases",
        nargs="?",
        type=Path,
        default=Path(__file__).with_name("flowtab-engineering-cases.jsonl"),
    )
    parser.add_argument(
        "--engineering-skill-root",
        type=Path,
        default=repository_root / ".agents/skills/flowtab-engineering",
    )
    parser.add_argument(
        "--audit-skill-root",
        type=Path,
        default=repository_root / ".agents/skills/flowtab-test-audit",
    )
    args = parser.parse_args()

    reference_names = {
        path.name
        for root in (args.engineering_skill_root, args.audit_skill_root)
        for path in (root / "references").glob("*.md")
    }
    errors: list[str] = []
    cases: list[dict[str, object]] = []
    seen_ids: set[str] = set()

    for line_number, line in enumerate(
        args.cases.read_text(encoding="utf-8").splitlines(), start=1
    ):
        if not line.strip():
            continue
        try:
            case = json.loads(line)
        except json.JSONDecodeError as error:
            errors.append(f"line {line_number}: invalid JSON: {error}")
            continue
        if not isinstance(case, dict) or set(case) != REQUIRED_KEYS:
            found = sorted(case) if isinstance(case, dict) else type(case).__name__
            errors.append(
                f"line {line_number}: expected keys {sorted(REQUIRED_KEYS)}, found {found}"
            )
            continue

        case_id = case["id"]
        if not isinstance(case_id, str) or not ID_RE.fullmatch(case_id):
            errors.append(f"line {line_number}: invalid id {case_id!r}")
        elif case_id in seen_ids:
            errors.append(f"line {line_number}: duplicate id {case_id}")
        else:
            seen_ids.add(case_id)

        prompt = case["prompt"]
        if not isinstance(prompt, str) or not prompt.strip():
            errors.append(f"line {line_number}: prompt must be non-empty")

        route = case["expected_route"]
        if route not in ROUTES:
            errors.append(f"line {line_number}: invalid route {route!r}")

        expected_references = case["expected_references"]
        if not isinstance(expected_references, list) or not all(
            isinstance(value, str) for value in expected_references
        ):
            errors.append(f"line {line_number}: expected_references must be strings")
        else:
            missing = sorted(set(expected_references) - reference_names)
            if missing:
                errors.append(f"line {line_number}: missing references {missing}")

        asset_scope = case["asset_scope"]
        if asset_scope not in ASSET_SCOPES:
            errors.append(f"line {line_number}: invalid asset scope {asset_scope!r}")

        expectations = case["expectations"]
        if not isinstance(expectations, list) or not expectations or not all(
            isinstance(value, str) and value.strip() for value in expectations
        ):
            errors.append(f"line {line_number}: expectations must be non-empty strings")

        if route == "none" and (expected_references or asset_scope != "none"):
            errors.append(f"line {line_number}: non-FlowTab case owns Skill work")
        if route == "flowtab-test-audit" and not any(
            name.startswith("stage-") for name in expected_references
        ):
            errors.append(f"line {line_number}: audit route has no stage reference")
        if (
            route == "flowtab-test-audit"
            and "stage-01-empty-boundary-and-reconstruction-plan.md" in expected_references
            and asset_scope != "replace_all"
        ):
            errors.append(f"line {line_number}: Stage 01 must replace the full asset boundary")
        cases.append(case)

    if len(cases) < 18:
        errors.append("evaluation corpus must contain at least 18 cases")
    routes = {case.get("expected_route") for case in cases}
    if routes != ROUTES:
        errors.append(f"evaluation corpus must cover routes {sorted(ROUTES)}")
    scopes = {case.get("asset_scope") for case in cases}
    if not {"paths", "replace_all", "stage_owned"}.issubset(scopes):
        errors.append("evaluation corpus must cover paths, replace_all, and stage_owned asset scopes")

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"PASS: {len(cases)} cases from {args.cases.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
