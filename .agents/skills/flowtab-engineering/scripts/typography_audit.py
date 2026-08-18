#!/usr/bin/env python3
"""Audit FlowTab font construction against the tracked typography allowlist."""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Iterable


@dataclass(frozen=True)
class Detector:
    kind: str
    pattern: re.Pattern[str]


@dataclass(frozen=True)
class Finding:
    file: str
    kind: str
    line: int
    source: str

    def as_dict(self) -> dict[str, object]:
        return {
            "file": self.file,
            "kind": self.kind,
            "line": self.line,
            "source": self.source,
        }


DETECTORS = (
    Detector(
        "swiftui-system-size",
        re.compile(r"\.system\s*\(\s*size\s*:", re.DOTALL),
    ),
    Detector(
        "swiftui-custom-font",
        re.compile(r"\bFont\s*\.\s*custom\s*\(", re.DOTALL),
    ),
    Detector(
        "appkit-system-font",
        re.compile(
            r"(?:\bNSFont\s*\.\s*|\.)?systemFont\s*\(\s*ofSize\s*:",
            re.DOTALL,
        ),
    ),
    Detector(
        "appkit-monospaced-system-font",
        re.compile(
            r"(?:\bNSFont\s*\.\s*|\.)?monospacedSystemFont"
            r"\s*\(\s*ofSize\s*:",
            re.DOTALL,
        ),
    ),
    Detector(
        "appkit-other-sized-font",
        re.compile(
            r"(?<![A-Za-z0-9_])"
            r"(?!(?:systemFont|monospacedSystemFont)\b)"
            r"[A-Za-z_][A-Za-z0-9_]*Font\s*\(\s*ofSize\s*:",
            re.DOTALL,
        ),
    ),
    Detector(
        "appkit-named-font",
        re.compile(
            r"\bNSFont\s*\(\s*name\s*:.{0,500}?\bsize\s*:",
            re.DOTALL,
        ),
    ),
    Detector(
        "appkit-descriptor-font",
        re.compile(
            r"\bNSFont\s*\(\s*descriptor\s*:.{0,500}?\bsize\s*:",
            re.DOTALL,
        ),
    ),
    Detector(
        "resized-font",
        re.compile(r"\.withSize\s*\(", re.DOTALL),
    ),
)
DETECTOR_KINDS = frozenset(detector.kind for detector in DETECTORS)
CLASSIFICATIONS = frozenset({"canonical-source", "named-exception", "testing-diagnostic", "legacy"})
DEFAULT_ALLOWLIST = (
    Path(__file__).resolve().parents[1]
    / "references"
    / "typography-audit-allowlist.json"
)


def mask_noncode(source: str) -> str:
    """Replace Swift comments and string contents while preserving offsets."""

    masked = list(source)
    index = 0
    block_depth = 0
    state = "code"
    string_delimiter = ""

    def blank(position: int) -> None:
        if masked[position] != "\n":
            masked[position] = " "

    while index < len(source):
        if state == "line-comment":
            if source[index] == "\n":
                state = "code"
            else:
                blank(index)
            index += 1
            continue

        if state == "block-comment":
            if source.startswith("/*", index):
                blank(index)
                blank(index + 1)
                block_depth += 1
                index += 2
                continue
            if source.startswith("*/", index):
                blank(index)
                blank(index + 1)
                block_depth -= 1
                index += 2
                if block_depth == 0:
                    state = "code"
                continue
            blank(index)
            index += 1
            continue

        if state == "string":
            if source.startswith(string_delimiter, index):
                for offset in range(len(string_delimiter)):
                    blank(index + offset)
                index += len(string_delimiter)
                state = "code"
                continue
            if string_delimiter == '"' and source[index] == "\\":
                blank(index)
                index += 1
                if index < len(source):
                    blank(index)
                    index += 1
                continue
            blank(index)
            index += 1
            continue

        if source.startswith("//", index):
            blank(index)
            blank(index + 1)
            state = "line-comment"
            index += 2
            continue
        if source.startswith("/*", index):
            blank(index)
            blank(index + 1)
            state = "block-comment"
            block_depth = 1
            index += 2
            continue
        if source.startswith('"""', index):
            for offset in range(3):
                blank(index + offset)
            string_delimiter = '"""'
            state = "string"
            index += 3
            continue
        if source[index] == '"':
            blank(index)
            string_delimiter = '"'
            state = "string"
            index += 1
            continue
        index += 1

    return "".join(masked)


