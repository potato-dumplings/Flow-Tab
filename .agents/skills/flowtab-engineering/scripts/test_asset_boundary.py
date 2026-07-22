#!/usr/bin/env python3
"""FlowTab test-asset boundary, clear-plan, and closure checks."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any, Iterable

from test_asset_model import (
    ASSET_TYPES,
    LAYERS,
    RecordValidationError,
    canonical_json,
    normalize_path_intent,
    sha256_bytes,
)


BOUNDARY_ASSET_TYPES = set(ASSET_TYPES) | {"runner_root", "test_root"}
FRAGMENT_SELECTOR_KINDS = {
    "pbxproj_group_graph",
    "pbxproj_target_graph",
    "swift_package_test_target",
    "xcode_scheme_test_graph",
}
PBX_OBJECT_START_RE = re.compile(
    r"(?m)^\s*([A-F0-9]{24}) /\* (.*?) \*/ = \{"
)
PBX_IDENTIFIER_RE = re.compile(r"\b[A-F0-9]{24}\b")
PBX_OWNED_OBJECT_TYPES = {
    "PBXBuildFile",
    "PBXContainerItemProxy",
    "PBXCopyFilesBuildPhase",
    "PBXFileReference",
    "PBXFrameworksBuildPhase",
    "PBXGroup",
    "PBXResourcesBuildPhase",
    "PBXShellScriptBuildPhase",
    "PBXSourcesBuildPhase",
    "PBXTargetDependency",
    "PBXVariantGroup",
    "XCBuildConfiguration",
    "XCConfigurationList",
}
DEFAULT_BOUNDARY_MANIFEST = (
    Path(__file__).resolve().parents[1] / "references/test-asset-boundaries.json"
)


@dataclass(frozen=True)
class FragmentResolution:
    source_bytes: bytes
    matches: tuple[dict[str, Any], ...]
    owned_identifiers: tuple[str, ...]
    targets: tuple[str, ...]


def _require_string(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value:
        raise RecordValidationError(f"{field} must be a non-empty string")
    return value


def _normalize_layers(value: Any, field: str) -> list[str]:
    if not isinstance(value, list) or any(layer not in LAYERS for layer in value):
        raise RecordValidationError(f"{field} contains unsupported layers")
    return sorted(set(value))


def _normalize_selector(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise RecordValidationError("shared-carrier selector must be an object")
    kind = value.get("kind")
    if kind not in FRAGMENT_SELECTOR_KINDS:
        raise RecordValidationError(f"unsupported shared-carrier selector: {kind!r}")
    if kind in {"pbxproj_group_graph", "pbxproj_target_graph", "swift_package_test_target"}:
        expected_key = "path" if kind == "pbxproj_group_graph" else "target"
        if set(value) != {"kind", expected_key}:
            raise RecordValidationError(f"invalid {kind} selector: {value!r}")
        return {"kind": kind, expected_key: _require_string(value[expected_key], expected_key)}
    if set(value) != {"kind", "targets"}:
        raise RecordValidationError(f"invalid {kind} selector: {value!r}")
    targets = value["targets"]
    if not isinstance(targets, list) or not targets or not all(
        isinstance(target, str) and target for target in targets
    ):
        raise RecordValidationError("xcode_scheme_test_graph targets must be non-empty strings")
    return {"kind": kind, "targets": sorted(set(targets))}


def load_boundary_manifest(path: Path = DEFAULT_BOUNDARY_MANIFEST) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    expected_root_keys = {
        "active_audit_root",
        "asset_boundaries",
        "shared_carriers",
        "transient_reconstruction_root",
    }
    if not isinstance(value, dict) or set(value) != expected_root_keys:
        raise RecordValidationError(f"invalid test-asset boundary manifest: {path}")

    normalized: dict[str, Any] = {
        "active_audit_root": normalize_path_intent(value["active_audit_root"]),
        "asset_boundaries": [],
        "shared_carriers": [],
        "transient_reconstruction_root": normalize_path_intent(
            value["transient_reconstruction_root"]
        ),
    }
    boundary_roles: set[str] = set()
    boundary_paths: set[str] = set()
    required_boundary_keys = {
        "asset_type",
        "layer_capabilities",
        "owner",
        "project_identity",
        "relative_path_intent",
        "role",
        "target",
    }
    for entry in value["asset_boundaries"]:
        if not isinstance(entry, dict) or set(entry) != required_boundary_keys:
            raise RecordValidationError(f"invalid asset boundary entry: {entry!r}")
        role = _require_string(entry["role"], "asset boundary role")
        intent = normalize_path_intent(entry["relative_path_intent"])
        if role in boundary_roles or intent in boundary_paths:
            raise RecordValidationError(f"duplicate asset boundary role or path: {entry!r}")
        if entry["asset_type"] not in BOUNDARY_ASSET_TYPES:
            raise RecordValidationError(f"unsupported boundary asset type: {entry['asset_type']}")
        target = entry["target"]
        project_identity = entry["project_identity"]
        if target is not None and (not isinstance(target, str) or not target):
            raise RecordValidationError(f"invalid boundary target: {entry!r}")
        if project_identity is not None and (
            not isinstance(project_identity, str) or not project_identity
        ):
            raise RecordValidationError(f"invalid boundary project identity: {entry!r}")
        if target is not None and project_identity is None:
            raise RecordValidationError(f"target boundary requires project identity: {entry!r}")
        boundary_roles.add(role)
        boundary_paths.add(intent)
        normalized["asset_boundaries"].append(
            {
                **entry,
                "layer_capabilities": _normalize_layers(
                    entry["layer_capabilities"], f"asset boundary {role}"
                ),
                "relative_path_intent": intent,
            }
        )

    carrier_roles: set[str] = set()
    carrier_paths: set[str] = set()
    fragment_ids: set[str] = set()
    required_carrier_keys = {
        "discovery_kind",
        "interface",
        "layer_capabilities",
        "owner",
        "project_identity",
        "relative_path_intent",
        "role",
        "test_owned_fragments",
    }
    for entry in value["shared_carriers"]:
        if not isinstance(entry, dict) or set(entry) != required_carrier_keys:
            raise RecordValidationError(f"invalid shared carrier entry: {entry!r}")
        role = _require_string(entry["role"], "shared carrier role")
        intent = normalize_path_intent(entry["relative_path_intent"])
        discovery_kind = entry["discovery_kind"]
        if (
            role in carrier_roles
            or intent in carrier_paths
            or discovery_kind not in {"configuration", "runner", "scheme"}
        ):
            raise RecordValidationError(f"duplicate or invalid shared carrier: {entry!r}")
        interface = entry["interface"]
        if discovery_kind == "runner" and (not isinstance(interface, str) or not interface):
            raise RecordValidationError(f"runner carrier requires an interface: {entry!r}")
        if discovery_kind != "runner" and interface is not None:
            raise RecordValidationError(f"non-runner carrier cannot declare an interface: {entry!r}")
        project_identity = entry["project_identity"]
        if not isinstance(project_identity, str) or not project_identity:
            raise RecordValidationError(f"shared carrier requires project identity: {entry!r}")
        fragments = entry["test_owned_fragments"]
        if not isinstance(fragments, list) or not fragments:
            raise RecordValidationError(f"shared carrier requires owned fragments: {entry!r}")
        normalized_fragments: list[dict[str, Any]] = []
        for fragment in fragments:
            if not isinstance(fragment, dict) or set(fragment) != {"fragment_id", "selector"}:
                raise RecordValidationError(f"invalid shared-carrier fragment: {fragment!r}")
            fragment_id = _require_string(fragment["fragment_id"], "fragment_id")
            if fragment_id in fragment_ids:
                raise RecordValidationError(f"duplicate shared-carrier fragment: {fragment_id}")
            fragment_ids.add(fragment_id)
            normalized_fragments.append(
                {"fragment_id": fragment_id, "selector": _normalize_selector(fragment["selector"])}
            )
        carrier_roles.add(role)
        carrier_paths.add(intent)
        normalized["shared_carriers"].append(
            {
                **entry,
                "layer_capabilities": _normalize_layers(
                    entry["layer_capabilities"], f"shared carrier {role}"
                ),
                "relative_path_intent": intent,
                "test_owned_fragments": sorted(
                    normalized_fragments, key=lambda fragment: fragment["fragment_id"]
                ),
            }
        )
    normalized["asset_boundaries"].sort(key=lambda entry: entry["role"])
    normalized["shared_carriers"].sort(key=lambda entry: entry["role"])
    return normalized


def resolve_owned_path(repository_root: Path, intent: str) -> Path:
    root = repository_root.resolve()
    path = (root / normalize_path_intent(intent)).resolve()
    if path != root and root not in path.parents:
        raise RecordValidationError(f"path intent escapes repository boundary: {intent}")
    return path


def _balanced_end(text: str, opening_index: int, opening: str, closing: str) -> int:
    depth = 0
    quote: str | None = None
    escaped = False
    for index in range(opening_index, len(text)):
        character = text[index]
        if quote is not None:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == quote:
                quote = None
            continue
        if character in {'"', "'"}:
            quote = character
        elif character == opening:
            depth += 1
        elif character == closing:
            depth -= 1
            if depth == 0:
                return index + 1
    raise RecordValidationError(f"unbalanced {opening}{closing} fragment")


def _match(text: str, start: int, end: int) -> dict[str, Any]:
    content = text[start:end]
    return {
        "start": start,
        "end": end,
        "start_line": text.count("\n", 0, start) + 1,
        "end_line": text.count("\n", 0, end) + 1,
        "sha256": sha256_bytes(content.encode("utf-8")),
    }


def _pbx_objects(text: str) -> dict[str, dict[str, Any]]:
    objects: dict[str, dict[str, Any]] = {}
    for match in PBX_OBJECT_START_RE.finditer(text):
        opening = text.find("{", match.start(), match.end())
        end = _balanced_end(text, opening, "{", "}")
        while end < len(text) and text[end] in "; \t":
            end += 1
        body = text[match.start():end]
        isa_match = re.search(r"\bisa = ([A-Za-z0-9_]+);", body)
        identifier = match.group(1)
        objects[identifier] = {
            "body": body,
            "comment": match.group(2),
            "end": end,
            "isa": isa_match.group(1) if isa_match else None,
            "start": match.start(),
        }
    return objects


def _pbx_owned_graph(text: str, selector: dict[str, Any]) -> tuple[list[dict[str, Any]], list[str]]:
    objects = _pbx_objects(text)
    kind = selector["kind"]
    target_roots: list[str] = []
    if kind == "pbxproj_target_graph":
        target = re.escape(selector["target"])
        target_roots = [
            identifier
            for identifier, value in objects.items()
            if value["isa"] == "PBXNativeTarget"
            and re.search(rf"(?m)^\s*name = \"?{target}\"?;", value["body"])
        ]
        group_roots = [
            identifier
            for identifier, value in objects.items()
            if value["isa"] == "PBXGroup"
            and (
                value["comment"] == selector["target"]
                or re.search(rf"(?m)^\s*(?:name|path) = \"?{target}\"?;", value["body"])
            )
        ]
    else:
        path = re.escape(selector["path"])
        group_roots = [
            identifier
            for identifier, value in objects.items()
            if value["isa"] == "PBXGroup"
            and re.search(rf"(?m)^\s*(?:name|path) = \"?{path}\"?;", value["body"])
        ]
    roots = sorted(set([*target_roots, *group_roots]))
    if not roots:
        raise RecordValidationError(f"shared-carrier selector did not resolve: {selector!r}")

    group_owned = set(group_roots)
    pending = list(group_roots)
    while pending:
        identifier = pending.pop()
        for reference in PBX_IDENTIFIER_RE.findall(objects[identifier]["body"]):
            candidate = objects.get(reference)
            if candidate is None or reference in group_owned:
                continue
            if candidate["isa"] not in {"PBXFileReference", "PBXGroup", "PBXVariantGroup"}:
                continue
            group_owned.add(reference)
            pending.append(reference)

    product_references = {
        match.group(1)
        for identifier in target_roots
        for match in re.finditer(
            r"\bproductReference = ([A-F0-9]{24})\b",
            objects[identifier]["body"],
        )
    }
    allowed_file_references = group_owned | product_references
    owned = set(target_roots) | group_owned
    pending = list(target_roots)
    while pending:
        identifier = pending.pop()
        for reference in PBX_IDENTIFIER_RE.findall(objects[identifier]["body"]):
            candidate = objects.get(reference)
            if candidate is None or reference in owned:
                continue
            if candidate["isa"] not in PBX_OWNED_OBJECT_TYPES:
                continue
            if candidate["isa"] == "PBXFileReference" and reference not in allowed_file_references:
                continue
            owned.add(reference)
            pending.append(reference)

    changed = True
    while changed:
        changed = False
        for identifier, value in objects.items():
            if identifier in owned or value["isa"] != "PBXBuildFile":
                continue
            if any(reference in owned for reference in PBX_IDENTIFIER_RE.findall(value["body"])):
                owned.add(identifier)
                changed = True

    matches = [
        _match(text, objects[identifier]["start"], objects[identifier]["end"])
        for identifier in sorted(owned, key=lambda item: objects[item]["start"])
    ]
    return matches, sorted(owned)


def resolve_carrier_fragment(text: str, fragment: dict[str, Any]) -> FragmentResolution:
    selector = fragment["selector"]
    kind = selector["kind"]
    matches: list[dict[str, Any]] = []
    identifiers: list[str] = []
    targets: list[str] = []
    if kind == "swift_package_test_target":
        target = selector["target"]
        for candidate in re.finditer(r"\.testTarget\s*\(", text):
            opening = text.find("(", candidate.start(), candidate.end())
            end = _balanced_end(text, opening, "(", ")")
            body = text[candidate.start():end]
            if re.search(rf"\bname\s*:\s*\"{re.escape(target)}\"", body):
                start = candidate.start()
                preceding = start - 1
                while preceding >= 0 and text[preceding].isspace():
                    preceding -= 1
                if preceding >= 0 and text[preceding] == ",":
                    start = preceding
                else:
                    following = end
                    while following < len(text) and text[following].isspace():
                        following += 1
                    if following < len(text) and text[following] == ",":
                        end = following + 1
                matches.append(_match(text, start, end))
        targets = [target]
    elif kind in {"pbxproj_group_graph", "pbxproj_target_graph"}:
        matches, identifiers = _pbx_owned_graph(text, selector)
        if kind == "pbxproj_target_graph":
            targets = [selector["target"]]
    else:
        targets = selector["targets"]
        spans: set[tuple[int, int]] = set()
        for match in re.finditer(r"<TestAction\b[\s\S]*?</TestAction>", text):
            if any(
                re.search(rf'BlueprintName\s*=\s*"{re.escape(target)}"', match.group(0))
                for target in targets
            ):
                spans.add((match.start(), match.end()))
        for match in re.finditer(r"<BuildActionEntry\b[\s\S]*?</BuildActionEntry>", text):
            body = match.group(0)
            if any(
                re.search(rf'BlueprintName\s*=\s*"{re.escape(target)}"', body)
                for target in targets
            ):
                spans.add((match.start(), match.end()))
        matches = [_match(text, start, end) for start, end in sorted(spans)]
        identifiers = sorted(
            set(
                identifier
                for match in matches
                for identifier in PBX_IDENTIFIER_RE.findall(text[match["start"]:match["end"]])
            )
        )

    if not matches:
        raise RecordValidationError(f"shared-carrier selector did not resolve: {selector!r}")
    source = "".join(text[match["start"]:match["end"]] for match in matches).encode("utf-8")
    return FragmentResolution(
        source_bytes=source,
        matches=tuple(matches),
        owned_identifiers=tuple(identifiers),
        targets=tuple(sorted(set(targets))),
    )


def clear_planned_carrier_text(
    text: str,
    matches: Iterable[dict[str, Any]],
    owned_identifiers: Iterable[str],
) -> str:
    intervals = sorted({(match["start"], match["end"]) for match in matches})
    merged: list[list[int]] = []
    for start, end in intervals:
        if not merged or start > merged[-1][1]:
            merged.append([start, end])
        else:
            merged[-1][1] = max(merged[-1][1], end)
    residual = text
    for start, end in reversed(merged):
        residual = residual[:start] + residual[end:]
    identifiers = set(owned_identifiers)
    return "".join(
        line
        for line in residual.splitlines(keepends=True)
        if not any(identifier in line for identifier in identifiers)
    )


def canonical_carrier_sha256(text: str) -> str:
    normalized = "\n".join(
        line.rstrip() for line in text.splitlines() if line.strip()
    )
    if normalized:
        normalized += "\n"
    return sha256_bytes(normalized.encode("utf-8"))


def fragment_record_specs(
    carrier: dict[str, Any], fragment: dict[str, Any], resolution: FragmentResolution
) -> list[dict[str, Any]]:
    selector = fragment["selector"]
    kind = selector["kind"]
    if kind == "swift_package_test_target":
        target = selector["target"]
        return [
            {"asset_type": "runner", "declared_name": carrier["interface"], "target": target},
            {"asset_type": "target", "declared_name": target, "target": target},
        ]
    if kind == "pbxproj_target_graph":
        target = selector["target"]
        return [
            {
                "asset_type": "configuration",
                "declared_name": f"{target}.build-configurations",
                "target": target,
            },
            {"asset_type": "target", "declared_name": target, "target": target},
        ]
    if kind == "pbxproj_group_graph":
        return [
            {
                "asset_type": "configuration",
                "declared_name": f"{selector['path']}.project-fragment",
                "target": None,
            }
        ]
    return [
        {
            "asset_type": "scheme",
            "declared_name": PurePosixPath(carrier["relative_path_intent"]).stem,
            "target": None,
        }
    ]


def _files_below(path: Path) -> list[Path]:
    if path.is_file():
        if path.is_symlink():
            raise RecordValidationError(f"asset boundary contains a symlink: {path}")
        return [path]
    if not path.is_dir():
        return []
    files = [
        candidate
        for candidate in sorted(path.rglob("*"))
        if candidate.is_file()
        and not any(part.startswith(".") for part in candidate.relative_to(path).parts)
    ]
    symlinks = [candidate for candidate in files if candidate.is_symlink()]
    if symlinks:
        raise RecordValidationError(f"asset boundary contains symlinks: {symlinks}")
    return files


def path_inventory(repository_root: Path, intent: str) -> dict[str, Any]:
    path = resolve_owned_path(repository_root, intent)
    files = _files_below(path)
    items = [
        {
            "relative_path_intent": candidate.relative_to(repository_root).as_posix(),
            "sha256": sha256_bytes(candidate.read_bytes()),
        }
        for candidate in files
    ]
    return {
        "exists": path.exists(),
        "file_count": len(items),
        "sha256": sha256_bytes(canonical_json(items).encode("utf-8")) if items else None,
    }


def boundary_closure_report(
    repository_root: Path,
    records: Iterable[dict[str, Any]],
    manifest_path: Path = DEFAULT_BOUNDARY_MANIFEST,
) -> dict[str, Any]:
    repository_root = repository_root.resolve()
    manifest = load_boundary_manifest(manifest_path)
    rows = list(records)
    record_paths = {
        row["asset_locator"]["relative_path_intent"]
        for row in rows
        if row.get("record_kind") == "test_asset"
    }
    boundary_paths = [entry["relative_path_intent"] for entry in manifest["asset_boundaries"]]
    carrier_paths = {entry["relative_path_intent"] for entry in manifest["shared_carriers"]}
    errors: list[str] = []
    asset_ids = {row["asset_id"] for row in rows}

    for row in rows:
        intent = row["asset_locator"]["relative_path_intent"]
        parts = PurePosixPath(intent).parts
        within_boundary = any(
            parts[: len(PurePosixPath(boundary).parts)] == PurePosixPath(boundary).parts
            for boundary in boundary_paths
        )
        if not within_boundary and intent not in carrier_paths:
            errors.append(f"asset is outside the replacement boundary: {row['asset_id']}: {intent}")
        missing_dependencies = sorted(set(row["dependencies"]) - asset_ids)
        if missing_dependencies:
            errors.append(
                f"asset has unresolved dependencies: {row['asset_id']}: {missing_dependencies}"
            )

    expected_types = {
        "capability_probe": {"capability_probe"},
        "fixture": {"fixture"},
        "pressure_scenario": {"pressure_scenario"},
        "runner": {"runner"},
        "runner_root": {"runner"},
        "scheme": {"scheme"},
        "test_root": {"test_file"},
        "testing_support": {"testing_support"},
    }
    for entry in manifest["asset_boundaries"]:
        intent = entry["relative_path_intent"]
        path = resolve_owned_path(repository_root, intent)
        files = _files_below(path)
        if not files:
            errors.append(f"asset boundary has no discoverable files: {entry['role']}: {intent}")
            continue
        for file in files:
            file_intent = file.relative_to(repository_root).as_posix()
            if file_intent not in record_paths:
                errors.append(f"asset-boundary file is not indexed: {file_intent}")
        types = expected_types.get(entry["asset_type"], {entry["asset_type"]})
        if not any(
            row["asset_type"] in types
            and (
                row["asset_locator"]["relative_path_intent"] == intent
                or row["asset_locator"]["relative_path_intent"].startswith(f"{intent}/")
            )
            for row in rows
        ):
            errors.append(f"asset boundary has no matching record: {entry['role']}: {intent}")

    fragment_count = 0
    for carrier in manifest["shared_carriers"]:
        intent = carrier["relative_path_intent"]
        path = resolve_owned_path(repository_root, intent)
        if not path.is_file():
            errors.append(f"shared carrier is unavailable: {intent}")
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for fragment in carrier["test_owned_fragments"]:
            fragment_count += 1
            try:
                resolution = resolve_carrier_fragment(text, fragment)
            except RecordValidationError as error:
                errors.append(f"{intent}:{fragment['fragment_id']}: {error}")
                continue
            for spec in fragment_record_specs(carrier, fragment, resolution):
                if not any(
                    row["asset_type"] == spec["asset_type"]
                    and row["asset_locator"]["relative_path_intent"] == intent
                    and row["asset_locator"]["declared_name"] == spec["declared_name"]
                    for row in rows
                ):
                    errors.append(
                        f"shared-carrier fragment has no {spec['asset_type']} record: "
                        f"{fragment['fragment_id']}"
                    )
    return {
        "asset_count": len(rows),
        "boundary_manifest_sha256": sha256_bytes(manifest_path.read_bytes()),
        "errors": sorted(set(errors)),
        "fragment_count": fragment_count,
        "record_kind": "test_asset_boundary_closure",
    }


def assert_boundary_closure(
    repository_root: Path,
    records: Iterable[dict[str, Any]],
    manifest_path: Path = DEFAULT_BOUNDARY_MANIFEST,
) -> dict[str, Any]:
    report = boundary_closure_report(repository_root, records, manifest_path)
    if report["errors"]:
        raise RecordValidationError("; ".join(report["errors"]))
    return report


def assert_reconstruction_empty(
    repository_root: Path,
    manifest_path: Path = DEFAULT_BOUNDARY_MANIFEST,
    clear_plan: dict[str, Any] | None = None,
) -> None:
    repository_root = repository_root.resolve()
    manifest = load_boundary_manifest(manifest_path)
    errors: list[str] = []
    for entry in manifest["asset_boundaries"]:
        intent = entry["relative_path_intent"]
        if _files_below(resolve_owned_path(repository_root, intent)):
            errors.append(f"asset boundary is not empty: {intent}")

    active_root = manifest["active_audit_root"]
    if _files_below(resolve_owned_path(repository_root, active_root)):
        errors.append(f"reconstruction output boundary is not empty: {active_root}")

    expected_plan_sha = sha256_bytes(manifest_path.read_bytes())
    planned_identifiers: dict[str, set[str]] = {}
    planned_carriers: dict[str, dict[str, Any]] = {}
    if clear_plan is not None:
        if clear_plan.get("record_kind") != "reconstruction_clear_plan":
            errors.append("clear plan has an unsupported record kind")
        if not clear_plan.get("ready"):
            errors.append("clear plan did not pass its pre-clear safety gate")
        if clear_plan.get("boundary_manifest_sha256") != expected_plan_sha:
            errors.append("clear plan uses a different boundary manifest")
        for carrier in clear_plan.get("shared_carrier_entries", []):
            planned_carriers[carrier["relative_path_intent"]] = carrier
            planned_identifiers.setdefault(carrier["relative_path_intent"], set()).update(
                identifier
                for fragment in carrier.get("fragments", [])
                for identifier in fragment.get("owned_identifiers", [])
            )

    for carrier in manifest["shared_carriers"]:
        intent = carrier["relative_path_intent"]
        path = resolve_owned_path(repository_root, intent)
        if not path.is_file():
            errors.append(f"shared carrier is unavailable after clearing: {intent}")
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        planned_carrier = planned_carriers.get(intent)
        if clear_plan is not None and planned_carrier is None:
            errors.append(f"clear plan omits shared carrier: {intent}")
        for fragment in carrier["test_owned_fragments"]:
            try:
                resolve_carrier_fragment(text, fragment)
            except RecordValidationError as error:
                if "selector did not resolve" not in str(error):
                    errors.append(
                        f"shared carrier cannot be verified after clearing: "
                        f"{intent}:{fragment['fragment_id']}: {error}"
                    )
            else:
                errors.append(
                    f"shared carrier retains test-owned fragment: {intent}:{fragment['fragment_id']}"
                )
        remaining = sorted(
            identifier for identifier in planned_identifiers.get(intent, set()) if identifier in text
        )
        if remaining:
            errors.append(f"shared carrier retains planned object identifiers: {intent}: {remaining}")
        if planned_carrier is not None and canonical_carrier_sha256(text) != planned_carrier.get(
            "production_residual_sha256"
        ):
            errors.append(f"shared carrier production residual changed while clearing: {intent}")

    transient_root = resolve_owned_path(repository_root, manifest["transient_reconstruction_root"])
    transient_files = _files_below(transient_root)
    if clear_plan is None and transient_files:
        errors.append(
            f"reconstruction output boundary is not empty: {manifest['transient_reconstruction_root']}"
        )
    if clear_plan is not None:
        expected_plan_path = transient_root / "RECONSTRUCTION_CLEAR_PLAN.json"
        if transient_files != [expected_plan_path]:
            errors.append(
                "transient reconstruction root contains pre-plan outputs: "
                + ", ".join(path.relative_to(repository_root).as_posix() for path in transient_files)
            )
        elif json.loads(expected_plan_path.read_text(encoding="utf-8")) != clear_plan:
            errors.append("retained reconstruction clear plan differs from the validated plan")
    if errors:
        raise RecordValidationError("; ".join(errors))
