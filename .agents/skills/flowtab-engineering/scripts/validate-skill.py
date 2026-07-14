#!/usr/bin/env python3
"""Validate the FlowTab Skill folder and an optional distribution archive."""

from __future__ import annotations

import argparse
import json
import re
import stat
import sys
import zipfile
from pathlib import Path, PurePosixPath


FRONTMATTER_RE = re.compile(
    r"\A---\r?\n(?P<frontmatter>.*?)\r?\n---\r?\n(?P<body>.*)\Z",
    re.DOTALL,
)
NAME_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
REFERENCE_RE = re.compile(r"references/([A-Za-z0-9._-]+\.md)")


def parse_frontmatter(skill_file: Path, errors: list[str]) -> tuple[dict[str, str], str]:
    text = skill_file.read_text(encoding="utf-8")
    match = FRONTMATTER_RE.match(text)
    if not match:
        errors.append("SKILL.md must contain one YAML frontmatter block followed by a body")
        return {}, ""

    values: dict[str, str] = {}
    for line in match.group("frontmatter").splitlines():
        if not line.strip():
            continue
        key, separator, raw_value = line.partition(":")
        if not separator:
            errors.append(f"invalid frontmatter line: {line}")
            continue
        key = key.strip()
        raw_value = raw_value.strip()
        if raw_value.startswith('"'):
            try:
                value = json.loads(raw_value)
            except json.JSONDecodeError as error:
                errors.append(f"invalid quoted frontmatter value for {key}: {error}")
                continue
        else:
            value = raw_value
        if not isinstance(value, str):
            errors.append(f"frontmatter field {key} must be a string")
            continue
        if key in values:
            errors.append(f"duplicate frontmatter field: {key}")
        values[key] = value
    return values, match.group("body")


def quoted_yaml_value(text: str, key: str, errors: list[str]) -> str | None:
    pattern = re.compile(
        rf"^\s+{re.escape(key)}:\s*(?P<value>\"(?:[^\"\\]|\\.)*\")\s*$",
        re.MULTILINE,
    )
    match = pattern.search(text)
    if not match:
        errors.append(f"agents/openai.yaml must contain a quoted {key}")
        return None
    try:
        value = json.loads(match.group("value"))
    except json.JSONDecodeError as error:
        errors.append(f"invalid agents/openai.yaml value for {key}: {error}")
        return None
    return value


def validate_openai_yaml(skill_root: Path, skill_name: str, errors: list[str]) -> None:
    metadata_file = skill_root / "agents" / "openai.yaml"
    if not metadata_file.is_file():
        errors.append("agents/openai.yaml is missing")
        return

    text = metadata_file.read_text(encoding="utf-8")
    display_name = quoted_yaml_value(text, "display_name", errors)
    short_description = quoted_yaml_value(text, "short_description", errors)
    default_prompt = quoted_yaml_value(text, "default_prompt", errors)

    if display_name is not None and not display_name.strip():
        errors.append("display_name must not be empty")
    if short_description is not None and not 25 <= len(short_description) <= 64:
        errors.append("short_description must contain 25 to 64 characters")
    if default_prompt is not None and f"${skill_name}" not in default_prompt:
        errors.append(f"default_prompt must mention ${skill_name}")

    policy_match = re.search(
        r"^\s+allow_implicit_invocation:\s*(true|false)\s*$",
        text,
        re.MULTILINE,
    )
    if not policy_match:
        errors.append("agents/openai.yaml must declare allow_implicit_invocation")
    elif policy_match.group(1) != "true":
        errors.append("the consolidated repository Skill must allow implicit invocation")


def validate_references(skill_root: Path, skill_text: str, errors: list[str]) -> None:
    references_root = skill_root / "references"
    if not references_root.is_dir():
        errors.append("references/ is missing")
        return

    reference_files = sorted(references_root.rglob("*.md"))
    if not reference_files:
        errors.append("references/ must contain at least one Markdown file")
        return

    for reference_file in reference_files:
        relative = reference_file.relative_to(references_root)
        if len(relative.parts) != 1:
            errors.append(f"reference must stay one level below SKILL.md: {relative}")
        intent = f"references/{relative.as_posix()}"
        if intent not in skill_text:
            errors.append(f"SKILL.md does not link directly to {intent}")

        lines = reference_file.read_text(encoding="utf-8").splitlines()
        if len(lines) > 100 and "## Contents" not in lines[:40]:
            errors.append(f"{intent} has more than 100 lines and no early Contents section")

    for reference_name in sorted(set(REFERENCE_RE.findall(skill_text))):
        if not (references_root / reference_name).is_file():
            errors.append(f"SKILL.md references a missing file: references/{reference_name}")


