#!/usr/bin/env python3
"""Guard existing FlowTab test semantics while allowing additive test coverage."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Dict, Iterable, List, Mapping, Optional, Sequence, Tuple


SCHEMA_VERSION = 1
STATE_PATH = Path(".build-local/codex/test-semantic-guard")
TEST_PREFIXES = ("FlowTabTests/", "FlowTabUITests/", "FlowTabCore/Tests/")


class GuardError(RuntimeError):
    pass


@dataclass(frozen=True)
class PatchEntry:
    action: str
    source: str
    destination: Optional[str] = None


@dataclass(frozen=True)
class FunctionRecord:
    name: str
    fingerprint: str
    start: int
    end: int


@dataclass(frozen=True)
class PatchAnalysis:
    changes: Mapping[str, Sequence[str]]
    head_contents: Mapping[str, Optional[str]]
    expected_contents: Mapping[str, Optional[str]]


def _run(
    argv: Sequence[str],
    *,
    cwd: Path,
    input_text: Optional[str] = None,
    check: bool = True,
) -> subprocess.CompletedProcess:
    completed = subprocess.run(
        list(argv),
        cwd=str(cwd),
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if check and completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip()
        raise GuardError("command failed: {}: {}".format(" ".join(argv), detail))
    return completed


def _git(repo: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess:
    return _run(("git",) + args, cwd=repo, check=check)


def _sha256(content: Optional[str]) -> Optional[str]:
    if content is None:
        return None
    return hashlib.sha256(content.encode("utf-8")).hexdigest()


def _repo_root(cwd: Path) -> Path:
    return Path(_run(("git", "rev-parse", "--show-toplevel"), cwd=cwd).stdout.strip())


def _repo_relative(repo: Path, cwd: Path, raw_path: str) -> str:
    candidate = PurePosixPath(raw_path)
    if candidate.is_absolute() or ".." in candidate.parts:
        raise GuardError("unsafe patch path: {}".format(raw_path))
    resolved = (cwd / Path(*candidate.parts)).resolve()
    try:
        return resolved.relative_to(repo.resolve()).as_posix()
    except ValueError as error:
        raise GuardError("patch path leaves repository: {}".format(raw_path)) from error


def _is_test_source(path: str) -> bool:
    return path.endswith(".swift") and path.startswith(TEST_PREFIXES)


def _extract_patch_entries(patch: str) -> List[PatchEntry]:
    entries: List[PatchEntry] = []
    for line in patch.splitlines():
        matched = re.match(r"^\*\*\* (Add|Update|Delete) File: (.+)$", line)
        if matched:
            entries.append(PatchEntry(matched.group(1).lower(), matched.group(2)))
            continue
        moved = re.match(r"^\*\*\* Move to: (.+)$", line)
        if moved and entries:
            prior = entries[-1]
            entries[-1] = PatchEntry(prior.action, prior.source, moved.group(1))
    return entries


def _head_content(repo: Path, path: str) -> Optional[str]:
    result = _git(repo, "show", "HEAD:{}".format(path), check=False)
    return result.stdout if result.returncode == 0 else None


def _index_content(repo: Path, path: str) -> Optional[str]:
    result = _git(repo, "show", ":{}".format(path), check=False)
    return result.stdout if result.returncode == 0 else None


def _worktree_content(repo: Path, path: str) -> Optional[str]:
    target = repo / path
    return target.read_text(encoding="utf-8") if target.is_file() else None


def _mask_comments_and_strings(source: str) -> str:
    chars = list(source)
    index = 0
    block_depth = 0
    quote = ""
    while index < len(chars):
        pair = source[index : index + 2]
        triple = source[index : index + 3]
        if block_depth:
            if pair == "/*":
                block_depth += 1
                chars[index : index + 2] = "  "
                index += 2
            elif pair == "*/":
                block_depth -= 1
                chars[index : index + 2] = "  "
                index += 2
            else:
                if chars[index] != "\n":
                    chars[index] = " "
                index += 1
            continue
        if quote:
            marker = triple if quote == '"""' else source[index]
            if marker == quote and (quote == '"""' or source[index - 1 : index] != "\\"):
                width = len(quote)
                chars[index : index + width] = " " * width
                index += width
                quote = ""
            else:
                if chars[index] != "\n":
                    chars[index] = " "
                index += 1
            continue
        if pair == "//":
            end = source.find("\n", index)
            end = len(source) if end < 0 else end
            chars[index:end] = " " * (end - index)
            index = end
        elif pair == "/*":
            block_depth = 1
            chars[index : index + 2] = "  "
            index += 2
        elif triple == '"""':
            quote = '"""'
            chars[index : index + 3] = "   "
            index += 3
        elif source[index] == '"':
            quote = '"'
            chars[index] = " "
            index += 1
        else:
            index += 1
    return "".join(chars)


