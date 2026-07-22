#!/usr/bin/env python3
"""Generate a deterministic, safety-qualified reconstruction clear plan."""

from __future__ import annotations

import subprocess
from pathlib import Path
from typing import Any, Iterable

from test_asset_boundary import (
    DEFAULT_BOUNDARY_MANIFEST,
    boundary_closure_report,
    canonical_carrier_sha256,
    clear_planned_carrier_text,
    load_boundary_manifest,
    path_inventory,
    resolve_carrier_fragment,
    resolve_owned_path,
)
from test_asset_model import RecordValidationError, normalize_path_intent, sha256_bytes


def _git(repository_root: Path, arguments: list[str]) -> str:
    result = subprocess.run(
        ["git", *arguments],
        cwd=repository_root,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        message = result.stderr.strip() or result.stdout.strip()
        raise RecordValidationError(f"git {' '.join(arguments)} failed: {message}")
    return result.stdout.rstrip()


def build_reconstruction_clear_plan(
    repository_root: Path,
    rollback_ref: str,
    records: Iterable[dict[str, Any]],
    manifest_path: Path = DEFAULT_BOUNDARY_MANIFEST,
) -> dict[str, Any]:
    repository_root = repository_root.resolve()
    manifest = load_boundary_manifest(manifest_path)
    rollback_commit = _git(
        repository_root, ["rev-parse", "--verify", f"{rollback_ref}^{{commit}}"]
    )
    head_commit = _git(repository_root, ["rev-parse", "--verify", "HEAD^{commit}"])
    stage_paths = [
        *(entry["relative_path_intent"] for entry in manifest["asset_boundaries"]),
        *(entry["relative_path_intent"] for entry in manifest["shared_carriers"]),
        manifest["active_audit_root"],
    ]
    status = _git(repository_root, ["status", "--porcelain=v1", "--", *stage_paths])
    dirty = sorted(
        normalize_path_intent(line[3:].split(" -> ")[-1])
        for line in status.splitlines()
        if len(line) >= 4
    )
    closure = boundary_closure_report(repository_root, records, manifest_path)
    boundary_entries = [
        {
            "asset_type": entry["asset_type"],
            "owner": entry["owner"],
            "relative_path_intent": entry["relative_path_intent"],
            "role": entry["role"],
            **path_inventory(repository_root, entry["relative_path_intent"]),
        }
        for entry in manifest["asset_boundaries"]
    ]
    carrier_entries: list[dict[str, Any]] = []
    fragment_errors: list[str] = []
    for carrier in manifest["shared_carriers"]:
        intent = carrier["relative_path_intent"]
        path = resolve_owned_path(repository_root, intent)
        fragments: list[dict[str, Any]] = []
        production_residual_sha256: str | None = None
        if not path.is_file():
            fragment_errors.append(f"shared carrier is unavailable: {intent}")
            carrier_sha = None
        else:
            source = path.read_bytes()
            carrier_sha = sha256_bytes(source)
            text = source.decode("utf-8", errors="replace")
            for fragment in carrier["test_owned_fragments"]:
                try:
                    resolution = resolve_carrier_fragment(text, fragment)
                except RecordValidationError as error:
                    fragment_errors.append(f"{intent}:{fragment['fragment_id']}: {error}")
                    continue
                fragments.append(
                    {
                        "fragment_id": fragment["fragment_id"],
                        "matches": list(resolution.matches),
                        "owned_identifiers": list(resolution.owned_identifiers),
                        "selector": fragment["selector"],
                        "sha256": sha256_bytes(resolution.source_bytes),
                    }
                )
            all_matches = [
                match for fragment in fragments for match in fragment["matches"]
            ]
            all_identifiers = [
                identifier
                for fragment in fragments
                for identifier in fragment["owned_identifiers"]
            ]
            production_residual_sha256 = canonical_carrier_sha256(
                clear_planned_carrier_text(text, all_matches, all_identifiers)
            )
        carrier_entries.append(
            {
                "fragments": fragments,
                "owner": carrier["owner"],
                "relative_path_intent": intent,
                "role": carrier["role"],
                "production_residual_sha256": production_residual_sha256,
                "sha256": carrier_sha,
            }
        )
    errors = sorted(set([*closure["errors"], *fragment_errors]))
    ready = rollback_commit == head_commit and not dirty and not errors
    return {
        "asset_entries": boundary_entries,
        "boundary_closure": closure,
        "boundary_manifest_sha256": sha256_bytes(manifest_path.read_bytes()),
        "dirty_path_intents": dirty,
        "errors": errors,
        "head_commit": head_commit,
        "ready": ready,
        "record_kind": "reconstruction_clear_plan",
        "rollback_commit": rollback_commit,
        "shared_carrier_entries": carrier_entries,
    }
