#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DEFAULT_TEST="FlowTabUITests/FlowTabUITests/testSwitcherPanelOptionTabWindowStateRoundTripsFullscreenWorkflowSiblingAcrossSpacesWithNoisyCGSiblingsWithoutAppAXWindows"
SAMPLE_INTERVAL_SECONDS="${1:-0.5}"
TEST_FILTER="${2:-${DEFAULT_TEST}}"
RESULTS_ROOT="${ROOT_DIR}/.build-local/runtime-topology-pressure"
RESULTS_DIR="${RESULTS_ROOT}/results-$(date +%Y%m%d-%H%M%S)"
SAMPLES_FILE="${RESULTS_DIR}/flowtab-samples.csv"
SUMMARY_FILE="${RESULTS_DIR}/summary.txt"
UI_LOG_FILE="${RESULTS_DIR}/ui-test.log"

mkdir -p "${RESULTS_DIR}"

echo "sample,timestamp,pids,cpu_percent,rss_kb" >"${SAMPLES_FILE}"

sample_count=0

sample_flowtab() {
  local pids
  local cpu_sum
  local rss_sum
  local pid
  local line
  local cpu
  local rss
  local joined_pids

  pids="$(pgrep -x FlowTab || true)"
  if [[ -z "${pids}" ]]; then
    return
  fi

  cpu_sum="0"
  rss_sum="0"
  joined_pids="$(echo "${pids}" | tr '\n' ';' | sed 's/;$//')"

  while IFS= read -r pid; do
    [[ -n "${pid}" ]] || continue
    line="$(ps -p "${pid}" -o %cpu= -o rss= | awk '{$1=$1; print}')"
    [[ -n "${line}" ]] || continue
    cpu="$(awk '{print $1}' <<<"${line}")"
    rss="$(awk '{print $2}' <<<"${line}")"
    cpu_sum="$(awk -v a="${cpu_sum}" -v b="${cpu}" 'BEGIN { printf "%.2f", a + b }')"
    rss_sum="$(awk -v a="${rss_sum}" -v b="${rss}" 'BEGIN { printf "%.0f", a + b }')"
  done <<<"${pids}"

  sample_count=$((sample_count + 1))
  echo "${sample_count},$(date +%s),${joined_pids},${cpu_sum},${rss_sum}" >>"${SAMPLES_FILE}"
}

echo "[1/3] Starting runtime topology UI pressure: ${TEST_FILTER}"
echo "Results: ${RESULTS_DIR}"

"${ROOT_DIR}/scripts/testing/run-ui-tests-local.sh" "-only-testing:${TEST_FILTER}" >"${UI_LOG_FILE}" 2>&1 &
TEST_PID=$!

echo "[2/3] Sampling FlowTab CPU/RSS every ${SAMPLE_INTERVAL_SECONDS}s..."
while kill -0 "${TEST_PID}" 2>/dev/null; do
  sample_flowtab
  sleep "${SAMPLE_INTERVAL_SECONDS}"
done

TEST_STATUS=0
wait "${TEST_PID}" || TEST_STATUS=$?

echo "[3/3] Aggregating samples..."
/usr/bin/python3 - "${SAMPLES_FILE}" "${SUMMARY_FILE}" "${SAMPLE_INTERVAL_SECONDS}" "${TEST_FILTER}" "${TEST_STATUS}" <<'PY'
import csv
import math
import sys

samples_path, summary_path, sample_interval, test_filter, ui_test_status = sys.argv[1:6]

with open(samples_path, newline="", encoding="utf-8") as handle:
    rows = list(csv.DictReader(handle))

if not rows:
    raise SystemExit("No FlowTab samples collected.")

cpu_values = [float(row["cpu_percent"]) for row in rows]
rss_kb_values = [float(row["rss_kb"]) for row in rows]

def percentile(values, pct):
    ordered = sorted(values)
    if not ordered:
        return 0.0
    index = math.ceil((pct / 100.0) * len(ordered)) - 1
    index = max(0, min(index, len(ordered) - 1))
    return ordered[index]

summary = [
    "Runtime topology pressure summary",
    f"test={test_filter}",
    f"uiTestStatus={ui_test_status}",
    f"sampleIntervalSeconds={sample_interval}",
    f"samples={len(rows)}",
    f"cpuAvg={sum(cpu_values) / len(cpu_values):.2f}",
    f"cpuP95={percentile(cpu_values, 95):.2f}",
    f"cpuMax={max(cpu_values):.2f}",
    f"rssAvgMB={(sum(rss_kb_values) / len(rss_kb_values)) / 1024.0:.2f}",
    f"rssP95MB={percentile(rss_kb_values, 95) / 1024.0:.2f}",
    f"rssMaxMB={max(rss_kb_values) / 1024.0:.2f}",
]

with open(summary_path, "w", encoding="utf-8") as handle:
    handle.write("\n".join(summary))
    handle.write("\n")

print("\n".join(summary))
PY

echo "Samples: ${SAMPLES_FILE}"
echo "Summary: ${SUMMARY_FILE}"

if [[ "${TEST_STATUS}" -ne 0 ]]; then
  echo "UI pressure test failed; tailing ${UI_LOG_FILE}" >&2
  tail -n 80 "${UI_LOG_FILE}" >&2
  exit "${TEST_STATUS}"
fi
