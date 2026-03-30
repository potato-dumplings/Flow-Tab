#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_DIR="$ROOT_DIR/.build-local/DerivedData"
APP_BIN="$DERIVED_DATA_DIR/Build/Products/Debug/FlowTabApp.app/Contents/MacOS/FlowTabApp"

DURATION_SECONDS="${1:-30}"
SWITCH_INTERVAL_MS="${2:-20}"
SAMPLE_INTERVAL_SECONDS="${3:-0.5}"

echo "[1/3] Building Debug app (derived data in .build-local/DerivedData)..."
xcodebuild \
  -project "$ROOT_DIR/FlowTabApp.xcodeproj" \
  -scheme FlowTabApp \
  -configuration Debug \
  -sdk macosx \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  build >/dev/null

if [[ ! -x "$APP_BIN" ]]; then
  echo "App binary not found: $APP_BIN" >&2
  exit 1
fi

SAMPLES_FILE="$(mktemp)"
trap 'rm -f "$SAMPLES_FILE"' EXIT

echo "[2/3] Launching stress mode for ${DURATION_SECONDS}s (switch interval ${SWITCH_INTERVAL_MS}ms)..."
"$APP_BIN" \
  --flowtab-tab-stress \
  --flowtab-tab-stress-duration "$DURATION_SECONDS" \
  --flowtab-tab-stress-interval-ms "$SWITCH_INTERVAL_MS" &
APP_PID=$!

while kill -0 "$APP_PID" 2>/dev/null; do
  SAMPLE_LINE="$(ps -p "$APP_PID" -o %cpu= -o rss= -o %mem= | awk '{$1=$1; print}')"
  if [[ -n "$SAMPLE_LINE" ]]; then
    echo "$SAMPLE_LINE" >>"$SAMPLES_FILE"
  fi
  sleep "$SAMPLE_INTERVAL_SECONDS"
done

wait "$APP_PID" || true

echo "[3/3] Aggregating CPU / memory stats..."
awk '
BEGIN {
  cpu_sum = 0
  cpu_max = 0
  rss_sum_kb = 0
  rss_max_kb = 0
  mem_pct_sum = 0
  mem_pct_max = 0
  count = 0
}
{
  cpu = $1 + 0
  rss_kb = $2 + 0
  mem_pct = $3 + 0

  cpu_sum += cpu
  rss_sum_kb += rss_kb
  mem_pct_sum += mem_pct
  count += 1

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

  printf("Samples: %d\n", count)
  printf("CPU: avg=%.2f%% peak=%.2f%%\n", avg_cpu, cpu_max)
  printf("RSS: avg=%.2fMB peak=%.2fMB\n", avg_rss_mb, max_rss_mb)
  printf("MEM%%: avg=%.3f%% peak=%.3f%%\n", avg_mem_pct, mem_pct_max)
}
' "$SAMPLES_FILE"
