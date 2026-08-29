#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
INVOCATION_DIRECTORY="$(pwd -P)"
INSTALLER="${ROOT_DIR}/scripts/testing/install-ui-test-app.sh"
UI_TEST_RUNNER="${ROOT_DIR}/scripts/testing/run-ui-tests-local.sh"
MANIFEST_CREATOR="${ROOT_DIR}/scripts/testing/create-ui-app-identity-manifest.sh"
PRESSURE_RUNNER="${ROOT_DIR}/scripts/perf/runtime-topology-pressure.sh"
EVIDENCE_TOOL="${ROOT_DIR}/scripts/perf/lib/app-panel-pressure-evidence.py"
PATH_BOUNDARIES_PATH="${ROOT_DIR}/scripts/lib/path-boundaries.sh"
UI_TEST_APP_LIFECYCLE_PATH="${ROOT_DIR}/scripts/testing/lib/ui-test-app-lifecycle.sh"
APP_PATH="${HOME}/Applications/Flow Tab UITest.app"
DEFAULT_RESULTS_ROOT="${ROOT_DIR}/.build-local/app-panel-pressure"
TEST_FILTER="FlowTabUITests/FlowTabUITests/testApplicationPanelReleasePressureGate"

DURATION_SECONDS=120
ATTRIBUTION_RUN=false
COOLDOWN_SECONDS=15
SAMPLE_INTERVAL_SECONDS=0.5
BUILD_ROOT=""
OUTPUT_DIR=""
HAS_OUTPUT_DIR=false
HAS_BUILD_ROOT=false
SCENARIO_SELECTION="all"
FLOW_SELECTION="application"
ACTIVE_CHILD_PID=""
FINAL_STATUS=0

# shellcheck source=/dev/null
source "${PATH_BOUNDARIES_PATH}"
# shellcheck source=/dev/null
source "${UI_TEST_APP_LIFECYCLE_PATH}"

usage() {
  printf '%s\n' \
    'Usage: ./scripts/perf/app-panel-pressure.sh [options]' \
    '' \
    'Runs the Release-optimized real-NSPanel gate.' \
    '' \
    'Options:' \
    '  --flow <application|app-to-window|search>' \
    '                                    Select the real UI journey.' \
    '  --scenario <all|realistic|extreme|local>' \
    '                                    Select deterministic scenarios or the' \
    '                                    current live runtime (default: all).' \
    '  --duration-seconds <120-300>  Active open/switch/close duration per scenario.' \
    '  --attribution                Allow a 30-119s diagnostic attribution run.' \
    '  --cooldown-seconds <10-60>    Closed-panel CPU recovery window (default: 15).' \
    '  --sample-interval <seconds>   CPU/RSS cadence (default: 0.5).' \
    '  --build-root <dir>            Reusable build/cache root.' \
    '  --output-dir <dir>            New immutable evidence directory.' \
    '  -h, --help                    Show this help.' \
    '' \
    'Each scenario reinstalls the fixed-path UI app immediately before its UI action.'
}

