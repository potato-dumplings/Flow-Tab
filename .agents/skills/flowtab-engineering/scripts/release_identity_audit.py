#!/usr/bin/env python3
"""Audit FlowTab release code identity and upgrade compatibility."""

from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable


CODESIGN = Path("/usr/bin/codesign")
LIPO = Path("/usr/bin/lipo")
DEFAULT_BUNDLE_ID = "io.github.potato-dumplings.flowtab"
TEAM_ID_RE = re.compile(r"^[A-Z0-9]{10}$")
AUTHORITY_PREFIXES = {
    "apple-development": "Apple Development:",
    "developer-id": "Developer ID Application:",
}


class AuditError(RuntimeError):
    pass


@dataclass(frozen=True)
class CodeIdentity:
    identifier: str
    team_identifier: str
    signature: str
    authorities: tuple[str, ...]
    designated_requirement: str

    @property
    def is_adhoc(self) -> bool:
        return (
            self.signature == "adhoc"
            or self.team_identifier == "not set"
            or self.designated_requirement.startswith("cdhash ")
        )

    @property
    def has_stable_certificate(self) -> bool:
        return (
            not self.is_adhoc
            and bool(self.authorities)
            and all(authority != "(unavailable)" for authority in self.authorities)
            and TEAM_ID_RE.fullmatch(self.team_identifier) is not None
        )


@dataclass(frozen=True)
class AppIdentity:
    path: Path
    bundle_identifier: str
    version: str
    architectures: tuple[str, ...]
    code: CodeIdentity


