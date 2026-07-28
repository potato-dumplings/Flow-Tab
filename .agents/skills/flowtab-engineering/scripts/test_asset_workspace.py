#!/usr/bin/env python3
"""Run full validation with one transient repository-local test-asset workspace."""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Sequence


WORKSPACE_INTENT = Path(".build-local/test-assets")
LOCK_INTENT = Path(".build-local/.test-assets.lock")
MARKER_NAME = ".active-run.json"
RUN_ID_RE = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9._-]{0,127})$")


class WorkspaceError(RuntimeError):
    """Raised when the transient workspace cannot be owned safely."""


def _repository_root(path: Path) -> Path:
    root = path.resolve()
    if not root.is_dir():
        raise WorkspaceError(f"Repository root is not a directory: {root}")
    return root


def _resolve_owned_path(repository_root: Path, intent: Path) -> Path:
    current = repository_root
    for component in intent.parts:
        current = current / component
        if current.is_symlink():
            raise WorkspaceError(
                f"Transient test-asset path must not traverse a symlink: {current}"
            )
    resolved = current.resolve(strict=False)
    try:
        resolved.relative_to(repository_root)
    except ValueError as error:
        raise WorkspaceError(
            f"Transient test-asset path escapes the repository: {resolved}"
        ) from error
    return resolved


def _remove_workspace(workspace: Path) -> None:
    if workspace.is_symlink():
        raise WorkspaceError(
            f"Transient test-asset workspace must not be a symlink: {workspace}"
        )
    if not workspace.exists():
        return
    if not workspace.is_dir():
        raise WorkspaceError(
            f"Transient test-asset workspace is not a directory: {workspace}"
        )
    shutil.rmtree(workspace)


def _write_marker(workspace: Path, run_id: str) -> None:
    marker = {
        "schema_version": 1,
        "run_id": run_id,
        "resource_boundary": "repository_root",
        "relative_path_intent": WORKSPACE_INTENT.as_posix(),
    }
    marker_path = workspace / MARKER_NAME
    temporary_path = workspace / f"{MARKER_NAME}.tmp"
    temporary_path.write_text(
        json.dumps(marker, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    temporary_path.replace(marker_path)


def run_full_validation(
    repository_root: Path,
    run_id: str,
    command: Sequence[str],
) -> int:
    """Run one full-validation command and remove its generated asset workspace."""

    root = _repository_root(repository_root)
    if not RUN_ID_RE.fullmatch(run_id):
        raise WorkspaceError(
            "Run ID must use 1-128 letters, digits, dots, underscores, or hyphens"
        )
    if not command:
        raise WorkspaceError("A full-validation command is required after --")

    build_local = _resolve_owned_path(root, Path(".build-local"))
    workspace = _resolve_owned_path(root, WORKSPACE_INTENT)
    lock_path = _resolve_owned_path(root, LOCK_INTENT)
    build_local.mkdir(parents=True, exist_ok=True)

    with lock_path.open("a+", encoding="utf-8") as lock_file:
        try:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise WorkspaceError(
                "Another full validation owns the transient test-asset workspace"
            ) from error

        _remove_workspace(workspace)
        workspace.mkdir()
        try:
            _write_marker(workspace, run_id)
            environment = os.environ.copy()
            environment["FLOWTAB_TEST_ASSET_ROOT"] = str(workspace)
            environment["FLOWTAB_TEST_ASSET_PATH_INTENT"] = WORKSPACE_INTENT.as_posix()
            completed = subprocess.run(
                list(command),
                cwd=root,
                env=environment,
                check=False,
            )
            return completed.returncode
        finally:
            _remove_workspace(workspace)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Run a full-validation command with a fresh .build-local/test-assets "
            "workspace that is removed at terminal exit."
        )
    )
    parser.add_argument("--repository-root", type=Path, default=Path.cwd())
    parser.add_argument("--run-id", required=True)
    parser.add_argument(
        "command",
        nargs=argparse.REMAINDER,
        help="Full-validation command, preceded by --",
    )
    args = parser.parse_args()

    command = args.command
    if command[:1] == ["--"]:
        command = command[1:]
    try:
        return run_full_validation(args.repository_root, args.run_id, command)
    except KeyboardInterrupt:
        return 130
    except (OSError, WorkspaceError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
