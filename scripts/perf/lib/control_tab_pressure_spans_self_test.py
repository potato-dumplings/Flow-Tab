#!/usr/bin/env python3
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from control_tab_pressure_spans import span_summary
from control_tab_pressure_test_support import ControlTabPressureFixture


class ControlTabPressureSpanEvidenceTests(
    unittest.TestCase,
    ControlTabPressureFixture,
):
    def test_component_overlap_is_indexed_within_each_sequence(self):
        events = [
            {"cycle": "1", "sequence": "1", "phase": "open"},
            {"cycle": "1", "sequence": "2", "phase": "open"},
        ]

        def component(
            sequence: str,
            name: str,
            start: int,
            end: int,
        ) -> dict[str, str]:
            return {
                "sequence": sequence,
                "phase": "open",
                "span_scope": "component_inclusive",
                "metric_name": name,
                "span_started_uptime_nanoseconds": str(start),
                "span_completed_uptime_nanoseconds": str(end),
                "span_wall_ms": str((end - start) / 1_000_000),
                "span_cpu_time_ms": "0.1",
                "span_work_units": "1",
                "span_outcome": "completed",
            }

        spans = [
            component("1", "outer", 0, 10_000_000),
            component("1", "inner", 2_000_000, 4_000_000),
            component("2", "separate", 2_000_000, 4_000_000),
        ]

        result = span_summary(events, spans)["open"][
            "component_inclusive"
        ]

        self.assertTrue(result["outer"]["overlap"])
        self.assertTrue(result["inner"]["overlap"])
        self.assertFalse(result["separate"]["overlap"])

    def test_missing_required_component_keeps_evidence_non_green(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = self.write_fixture(root)

            def remove_projection_read(rows):
                return [
                    row
                    for row in rows
                    if not (
                        row.get("record_kind") == "span"
                        and row.get("phase") == "open"
                        and row.get("metric_name") == "projection_read"
                    )
                ]

            self.rewrite_metrics(paths[0], remove_projection_read)
            result = self.evaluate_paths(root, paths)
            self.assertEqual(result["overall_verdict"], "failed")
            self.assertTrue(
                result["categories"]["evidence"][
                    "missing_span_sequences"
                ]
            )

    def test_timeline_cpu_mismatch_keeps_evidence_non_green(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = self.write_fixture(root)

            def break_timeline_cpu(rows):
                changed = False
                for row in rows:
                    if (
                        not changed
                        and row.get("record_kind") == "span"
                        and row.get("span_scope") == "timeline_exclusive"
                    ):
                        row["span_cpu_time_ms"] = "9"
                        changed = True
                return rows

            self.rewrite_metrics(paths[0], break_timeline_cpu)
            result = self.evaluate_paths(root, paths)
            self.assertTrue(
                result["categories"]["evidence"][
                    "timeline_reconciliation_failure_sequences"
                ]
            )

    def test_phase_weighted_cpu_over_fifty_percent_fails_cpu_gate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = self.write_fixture(root)

            def raise_reverse_cpu(rows):
                for row in rows:
                    if (
                        row.get("record_kind") == "event"
                        and row.get("phase") == "reverse"
                    ):
                        row["cpu_time_ms"] = "6"
                return rows

            self.rewrite_metrics(paths[0], raise_reverse_cpu)
            result = self.evaluate_paths(root, paths)
            self.assertEqual(result["categories"]["cpu"]["verdict"], "failed")
            self.assertGreater(
                result["categories"]["cpu"]["phase_cpu_failures"][
                    "reverse"
                ],
                50,
            )

    def test_explicit_cache_hit_outcome_is_valid_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = self.write_fixture(root)

            def mark_cache_hits(rows):
                for row in rows:
                    if (
                        row.get("record_kind") == "span"
                        and row.get("metric_name") == "preview_capture"
                    ):
                        row["span_outcome"] = "cache_hit"
                return rows

            self.rewrite_metrics(paths[0], mark_cache_hits)
            result = self.evaluate_paths(root, paths)
            self.assertEqual(result["overall_verdict"], "passed")
            outcomes = result["spans"]["open"][
                "component_inclusive"
            ]["preview_capture"]["outcomes"]
            self.assertGreater(outcomes["cache_hit"], 0)

    def test_failed_preview_outcome_keeps_evidence_non_green(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = self.write_fixture(root)

            def fail_preview(rows):
                for row in rows:
                    if (
                        row.get("record_kind") == "span"
                        and row.get("phase") == "open"
                        and row.get("metric_name") == "preview_capture"
                    ):
                        row["span_outcome"] = "failed"
                        break
                return rows

            self.rewrite_metrics(paths[0], fail_preview)
            result = self.evaluate_paths(root, paths)
            self.assertEqual(result["overall_verdict"], "failed")
            self.assertTrue(
                result["categories"]["evidence"][
                    "invalid_span_outcome_sequences"
                ]
            )

    def test_timed_out_screenshot_outcome_keeps_evidence_non_green(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = self.write_fixture(root)

            def time_out_screenshot(rows):
                for row in rows:
                    if (
                        row.get("record_kind") == "span"
                        and row.get("phase") == "open"
                        and row.get("metric_name")
                        == "preview_screenshot_manager_capture"
                    ):
                        row["span_outcome"] = "timed_out"
                        break
                return rows

            self.rewrite_metrics(paths[0], time_out_screenshot)
            result = self.evaluate_paths(root, paths)
            self.assertEqual(result["overall_verdict"], "failed")
            self.assertTrue(
                result["categories"]["evidence"][
                    "invalid_span_outcome_sequences"
                ]
            )

    def test_malformed_span_schema_keeps_evidence_non_green(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = self.write_fixture(root)

            def corrupt_span(rows):
                for row in rows:
                    if row.get("record_kind") == "span":
                        row["span_cpu_time_ms"] = "invalid"
                        break
                return rows

            self.rewrite_metrics(paths[0], corrupt_span)
            result = self.evaluate_paths(root, paths)
            self.assertEqual(result["overall_verdict"], "failed")
            self.assertTrue(
                result["categories"]["evidence"][
                    "protocol_schema_failures"
                ]
            )


if __name__ == "__main__":
    unittest.main()
