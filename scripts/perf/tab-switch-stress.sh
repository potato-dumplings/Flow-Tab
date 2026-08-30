#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_ROOT="$ROOT_DIR/.build-local"
HOST_ARCH="$(uname -m)"
PROCESS_EXIT_OBSERVATION_PATH="${ROOT_DIR}/scripts/perf/lib/process-exit-observation.sh"
TAB_SWITCH_EVIDENCE_PATH="${ROOT_DIR}/scripts/perf/lib/tab-switch-stress-evidence.sh"
RUNTIME_LOG_VOLUME_EVIDENCE_PATH="${ROOT_DIR}/scripts/perf/lib/runtime-log-volume-evidence.sh"
RUNTIME_TOPOLOGY_TARGET_PATH="${ROOT_DIR}/scripts/perf/lib/runtime-topology-target.sh"
MONOTONIC_CLOCK="${ROOT_DIR}/scripts/perf/lib/monotonic-clock.sh"
EVIDENCE_TOOL="${ROOT_DIR}/scripts/perf/lib/tab-switch-isolated-pressure-evidence.py"
APP_TERMINATION_GRACE_MILLISECONDS=2000
APP_TERMINATION_POLL_INTERVAL_SECONDS=0.1

# shellcheck source=scripts/perf/lib/process-exit-observation.sh
source "${PROCESS_EXIT_OBSERVATION_PATH}"
# shellcheck source=scripts/perf/lib/tab-switch-stress-evidence.sh
source "${TAB_SWITCH_EVIDENCE_PATH}"
# shellcheck source=scripts/perf/lib/runtime-log-volume-evidence.sh
source "${RUNTIME_LOG_VOLUME_EVIDENCE_PATH}"
# shellcheck source=scripts/perf/lib/runtime-topology-target.sh
source "${RUNTIME_TOPOLOGY_TARGET_PATH}"

usage() {
  cat <<'EOF'
Usage: ./scripts/perf/tab-switch-stress.sh [duration_seconds] [switch_interval_ms] [sample_interval_seconds] [--runtime-log-level <DEBUG|INFO|WARN|ERROR>] [--max-runtime-log-mb-per-minute <positive-decimal>] [--build-root <dir>] [--output-dir <dir>]

Runs the isolated state/log attribution lane and preserves its evidence.

Positional arguments:
  duration_seconds         Stress duration in seconds (default: 30)
  switch_interval_ms       Delay between tab switches in milliseconds (default: 20)
  sample_interval_seconds  CPU/RSS interval sampling cadence (default: 0.5)

Options:
  --build-root <dir>       Resolve DerivedData below this directory.
  --output-dir <dir>       New evidence directory. The leaf must not already exist.
                           Defaults to a unique directory under .build-local/tab-switch-stress/.
  --runtime-log-level <DEBUG|INFO|WARN|ERROR>
                           Runtime log level injected through TestingSupport (default: ERROR).
  --max-runtime-log-mb-per-minute <positive-decimal>
                           Fail when active-window logical log writes exceed this budget.
                           The budget gate is disabled by default.
  -h, --help               Show this help.

Outputs:
  samples.csv              Raw interval CPU and RSS samples
  summary.txt              Active-window metrics and whole-run diagnostics
  build.log                xcodebuild output and failures
  app.log                  Stress-process stdout and stderr
  status.json              Schema-v5 machine-readable evidence and verdict
EOF
}

