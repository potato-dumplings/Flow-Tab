#!/usr/bin/env python3
"""Resolve the Team ID from the exact code-signing certificate bytes."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path


FINGERPRINT_RE = re.compile(r"^[0-9A-F]{40}$")
TEAM_ID_RE = re.compile(r"^[A-Z0-9]{10}$")
CERTIFICATE_RE = re.compile(
    rb"SHA-1 hash:\s*([0-9A-Fa-f]{40}).*?"
    rb"(-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----)",
    re.DOTALL,
)


class CertificateError(RuntimeError):
    pass


def run(command: list[str], *, input_data: bytes | None = None) -> bytes:
    result = subprocess.run(
        command,
        input=input_data,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        details = (result.stderr or result.stdout).decode(
            "utf-8", "replace"
        ).strip()
        raise CertificateError(
            f"command failed ({command[0]}): {details}"
        )
    return result.stdout


def user_keychains() -> list[str]:
    output = run(["/usr/bin/security", "list-keychains", "-d", "user"])
    keychains = re.findall(r'"([^"]+)"', output.decode("utf-8", "replace"))
    if not keychains:
        raise CertificateError("the user keychain search list is empty")
    return keychains


def certificate_for_fingerprint(
    readback: bytes,
    fingerprint: str,
) -> bytes:
    normalized = fingerprint.upper()
    for match in CERTIFICATE_RE.finditer(readback):
        if match.group(1).decode("ascii").upper() == normalized:
            return match.group(2) + b"\n"
    raise CertificateError(
        "the selected code-signing identity certificate is unavailable"
    )


def parse_subject_component(subject: str, key: str) -> str:
    match = re.search(rf"(?:^|,){re.escape(key)}=([^,]+)", subject)
    if match is None:
        raise CertificateError(f"certificate subject is missing {key}")
    return match.group(1).replace(r"\,", ",").strip()


def team_id_from_certificate(certificate: bytes) -> str:
    output = run(
        [
            "/usr/bin/openssl",
            "x509",
            "-noout",
            "-subject",
            "-nameopt",
            "RFC2253",
        ],
        input_data=certificate,
    ).decode("utf-8", "replace").strip()
    subject = output.removeprefix("subject=").strip()
    common_name = parse_subject_component(subject, "CN")
    if not common_name.startswith("Apple Development:"):
        raise CertificateError(
            "the selected certificate is not an Apple Development certificate"
        )
    team_id = parse_subject_component(subject, "OU")
    if TEAM_ID_RE.fullmatch(team_id) is None:
        raise CertificateError(
            "the certificate organizational unit is not a valid Team ID"
        )
    return team_id


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fingerprint", required=True)
    parser.add_argument("--keychain", action="append", type=Path)
    args = parser.parse_args()

    fingerprint = args.fingerprint.upper()
    if FINGERPRINT_RE.fullmatch(fingerprint) is None:
        parser.error("--fingerprint must be a 40-character SHA-1 fingerprint")

    try:
        keychains = (
            [str(path.expanduser().resolve()) for path in args.keychain]
            if args.keychain
            else user_keychains()
        )
        readback = run(
            [
                "/usr/bin/security",
                "find-certificate",
                "-a",
                "-Z",
                "-p",
                *keychains,
            ]
        )
        certificate = certificate_for_fingerprint(readback, fingerprint)
        print(team_id_from_certificate(certificate))
        return 0
    except CertificateError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
