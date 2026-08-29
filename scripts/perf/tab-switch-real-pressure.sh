#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
INVOCATION_DIRECTORY="$(pwd -P)"
INSTALLER="${ROOT_DIR}/scripts/testing/install-ui-test-app.sh"
UI_TEST_RUNNER="${ROOT_DIR}/scripts/testing/run-ui-tests-local.sh"
MANIFEST_CREATOR="${ROOT_DIR}/scripts/testing/create-ui-app-identity-manifest.sh"
PRESSURE_RUNNER="${ROOT_DIR}/scripts/perf/runtime-topology-pressure.sh"
EVIDENCE_TOOL="${ROOT_DIR}/scripts/perf/lib/tab-switch-real-pressure-evidence.py"
PATH_BOUNDARIES_PATH="${ROOT_DIR}/scripts/lib/path-boundaries.sh"
UI_TEST_APP_LIFECYCLE_PATH="${ROOT_DIR}/scripts/testing/lib/ui-test-app-lifecycle.sh"
APP_PATH="${HOME}/Applications/Flow Tab UITest.app"
DEFAULT_RESULTS_ROOT="${ROOT_DIR}/.build-local/tab-switch-real-pressure"
TEST_FILTER="FlowTabUITests/FlowTabUITests/testRealPermissionTabSwitchPressureGate"

DURATION_SECONDS=30
SWITCH_INTERVAL_MILLISECONDS=20
SAMPLE_INTERVAL_SECONDS=0.5
RUNTIME_LOG_LEVEL="ERROR"
MAX_RUNTIME_LOG_MB_PER_MINUTE=""
BUILD_ROOT="${ROOT_DIR}/.build-local/tab-switch-real-pressure-build"
OUTPUT_DIR=""
HAS_BUILD_ROOT=false
HAS_OUTPUT_DIR=false
FINAL_STATUS=0
ACTIVE_CHILD_PID=""

# shellcheck source=/dev/null
source "${PATH_BOUNDARIES_PATH}"
# shellcheck source=/dev/null
source "${UI_TEST_APP_LIFECYCLE_PATH}"

usage() {
  printf '%s\n' \
    'Usage: ./scripts/perf/tab-switch-real-pressure.sh [options]' \
    '' \
    'Runs the fixed-identity, real-permission Tab pressure gate.' \
    '' \
    'Options:' \
    '  --duration-seconds <seconds>       Active switching duration (default: 30).' \
    '  --switch-interval-ms <milliseconds> Tab-switch cadence (default: 20).' \
    '  --sample-interval <seconds>        CPU/RSS cadence (default: 0.5).' \
    '  --runtime-log-level <ERROR|DEBUG>  Runtime log level (default: ERROR).' \
    '  --max-runtime-log-mb-per-minute <positive-decimal>' \
    '                                      Optional retained-log budget.' \
    '  --build-root <dir>                 Reusable build and fixture root.' \
    '  --evidence-dir <dir>               New immutable evidence directory.' \
    '  -h, --help                         Show this help.'
}