resolve_invocation_path() {
  local path="$1"
  if [[ "${path}" == /* ]]; then
    printf '%s' "${path}"
  else
    printf '%s/%s' "${INVOCATION_DIRECTORY}" "${path#./}"
  fi
}

number_in_range() {
  local value="$1"
  local minimum="$2"
  local maximum="$3"
  LC_ALL=C awk \
    -v value="${value}" \
    -v minimum="${minimum}" \
    -v maximum="${maximum}" \
    'BEGIN { exit !(value ~ /^[0-9]+([.][0-9]+)?$/ && value >= minimum && value <= maximum) }'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --flow)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      FLOW_SELECTION="$2"
      shift 2
      ;;
    --scenario)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      SCENARIO_SELECTION="$2"
      shift 2
      ;;
    --duration-seconds)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      DURATION_SECONDS="$2"
      shift 2
      ;;
    --attribution)
      ATTRIBUTION_RUN=true
      shift
      ;;
    --cooldown-seconds)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      COOLDOWN_SECONDS="$2"
      shift 2
      ;;
    --sample-interval)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      SAMPLE_INTERVAL_SECONDS="$2"
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
    --output-dir)
      if [[ "${HAS_OUTPUT_DIR}" == true || $# -lt 2 || -z "$2" ]]; then
        echo "--output-dir requires one value and may only be specified once." >&2
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

if [[ "${ATTRIBUTION_RUN}" == true ]]; then
  number_in_range "${DURATION_SECONDS}" 30 300 || {
    echo "--duration-seconds must be between 30 and 300 for attribution runs." >&2
    exit 2
  }
else
  number_in_range "${DURATION_SECONDS}" 120 300 || {
    echo "--duration-seconds must be between 120 and 300." >&2
    exit 2
  }
fi
case "${FLOW_SELECTION}" in
  application|app-to-window|search)
    ;;
  *)
    echo "--flow must be application, app-to-window, or search." >&2
    exit 2
    ;;
esac
case "${SCENARIO_SELECTION}" in
  all)
    SCENARIOS=(realistic extreme)
    ;;
  realistic|extreme|local)
    SCENARIOS=("${SCENARIO_SELECTION}")
    ;;
  *)
    echo "--scenario must be all, realistic, extreme, or local." >&2
    exit 2
    ;;
esac
number_in_range "${COOLDOWN_SECONDS}" 10 60 || {
  echo "--cooldown-seconds must be between 10 and 60." >&2
  exit 2
}
number_in_range "${SAMPLE_INTERVAL_SECONDS}" 0.1 5 || {
  echo "--sample-interval must be between 0.1 and 5." >&2
  exit 2
}

if [[ "${HAS_BUILD_ROOT}" == true ]]; then
  BUILD_ROOT="$(resolve_invocation_path "${BUILD_ROOT}")"
  INSTALLER_BUILD_ROOT="${BUILD_ROOT}/release-ui-app"
  RUNTIME_BUILD_ROOT="${BUILD_ROOT}/runtime"
else
  INSTALLER_BUILD_ROOT="${ROOT_DIR}/.build-local/ui-test-app"
  RUNTIME_BUILD_ROOT="${ROOT_DIR}/.build-local"
fi
if [[ -z "${OUTPUT_DIR}" ]]; then
  mkdir -p "${DEFAULT_RESULTS_ROOT}"
  OUTPUT_DIR="${DEFAULT_RESULTS_ROOT}/run-$(date -u '+%Y%m%d-%H%M%S')"
else
  OUTPUT_DIR="$(resolve_invocation_path "${OUTPUT_DIR}")"
fi
if [[ -e "${OUTPUT_DIR}" ]]; then
  echo "Output directory must not already exist: ${OUTPUT_DIR}" >&2
  exit 2
fi
mkdir -p "${OUTPUT_DIR}"

cleanup() {
  local exit_status=$?
  trap - EXIT INT TERM
  if [[ -n "${ACTIVE_CHILD_PID}" ]] && kill -0 "${ACTIVE_CHILD_PID}" 2>/dev/null; then
    kill -TERM "${ACTIVE_CHILD_PID}" 2>/dev/null || true
    wait "${ACTIVE_CHILD_PID}" 2>/dev/null || true
  fi
  ACTIVE_CHILD_PID=""
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

printf 'scenario\tpressure_status\tevidence_status\n' \
  >"${OUTPUT_DIR}/scenario-status.tsv"

echo "Preparing the signed UI-test runner before timed scenarios..."
"${INSTALLER}" \
  --configuration Release \
  --include-testing-support \
  --build-root "${INSTALLER_BUILD_ROOT}"
"${UI_TEST_RUNNER}" \
  build-for-testing \
  --build-root "${RUNTIME_BUILD_ROOT}/ui-tests" \
  --output-root "${OUTPUT_DIR}/ui-test-build"

for scenario in "${SCENARIOS[@]}"; do
  scenario_dir="${OUTPUT_DIR}/${scenario}"
  metrics_path="${scenario_dir}/ui-metrics.csv"
  identity_manifest="${scenario_dir}/ui-app-identity.json"
  pressure_output="${scenario_dir}/runtime-pressure"
  summary_path="${scenario_dir}/gate-summary.txt"
  json_path="${scenario_dir}/gate-summary.json"
  mkdir -p "${scenario_dir}"

  echo "Installing Release-optimized UI app for ${scenario} scenario..."
  "${INSTALLER}" \
    --configuration Release \
    --include-testing-support \
    --build-root "${INSTALLER_BUILD_ROOT}"
  "${MANIFEST_CREATOR}" \
    --app-path "${APP_PATH}" \
    --output-file "${identity_manifest}"

  echo "Running ${scenario} ${FLOW_SELECTION} pressure for ${DURATION_SECONDS}s..."
  set +e
  FLOWTAB_APP_PANEL_PRESSURE_FLOW="${FLOW_SELECTION}" \
  FLOWTAB_APP_PANEL_PRESSURE_SCENARIO="${scenario}" \
  FLOWTAB_APP_PANEL_PRESSURE_DURATION_SECONDS="${DURATION_SECONDS}" \
  FLOWTAB_APP_PANEL_PRESSURE_COOLDOWN_SECONDS="${COOLDOWN_SECONDS}" \
  FLOWTAB_APP_PANEL_PRESSURE_METRICS_PATH="${metrics_path}" \
    "${PRESSURE_RUNNER}" \
      "${SAMPLE_INTERVAL_SECONDS}" \
      "${TEST_FILTER}" \
      --ui-app-identity-manifest "${identity_manifest}" \
      --reuse-ui-test-build \
      --skip-space-fixtures \
      --build-root "${RUNTIME_BUILD_ROOT}" \
      --output-dir "${pressure_output}" &
  ACTIVE_CHILD_PID=$!
  wait "${ACTIVE_CHILD_PID}"
  pressure_status=$?
  ACTIVE_CHILD_PID=""
  set -e

  evidence_status=1
  if [[ -f "${metrics_path}" && -f "${pressure_output}/flowtab-samples.csv" ]]; then
    set +e
    /usr/bin/python3 "${EVIDENCE_TOOL}" evaluate \
      --metrics "${metrics_path}" \
      --samples "${pressure_output}/flowtab-samples.csv" \
      --flow "${FLOW_SELECTION}" \
      --scenario "${scenario}" \
      --duration-seconds "${DURATION_SECONDS}" \
      --cooldown-seconds "${COOLDOWN_SECONDS}" \
      --summary "${summary_path}" \
      --json "${json_path}"
    evidence_status=$?
    set -e
  else
    echo "Missing UI metrics or CPU/RSS samples for ${scenario}." >&2
  fi

  printf '%s\t%s\t%s\n' \
    "${scenario}" \
    "${pressure_status}" \
    "${evidence_status}" \
    >>"${OUTPUT_DIR}/scenario-status.tsv"
  if [[ "${pressure_status}" -ne 0 || "${evidence_status}" -ne 0 ]]; then
    FINAL_STATUS=1
  fi
done

echo "FlowTab ${FLOW_SELECTION} pressure evidence: ${OUTPUT_DIR}"
if [[ "${FINAL_STATUS}" -eq 0 ]]; then
  echo "FlowTab Release pressure gate passed for selected scenarios."
fi
