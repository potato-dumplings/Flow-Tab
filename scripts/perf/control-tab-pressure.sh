#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
INVOCATION_DIRECTORY="$(pwd -P)"
INSTALLER="${ROOT_DIR}/scripts/testing/install-ui-test-app.sh"
UI_TEST_RUNNER="${ROOT_DIR}/scripts/testing/run-ui-tests-local.sh"
PERMISSION_PREFLIGHT_TEST="FlowTabUITests/FlowTabUITests/testSpaceFixturePermissionPreflightResolvesExactGrantedProjection"
MANIFEST_CREATOR="${ROOT_DIR}/scripts/testing/create-ui-app-identity-manifest.sh"
PRESSURE_RUNNER="${ROOT_DIR}/scripts/perf/runtime-topology-pressure.sh"
EVIDENCE_TOOL="${ROOT_DIR}/scripts/perf/lib/control-tab-pressure-evidence.py"
ATTACHMENT_TOOL="${ROOT_DIR}/scripts/perf/lib/app-panel-attachment-evidence.py"
PATH_BOUNDARIES_PATH="${ROOT_DIR}/scripts/lib/path-boundaries.sh"
LIFECYCLE_PATH="${ROOT_DIR}/scripts/testing/lib/ui-test-app-lifecycle.sh"
APP_PATH="${HOME}/Applications/Flow Tab UITest.app"
DEFAULT_ROOT="${ROOT_DIR}/.build-local/control-tab-pressure"

LANE_SELECTION="all"
SCENARIO_SELECTION="all"
ATTEMPTS=3
DURATION_SECONDS=120
COOLDOWN_SECONDS=15
SAMPLE_INTERVAL_SECONDS=0.5
ATTRIBUTION_RUN=false
RECORDER_MODE="full"
BASELINE_SUMMARY=""
BUILD_ROOT="${DEFAULT_ROOT}/build"
OUTPUT_DIR=""
HAS_BUILD_ROOT=false
HAS_OUTPUT_DIR=false
ACTIVE_CHILD_PID=""
FINAL_STATUS=1
CURRENT_STAGE="argument-parsing"
STATUS_WRITTEN=false

# shellcheck source=/dev/null
source "${PATH_BOUNDARIES_PATH}"
# shellcheck source=/dev/null
source "${LIFECYCLE_PATH}"

usage() {
  printf '%s\n' \
    'Usage: ./scripts/perf/control-tab-pressure.sh [options]' \
    '' \
    'Runs the Release Control+Tab end-to-end pressure gate.' \
    '' \
    'Options:' \
    '  --lane <all|ready|mutation|topology>' \
    '  --scenario <all|realistic|extreme>   Ready-lane scenario selection.' \
    '  --attempts <count>                    Attempts per scenario (default: 3).' \
    '  --duration-seconds <120-300>          Active duration (default: 120).' \
    '  --attribution                         Allow a 30-119s locating run.' \
    '  --recorder-mode <full|external-only>  Component spans or sampler-only control.' \
    '  --cooldown-seconds <1-60>             Closed-panel cooldown (default: 15).' \
    '  --sample-interval <0.1-5>             CPU/RSS cadence (default: 0.5).' \
    '  --baseline-summary <json>             Compatible green baseline.' \
    '  --build-root <dir>                    Reusable build/cache root.' \
    '  --output-dir <dir>                    New immutable evidence directory.' \
    '  -h, --help                            Show this help.'
}