def excerpt(source: str, start: int, end: int) -> str:
    start_line = source.rfind("\n", 0, start) + 1
    end_line = source.find("\n", end)
    if end_line == -1:
        end_line = len(source)
    normalized = " ".join(source[start_line:end_line].split())
    if len(normalized) > 180:
        return normalized[:177] + "..."
    return normalized


def scan_file(repository_root: Path, source_file: Path) -> list[Finding]:
    source = source_file.read_text(encoding="utf-8")
    searchable = mask_noncode(source)
    relative = source_file.relative_to(repository_root).as_posix()
    findings: list[Finding] = []
    for detector in DETECTORS:
        for match in detector.pattern.finditer(searchable):
            findings.append(
                Finding(
                    file=relative,
                    kind=detector.kind,
                    line=source.count("\n", 0, match.start()) + 1,
                    source=excerpt(source, match.start(), match.end()),
                )
            )
    return findings


def scan_repository(repository_root: Path) -> list[Finding]:
    source_root = repository_root / "FlowTab"
    if not source_root.is_dir():
        raise ValueError(f"FlowTab source root is missing: {source_root}")
    findings: list[Finding] = []
    for source_file in sorted(source_root.rglob("*.swift")):
        findings.extend(scan_file(repository_root, source_file))
    return sorted(findings, key=lambda item: (item.file, item.line, item.kind))


def load_allowlist(path: Path, repository_root: Path) -> dict[tuple[str, str], int]:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise ValueError(f"typography allowlist is missing: {path}") from error
    except json.JSONDecodeError as error:
        raise ValueError(f"invalid typography allowlist JSON: {error}") from error

    if not isinstance(document, dict) or document.get("schema_version") != 1:
        raise ValueError("typography allowlist must use schema_version 1")
    scope = document.get("scope")
    expected_scope = {
        "resource_boundary": "repository_root",
        "relative_path_intent": "FlowTab",
    }
    if scope != expected_scope:
        raise ValueError(f"typography allowlist scope must equal {expected_scope}")

    entries = document.get("entries")
    if not isinstance(entries, list) or not entries:
        raise ValueError("typography allowlist entries must be a non-empty list")

    expected: dict[tuple[str, str], int] = {}
    required_fields = {"file", "kind", "expected_count", "classification", "target"}
    for index, raw_entry in enumerate(entries):
        label = f"entries[{index}]"
        if not isinstance(raw_entry, dict) or set(raw_entry) != required_fields:
            raise ValueError(f"{label} must contain exactly {sorted(required_fields)}")

        file = raw_entry["file"]
        kind = raw_entry["kind"]
        count = raw_entry["expected_count"]
        classification = raw_entry["classification"]
        target = raw_entry["target"]
        if not all(isinstance(value, str) for value in (file, kind, classification, target)):
            raise ValueError(f"{label} string fields must contain strings")
        path_intent = PurePosixPath(file)
        if path_intent.is_absolute() or ".." in path_intent.parts:
            raise ValueError(f"{label}.file must be a repository-relative path intent")
        if not file.startswith("FlowTab/") or not (repository_root / file).is_file():
            raise ValueError(f"{label}.file is outside or missing from FlowTab: {file}")
        if kind not in DETECTOR_KINDS:
            raise ValueError(f"{label}.kind is unsupported: {kind}")
        if type(count) is not int or count <= 0:
            raise ValueError(f"{label}.expected_count must be a positive integer")
        if classification not in CLASSIFICATIONS:
            raise ValueError(f"{label}.classification is unsupported: {classification}")
        if not target.strip():
            raise ValueError(f"{label}.target must not be empty")
        key = (file, kind)
        if key in expected:
            raise ValueError(f"duplicate typography allowlist entry: {file} / {kind}")
        expected[key] = count
    return expected


