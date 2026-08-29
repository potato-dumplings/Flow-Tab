#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RESULTS_ROOT="${ROOT_DIR}/.build-local/runtime-topology-pressure"
UI_TEST_RUNNER="${ROOT_DIR}/scripts/testing/run-ui-tests-local.sh"
EVIDENCE_TOOL="${ROOT_DIR}/scripts/perf/lib/runtime-topology-evidence.py"
MONOTONIC_CLOCK="${ROOT_DIR}/scripts/perf/lib/monotonic-clock.sh"
TARGET_TOOL="${ROOT_DIR}/scripts/perf/lib/runtime-topology-target.sh"
PROCESS_EXIT_OBSERVATION_PATH="${ROOT_DIR}/scripts/perf/lib/process-exit-observation.sh"
APPLICATION_LIFECYCLE_TOOL="${ROOT_DIR}/scripts/perf/lib/runtime-topology-application-lifecycle.js"
APPLICATION_PROCESS_CLEANUP_TOOL="${ROOT_DIR}/scripts/perf/lib/runtime-topology-application-process-cleanup.js"
SPACE_FIXTURE_WORKFLOW_CONFIG="${ROOT_DIR}/docs/fixtures/space-fixture-home-multi-app-workflow.json"
SYSTEM_APP_MRU_FIXTURE_WORKFLOW_CONFIG="${ROOT_DIR}/docs/fixtures/space-fixture-system-app-mru-workflow.json"
DEFAULT_TEST="FlowTabUITests/FlowTabUITests/testSwitcherPanelOptionTabWindowStateRoundTripsFullscreenWorkflowSiblingAcrossSpacesWithNoisyCGSiblingsWithoutAppAXWindows"
TEST_TERMINATION_GRACE_MILLISECONDS=2000
TEST_KILL_CONFIRMATION_WATCHDOG_MILLISECONDS=2000
TEST_TERMINATION_POLL_INTERVAL_SECONDS=0.1
TARGET_EXIT_COMPLETION_WATCHDOG_MILLISECONDS=30000
TARGET_EXIT_COMPLETION_POLL_INTERVAL_SECONDS=0.1

source "$TARGET_TOOL"
# shellcheck source=scripts/perf/lib/process-exit-observation.sh
source "$PROCESS_EXIT_OBSERVATION_PATH"

usage() {
  cat <<'EOF'
Usage: ./scripts/perf/runtime-topology-pressure.sh [sample_interval_seconds] [test_filter] --ui-app-identity-manifest <file> [--reuse-ui-test-build] [--skip-space-fixtures] [--build-root <dir>] [--output-dir <dir>]

Runs one real-topology UI pressure scenario, samples FlowTab CPU/RSS, and
preserves the UI wrapper result bundle and logs in a unique child attempt.

Positional arguments:
  sample_interval_seconds  CPU/RSS sampling cadence in seconds (default: 0.5)
  test_filter              FlowTabUITests test identifier (default: the Noisy
                           Option+Tab fullscreen/off-space workflow)

Options:
  --ui-app-identity-manifest <file>
                           Required private JSON manifest for the fixed App and
                           per-sample PID identity binding.
  --reuse-ui-test-build    Run test-without-building against an already prepared
                           and signed UI-test runner.
  --skip-space-fixtures    Forward fixture preparation opt-out to the UI wrapper.
  --build-root <dir>       Resolve UI-test build products, caches, and generated
                           fixture variants below this directory.
  --output-dir <dir>       New evidence directory. The leaf must not already exist.
                           Defaults to a unique directory under
                           .build-local/runtime-topology-pressure/.
  -h, --help               Show this help.

Outputs:
  flowtab-samples.csv      Raw FlowTab CPU/RSS samples
  pid-bindings.csv         Per-sample PID/start/path/executable identity verdicts
  target-launch-receipt.json
                           Unique post-request launch identity
  summary.txt              Aggregate pressure statistics
  logs/                    Aggregate UI wrapper and summary logs
  attempts/ui-tests/run/   Unique UI wrapper output root and .xcresult
  status.json              Top-level stage and child/log exit status
EOF
}

