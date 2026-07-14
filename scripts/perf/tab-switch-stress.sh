#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_ROOT="$ROOT_DIR/.build-local"
HOST_ARCH="$(uname -m)"

usage() {
  cat <<'EOF'
Usage: ./scripts/perf/tab-switch-stress.sh [duration_seconds] [switch_interval_ms] [sample_interval_seconds] [--build-root <dir>] [--output-dir <dir>]

Runs the tab-switch stress scenario and preserves its evidence.

Positional arguments:
  duration_seconds         Stress duration in seconds (default: 30)
  switch_interval_ms       Delay between tab switches in milliseconds (default: 20)
  sample_interval_seconds  CPU/RSS sampling cadence in seconds (default: 0.5)

Options:
  --build-root <dir>       Resolve DerivedData below this directory.
  --output-dir <dir>       New evidence directory. The leaf must not already exist.
                           Defaults to a unique directory under .build-local/tab-switch-stress/.
  -h, --help               Show this help.

Outputs:
  samples.csv              Raw timestamped CPU, RSS, and memory samples
  summary.txt              Run configuration and aggregate statistics
  build.log                xcodebuild output and failures
  app.log                  Stress-process stdout and stderr
  status.json              Stage and child-process exit status
EOF
}

OUTPUT_DIR=""
HAS_CUSTOM_OUTPUT_DIR=false
HAS_CUSTOM_BUILD_ROOT=false
POSITIONAL_ARGS=()
APP_PID=""
APP_REAPED=true
APP_EXIT_STATUS="not_started"
STATUS_FILE=""
CURRENT_STAGE="argument_parsing"
XCODEBUILD_STATUS="null"
BUILD_TEE_STATUS="null"
SUMMARY_STATUS="null"
SUMMARY_TEE_STATUS="null"
SAMPLE_INDEX=0
SAMPLING_FAILED=false

write_status() {
  local final_exit_code="$1"
  local status_temp
  local app_exit_code_json="null"
  local sampling_failed_json="false"

  if [[ -z "$STATUS_FILE" ]]; then
    return 0
  fi

  if [[ "$APP_EXIT_STATUS" =~ ^[0-9]+$ ]]; then
    app_exit_code_json="$APP_EXIT_STATUS"
  fi
  if [[ "$SAMPLING_FAILED" == true ]]; then
    sampling_failed_json="true"
  fi

  status_temp="${STATUS_FILE}.tmp"
  {
    printf '{\n'
    printf '  "schema_version": 1,\n'
    printf '  "runner_kind": "tab_switch_stress",\n'
    printf '  "stage": "%s",\n' "$CURRENT_STAGE"
    printf '  "final_exit_code": %s,\n' "$final_exit_code"
    printf '  "xcodebuild_exit_code": %s,\n' "$XCODEBUILD_STATUS"
    printf '  "build_log_exit_code": %s,\n' "$BUILD_TEE_STATUS"
    printf '  "app_exit_code": %s,\n' "$app_exit_code_json"
    printf '  "sampling_failed": %s,\n' "$sampling_failed_json"
    printf '  "sample_count": %s,\n' "$SAMPLE_INDEX"
    printf '  "summary_exit_code": %s,\n' "$SUMMARY_STATUS"
    printf '  "summary_log_exit_code": %s\n' "$SUMMARY_TEE_STATUS"
    printf '}\n'
  } >"$status_temp" || return 1
  mv "$status_temp" "$STATUS_FILE"
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
  local wait_attempt=0
  local process_state=""

  if [[ -z "$APP_PID" || "$APP_REAPED" == true ]]; then
    return
  fi

  if kill -0 "$APP_PID" 2>/dev/null; then
    kill -TERM "$APP_PID" 2>/dev/null || true
    while kill -0 "$APP_PID" 2>/dev/null && [[ "$wait_attempt" -lt 20 ]]; do
      if process_state="$(LC_ALL=C ps -p "$APP_PID" -o stat= 2>/dev/null | LC_ALL=C awk '{$1=$1; print}')" && [[ "$process_state" == Z* ]]; then
        break
      fi
      sleep 0.1
      wait_attempt=$((wait_attempt + 1))
    done
    if kill -0 "$APP_PID" 2>/dev/null && [[ "$process_state" != Z* ]]; then
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
  write_status "$signal_exit_code" || true
  exit "$signal_exit_code"
}

