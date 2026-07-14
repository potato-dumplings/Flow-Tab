#!/usr/bin/env python3
"""Validate the FlowTab engineering Skill evaluation corpus."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


ID_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
REGISTRY_PHASES = {"none", "publication", "prompt_entry"}
REQUIRED_KEYS = {
    "id",
    "prompt",
    "expect_trigger",
    "expected_references",
    "registry_entry_phase",
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
        "--skill-root",
        type=Path,
        default=repository_root / ".agents" / "skills" / "flowtab-engineering",
    )
    args = parser.parse_args()

    cases_path = args.cases.resolve()
    skill_root = args.skill_root.resolve()
    reference_names = {
        path.name for path in (skill_root / "references").glob("*.md")
    }
    errors: list[str] = []
    cases: list[dict[str, object]] = []
    seen_ids: set[str] = set()

    for line_number, line in enumerate(
        cases_path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        if not line.strip():
            continue
        try:
            case = json.loads(line)
        except json.JSONDecodeError as error:
            errors.append(f"line {line_number}: invalid JSON: {error}")
            continue
        if not isinstance(case, dict):
            errors.append(f"line {line_number}: case must be an object")
            continue
        if set(case) != REQUIRED_KEYS:
            errors.append(
                f"line {line_number}: expected keys {sorted(REQUIRED_KEYS)}, "
                f"found {sorted(case)}"
            )
            continue

        case_id = case["id"]
        if not isinstance(case_id, str) or not ID_RE.fullmatch(case_id):
            errors.append(f"line {line_number}: invalid id {case_id!r}")
        elif case_id in seen_ids:
            errors.append(f"line {line_number}: duplicate id {case_id}")
        else:
            seen_ids.add(case_id)

        if not isinstance(case["prompt"], str) or not case["prompt"].strip():
            errors.append(f"line {line_number}: prompt must be non-empty")
        if not isinstance(case["expect_trigger"], bool):
            errors.append(f"line {line_number}: expect_trigger must be boolean")

        expected_references = case["expected_references"]
        if not isinstance(expected_references, list) or not all(
            isinstance(value, str) for value in expected_references
        ):
            errors.append(f"line {line_number}: expected_references must be strings")
        else:
            missing = sorted(set(expected_references) - reference_names)
            if missing:
                errors.append(f"line {line_number}: missing references {missing}")

        phase = case["registry_entry_phase"]
        if not isinstance(phase, str) or phase not in REGISTRY_PHASES:
            errors.append(f"line {line_number}: invalid registry phase {phase!r}")

        expectations = case["expectations"]
        if not isinstance(expectations, list) or not expectations or not all(
            isinstance(value, str) and value.strip() for value in expectations
        ):
            errors.append(f"line {line_number}: expectations must be non-empty strings")

        if case.get("expect_trigger") is False:
            if expected_references:
                errors.append(f"line {line_number}: non-trigger case has references")
            if phase != "none":
                errors.append(f"line {line_number}: non-trigger case enters Registry")
        cases.append(case)

    if len(cases) < 15:
        errors.append("evaluation corpus must contain at least 15 cases")
    trigger_values = {
        value
        for case in cases
        if isinstance((value := case.get("expect_trigger")), bool)
    }
    if trigger_values != {True, False}:
        errors.append("evaluation corpus must contain trigger and non-trigger cases")
    phases = {
        value
        for case in cases
        if isinstance((value := case.get("registry_entry_phase")), str)
    }
    if phases != REGISTRY_PHASES:
        errors.append(f"evaluation corpus must cover Registry phases {REGISTRY_PHASES}")

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print(f"PASS: {len(cases)} cases from {cases_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