OUTPUT_DIR=""
HAS_CUSTOM_OUTPUT_DIR=false
HAS_CUSTOM_BUILD_ROOT=false
HAS_UI_APP_IDENTITY_MANIFEST=false
REUSE_UI_TEST_BUILD=false
SKIP_SPACE_FIXTURES=false
BUILD_ROOT=""
UI_APP_IDENTITY_MANIFEST=""
POSITIONAL_ARGS=()
TEST_PID=""
TEST_START_IDENTITY=""
TEST_PROCESS_IDENTITY_CAPTURE_FAILED=false
TEST_REAPED=true
TEST_PROCESS_STATUS="not_started"
APPLICATION_BASELINE_STATUS="null"
APPLICATION_CLEANUP_STATUS="null"
APPLICATION_CLEANUP_FAILED=false
APPLICATION_CLEANUP_FINISHED=false
STATUS_FILE=""
CURRENT_STAGE="argument_parsing"
UI_WRAPPER_STATUS="null"
UI_LOG_STATUS="null"
SUMMARY_STATUS="null"
SUMMARY_LOG_STATUS="null"
SAMPLE_COUNT=0
SAMPLING_FAILED=false
TERMINATION_TIMED_OUT=false
IDENTITY_FAILED=false
IDENTITY_VERDICT="not_evaluated"
IDENTITY_CHECK_COUNT=0
TARGET_PID=""
TARGET_START_IDENTITY=""
TARGET_START_EPOCH_SECONDS=""
TARGET_STABILITY_WINDOW_MILLISECONDS=""
TARGET_FIRST_OBSERVED_MONOTONIC_NS=""
TARGET_QUALIFIED_MONOTONIC_NS=""
TARGET_OBSERVATION_COUNT=0
REJECTED_TRANSIENT_IDENTITY_COUNT=0
TARGET_PREVIOUS_CPU_CENTISECONDS=""
TARGET_PREVIOUS_CPU_SAMPLE_MONOTONIC_NS=""
TARGET_TERMINAL_EXIT_OBSERVED=false
TARGET_TERMINATION_VERDICT="not_observed"
PREEXISTING_TARGET_IDENTITIES=""
LAUNCH_REQUEST_MONOTONIC_NS=""
LAUNCH_REQUEST_EPOCH_SECONDS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ui-app-identity-manifest)
      if [[ "$HAS_UI_APP_IDENTITY_MANIFEST" == true || $# -lt 2 || -z "$2" ]]; then
        echo "--ui-app-identity-manifest requires one value and may only be specified once." >&2
        exit 2
      fi
      UI_APP_IDENTITY_MANIFEST="$2"
      HAS_UI_APP_IDENTITY_MANIFEST=true
      shift 2
      ;;
    --ui-app-identity-manifest=*)
      if [[ "$HAS_UI_APP_IDENTITY_MANIFEST" == true ]]; then
        echo "--ui-app-identity-manifest may only be specified once." >&2
        exit 2
      fi
      UI_APP_IDENTITY_MANIFEST="${1#*=}"
      HAS_UI_APP_IDENTITY_MANIFEST=true
      shift
      ;;
    --reuse-ui-test-build)
      REUSE_UI_TEST_BUILD=true
      shift
      ;;
    --skip-space-fixtures)
      SKIP_SPACE_FIXTURES=true
      shift
      ;;
    --build-root)
      if [[ "$HAS_CUSTOM_BUILD_ROOT" == true || $# -lt 2 || -z "$2" ]]; then
        echo "--build-root requires one non-empty value and may only be specified once." >&2
        exit 2
      fi
      BUILD_ROOT="$2"
      HAS_CUSTOM_BUILD_ROOT=true
      shift 2
      ;;
    --build-root=*)
      if [[ "$HAS_CUSTOM_BUILD_ROOT" == true ]]; then
        echo "--build-root may only be specified once." >&2
        exit 2
      fi
      BUILD_ROOT="${1#*=}"
      if [[ -z "$BUILD_ROOT" ]]; then
        echo "Missing value for --build-root." >&2
        exit 2
      fi
      HAS_CUSTOM_BUILD_ROOT=true
      shift
      ;;
    --output-dir)
      if [[ "$HAS_CUSTOM_OUTPUT_DIR" == true ]]; then
        echo "--output-dir may only be specified once." >&2
        exit 2
      fi
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "Missing value for --output-dir." >&2
        usage >&2
        exit 2
      fi
      OUTPUT_DIR="$2"
      HAS_CUSTOM_OUTPUT_DIR=true
      shift 2
      ;;
    --output-dir=*)
      if [[ "$HAS_CUSTOM_OUTPUT_DIR" == true ]]; then
        echo "--output-dir may only be specified once." >&2
        exit 2
      fi
      OUTPUT_DIR="${1#*=}"
      if [[ -z "$OUTPUT_DIR" ]]; then
        echo "Missing value for --output-dir." >&2
        usage >&2
        exit 2
      fi
      HAS_CUSTOM_OUTPUT_DIR=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        POSITIONAL_ARGS+=("$1")
        shift
      done
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ ${#POSITIONAL_ARGS[@]} -gt 2 ]]; then
  echo "Expected at most two positional arguments." >&2
  usage >&2
  exit 2
fi

SAMPLE_INTERVAL_SECONDS="${POSITIONAL_ARGS[0]:-0.5}"
TEST_FILTER="${POSITIONAL_ARGS[1]:-${DEFAULT_TEST}}"
UI_TEST_ACTION="test"
if [[ "${REUSE_UI_TEST_BUILD}" == true ]]; then
  UI_TEST_ACTION="test-without-building"
fi

if ! LC_ALL=C awk -v value="$SAMPLE_INTERVAL_SECONDS" 'BEGIN { exit !(value ~ /^[0-9]+([.][0-9]+)?$/ && value + 0 > 0) }'; then
  echo "sample_interval_seconds must be a positive number." >&2
  exit 2
fi
if [[ -z "$TEST_FILTER" ]]; then
  echo "test_filter must not be empty." >&2
  exit 2
fi
if [[ "$HAS_UI_APP_IDENTITY_MANIFEST" != true || -z "$UI_APP_IDENTITY_MANIFEST" ]]; then
  echo "--ui-app-identity-manifest is required." >&2
  exit 2
fi
if [[ ! -f "$UI_APP_IDENTITY_MANIFEST" ]]; then
  echo "UI App identity manifest not found: $UI_APP_IDENTITY_MANIFEST" >&2
  exit 2
fi

IDENTITY_FIELDS="$(/usr/bin/python3 "$EVIDENCE_TOOL" validate-manifest "$UI_APP_IDENTITY_MANIFEST")" || exit 2
IFS=$'\t' read -r EXPECTED_APP_PATH EXPECTED_BUNDLE_ID EXPECTED_EXECUTABLE_SHA256 EXPECTED_DESIGNATED_REQUIREMENT_SHA256 PID_BINDING_POLICY_VERSION TARGET_STABILITY_WINDOW_MILLISECONDS <<<"$IDENTITY_FIELDS"

if [[ ! -d "$EXPECTED_APP_PATH" ]]; then
  echo "Expected UI App bundle not found: $EXPECTED_APP_PATH" >&2
  exit 2
fi
IDENTITY_PLIST_FIELDS="$(/usr/bin/python3 "$EVIDENCE_TOOL" read-plist "$EXPECTED_APP_PATH/Contents/Info.plist")" || exit 2
IFS=$'\t' read -r ACTUAL_BUNDLE_ID EXPECTED_EXECUTABLE_NAME <<<"$IDENTITY_PLIST_FIELDS"
EXPECTED_EXECUTABLE_PATH="$EXPECTED_APP_PATH/Contents/MacOS/$EXPECTED_EXECUTABLE_NAME"
if [[ "$ACTUAL_BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" || ! -x "$EXPECTED_EXECUTABLE_PATH" ]]; then
  echo "UI App bundle identity does not match the frozen manifest." >&2
  exit 2
fi
ACTUAL_EXECUTABLE_SHA256="$(LC_ALL=C shasum -a 256 "$EXPECTED_EXECUTABLE_PATH" | awk '{print $1}')"
if [[ "$ACTUAL_EXECUTABLE_SHA256" != "$EXPECTED_EXECUTABLE_SHA256" ]]; then
  echo "UI App executable checksum does not match the frozen manifest." >&2
  exit 2
fi
DESIGNATED_REQUIREMENT="$(/usr/bin/codesign -dr - "$EXPECTED_APP_PATH" 2>&1 | sed -n 's/^designated => //p')"
if [[ -z "$DESIGNATED_REQUIREMENT" ]]; then
  echo "Could not read the UI App designated requirement." >&2
  exit 2
fi
ACTUAL_DESIGNATED_REQUIREMENT_SHA256="$(printf '%s' "$DESIGNATED_REQUIREMENT" | LC_ALL=C shasum -a 256 | awk '{print $1}')"
if [[ "$ACTUAL_DESIGNATED_REQUIREMENT_SHA256" != "$EXPECTED_DESIGNATED_REQUIREMENT_SHA256" ]]; then
  echo "UI App designated-requirement checksum does not match the frozen manifest." >&2
  exit 2
fi
UI_APP_IDENTITY_MANIFEST_SHA256="$(LC_ALL=C shasum -a 256 "$UI_APP_IDENTITY_MANIFEST" | awk '{print $1}')"
if [[ "$HAS_CUSTOM_BUILD_ROOT" == true ]]; then
  CHILD_UI_BUILD_ROOT="${BUILD_ROOT}/ui-tests"
  SPACE_FIXTURE_RESOLVED_WORKFLOW="${CHILD_UI_BUILD_ROOT}/space-fixture-workflow/variants/resolved-workflow.json"
  SYSTEM_APP_MRU_RESOLVED_WORKFLOW="${CHILD_UI_BUILD_ROOT}/space-fixture-workflow/system-app-mru-variants/resolved-workflow.json"
else
  CHILD_UI_BUILD_ROOT="${ROOT_DIR}/.build-local/ui-tests"
  SPACE_FIXTURE_RESOLVED_WORKFLOW="${ROOT_DIR}/.build-local/space-fixture-workflow/variants/resolved-workflow.json"
  SYSTEM_APP_MRU_RESOLVED_WORKFLOW="${ROOT_DIR}/.build-local/space-fixture-workflow/system-app-mru-variants/resolved-workflow.json"
fi

if [[ "$HAS_CUSTOM_OUTPUT_DIR" == true ]]; then
  if ! mkdir -p "$(dirname "$OUTPUT_DIR")"; then
    echo "Could not create output parent directory: $(dirname "$OUTPUT_DIR")" >&2
    exit 1
  fi
  if ! mkdir "$OUTPUT_DIR" 2>/dev/null; then
    if [[ -e "$OUTPUT_DIR" ]]; then
      echo "Output directory must not already exist: $OUTPUT_DIR" >&2
      echo "Use a new attempt-specific directory so prior evidence cannot be overwritten." >&2
    else
      echo "Could not create output directory: $OUTPUT_DIR" >&2
    fi
    exit 1
  fi
else
  RUN_TIMESTAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
  OUTPUT_BASE="${RESULTS_ROOT}/results-${RUN_TIMESTAMP}"
  if ! mkdir -p "$RESULTS_ROOT"; then
    echo "Could not create default output parent: $RESULTS_ROOT" >&2
    exit 1
  fi
  OUTPUT_DIR="$OUTPUT_BASE"
  COLLISION_INDEX=1
  while ! mkdir "$OUTPUT_DIR" 2>/dev/null; do
    if [[ ! -e "$OUTPUT_DIR" ]]; then
      echo "Could not create output directory: $OUTPUT_DIR" >&2
      exit 1
    fi
    OUTPUT_DIR="${OUTPUT_BASE}-${COLLISION_INDEX}"
    COLLISION_INDEX=$((COLLISION_INDEX + 1))
  done
fi

SAMPLES_FILE="${OUTPUT_DIR}/flowtab-samples.csv"
PID_BINDINGS_FILE="${OUTPUT_DIR}/pid-bindings.csv"
LAUNCH_RECEIPT_FILE="${OUTPUT_DIR}/target-launch-receipt.json"
SUMMARY_FILE="${OUTPUT_DIR}/summary.txt"
LOG_DIR="${OUTPUT_DIR}/logs"
UI_LOG_FILE="${LOG_DIR}/ui-test.log"
SUMMARY_LOG_FILE="${LOG_DIR}/summary.log"
UI_RUN_STATUS_FILE="${OUTPUT_DIR}/ui-run-status.txt"
APPLICATION_BASELINE_FILE="${OUTPUT_DIR}/application-baseline.json"
APPLICATION_CLEANUP_EVIDENCE_FILE="${OUTPUT_DIR}/application-cleanup.json"
STATUS_FILE="${OUTPUT_DIR}/status.json"
UI_ATTEMPT_DIR="${OUTPUT_DIR}/attempts/ui-tests/run"

mkdir -p "$LOG_DIR"
printf 'sample,timestamp,pid,cpu_percent,rss_kb\n' >"$SAMPLES_FILE"
printf 'identity_check,timestamp,pid,process_start_epoch_seconds,process_start_identity,process_path_sha256,executable_sha256,verdict\n' >"$PID_BINDINGS_FILE"

write_status() {
  local final_exit_code="$1"
  local status_temp="${STATUS_FILE}.tmp"
  local sampling_failed_json="false"
  local termination_timed_out_json="false"
  local target_terminal_exit_observed_json="false"
  local application_cleanup_failed_json="false"
  local application_cleanup_evidence_present="false"
  local result_bundle_directory_present="false"
  local result_bundle_present="false"

  if [[ "$SAMPLING_FAILED" == true ]]; then
    sampling_failed_json="true"
  fi
  if [[ "$TERMINATION_TIMED_OUT" == true ]]; then
    termination_timed_out_json="true"
  fi
  if [[ "$TARGET_TERMINAL_EXIT_OBSERVED" == true ]]; then
    target_terminal_exit_observed_json="true"
  fi
  if [[ "$APPLICATION_CLEANUP_FAILED" == true ]]; then
    application_cleanup_failed_json="true"
  fi
  if [[ -f "$APPLICATION_CLEANUP_EVIDENCE_FILE" ]]; then
    application_cleanup_evidence_present="true"
  fi
  if [[ -d "${UI_ATTEMPT_DIR}/results/FlowTabUITests.xcresult" ]]; then
    result_bundle_directory_present="true"
  fi
  if [[ -f "${UI_ATTEMPT_DIR}/results/FlowTabUITests.xcresult/Info.plist" ]]; then
    result_bundle_present="true"
  fi

  {
    printf '{\n'
    printf '  "schema_version": 1,\n'
    printf '  "runner_kind": "runtime_topology_pressure",\n'
    printf '  "ui_test_action": "%s",\n' "$UI_TEST_ACTION"
    printf '  "stage": "%s",\n' "$CURRENT_STAGE"
    printf '  "final_exit_code": %s,\n' "$final_exit_code"
    printf '  "ui_wrapper_exit_code": %s,\n' "$UI_WRAPPER_STATUS"
    printf '  "ui_log_exit_code": %s,\n' "$UI_LOG_STATUS"
    printf '  "ui_process_exit_code": %s,\n' "$([[ "$TEST_PROCESS_STATUS" =~ ^[0-9]+$ ]] && printf '%s' "$TEST_PROCESS_STATUS" || printf 'null')"
    printf '  "ui_result_bundle_directory_present": %s,\n' "$result_bundle_directory_present"
    printf '  "ui_result_bundle_present": %s,\n' "$result_bundle_present"
    printf '  "ui_result_bundle_valid": %s,\n' "$result_bundle_present"
    printf '  "sampling_failed": %s,\n' "$sampling_failed_json"
    printf '  "termination_timed_out": %s,\n' "$termination_timed_out_json"
    printf '  "application_baseline_exit_code": %s,\n' "$APPLICATION_BASELINE_STATUS"
    printf '  "application_cleanup_exit_code": %s,\n' "$APPLICATION_CLEANUP_STATUS"
    printf '  "application_cleanup_failed": %s,\n' "$application_cleanup_failed_json"
    printf '  "application_cleanup_evidence_present": %s,\n' "$application_cleanup_evidence_present"
    printf '  "identity_verdict": "%s",\n' "$IDENTITY_VERDICT"
    printf '  "identity_check_count": %s,\n' "$IDENTITY_CHECK_COUNT"
    printf '  "pid_binding_policy_version": "%s",\n' "$PID_BINDING_POLICY_VERSION"
    printf '  "stable_identity_window_milliseconds": %s,\n' "$TARGET_STABILITY_WINDOW_MILLISECONDS"
    printf '  "rejected_transient_identity_count": %s,\n' "$REJECTED_TRANSIENT_IDENTITY_COUNT"
    printf '  "target_terminal_exit_observed": %s,\n' "$target_terminal_exit_observed_json"
    printf '  "target_termination_verdict": "%s",\n' "$TARGET_TERMINATION_VERDICT"
    printf '  "target_launch_receipt_present": %s,\n' "$([[ -f "$LAUNCH_RECEIPT_FILE" ]] && printf true || printf false)"
    printf '  "sample_count": %s,\n' "$SAMPLE_COUNT"
    printf '  "summary_exit_code": %s,\n' "$SUMMARY_STATUS"
    printf '  "summary_log_exit_code": %s\n' "$SUMMARY_LOG_STATUS"
    printf '}\n'
  } >"$status_temp" || return 1
  mv "$status_temp" "$STATUS_FILE"
}

load_ui_run_status() {
  local value

  if [[ ! -f "$UI_RUN_STATUS_FILE" ]]; then
    return 0
  fi
  value="$(awk -F= '$1 == "wrapper_exit_code" { print $2 }' "$UI_RUN_STATUS_FILE")"
  [[ -n "$value" ]] && UI_WRAPPER_STATUS="$value"
  value="$(awk -F= '$1 == "log_exit_code" { print $2 }' "$UI_RUN_STATUS_FILE")"
  [[ -n "$value" ]] && UI_LOG_STATUS="$value"
  return 0
}

capture_application_baseline() {
  local bundle_identifier
  local baseline_status
  local fixture_bundle_identifiers
  local bundle_identifiers=("$EXPECTED_BUNDLE_ID")

  if ! fixture_bundle_identifiers="$(
    /usr/bin/python3 "$EVIDENCE_TOOL" workflow-bundle-identifiers \
      "$SPACE_FIXTURE_WORKFLOW_CONFIG" \
      "$SYSTEM_APP_MRU_FIXTURE_WORKFLOW_CONFIG"
  )"; then
    APPLICATION_BASELINE_STATUS=1
    echo "Could not resolve the configured fixture bundle identities." >&2
    echo "unmetCondition=fixtureBundleIdentitiesResolved" >&2
    return 1
  fi
  while IFS= read -r bundle_identifier; do
    [[ -n "$bundle_identifier" ]] || continue
    bundle_identifiers+=("$bundle_identifier")
  done <<<"$fixture_bundle_identifiers"

  if /usr/bin/osascript -l JavaScript \
    "$APPLICATION_LIFECYCLE_TOOL" \
    capture \
    "$APPLICATION_BASELINE_FILE" \
    "${bundle_identifiers[@]}"; then
    APPLICATION_BASELINE_STATUS=0
    return 0
  else
    baseline_status=$?
  fi
  APPLICATION_BASELINE_STATUS="$baseline_status"
  echo "Could not capture the pre-request application identity baseline." >&2
  echo "unmetCondition=applicationBaselineCaptured" >&2
  return "$baseline_status"
}

