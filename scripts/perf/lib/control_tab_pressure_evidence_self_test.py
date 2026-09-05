#!/usr/bin/env python3
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from control_tab_pressure_contract import evaluate_attempt, percentile
from control_tab_pressure_test_support import ControlTabPressureFixture


class ControlTabPressureEvidenceTests(
    ControlTabPressureFixture,
    unittest.TestCase,
):
    def test_percentile_uses_nearest_rank(self):
        self.assertEqual(percentile([1, 2, 3, 4, 5], 0.95), 5)

    def test_complete_attempt_passes_all_categories(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.evaluate(Path(directory))
        self.assertEqual(result["overall_verdict"], "passed")
        self.assertGreaterEqual(result["categories"]["evidence"]["active_coverage"], 0.90)
        self.assertEqual(
            set(result["phases"]),
            {"open", "forward", "reverse", "commit", "cancel", "cooldown"},
        )

    def test_path_summary_splits_presentation_activation_and_readback(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.evaluate(Path(directory))
        self.assertEqual(
            result["paths"]["open"]["derived"]
            ["first_visible_after_panel_ms"]["p95"],
            2.0,
        )
        self.assertEqual(
            result["paths"]["commit"]["derived"]
            ["activation_request_to_command_return_ms"]["p95"],
            2.0,
        )
        self.assertEqual(
            result["paths"]["forward"]["derived"]
            ["readback_after_command_ms"]["p95"],
            2.0,
        )

    def test_product_slo_reports_first_frame_cpu_failure_separately(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = self.write_fixture(root)

            def increase_first_frame_cpu(rows):
                for row in rows:
                    if row.get("metric_name") == (
                        "cached_first_frame_cpu_time_ms"
                    ):
                        row["metric_ms"] = "4"
                return rows

            self.rewrite_metrics(paths[0], increase_first_frame_cpu)
            result = self.evaluate_paths(root, paths)
        self.assertEqual(result["categories"]["latency"]["verdict"], "passed")
        self.assertEqual(result["categories"]["product_slo"]["verdict"], "failed")
        self.assertEqual(
            result["categories"]["product_slo"]["failures"]
            ["cached_first_frame_cpu_time_p95_ms"],
            {"observed": 4.0, "limit": 3.0},
        )

    def test_raw_path_reconciliation_failure_keeps_evidence_non_green(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = self.write_fixture(root)

            def break_open_partition_sum(rows):
                for row in rows:
                    if (
                        row.get("metric_kind") == "partition"
                        and row.get("phase") == "open"
                        and row.get("metric_name") == "unattributed_ms"
                    ):
                        row["metric_ms"] = "4"
                        break
                return rows

            self.rewrite_metrics(paths[0], break_open_partition_sum)
            result = self.evaluate_paths(root, paths)
        self.assertEqual(result["overall_verdict"], "failed")
        self.assertTrue(
            result["categories"]["evidence"]
            ["path_reconciliation_failure_sequences"]
        )

    def test_missing_command_path_metric_fails_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = self.write_fixture(root)
            self.rewrite_metrics(
                paths[0],
                lambda rows: [
                    row
                    for row in rows
                    if not (
                        row.get("phase") == "forward"
                        and row.get("metric_name") == "command_execution_ms"
                    )
                ],
            )
            result = self.evaluate_paths(root, paths)
        self.assertEqual(result["overall_verdict"], "failed")
        self.assertTrue(
            result["categories"]["evidence"]["path_metric_gap_sequences"]
        )

    def test_missing_samples_keeps_status_non_green(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.evaluate(Path(directory), samples=False)
        self.assertEqual(result["overall_verdict"], "failed")
        self.assertEqual(result["categories"]["evidence"]["verdict"], "failed")

    def test_absolute_latency_failure_is_reported(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.evaluate(Path(directory), slow_open=True)
        self.assertEqual(result["overall_verdict"], "failed")
        self.assertEqual(
            result["categories"]["latency"]["failures"],
            {"ready_open": 60.0},
        )

    def test_non_ready_open_is_reported_without_ready_latency_gate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = self.write_fixture(root, slow_open=True)
            result = evaluate_attempt(
                *paths,
                "topology",
                "noisy",
                1,
                5,
                identity_manifest_path=root / "ui-app-identity.json",
                target_launch_receipt_path=root / "target-launch-receipt.json",
                cleanup_evidence_path=root / "application-cleanup.json",
                sampler_readiness_path=root / "sampling-ready.json",
                result_bundle_path=root / "FlowTabUITests.xcresult",
            )
        self.assertNotIn(
            "ready_open",
            result["categories"]["latency"]["measurements_ms"],
        )

    def test_commit_gate_uses_activation_request_milestone(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = self.write_fixture(root)

            def slow_commit_completion(rows):
                for row in rows:
                    if row["record_kind"] == "event" and row["phase"] == "commit":
                        row["wall_ms"] = "250"
                return rows

            self.rewrite_metrics(paths[0], slow_commit_completion)
            result = self.evaluate_paths(root, paths)
        self.assertNotIn(
            "commit_activation_request",
            result["categories"]["latency"]["failures"],
        )
        self.assertEqual(
            result["phases"]["commit"]["activation_request_ms"]["p95"],
            4.0,
        )

    def test_slow_activation_request_fails_commit_gate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = self.write_fixture(root)

            def slow_activation_request(rows):
                for row in rows:
                    if row.get("metric_name") == "activation_request_ms":
                        row["metric_ms"] = "60"
                return rows

            self.rewrite_metrics(paths[0], slow_activation_request)
            result = self.evaluate_paths(root, paths)
        self.assertEqual(
            result["categories"]["latency"]["failures"],
            {"commit_activation_request": 60.0},
        )

    def test_missing_activation_request_metric_fails_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = self.write_fixture(root)
            self.rewrite_metrics(
                paths[0],
                lambda rows: [
                    row
                    for row in rows
                    if row.get("metric_name") != "activation_request_ms"
                ],
            )
            result = self.evaluate_paths(root, paths)
        self.assertEqual(result["categories"]["latency"]["verdict"], "failed")
        self.assertEqual(result["categories"]["evidence"]["verdict"], "failed")
        self.assertTrue(
            result["categories"]["evidence"]["commit_metric_gap_sequences"]
        )

    def test_invalid_timing_keeps_evidence_non_green(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = self.write_fixture(root)

            def invalidate_timing(rows):
                event = next(
                    row
                    for row in rows
                    if row["record_kind"] == "event" and int(row["cycle"]) > 0
                )
                event["timing_valid"] = "0"
                return rows

            self.rewrite_metrics(paths[0], invalidate_timing)
            result = self.evaluate_paths(root, paths)
        self.assertEqual(result["overall_verdict"], "failed")
        self.assertEqual(result["categories"]["evidence"]["verdict"], "failed")
        self.assertTrue(
            result["categories"]["evidence"]["invalid_timing_sequences"]
        )

    def test_late_presentation_keeps_correctness_non_green(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = self.write_fixture(root)

            def report_late_presentation(rows):
                event = next(
                    row
                    for row in rows
                    if row["record_kind"] == "event" and row["phase"] == "cancel"
                )
                event["late_presentation_observed"] = "1"
                return rows

            self.rewrite_metrics(paths[0], report_late_presentation)
            result = self.evaluate_paths(root, paths)
        self.assertEqual(result["overall_verdict"], "failed")
        self.assertEqual(result["categories"]["correctness"]["verdict"], "failed")
        self.assertTrue(
            result["categories"]["correctness"]["late_presentation_sequences"]
        )

    def test_missing_required_proof_keeps_correctness_non_green(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = self.write_fixture(root)
            self.rewrite_metrics(
                paths[0],
                lambda rows: [
                    row
                    for row in rows
                    if row.get("proof_kind") != "physical_shortcut"
                ],
            )
            result = self.evaluate_paths(root, paths)
        self.assertEqual(result["overall_verdict"], "failed")
        self.assertEqual(
            result["categories"]["correctness"]["missing_proofs"],
            ["physical_shortcut"],
        )

    def test_failed_permission_proof_reports_blocked(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = self.write_fixture(root)

            def permission(rows):
                proof = next(row for row in rows if row["record_kind"] == "proof")
                proof["proof_kind"] = "permission"
                proof["proof_satisfied"] = "0"
                return rows

            self.rewrite_metrics(paths[0], permission)
            result = self.evaluate_paths(root, paths)
        self.assertEqual(result["overall_verdict"], "blocked")
        self.assertTrue(result["permission_blocked"])

    def test_runtime_failure_status_keeps_evidence_non_green(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = self.write_fixture(root)
            status = json.loads(paths[2].read_text(encoding="utf-8"))
            status["final_exit_code"] = 65
            paths[2].write_text(json.dumps(status), encoding="utf-8")
            result = self.evaluate_paths(root, paths)
        self.assertEqual(result["overall_verdict"], "failed")
        self.assertEqual(result["categories"]["evidence"]["verdict"], "failed")

    def test_missing_sampler_readiness_keeps_evidence_non_green(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = self.write_fixture(root)
            status = json.loads(paths[2].read_text(encoding="utf-8"))
            status["sampling_readiness_present"] = False
            paths[2].write_text(json.dumps(status), encoding="utf-8")
            result = self.evaluate_paths(root, paths)
        self.assertEqual(result["overall_verdict"], "failed")
        self.assertEqual(result["categories"]["evidence"]["verdict"], "failed")

    def test_missing_identity_manifest_keeps_evidence_non_green(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = self.write_fixture(root)
            (root / "ui-app-identity.json").unlink()
            result = self.evaluate_paths(root, paths)
        self.assertEqual(result["overall_verdict"], "failed")
        self.assertFalse(
            result["categories"]["evidence"]["identity_manifest_present"]
        )

    def test_missing_target_launch_receipt_keeps_evidence_non_green(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = self.write_fixture(root)
            (root / "target-launch-receipt.json").unlink()
            result = self.evaluate_paths(root, paths)
        self.assertEqual(result["overall_verdict"], "failed")
        self.assertFalse(
            result["categories"]["evidence"]["target_launch_receipt_present"]
        )


if __name__ == "__main__":
    unittest.main()