OUTPUT_DIR=""
HAS_CUSTOM_OUTPUT_DIR=false
HAS_CUSTOM_BUILD_ROOT=false
HAS_RUNTIME_LOG_LEVEL=false
HAS_RUNTIME_LOG_BUDGET=false
RUNTIME_LOG_LEVEL="ERROR"
MAX_RUNTIME_LOG_MB_PER_MINUTE=""
POSITIONAL_ARGS=()
APP_PID=""
APP_START_IDENTITY=""
APP_REAPED=true
APP_EXIT_STATUS="null"
STATUS_FILE=""
RUNNER_STATUS_FILE=""
SUMMARY_FILE=""
SAMPLES_FILE=""
APP_HOME=""
CURRENT_STAGE="argument_parsing"
XCODEBUILD_STATUS="null"
BUILD_TEE_STATUS="null"
SAMPLE_INDEX=0
SAMPLING_FAILED=false
EVIDENCE_PARSE_STATUS="null"
IDENTITY_CHECK_COUNT=0
IDENTITY_VERDICT="not_evaluated"
START_IDENTITY_CAPTURED=false
FINAL_EVIDENCE_WRITTEN=false
DURATION_SECONDS="null"
SWITCH_INTERVAL_MS="null"
SAMPLE_INTERVAL_SECONDS="null"

json_number_or_null() {
  local value="$1"
  if [[ "$value" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
    printf '%s' "$value"
  else
    printf 'null'
  fi
}

write_runner_status() {
  local final_exit_code="$1"
  local runner_status_temp
  local runtime_log_budget_json
  local app_pid_json
  local required_switches_json
  local completed_switches_json
  local home_switches_json
  local logs_switches_json
  local settings_switches_json
  local elapsed_nanoseconds_json
  local started_uptime_json
  local completed_uptime_json

  [[ -n "$RUNNER_STATUS_FILE" ]] || return 0

  runner_status_temp="${RUNNER_STATUS_FILE}.tmp"
  runtime_log_budget_json="$(
    json_number_or_null "$MAX_RUNTIME_LOG_MB_PER_MINUTE"
  )"
  app_pid_json="$(json_number_or_null "$APP_PID")"
  required_switches_json="$(
    json_number_or_null "$FLOWTAB_TAB_SWITCH_PLANNED_SWITCH_COUNT"
  )"
  completed_switches_json="$(
    json_number_or_null "$FLOWTAB_TAB_SWITCH_COMPLETED_SWITCH_COUNT"
  )"
  home_switches_json="$(
    json_number_or_null "$FLOWTAB_TAB_SWITCH_HOME_SWITCH_COUNT"
  )"
  logs_switches_json="$(
    json_number_or_null "$FLOWTAB_TAB_SWITCH_LOGS_SWITCH_COUNT"
  )"
  settings_switches_json="$(
    json_number_or_null "$FLOWTAB_TAB_SWITCH_SETTINGS_SWITCH_COUNT"
  )"
  elapsed_nanoseconds_json="$(
    json_number_or_null "$FLOWTAB_TAB_SWITCH_ELAPSED_NANOSECONDS"
  )"
  started_uptime_json="$(
    json_number_or_null "$FLOWTAB_TAB_SWITCH_STARTED_UPTIME_NANOSECONDS"
  )"
  completed_uptime_json="$(
    json_number_or_null "$FLOWTAB_TAB_SWITCH_COMPLETED_UPTIME_NANOSECONDS"
  )"

  {
    printf '{\n'
    printf '  "schema_version": 1,\n'
    printf '  "stage": "%s",\n' "$CURRENT_STAGE"
    printf '  "duration_seconds": %s,\n' \
      "$(json_number_or_null "$DURATION_SECONDS")"
    printf '  "switch_interval_milliseconds": %s,\n' \
      "$(json_number_or_null "$SWITCH_INTERVAL_MS")"
    printf '  "sample_interval_seconds": %s,\n' \
      "$(json_number_or_null "$SAMPLE_INTERVAL_SECONDS")"
    printf '  "runtime_log_level": "%s",\n' "$RUNTIME_LOG_LEVEL"
    printf '  "max_runtime_log_mb_per_minute": %s,\n' \
      "$runtime_log_budget_json"
    printf '  "completion_evidence": "%s",\n' \
      "$FLOWTAB_TAB_SWITCH_EVIDENCE_CONDITION"
    printf '  "required_switches": %s,\n' "$required_switches_json"
    printf '  "completed_switches": %s,\n' "$completed_switches_json"
    printf '  "home_switches": %s,\n' "$home_switches_json"
    printf '  "logs_switches": %s,\n' "$logs_switches_json"
    printf '  "settings_switches": %s,\n' "$settings_switches_json"
    printf '  "elapsed_nanoseconds": %s,\n' "$elapsed_nanoseconds_json"
    printf '  "stress_started_uptime_nanoseconds": %s,\n' \
      "$started_uptime_json"
    printf '  "stress_completed_uptime_nanoseconds": %s,\n' \
      "$completed_uptime_json"
    printf '  "app_pid": %s,\n' "$app_pid_json"
    printf '  "start_identity_captured": %s,\n' \
      "$START_IDENTITY_CAPTURED"
    printf '  "identity_check_count": %s,\n' "$IDENTITY_CHECK_COUNT"
    printf '  "identity_verdict": "%s",\n' "$IDENTITY_VERDICT"
    printf '  "final_exit_code": %s,\n' "$final_exit_code"
    printf '  "xcodebuild_exit_code": %s,\n' "$XCODEBUILD_STATUS"
    printf '  "build_log_exit_code": %s,\n' "$BUILD_TEE_STATUS"
    printf '  "app_exit_code": %s,\n' \
      "$(json_number_or_null "$APP_EXIT_STATUS")"
    printf '  "sampling_failed": %s,\n' "$SAMPLING_FAILED"
    printf '  "evidence_parse_exit_code": %s\n' \
      "$(json_number_or_null "$EVIDENCE_PARSE_STATUS")"
    printf '}\n'
  } >"$runner_status_temp" || return 1
  mv "$runner_status_temp" "$RUNNER_STATUS_FILE"
}

