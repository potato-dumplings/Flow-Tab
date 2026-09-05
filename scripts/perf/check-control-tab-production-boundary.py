#!/usr/bin/env python3
"""Check the Control+Tab pressure changes against the production source boundary."""
from __future__ import annotations

import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
FORBIDDEN = re.compile(
    r"ControlTabPressure|SwitcherInteraction(?:Diagnostic|Span|Component)|"
    r"Runtime(?:Process|FocusedRepair|WindowPreviewCapture)Diagnostic|"
    r"FocusedWindowSessionDiagnostic|interactionDiagnosticSink|pressure[A-Z]|processCPUSnapshot"
)
COMPOSITION = {"FlowTab/App/AppDelegate.swift"}
LEGACY_RELOCATION = {"FlowTab/Infrastructure/Runtime/ScreenCapturePermissionChecker.swift"}


def production(path: str) -> bool:
    return path.startswith("FlowTab/") and "/TestingSupport/" not in path and path.endswith(".swift")


def failures(path: str, line: str) -> bool:
    if not production(path) or path in COMPOSITION:
        return False
    if FORBIDDEN.search(line):
        return True
    return ("#if FLOWTAB_TESTING" in line or "FlowTabTestLaunchOptions" in line) and path not in LEGACY_RELOCATION


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True)


def main() -> int:
    errors = []
    path = ""
    for line in git("diff", "--no-ext-diff", "--unified=0", "HEAD", "--", "FlowTab").splitlines():
        if line.startswith("+++ b/"):
            path = line[6:]
        elif line.startswith("+") and not line.startswith("+++") and failures(path, line[1:]):
            errors.append(f"{path}: {line[1:]}")
    for path in git("ls-files", "--others", "--exclude-standard", "--", "FlowTab").splitlines():
        if not production(path):
            continue
        for number, line in enumerate((ROOT / path).read_text().splitlines(), 1):
            if failures(path, line):
                errors.append(f"{path}:{number}: {line}")
    # The relocated permission checker keeps the pre-existing launch/permission policy.
    legacy_source = git("show", "HEAD:FlowTab/Infrastructure/Runtime/RuntimeWindowPreviewProvider.swift")
    relocated = (ROOT / next(iter(LEGACY_RELOCATION))).read_text()
    original = legacy_source.split("enum ScreenCapturePermissionChecker {", 1)[1]
    original = "enum ScreenCapturePermissionChecker {" + original
    if relocated[relocated.index("enum ScreenCapturePermissionChecker {"):].strip() != original.strip():
        errors.append("Relocated ScreenCapturePermissionChecker differs from its existing production policy.")
    for error in errors:
        print(error)
    if not errors:
        print("Control+Tab production dependency boundary passed.")
    return int(bool(errors))


if __name__ == "__main__":
    raise SystemExit(main())
