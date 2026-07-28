#!/usr/bin/env python3
"""Process/tooling tests for the FlowTab canonical test-asset path."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from test_asset_boundary import (
    assert_boundary_closure,
    assert_reconstruction_empty,
    clear_planned_carrier_text,
    resolve_carrier_fragment,
)
from test_asset_clear_plan import build_reconstruction_clear_plan
from test_asset_index import (
    build_deltas,
    discover_assets,
    filter_assets,
    load_boundary_manifest,
)
from test_asset_model import (
    RecordValidationError,
    aggregate_required_status,
    canonical_jsonl,
    load_jsonl,
    validate_record,
)
from test_asset_views import build_projection, record_references
from test_asset_workspace import run_full_validation


class TestAssetToolTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self._write(
            "FlowTabCore/Package.swift",
            """// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "FlowTab",
    targets: [
        .target(name: "FlowTabCore"),
        .testTarget(name: "FlowTabCoreTests", dependencies: ["FlowTabCore"])
    ]
)
""",
        )
        self._write(
            "FlowTabCore/Tests/FlowTabCoreTests/CoreRuleTests.swift",
            """import XCTest

final class CoreRuleTests: XCTestCase {
    func testRuleUsesExplicitInput() {
        let input = 2
        XCTAssertEqual(input + 1, 3)
    }
}
""",
        )
        self._write(
            "FlowTabTests/SampleTests.swift",
            """import XCTest

final class SampleTests: XCTestCase {
    func testFixtureBackedBehavior() {
        let fixtureValue = 4
        XCTAssertEqual(fixtureValue, 4)
    }
}
""",
        )
        self._write(
            "FlowTabUITests/VisibleTests.swift",
            """import XCTest

final class VisibleTests: XCTestCase {
    func testVisibleResult() {
        XCTAssertTrue(true)
    }
}
""",
        )
        self._write("FlowTab/TestingSupport/LaunchSupport.swift", "struct LaunchSupport {}\n")
        self._write("FlowTabSpaceFixture/Fixture.swift", "struct Fixture {}\n")
        self._write("docs/fixtures/workflow.json", "{\"windows\": []}\n")
        self._write("scripts/testing/run-flowtabtests-local.sh", "#!/bin/bash\nexit 0\n")
        self._write("scripts/testing/run-ui-tests-local.sh", "#!/bin/bash\nexit 0\n")
        self._write("scripts/testing/install-ui-test-app.sh", "#!/bin/bash\nexit 0\n")
        self._write("scripts/testing/create-ui-app-identity-manifest.sh", "#!/bin/bash\nexit 0\n")
        for pressure_runner in (
            "runtime-topology-pressure.sh",
            "search-committed-index-pressure.sh",
            "tab-switch-stress.sh",
        ):
            self._write(
                f"scripts/perf/{pressure_runner}",
                "#!/bin/bash\npython3 scripts/perf/lib/pressure-summary.py\n",
            )
        self._write("scripts/perf/lib/pressure-summary.py", "print('summary')\n")
        self._write("scripts/audit/runtime-contract.sh", "#!/bin/bash\nexit 0\n")
        self._write(
            "scripts/release/test-release-distribution-contract.sh",
            "#!/bin/bash\nexit 0\n",
        )
        self._write(
            "scripts/release/test-uninstall-flowtab-cleanup.js",
            "const assert = require('node:assert/strict');\nassert.ok(true);\n",
        )
        self._write(
            "FlowTab.xcodeproj/xcshareddata/xcschemes/FlowTab.xcscheme",
            """<Scheme>