preserve_final_evidence() {
  local final_exit_code="$1"
  local evaluator_status=0
  local -a evaluator_arguments

  if [[ "$FINAL_EVIDENCE_WRITTEN" == true || -z "$STATUS_FILE" ]]; then
    return 0
  fi
  write_runner_status "$final_exit_code" || return 1
  evaluator_arguments=(
    evaluate
    --runner-status "$RUNNER_STATUS_FILE"
    --samples "$SAMPLES_FILE"
    --runtime-home "$APP_HOME"
    --output "$STATUS_FILE"
    --summary "$SUMMARY_FILE"
  )
  /usr/bin/python3 "$EVIDENCE_TOOL" "${evaluator_arguments[@]}" \
    || evaluator_status=$?
  if [[ -f "$STATUS_FILE" && -f "$SUMMARY_FILE" ]]; then
    FINAL_EVIDENCE_WRITTEN=true
  fi
  return "$evaluator_status"
}

reap_app() {
  if [[ -z "$APP_PID" || "$APP_REAPED" == true ]]; then
    return
  fi
  if wait "$APP_PID"; then
    APP_EXIT_STATUS=0
  else
    APP_EXIT_STATUS=$?
  fi
  APP_REAPED=true
}

terminate_app() {
  local observation_status=0

  if [[ -z "$APP_PID" || "$APP_REAPED" == true ]]; then
    return
  fi
  if kill -0 "$APP_PID" 2>/dev/null; then
    kill -TERM "$APP_PID" 2>/dev/null || true
    flowtab_perf_wait_for_process_exit \
      "$APP_PID" \
      "$APP_START_IDENTITY" \
      "$APP_TERMINATION_GRACE_MILLISECONDS" \
      "$APP_TERMINATION_POLL_INTERVAL_SECONDS" \
      || observation_status=$?
    if [[ "$observation_status" -ne 0 ]] \
      && [[ "$FLOWTAB_PERF_PROCESS_EXIT_CONDITION" != "identity_changed" ]]; then
      echo "Escalating child termination to SIGKILL after evidence watchdog." >&2
      kill -KILL "$APP_PID" 2>/dev/null || true
    fi
  fi
  reap_app
}

