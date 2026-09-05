#!/usr/bin/env python3
from __future__ import annotations

import re
import unittest
from pathlib import Path

from control_tab_pressure_contract_schema import compatible_identity, environment_identity
from control_tab_pressure_span_schema import COMPONENT_NAMES, PROTOCOL_VERSION, REQUIRED_COMPONENTS, SCHEMA, SCHEMA_DIGEST, schema_failures


class ControlTabPressureSchemaTests(unittest.TestCase):
    root = Path(__file__).resolve().parents[3]

    def test_all_fifty_components_have_concrete_migration_boundaries(self):
        self.assertEqual(PROTOCOL_VERSION, 6)
        self.assertEqual(len(SCHEMA["components"]), 50)
        self.assertEqual(len(COMPONENT_NAMES), 50)
        self.assertEqual(len(SCHEMA["lifecycle_phases"]), 6)
        self.assertEqual(SCHEMA["reconciliation_tolerance_ms"], 0.5)
        for item in SCHEMA["components"]:
            for field in ("production_owner", "test_owner", "boundary", "parents", "work_units", "outcomes", "conditional_rule"):
                self.assertTrue(item[field], (item["name"], field))
            self.assertTrue((self.root / item["production_owner"]).is_file())
            self.assertTrue((self.root / item["test_owner"]).is_file())
            self.assertNotIn("TestingSupport", item["production_owner"])
            self.assertIn("TestingSupport", item["test_owner"])
            self.assertEqual(item["required_phases"], [phase for phase, names in REQUIRED_COMPONENTS.items() if item["name"] in names])

    def test_swift_component_and_required_phase_definitions_match(self):
        source = (self.root / "FlowTab/TestingSupport/SwitcherInteractionDiagnostics.swift").read_text()
        body = source.split("enum SwitcherInteractionComponent", 1)[1].split("enum SwitcherInteractionSpanOutcome", 1)[0]
        mapping = dict(re.findall(r'case\s+(\w+)\s*=\s*"([^"]+)"', body))
        self.assertEqual(mapping, {item["swift_case"]: item["name"] for item in SCHEMA["components"]})
        source = (self.root / "FlowTab/TestingSupport/ControlTabPressureSpanContract.swift").read_text()
        found = {}
        for phases, names in re.findall(r"case ([^:]+):\s*return \[([^]]*)\]", source):
            for phase in re.findall(r"\.(\w+)", phases):
                found[phase] = {mapping[name] for name in re.findall(r"\.(\w+)", names)}
        self.assertEqual(found, REQUIRED_COMPONENTS)

    def test_swift_recorder_uses_the_same_version_and_digest(self):
        source = (self.root / "FlowTabUITests/FlowTabUITests+ControlTabPressureMetricsRecorder.swift").read_text()
        self.assertEqual(int(re.search(r"static let protocolVersion = (\d+)", source)[1]), PROTOCOL_VERSION)
        self.assertEqual(re.search(r'static let schemaDigest\s*=\s*"([^"]+)"', source)[1], SCHEMA_DIGEST)

    def test_v5_evidence_and_baselines_remain_historical(self):
        current = environment_identity("ready", "realistic")
        historical = dict(current, protocol_version=5)
        self.assertFalse(compatible_identity(current, historical))
        self.assertFalse(compatible_identity(historical, historical))
        self.assertIn("protocol:1", schema_failures([dict(protocol_version="5", schema_digest=SCHEMA_DIGEST, sequence="1")]))


if __name__ == "__main__":
    unittest.main()