resolve_invocation_path() {
  local path="$1"
  if [[ "${path}" == /* ]]; then
    printf '%s' "${path}"
  else
    printf '%s/%s' "${INVOCATION_DIRECTORY}" "${path#./}"
  fi
}

positive_number() {
  LC_ALL=C awk -v value="$1" \
    'BEGIN { exit !(value ~ /^[0-9]+([.][0-9]+)?$/ && value > 0) }'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --duration-seconds)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      DURATION_SECONDS="$2"
      shift 2
      ;;
    --switch-interval-ms)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      SWITCH_INTERVAL_MILLISECONDS="$2"
      shift 2
      ;;
    --sample-interval)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      SAMPLE_INTERVAL_SECONDS="$2"
      shift 2
      ;;
    --runtime-log-level)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      RUNTIME_LOG_LEVEL="$(printf '%s' "$2" | LC_ALL=C tr '[:lower:]' '[:upper:]')"
      shift 2
      ;;
    --max-runtime-log-mb-per-minute)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      MAX_RUNTIME_LOG_MB_PER_MINUTE="$2"
      shift 2
      ;;
    --build-root)
      if [[ "${HAS_BUILD_ROOT}" == true || $# -lt 2 || -z "$2" ]]; then
        echo "--build-root requires one value and may only be specified once." >&2
        exit 2
      fi
      BUILD_ROOT="$2"
      HAS_BUILD_ROOT=true
      shift 2
      ;;
    --evidence-dir)
      if [[ "${HAS_OUTPUT_DIR}" == true || $# -lt 2 || -z "$2" ]]; then
        echo "--evidence-dir requires one value and may only be specified once." >&2
        exit 2
      fi
      OUTPUT_DIR="$2"
      HAS_OUTPUT_DIR=true
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

positive_number "${DURATION_SECONDS}" || {
  echo "--duration-seconds must be positive." >&2
  exit 2
}
positive_number "${SWITCH_INTERVAL_MILLISECONDS}" || {
  echo "--switch-interval-ms must be positive." >&2
  exit 2
}
positive_number "${SAMPLE_INTERVAL_SECONDS}" || {
  echo "--sample-interval must be positive." >&2
  exit 2
}
case "${RUNTIME_LOG_LEVEL}" in
  ERROR|DEBUG) ;;
  *)
    echo "--runtime-log-level must be ERROR or DEBUG." >&2
    exit 2
    ;;
esac
if [[ -n "${MAX_RUNTIME_LOG_MB_PER_MINUTE}" ]]; then
  positive_number "${MAX_RUNTIME_LOG_MB_PER_MINUTE}" || {
    echo "--max-runtime-log-mb-per-minute must be positive." >&2
    exit 2
  }
fi

BUILD_ROOT="$(resolve_invocation_path "${BUILD_ROOT}")"
if [[ -z "${OUTPUT_DIR}" ]]; then
  mkdir -p "${DEFAULT_RESULTS_ROOT}"
  OUTPUT_DIR="${DEFAULT_RESULTS_ROOT}/run-$(date -u '+%Y%m%d-%H%M%S')"
else
  OUTPUT_DIR="$(resolve_invocation_path "${OUTPUT_DIR}")"
fi
if [[ -e "${OUTPUT_DIR}" ]]; then
  echo "Evidence directory must not already exist: ${OUTPUT_DIR}" >&2
  exit 2
fi
mkdir -p "${OUTPUT_DIR}"

INSTALLER_BUILD_ROOT="${BUILD_ROOT}/release-ui-app"
RUNTIME_BUILD_ROOT="${BUILD_ROOT}/runtime"
UI_BUILD_OUTPUT="${OUTPUT_DIR}/ui-test-build"
IDENTITY_MANIFEST="${OUTPUT_DIR}/ui-app-identity.json"
RUNTIME_HOME="${OUTPUT_DIR}/runtime-home"
UI_STATUS="${OUTPUT_DIR}/ui-status.json"
RUNTIME_OUTPUT="${OUTPUT_DIR}/runtime-pressure"
STATUS_PATH="${OUTPUT_DIR}/status.json"
SUMMARY_PATH="${OUTPUT_DIR}/summary.txt"
mkdir -p "${RUNTIME_HOME}"

cleanup() {
  local exit_status=$?
  trap - EXIT INT TERM
  if [[ -n "${ACTIVE_CHILD_PID}" ]] \
    && kill -0 "${ACTIVE_CHILD_PID}" 2>/dev/null; then
    kill -TERM "${ACTIVE_CHILD_PID}" 2>/dev/null || true
    wait "${ACTIVE_CHILD_PID}" 2>/dev/null || true
  fi
  if [[ -d "${APP_PATH}" ]]; then
    flowtab_ui_test_app_remove_managed_bundle \
      "${ROOT_DIR}" \
      "${HOME}" \
      "${APP_PATH}" >/dev/null 2>&1 || true
  fi
  if [[ "${FINAL_STATUS}" -ne 0 ]]; then
    exit "${FINAL_STATUS}"
  fi
  exit "${exit_status}"
}
trap cleanup EXIT INT TERM

echo "Preparing signed UI runner and fixed fixture variants..."
"${INSTALLER}" \
  --configuration Release \
  --include-testing-support \
  --build-root "${INSTALLER_BUILD_ROOT}"
"${UI_TEST_RUNNER}" \
  build-for-testing \
  --build-root "${RUNTIME_BUILD_ROOT}/ui-tests" \
  --output-root "${UI_BUILD_OUTPUT}"

echo "Installing the fixed-path App immediately before the real UI action..."
"${INSTALLER}" \
  --configuration Release \
  --include-testing-support \
  --build-root "${INSTALLER_BUILD_ROOT}"
"${MANIFEST_CREATOR}" \
  --app-path "${APP_PATH}" \
  --output-file "${IDENTITY_MANIFEST}"

echo "Running real-permission Tab pressure..."
set +e
FLOWTAB_TAB_SWITCH_REAL_DURATION_SECONDS="${DURATION_SECONDS}" \
FLOWTAB_TAB_SWITCH_REAL_INTERVAL_MILLISECONDS="${SWITCH_INTERVAL_MILLISECONDS}" \
FLOWTAB_TAB_SWITCH_REAL_RUNTIME_LOG_LEVEL="${RUNTIME_LOG_LEVEL}" \
FLOWTAB_TAB_SWITCH_REAL_HOME="${RUNTIME_HOME}" \
FLOWTAB_TAB_SWITCH_REAL_STATUS_PATH="${UI_STATUS}" \
  "${PRESSURE_RUNNER}" \
    "${SAMPLE_INTERVAL_SECONDS}" \
    "${TEST_FILTER}" \
    --ui-app-identity-manifest "${IDENTITY_MANIFEST}" \
    --reuse-ui-test-build \
    --build-root "${RUNTIME_BUILD_ROOT}" \
    --output-dir "${RUNTIME_OUTPUT}" &
ACTIVE_CHILD_PID=$!
wait "${ACTIVE_CHILD_PID}"
pressure_status=$?
ACTIVE_CHILD_PID=""
set -e

evidence_arguments=(
  evaluate
  --ui-status "${UI_STATUS}"
  --runtime-status "${RUNTIME_OUTPUT}/status.json"
  --samples "${RUNTIME_OUTPUT}/flowtab-samples.csv"
  --runtime-home "${RUNTIME_HOME}"
  --runtime-log-level "${RUNTIME_LOG_LEVEL}"
  --duration-seconds "${DURATION_SECONDS}"
  --interval-milliseconds "${SWITCH_INTERVAL_MILLISECONDS}"
  --runtime-exit-code "${pressure_status}"
  --output "${STATUS_PATH}"
  --summary "${SUMMARY_PATH}"
)
if [[ -n "${MAX_RUNTIME_LOG_MB_PER_MINUTE}" ]]; then
  evidence_arguments+=(
    --runtime-log-budget "${MAX_RUNTIME_LOG_MB_PER_MINUTE}"
  )
fi
set +e
/usr/bin/python3 "${EVIDENCE_TOOL}" "${evidence_arguments[@]}"
evidence_status=$?
set -e

if [[ "${pressure_status}" -ne 0 || "${evidence_status}" -ne 0 ]]; then
  FINAL_STATUS=1
fi
echo "FlowTab real Tab pressure evidence: ${OUTPUT_DIR}"
if [[ "${FINAL_STATUS}" -eq 0 ]]; then
  echo "FlowTab real-permission Tab pressure gate passed."
fi