handle_signal() {
  local signal_exit_code="$1"
  trap - EXIT INT TERM
  CURRENT_STAGE="interrupted"
  terminate_app
  preserve_final_evidence "$signal_exit_code" || true
  exit "$signal_exit_code"
}

handle_exit() {
  local script_exit_code="$1"
  local evidence_status=0

  trap - EXIT INT TERM
  terminate_app
  preserve_final_evidence "$script_exit_code" || evidence_status=$?
  if [[ "$evidence_status" -ne 0 && "$script_exit_code" -eq 0 ]]; then
    script_exit_code=1
  fi
  exit "$script_exit_code"
}

trap 'handle_signal 130' INT
trap 'handle_signal 143' TERM
trap 'handle_exit "$?"' EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
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
      [[ -n "$BUILD_ROOT" ]] || { echo "Missing value for --build-root." >&2; exit 2; }
      HAS_CUSTOM_BUILD_ROOT=true
      shift
      ;;
    --output-dir)
      if [[ "$HAS_CUSTOM_OUTPUT_DIR" == true || $# -lt 2 || -z "$2" ]]; then
        echo "--output-dir requires one non-empty value and may only be specified once." >&2
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
      [[ -n "$OUTPUT_DIR" ]] || { echo "Missing value for --output-dir." >&2; exit 2; }
      HAS_CUSTOM_OUTPUT_DIR=true
      shift
      ;;
    --runtime-log-level)
      if [[ "$HAS_RUNTIME_LOG_LEVEL" == true || $# -lt 2 || -z "$2" ]]; then
        echo "--runtime-log-level requires one value and may only be specified once." >&2
        exit 2
      fi
      RUNTIME_LOG_LEVEL="$(printf '%s' "$2" | LC_ALL=C tr '[:lower:]' '[:upper:]')"
      HAS_RUNTIME_LOG_LEVEL=true
      shift 2
      ;;
    --runtime-log-level=*)
      if [[ "$HAS_RUNTIME_LOG_LEVEL" == true ]]; then
        echo "--runtime-log-level may only be specified once." >&2
        exit 2
      fi
      RUNTIME_LOG_LEVEL="$(printf '%s' "${1#*=}" | LC_ALL=C tr '[:lower:]' '[:upper:]')"
      [[ -n "$RUNTIME_LOG_LEVEL" ]] || { echo "Missing runtime log level." >&2; exit 2; }
      HAS_RUNTIME_LOG_LEVEL=true
      shift
      ;;
    --max-runtime-log-mb-per-minute)
      if [[ "$HAS_RUNTIME_LOG_BUDGET" == true || $# -lt 2 || -z "$2" ]]; then
        echo "--max-runtime-log-mb-per-minute requires one value and may only be specified once." >&2
        exit 2
      fi
      MAX_RUNTIME_LOG_MB_PER_MINUTE="$2"
      HAS_RUNTIME_LOG_BUDGET=true
      shift 2
      ;;
    --max-runtime-log-mb-per-minute=*)
      if [[ "$HAS_RUNTIME_LOG_BUDGET" == true ]]; then
        echo "--max-runtime-log-mb-per-minute may only be specified once." >&2
        exit 2
      fi
      MAX_RUNTIME_LOG_MB_PER_MINUTE="${1#*=}"
      [[ -n "$MAX_RUNTIME_LOG_MB_PER_MINUTE" ]] || { echo "Missing runtime log budget." >&2; exit 2; }
      HAS_RUNTIME_LOG_BUDGET=true
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

case "$RUNTIME_LOG_LEVEL" in
  DEBUG|INFO|WARN|ERROR) ;;
  *) echo "Invalid --runtime-log-level value: $RUNTIME_LOG_LEVEL" >&2; exit 2 ;;
esac

if [[ -n "$MAX_RUNTIME_LOG_MB_PER_MINUTE" ]] \
  && ! flowtab_runtime_log_is_positive_decimal "$MAX_RUNTIME_LOG_MB_PER_MINUTE"; then
  echo "Invalid --max-runtime-log-mb-per-minute value: $MAX_RUNTIME_LOG_MB_PER_MINUTE" >&2
  exit 2
fi
if [[ -n "$MAX_RUNTIME_LOG_MB_PER_MINUTE" ]]; then
  MAX_RUNTIME_LOG_MB_PER_MINUTE="$(
    flowtab_runtime_log_normalize_decimal "$MAX_RUNTIME_LOG_MB_PER_MINUTE"
  )"
