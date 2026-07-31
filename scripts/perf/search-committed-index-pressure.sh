#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RESULTS_ROOT="${ROOT_DIR}/.build-local/search-committed-index-pressure"
FLOWTABTESTS_RUNNER="${ROOT_DIR}/scripts/testing/run-flowtabtests-local.sh"
MONOTONIC_CLOCK="${ROOT_DIR}/scripts/perf/lib/monotonic-clock.sh"
PROCESS_EXIT_OBSERVATION_PATH="${ROOT_DIR}/scripts/perf/lib/process-exit-observation.sh"
TEST_TERMINATION_GRACE_MILLISECONDS=2000
TEST_KILL_CONFIRMATION_WATCHDOG_MILLISECONDS=2000
TEST_TERMINATION_POLL_INTERVAL_SECONDS=0.1

# shellcheck source=scripts/perf/lib/process-exit-observation.sh
source "${PROCESS_EXIT_OBSERVATION_PATH}"

usage() {
  cat <<'EOF'
Usage: ./scripts/perf/search-committed-index-pressure.sh [sample_interval_seconds] --scenario <realistic|stress> --scenario-duration-seconds <seconds> [--build-root <dir>] [--output-dir <dir>]

Runs the committed-index Search pressure scenario while sampling the
FlowTabTests process tree and preserving every child test invocation.

Positional arguments:
  sample_interval_seconds  CPU/RSS sampling cadence in seconds (default: 0.5)

Options:
  --scenario <name>        Required workload rhythm: realistic or stress.
  --scenario-duration-seconds <seconds>
                           Required active sampling duration; minimum 30 seconds.
  --build-root <dir>       Resolve child FlowTabTests build products and caches
                           below this directory.
  --output-dir <dir>       New evidence directory. The leaf must not already exist.
                           Defaults to a unique directory under
                           .build-local/search-committed-index-pressure/.
  -h, --help               Show this help.

Outputs:
  process-samples.csv      Raw process-tree CPU/RSS samples
  summary.txt              Aggregate pressure statistics and test metrics
  child-attempts.jsonl     Build/test child attempt outcomes
  test-loop-status.txt     Last batch and child/log exit codes
  logs/                    Aggregate build, test, and summary logs
  attempts/flowtabtests/   Unique FlowTabTests wrapper output roots
  status.json              Top-level stage and child-process exit status
EOF
}

OUTPUT_DIR=""
HAS_CUSTOM_OUTPUT_DIR=false
HAS_CUSTOM_BUILD_ROOT=false
HAS_SCENARIO=false
HAS_SCENARIO_DURATION=false
BUILD_ROOT=""
SCENARIO=""
SCENARIO_DURATION_SECONDS=""
POSITIONAL_ARGS=()
TEST_PID=""
TEST_START_IDENTITY=""
TEST_PROCESS_IDENTITY_CAPTURE_FAILED=false
TEST_REAPED=true
TEST_PROCESS_STATUS="not_started"
STATUS_FILE=""
CURRENT_STAGE="argument_parsing"
BUILD_WRAPPER_STATUS="null"
BUILD_LOG_STATUS="null"
TEST_WRAPPER_STATUS="null"
TEST_LOG_STATUS="null"
SUMMARY_STATUS="null"
SUMMARY_LOG_STATUS="null"
SAMPLE_COUNT=0
SAMPLING_FAILED=false
TERMINATION_TIMED_OUT=false
BATCH_COUNT=0
SUCCESSFUL_BATCH_COUNT=0
ACTIVE_SAMPLING_SECONDS="null"
VALID_SAMPLE_COUNT=0
MINIMUM_SAMPLE_COUNT="null"
CADENCE_GAP_COUNT="null"
ACTIVE_SAMPLING_VERDICT="not_evaluated"
RHYTHM_CONFORMANCE_VERDICT="not_evaluated"
RHYTHM_CONTRACT_ID=""

