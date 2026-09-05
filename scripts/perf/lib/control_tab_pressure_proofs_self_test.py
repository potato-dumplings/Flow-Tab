#!/usr/bin/env python3
from __future__ import annotations

import unittest

from control_tab_pressure_proofs import (
    exact_activation_coverage,
    validate_proofs,
)


class ControlTabPressureProofTests(unittest.TestCase):
    @staticmethod
    def exact_activation(window: int) -> dict[str, str]:
        return {
            "proof_kind": "exact_activation",
            "proof_satisfied": "1",
            "proof_pid": "42",
            "proof_window_id": f"window-{window}",
            "proof_cg_window_id": str(100 + window),
            "proof_detail": (
                f"title=Window {window};target-pid,window-id,"
                "cg-window-id,verified-focus-readback"
            ),
        }

    def test_direct_sampler_proof_is_rejected(self):
        valid, invalid, _ = validate_proofs([
            {
                "proof_kind": "sampler_readiness",
                "proof_satisfied": "1",
                "proof_pid": "0",
                "proof_detail": "direct-ui-run",
            }
        ])
        self.assertNotIn("sampler_readiness", valid)
        self.assertEqual(invalid, ["sampler_readiness"])

    def test_mutation_generation_replay_is_rejected(self):
        proofs = []
        for generation in (1, 2, 2):
            proofs.append({
                "proof_kind": "mutation_generation",
                "proof_satisfied": "1",
                "proof_generation": str(generation),
                "proof_pid": "42",
                "proof_window_id": "window-plan-3",
                "proof_cg_window_id": "123",
                "proof_detail": "action=open;windows=3",
            })
        valid, invalid, _ = validate_proofs(proofs)
        self.assertNotIn("mutation_generation", valid)
        self.assertIn("mutation_generation_order", invalid)

    def test_exact_activation_coverage_requires_every_window(self):
        incomplete = [
            self.exact_activation(window)
            for window in (1, 2, 1, 2)
        ]
        complete = [
            self.exact_activation(window)
            for window in (1, 2, 3, 4)
        ]

        self.assertEqual(
            exact_activation_coverage(incomplete, 4)["verdict"],
            "failed",
        )
        self.assertEqual(
            exact_activation_coverage(complete, 4)["verdict"],
            "passed",
        )


if __name__ == "__main__":
    unittest.main()