handle_exit() {
  local script_exit_code="$1"
  trap - EXIT INT TERM
  terminate_app
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
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --output-dir." >&2
        usage >&2
        exit 2
      fi
      if [[ -z "$2" ]]; then
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

if [[ ${#POSITIONAL_ARGS[@]} -gt 3 ]]; then
  echo "Expected at most three positional arguments." >&2
  usage >&2
  exit 2
fi

DURATION_SECONDS="${POSITIONAL_ARGS[0]:-30}"
SWITCH_INTERVAL_MS="${POSITIONAL_ARGS[1]:-20}"
SAMPLE_INTERVAL_SECONDS="${POSITIONAL_ARGS[2]:-0.5}"
DERIVED_DATA_DIR="${BUILD_ROOT}/DerivedData"
APP_BIN="$DERIVED_DATA_DIR/Build/Products/Debug/Flow Tab.app/Contents/MacOS/FlowTab"

if [[ "$HAS_CUSTOM_OUTPUT_DIR" == true ]]; then
  if ! mkdir -p "$(dirname "$OUTPUT_DIR")"; then
    echo "Could not create output parent directory: $(dirname "$OUTPUT_DIR")" >&2
    exit 1
  fi
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
  if ! mkdir -p "$(dirname "$OUTPUT_BASE")"; then
    echo "Could not create default output parent: $(dirname "$OUTPUT_BASE")" >&2
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

SAMPLES_FILE="$OUTPUT_DIR/samples.csv"
SUMMARY_FILE="$OUTPUT_DIR/summary.txt"
BUILD_LOG="$OUTPUT_DIR/build.log"
APP_LOG="$OUTPUT_DIR/app.log"
STATUS_FILE="$OUTPUT_DIR/status.json"

printf 'sample_index,captured_at_utc,cpu_percent,rss_kb,mem_percent\n' >"$SAMPLES_FILE"

echo "Evidence directory: $OUTPUT_DIR"

CURRENT_STAGE="building"
echo "[1/3] Building Debug app (derived data in ${DERIVED_DATA_DIR})..."
set +e
xcodebuild \
  -project "$ROOT_DIR/FlowTab.xcodeproj" \
  -scheme FlowTab \
  -configuration Debug \
  -destination "platform=macOS,arch=${HOST_ARCH}" \
  -sdk macosx \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  build 2>&1 | tee "$BUILD_LOG"
build_pipeline_status=("${PIPESTATUS[@]}")
XCODEBUILD_STATUS="${build_pipeline_status[0]}"
BUILD_TEE_STATUS="${build_pipeline_status[1]}"
set -e

if [[ "$BUILD_TEE_STATUS" -ne 0 ]]; then
  CURRENT_STAGE="build_log_failed"
  echo "Failed to preserve build log: $BUILD_LOG" >&2
  exit 1
fi

if [[ "$XCODEBUILD_STATUS" -ne 0 ]]; then
  CURRENT_STAGE="build_failed"
  echo "Debug app build failed with exit code $XCODEBUILD_STATUS. Build log: $BUILD_LOG" >&2
  exit "$XCODEBUILD_STATUS"
fi

if [[ ! -x "$APP_BIN" ]]; then
  CURRENT_STAGE="app_missing"
  echo "App binary not found: $APP_BIN" >&2
  exit 1
fi

CURRENT_STAGE="sampling"
echo "[2/3] Launching stress mode for ${DURATION_SECONDS}s (switch interval ${SWITCH_INTERVAL_MS}ms)..."
"$APP_BIN" \
  --flowtab-tab-stress \
  --flowtab-tab-stress-duration "$DURATION_SECONDS" \
  --flowtab-tab-stress-interval-ms "$SWITCH_INTERVAL_MS" \
  >"$APP_LOG" 2>&1 &
APP_PID=$!
APP_REAPED=false

while kill -0 "$APP_PID" 2>/dev/null; do
  if ! SAMPLE_LINE="$(LC_ALL=C ps -p "$APP_PID" -o stat= -o %cpu= -o rss= -o %mem= | LC_ALL=C awk '{$1=$1; print}')"; then
    if kill -0 "$APP_PID" 2>/dev/null; then
      echo "Failed to sample the running stress process." >&2
      SAMPLING_FAILED=true
      terminate_app
    fi
    break
  fi
  if [[ -n "$SAMPLE_LINE" ]]; then
    read -r PROCESS_STATE CPU_PERCENT RSS_KB MEM_PERCENT <<<"$SAMPLE_LINE"
    if [[ "$PROCESS_STATE" == Z* ]]; then
      break
    fi
    SAMPLE_INDEX=$((SAMPLE_INDEX + 1))
    printf '%d,%s,%s,%s,%s\n' \
      "$SAMPLE_INDEX" \
      "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
      "$CPU_PERCENT" \
      "$RSS_KB" \
      "$MEM_PERCENT" >>"$SAMPLES_FILE"
  fi
  sleep "$SAMPLE_INTERVAL_SECONDS"
done

reap_app

echo "[3/3] Aggregating CPU / memory stats..."
CURRENT_STAGE="aggregating"
set +e
{
  printf 'Duration: %ss\n' "$DURATION_SECONDS"
  printf 'Switch interval: %sms\n' "$SWITCH_INTERVAL_MS"
  printf 'Sample interval: %ss\n' "$SAMPLE_INTERVAL_SECONDS"
  printf 'App exit status: %s\n' "$APP_EXIT_STATUS"
  printf 'Sampling status: %s\n' "$([[ "$SAMPLING_FAILED" == true ]] && printf failed || printf completed)"
  printf 'Samples file: %s\n\n' "$SAMPLES_FILE"

  LC_ALL=C awk -F, '
BEGIN {
  cpu_sum = 0
  cpu_max = 0
  rss_sum_kb = 0
  rss_max_kb = 0
  mem_pct_sum = 0
  mem_pct_max = 0
  count = 0
}
NR == 1 { next }
{
  cpu = $3 + 0
  rss_kb = $4 + 0
  mem_pct = $5 + 0

  cpu_sum += cpu
  rss_sum_kb += rss_kb
  mem_pct_sum += mem_pct
  count += 1
  cpu_values[count] = cpu
  rss_values[count] = rss_kb
  mem_pct_values[count] = mem_pct

  if (cpu > cpu_max) cpu_max = cpu
  if (rss_kb > rss_max_kb) rss_max_kb = rss_kb
  if (mem_pct > mem_pct_max) mem_pct_max = mem_pct
}
END {
  if (count == 0) {
    print "No samples collected."
    exit 1
  }

  avg_cpu = cpu_sum / count
  avg_rss_mb = (rss_sum_kb / count) / 1024
  max_rss_mb = rss_max_kb / 1024
  avg_mem_pct = mem_pct_sum / count

  # macOS awk does not provide a portable asort(), and sample sets are small.
  for (i = 2; i <= count; i += 1) {
    cpu_value = cpu_values[i]
    rss_value = rss_values[i]
    mem_pct_value = mem_pct_values[i]
    j = i - 1
    while (j >= 1 && cpu_values[j] > cpu_value) {
      cpu_values[j + 1] = cpu_values[j]
      j -= 1
    }
    cpu_values[j + 1] = cpu_value

    j = i - 1
    while (j >= 1 && rss_values[j] > rss_value) {
      rss_values[j + 1] = rss_values[j]
      j -= 1
    }
    rss_values[j + 1] = rss_value

    j = i - 1
    while (j >= 1 && mem_pct_values[j] > mem_pct_value) {
      mem_pct_values[j + 1] = mem_pct_values[j]
      j -= 1
    }
    mem_pct_values[j + 1] = mem_pct_value
  }
  p95_index = int((95 * count + 99) / 100)
  p95_cpu = cpu_values[p95_index]
  p95_rss_mb = rss_values[p95_index] / 1024
  p95_mem_pct = mem_pct_values[p95_index]

  printf("Samples: %d\n", count)
  printf("CPU: avg=%.2f%% p95=%.2f%% max=%.2f%%\n", avg_cpu, p95_cpu, cpu_max)
  printf("RSS: avg=%.2fMB p95=%.2fMB max=%.2fMB\n", avg_rss_mb, p95_rss_mb, max_rss_mb)
  printf("MEM%%: avg=%.3f%% p95=%.3f%% max=%.3f%%\n", avg_mem_pct, p95_mem_pct, mem_pct_max)
}
' "$SAMPLES_FILE"
} | tee "$SUMMARY_FILE"
summary_pipeline_status=("${PIPESTATUS[@]}")
SUMMARY_STATUS="${summary_pipeline_status[0]}"
SUMMARY_TEE_STATUS="${summary_pipeline_status[1]}"
set -e

if [[ "$SUMMARY_TEE_STATUS" -ne 0 ]]; then
  CURRENT_STAGE="summary_log_failed"
  echo "Failed to preserve stress summary: $SUMMARY_FILE" >&2
  exit 1
fi

echo "Preserved raw samples: $SAMPLES_FILE"
echo "Preserved summary: $SUMMARY_FILE"
echo "Preserved build log: $BUILD_LOG"
echo "Preserved app log: $APP_LOG"

if [[ "$SAMPLING_FAILED" == true ]]; then
  CURRENT_STAGE="sampling_failed"
  exit 1
fi

if [[ "$APP_EXIT_STATUS" -ne 0 ]]; then
  CURRENT_STAGE="app_failed"
  echo "Stress process failed with exit code $APP_EXIT_STATUS." >&2
  exit "$APP_EXIT_STATUS"
fi

if [[ "$SUMMARY_STATUS" -ne 0 ]]; then
  CURRENT_STAGE="summary_failed"
  exit "$SUMMARY_STATUS"
fi

CURRENT_STAGE="completed"
