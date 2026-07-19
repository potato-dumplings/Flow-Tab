#!/usr/bin/env python3
"""Deterministic tests for the FlowTab project test-semantic guard."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("test_semantic_guard.py")
SPEC = importlib.util.spec_from_file_location("test_semantic_guard", MODULE_PATH)
GUARD = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = GUARD
SPEC.loader.exec_module(GUARD)


BEFORE = """import XCTest

final class ExampleTests: XCTestCase {
    let expected = 1

    func testExistingBehavior() {
        XCTAssertEqual(value(), 1)
    }

    func value() -> Int {
        expected
    }
}
"""


class SemanticClassificationTests(unittest.TestCase):
    def test_new_test_method_is_additive(self) -> None:
        after = BEFORE.replace(
            "\n}\n",
            """

    func testNewBehavior() {
        XCTAssertEqual(value(), expected)
    }
}
""",
        )
        self.assertEqual(GUARD.semantic_changes(BEFORE, after), [])

    def test_existing_assertion_change_requires_clarification(self) -> None:
        after = BEFORE.replace("XCTAssertEqual(value(), 1)", "XCTAssertEqual(value(), 2)")
        self.assertEqual(
            GUARD.semantic_changes(BEFORE, after), ["testExistingBehavior"]
        )

    def test_insertion_inside_existing_test_requires_clarification(self) -> None:
        after = BEFORE.replace(
            "        XCTAssertEqual(value(), 1)",
            "        XCTAssertNotNil(Optional(value()))\n        XCTAssertEqual(value(), 1)",
        )
        self.assertEqual(
            GUARD.semantic_changes(BEFORE, after), ["testExistingBehavior"]
        )

    def test_shared_helper_change_requires_clarification(self) -> None:
        after = BEFORE.replace("        expected\n", "        expected + 1\n")
        self.assertEqual(GUARD.semantic_changes(BEFORE, after), ["value"])

    def test_file_scope_semantic_change_requires_clarification(self) -> None:
        after = BEFORE.replace("let expected = 1", "let expected = 2")
        self.assertEqual(GUARD.semantic_changes(BEFORE, after), ["<file-scope>"])

    def test_comment_and_whitespace_edits_are_not_semantic(self) -> None:
        after = BEFORE.replace(
            "func testExistingBehavior() {",
            "// Independent Oracle.\n    func testExistingBehavior()    {",
        )
        self.assertEqual(GUARD.semantic_changes(BEFORE, after), [])


class RepositoryGuardTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory(prefix="flowtab-guard-test-")
        self.repo = Path(self.directory.name)
        self.test_path = self.repo / "FlowTabTests/ExampleTests.swift"
        self.test_path.parent.mkdir(parents=True)
        self.test_path.write_text(BEFORE, encoding="utf-8")
        self._git("init", "-q")
        self._git("config", "user.name", "Guard Test")
        self._git("config", "user.email", "guard@example.invalid")
        self._git("add", ".")
        self._git("commit", "-qm", "baseline")

    def tearDown(self) -> None:
        self.directory.cleanup()

    def _git(self, *args: str) -> None:
        subprocess.run(("git",) + args, cwd=self.repo, check=True)

    def _analyze(self, patch: str):
        return GUARD.analyze_patch(self.repo, self.repo, patch)

    def _run_hook(self, patch: str) -> subprocess.CompletedProcess:
        payload = {
            "session_id": "session-test",
            "cwd": str(self.repo),
            "hook_event_name": "PreToolUse",
            "tool_name": "apply_patch",
            "tool_input": {"command": patch},
        }
        return subprocess.run(
            (sys.executable, str(MODULE_PATH), "hook"),
            cwd=self.repo,
            input=json.dumps(payload),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def test_patch_adding_method_is_allowed(self) -> None:
        patch = """*** Begin Patch
*** Update File: FlowTabTests/ExampleTests.swift
@@
     func value() -> Int {
         expected
     }
+
+    func testNewBehavior() {
+        XCTAssertEqual(value(), expected)
+    }
 }
*** End Patch
"""
        self.assertEqual(self._analyze(patch).changes, {})

    def test_patch_changing_existing_test_is_reported(self) -> None:
        patch = """*** Begin Patch