cleanup_independent_applications() {
  local cleanup_status

  if [[ "$APPLICATION_CLEANUP_FINISHED" == true ]]; then
    [[ "$APPLICATION_CLEANUP_FAILED" == false ]]
    return
  fi
  APPLICATION_CLEANUP_FINISHED=true
  if [[ "$APPLICATION_BASELINE_STATUS" != 0 ]]; then
    return 0
  fi

  if /usr/bin/osascript -l JavaScript \
    "$APPLICATION_LIFECYCLE_TOOL" \
    terminate \
    "$APPLICATION_BASELINE_FILE" \
    "$APPLICATION_CLEANUP_EVIDENCE_FILE" \
    "$EXPECTED_BUNDLE_ID" \
    "$EXPECTED_APP_PATH" \
    "$SPACE_FIXTURE_RESOLVED_WORKFLOW" \
    "$SYSTEM_APP_MRU_RESOLVED_WORKFLOW"; then
    if /usr/bin/osascript -l JavaScript \
      "$APPLICATION_PROCESS_CLEANUP_TOOL" \
      cleanup \
      "$APPLICATION_CLEANUP_EVIDENCE_FILE"; then
      APPLICATION_CLEANUP_STATUS=0
      return 0
    else
      cleanup_status=$?
    fi
  else
    cleanup_status=$?
  fi
  APPLICATION_CLEANUP_STATUS="$cleanup_status"
  APPLICATION_CLEANUP_FAILED=true
  echo "Independent runtime-topology application cleanup failed." >&2
  echo "unmetCondition=postRequestApplicationsAbsent" >&2
  echo "lastObservationFile=${APPLICATION_CLEANUP_EVIDENCE_FILE}" >&2
  return "$cleanup_status"
}

