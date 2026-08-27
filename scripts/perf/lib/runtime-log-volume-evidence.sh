#!/usr/bin/env bash

FLOWTAB_RUNTIME_LOG_VOLUME_CONDITION="not_measured"
FLOWTAB_RUNTIME_LOG_FILE_COUNT=""
FLOWTAB_RUNTIME_LOG_LINE_COUNT=""
FLOWTAB_RUNTIME_LOG_RETAINED_BYTES=""
FLOWTAB_RUNTIME_LOG_BYTES_PER_SECOND=""
FLOWTAB_RUNTIME_LOG_MEGABYTES_PER_MINUTE=""
FLOWTAB_RUNTIME_LOG_BYTES_PER_COMPLETED_SWITCH=""
FLOWTAB_RUNTIME_LOG_ESTIMATED_20MB_RETENTION_MINUTES=""
FLOWTAB_RUNTIME_LOG_BUDGET_MB_PER_MINUTE=""
FLOWTAB_RUNTIME_LOG_BUDGET_SATISFIED=""

flowtab_runtime_log_reset_volume_evidence() {
  FLOWTAB_RUNTIME_LOG_VOLUME_CONDITION="not_measured"
  FLOWTAB_RUNTIME_LOG_FILE_COUNT=""
  FLOWTAB_RUNTIME_LOG_LINE_COUNT=""
  FLOWTAB_RUNTIME_LOG_RETAINED_BYTES=""
  FLOWTAB_RUNTIME_LOG_BYTES_PER_SECOND=""
  FLOWTAB_RUNTIME_LOG_MEGABYTES_PER_MINUTE=""
  FLOWTAB_RUNTIME_LOG_BYTES_PER_COMPLETED_SWITCH=""
  FLOWTAB_RUNTIME_LOG_ESTIMATED_20MB_RETENTION_MINUTES=""
  FLOWTAB_RUNTIME_LOG_BUDGET_MB_PER_MINUTE=""
  FLOWTAB_RUNTIME_LOG_BUDGET_SATISFIED=""
}

flowtab_runtime_log_is_positive_decimal() {
  local value="$1"
  [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]] \
    && LC_ALL=C awk -v value="$value" 'BEGIN { exit !(value > 0) }'
}

flowtab_runtime_log_normalize_decimal() {
  local value="$1"
  local integer_part="${value%%.*}"

  while [[ "$integer_part" == 0?* ]]; do
    integer_part="${integer_part#0}"
  done
  if [[ "$value" == *.* ]]; then
    printf '%s.%s\n' "$integer_part" "${value#*.}"
  else
    printf '%s\n' "$integer_part"
  fi
}

