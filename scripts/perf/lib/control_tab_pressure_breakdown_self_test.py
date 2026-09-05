#!/usr/bin/env python3
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from control_tab_pressure_breakdown import (
    event_breakdowns,
    mutation_generation_evidence,
    topology_target_evidence,
)
from control_tab_pressure_contract import load_phase_metrics
from control_tab_pressure_test_support import ControlTabPressureFixture


class ControlTabPressureBreakdownTests(
    unittest.TestCase,
    ControlTabPressureFixture,
):
    def test_breakdown_keeps_scale_phase_and_components(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = self.write_fixture(Path(directory))
            events, _, _, _, spans, _ = load_phase_metrics(paths[0])
            breakdowns = event_breakdowns(events, spans, "ready")

        opened = next(item for item in breakdowns if item["phase"] == "open")
        self.assertEqual(opened["app_count"], 24)
        self.assertEqual(opened["window_count"], 5)
        self.assertEqual(opened["event_count"], 10)
        self.assertIn("preview_capture", opened["components"])

    def test_mutation_generations_keep_window_count_detail(self):
        evidence = mutation_generation_evidence(
            [
                {
                    "proof_kind": "mutation_generation",
                    "proof_generation": "3",
                    "proof_pid": "42",
                    "proof_detail": "action=close;windows=2",
                },
                {
                    "proof_kind": "mutation_generation",
                    "proof_generation": "4",
                    "proof_pid": "42",
                    "proof_detail": "action=open;windows=3",
                },
            ]
        )
        self.assertEqual([item["generation"] for item in evidence], [3, 4])
        self.assertEqual(
            [item["detail"] for item in evidence],
            ["action=close;windows=2", "action=open;windows=3"],
        )

    def test_topology_targets_keep_exact_activation_identity(self):
        events = [
            {
                "cycle": "1",
                "phase": "commit",
                "activation_verified": "1",
                "activation_target_pid": "42",
                "activation_target_window_id": f"window-{index}",
                "activation_target_cg_window_id": str(100 + index),
            }
            for index in range(1, 5)
        ]
        targets = topology_target_evidence(events)

        self.assertEqual(len(targets), 4)
        self.assertEqual({item["pid"] for item in targets}, {42})
        self.assertEqual(
            {item["cg_window_id"] for item in targets},
            {101, 102, 103, 104},
        )


if __name__ == "__main__":
    unittest.main()