<BuildAction>
<BuildActionEntry><BuildableReference BlueprintIdentifier="AAAAAAAAAAAAAAAAAAAAAAAA" BlueprintName="FlowTabSpaceFixture"/></BuildActionEntry>
<BuildActionEntry><BuildableReference BlueprintIdentifier="BBBBBBBBBBBBBBBBBBBBBBBB" BlueprintName="FlowTabTests"/></BuildActionEntry>
<BuildActionEntry><BuildableReference BlueprintIdentifier="CCCCCCCCCCCCCCCCCCCCCCCC" BlueprintName="FlowTabUITests"/></BuildActionEntry>
</BuildAction>
<TestAction><Testables><TestableReference><BuildableReference BlueprintIdentifier="BBBBBBBBBBBBBBBBBBBBBBBB" BlueprintName="FlowTabTests"/></TestableReference></Testables></TestAction>
</Scheme>
""",
        )
        self._write(
            "FlowTab.xcodeproj/xcshareddata/xcschemes/FlowTabSpaceFixture.xcscheme",
            "<Scheme><TestAction><BuildableReference BlueprintName=\"FlowTabSpaceFixture\"/></TestAction></Scheme>\n",
        )
        self._write(
            "FlowTab.xcodeproj/project.pbxproj",
            """// !$*UTF8*$!