def validate_scripts(skill_root: Path, errors: list[str]) -> None:
    scripts_root = skill_root / "scripts"
    if not scripts_root.is_dir():
        errors.append("scripts/ is missing")
        return
    for script in sorted(scripts_root.glob("*.py")):
        try:
            compile(script.read_text(encoding="utf-8"), str(script), "exec")
        except SyntaxError as error:
            errors.append(f"{script.relative_to(skill_root)} has invalid Python: {error}")


def validate_skill(skill_root: Path) -> list[str]:
    errors: list[str] = []
    skill_file = skill_root / "SKILL.md"
    if not skill_file.is_file():
        return ["SKILL.md is missing"]

    values, body = parse_frontmatter(skill_file, errors)
    if set(values) != {"name", "description"}:
        errors.append("frontmatter must contain exactly name and description")

    name = values.get("name", "")
    description = values.get("description", "")
    if not NAME_RE.fullmatch(name) or len(name) > 64:
        errors.append("name must be hyphen-case and no longer than 64 characters")
    if name != skill_root.name:
        errors.append(f"frontmatter name {name!r} must match folder {skill_root.name!r}")
    if not description.strip():
        errors.append("description must not be empty")
    if "<" in description or ">" in description:
        errors.append("description must not contain angle brackets")
    if len(description) > 1024:
        errors.append(f"description has {len(description)} characters; maximum is 1024")
    if not body.strip():
        errors.append("SKILL.md body must not be empty")
    if len(skill_file.read_text(encoding="utf-8").splitlines()) > 500:
        errors.append("SKILL.md must stay below 500 lines")

    validate_openai_yaml(skill_root, name, errors)
    skill_text = skill_file.read_text(encoding="utf-8")
    validate_references(skill_root, skill_text, errors)
    validate_scripts(skill_root, errors)

    scanned_files = [
        path
        for path in skill_root.rglob("*")
        if path.is_file() and path.suffix in {".md", ".yaml", ".yml", ".py"}
    ]
    retired_skill_name = "flowtab-" + "direct-delivery"
    sibling_reference_prefix = ".." + "/flowtab-"
    for path in scanned_files:
        text = path.read_text(encoding="utf-8")
        relative = path.relative_to(skill_root)
        if retired_skill_name in text:
            errors.append(f"stale Skill name in {relative}")
        if sibling_reference_prefix in text:
            errors.append(f"cross-Skill sibling reference in {relative}")

    return errors


def validate_archive(archive: Path, expected_top_level: str) -> list[str]:
    errors: list[str] = []
    if not archive.is_file() or not zipfile.is_zipfile(archive):
        return [f"archive is missing or is not a zip file: {archive}"]

    with zipfile.ZipFile(archive) as bundle:
        files = [entry for entry in bundle.infolist() if entry.filename]
        top_levels: set[str] = set()
        skill_files: list[str] = []
        for entry in files:
            path = PurePosixPath(entry.filename)
            if path.is_absolute() or ".." in path.parts:
                errors.append(f"archive entry escapes its root: {entry.filename}")
                continue
            if "__MACOSX" in path.parts or any(part.startswith("._") for part in path.parts):
                errors.append(f"macOS metadata entry is not allowed: {entry.filename}")
            if path.parts:
                top_levels.add(path.parts[0])
            if path.name == "SKILL.md":
                skill_files.append(entry.filename)
            mode = (entry.external_attr >> 16) & 0o170000
            if stat.S_ISLNK(mode):
                errors.append(f"archive symlink is not allowed: {entry.filename}")

        if top_levels != {expected_top_level}:
            errors.append(
                f"archive must contain one top-level folder named {expected_top_level}: "
                f"{sorted(top_levels)}"
            )
        expected_skill_file = f"{expected_top_level}/SKILL.md"
        if skill_files != [expected_skill_file]:
            errors.append(
                f"archive must contain exactly {expected_skill_file}: {skill_files}"
            )
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "skill_root",
        nargs="?",
        type=Path,
        default=Path(__file__).resolve().parents[1],
    )
    parser.add_argument("--archive", type=Path)
    args = parser.parse_args()

    skill_root = args.skill_root.resolve()
    errors = validate_skill(skill_root)
    if args.archive is not None:
        errors.extend(validate_archive(args.archive.resolve(), skill_root.name))

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print(f"PASS: {skill_root}")
    if args.archive is not None:
        print(f"PASS: {args.archive.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
