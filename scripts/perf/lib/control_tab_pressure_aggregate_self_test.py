#!/usr/bin/env python3

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from control_tab_pressure_contract_schema import environment_identity


ROOT = Path(__file__).resolve().parent


def load_cli_module():
    spec = importlib.util.spec_from_file_location(
        "control_tab_pressure_evidence_cli",
        ROOT / "control-tab-pressure-evidence.py",
    )
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def attempt(*, open_p95: float, complete: bool) -> dict:
    categories = {
        name: {"verdict": "passed" if complete else "failed"}
        for name in (
            "correctness", "latency", "cpu", "rss", "evidence", "cleanup",
            "product_slo",
        )
    }
    phases = {
        name: {
            "wall_ms": {
                "p50": open_p95 / 2,
                "p95": open_p95,
                "max": open_p95 * 2,
            },
            "cpu_time_ms": {
                "p50": open_p95 / 4,
                "p95": open_p95 / 2,
                "max": open_p95,
            },
            "cpu_percent": 10.0,
        }
        for name in ("open", "forward", "reverse", "commit", "cancel", "cooldown")
    }
    return {
        "identity": {
            **environment_identity("mutation", "closed-panel"),
            "machine": "machine",
            "system": "system",
            "architecture": "arm64",
            "build_configuration": "Release",
            "lane": "mutation",
            "scenario": "closed-panel",
        },
        "overall_verdict": "passed" if complete else "failed",
        "categories": categories,
        "active_cpu": {"avg": 1.0, "p95": 2.0, "max": 3.0} if complete else None,
        "cooldown_cpu": {"avg": 0.1, "p95": 0.2, "max": 0.3} if complete else None,
        "rss": {"p95": 100.0} if complete else None,
        "rss_plateau_growth_kb": 5.0 if complete else 0.0,
        "throughput_per_second": 4.0 if complete else 0.0,
        "phases": phases if complete else {},
    }


class AggregateEvidenceTests(unittest.TestCase):
    def test_incomplete_attempt_fails_without_discarding_complete_medians(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            documents = [attempt(open_p95=10.0, complete=True),
                         attempt(open_p95=0.0, complete=False),
                         attempt(open_p95=30.0, complete=True)]
            documents[1]["identity"] = {
                "lane": "mutation", "scenario": "closed-panel"
            }
            paths = []
            for index, document in enumerate(documents):
                path = root / f"attempt-{index}.json"
                path.write_text(json.dumps(document), encoding="utf-8")
                paths.append(str(path))
            output = root / "summary.json"
            status = load_cli_module().aggregate_command(SimpleNamespace(
                attempt_summary=paths,
                baseline_summary=None,
                output=str(output),
                summary=str(root / "summary.txt"),
            ))
            result = json.loads(output.read_text(encoding="utf-8"))

        self.assertEqual(status, 1)
        self.assertEqual(result["overall_verdict"], "failed")
        self.assertEqual(result["aggregated_attempt_count"], 2)
        self.assertFalse(result["attempts_aggregatable"])
        self.assertFalse(result["attempts_compatible"])
        self.assertTrue(result["aggregatable_attempts_compatible"])
        self.assertEqual(result["medians"]["phases"]["open"]["p50_wall_ms"], 10.0)
        self.assertEqual(result["medians"]["phases"]["open"]["p95_wall_ms"], 20.0)
        self.assertEqual(result["medians"]["phases"]["open"]["max_wall_ms"], 40.0)
        self.assertEqual(
            result["medians"]["phases"]["open"]["p50_cpu_time_ms"], 5.0
        )
        self.assertEqual(
            result["medians"]["phases"]["open"]["p95_cpu_time_ms"], 10.0
        )
        self.assertEqual(
            result["medians"]["phases"]["open"]["max_cpu_time_ms"], 20.0
        )
        self.assertFalse(result["baseline_eligible"])


if __name__ == "__main__":
    unittest.main()