111111111111111111111111 /* FlowTabTests */ = {
    isa = PBXNativeTarget;
    buildConfigurationList = 111111111111111111111112 /* Build configuration list for PBXNativeTarget "FlowTabTests" */;
    name = FlowTabTests;
};
111111111111111111111112 /* Build configuration list for PBXNativeTarget "FlowTabTests" */ = {
    isa = XCConfigurationList;
    buildConfigurations = (111111111111111111111113 /* Debug */);
};
111111111111111111111113 /* Debug */ = {isa = XCBuildConfiguration; name = Debug;};
222222222222222222222221 /* FlowTabUITests */ = {
    isa = PBXNativeTarget;
    buildConfigurationList = 222222222222222222222222 /* Build configuration list for PBXNativeTarget "FlowTabUITests" */;
    name = FlowTabUITests;
};
222222222222222222222222 /* Build configuration list for PBXNativeTarget "FlowTabUITests" */ = {
    isa = XCConfigurationList;
    buildConfigurations = (222222222222222222222223 /* Debug */);
};
222222222222222222222223 /* Debug */ = {isa = XCBuildConfiguration; name = Debug;};
333333333333333333333331 /* FlowTabSpaceFixture */ = {
    isa = PBXNativeTarget;
    buildConfigurationList = 333333333333333333333332 /* Build configuration list for PBXNativeTarget "FlowTabSpaceFixture" */;
    name = FlowTabSpaceFixture;
};
333333333333333333333332 /* Build configuration list for PBXNativeTarget "FlowTabSpaceFixture" */ = {
    isa = XCConfigurationList;
    buildConfigurations = (333333333333333333333333 /* Debug */);
};
333333333333333333333333 /* Debug */ = {isa = XCBuildConfiguration; name = Debug;};
444444444444444444444441 /* TestingSupport */ = {
    isa = PBXGroup;
    path = TestingSupport;
};
""",
        )
        self._write("xcconfigs/LocalSigning.xcconfig", "FLOWTAB_DEVELOPMENT_TEAM =\n")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def _write(self, intent: str, content: str) -> None:
        path = self.root / intent
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def test_rebuild_is_deterministic(self) -> None:
        first = canonical_jsonl(discover_assets(self.root))
        second = canonical_jsonl(discover_assets(self.root))
        self.assertEqual(first, second)

    def test_boundary_manifest_owns_routine_and_reconstruction_paths(self) -> None:
        manifest = load_boundary_manifest()
        intents = {
            entry["relative_path_intent"]
            for entry in manifest["asset_boundaries"]
        }
        self.assertIn("FlowTabTests", intents)
        self.assertIn("FlowTabUITests", intents)
        self.assertIn("scripts/testing", intents)
        self.assertIn("scripts/audit", intents)
        self.assertIn("scripts/release/test-uninstall-flowtab-cleanup.js", intents)
        self.assertEqual(
            manifest["transient_reconstruction_root"],
            ".build-local/test-audit/rebuild",
        )
        fragments = {
            fragment["fragment_id"]
            for carrier in manifest["shared_carriers"]
            for fragment in carrier["test_owned_fragments"]
        }
        self.assertIn("flowtab-tests-target-graph", fragments)
        self.assertIn("flowtab-testing-support-group-graph", fragments)

    def test_empty_boundary_gate_rejects_prior_assets_and_outputs(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            clean_root = Path(directory)
            for intent, content in (
                ("FlowTabCore/Package.swift", "import PackageDescription\n"),
                ("FlowTab.xcodeproj/project.pbxproj", "// !$*UTF8*$!\n"),
                (
                    "FlowTab.xcodeproj/xcshareddata/xcschemes/FlowTab.xcscheme",
                    "<Scheme></Scheme>\n",
                ),
            ):
                path = clean_root / intent
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content, encoding="utf-8")
            assert_reconstruction_empty(clean_root)
            old_test = clean_root / "FlowTabTests/OldTests.swift"
            old_test.parent.mkdir(parents=True)
            old_test.write_text("final class OldTests {}\n", encoding="utf-8")
            with self.assertRaises(RecordValidationError):
                assert_reconstruction_empty(clean_root)
            old_test.unlink()
            old_anchor = clean_root / "docs/test-audit/C0_HANDOFF.json"
            old_anchor.parent.mkdir(parents=True)
            old_anchor.write_text("{}\n", encoding="utf-8")
            with self.assertRaises(RecordValidationError):
                assert_reconstruction_empty(clean_root)

    def test_path_scope_matches_full_records_byte_for_byte(self) -> None:
        full = discover_assets(self.root)
        scoped = filter_assets(full, ["FlowTabTests"])
        expected = [
            row
            for row in full
            if row["asset_locator"]["relative_path_intent"].startswith("FlowTabTests/")
        ]
        self.assertEqual(canonical_jsonl(scoped), canonical_jsonl(expected))

    def test_path_scope_can_describe_a_partial_reconstruction_candidate(self) -> None:
        self._write(
            "FlowTabCore/Package.swift",
            "// swift-tools-version: 5.9\nimport PackageDescription\n",
        )
        records = discover_assets(self.root)
        scoped = filter_assets(records, ["FlowTabTests"])
        self.assertTrue(scoped)
        with self.assertRaises(RecordValidationError):
            assert_boundary_closure(self.root, records)

    def test_full_validation_workspace_is_fresh_and_removed_after_success(self) -> None:
        stale = self.root / ".build-local/test-assets/stale.txt"
        stale.parent.mkdir(parents=True)
        stale.write_text("stale\n", encoding="utf-8")
        command = [
            sys.executable,
            "-c",
            (
                "import os; "
                "from pathlib import Path; "
                "root = Path(os.environ['FLOWTAB_TEST_ASSET_ROOT']); "
                "assert os.environ['FLOWTAB_TEST_ASSET_PATH_INTENT'] "
                "== '.build-local/test-assets'; "
                "assert not (root / 'stale.txt').exists(); "
                "(root / 'ledger.jsonl').write_text('{}\\n', encoding='utf-8')"
            ),
        ]

        self.assertEqual(run_full_validation(self.root, "full-success", command), 0)
        self.assertFalse((self.root / ".build-local/test-assets").exists())

    def test_full_validation_workspace_is_removed_after_failure(self) -> None:
        command = [
            sys.executable,
            "-c",
            (
                "import os; "
                "from pathlib import Path; "
                "root = Path(os.environ['FLOWTAB_TEST_ASSET_ROOT']); "
                "(root / 'failed.jsonl').write_text('{}\\n', encoding='utf-8'); "
                "raise SystemExit(7)"
            ),
        ]

        self.assertEqual(run_full_validation(self.root, "full-failure", command), 7)
        self.assertFalse((self.root / ".build-local/test-assets").exists())

    def test_full_validation_workspace_is_removed_when_child_cannot_start(self) -> None:
        command = [str(self.root / "missing-full-validation-entry")]

        with self.assertRaises(FileNotFoundError):
            run_full_validation(self.root, "full-launch-error", command)
        self.assertFalse((self.root / ".build-local/test-assets").exists())

    def test_generated_view_cannot_change_discovery(self) -> None:
        before = canonical_jsonl(discover_assets(self.root))
        projection = build_projection(discover_assets(self.root), [], [])
        self._write("docs/generated-test-summary.json", json.dumps(projection))
        after = canonical_jsonl(discover_assets(self.root))
        self.assertEqual(before, after)
        (self.root / "docs/generated-test-summary.json").unlink()
        rebuilt = canonical_jsonl(discover_assets(self.root))
        self.assertEqual(before, rebuilt)

    def test_full_ledger_round_trip_passes_boundary_closure(self) -> None:
        records = discover_assets(self.root)
        report = assert_boundary_closure(self.root, records)
        self.assertEqual(report["errors"], [])
        ledger = self.root / "ledger.jsonl"
        ledger.write_text(canonical_jsonl(records), encoding="utf-8")
        loaded = load_jsonl(ledger, "test_asset")
        self.assertEqual(canonical_jsonl(records), canonical_jsonl(loaded))
        self.assertEqual(
            canonical_jsonl(filter_assets(records, ["FlowTabTests"])),
            canonical_jsonl(filter_assets(loaded, ["FlowTabTests"])),
        )

    def test_clear_plan_qualifies_and_proves_the_empty_boundary(self) -> None:
        subprocess.run(["git", "init", "-q"], cwd=self.root, check=True)
        subprocess.run(["git", "add", "."], cwd=self.root, check=True)
        subprocess.run(
            [
                "git",
                "-c",
                "user.name=FlowTab Test",
                "-c",
                "user.email=flowtab-test@example.invalid",
                "commit",
                "-qm",
                "fixture",
            ],
            cwd=self.root,
            check=True,
        )
        plan = build_reconstruction_clear_plan(self.root, "HEAD", discover_assets(self.root))
        self.assertTrue(plan["ready"])
        self.assertFalse(plan["errors"])
        self.assertTrue(
            all(
                carrier["fragments"]
                for carrier in plan["shared_carrier_entries"]
            )
        )
        plan_path = self.root / ".build-local/test-audit/rebuild/RECONSTRUCTION_CLEAR_PLAN.json"
        plan_path.parent.mkdir(parents=True)
        plan_path.write_text(json.dumps(plan, sort_keys=True), encoding="utf-8")

        manifest = load_boundary_manifest()
        for entry in manifest["asset_boundaries"]:
            path = self.root / entry["relative_path_intent"]
            if path.is_dir():
                shutil.rmtree(path)
            elif path.is_file():
                path.unlink()
        for carrier in plan["shared_carrier_entries"]:
            path = self.root / carrier["relative_path_intent"]
            text = path.read_text(encoding="utf-8")
            matches = [
                match for fragment in carrier["fragments"] for match in fragment["matches"]
            ]
            identifiers = [
                identifier
                for fragment in carrier["fragments"]
                for identifier in fragment["owned_identifiers"]
            ]
            path.write_text(
                clear_planned_carrier_text(text, matches, identifiers),
                encoding="utf-8",
            )
        assert_reconstruction_empty(self.root, clear_plan=plan)
        package = self.root / "FlowTabCore/Package.swift"
        package.write_text(package.read_text(encoding="utf-8") + "// changed\n", encoding="utf-8")
        with self.assertRaises(RecordValidationError):
            assert_reconstruction_empty(self.root, clear_plan=plan)

    def test_target_graph_preserves_shared_production_file_references(self) -> None:
        shared_file = "EEEEEEEEEEEEEEEEEEEEEEEE"
        project = f"""AAAAAAAAAAAAAAAAAAAAAAAA /* FlowTabTests */ = {{
    isa = PBXNativeTarget;
    buildPhases = (BBBBBBBBBBBBBBBBBBBBBBBB /* Sources */);
    name = FlowTabTests;
}};
BBBBBBBBBBBBBBBBBBBBBBBB /* Sources */ = {{
    isa = PBXSourcesBuildPhase;
    files = (CCCCCCCCCCCCCCCCCCCCCCCC /* Shared.swift in Sources */);
}};
CCCCCCCCCCCCCCCCCCCCCCCC /* Shared.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {shared_file} /* Shared.swift */;}};
{shared_file} /* Shared.swift */ = {{isa = PBXFileReference; path = Shared.swift;}};
DDDDDDDDDDDDDDDDDDDDDDDD /* FlowTabTests */ = {{
    isa = PBXGroup;
    path = FlowTabTests;
}};
"""
        resolution = resolve_carrier_fragment(
            project,
            {
                "fragment_id": "flowtab-tests-target-graph",
                "selector": {"kind": "pbxproj_target_graph", "target": "FlowTabTests"},
            },
        )
        self.assertIn("CCCCCCCCCCCCCCCCCCCCCCCC", resolution.owned_identifiers)
        self.assertNotIn(shared_file, resolution.owned_identifiers)

    def test_pressure_helper_is_a_runner_not_a_scenario(self) -> None:
        records = discover_assets(self.root)
        helper = "scripts/perf/lib/pressure-summary.py"
        helper_record = next(
            row
            for row in records
            if row["asset_type"] == "runner"
            and row["asset_locator"]["relative_path_intent"] == helper
        )
        top_level_runner = next(
            row
            for row in records
            if row["asset_type"] == "runner"
            and row["asset_locator"]["relative_path_intent"]
            == "scripts/perf/search-committed-index-pressure.sh"
        )
        self.assertIn(helper_record["asset_id"], top_level_runner["dependencies"])
        self.assertFalse(
            any(
                row["asset_type"] == "pressure_scenario"
                and row["asset_locator"]["relative_path_intent"] == helper
                for row in records
            )
        )

    def test_file_scoped_runner_boundary_is_indexed(self) -> None:
        records = discover_assets(self.root)
        intent = "scripts/release/test-uninstall-flowtab-cleanup.js"
        release_test = next(
            row
            for row in records
            if row["asset_type"] == "runner"
            and row["asset_locator"]["relative_path_intent"] == intent
        )
        self.assertEqual(release_test["owner"], "RepositoryRelease")
        self.assertEqual(release_test["layer_capabilities"], ["behavior", "process_tooling"])

    def test_move_produces_lineage(self) -> None:
        before = discover_assets(self.root)
        source = self.root / "FlowTabTests/SampleTests.swift"
        destination = self.root / "FlowTabTests/Moved/SampleTests.swift"
        destination.parent.mkdir(parents=True)
        source.rename(destination)
        after = discover_assets(self.root)
        deltas = build_deltas(before, after)
        moved = [row for row in deltas if row["change_kind"] == "moved"]
        self.assertGreaterEqual(len(moved), 2)
        self.assertTrue(all(row["lineage_evidence"] for row in moved))

    def test_rename_produces_lineage(self) -> None:
        before = discover_assets(self.root)
        source = self.root / "FlowTabTests/SampleTests.swift"
        destination = self.root / "FlowTabTests/RenamedTests.swift"
        source.rename(destination)
        after = discover_assets(self.root)
        deltas = build_deltas(before, after)
        renamed = [row for row in deltas if row["change_kind"] == "renamed"]
        self.assertEqual(len(renamed), 1)
        self.assertEqual(renamed[0]["before_ref"].split(":", 1)[0], "test_file")
        self.assertTrue(renamed[0]["lineage_evidence"])
        self.assertEqual(renamed[0]["lineage_basis"], "unique_type_and_fingerprint")
        self.assertEqual(renamed[0]["lineage_confidence"], "inferred")

    def test_ambiguous_fingerprint_does_not_infer_lineage(self) -> None:
        self._write("docs/fixtures/duplicate-a.json", "{}\n")
        self._write("docs/fixtures/duplicate-b.json", "{}\n")
        before = discover_assets(self.root)
        (self.root / "docs/fixtures/duplicate-a.json").rename(
            self.root / "docs/fixtures/duplicate-c.json"
        )
        (self.root / "docs/fixtures/duplicate-b.json").rename(
            self.root / "docs/fixtures/duplicate-d.json"
        )
        after = discover_assets(self.root)
        deltas = build_deltas(before, after)
        inferred_lineage = [
            row
            for row in deltas
            if row["change_kind"] in {"moved", "renamed"}
        ]
        self.assertEqual(inferred_lineage, [])
        unresolved = [row for row in deltas if row["lineage_confidence"] == "unresolved"]
        self.assertEqual(len(unresolved), 4)
        self.assertTrue(all(row["lineage_candidates"] for row in unresolved))

    def test_asset_observes_assertions_without_product_claims(self) -> None:
        declaration = next(
            row
            for row in discover_assets(self.root)
            if row["asset_type"] == "test_declaration"
            and row["asset_locator"]["qualified_symbol"] == "SampleTests.testFixtureBackedBehavior"
        )
        semantics = declaration["observed_test_semantics"]
        self.assertEqual(semantics["extraction_status"], "references_only")
        self.assertTrue(semantics["assertion_refs"])
        self.assertNotIn("protected_behavior", declaration)
        self.assertNotIn("oracle", declaration)

    def test_requiredness_is_rejected_from_asset_records(self) -> None:
        asset = next(row for row in discover_assets(self.root) if row["asset_type"] == "test_file")
        asset["requiredness"] = "required"
        with self.assertRaises(RecordValidationError):
            validate_record(asset, "test_asset")

    def test_required_ui_status_aggregation(self) -> None:
        source_ref = {
            "resource_boundary": "repository_root",
            "relative_path_intent": "FlowTabUITests/VisibleTests.swift",
            "line": 4,
            "qualified_symbol": "VisibleTests.testVisibleResult",
        }

        def plan(row_id: str, requiredness: str) -> dict[str, object]:
            return {
                "record_kind": "validation_plan_row",
                "record_lifecycle": "transient",
                "scope_kind": "task",
                "plan_row_id": row_id,
                "scope_id": "ui-scope",
                "asset_id": None,
                "scenario_ref": {"statement": "Visible result", "source_refs": [source_ref]},
                "requiredness": requiredness,
                "layer": "ui_real_topology",
                "runner_ref": None,
                "prerequisite_refs": [],
                "protected_behavior": {
                    "statement": "The result is visible",
                    "status": "confirmed",
                    "source_refs": [source_ref],
                },
                "oracle": {
                    "kind": "explicit_input",
                    "status": "valid",
                    "evidence_refs": [source_ref],
                    "independence_basis": "Explicit fixture input",
                },
                "provenance": [source_ref],
            }

        def observation(row_id: str, status: str) -> dict[str, object]:
            return {
                "record_kind": "execution_observation",
                "attempt_id": f"attempt-{row_id}",
                "plan_row_id": row_id,
                "execution_status": status,
                "evidence_refs": [source_ref],
                "environment_identity": {"toolchain": "fixture"},
                "blocked_reason": "permission" if status == "blocked" else None,
                "started_at": None,
            }

        plans = [plan("required-pass", "required"), plan("required-block", "required"), plan("optional-fail", "optional")]
        observations = [
            observation("required-pass", "passed"),
            observation("required-block", "blocked"),
            observation("optional-fail", "failed"),
        ]
        self.assertEqual(aggregate_required_status(plans, observations), "blocked")
        self.assertEqual(aggregate_required_status([plan("na", "not_applicable")], []), "not relevant")
        references = record_references(plans, "validation_plan_row", ["required-pass"])
        self.assertEqual(references["source_record_kind"], "validation_plan_row")
        self.assertEqual(references["records"][0]["record_id"], "required-pass")
        self.assertRegex(references["records"][0]["sha256"], r"^sha256:[0-9a-f]{64}$")
        for unresolved_status in ("flaky", "skipped", "unknown"):
            with self.subTest(status=unresolved_status), self.assertRaises(RecordValidationError):
                aggregate_required_status(
                    [plan(unresolved_status, "required")],
                    [observation(unresolved_status, unresolved_status)],
                )


if __name__ == "__main__":
    unittest.main()