declare -a TEST_FILTERS=()
declare -a CHILD_BUILD_ROOT_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario)
      if [[ "$HAS_SCENARIO" == true || $# -lt 2 || -z "$2" ]]; then
        echo "--scenario requires one value and may only be specified once." >&2
        exit 2
      fi
      SCENARIO="$2"
      HAS_SCENARIO=true
      shift 2
      ;;
    --scenario=*)
      if [[ "$HAS_SCENARIO" == true ]]; then
        echo "--scenario may only be specified once." >&2
        exit 2
      fi
      SCENARIO="${1#*=}"
      HAS_SCENARIO=true
      shift
      ;;
    --scenario-duration-seconds)
      if [[ "$HAS_SCENARIO_DURATION" == true || $# -lt 2 || -z "$2" ]]; then
        echo "--scenario-duration-seconds requires one value and may only be specified once." >&2
        exit 2
      fi
      SCENARIO_DURATION_SECONDS="$2"
      HAS_SCENARIO_DURATION=true
      shift 2
      ;;
    --scenario-duration-seconds=*)
      if [[ "$HAS_SCENARIO_DURATION" == true ]]; then
        echo "--scenario-duration-seconds may only be specified once." >&2
        exit 2
      fi
      SCENARIO_DURATION_SECONDS="${1#*=}"
      HAS_SCENARIO_DURATION=true
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

if [[ ${#POSITIONAL_ARGS[@]} -gt 1 ]]; then
  echo "Expected at most one positional argument." >&2
  usage >&2
  exit 2
fi

SAMPLE_INTERVAL_SECONDS="${POSITIONAL_ARGS[0]:-0.5}"
if ! LC_ALL=C awk -v value="$SAMPLE_INTERVAL_SECONDS" 'BEGIN { exit !(value ~ /^[0-9]+([.][0-9]+)?$/ && value + 0 > 0) }'; then
  echo "sample_interval_seconds must be a positive number." >&2
  exit 2
fi
if [[ "$HAS_SCENARIO" != true || "$SCENARIO" != "realistic" && "$SCENARIO" != "stress" ]]; then
  echo "--scenario must be explicitly set to realistic or stress." >&2
  exit 2
fi
if [[ "$HAS_SCENARIO_DURATION" != true ]] || ! [[ "$SCENARIO_DURATION_SECONDS" =~ ^[0-9]+$ ]] || [[ "$SCENARIO_DURATION_SECONDS" -lt 30 ]]; then
  echo "--scenario-duration-seconds must be an integer of at least 30." >&2
  exit 2
fi

MIN_SAMPLE_SECONDS="$SCENARIO_DURATION_SECONDS"
case "$SCENARIO" in
  realistic)
    RHYTHM_CONTRACT_ID="flowtab.search.realistic.v1"
    TEST_FILTERS=(
      "-only-testing:FlowTabTests/FlowTabTests/testSearchPerformanceWindowScope"
      "-only-testing:FlowTabTests/FlowTabTests/testLiveSwitcherModelSearchPressureReadsCommittedGenerationValidatedIndexWithoutSampling"
    )
    ;;
  stress)
    RHYTHM_CONTRACT_ID="flowtab.search.stress.v1"
    TEST_FILTERS=(
      "-only-testing:FlowTabTests/FlowTabTests/testSearchPressureWindowScopeUnified"
      "-only-testing:FlowTabTests/FlowTabTests/testSearchPressureWindowScopeSegmentedQueries"
      "-only-testing:FlowTabTests/FlowTabTests/testSearchPressureWindowScopeQueryWorkloadMatrix"
      "-only-testing:FlowTabTests/FlowTabTests/testLiveSwitcherModelSearchPressureReadsCommittedGenerationValidatedIndexWithoutSampling"
    )
    ;;
esac
if [[ "$HAS_CUSTOM_BUILD_ROOT" == true ]]; then
  CHILD_BUILD_ROOT_ARGS=(--build-root "${BUILD_ROOT}/flowtabtests")
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

SAMPLES_FILE="${OUTPUT_DIR}/process-samples.csv"
SUMMARY_FILE="${OUTPUT_DIR}/summary.txt"
CHILD_ATTEMPTS_FILE="${OUTPUT_DIR}/child-attempts.jsonl"
TEST_LOOP_STATUS_FILE="${OUTPUT_DIR}/test-loop-status.txt"
LOG_DIR="${OUTPUT_DIR}/logs"
BUILD_LOG_FILE="${LOG_DIR}/build-for-testing.log"
TEST_LOG_FILE="${LOG_DIR}/flowtabtests.log"
SUMMARY_LOG_FILE="${LOG_DIR}/summary.log"
STATUS_FILE="${OUTPUT_DIR}/status.json"
BUILD_ATTEMPT_DIR="${OUTPUT_DIR}/attempts/flowtabtests/build-for-testing"
WORKLOAD_STATE_FILE="${OUTPUT_DIR}/workload-state.txt"
SUMMARY_FACTS_FILE="${OUTPUT_DIR}/summary-facts.txt"

mkdir -p "$LOG_DIR"
printf 'sample,timestamp,monotonic_ns,scenario,workload_live,rhythm_conformance,rhythm_contract_id,pids,cpu_percent,rss_kb\n' >"$SAMPLES_FILE"
: >"$CHILD_ATTEMPTS_FILE"
: >"$TEST_LOG_FILE"

write_status() {
  local final_exit_code="$1"
  local status_temp="${STATUS_FILE}.tmp"
  local sampling_failed_json="false"
  local termination_timed_out_json="false"

  if [[ "$SAMPLING_FAILED" == true ]]; then
    sampling_failed_json="true"
  fi
  if [[ "$TERMINATION_TIMED_OUT" == true ]]; then
    termination_timed_out_json="true"
  fi

  {
    printf '{\n'
    printf '  "schema_version": 1,\n'
    printf '  "runner_kind": "search_committed_index_pressure",\n'
    printf '  "scenario": "%s",\n' "$SCENARIO"
    printf '  "rhythm_contract_id": "%s",\n' "$RHYTHM_CONTRACT_ID"
    printf '  "scenario_duration_seconds": %s,\n' "$SCENARIO_DURATION_SECONDS"
    printf '  "stage": "%s",\n' "$CURRENT_STAGE"
    printf '  "final_exit_code": %s,\n' "$final_exit_code"
    printf '  "build_wrapper_exit_code": %s,\n' "$BUILD_WRAPPER_STATUS"
    printf '  "build_log_exit_code": %s,\n' "$BUILD_LOG_STATUS"
    printf '  "last_test_wrapper_exit_code": %s,\n' "$TEST_WRAPPER_STATUS"
    printf '  "last_test_log_exit_code": %s,\n' "$TEST_LOG_STATUS"
    printf '  "test_process_exit_code": %s,\n' "$([[ "$TEST_PROCESS_STATUS" =~ ^[0-9]+$ ]] && printf '%s' "$TEST_PROCESS_STATUS" || printf 'null')"
    printf '  "test_batches": %s,\n' "$BATCH_COUNT"
    printf '  "successful_test_batches": %s,\n' "$SUCCESSFUL_BATCH_COUNT"
    printf '  "sampling_failed": %s,\n' "$sampling_failed_json"
    printf '  "termination_timed_out": %s,\n' "$termination_timed_out_json"
    printf '  "sample_count": %s,\n' "$SAMPLE_COUNT"
    printf '  "valid_sample_count": %s,\n' "$VALID_SAMPLE_COUNT"
    printf '  "minimum_sample_count": %s,\n' "$MINIMUM_SAMPLE_COUNT"
    printf '  "active_sampling_seconds": %s,\n' "$ACTIVE_SAMPLING_SECONDS"
    printf '  "cadence_gap_count": %s,\n' "$CADENCE_GAP_COUNT"
    printf '  "active_sampling_verdict": "%s",\n' "$ACTIVE_SAMPLING_VERDICT"
    printf '  "rhythm_conformance_verdict": "%s",\n' "$RHYTHM_CONFORMANCE_VERDICT"
    printf '  "summary_exit_code": %s,\n' "$SUMMARY_STATUS"
    printf '  "summary_log_exit_code": %s\n' "$SUMMARY_LOG_STATUS"
    printf '}\n'
  } >"$status_temp" || return 1
  mv "$status_temp" "$STATUS_FILE"
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

capture_test_process_tree_identities() {
  local process_pid

  while IFS= read -r process_pid; do
    [[ -n "$process_pid" ]] || continue
    if ! flowtab_perf_capture_process_identity "$process_pid"; then
      TEST_PROCESS_IDENTITY_CAPTURE_FAILED=true
      echo "Failed to capture an exact test-process identity." >&2
      echo "unmetCondition=processIdentityCaptured pid=${process_pid}" >&2
      echo "lastObservation: ${FLOWTAB_PERF_PROCESS_EXIT_LAST_OBSERVATION}" >&2
    fi
  done < <(descendant_pids "$TEST_PID")
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
    echo "Escalating test process tree to SIGKILL after evidence watchdog." >&2
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

load_test_loop_status() {
  local value

  if [[ ! -f "$TEST_LOOP_STATUS_FILE" ]]; then
    return 0
  fi
  value="$(awk -F= '$1 == "batch_count" { print $2 }' "$TEST_LOOP_STATUS_FILE")"
  [[ -n "$value" ]] && BATCH_COUNT="$value"
  value="$(awk -F= '$1 == "successful_batch_count" { print $2 }' "$TEST_LOOP_STATUS_FILE")"
  [[ -n "$value" ]] && SUCCESSFUL_BATCH_COUNT="$value"
  value="$(awk -F= '$1 == "last_wrapper_exit_code" { print $2 }' "$TEST_LOOP_STATUS_FILE")"
  [[ -n "$value" ]] && TEST_WRAPPER_STATUS="$value"
  value="$(awk -F= '$1 == "last_log_exit_code" { print $2 }' "$TEST_LOOP_STATUS_FILE")"
  [[ -n "$value" ]] && TEST_LOG_STATUS="$value"
  return 0
}

handle_signal() {
  local signal_exit_code="$1"
  trap - EXIT INT TERM
  CURRENT_STAGE="interrupted"
  terminate_test_process
  load_test_loop_status
  write_status "$signal_exit_code" || true
  exit "$signal_exit_code"
}

handle_exit() {
  local script_exit_code="$1"
  trap - EXIT INT TERM
  terminate_test_process
  load_test_loop_status
  if [[ "$TERMINATION_TIMED_OUT" == true && "$script_exit_code" -eq 0 ]]; then
    CURRENT_STAGE="termination_timed_out"
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

append_child_attempt() {
  local attempt_id="$1"
  local phase="$2"
  local wrapper_status="$3"
  local log_status="$4"
  local result_bundle_present="$5"

  printf '{"attempt_id":"%s","phase":"%s","wrapper_exit_code":%s,"log_exit_code":%s,"result_bundle_present":%s}\n' \
    "$attempt_id" \
    "$phase" \
    "$wrapper_status" \
    "$log_status" \
    "$result_bundle_present" >>"$CHILD_ATTEMPTS_FILE"
}

write_test_loop_status() {
  local batch_count="$1"
  local successful_batch_count="$2"
  local wrapper_status="$3"
  local log_status="$4"
  local status_temp="${TEST_LOOP_STATUS_FILE}.tmp"

  {
    printf 'batch_count=%s\n' "$batch_count"
    printf 'successful_batch_count=%s\n' "$successful_batch_count"
    printf 'last_wrapper_exit_code=%s\n' "$wrapper_status"
    printf 'last_log_exit_code=%s\n' "$log_status"
  } >"$status_temp"
  mv "$status_temp" "$TEST_LOOP_STATUS_FILE"
}

write_workload_state() {
  local phase="$1"
  local batch="$2"
  local state_temp="${WORKLOAD_STATE_FILE}.tmp"

  {
    printf 'phase=%s\n' "$phase"
    printf 'scenario=%s\n' "$SCENARIO"
    printf 'rhythm_contract_id=%s\n' "$RHYTHM_CONTRACT_ID"
    printf 'batch=%s\n' "$batch"
  } >"$state_temp"
  mv "$state_temp" "$WORKLOAD_STATE_FILE"
}

load_summary_facts() {
  local value

  [[ -f "$SUMMARY_FACTS_FILE" ]] || return 0
  value="$(awk -F= '$1 == "active_sampling_seconds" { print $2 }' "$SUMMARY_FACTS_FILE")"
  [[ -n "$value" ]] && ACTIVE_SAMPLING_SECONDS="$value"
  value="$(awk -F= '$1 == "valid_sample_count" { print $2 }' "$SUMMARY_FACTS_FILE")"
  [[ -n "$value" ]] && VALID_SAMPLE_COUNT="$value"
  value="$(awk -F= '$1 == "minimum_sample_count" { print $2 }' "$SUMMARY_FACTS_FILE")"
  [[ -n "$value" ]] && MINIMUM_SAMPLE_COUNT="$value"
  value="$(awk -F= '$1 == "cadence_gap_count" { print $2 }' "$SUMMARY_FACTS_FILE")"
  [[ -n "$value" ]] && CADENCE_GAP_COUNT="$value"
  value="$(awk -F= '$1 == "active_sampling_verdict" { print $2 }' "$SUMMARY_FACTS_FILE")"
  [[ -n "$value" ]] && ACTIVE_SAMPLING_VERDICT="$value"
  value="$(awk -F= '$1 == "rhythm_conformance_verdict" { print $2 }' "$SUMMARY_FACTS_FILE")"
  [[ -n "$value" ]] && RHYTHM_CONFORMANCE_VERDICT="$value"
}

monotonic_now_ns() {
  "$MONOTONIC_CLOCK"
}

sample_process_tree() {
  local root_pid="$1"
  local cpu_sum="0"
  local rss_sum="0"
  local joined_pids=""
  local sampled_any=false
  local pid
  local workload_phase="unknown"
  local workload_scenario="unknown"
  local workload_rhythm_contract="unknown"
  local workload_live="false"
  local rhythm_conformance="not_conformant"
  local monotonic_ns

  if [[ -f "$WORKLOAD_STATE_FILE" ]]; then
    workload_phase="$(awk -F= '$1 == "phase" { print $2 }' "$WORKLOAD_STATE_FILE")"
    workload_scenario="$(awk -F= '$1 == "scenario" { print $2 }' "$WORKLOAD_STATE_FILE")"
    workload_rhythm_contract="$(awk -F= '$1 == "rhythm_contract_id" { print $2 }' "$WORKLOAD_STATE_FILE")"
  fi
  if [[ "$workload_phase" == "running" && "$workload_scenario" == "$SCENARIO" ]]; then
    workload_live="true"
  fi
  if [[ "$workload_live" == "true" && "$workload_rhythm_contract" == "$RHYTHM_CONTRACT_ID" ]]; then
    rhythm_conformance="conformant"
  fi
  monotonic_ns="$(monotonic_now_ns)" || return 1

  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    local line
    local cpu
    local rss
    line="$(LC_ALL=C ps -p "$pid" -o %cpu= -o rss= 2>/dev/null | LC_ALL=C awk '{$1=$1; print}' || true)"
    [[ -n "$line" ]] || continue
    cpu="$(LC_ALL=C awk '{print $1}' <<<"$line")"
    rss="$(LC_ALL=C awk '{print $2}' <<<"$line")"
    cpu_sum="$(LC_ALL=C awk -v a="$cpu_sum" -v b="$cpu" 'BEGIN { printf "%.2f", a + b }')"
    rss_sum="$(LC_ALL=C awk -v a="$rss_sum" -v b="$rss" 'BEGIN { printf "%.0f", a + b }')"
    if [[ -z "$joined_pids" ]]; then
      joined_pids="$pid"
    else
      joined_pids="${joined_pids};${pid}"
    fi
    sampled_any=true
  done < <(descendant_pids "$root_pid")

  [[ "$sampled_any" == true ]] || return 1
  test_process_is_live || return 1

  SAMPLE_COUNT=$((SAMPLE_COUNT + 1))
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$SAMPLE_COUNT" \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    "$monotonic_ns" \
    "$SCENARIO" \
    "$workload_live" \
    "$rhythm_conformance" \
    "$RHYTHM_CONTRACT_ID" \
    "$joined_pids" \
    "$cpu_sum" \
    "$rss_sum" >>"$SAMPLES_FILE"
}

test_process_is_live() {
  local process_state

  kill -0 "$TEST_PID" 2>/dev/null || return 1
  process_state="$(LC_ALL=C ps -p "$TEST_PID" -o stat= 2>/dev/null | LC_ALL=C awk '{$1=$1; print}' || true)"
  [[ "$process_state" != Z* ]]
}

run_test_loop() {
  local batch=0
  local successful_batches=0
  local start_monotonic_ns
  local current_monotonic_ns
  local elapsed_seconds
  local attempt_id
  local attempt_dir
  local wrapper_status
  local log_status
  local result_bundle_present
  local pipeline_status
  local required_loop_seconds=$((MIN_SAMPLE_SECONDS + 5))

  trap - EXIT INT TERM
  start_monotonic_ns="$(monotonic_now_ns)"
  write_test_loop_status 0 0 null null
  write_workload_state preparing 0

  while true; do
    batch=$((batch + 1))
    attempt_id="$(printf 'test-batch-%04d' "$batch")"
    attempt_dir="${OUTPUT_DIR}/attempts/flowtabtests/${attempt_id}"
    printf '[SearchCommittedIndexPressureBatch] batch=%s started attempt=%s\n' "$batch" "$attempt_id" >>"$TEST_LOG_FILE"
    write_workload_state running "$batch"

    set +e
    "$FLOWTABTESTS_RUNNER" \
      test-without-building \
      "${CHILD_BUILD_ROOT_ARGS[@]}" \
      --output-root "$attempt_dir" \
      "${TEST_FILTERS[@]}" 2>&1 | tee -a "$TEST_LOG_FILE"
    pipeline_status=("${PIPESTATUS[@]}")
    wrapper_status="${pipeline_status[0]}"
    log_status="${pipeline_status[1]}"
    set -e
    write_workload_state between_batches "$batch"

    result_bundle_present=false
    if [[ -d "${attempt_dir}/results/FlowTabTests.xcresult" ]]; then
      result_bundle_present=true
    fi
    append_child_attempt "$attempt_id" test-without-building "$wrapper_status" "$log_status" "$result_bundle_present"

    if [[ "$wrapper_status" -eq 0 && "$log_status" -eq 0 ]]; then
      successful_batches=$((successful_batches + 1))
    fi
    write_test_loop_status "$batch" "$successful_batches" "$wrapper_status" "$log_status"

    current_monotonic_ns="$(monotonic_now_ns)"
    elapsed_seconds=$(( (current_monotonic_ns - start_monotonic_ns) / 1000000000 ))
    printf '[SearchCommittedIndexPressureBatch] batch=%s wrapperStatus=%s logStatus=%s elapsedSeconds=%s\n' \
      "$batch" "$wrapper_status" "$log_status" "$elapsed_seconds" >>"$TEST_LOG_FILE"

    if [[ "$log_status" -ne 0 ]]; then
      write_workload_state failed "$batch"
      exit 1
    fi
    if [[ "$wrapper_status" -ne 0 ]]; then
      write_workload_state failed "$batch"
      exit "$wrapper_status"
    fi
    if [[ "$elapsed_seconds" -ge "$required_loop_seconds" ]]; then
      break
    fi
  done
  write_workload_state completed "$batch"
}

echo "Evidence directory: $OUTPUT_DIR"
echo "[1/4] Building FlowTabTests for committed-index Search pressure..."
CURRENT_STAGE="building_flowtabtests"
set +e
"$FLOWTABTESTS_RUNNER" \
  build-for-testing \
  "${CHILD_BUILD_ROOT_ARGS[@]}" \
  --output-root "$BUILD_ATTEMPT_DIR" 2>&1 | tee "$BUILD_LOG_FILE"
build_pipeline_status=("${PIPESTATUS[@]}")
BUILD_WRAPPER_STATUS="${build_pipeline_status[0]}"
BUILD_LOG_STATUS="${build_pipeline_status[1]}"
set -e
append_child_attempt build-for-testing build-for-testing "$BUILD_WRAPPER_STATUS" "$BUILD_LOG_STATUS" false

if [[ "$BUILD_LOG_STATUS" -ne 0 ]]; then
  CURRENT_STAGE="build_log_failed"
  echo "Failed to preserve build log: $BUILD_LOG_FILE" >&2
  exit 1
fi
if [[ "$BUILD_WRAPPER_STATUS" -ne 0 ]]; then
  CURRENT_STAGE="build_failed"
  echo "FlowTabTests build failed with exit code $BUILD_WRAPPER_STATUS." >&2
  exit "$BUILD_WRAPPER_STATUS"
fi

echo "[2/4] Starting committed-index Search pressure tests..."
CURRENT_STAGE="running_tests"
run_test_loop &
TEST_PID=$!
TEST_REAPED=false
TEST_START_IDENTITY="$(
  flowtab_perf_process_start_identity "$TEST_PID" 2>/dev/null || true
)"

echo "[3/4] Sampling the test process tree every ${SAMPLE_INTERVAL_SECONDS}s for at least ${MIN_SAMPLE_SECONDS}s..."
CURRENT_STAGE="sampling"
while test_process_is_live; do
  if ! sample_process_tree "$TEST_PID" && test_process_is_live; then
    SAMPLING_FAILED=true
  fi
  sleep "$SAMPLE_INTERVAL_SECONDS"
done

reap_test_process
load_test_loop_status

echo "[4/4] Aggregating samples..."
CURRENT_STAGE="aggregating"
set +e
/usr/bin/python3 "${ROOT_DIR}/scripts/perf/lib/search-pressure-summary.py" \
  "$SAMPLES_FILE" \
  "$SUMMARY_FILE" \
  "$SAMPLE_INTERVAL_SECONDS" \
  "$MIN_SAMPLE_SECONDS" \
  "$SCENARIO" \
  "$TEST_WRAPPER_STATUS" \
  "$TEST_LOG_FILE" \
  "$SUMMARY_FACTS_FILE" \
  "$RHYTHM_CONTRACT_ID" 2>&1 | tee "$SUMMARY_LOG_FILE"
summary_pipeline_status=("${PIPESTATUS[@]}")
SUMMARY_STATUS="${summary_pipeline_status[0]}"
SUMMARY_LOG_STATUS="${summary_pipeline_status[1]}"
set -e
load_summary_facts

echo "Samples: $SAMPLES_FILE"
echo "Summary: $SUMMARY_FILE"
echo "Child attempts: $CHILD_ATTEMPTS_FILE"

if [[ "$TEST_LOG_STATUS" != "null" && "$TEST_LOG_STATUS" -ne 0 ]]; then
  CURRENT_STAGE="test_log_failed"
  exit 1
fi
if [[ "$TEST_WRAPPER_STATUS" != "null" && "$TEST_WRAPPER_STATUS" -ne 0 ]]; then
  CURRENT_STAGE="tests_failed"
  echo "Committed-index Search pressure tests failed; tailing $TEST_LOG_FILE" >&2
  tail -n 80 "$TEST_LOG_FILE" >&2
  exit "$TEST_WRAPPER_STATUS"
fi
if [[ "$SAMPLING_FAILED" == true ]]; then
  CURRENT_STAGE="sampling_failed"
  echo "Sampling failed while the pressure process was still running." >&2
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