descendant_pids() {
  local root_pid="$1"
  local all_pids=("$root_pid")
  local index=0

  while [[ "$index" -lt "${#all_pids[@]}" ]]; do
    local parent="${all_pids[$index]}"
    local children
    children="$(pgrep -P "$parent" 2>/dev/null || true)"
    if [[ -n "$children" ]]; then
      while IFS= read -r child; do
        [[ -n "$child" ]] || continue
        all_pids+=("$child")
      done <<<"$children"
    fi
    index=$((index + 1))
  done

  printf '%s\n' "${all_pids[@]}"
}

reap_test_process() {
  if [[ -z "$TEST_PID" || "$TEST_REAPED" == true ]]; then
    return
  fi

  if wait "$TEST_PID"; then
    TEST_PROCESS_STATUS=0
  else
    TEST_PROCESS_STATUS=$?
  fi
  TEST_REAPED=true
}

process_is_running() {
  local pid="$1"
  local process_state

  kill -0 "$pid" 2>/dev/null || return 1
  process_state="$(LC_ALL=C ps -p "$pid" -o stat= 2>/dev/null | LC_ALL=C awk '{$1=$1; print}' || true)"
  [[ "$process_state" == Z* ]] && return 1
  return 0
}

terminate_test_process() {
  local observation_status=0

  if [[ -z "$TEST_PID" || "$TEST_REAPED" == true ]]; then
    return
  fi

  FLOWTAB_PERF_PROCESS_IDENTITY_RECORDS=()
  TEST_PROCESS_IDENTITY_CAPTURE_FAILED=false
  if [[ -n "$TEST_START_IDENTITY" ]]; then
    flowtab_perf_remember_process_identity "$TEST_PID" "$TEST_START_IDENTITY"
  fi
  capture_test_process_tree_identities
  if [[ "${#FLOWTAB_PERF_PROCESS_IDENTITY_RECORDS[@]}" -eq 0 ]]; then
    if [[ "$TEST_PROCESS_IDENTITY_CAPTURE_FAILED" == true ]]; then
      TERMINATION_TIMED_OUT=true
    fi
    reap_test_process
    return
  fi

  flowtab_perf_signal_active_process_identities \
    TERM \
    "${FLOWTAB_PERF_PROCESS_IDENTITY_RECORDS[@]}"
  flowtab_perf_wait_for_process_identities_exit \
    "$TEST_TERMINATION_GRACE_MILLISECONDS" \
    "$TEST_TERMINATION_POLL_INTERVAL_SECONDS" \
    "${FLOWTAB_PERF_PROCESS_IDENTITY_RECORDS[@]}" \
    || observation_status=$?

  if [[ "$observation_status" -ne 0 ]]; then
    echo "Escalating UI process tree to SIGKILL after evidence watchdog." >&2
    capture_test_process_tree_identities
    flowtab_perf_signal_active_process_identities \
      KILL \
      "${FLOWTAB_PERF_PROCESS_IDENTITY_RECORDS[@]}"
    observation_status=0
    flowtab_perf_wait_for_process_identities_exit \
      "$TEST_KILL_CONFIRMATION_WATCHDOG_MILLISECONDS" \
      "$TEST_TERMINATION_POLL_INTERVAL_SECONDS" \
      "${FLOWTAB_PERF_PROCESS_IDENTITY_RECORDS[@]}" \
      || observation_status=$?
  fi

  if [[ "$observation_status" -ne 0 ]] \
    || [[ "$TEST_PROCESS_IDENTITY_CAPTURE_FAILED" == true ]]; then
    TERMINATION_TIMED_OUT=true
  fi
  reap_test_process
}

