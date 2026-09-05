#!/usr/bin/env python3
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

from control_tab_pressure_contract import compatible_identity, median_attempts
from control_tab_pressure_test_support import (
    ControlTabPressureFixture,
    load_cli_module,
)


class ControlTabPressureBaselineTests(
    ControlTabPressureFixture,
    unittest.TestCase,
):
    def test_baseline_identity_and_five_percent_regression(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.evaluate(Path(directory))
        medians = median_attempts([result, result, result])
        self.assertTrue(compatible_identity(result["identity"], dict(result["identity"])))
        baseline = json.loads(json.dumps(medians))
        baseline["active_cpu_avg"] = medians["active_cpu_avg"] / 1.06
        baseline["phases"]["open"]["p95_cpu_time_ms"] = (
            medians["phases"]["open"]["p95_cpu_time_ms"] / 1.06
        )
        regressions = load_cli_module().regression_map(medians, baseline)
        self.assertIn("active_cpu_avg", regressions)
        self.assertIn("phase.open.p95_cpu_time_ms", regressions)

    def test_incompatible_baseline_is_not_selected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = self.evaluate(root)
            incompatible = {
                "overall_verdict": "passed",
                "attempt_count": 3,
                "identity": dict(result["identity"]),
                "medians": median_attempts([result, result, result]),
            }
            incompatible["identity"]["architecture"] = "different"
            baseline = root / "baseline.json"
            baseline.write_text(json.dumps(incompatible), encoding="utf-8")
            candidate = load_cli_module().baseline_candidate(
                baseline,
                result["identity"],
            )
        self.assertIsNone(candidate)

    def test_single_attempt_baseline_is_not_selected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = self.evaluate(root)
            baseline = root / "baseline.json"
            baseline.write_text(
                json.dumps({
                    "overall_verdict": "passed",
                    "attempt_count": 1,
                    "identity": result["identity"],
                    "medians": median_attempts([result]),
                }),
                encoding="utf-8",
            )
            candidate = load_cli_module().baseline_candidate(
                baseline,
                result["identity"],
            )
        self.assertIsNone(candidate)

    def test_single_attempt_aggregate_is_not_recorded_as_baseline(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = self.evaluate(root)
            attempt = root / "attempt.json"
            output = root / "aggregate.json"
            summary = root / "aggregate.txt"
            attempt.write_text(json.dumps(result), encoding="utf-8")
            status = load_cli_module().aggregate_command(
                SimpleNamespace(
                    attempt_summary=[str(attempt)],
                    baseline_summary=None,
                    output=str(output),
                    summary=str(summary),
                )
            )
            aggregate = json.loads(output.read_text(encoding="utf-8"))
        self.assertEqual(status, 0)
        self.assertFalse(aggregate["baseline_eligible"])
        self.assertEqual(
            aggregate["baseline"]["verdict"],
            "not_recorded_attempt_count",
        )

    def test_complete_failed_attempts_still_publish_medians(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = self.evaluate(root)
            result["overall_verdict"] = "failed"
            result["categories"]["latency"]["verdict"] = "failed"
            attempt = root / "attempt.json"
            output = root / "aggregate.json"
            attempt.write_text(json.dumps(result), encoding="utf-8")
            load_cli_module().aggregate_command(
                SimpleNamespace(
                    attempt_summary=[str(attempt)] * 3,
                    baseline_summary=None,
                    output=str(output),
                    summary=str(root / "aggregate.txt"),
                )
            )
            aggregate = json.loads(output.read_text(encoding="utf-8"))
        self.assertEqual(aggregate["overall_verdict"], "failed")
        self.assertTrue(aggregate["attempts_aggregatable"])
        self.assertIn("cooldown", aggregate["medians"]["phases"])
        self.assertFalse(aggregate["baseline_eligible"])


if __name__ == "__main__":
    unittest.main()