def _strip_comments(source: str) -> str:
    result: List[str] = []
    index = 0
    block_depth = 0
    quote = ""
    while index < len(source):
        pair = source[index : index + 2]
        triple = source[index : index + 3]
        if block_depth:
            if pair == "/*":
                block_depth += 1
                index += 2
            elif pair == "*/":
                block_depth -= 1
                index += 2
            else:
                result.append("\n" if source[index] == "\n" else " ")
                index += 1
            continue
        if quote:
            if quote == '"""' and triple == '"""':
                result.append(triple)
                index += 3
                quote = ""
            else:
                char = source[index]
                result.append(char)
                if quote == '"' and char == '"' and source[index - 1 : index] != "\\":
                    quote = ""
                index += 1
            continue
        if pair == "//":
            end = source.find("\n", index)
            index = len(source) if end < 0 else end
        elif pair == "/*":
            block_depth = 1
            index += 2
        elif triple == '"""':
            quote = '"""'
            result.append(triple)
            index += 3
        elif source[index] == '"':
            quote = '"'
            result.append('"')
            index += 1
        else:
            result.append(source[index])
            index += 1
    return "".join(result)


def _semantic_tokens(source: str) -> List[str]:
    without_comments = _strip_comments(source)
    return re.findall(
        r'[A-Za-z_][A-Za-z0-9_]*|\d+(?:\.\d+)?|"(?:\\.|[^"\\])*"|[^\s]',
        without_comments,
    )


def _function_records(source: str) -> List[FunctionRecord]:
    masked = _mask_comments_and_strings(source)
    records: List[FunctionRecord] = []
    pattern = re.compile(r"\bfunc\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:<[^{}()]*>)?\s*\(")
    for matched in pattern.finditer(masked):
        opening = masked.find("{", matched.end())
        if opening < 0:
            continue
        depth = 0
        closing = -1
        for index in range(opening, len(masked)):
            if masked[index] == "{":
                depth += 1
            elif masked[index] == "}":
                depth -= 1
                if depth == 0:
                    closing = index + 1
                    break
        if closing < 0:
            continue
        start = source.rfind("\n", 0, matched.start()) + 1
        while start > 0:
            prior_end = start - 1
            prior_start = source.rfind("\n", 0, prior_end) + 1
            prior = source[prior_start:prior_end].strip()
            if not prior.startswith("@"):
                break
            start = prior_start
        fingerprint = "\x1f".join(_semantic_tokens(source[start:closing]))
        records.append(FunctionRecord(matched.group(1), fingerprint, start, closing))
    return records


def _outside_function_tokens(source: str, records: Sequence[FunctionRecord]) -> List[str]:
    pieces: List[str] = []
    cursor = 0
    for record in sorted(records, key=lambda value: value.start):
        pieces.append(source[cursor : record.start])
        cursor = max(cursor, record.end)
    pieces.append(source[cursor:])
    return _semantic_tokens("".join(pieces))


def _only_additions(before: Sequence[str], after: Sequence[str]) -> bool:
    cursor = 0
    for token in after:
        if cursor < len(before) and token == before[cursor]:
            cursor += 1
    return cursor == len(before)


def semantic_changes(before: Optional[str], after: Optional[str]) -> List[str]:
    if before is None:
        return []
    if after is None:
        return ["<file>"]
    before_records = _function_records(before)
    after_records = _function_records(after)
    available = Counter(record.fingerprint for record in after_records)
    changed: List[str] = []
    for record in before_records:
        if available[record.fingerprint]:
            available[record.fingerprint] -= 1
        else:
            changed.append(record.name)
    before_outside = _outside_function_tokens(before, before_records)
    after_outside = _outside_function_tokens(after, after_records)
    if not _only_additions(before_outside, after_outside):
        changed.append("<file-scope>")
    return sorted(set(changed))


