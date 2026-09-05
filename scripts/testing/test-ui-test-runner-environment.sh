#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RUN_SCRIPT_PATH="${ROOT_DIR}/scripts/testing/run-ui-tests-local.sh"
PRESSURE_SCRIPT_PATH="${ROOT_DIR}/scripts/perf/control-tab-pressure.sh"
RECORDER_MODE_KEY="FLOWTAB_CONTROL_TAB_RECORDER_MODE"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

bash -n "${RUN_SCRIPT_PATH}"
bash -n "${PRESSURE_SCRIPT_PATH}"

/usr/bin/grep -Fq \
  "${RECORDER_MODE_KEY}=\"\${RECORDER_MODE}\"" \
  "${PRESSURE_SCRIPT_PATH}" \
  || fail "pressure wrapper does not export ${RECORDER_MODE_KEY}"

/usr/bin/awk -v key="${RECORDER_MODE_KEY}" '
  /for environment_name in/ { in_environment_list = 1 }
  in_environment_list && index($0, key) { found = 1 }
  in_environment_list && /^  do$/ { exit }
  END { exit found ? 0 : 1 }
' "${RUN_SCRIPT_PATH}" \
  || fail "UI test runner environment does not propagate ${RECORDER_MODE_KEY}"

echo "UI test runner environment contract tests passed."