def compare_allowlist(
    findings: Iterable[Finding], expected: dict[tuple[str, str], int]
) -> list[str]:
    actual = Counter((finding.file, finding.kind) for finding in findings)
    errors: list[str] = []
    for key in sorted(actual.keys() | expected.keys()):
        actual_count = actual.get(key, 0)
        expected_count = expected.get(key, 0)
        if actual_count != expected_count:
            file, kind = key
            errors.append(
                f"{file} / {kind}: expected {expected_count}, found {actual_count}"
            )
    return errors


def run_self_test() -> None:
    sample = '''
// .font(.system(size: 99))
let string = "NSFont(name: fake, size: 99)"
let swiftUIFont = Font.system(size: 12)
let appKitFont = NSFont.systemFont(ofSize: 13)
let bold = NSFont.boldSystemFont(ofSize: 15)
let monospaced = NSFont.monospacedSystemFont(
    ofSize: 11,
    weight: .regular
)
let named = NSFont(name: fontName, size: displaySize)
let descriptor = NSFont(
    descriptor: font.fontDescriptor,
    size: font.pointSize * scale
)
let custom = Font.custom("Example", size: 14)
let resized = font.withSize(15)
'''
    searchable = mask_noncode(sample)
    actual = Counter(
        detector.kind
        for detector in DETECTORS
        for _ in detector.pattern.finditer(searchable)
    )
    expected = Counter(
        {
            "swiftui-system-size": 1,
            "swiftui-custom-font": 1,
            "appkit-system-font": 1,
            "appkit-other-sized-font": 1,
            "appkit-monospaced-system-font": 1,
            "appkit-named-font": 1,
            "appkit-descriptor-font": 1,
            "resized-font": 1,
        }
    )
    if actual != expected:
        raise AssertionError(f"detector self-test mismatch: expected {expected}, found {actual}")


def print_findings(findings: list[Finding], output_format: str) -> None:
    if output_format == "json":
        print(json.dumps([finding.as_dict() for finding in findings], indent=2))
        return
    for finding in findings:
        print(f"{finding.file}:{finding.line}: {finding.kind}: {finding.source}")
    print(f"FOUND: {len(findings)} typography construction entries")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Audit FlowTab font construction against a tracked allowlist."
    )
    parser.add_argument("--repository-root", type=Path)
    parser.add_argument("--allowlist", type=Path, default=DEFAULT_ALLOWLIST)
    parser.add_argument("--scan", action="store_true", help="list findings without checking")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--format", choices=("text", "json"), default="text")
    args = parser.parse_args()

    if args.self_test:
        run_self_test()
        print("PASS: typography audit detector self-test")
        return 0
    if args.repository_root is None:
        parser.error("--repository-root is required unless --self-test is used")

    repository_root = args.repository_root.resolve()
    try:
        findings = scan_repository(repository_root)
        if args.scan:
            print_findings(findings, args.format)
            return 0
        allowlist = args.allowlist.resolve()
        expected = load_allowlist(allowlist, repository_root)
        errors = compare_allowlist(findings, expected)
    except (OSError, UnicodeError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        print_findings(findings, args.format)
        return 1

    allowlist_display = (
        allowlist.relative_to(repository_root)
        if allowlist.is_relative_to(repository_root)
        else allowlist
    )
    print(
        f"PASS: {len(findings)} typography construction entries match "
        f"{allowlist_display}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