def run(command: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    if check and result.returncode != 0:
        details = (result.stderr or result.stdout).strip()
        raise AuditError(f"command failed ({command[0]}): {details}")
    return result


def combined_output(result: subprocess.CompletedProcess[str]) -> str:
    return "\n".join(
        output.strip()
        for output in (result.stderr, result.stdout)
        if output.strip()
    )


def parse_codesign_details(output: str) -> CodeIdentity:
    identifier = ""
    team_identifier = ""
    signature = "certificate"
    authorities: list[str] = []
    designated_requirement = ""

    for raw_line in output.splitlines():
        line = raw_line.strip()
        if line.startswith("Identifier="):
            identifier = line.removeprefix("Identifier=")
        elif line.startswith("TeamIdentifier="):
            team_identifier = line.removeprefix("TeamIdentifier=")
        elif line.startswith("Signature="):
            signature = line.removeprefix("Signature=").lower()
        elif line.startswith("Authority="):
            authorities.append(line.removeprefix("Authority="))
        elif line.startswith("# designated => "):
            designated_requirement = line.removeprefix("# designated => ")
        elif line.startswith("designated => "):
            designated_requirement = line.removeprefix("designated => ")

    missing = [
        name
        for name, value in (
            ("Identifier", identifier),
            ("TeamIdentifier", team_identifier),
            ("designated requirement", designated_requirement),
        )
        if not value
    ]
    if missing:
        raise AuditError(f"codesign output is missing: {', '.join(missing)}")

    return CodeIdentity(
        identifier=identifier,
        team_identifier=team_identifier,
        signature=signature,
        authorities=tuple(authorities),
        designated_requirement=designated_requirement,
    )


def inspect_app(path: Path) -> AppIdentity:
    app_path = path.expanduser().resolve()
    info_path = app_path / "Contents" / "Info.plist"
    if not app_path.is_dir() or not info_path.is_file():
        raise AuditError(f"App bundle is missing: {path}")

    run([str(CODESIGN), "--verify", "--deep", "--strict", "--verbose=2", str(app_path)])
    details = run([str(CODESIGN), "-dvvv", "-r-", str(app_path)])
    code = parse_codesign_details(combined_output(details))

    with info_path.open("rb") as stream:
        info = plistlib.load(stream)
    bundle_identifier = info.get("CFBundleIdentifier")
    version = info.get("CFBundleShortVersionString")
    executable_name = info.get("CFBundleExecutable")
    if not all(isinstance(value, str) and value for value in (bundle_identifier, version, executable_name)):
        raise AuditError(f"App metadata is incomplete: {app_path}")
    if executable_name in {".", ".."} or "/" in executable_name:
        raise AuditError(f"App executable must be a direct child name: {executable_name}")

    executable_path = app_path / "Contents" / "MacOS" / executable_name
    if not executable_path.is_file():
        raise AuditError(f"App executable is missing: {executable_path}")
    architectures_result = run([str(LIPO), "-archs", str(executable_path)])
    architectures = tuple(sorted(architectures_result.stdout.split()))
    if not architectures:
        raise AuditError(f"App executable has no reported architectures: {executable_path}")

    return AppIdentity(
        path=app_path,
        bundle_identifier=bundle_identifier,
        version=version,
        architectures=architectures,
        code=code,
    )


def validate_candidate(
    candidate: AppIdentity,
    *,
    authority_kind: str,
    expected_bundle_id: str,
    expected_version: str | None,
    expected_team_id: str | None,
    required_architectures: set[str],
) -> None:
    if not candidate.code.has_stable_certificate:
        raise AuditError("candidate must use a visible stable certificate identity; ad-hoc is forbidden")
    authority_prefix = AUTHORITY_PREFIXES[authority_kind]
    if not candidate.code.authorities[0].startswith(authority_prefix):
        raise AuditError(f"candidate authority does not match {authority_kind}")
    if candidate.bundle_identifier != expected_bundle_id or candidate.code.identifier != expected_bundle_id:
        raise AuditError("candidate Bundle ID and signing identifier must match the expected Bundle ID")
    if expected_version is not None and candidate.version != expected_version:
        raise AuditError(
            f"candidate version {candidate.version!r} does not match {expected_version!r}"
        )
    if expected_team_id is not None and candidate.code.team_identifier != expected_team_id:
        raise AuditError("candidate TeamIdentifier does not match the expected team")
    missing_architectures = required_architectures - set(candidate.architectures)
    if missing_architectures:
        raise AuditError(
            f"candidate is missing required architectures: {sorted(missing_architectures)}"
        )


def satisfies_requirement(app_path: Path, requirement: str) -> bool:
    result = run(
        [
            str(CODESIGN),
            "--verify",
            "--deep",
            "--strict",
            f"-R={requirement}",
            str(app_path),
        ],
        check=False,
    )
    return result.returncode == 0


def requirement_digest(requirement: str) -> str:
    return hashlib.sha256(requirement.encode("utf-8")).hexdigest()


def evaluate_compatibility(
    baseline: AppIdentity,
    candidate: AppIdentity,
    *,
    expected_bundle_id: str,
    accept_adhoc_migration: bool,
    requirement_checker: Callable[[Path, str], bool] = satisfies_requirement,
) -> dict[str, object]:
    if (
        baseline.bundle_identifier != expected_bundle_id
        or baseline.code.identifier != expected_bundle_id
    ):
        raise AuditError(
            "baseline Bundle ID and signing identifier must match the expected Bundle ID"
        )
    if baseline.code.is_adhoc:
        if not accept_adhoc_migration:
            raise AuditError(
                "baseline is ad-hoc; use --accept-adhoc-migration only for the one-time stable identity transition"
            )
        return {
            "status": "one_time_regrant_required",
            "mutual_designated_requirement": False,
        }
    if not baseline.code.has_stable_certificate:
        raise AuditError("baseline stable certificate identity is unavailable or incomplete")
    if baseline.code.team_identifier != candidate.code.team_identifier:
        raise AuditError("baseline and candidate TeamIdentifiers differ")

    candidate_satisfies_baseline = requirement_checker(
        candidate.path,
        baseline.code.designated_requirement,
    )
    baseline_satisfies_candidate = requirement_checker(
        baseline.path,
        candidate.code.designated_requirement,
    )
    if not candidate_satisfies_baseline or not baseline_satisfies_candidate:
        raise AuditError(
            "baseline and candidate designated requirements are not mutually compatible"
        )
    return {
        "status": "compatible",
        "mutual_designated_requirement": True,
        "candidate_satisfies_baseline": candidate_satisfies_baseline,
        "baseline_satisfies_candidate": baseline_satisfies_candidate,
    }


def identity_summary(app: AppIdentity, authority_kind: str | None = None) -> dict[str, object]:
    return {
        "path": str(app.path),
        "bundle_id": app.bundle_identifier,
        "version": app.version,
        "architectures": list(app.architectures),
        "authority_kind": authority_kind,
        "team_identifier": app.code.team_identifier,
        "adhoc": app.code.is_adhoc,
        "designated_requirement_sha256": requirement_digest(
            app.code.designated_requirement
        ),
    }


def parse_architectures(raw: str) -> set[str]:
    values = {value.strip() for value in raw.split(",") if value.strip()}
    if not values:
        raise argparse.ArgumentTypeError("required architectures must not be empty")
    return values


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate-app", required=True, type=Path)
    parser.add_argument("--baseline-app", type=Path)
    parser.add_argument(
        "--authority-kind",
        required=True,
        choices=sorted(AUTHORITY_PREFIXES),
    )
    parser.add_argument("--expected-bundle-id", default=DEFAULT_BUNDLE_ID)
    parser.add_argument("--expected-version")
    parser.add_argument("--expected-team-id")
    parser.add_argument(
        "--required-architectures",
        type=parse_architectures,
        default=set(),
    )
    parser.add_argument("--candidate-only", action="store_true")
    parser.add_argument("--accept-adhoc-migration", action="store_true")
    args = parser.parse_args()

    if args.expected_team_id is not None and not TEAM_ID_RE.fullmatch(args.expected_team_id):
        parser.error("--expected-team-id must contain 10 uppercase letters or digits")
    if args.candidate_only and args.baseline_app is not None:
        parser.error("--candidate-only cannot be combined with --baseline-app")
    if not args.candidate_only and args.baseline_app is None:
        parser.error("--baseline-app is required unless --candidate-only is explicit")
    if args.accept_adhoc_migration and args.baseline_app is None:
        parser.error("--accept-adhoc-migration requires --baseline-app")

    try:
        candidate = inspect_app(args.candidate_app)
        validate_candidate(
            candidate,
            authority_kind=args.authority_kind,
            expected_bundle_id=args.expected_bundle_id,
            expected_version=args.expected_version,
            expected_team_id=args.expected_team_id,
            required_architectures=args.required_architectures,
        )

        result: dict[str, object] = {
            "schema_version": 1,
            "candidate": identity_summary(candidate, args.authority_kind),
        }
        if args.candidate_only:
            result["compatibility"] = {
                "status": "candidate_only_unproven",
                "mutual_designated_requirement": False,
            }
        else:
            baseline = inspect_app(args.baseline_app)
            result["baseline"] = identity_summary(baseline)
            result["compatibility"] = evaluate_compatibility(
                baseline,
                candidate,
                expected_bundle_id=args.expected_bundle_id,
                accept_adhoc_migration=args.accept_adhoc_migration,
            )

        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
        return 0
    except (AuditError, OSError, plistlib.InvalidFileException) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