capture_test_process_tree_identities() {
  local process_pid

  while IFS= read -r process_pid; do
    [[ -n "$process_pid" ]] || continue
    if ! flowtab_perf_capture_process_identity "$process_pid"; then
      TEST_PROCESS_IDENTITY_CAPTURE_FAILED=true
      echo "Failed to capture an exact UI test-process identity." >&2
      echo "unmetCondition=processIdentityCaptured pid=${process_pid}" >&2
      echo "lastObservation: ${FLOWTAB_PERF_PROCESS_EXIT_LAST_OBSERVATION}" >&2
    fi
  done < <(descendant_pids "$TEST_PID")
}

handle_signal() {
  local signal_exit_code="$1"
  trap - EXIT INT TERM
  CURRENT_STAGE="interrupted"
  terminate_test_process
  cleanup_independent_applications || true
  load_ui_run_status
  write_status "$signal_exit_code" || true
  exit "$signal_exit_code"
}

handle_exit() {
  local script_exit_code="$1"
  trap - EXIT INT TERM
  terminate_test_process
  cleanup_independent_applications || true
  load_ui_run_status
  if [[ "$TERMINATION_TIMED_OUT" == true && "$script_exit_code" -eq 0 ]]; then
    CURRENT_STAGE="termination_timed_out"
    script_exit_code=1
  fi
  if [[ "$APPLICATION_CLEANUP_FAILED" == true && "$script_exit_code" -eq 0 ]]; then
    CURRENT_STAGE="application_cleanup_failed"
    script_exit_code=1
  fi
  if ! write_status "$script_exit_code"; then
    echo "Failed to preserve run status: $STATUS_FILE" >&2
    if [[ "$script_exit_code" -eq 0 ]]; then
      script_exit_code=1
    fi
  fi
  exit "$script_exit_code"
}