def _simulate_patch(repo: Path, cwd: Path, patch: str) -> Mapping[str, Optional[str]]:
    entries = _extract_patch_entries(patch)
    raw_paths = {entry.source for entry in entries}
    raw_paths.update(entry.destination for entry in entries if entry.destination)
    resolved = {raw: _repo_relative(repo, cwd, raw) for raw in raw_paths}
    if not any(_is_test_source(path) for path in resolved.values()):
        return {}
    executable = shutil.which("apply_patch")
    if not executable:
        raise GuardError("apply_patch executable is unavailable to the project hook")
    with tempfile.TemporaryDirectory(prefix="flowtab-test-guard-") as directory:
        temporary_repo = Path(directory)
        temporary_cwd = temporary_repo / cwd.resolve().relative_to(repo.resolve())
        temporary_cwd.mkdir(parents=True, exist_ok=True)
        for entry in entries:
            source = resolved[entry.source]
            target = temporary_repo / source
            if entry.action in ("update", "delete"):
                original = repo / source
                if not original.is_file():
                    raise GuardError("patch source is unavailable: {}".format(source))
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(str(original), str(target))
            if entry.destination:
                (temporary_repo / resolved[entry.destination]).parent.mkdir(
                    parents=True, exist_ok=True
                )
            elif entry.action == "add":
                target.parent.mkdir(parents=True, exist_ok=True)
        completed = _run((executable,), cwd=temporary_cwd, input_text=patch, check=False)
        if completed.returncode != 0:
            detail = completed.stderr.strip() or completed.stdout.strip()
            raise GuardError("candidate patch could not be analyzed: {}".format(detail))
        result: Dict[str, Optional[str]] = {}
        for path in resolved.values():
            if not _is_test_source(path):
                continue
            candidate = temporary_repo / path
            result[path] = candidate.read_text(encoding="utf-8") if candidate.is_file() else None
        return result


def analyze_patch(repo: Path, cwd: Path, patch: str) -> PatchAnalysis:
    expected = _simulate_patch(repo, cwd, patch)
    changes: Dict[str, Sequence[str]] = {}
    heads: Dict[str, Optional[str]] = {}
    for path, content in expected.items():
        head = _head_content(repo, path)
        heads[path] = head
        symbols = semantic_changes(head, content)
        if symbols:
            changes[path] = symbols
    return PatchAnalysis(changes, heads, expected)


def _state_root(repo: Path) -> Path:
    return repo / STATE_PATH


def _record_token(analysis: PatchAnalysis) -> str:
    payload = {
        "changes": analysis.changes,
        "head_hashes": {path: _sha256(value) for path, value in analysis.head_contents.items()},
        "expected_hashes": {
            path: _sha256(value) for path, value in analysis.expected_contents.items()
        },
    }
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()[:16]


def _write_pending(repo: Path, analysis: PatchAnalysis, session_id: str) -> str:
    token = _record_token(analysis)
    pending = _state_root(repo) / "pending"
    pending.mkdir(parents=True, exist_ok=True)
    record = {
        "schema_version": SCHEMA_VERSION,
        "token": token,
        "session_id": session_id,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "head_commit": _git(repo, "rev-parse", "HEAD").stdout.strip(),
        "changes": analysis.changes,
        "head_hashes": {path: _sha256(value) for path, value in analysis.head_contents.items()},
        "expected_hashes": {
            path: _sha256(value) for path, value in analysis.expected_contents.items()
        },
        "expected_contents": analysis.expected_contents,
    }
    (pending / "{}.json".format(token)).write_text(
        json.dumps(record, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return token


def _authorization_records(repo: Path) -> Iterable[Mapping[str, object]]:
    directory = _state_root(repo) / "authorized"
    if not directory.is_dir():
        return ()
    records: List[Mapping[str, object]] = []
    for path in sorted(directory.glob("*.json")):
        try:
            records.append(json.loads(path.read_text(encoding="utf-8")))
        except (OSError, ValueError):
            continue
    return records


def _record_covers(
    repo: Path,
    record: Mapping[str, object],
    path: str,
    expected: Optional[str],
) -> bool:
    if record.get("head_commit") != _git(repo, "rev-parse", "HEAD").stdout.strip():
        return False
    changes = record.get("changes")
    contents = record.get("expected_contents")
    head_hashes = record.get("head_hashes")
    if not isinstance(changes, dict) or path not in changes:
        return False
    if not isinstance(contents, dict) or path not in contents:
        return False
    if not isinstance(head_hashes, dict):
        return False
    head = _head_content(repo, path)
    if head_hashes.get(path) != _sha256(head):
        return False
    authorized = contents.get(path)
    if authorized is not None and not isinstance(authorized, str):
        return False
    return not semantic_changes(authorized, expected)


def _uncovered(
    repo: Path,
    changes: Mapping[str, Sequence[str]],
    expected: Mapping[str, Optional[str]],
) -> Mapping[str, Sequence[str]]:
    records = tuple(_authorization_records(repo))
    return {
        path: symbols
        for path, symbols in changes.items()
        if not any(_record_covers(repo, record, path, expected.get(path)) for record in records)
    }


def _staged_analysis(repo: Path, include_worktree: bool) -> PatchAnalysis:
    staged = _git(repo, "diff", "--cached", "--name-only", "--no-renames", "-z").stdout
    paths = {path for path in staged.split("\0") if path and _is_test_source(path)}
    if include_worktree:
        dirty = _git(repo, "diff", "--name-only", "--no-renames", "-z").stdout
        paths.update(path for path in dirty.split("\0") if path and _is_test_source(path))
    changes: Dict[str, Sequence[str]] = {}
    heads: Dict[str, Optional[str]] = {}
    expected: Dict[str, Optional[str]] = {}
    for path in sorted(paths):
        head = _head_content(repo, path)
        candidate = _worktree_content(repo, path) if include_worktree else _index_content(repo, path)
        heads[path] = head
        expected[path] = candidate
        symbols = semantic_changes(head, candidate)
        if symbols:
            changes[path] = symbols
    return PatchAnalysis(changes, heads, expected)


def _is_git_commit(command: str) -> bool:
    return re.search(r"(?m)(?:^|[;&|]\s*|\n)\s*git\b[^\n;&|]*\bcommit\b", command) is not None


def _commit_includes_worktree(command: str) -> bool:
    return re.search(r"(?:^|\s)(?:-a|--all)(?:\s|$)", command) is not None


def _format_changes(changes: Mapping[str, Sequence[str]]) -> str:
    return "; ".join(
        "{}: {}".format(path, ", ".join(symbols))
        for path, symbols in sorted(changes.items())
    )


def _deny(reason: str) -> None:
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": reason,
                }
            },
            ensure_ascii=False,
        )
    )