resolve_path() {
  if [[ "$1" == /* ]]; then
    printf '%s' "$1"
  else
    printf '%s/%s' "${INVOCATION_DIRECTORY}" "${1#./}"
  fi
}

number_in_range() {
  LC_ALL=C awk -v value="$1" -v minimum="$2" -v maximum="$3" \
    'BEGIN { exit !(value ~ /^[0-9]+([.][0-9]+)?$/ && value >= minimum && value <= maximum) }'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lane) LANE_SELECTION="${2-}"; shift 2 ;;
    --scenario) SCENARIO_SELECTION="${2-}"; shift 2 ;;
    --attempts) ATTEMPTS="${2-}"; shift 2 ;;
    --duration-seconds) DURATION_SECONDS="${2-}"; shift 2 ;;
    --cooldown-seconds) COOLDOWN_SECONDS="${2-}"; shift 2 ;;
    --sample-interval) SAMPLE_INTERVAL_SECONDS="${2-}"; shift 2 ;;
    --baseline-summary) BASELINE_SUMMARY="${2-}"; shift 2 ;;
    --build-root)
      [[ "${HAS_BUILD_ROOT}" == false && -n "${2-}" ]] || exit 2
      BUILD_ROOT="$2"; HAS_BUILD_ROOT=true; shift 2
      ;;
    --output-dir)
      [[ "${HAS_OUTPUT_DIR}" == false && -n "${2-}" ]] || exit 2
      OUTPUT_DIR="$2"; HAS_OUTPUT_DIR=true; shift 2
      ;;
    --attribution) ATTRIBUTION_RUN=true; shift ;;
    --recorder-mode) RECORDER_MODE="${2-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "${LANE_SELECTION}" in all|ready|mutation|topology) ;; *) usage >&2; exit 2 ;; esac
case "${SCENARIO_SELECTION}" in all|realistic|extreme) ;; *) usage >&2; exit 2 ;; esac
case "${RECORDER_MODE}" in full|external-only) ;; *) usage >&2; exit 2 ;; esac
[[ "${ATTEMPTS}" =~ ^[1-9][0-9]*$ ]] && [[ "${ATTEMPTS}" -le 10 ]] || {
  echo "--attempts must be an integer from 1 through 10." >&2; exit 2;
}
if [[ "${ATTRIBUTION_RUN}" == true ]]; then
  number_in_range "${DURATION_SECONDS}" 30 119 || {
    echo "Attribution duration must be between 30 and 119 seconds." >&2; exit 2;
  }
else
  number_in_range "${DURATION_SECONDS}" 120 300 || {
    echo "Formal duration must be between 120 and 300 seconds." >&2; exit 2;
  }
fi
if [[ "${RECORDER_MODE}" == external-only && "${ATTRIBUTION_RUN}" != true ]]; then
  echo "External-only recorder mode is limited to attribution runs." >&2
  exit 2
fi
number_in_range "${COOLDOWN_SECONDS}" 1 60 || exit 2
number_in_range "${SAMPLE_INTERVAL_SECONDS}" 0.1 5 || exit 2
BUILD_ROOT="$(resolve_path "${BUILD_ROOT}")"
if [[ -n "${BASELINE_SUMMARY}" ]]; then
  BASELINE_SUMMARY="$(resolve_path "${BASELINE_SUMMARY}")"
  [[ -f "${BASELINE_SUMMARY}" ]] || {
    echo "Baseline summary not found: ${BASELINE_SUMMARY}" >&2; exit 2;
  }
fi

if [[ -z "${OUTPUT_DIR}" ]]; then
  mkdir -p "${DEFAULT_ROOT}"
  base_output="${DEFAULT_ROOT}/run-$(date -u '+%Y%m%d-%H%M%S')"
  OUTPUT_DIR="${base_output}"
  collision=1
  while [[ -e "${OUTPUT_DIR}" ]]; do
    OUTPUT_DIR="${base_output}-${collision}"
    collision=$((collision + 1))
  done
else
  OUTPUT_DIR="$(resolve_path "${OUTPUT_DIR}")"
fi
[[ ! -e "${OUTPUT_DIR}" ]] || {
  echo "Output directory must not already exist: ${OUTPUT_DIR}" >&2; exit 2;
}
mkdir -p "${OUTPUT_DIR}"
/usr/bin/python3 -c \
  'import json,sys; json.dump({"schema_version":1,"recorder_mode":sys.argv[2],"formal_eligible":sys.argv[2]=="full"},open(sys.argv[1],"w"),indent=2); open(sys.argv[1],"a").write("\n")' \
  "${OUTPUT_DIR}/instrumentation-mode.json" "${RECORDER_MODE}"

cleanup() {
  local exit_status=$?
  trap - EXIT INT TERM
  if [[ -n "${ACTIVE_CHILD_PID}" ]] && kill -0 "${ACTIVE_CHILD_PID}" 2>/dev/null; then
    kill -TERM "${ACTIVE_CHILD_PID}" 2>/dev/null || true
    wait "${ACTIVE_CHILD_PID}" 2>/dev/null || true
  fi
  if [[ -d "${APP_PATH}" ]]; then
    flowtab_ui_test_app_remove_managed_bundle \
      "${ROOT_DIR}" "${HOME}" "${APP_PATH}" >/dev/null 2>&1 || true
  fi
  if [[ "${STATUS_WRITTEN}" == false ]]; then
    /usr/bin/python3 -c \
      'import json,sys; json.dump({"schema_version":1,"runner_kind":"control_tab_pressure","overall_verdict":"failed","stage":sys.argv[2],"recorder_mode":sys.argv[3],"formal_eligible":sys.argv[3]=="full"},open(sys.argv[1],"w"),indent=2); open(sys.argv[1],"a").write("\n")' \
      "${OUTPUT_DIR}/status.json" "${CURRENT_STAGE}" "${RECORDER_MODE}" || true
  fi
  [[ "${FINAL_STATUS}" -eq 0 ]] && exit 0
  [[ "${exit_status}" -ne 0 ]] && exit "${exit_status}"
  exit "${FINAL_STATUS}"
}
trap cleanup EXIT INT TERM

SCENARIOS=()
if [[ "${LANE_SELECTION}" == all || "${LANE_SELECTION}" == ready ]]; then
  if [[ "${SCENARIO_SELECTION}" == all || "${SCENARIO_SELECTION}" == realistic ]]; then
    SCENARIOS+=("ready|realistic|24|5|testControlTabDeterministicPressureGate|flowtab-control-tab-ready-realistic-windowContentDraw")
  fi
  if [[ "${SCENARIO_SELECTION}" == all || "${SCENARIO_SELECTION}" == extreme ]]; then
    SCENARIOS+=("ready|extreme|120|100|testControlTabDeterministicPressureGate|flowtab-control-tab-ready-extreme-windowContentDraw")
  fi
fi
if [[ "${LANE_SELECTION}" == all || "${LANE_SELECTION}" == mutation ]]; then
  SCENARIOS+=("mutation|closed-panel|0|0|testControlTabClosedPanelMutationPressureGate|flowtab-control-tab-mutation-closed-panel-windowContentDraw")
fi
if [[ "${LANE_SELECTION}" == all || "${LANE_SELECTION}" == topology ]]; then
  SCENARIOS+=("topology|noisy|0|4|testControlTabNoisyTopologyPressureGate|flowtab-control-tab-topology-noisy-windowContentDraw")
fi

CURRENT_STAGE="build-release-app"
echo "Preparing Release TestingSupport app and signed UI runner..."
"${INSTALLER}" --configuration Release --include-testing-support \
  --build-root "${BUILD_ROOT}/release-ui-app"
CURRENT_STAGE="build-ui-tests"
"${UI_TEST_RUNNER}" build-for-testing \
  --build-root "${BUILD_ROOT}/ui-tests" \
  --output-root "${OUTPUT_DIR}/ui-test-build"
CURRENT_STAGE="permission-preflight"
echo "Verifying fixed-app Accessibility and Screen Recording grants..."
"${UI_TEST_RUNNER}" test-without-building \
  --skip-space-fixtures \
  --build-root "${BUILD_ROOT}/ui-tests" \
  --output-root "${OUTPUT_DIR}/permission-preflight" \
  "-only-testing:${PERMISSION_PREFLIGHT_TEST}"

scenario_summaries=()
for specification in "${SCENARIOS[@]}"; do
  IFS='|' read -r lane scenario app_count window_count test_name attachment_name <<<"${specification}"
  scenario_dir="${OUTPUT_DIR}/${lane}-${scenario}"
  mkdir "${scenario_dir}"
  attempt_summaries=()
  for ((attempt = 1; attempt <= ATTEMPTS; attempt++)); do
    attempt_dir="${scenario_dir}/attempt-$(printf '%02d' "${attempt}")"
    mkdir "${attempt_dir}"
    metrics_path="${attempt_dir}/phase-metrics.csv"
    identity_path="${attempt_dir}/ui-app-identity.json"
    runtime_output="${attempt_dir}/runtime"
    summary_json="${attempt_dir}/summary.json"
    summary_text="${attempt_dir}/summary.txt"
    process_samples="${attempt_dir}/process-samples.csv"
    runtime_status="${attempt_dir}/runtime-status.json"
    sampler_readiness="${runtime_output}/sampling-ready.json"

    CURRENT_STAGE="install-${lane}-${scenario}-${attempt}"
    echo "Installing fixed Release app for ${lane}/${scenario} attempt ${attempt}..."
    "${INSTALLER}" --configuration Release --include-testing-support \
      --build-root "${BUILD_ROOT}/release-ui-app"
    "${MANIFEST_CREATOR}" --app-path "${APP_PATH}" --output-file "${identity_path}"

    pressure_arguments=(
      "${SAMPLE_INTERVAL_SECONDS}"
      "FlowTabUITests/FlowTabUITests/${test_name}"
      --ui-app-identity-manifest "${identity_path}"
      --reuse-ui-test-build
      --build-root "${BUILD_ROOT}"
      --output-dir "${runtime_output}"
    )
    if [[ "${lane}" != topology ]]; then
      pressure_arguments+=(--skip-space-fixtures)
    fi
    CURRENT_STAGE="run-${lane}-${scenario}-${attempt}"
    set +e
    FLOWTAB_CONTROL_TAB_LANE="${lane}" \
    FLOWTAB_CONTROL_TAB_SCENARIO="${scenario}" \
    FLOWTAB_CONTROL_TAB_DURATION_SECONDS="${DURATION_SECONDS}" \
    FLOWTAB_CONTROL_TAB_COOLDOWN_SECONDS="${COOLDOWN_SECONDS}" \
    FLOWTAB_CONTROL_TAB_METRICS_PATH="${metrics_path}" \
    FLOWTAB_CONTROL_TAB_SAMPLER_READY_PATH="${sampler_readiness}" \
    FLOWTAB_CONTROL_TAB_RECORDER_MODE="${RECORDER_MODE}" \
    FLOWTAB_RUNTIME_TARGET_LAUNCH_WATCHDOG_MILLISECONDS=90000 \
      "${PRESSURE_RUNNER}" "${pressure_arguments[@]}" &
    ACTIVE_CHILD_PID=$!
    wait "${ACTIVE_CHILD_PID}"
    pressure_status=$?
    ACTIVE_CHILD_PID=""
    set -e

    [[ -f "${runtime_output}/flowtab-samples.csv" ]] && \
      cp "${runtime_output}/flowtab-samples.csv" "${process_samples}"
    [[ -f "${runtime_output}/status.json" ]] && \
      cp "${runtime_output}/status.json" "${runtime_status}"

    evidence_arguments=(
      evaluate
      --metrics "${metrics_path}"
      --samples "${process_samples}"
      --runtime-status "${runtime_status}"
      --lane "${lane}" --scenario "${scenario}"
      --expected-app-count "${app_count}"
      --expected-window-count "${window_count}"
      --identity-manifest "${identity_path}"
      --target-launch-receipt "${runtime_output}/target-launch-receipt.json"
      --cleanup-evidence "${runtime_output}/application-cleanup.json"
      --sampler-readiness "${sampler_readiness}"
      --result-bundle "${runtime_output}/attempts/ui-tests/run/results/FlowTabUITests.xcresult"
    )
    if [[ "${attempt}" -eq 1 ]]; then
      xcresult="${runtime_output}/attempts/ui-tests/run/results/FlowTabUITests.xcresult"
      set +e
      /usr/bin/python3 "${ATTACHMENT_TOOL}" export \
        --xcresult "${xcresult}" \
        --output-dir "${attempt_dir}/first-frame" \
        --expected-name "${attachment_name}"
      attachment_status=$?
      set -e
      evidence_arguments+=(
        --attachment-manifest "${attempt_dir}/first-frame/attachment-evidence.json"
      )
    else
      attachment_status=0
    fi
    evidence_arguments+=(
      --output "${summary_json}" --summary "${summary_text}"
    )

    set +e
    /usr/bin/python3 "${EVIDENCE_TOOL}" "${evidence_arguments[@]}"
    evidence_status=$?
    set -e
    attempt_summaries+=("${summary_json}")
    printf 'pressure_exit_code=%s\nevidence_exit_code=%s\nattachment_exit_code=%s\n' \
      "${pressure_status}" "${evidence_status}" "${attachment_status}" \
      >"${attempt_dir}/runner-status.txt"
  done

  aggregate_arguments=()
  for path in "${attempt_summaries[@]}"; do
    aggregate_arguments+=(--attempt-summary "${path}")
  done
  [[ -n "${BASELINE_SUMMARY}" ]] && \
    aggregate_arguments+=(--baseline-summary "${BASELINE_SUMMARY}")
  scenario_json="${scenario_dir}/summary.json"
  set +e
  /usr/bin/python3 "${EVIDENCE_TOOL}" aggregate \
    "${aggregate_arguments[@]}" \
    --output "${scenario_json}" \
    --summary "${scenario_dir}/summary.txt"
  aggregate_status=$?
  set -e
  scenario_summaries+=("${scenario_json}")
  printf 'aggregate_exit_code=%s\n' "${aggregate_status}" \
    >"${scenario_dir}/runner-status.txt"
done

matrix_arguments=()
for path in "${scenario_summaries[@]}"; do
  matrix_arguments+=(--scenario-summary "${path}")
done
CURRENT_STAGE="aggregate-matrix"
set +e
/usr/bin/python3 "${EVIDENCE_TOOL}" matrix \
  "${matrix_arguments[@]}" \
  --output "${OUTPUT_DIR}/status.json" \
  --summary "${OUTPUT_DIR}/summary.txt"
FINAL_STATUS=$?
set -e
/usr/bin/python3 -c \
  'import json,sys; path=sys.argv[1]; data=json.load(open(path)); data["recorder_mode"]=sys.argv[2]; data["formal_eligible"]=sys.argv[2]=="full"; json.dump(data,open(path,"w"),indent=2); open(path,"a").write("\n")' \
  "${OUTPUT_DIR}/status.json" "${RECORDER_MODE}"
STATUS_WRITTEN=true
CURRENT_STAGE="completed"
echo "Control+Tab pressure evidence: ${OUTPUT_DIR}"