trap 'handle_signal 130' INT
trap 'handle_signal 143' TERM
trap 'handle_exit "$?"' EXIT

test_process_is_live() {
  local process_state

  kill -0 "$TEST_PID" 2>/dev/null || return 1
  process_state="$(LC_ALL=C ps -p "$TEST_PID" -o stat= 2>/dev/null | LC_ALL=C awk '{$1=$1; print}' || true)"
  [[ "$process_state" != Z* ]]
}

target_loss_can_be_terminal() {
  [[ "$IDENTITY_VERDICT" == "identity_match_lost" || "$IDENTITY_VERDICT" == "sample_unavailable" ]]
}

observe_ui_process_tree_completion_after_target_exit() {
  local observation_status=0

  FLOWTAB_PERF_PROCESS_IDENTITY_RECORDS=()
  TEST_PROCESS_IDENTITY_CAPTURE_FAILED=false
  if [[ -z "$TEST_START_IDENTITY" ]]; then
    echo "Could not observe UI process-tree completion without the wrapper identity." >&2
    echo "unmetCondition=processIdentityCaptured pid=${TEST_PID}" >&2
    echo "targetTerminationVerdict=${TARGET_TERMINATION_VERDICT}" >&2
    return 2
  fi
  flowtab_perf_remember_process_identity "$TEST_PID" "$TEST_START_IDENTITY"
  capture_test_process_tree_identities
  if [[ "$TEST_PROCESS_IDENTITY_CAPTURE_FAILED" == true ]]; then
    echo "targetTerminationVerdict=${TARGET_TERMINATION_VERDICT}" >&2
    return 2
  fi
  flowtab_perf_wait_for_process_identities_exit \
    "$TARGET_EXIT_COMPLETION_WATCHDOG_MILLISECONDS" \
    "$TARGET_EXIT_COMPLETION_POLL_INTERVAL_SECONDS" \
    "${FLOWTAB_PERF_PROCESS_IDENTITY_RECORDS[@]}" \
    || observation_status=$?
  if [[ "$observation_status" -ne 0 ]]; then
    echo "targetTerminationVerdict=${TARGET_TERMINATION_VERDICT}" >&2
    return "$observation_status"
  fi
  reap_test_process
}