def _handle_hook() -> int:
    payload = json.load(sys.stdin)
    cwd = Path(payload.get("cwd") or os.getcwd()).resolve()
    repo = _repo_root(cwd)
    tool_name = payload.get("tool_name")
    tool_input = payload.get("tool_input") or {}
    command = tool_input.get("command", "") if isinstance(tool_input, dict) else ""
    try:
        if tool_name == "apply_patch":
            analysis = analyze_patch(repo, cwd, command)
            uncovered = _uncovered(repo, analysis.changes, analysis.expected_contents)
            if uncovered:
                token = _write_pending(repo, analysis, str(payload.get("session_id", "unknown")))
                _deny(
                    "Existing test semantics require user clarification. {}. "
                    "After explicit clarification, run: /usr/bin/python3 "
                    ".codex/hooks/test_semantic_guard.py authorize {} --note "
                    "\"<clarification summary>\", then retry the patch. New test files "
                    "and new test declarations remain available without clarification.".format(
                        _format_changes(uncovered), token
                    )
                )
        elif tool_name == "Bash" and _is_git_commit(command):
            analysis = _staged_analysis(repo, _commit_includes_worktree(command))
            uncovered = _uncovered(repo, analysis.changes, analysis.expected_contents)
            if uncovered:
                _deny(
                    "Commit contains existing test semantic changes without a matching "
                    "clarification authorization: {}.".format(_format_changes(uncovered))
                )
    except (GuardError, OSError, ValueError, json.JSONDecodeError) as error:
        _deny("FlowTab test semantic guard could not verify this operation: {}".format(error))
    return 0


def _authorize(repo: Path, token: str, note: str) -> int:
    if not note.strip():
        raise GuardError("authorization requires a clarification summary")
    matches = sorted((_state_root(repo) / "pending").glob("{}*.json".format(token)))
    if len(matches) != 1:
        raise GuardError("pending clarification token is missing or ambiguous: {}".format(token))
    record = json.loads(matches[0].read_text(encoding="utf-8"))
    record["authorized_at"] = datetime.now(timezone.utc).isoformat()
    record["clarification_summary"] = note.strip()
    destination = _state_root(repo) / "authorized"
    destination.mkdir(parents=True, exist_ok=True)
    (destination / "{}.json".format(record["token"])).write_text(
        json.dumps(record, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print("authorized {}: {}".format(record["token"], _format_changes(record["changes"])))
    return 0


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("hook")
    authorize = subparsers.add_parser("authorize")
    authorize.add_argument("token")
    authorize.add_argument("--note", required=True)
    arguments = parser.parse_args(argv)
    if arguments.command == "hook":
        return _handle_hook()
    try:
        return _authorize(_repo_root(Path.cwd()), arguments.token, arguments.note)
    except GuardError as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
