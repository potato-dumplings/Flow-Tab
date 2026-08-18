#!/usr/bin/env python3
"""Process/tooling tests for FlowTab release identity parsing and gates."""

from __future__ import annotations

import unittest
from pathlib import Path
from subprocess import CompletedProcess

from release_identity_audit import (
    AppIdentity,
    AuditError,
    combined_output,
    evaluate_compatibility,
    parse_codesign_details,
    requirement_digest,
    validate_candidate,
)


APPLE_DEVELOPMENT_DETAILS = """
Identifier=io.github.potato-dumplings.flowtab
Authority=Apple Development: Example Developer (ABCDEFGHIJ)
Authority=Apple Worldwide Developer Relations Certification Authority
Authority=Apple Root CA
TeamIdentifier=123456789A
designated => identifier "io.github.potato-dumplings.flowtab" and anchor apple generic and certificate leaf[subject.CN] = "Apple Development: Example Developer (ABCDEFGHIJ)"
"""

ADHOC_DETAILS = """
Identifier=io.github.potato-dumplings.flowtab
Signature=adhoc
TeamIdentifier=not set
# designated => cdhash H"0123456789012345678901234567890123456789"
"""


class ReleaseIdentityAuditTests(unittest.TestCase):
    @staticmethod
    def _app(details: str, path: str = "Flow Tab.app") -> AppIdentity:
        return AppIdentity(
            path=Path(path),
            bundle_identifier="io.github.potato-dumplings.flowtab",
            version="0.1.0-alpha.02",
            architectures=("arm64", "x86_64"),
            code=parse_codesign_details(details),
        )

    def test_codesign_streams_are_combined(self) -> None:
        result = CompletedProcess(
            args=["codesign"],
            returncode=0,
            stdout='designated => identifier "io.github.potato-dumplings.flowtab"',
            stderr="Identifier=io.github.potato-dumplings.flowtab",
        )
        output = combined_output(result)
        self.assertIn("Identifier=io.github.potato-dumplings.flowtab", output)
        self.assertIn("designated => identifier", output)

    def test_certificate_identity_is_stable(self) -> None:
        identity = parse_codesign_details(APPLE_DEVELOPMENT_DETAILS)
        self.assertTrue(identity.has_stable_certificate)
        self.assertFalse(identity.is_adhoc)
        self.assertEqual(identity.team_identifier, "123456789A")

    def test_adhoc_identity_is_not_stable(self) -> None:
        identity = parse_codesign_details(ADHOC_DETAILS)
        self.assertTrue(identity.is_adhoc)
        self.assertFalse(identity.has_stable_certificate)

    def test_candidate_gate_rejects_adhoc(self) -> None:
        candidate = self._app(ADHOC_DETAILS)
        with self.assertRaisesRegex(AuditError, "ad-hoc is forbidden"):
            validate_candidate(
                candidate,
                authority_kind="apple-development",
                expected_bundle_id="io.github.potato-dumplings.flowtab",
                expected_version="0.1.0-alpha.02",
                expected_team_id=None,
                required_architectures={"arm64", "x86_64"},
            )

    def test_candidate_gate_accepts_expected_certificate_identity(self) -> None:
        candidate = self._app(APPLE_DEVELOPMENT_DETAILS)
        validate_candidate(
            candidate,
            authority_kind="apple-development",
            expected_bundle_id="io.github.potato-dumplings.flowtab",
            expected_version="0.1.0-alpha.02",
            expected_team_id="123456789A",
            required_architectures={"arm64", "x86_64"},
        )

    def test_adhoc_baseline_requires_explicit_migration(self) -> None:
        with self.assertRaisesRegex(AuditError, "baseline is ad-hoc"):
            evaluate_compatibility(
                self._app(ADHOC_DETAILS, "baseline.app"),
                self._app(APPLE_DEVELOPMENT_DETAILS, "candidate.app"),
                expected_bundle_id="io.github.potato-dumplings.flowtab",
                accept_adhoc_migration=False,
            )

    def test_explicit_adhoc_migration_requires_one_time_regrant(self) -> None:
        result = evaluate_compatibility(
            self._app(ADHOC_DETAILS, "baseline.app"),
            self._app(APPLE_DEVELOPMENT_DETAILS, "candidate.app"),
            expected_bundle_id="io.github.potato-dumplings.flowtab",
            accept_adhoc_migration=True,
        )
        self.assertEqual(result["status"], "one_time_regrant_required")
        self.assertFalse(result["mutual_designated_requirement"])

    def test_stable_baseline_requires_mutual_compatibility(self) -> None:
        calls: list[tuple[Path, str]] = []

        def checker(path: Path, requirement: str) -> bool:
            calls.append((path, requirement))
            return True

        result = evaluate_compatibility(
            self._app(APPLE_DEVELOPMENT_DETAILS, "baseline.app"),
            self._app(APPLE_DEVELOPMENT_DETAILS, "candidate.app"),
            expected_bundle_id="io.github.potato-dumplings.flowtab",
            accept_adhoc_migration=False,
            requirement_checker=checker,
        )
        self.assertEqual(result["status"], "compatible")
        self.assertEqual([path for path, _ in calls], [Path("candidate.app"), Path("baseline.app")])

    def test_one_way_requirement_match_is_rejected(self) -> None:
        outcomes = iter((True, False))
        with self.assertRaisesRegex(AuditError, "not mutually compatible"):
            evaluate_compatibility(
                self._app(APPLE_DEVELOPMENT_DETAILS, "baseline.app"),
                self._app(APPLE_DEVELOPMENT_DETAILS, "candidate.app"),
                expected_bundle_id="io.github.potato-dumplings.flowtab",
                accept_adhoc_migration=False,
                requirement_checker=lambda _path, _requirement: next(outcomes),
            )

    def test_requirement_digest_is_deterministic(self) -> None:
        requirement = parse_codesign_details(
            APPLE_DEVELOPMENT_DETAILS
        ).designated_requirement
        self.assertEqual(requirement_digest(requirement), requirement_digest(requirement))


if __name__ == "__main__":
    unittest.main()