*** Update File: FlowTabTests/ExampleTests.swift
@@
     func testExistingBehavior() {
-        XCTAssertEqual(value(), 1)
+        XCTAssertEqual(value(), 2)
     }
*** End Patch
"""
        self.assertEqual(
            self._analyze(patch).changes,
            {"FlowTabTests/ExampleTests.swift": ["testExistingBehavior"]},
        )

    def test_hook_denies_existing_test_change_and_issues_token(self) -> None:
        patch = """*** Begin Patch
*** Update File: FlowTabTests/ExampleTests.swift
@@
     func testExistingBehavior() {
-        XCTAssertEqual(value(), 1)
+        XCTAssertEqual(value(), 2)
     }
*** End Patch
"""
        completed = self._run_hook(patch)
        self.assertEqual(completed.returncode, 0)
        output = json.loads(completed.stdout)
        specific = output["hookSpecificOutput"]
        self.assertEqual(specific["permissionDecision"], "deny")
        self.assertIn("authorize", specific["permissionDecisionReason"])

    def test_hook_returns_no_output_for_new_test_method(self) -> None:
        patch = """*** Begin Patch
*** Update File: FlowTabTests/ExampleTests.swift
@@
     func value() -> Int {
         expected
     }
+
+    func testNewBehavior() {
+        XCTAssertEqual(value(), expected)
+    }
 }
*** End Patch
"""
        completed = self._run_hook(patch)
        self.assertEqual(completed.returncode, 0)
        self.assertEqual(completed.stdout, "")

    def test_new_untracked_test_file_is_allowed(self) -> None:
        patch = """*** Begin Patch
*** Add File: FlowTabTests/NewTests.swift
+import XCTest
+
+final class NewTests: XCTestCase {
+    func testNewBehavior() {
+        XCTAssertTrue(true)
+    }
+}
*** End Patch
"""
        self.assertEqual(self._analyze(patch).changes, {})

    def test_authorization_covers_only_the_clarified_candidate(self) -> None:
        changed = BEFORE.replace("XCTAssertEqual(value(), 1)", "XCTAssertEqual(value(), 2)")
        analysis = GUARD.PatchAnalysis(
            {"FlowTabTests/ExampleTests.swift": ["testExistingBehavior"]},
            {"FlowTabTests/ExampleTests.swift": BEFORE},
            {"FlowTabTests/ExampleTests.swift": changed},
        )
        token = GUARD._write_pending(self.repo, analysis, "session-test")
        GUARD._authorize(self.repo, token, "User clarified the expected result is 2.")
        self.assertEqual(
            GUARD._uncovered(self.repo, analysis.changes, analysis.expected_contents), {}
        )
        changed_again = changed.replace("value(), 2", "value(), 3")
        uncovered = GUARD._uncovered(
            self.repo,
            {"FlowTabTests/ExampleTests.swift": ["testExistingBehavior"]},
            {"FlowTabTests/ExampleTests.swift": changed_again},
        )
        self.assertIn("FlowTabTests/ExampleTests.swift", uncovered)

    def test_commit_analysis_rejects_unclarified_existing_test_change(self) -> None:
        self.test_path.write_text(
            BEFORE.replace("XCTAssertEqual(value(), 1)", "XCTAssertEqual(value(), 2)"),
            encoding="utf-8",
        )
        self._git("add", "FlowTabTests/ExampleTests.swift")
        analysis = GUARD._staged_analysis(self.repo, include_worktree=False)
        self.assertEqual(
            GUARD._uncovered(self.repo, analysis.changes, analysis.expected_contents),
            {"FlowTabTests/ExampleTests.swift": ["testExistingBehavior"]},
        )

    def test_commit_analysis_allows_new_test_method(self) -> None:
        self.test_path.write_text(
            BEFORE.replace(
                "\n}\n",
                "\n    func testAdded() { XCTAssertTrue(true) }\n}\n",
            ),
            encoding="utf-8",
        )
        self._git("add", "FlowTabTests/ExampleTests.swift")
        self.assertEqual(
            GUARD._staged_analysis(self.repo, include_worktree=False).changes,
            {},
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