run_ui_test() {
  local wrapper_status
  local log_status
  local pipeline_status
  local status_temp="${UI_RUN_STATUS_FILE}.tmp"
  local -a runner_arguments=("${UI_TEST_ACTION}")

  if [[ "${HAS_CUSTOM_BUILD_ROOT}" == true ]]; then
    runner_arguments+=(--build-root "${CHILD_UI_BUILD_ROOT}")
  fi
  if [[ "${SKIP_SPACE_FIXTURES}" == true ]]; then
    runner_arguments+=(--skip-space-fixtures)
  fi

  trap - EXIT INT TERM
  set +e
  "$UI_TEST_RUNNER" \
    "${runner_arguments[@]}" \
    --ui-test-app-path "$EXPECTED_APP_PATH" \
    --output-root "$UI_ATTEMPT_DIR" \
    "-only-testing:${TEST_FILTER}" 2>&1 | tee "$UI_LOG_FILE"
  pipeline_status=("${PIPESTATUS[@]}")
  wrapper_status="${pipeline_status[0]}"
  log_status="${pipeline_status[1]}"
  set -e

  {
    printf 'wrapper_exit_code=%s\n' "$wrapper_status"
    printf 'log_exit_code=%s\n' "$log_status"
  } >"$status_temp"
  mv "$status_temp" "$UI_RUN_STATUS_FILE"

  if [[ "$log_status" -ne 0 ]]; then
    exit 1
  fi
  exit "$wrapper_status"
}