flowtab_runtime_log_measure_volume() {
  local logs_directory="$1"
  local actual_elapsed_seconds="$2"
  local completed_switch_count="$3"
  local maximum_log_file_count="$4"
  local budget_mb_per_minute="${5:-}"
  local file_bytes
  local file_lines
  local log_file
  local had_nullglob=false

  flowtab_runtime_log_reset_volume_evidence
  FLOWTAB_RUNTIME_LOG_BUDGET_MB_PER_MINUTE="$budget_mb_per_minute"

  if ! flowtab_runtime_log_is_positive_decimal "$actual_elapsed_seconds" \
    || [[ ! "$completed_switch_count" =~ ^[0-9]+$ ]] \
    || [[ "$completed_switch_count" -eq 0 ]] \
    || [[ ! "$maximum_log_file_count" =~ ^[0-9]+$ ]] \
    || [[ "$maximum_log_file_count" -eq 0 ]] \
    || { [[ -n "$budget_mb_per_minute" ]] \
      && ! flowtab_runtime_log_is_positive_decimal "$budget_mb_per_minute"; }; then
    FLOWTAB_RUNTIME_LOG_VOLUME_CONDITION="measurement_failed"
    return 1
  fi

  FLOWTAB_RUNTIME_LOG_FILE_COUNT=0
  FLOWTAB_RUNTIME_LOG_LINE_COUNT=0
  FLOWTAB_RUNTIME_LOG_RETAINED_BYTES=0
  FLOWTAB_RUNTIME_LOG_BYTES_PER_SECOND="0.000000"
  FLOWTAB_RUNTIME_LOG_MEGABYTES_PER_MINUTE="0.000000"
  FLOWTAB_RUNTIME_LOG_BYTES_PER_COMPLETED_SWITCH="0.000"

  if [[ ! -e "$logs_directory" ]]; then
    FLOWTAB_RUNTIME_LOG_VOLUME_CONDITION="zero"
    if [[ -n "$budget_mb_per_minute" ]]; then
      FLOWTAB_RUNTIME_LOG_BUDGET_SATISFIED=true
    fi
    return 0
  fi
  if [[ ! -d "$logs_directory" || ! -r "$logs_directory" || ! -x "$logs_directory" ]]; then
    FLOWTAB_RUNTIME_LOG_VOLUME_CONDITION="measurement_failed"
    return 1
  fi

  if shopt -q nullglob; then
    had_nullglob=true
  else
    shopt -s nullglob
  fi
  for log_file in "$logs_directory"/*.log; do
    FLOWTAB_RUNTIME_LOG_FILE_COUNT=$((
      FLOWTAB_RUNTIME_LOG_FILE_COUNT + 1
    ))
    if [[ ! -f "$log_file" || ! -r "$log_file" ]]; then
      FLOWTAB_RUNTIME_LOG_VOLUME_CONDITION="measurement_failed"
      if [[ "$had_nullglob" == false ]]; then
        shopt -u nullglob
      fi
      return 1
    fi
    if ! file_bytes="$(LC_ALL=C wc -c <"$log_file")" \
      || ! file_lines="$(LC_ALL=C wc -l <"$log_file")"; then
      FLOWTAB_RUNTIME_LOG_VOLUME_CONDITION="measurement_failed"
      if [[ "$had_nullglob" == false ]]; then
        shopt -u nullglob
      fi
      return 1
    fi
    file_bytes="${file_bytes//[[:space:]]/}"
    file_lines="${file_lines//[[:space:]]/}"
    if [[ ! "$file_bytes" =~ ^[0-9]+$ ]] \
      || [[ ! "$file_lines" =~ ^[0-9]+$ ]]; then
      FLOWTAB_RUNTIME_LOG_VOLUME_CONDITION="measurement_failed"
      if [[ "$had_nullglob" == false ]]; then
        shopt -u nullglob
      fi
      return 1
    fi
    FLOWTAB_RUNTIME_LOG_RETAINED_BYTES=$((
      FLOWTAB_RUNTIME_LOG_RETAINED_BYTES + file_bytes
    ))
    FLOWTAB_RUNTIME_LOG_LINE_COUNT=$((
      FLOWTAB_RUNTIME_LOG_LINE_COUNT + file_lines
    ))
  done
  if [[ "$had_nullglob" == false ]]; then
    shopt -u nullglob
  fi

  FLOWTAB_RUNTIME_LOG_BYTES_PER_SECOND="$({
    LC_ALL=C awk \
      -v bytes="$FLOWTAB_RUNTIME_LOG_RETAINED_BYTES" \
      -v seconds="$actual_elapsed_seconds" \
      'BEGIN { printf "%.6f", bytes / seconds }'
  })"
  FLOWTAB_RUNTIME_LOG_MEGABYTES_PER_MINUTE="$({
    LC_ALL=C awk \
      -v bytes="$FLOWTAB_RUNTIME_LOG_RETAINED_BYTES" \
      -v seconds="$actual_elapsed_seconds" \
      'BEGIN { printf "%.6f", bytes * 60 / seconds / 1000000 }'
  })"
  FLOWTAB_RUNTIME_LOG_BYTES_PER_COMPLETED_SWITCH="$({
    LC_ALL=C awk \
      -v bytes="$FLOWTAB_RUNTIME_LOG_RETAINED_BYTES" \
      -v switches="$completed_switch_count" \
      'BEGIN { printf "%.3f", bytes / switches }'
  })"
  if [[ "$FLOWTAB_RUNTIME_LOG_RETAINED_BYTES" -gt 0 ]]; then
    FLOWTAB_RUNTIME_LOG_ESTIMATED_20MB_RETENTION_MINUTES="$({
      LC_ALL=C awk \
        -v rate="$FLOWTAB_RUNTIME_LOG_BYTES_PER_SECOND" \
        'BEGIN { printf "%.3f", 20000000 / rate / 60 }'
    })"
  fi

  if [[ "$FLOWTAB_RUNTIME_LOG_FILE_COUNT" -ge "$maximum_log_file_count" ]]; then
    FLOWTAB_RUNTIME_LOG_VOLUME_CONDITION="capacity_saturated"
    if [[ -n "$budget_mb_per_minute" ]]; then
      FLOWTAB_RUNTIME_LOG_BUDGET_SATISFIED=false
    fi
    return 2
  fi

  if [[ "$FLOWTAB_RUNTIME_LOG_RETAINED_BYTES" -eq 0 ]]; then
    FLOWTAB_RUNTIME_LOG_VOLUME_CONDITION="zero"
    if [[ -n "$budget_mb_per_minute" ]]; then
      FLOWTAB_RUNTIME_LOG_BUDGET_SATISFIED=true
    fi
    return 0
  fi

  FLOWTAB_RUNTIME_LOG_VOLUME_CONDITION="measured"
  if [[ -n "$budget_mb_per_minute" ]]; then
    if LC_ALL=C awk \
      -v actual="$FLOWTAB_RUNTIME_LOG_MEGABYTES_PER_MINUTE" \
      -v budget="$budget_mb_per_minute" \
      'BEGIN { exit !(actual <= budget) }'; then
      FLOWTAB_RUNTIME_LOG_BUDGET_SATISFIED=true
    else
      FLOWTAB_RUNTIME_LOG_BUDGET_SATISFIED=false
      return 3
    fi
  fi
  return 0
}
