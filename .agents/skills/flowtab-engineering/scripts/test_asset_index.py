#!/usr/bin/env python3
"""Discover and normalize FlowTab repository test assets."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path, PurePosixPath
from typing import Any, Iterable

from test_asset_boundary import (
    assert_boundary_closure,
    assert_reconstruction_empty,
    fragment_record_specs,
    load_boundary_manifest,
    resolve_carrier_fragment,
    resolve_owned_path,
)
from test_asset_clear_plan import build_reconstruction_clear_plan
from test_asset_model import (
    SCHEMA_FILENAMES,
    SCHEMAS,
    RecordValidationError,
    canonical_json,
    canonical_jsonl,
    configuration_identity,
    load_jsonl,
    make_id,
    normalize_path_intent,
    rule_snapshot,
    runner_id,
    runner_identity,
    schema_text,
    sha256_bytes,
    target_id,
    target_identity,
    validate_record,
)
from test_asset_views import (
    build_projection,
    filter_assets,
    projection_text,
    record_references,
    write_output,
)


DEFAULT_BOUNDARY_MANIFEST = Path(__file__).resolve().parents[1] / "references/test-asset-boundaries.json"
ASSERTION_RE = re.compile(r"\b(?:XCTAssert\w*|XCTFail|XCTUnwrap|#expect|#require)\s*\(")
CONTAINER_RE = re.compile(r"^\s*(?:final\s+)?(?:class|extension)\s+([A-Za-z_][A-Za-z0-9_]*)")
TEST_RE = re.compile(r"^\s*func\s+(test[A-Za-z0-9_]+)\s*\(")
RUNNER_SUFFIXES = {".js", ".py", ".sh"}


def _path_ref(intent: str, line: int | None = None, symbol: str | None = None) -> dict[str, Any]:
    return {
        "resource_boundary": "repository_root",
        "relative_path_intent": normalize_path_intent(intent),
        "line": line,
        "qualified_symbol": symbol,
    }


def _locator(intent: str, name: str | None, symbol: str | None, target: str | None) -> dict[str, Any]:
    return {
        "resource_boundary": "repository_root",
        "relative_path_intent": normalize_path_intent(intent),
        "declared_name": name,
        "qualified_symbol": symbol,
        "target": target,
    }


def _asset(
    asset_type: str,
    identity: dict[str, str | None],
    intent: str,
    source_bytes: bytes,
    owner: str,
    layers: list[str],
    *,
    name: str | None = None,
    symbol: str | None = None,
    target: str | None = None,
    execution_entry: dict[str, Any] | None = None,
    dependencies: list[str] | None = None,
    semantics: dict[str, Any] | None = None,
    provenance: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    return validate_record(
        {
            "record_kind": "test_asset",
            "asset_id": make_id(asset_type, identity),
            "asset_type": asset_type,
            "identity_key": identity,
            "asset_locator": _locator(intent, name, symbol, target),
            "asset_fingerprint": sha256_bytes(source_bytes),
            "owner": owner,
            "layer_capabilities": layers,
            "execution_entry": execution_entry,
            "dependencies": dependencies or [],
            "observed_test_semantics": semantics,
            "provenance": provenance or [_path_ref(intent, symbol=symbol)],
        },
        "test_asset",
    )


def _interface_for_runner_path(intent: str) -> str:
    return {
        "FlowTabCore/Package.swift": "swift-test",
        "scripts/testing/run-flowtabtests-local.sh": "flowtab-tests",
        "scripts/testing/run-ui-tests-local.sh": "flowtab-ui-tests",
    }.get(intent, Path(intent).stem)


def _runner_for_target(target: str) -> tuple[str, str, str | None]:
    if target == "FlowTabCoreTests":
        intent, interface = "FlowTabCore/Package.swift", "swift-test"
        return runner_id(intent, interface), interface, "--filter <qualified-symbol>"
    if target == "FlowTabUITests":
        intent, interface = "scripts/testing/run-ui-tests-local.sh", "flowtab-ui-tests"
        return runner_id(intent, interface), interface, "-only-testing:<target>/<qualified-symbol>"
    intent, interface = "scripts/testing/run-flowtabtests-local.sh", "flowtab-tests"
    return runner_id(intent, interface), interface, "-only-testing:<target>/<qualified-symbol>"


def _method_end(lines: list[str], start: int) -> int:
    depth = 0
    saw_open = False
    for index in range(start, len(lines)):
        depth += lines[index].count("{") - lines[index].count("}")
        saw_open = saw_open or "{" in lines[index]
        if saw_open and depth <= 0:
            return index + 1
    return len(lines)


def _test_assets(
    path: Path,
    repository_root: Path,
    project_identity: str,
    target: str,
    layers: list[str],
) -> list[dict[str, Any]]:
    intent = path.relative_to(repository_root).as_posix()
    source = path.read_bytes()
    file_identity = {"relative_path_intent": intent, "target": target}
    file_record = _asset(
        "test_file",
        file_identity,
        intent,
        source,
        target,
        layers,
        name=path.name,
        target=target,
        dependencies=[target_id(project_identity, target)],
    )
    records = [file_record]
    if path.suffix != ".swift":
        return records

    text = source.decode("utf-8", errors="replace")
    lines = text.splitlines(keepends=True)
    container = path.stem
    for index, line in enumerate(lines):
        container_match = CONTAINER_RE.match(line)
        if container_match:
            container = container_match.group(1)
        test_match = TEST_RE.match(line)
        if not test_match:
            continue
        method = test_match.group(1)
        symbol = f"{container}.{method}"
        end = _method_end(lines, index)
        method_lines = lines[index:end]
        assertion_refs = [
            _path_ref(intent, index + offset + 1, symbol)
            for offset, body_line in enumerate(method_lines)
            if ASSERTION_RE.search(body_line)
        ]
        fixture_refs = [
            _path_ref(intent, index + offset + 1, symbol)
            for offset, body_line in enumerate(method_lines)
            if "fixture" in body_line.lower()
        ]
        runner_ref, interface, selector = _runner_for_target(target)
        if target == "FlowTabCoreTests":
            selector = f"--filter {symbol}"
        else:
            selector = f"-only-testing:{target}/{symbol.replace('.', '/')}"
        semantics = {
            "input_refs": [],
            "fixture_refs": fixture_refs,
            "assertion_refs": assertion_refs,
            "extraction_status": "references_only",
        }
        records.append(
            _asset(
                "test_declaration",
                {"qualified_symbol": symbol, "target": target},
                intent,
                "".join(method_lines).encode("utf-8"),
                target,
                layers,
                name=method,
                symbol=symbol,
                target=target,
                execution_entry={"runner_ref": runner_ref, "interface": interface, "selector": selector},
                dependencies=[file_record["asset_id"], runner_ref, target_id(project_identity, target)],
                semantics=semantics,
                provenance=[_path_ref(intent, index + 1, symbol)],
            )
        )
    return records


def _files_below(root: Path) -> Iterable[Path]:
    if root.is_file():
        return (root,)
    if not root.is_dir():
        return []
    return (path for path in sorted(root.rglob("*")) if path.is_file() and not any(part.startswith(".") for part in path.relative_to(root).parts))


def discover_assets(
    repository_root: Path,
    manifest_path: Path = DEFAULT_BOUNDARY_MANIFEST,
) -> list[dict[str, Any]]:
    repository_root = repository_root.resolve()
    boundary_manifest = load_boundary_manifest(manifest_path)
    records: list[dict[str, Any]] = []

    target_refs: dict[str, str] = {}
    for carrier in boundary_manifest["shared_carriers"]:
        project_identity = carrier["project_identity"]
        for fragment in carrier["test_owned_fragments"]:
            selector = fragment["selector"]
            if selector["kind"] in {"pbxproj_target_graph", "swift_package_test_target"}:
                target = selector["target"]
                target_refs[target] = target_id(project_identity, target)

    for carrier in boundary_manifest["shared_carriers"]:
        intent = carrier["relative_path_intent"]
        path = resolve_owned_path(repository_root, intent)
        if not path.is_file():
            raise RecordValidationError(f"shared carrier is unavailable: {intent}")
        text = path.read_text(encoding="utf-8", errors="replace")
        resolutions: list[tuple[dict[str, Any], Any]] = []
        for fragment in carrier["test_owned_fragments"]:
            try:
                resolution = resolve_carrier_fragment(text, fragment)
            except RecordValidationError as error:
                if "selector did not resolve" not in str(error):
                    raise
                continue
            resolutions.append((fragment, resolution))
        for fragment, resolution in resolutions:
            specs = fragment_record_specs(carrier, fragment, resolution)
            configuration_refs = {
                spec["target"]: make_id(
                    "configuration",
                    configuration_identity(carrier["owner"], intent, spec["declared_name"]),
                )
                for spec in specs
                if spec["asset_type"] == "configuration" and spec["target"] is not None
            }
            for spec in specs:
                if spec["asset_type"] == "target":
                    target = spec["target"]
                    records.append(
                        _asset(
                            "target",
                            target_identity(carrier["project_identity"], target),
                            intent,
                            resolution.source_bytes,
                            carrier["owner"],
                            carrier["layer_capabilities"],
                            name=target,
                            target=target,
                            dependencies=(
                                [configuration_refs[target]] if target in configuration_refs else []
                            ),
                        )
                    )
                elif spec["asset_type"] == "configuration":
                    target = spec["target"]
                    records.append(
                        _asset(
                            "configuration",
                            configuration_identity(
                                carrier["owner"], intent, spec["declared_name"]
                            ),
                            intent,
                            resolution.source_bytes,
                            carrier["owner"],
                            carrier["layer_capabilities"],
                            name=spec["declared_name"],
                            target=target,
                        )
                    )

        if not resolutions:
            continue
        combined_source = b"".join(resolution.source_bytes for _, resolution in resolutions)
        combined_targets = sorted(
            set(target for _, resolution in resolutions for target in resolution.targets)
        )
        dependencies = [target_refs[target] for target in combined_targets if target in target_refs]
        if carrier["discovery_kind"] == "runner":
            interface = carrier["interface"]
            records.append(
                _asset(
                    "runner",
                    runner_identity(intent, interface),
                    intent,
                    combined_source,
                    carrier["owner"],
                    carrier["layer_capabilities"],
                    name=interface,
                    execution_entry={"runner_ref": None, "interface": interface, "selector": None},
                    dependencies=dependencies,
                )
            )
        elif carrier["discovery_kind"] == "scheme":
            scheme_name = path.stem
            records.append(
                _asset(
                    "scheme",
                    {"project": carrier["project_identity"], "scheme": scheme_name},
                    intent,
                    combined_source,
                    carrier["owner"],
                    carrier["layer_capabilities"],
                    name=scheme_name,
                    dependencies=dependencies,
                )
            )

    runner_roots = [
        entry
        for entry in boundary_manifest["asset_boundaries"]
        if entry["asset_type"] in {"runner", "runner_root"}
    ]
    runner_paths = sorted(
        path
        for entry in runner_roots
        for path in _files_below(repository_root / entry["relative_path_intent"])
        if path.suffix in RUNNER_SUFFIXES
    )
    runner_specs: list[tuple[Path, str, str, dict[str, Any]]] = []
    for path in runner_paths:
        intent = path.relative_to(repository_root).as_posix()
        matching_roots = [
            entry
            for entry in runner_roots
            if PurePosixPath(intent).parts[: len(PurePosixPath(entry["relative_path_intent"]).parts)]
            == PurePosixPath(entry["relative_path_intent"]).parts
        ]
        if not matching_roots:
            raise RecordValidationError(f"Runner is outside the shared asset boundary: {intent}")
        boundary = max(matching_roots, key=lambda entry: len(PurePosixPath(entry["relative_path_intent"]).parts))
        runner_specs.append((path, intent, _interface_for_runner_path(intent), boundary))

    for path, intent, interface, boundary in runner_specs:
        layers = boundary["layer_capabilities"]
        source = path.read_bytes()
        source_text = source.decode("utf-8", errors="replace")
        dependencies = [
            runner_id(other_intent, other_interface)
            for _, other_intent, other_interface, _ in runner_specs
            if other_intent != intent and other_intent in source_text
        ]
        records.append(
            _asset(
                "runner",
                runner_identity(intent, interface),
                intent,
                source,
                boundary["owner"],
                layers,
                name=interface,
                execution_entry={"runner_ref": None, "interface": interface, "selector": None},
                dependencies=dependencies,
            )
        )

    for entry in boundary_manifest["asset_boundaries"]:
        if entry["asset_type"] not in {"capability_probe", "pressure_scenario"}:
            continue
        intent = entry["relative_path_intent"]
        path = resolve_owned_path(repository_root, intent)
        if not path.is_file():
            continue
        interface = _interface_for_runner_path(intent)
        if entry["asset_type"] == "capability_probe":
            identity = {"capability": entry["role"], "relative_path_intent": intent}
        else:
            identity = {"runner": intent, "scenario": entry["role"]}
        records.append(
            _asset(
                entry["asset_type"],
                identity,
                intent,
                path.read_bytes(),
                entry["owner"],
                entry["layer_capabilities"],
                name=entry["role"],
                execution_entry={
                    "runner_ref": runner_id(intent, interface),
                    "interface": interface,
                    "selector": None,
                },
                dependencies=[runner_id(intent, interface)],
            )
        )

    for entry in boundary_manifest["asset_boundaries"]:
        if entry["asset_type"] != "test_root":
            continue
        root_intent = entry["relative_path_intent"]
        for path in _files_below(repository_root / root_intent):
            records.extend(
                _test_assets(
                    path,
                    repository_root,
                    entry["project_identity"],
                    entry["target"],
                    entry["layer_capabilities"],
                )
            )

    for entry in boundary_manifest["asset_boundaries"]:
        asset_type = entry["asset_type"]
        if asset_type not in {"fixture", "testing_support"}:
            continue
        root_intent = entry["relative_path_intent"]
        for path in _files_below(repository_root / root_intent):
            intent = path.relative_to(repository_root).as_posix()
            records.append(
                _asset(
                    asset_type,
                    {"relative_path_intent": intent},
                    intent,
                    path.read_bytes(),
                    entry["owner"],
                    entry["layer_capabilities"],
                    name=path.name,
                    target=entry["target"],
                    dependencies=(
                        [target_id(entry["project_identity"], entry["target"])]
                        if entry["target"] is not None
                        else []
                    ),
                )
            )

    for entry in boundary_manifest["asset_boundaries"]:
        if entry["asset_type"] != "scheme":
            continue
        intent = entry["relative_path_intent"]
        path = resolve_owned_path(repository_root, intent)
        if not path.is_file():
            continue
        source = path.read_bytes()
        blueprint_targets = sorted(
            set(
                re.findall(
                    r'BlueprintName\s*=\s*"([^"]+)"',
                    source.decode("utf-8", errors="replace"),
                )
            )
        )
        records.append(
            _asset(
                "scheme",
                {"project": entry["project_identity"], "scheme": path.stem},
                intent,
                source,
                entry["owner"],
                entry["layer_capabilities"],
                name=path.stem,
                target=entry["target"],
                dependencies=[target_refs[target] for target in blueprint_targets if target in target_refs],
            )
        )

    by_id: dict[str, dict[str, Any]] = {}
    for record in records:
        existing = by_id.get(record["asset_id"])
        if existing is not None and canonical_json(existing) != canonical_json(record):
            raise RecordValidationError(f"conflicting asset identity: {record['asset_id']}")
        by_id[record["asset_id"]] = record
    return list(by_id.values())


def _delta(
    kind: str,
    before: dict[str, Any] | None,
    after: dict[str, Any] | None,
    evidence: list[str],
    *,
    lineage_basis: str,
    lineage_confidence: str,
    lineage_candidates: list[str] | None = None,
) -> dict[str, Any]:
    identity = {
        "after": after["asset_id"] if after else None,
        "after_fingerprint": after["asset_fingerprint"] if after else None,
        "before": before["asset_id"] if before else None,
        "before_fingerprint": before["asset_fingerprint"] if before else None,
        "change_kind": kind,
        "lineage_basis": lineage_basis,
        "lineage_confidence": lineage_confidence,
    }
    return validate_record(
        {
            "record_kind": "asset_delta",
            "delta_id": make_id("asset_delta", identity),
            "change_kind": kind,
            "before_ref": before["asset_id"] if before else None,
            "before_fingerprint": before["asset_fingerprint"] if before else None,
            "after_record": after,
            "lineage_basis": lineage_basis,
            "lineage_candidates": lineage_candidates or [],
            "lineage_confidence": lineage_confidence,
            "lineage_evidence": evidence,
        },
        "asset_delta",
    )


def build_deltas(before_rows: list[dict[str, Any]], after_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    before = {row["asset_id"]: row for row in before_rows}
    after = {row["asset_id"]: row for row in after_rows}
    deltas: list[dict[str, Any]] = []
    for asset_id in sorted(set(before) & set(after)):
        old, new = before[asset_id], after[asset_id]
        if canonical_json(old) == canonical_json(new):
            continue
        old_locator, new_locator = old["asset_locator"], new["asset_locator"]
        if old_locator["relative_path_intent"] != new_locator["relative_path_intent"]:
            kind = "moved"
        elif old_locator["declared_name"] != new_locator["declared_name"]:
            kind = "renamed"
        else:
            kind = "modified"
        deltas.append(
            _delta(
                kind,
                old,
                new,
                ["same deterministic asset identity"],
                lineage_basis="deterministic_identity",
                lineage_confidence="confirmed",
            )
        )

    removed = {key: before[key] for key in sorted(set(before) - set(after))}
    added = {key: after[key] for key in sorted(set(after) - set(before))}
    for old_id, old in list(removed.items()):
        match_ids = [
            new_id
            for new_id, new in added.items()
            if new["asset_type"] == old["asset_type"]
            and new["asset_fingerprint"] == old["asset_fingerprint"]
        ]
        matching_removed = [
            candidate
            for candidate in removed.values()
            if candidate["asset_type"] == old["asset_type"]
            and candidate["asset_fingerprint"] == old["asset_fingerprint"]
        ]
        if len(match_ids) != 1 or len(matching_removed) != 1:
            continue
        match_id = match_ids[0]
        new = added.pop(match_id)
        removed.pop(old_id)
        old_path = PurePosixPath(old["asset_locator"]["relative_path_intent"])
        new_path = PurePosixPath(new["asset_locator"]["relative_path_intent"])
        kind = "renamed" if old_path.name != new_path.name else "moved"
        deltas.append(
            _delta(
                kind,
                old,
                new,
                ["matching asset type and content fingerprint"],
                lineage_basis="unique_type_and_fingerprint",
                lineage_confidence="inferred",
            )
        )
    for row in removed.values():
        candidates = sorted(
            candidate["asset_id"]
            for candidate in added.values()
            if candidate["asset_type"] == row["asset_type"]
            and candidate["asset_fingerprint"] == row["asset_fingerprint"]
        )
        deltas.append(
            _delta(
                "retired",
                row,
                None,
                ["asset absent from after snapshot"],
                lineage_basis=(
                    "type_and_fingerprint_candidates" if candidates else "snapshot_absence"
                ),
                lineage_candidates=candidates,
                lineage_confidence="unresolved" if candidates else "confirmed",
            )
        )
    for row in added.values():
        candidates = sorted(
            candidate["asset_id"]
            for candidate in removed.values()
            if candidate["asset_type"] == row["asset_type"]
            and candidate["asset_fingerprint"] == row["asset_fingerprint"]
        )
        deltas.append(
            _delta(
                "added",
                None,
                row,
                ["asset absent from before snapshot"],
                lineage_basis=(
                    "type_and_fingerprint_candidates" if candidates else "snapshot_absence"
                ),
                lineage_candidates=candidates,
                lineage_confidence="unresolved" if candidates else "confirmed",
            )
        )
    return deltas


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    index = subparsers.add_parser("index")
    index.add_argument("--repository-root", required=True, type=Path)
    index.add_argument("--scope", required=True, choices=["all", "paths"])
    index.add_argument("--path-intent", action="append", default=[])
    index.add_argument("--boundary-manifest", type=Path, default=DEFAULT_BOUNDARY_MANIFEST)
    index.add_argument("--output", required=True)

    boundaries = subparsers.add_parser("boundaries")
    boundaries.add_argument("--manifest", type=Path, default=DEFAULT_BOUNDARY_MANIFEST)
    boundaries.add_argument("--output", required=True)

    clear_plan = subparsers.add_parser("reconstruction-clear-plan")
    clear_plan.add_argument("--repository-root", required=True, type=Path)
    clear_plan.add_argument("--rollback-commit", required=True)
    clear_plan.add_argument("--manifest", type=Path, default=DEFAULT_BOUNDARY_MANIFEST)
    clear_plan.add_argument("--output", required=True)

    empty = subparsers.add_parser("assert-reconstruction-empty")
    empty.add_argument("--repository-root", required=True, type=Path)
    empty.add_argument("--manifest", type=Path, default=DEFAULT_BOUNDARY_MANIFEST)
    empty.add_argument("--clear-plan", required=True, type=Path)

    closure = subparsers.add_parser("assert-boundary-closure")
    closure.add_argument("--repository-root", required=True, type=Path)
    closure.add_argument("--ledger", required=True, type=Path)
    closure.add_argument("--manifest", type=Path, default=DEFAULT_BOUNDARY_MANIFEST)
    closure.add_argument("--output")

    delta = subparsers.add_parser("delta")
    delta.add_argument("--before", required=True, type=Path)
    delta.add_argument("--after", required=True, type=Path)
    delta.add_argument("--output", required=True)

    validate = subparsers.add_parser("validate")
    validate.add_argument("--record-kind", required=True, choices=sorted(SCHEMAS))
    validate.add_argument("--input", required=True, type=Path)

    references = subparsers.add_parser("references")
    references.add_argument("--record-kind", required=True, choices=sorted(SCHEMAS))
    references.add_argument("--input", required=True, type=Path)
    references.add_argument("--record-id", action="append", default=[])
    references.add_argument("--output", required=True)

    project = subparsers.add_parser("project")
    project.add_argument("--ledger", required=True, type=Path)
    project.add_argument("--plan", required=True, type=Path)
    project.add_argument("--observations", required=True, type=Path)
    project.add_argument("--output", required=True)

    schemas = subparsers.add_parser("schemas")
    schemas.add_argument("--references-root", type=Path, default=Path(__file__).resolve().parents[1] / "references")
    schemas.add_argument("--write", action="store_true")
    schemas.add_argument("--check", action="store_true")

    rules = subparsers.add_parser("rules")
    rules.add_argument("--skill-root", type=Path, default=Path(__file__).resolve().parents[1])
    rules.add_argument("--manifest", type=Path)
    rules.add_argument("--output", required=True)
    return parser


def main() -> int:
    args = _parser().parse_args()
    try:
        if args.command == "index":
            records = discover_assets(args.repository_root, args.boundary_manifest)
            if args.scope == "paths":
                if not args.path_intent:
                    raise RecordValidationError("--scope paths requires --path-intent")
                records = filter_assets(records, args.path_intent)
            else:
                assert_boundary_closure(args.repository_root, records, args.boundary_manifest)
            write_output(args.output, canonical_jsonl(records))
        elif args.command == "boundaries":
            write_output(
                args.output,
                json.dumps(load_boundary_manifest(args.manifest), ensure_ascii=False, sort_keys=True, indent=2) + "\n",
            )
        elif args.command == "reconstruction-clear-plan":
            records = discover_assets(args.repository_root, args.manifest)
            plan = build_reconstruction_clear_plan(
                args.repository_root,
                args.rollback_commit,
                records,
                args.manifest,
            )
            write_output(args.output, json.dumps(plan, ensure_ascii=False, sort_keys=True, indent=2) + "\n")
            if not plan["ready"]:
                raise RecordValidationError(
                    "reconstruction clear plan is not eligible: "
                    f"dirty={plan['dirty_path_intents']} errors={plan['errors']} "
                    f"head_matches_rollback={plan['head_commit'] == plan['rollback_commit']}"
                )
        elif args.command == "assert-reconstruction-empty":
            clear_plan = json.loads(args.clear_plan.read_text(encoding="utf-8"))
            assert_reconstruction_empty(args.repository_root, args.manifest, clear_plan)
            print("PASS: reconstruction asset boundary is empty")
        elif args.command == "assert-boundary-closure":
            report = assert_boundary_closure(
                args.repository_root,
                load_jsonl(args.ledger, "test_asset"),
                args.manifest,
            )
            if args.output:
                write_output(args.output, json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2) + "\n")
            print(
                f"PASS: {report['asset_count']} assets cover "
                f"{report['fragment_count']} shared-carrier fragments"
            )
        elif args.command == "delta":
            before = load_jsonl(args.before, "test_asset")
            after = load_jsonl(args.after, "test_asset")
            write_output(args.output, canonical_jsonl(build_deltas(before, after)))
        elif args.command == "validate":
            rows = load_jsonl(args.input, args.record_kind)
            if args.input.read_text(encoding="utf-8") != canonical_jsonl(rows):
                raise RecordValidationError(f"{args.input}: JSONL is valid but not canonical")
            print(f"PASS: {len(rows)} canonical {args.record_kind} records")
        elif args.command == "references":
            rows = load_jsonl(args.input, args.record_kind)
            if args.input.read_text(encoding="utf-8") != canonical_jsonl(rows):
                raise RecordValidationError(f"{args.input}: JSONL is valid but not canonical")
            references = record_references(rows, args.record_kind, args.record_id)
            write_output(
                args.output,
                json.dumps(references, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
            )
        elif args.command == "project":
            projection = build_projection(
                load_jsonl(args.ledger, "test_asset"),
                load_jsonl(args.plan, "validation_plan_row"),
                load_jsonl(args.observations, "execution_observation"),
            )
            write_output(args.output, projection_text(projection))
        elif args.command == "schemas":
            if args.write == args.check:
                raise RecordValidationError("select exactly one of --write or --check")
            for kind, filename in SCHEMA_FILENAMES.items():
                path = args.references_root / filename
                expected = schema_text(kind)
                if args.write:
                    path.write_text(expected, encoding="utf-8")
                elif not path.is_file() or path.read_text(encoding="utf-8") != expected:
                    raise RecordValidationError(f"stale generated schema: {path}")
            print(f"PASS: {len(SCHEMA_FILENAMES)} generated schemas")
        elif args.command == "rules":
            manifest = args.manifest or args.skill_root / "references/shared-test-asset-rules.json"
            write_output(
                args.output,
                json.dumps(rule_snapshot(args.skill_root, manifest), sort_keys=True, indent=2) + "\n",
            )
    except (OSError, json.JSONDecodeError, RecordValidationError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