echo "Evidence directory: $OUTPUT_DIR"
echo "[1/3] Starting runtime topology UI pressure: $TEST_FILTER"
CURRENT_STAGE="capturing_application_baseline"
if ! capture_application_baseline; then
  CURRENT_STAGE="application_baseline_failed"
  exit 1
fi
CURRENT_STAGE="running_ui_test"
capture_preexisting_target_identities
LAUNCH_REQUEST_EPOCH_SECONDS="$(date +%s)"
LAUNCH_REQUEST_MONOTONIC_NS="$(monotonic_ns)"
run_ui_test &
TEST_PID=$!
TEST_REAPED=false
TEST_START_IDENTITY="$(
  flowtab_perf_process_start_identity "$TEST_PID" 2>/dev/null || true
)"

CURRENT_STAGE="awaiting_target_launch"
if ! await_target_launch; then
  IDENTITY_FAILED=true
  CURRENT_STAGE="target_launch_identity_failed"
  echo "Could not bind the pressure run to one post-request FlowTab process matching the frozen UI App identity." >&2
  exit 1
fi

echo "[2/3] Sampling FlowTab CPU/RSS every ${SAMPLE_INTERVAL_SECONDS}s..."
CURRENT_STAGE="sampling"
while test_process_is_live; do
  if ! sample_flowtab; then
    TARGET_TERMINATION_VERDICT="$IDENTITY_VERDICT"
    if target_loss_can_be_terminal \
      && observe_ui_process_tree_completion_after_target_exit; then
      TARGET_TERMINAL_EXIT_OBSERVED=true
      IDENTITY_VERDICT="matched"
      break
    fi
    SAMPLING_FAILED=true
    IDENTITY_FAILED=true
    break
  fi
  sleep "$SAMPLE_INTERVAL_SECONDS"
done

if [[ "$IDENTITY_FAILED" == true ]]; then
  CURRENT_STAGE="identity_binding_failed"
  echo "Runtime target identity changed or became ambiguous during sampling." >&2
  exit 1
fi

reap_test_process
load_ui_run_status

echo "[3/3] Aggregating samples..."
CURRENT_STAGE="aggregating"
set +e
/usr/bin/python3 "$EVIDENCE_TOOL" summarize \
  "$SAMPLES_FILE" \
  "$SUMMARY_FILE" \
  "$SAMPLE_INTERVAL_SECONDS" \
  "$TEST_FILTER" \
  "$IDENTITY_CHECK_COUNT" \
  "$IDENTITY_VERDICT" \
  "$UI_WRAPPER_STATUS" \
  "$PID_BINDINGS_FILE" \
  "$LAUNCH_RECEIPT_FILE" 2>&1 | tee "$SUMMARY_LOG_FILE"
summary_pipeline_status=("${PIPESTATUS[@]}")
SUMMARY_STATUS="${summary_pipeline_status[0]}"
SUMMARY_LOG_STATUS="${summary_pipeline_status[1]}"
set -e

echo "Samples: $SAMPLES_FILE"
echo "PID bindings: $PID_BINDINGS_FILE"
echo "Target launch receipt: $LAUNCH_RECEIPT_FILE"
echo "Summary: $SUMMARY_FILE"
echo "UI child attempt: $UI_ATTEMPT_DIR"

if [[ "$UI_LOG_STATUS" != "null" && "$UI_LOG_STATUS" -ne 0 ]]; then
  CURRENT_STAGE="ui_log_failed"
  exit 1
fi
if [[ ! -f "${UI_ATTEMPT_DIR}/results/FlowTabUITests.xcresult/Info.plist" ]]; then
  CURRENT_STAGE="ui_result_bundle_invalid"
  echo "UI pressure result bundle is incomplete: ${UI_ATTEMPT_DIR}/results/FlowTabUITests.xcresult" >&2
  exit 1
fi
if [[ "$UI_WRAPPER_STATUS" != "null" && "$UI_WRAPPER_STATUS" -ne 0 ]]; then
  CURRENT_STAGE="ui_test_failed"
  echo "UI pressure test failed; tailing $UI_LOG_FILE" >&2
  tail -n 80 "$UI_LOG_FILE" >&2
  exit "$UI_WRAPPER_STATUS"
fi
if [[ "$TEST_PROCESS_STATUS" =~ ^[0-9]+$ ]] && [[ "$TEST_PROCESS_STATUS" -ne 0 ]]; then
  CURRENT_STAGE="ui_process_failed"
  exit "$TEST_PROCESS_STATUS"
fi
if [[ "$SAMPLING_FAILED" == true ]]; then
  CURRENT_STAGE="sampling_failed"
  echo "FlowTab was discovered but could not be sampled." >&2
  exit 1
fi
if [[ "$SUMMARY_LOG_STATUS" -ne 0 ]]; then
  CURRENT_STAGE="summary_log_failed"
  exit 1
fi
if [[ "$SUMMARY_STATUS" -ne 0 ]]; then
  CURRENT_STAGE="summary_failed"
  exit "$SUMMARY_STATUS"
fi

CURRENT_STAGE="completed"
