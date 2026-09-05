#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PYTHON_CACHE="${ROOT_DIR}/.build-local/control-tab-pressure/python-cache"

PYTHONPYCACHEPREFIX="${PYTHON_CACHE}" \
  /usr/bin/python3 -m py_compile \
    "${ROOT_DIR}/scripts/perf/lib/control-tab-pressure-evidence.py" \
    "${ROOT_DIR}/scripts/perf/lib/control_tab_pressure_baseline.py" \
    "${ROOT_DIR}/scripts/perf/lib/control_tab_pressure_baseline_self_test.py" \
    "${ROOT_DIR}/scripts/perf/lib/control_tab_pressure_breakdown.py" \
    "${ROOT_DIR}/scripts/perf/lib/control_tab_pressure_breakdown_self_test.py" \
    "${ROOT_DIR}/scripts/perf/lib/control_tab_pressure_contract.py" \
    "${ROOT_DIR}/scripts/perf/lib/control_tab_pressure_contract_schema.py" \
    "${ROOT_DIR}/scripts/perf/lib/control_tab_pressure_metrics.py" \
    "${ROOT_DIR}/scripts/perf/lib/control_tab_pressure_proofs.py" \
    "${ROOT_DIR}/scripts/perf/lib/control_tab_pressure_span_schema.py" \
    "${ROOT_DIR}/scripts/perf/lib/control_tab_pressure_spans.py" \
    "${ROOT_DIR}/scripts/perf/lib/control_tab_pressure_spans_self_test.py" \
    "${ROOT_DIR}/scripts/perf/lib/control_tab_pressure_aggregate_self_test.py" \
    "${ROOT_DIR}/scripts/perf/lib/control_tab_pressure_evidence_self_test.py" \
    "${ROOT_DIR}/scripts/perf/lib/control_tab_pressure_proofs_self_test.py" \
    "${ROOT_DIR}/scripts/perf/lib/control_tab_pressure_test_support.py"
PYTHONDONTWRITEBYTECODE=1 \
  /usr/bin/python3 \
    "${ROOT_DIR}/scripts/perf/lib/control_tab_pressure_evidence_self_test.py"
PYTHONDONTWRITEBYTECODE=1 \
  /usr/bin/python3 \
    "${ROOT_DIR}/scripts/perf/lib/control_tab_pressure_baseline_self_test.py"
PYTHONDONTWRITEBYTECODE=1 \
  /usr/bin/python3 \
    "${ROOT_DIR}/scripts/perf/lib/control_tab_pressure_proofs_self_test.py"
PYTHONDONTWRITEBYTECODE=1 \
  /usr/bin/python3 \
    "${ROOT_DIR}/scripts/perf/lib/control_tab_pressure_aggregate_self_test.py"
PYTHONDONTWRITEBYTECODE=1 \
  /usr/bin/python3 \
    "${ROOT_DIR}/scripts/perf/lib/control_tab_pressure_breakdown_self_test.py"
PYTHONDONTWRITEBYTECODE=1 \
  /usr/bin/python3 \
    "${ROOT_DIR}/scripts/perf/lib/control_tab_pressure_spans_self_test.py"
PYTHONDONTWRITEBYTECODE=1 \
  /usr/bin/python3 \
    "${ROOT_DIR}/scripts/perf/lib/control_tab_pressure_schema_self_test.py"
bash -n "${ROOT_DIR}/scripts/perf/control-tab-pressure.sh"
aggregate_invocations="$(
  rg -c '^  /usr/bin/python3 "\$\{EVIDENCE_TOOL\}" aggregate' \
    "${ROOT_DIR}/scripts/perf/control-tab-pressure.sh"
)"
if [[ "${aggregate_invocations}" -ne 1 ]]; then
  echo "Control+Tab runner must contain one scenario aggregate command." >&2
  exit 1
fi
permission_preflight_invocations="$(
  rg -c '^  "-only-testing:\$\{PERMISSION_PREFLIGHT_TEST\}"$' \
    "${ROOT_DIR}/scripts/perf/control-tab-pressure.sh"
)"
if [[ "${permission_preflight_invocations}" -ne 1 ]]; then
  echo "Control+Tab runner must execute one permission-preflight XCTest before the matrix." >&2
  exit 1
fi
permission_preflight_line="$(
  rg -n '^CURRENT_STAGE="permission-preflight"$' \
    "${ROOT_DIR}/scripts/perf/control-tab-pressure.sh" \
    | cut -d: -f1
)"
scenario_loop_line="$(
  rg -n '^for specification in "\$\{SCENARIOS\[@\]\}"; do$' \
    "${ROOT_DIR}/scripts/perf/control-tab-pressure.sh" \
    | cut -d: -f1
)"
if [[ -z "${permission_preflight_line}" \
  || -z "${scenario_loop_line}" \
  || "${permission_preflight_line}" -ge "${scenario_loop_line}" ]]
then
  echo "Control+Tab permission preflight must complete before scenario execution." >&2
  exit 1
fi
"${ROOT_DIR}/scripts/perf/control-tab-pressure.sh" --help >/dev/null
if "${ROOT_DIR}/scripts/perf/control-tab-pressure.sh" \
  --attribution --duration-seconds 29 >/dev/null 2>&1
then
  echo "Control+Tab runner accepted an attribution duration below 30s." >&2
  exit 1
fi
if "${ROOT_DIR}/scripts/perf/control-tab-pressure.sh" \
  --duration-seconds 119 >/dev/null 2>&1
then
  echo "Control+Tab runner accepted a formal duration below 120s." >&2
  exit 1
fi
echo "Control+Tab pressure evidence and runner contracts passed."