fi

if [[ ${#POSITIONAL_ARGS[@]} -gt 3 ]]; then
  echo "Expected at most three positional arguments." >&2
  usage >&2
  exit 2
fi

DURATION_SECONDS="${POSITIONAL_ARGS[0]:-30}"
SWITCH_INTERVAL_MS="${POSITIONAL_ARGS[1]:-20}"
SAMPLE_INTERVAL_SECONDS="${POSITIONAL_ARGS[2]:-0.5}"
for numeric_argument in \
  "$DURATION_SECONDS" "$SWITCH_INTERVAL_MS" "$SAMPLE_INTERVAL_SECONDS"; do
  if ! flowtab_runtime_log_is_positive_decimal "$numeric_argument"; then
    echo "Duration, switch interval, and sample interval must be positive decimals." >&2
    exit 2
  fi
done

DERIVED_DATA_DIR="${BUILD_ROOT}/DerivedData"
SOURCE_PACKAGES_DIR="${BUILD_ROOT}/source-packages"
BUILD_TMP_DIR="${BUILD_ROOT}/tmp"
BUILD_HOME_DIR="${BUILD_ROOT}/home"
MODULE_CACHE_DIR="${BUILD_ROOT}/module-cache"
APP_BIN="$DERIVED_DATA_DIR/Build/Products/Testing/Flow Tab.app/Contents/MacOS/FlowTab"

if [[ "$HAS_CUSTOM_OUTPUT_DIR" == true ]]; then
  mkdir -p "$(dirname "$OUTPUT_DIR")"
  if ! mkdir "$OUTPUT_DIR" 2>/dev/null; then
    if [[ -e "$OUTPUT_DIR" ]]; then
      echo "Output directory must not already exist: $OUTPUT_DIR" >&2
    else
      echo "Could not create output directory: $OUTPUT_DIR" >&2
    fi
    exit 1
  fi
else
  RUN_TIMESTAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
  OUTPUT_BASE="${BUILD_ROOT}/tab-switch-stress/results-$RUN_TIMESTAMP"
  mkdir -p "$(dirname "$OUTPUT_BASE")"
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

SAMPLES_FILE="$OUTPUT_DIR/samples.csv"
SUMMARY_FILE="$OUTPUT_DIR/summary.txt"
BUILD_LOG="$OUTPUT_DIR/build.log"
APP_LOG="$OUTPUT_DIR/app.log"
STATUS_FILE="$OUTPUT_DIR/status.json"
RUNNER_STATUS_FILE="$OUTPUT_DIR/runner-status.json"
APP_HOME="$OUTPUT_DIR/home"

mkdir -p \
  "$APP_HOME" \
  "$BUILD_TMP_DIR" \
  "$BUILD_HOME_DIR" \
  "$MODULE_CACHE_DIR/clang" \
  "$MODULE_CACHE_DIR/swift" \
  "$SOURCE_PACKAGES_DIR"
printf '%s\n' \
  'sample,timestamp,pid,interval_started_uptime_nanoseconds,interval_completed_uptime_nanoseconds,cpu_percent,rss_kb' \
  >"$SAMPLES_FILE"

echo "Evidence directory: $OUTPUT_DIR"
CURRENT_STAGE="building"
echo "[1/3] Building Testing app (derived data in ${DERIVED_DATA_DIR})..."
set +e
TMPDIR="${BUILD_TMP_DIR}/" \
HOME="$BUILD_HOME_DIR" \
CFFIXED_USER_HOME="$BUILD_HOME_DIR" \
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR/clang" \
SWIFT_MODULECACHE_PATH="$MODULE_CACHE_DIR/swift" \
SWIFTPM_PACKAGECACHE="$SOURCE_PACKAGES_DIR" \
xcodebuild \
  -project "$ROOT_DIR/FlowTab.xcodeproj" \
  -scheme FlowTab \
  -configuration Testing \
  -destination "platform=macOS,arch=${HOST_ARCH}" \
  -sdk macosx \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tee "$BUILD_LOG"
build_pipeline_status=("${PIPESTATUS[@]}")
XCODEBUILD_STATUS="${build_pipeline_status[0]}"
BUILD_TEE_STATUS="${build_pipeline_status[1]}"
set -e

if [[ "$BUILD_TEE_STATUS" -ne 0 ]]; then
  CURRENT_STAGE="build_log_failed"
  exit 1
fi
if [[ "$XCODEBUILD_STATUS" -ne 0 ]]; then
  CURRENT_STAGE="build_failed"
  exit "$XCODEBUILD_STATUS"
fi
if [[ ! -x "$APP_BIN" ]]; then
  CURRENT_STAGE="app_missing"
  echo "App binary not found: $APP_BIN" >&2
  exit 1
fi

CURRENT_STAGE="sampling"
echo "[2/3] Launching stress mode for ${DURATION_SECONDS}s (switch interval ${SWITCH_INTERVAL_MS}ms)..."
HOME="$APP_HOME" \
CFFIXED_USER_HOME="$APP_HOME" \
FLOWTAB_UI_TESTING=1 \
"$APP_BIN" \
  --flowtab-tab-stress \
  --flowtab-tab-stress-prewarm-tabs \
  --flowtab-tab-stress-duration "$DURATION_SECONDS" \
  --flowtab-tab-stress-interval-ms "$SWITCH_INTERVAL_MS" \
  --flowtab-tab-stress-runtime-log-level "$RUNTIME_LOG_LEVEL" \
  --flowtab-ui-runtime-log-level "$RUNTIME_LOG_LEVEL" \
  >"$APP_LOG" 2>&1 &
APP_PID=$!
APP_REAPED=false
APP_START_IDENTITY="$(
  flowtab_perf_process_start_identity "$APP_PID" 2>/dev/null || true
)"
if [[ -z "$APP_START_IDENTITY" ]]; then
  IDENTITY_VERDICT="launch_readback_failed"
  SAMPLING_FAILED=true
  CURRENT_STAGE="process_identity_failed"
  terminate_app
else
  START_IDENTITY_CAPTURED=true
  IDENTITY_VERDICT="matched"
fi

PREVIOUS_CPU_CENTISECONDS=""
PREVIOUS_SAMPLE_UPTIME_NANOSECONDS=""
while [[ "$SAMPLING_FAILED" == false ]] \
  && kill -0 "$APP_PID" 2>/dev/null; do
  CURRENT_START_IDENTITY="$(
    flowtab_perf_process_start_identity "$APP_PID" 2>/dev/null || true
  )"
  if [[ -z "$CURRENT_START_IDENTITY" ]]; then
    if kill -0 "$APP_PID" 2>/dev/null; then
      IDENTITY_VERDICT="readback_failed"
      SAMPLING_FAILED=true
    fi
    break
  fi
  IDENTITY_CHECK_COUNT=$((IDENTITY_CHECK_COUNT + 1))
  if [[ "$CURRENT_START_IDENTITY" != "$APP_START_IDENTITY" ]]; then
    IDENTITY_VERDICT="changed"
    SAMPLING_FAILED=true
    break
  fi

  set +e
  SAMPLE_LINE="$(
    LC_ALL=C /bin/ps -p "$APP_PID" -o stat= -o cputime= -o rss= \
      | LC_ALL=C /usr/bin/awk '{$1=$1; print}'
  )"
  sample_status=$?
  set -e
  if [[ "$sample_status" -ne 0 || -z "$SAMPLE_LINE" ]]; then
    if kill -0 "$APP_PID" 2>/dev/null; then
      SAMPLING_FAILED=true
      IDENTITY_VERDICT="sample_readback_failed"
    fi
    break
  fi
  read -r PROCESS_STATE CPU_TIME RSS_KB <<<"$SAMPLE_LINE"
  if [[ "$PROCESS_STATE" == Z* ]]; then
    break
  fi
  CURRENT_CPU_CENTISECONDS="$(
    flowtab_perf_cpu_time_centiseconds "$CPU_TIME" 2>/dev/null || true
  )"
  CURRENT_SAMPLE_UPTIME_NANOSECONDS="$(monotonic_ns 2>/dev/null || true)"
  if [[ ! "$CURRENT_CPU_CENTISECONDS" =~ ^[0-9]+$ ]] \
    || [[ ! "$CURRENT_SAMPLE_UPTIME_NANOSECONDS" =~ ^[0-9]+$ ]] \
    || [[ ! "$RSS_KB" =~ ^[0-9]+$ ]]; then
    SAMPLING_FAILED=true
    IDENTITY_VERDICT="sample_parse_failed"
    break
  fi

  if [[ -n "$PREVIOUS_CPU_CENTISECONDS" ]]; then
    INTERVAL_NANOSECONDS=$((
      CURRENT_SAMPLE_UPTIME_NANOSECONDS
        - PREVIOUS_SAMPLE_UPTIME_NANOSECONDS
    ))
    CPU_PERCENT="$(
      flowtab_perf_interval_cpu_percent \
        "$CURRENT_CPU_CENTISECONDS" \
        "$PREVIOUS_CPU_CENTISECONDS" \
        "$INTERVAL_NANOSECONDS" 2>/dev/null || true
    )"
    if [[ ! "$CPU_PERCENT" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
      SAMPLING_FAILED=true
      IDENTITY_VERDICT="cpu_interval_failed"
      break
    fi
    SAMPLE_INDEX=$((SAMPLE_INDEX + 1))
    printf '%s,%s,%s,%s,%s,%s,%s\n' \
      "$SAMPLE_INDEX" \
      "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
      "$APP_PID" \
      "$PREVIOUS_SAMPLE_UPTIME_NANOSECONDS" \
      "$CURRENT_SAMPLE_UPTIME_NANOSECONDS" \
      "$CPU_PERCENT" \
      "$RSS_KB" >>"$SAMPLES_FILE"
  fi
  PREVIOUS_CPU_CENTISECONDS="$CURRENT_CPU_CENTISECONDS"
  PREVIOUS_SAMPLE_UPTIME_NANOSECONDS="$CURRENT_SAMPLE_UPTIME_NANOSECONDS"
  sleep "$SAMPLE_INTERVAL_SECONDS"
done

if [[ "$SAMPLING_FAILED" == true ]]; then
  terminate_app
else
  reap_app
fi

set +e
flowtab_tab_switch_parse_completion_evidence \
  "$APP_LOG" \
  "$RUNTIME_LOG_LEVEL"
EVIDENCE_PARSE_STATUS=$?
set -e

echo "[3/3] Evaluating active-window evidence..."
CURRENT_STAGE="evaluating"
set +e
preserve_final_evidence 0
EVALUATOR_STATUS=$?
set -e

echo "Preserved raw samples: $SAMPLES_FILE"
echo "Preserved summary: $SUMMARY_FILE"
echo "Preserved build log: $BUILD_LOG"
echo "Preserved app log: $APP_LOG"
echo "Preserved schema-v5 status: $STATUS_FILE"

if [[ "$EVALUATOR_STATUS" -ne 0 ]]; then
  exit "$EVALUATOR_STATUS"
fi
