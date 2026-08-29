#!/usr/bin/env bash

TARGET_LAUNCH_WATCHDOG_MILLISECONDS=45000
TARGET_LAUNCH_POLL_INTERVAL_SECONDS=0.1
TARGET_MATCHING_IDENTITY_ROWS=()
TARGET_LAUNCH_ROWS=()
TARGET_LAUNCH_READBACK_ERROR=""
TARGET_LAUNCH_CLOCK_ERROR=""
TARGET_LAUNCH_LAST_OBSERVATION="none"
TARGET_LAUNCH_NOW_NS=0
TARGET_PROCESS_START_RECORD=""

# The caller resolves path and identity intent before these functions inspect live processes.
monotonic_ns() {
  "$MONOTONIC_CLOCK"
}

flowtab_perf_cpu_time_centiseconds() {
  local value="$1"

  LC_ALL=C /usr/bin/awk -v value="$value" '
    BEGIN {
      days = 0
      day_count = split(value, day_parts, "-")
      if (day_count == 2) {
        if (day_parts[1] !~ /^[0-9]+$/) exit 1
        days = day_parts[1] + 0
        value = day_parts[2]
      } else if (day_count != 1) {
        exit 1
      }

      time_count = split(value, time_parts, ":")
      if (time_count == 2) {
        hours = 0
        minutes = time_parts[1]
        seconds = time_parts[2]
      } else if (time_count == 3) {
        hours = time_parts[1]
        minutes = time_parts[2]
        seconds = time_parts[3]
      } else {
        exit 1
      }

      if (hours !~ /^[0-9]+$/ || minutes !~ /^[0-9]+$/) exit 1
      if (seconds !~ /^[0-9]+([.][0-9][0-9]?)?$/) exit 1
      if (minutes + 0 >= 60 || seconds + 0 >= 60) exit 1
      if (day_count == 2 && hours + 0 >= 24) exit 1

      total_seconds = (((days * 24 + hours) * 60 + minutes) * 60) + seconds
      printf "%.0f\n", total_seconds * 100
    }
  '
}

flowtab_perf_interval_cpu_percent() {
  local current_centiseconds="$1"
  local previous_centiseconds="$2"
  local elapsed_nanoseconds="$3"

  LC_ALL=C /usr/bin/awk \
    -v current="$current_centiseconds" \
    -v previous="$previous_centiseconds" \
    -v elapsed="$elapsed_nanoseconds" '
      BEGIN {
        if (current !~ /^[0-9]+$/ || previous !~ /^[0-9]+$/) exit 1
        if (elapsed !~ /^[0-9]+$/ || elapsed + 0 <= 0) exit 1
        if (current + 0 < previous + 0) exit 1
        printf "%.3f\n", ((current - previous) * 1000000000) / elapsed
      }
    '
}

target_identity_readback_failed() {
  TARGET_LAUNCH_READBACK_ERROR="$1"
  TARGET_LAUNCH_LAST_OBSERVATION="$1"
  echo "Target identity readback failed: $1" >&2
  return 2
}

target_process_is_active() {
  local pid="$1"
  local process_state
  local readback_status=0

  process_state="$(
    LC_ALL=C /bin/ps -p "$pid" -o state= 2>/dev/null \
      | LC_ALL=C /usr/bin/awk '{$1=$1; print}'
  )" || readback_status=$?
  if [[ "$readback_status" -ne 0 || -z "$process_state" ]]; then
    if /bin/kill -0 "$pid" 2>/dev/null; then
      target_identity_readback_failed \
        "processStateReadbackError pid=${pid} status=${readback_status}"
      return 2
    fi
    return 1
  fi
  [[ "$process_state" != Z* ]]
}

read_process_start_record() {
  local pid="$1"
  local readback_status=0
  local started_at
  local started_epoch_seconds
  local start_identity

  TARGET_PROCESS_START_RECORD=""
  started_at="$(
    LC_ALL=C /bin/ps -p "$pid" -o lstart= 2>/dev/null \
      | LC_ALL=C /usr/bin/awk '{$1=$1; print}'
  )" || readback_status=$?
  if [[ "$readback_status" -ne 0 || -z "$started_at" ]]; then
    if /bin/kill -0 "$pid" 2>/dev/null; then
      target_identity_readback_failed \
        "processStartReadbackError pid=${pid} status=${readback_status}"
      return 2
    fi
    return 1
  fi
  started_epoch_seconds="$(LC_ALL=C /bin/date -j -f '%a %b %e %T %Y' "$started_at" '+%s' 2>/dev/null || true)"
  if [[ ! "$started_epoch_seconds" =~ ^[0-9]+$ ]]; then
    target_identity_readback_failed \
      "processStartParseError pid=${pid} record=${started_at}"
    return 2
  fi
  start_identity="$(printf '%s' "$started_at" | LC_ALL=C shasum -a 256 | awk '{print $1}')"
  TARGET_PROCESS_START_RECORD="${start_identity}:${started_epoch_seconds}"
}

process_path_matches_expected() {
  local pid="$1"
  local command_name
  local command_line
  local command_name_status=0
  local command_line_status=0

  command_name="$(LC_ALL=C /bin/ps -p "$pid" -o comm= 2>/dev/null | sed 's/^[[:space:]]*//')" \
    || command_name_status=$?
  if [[ "$command_name" == "$EXPECTED_EXECUTABLE_PATH" ]]; then
    return 0
  fi

  command_line="$(LC_ALL=C /bin/ps -p "$pid" -o command= 2>/dev/null | sed 's/^[[:space:]]*//')" \
    || command_line_status=$?
  if [[ "$command_line" == "$EXPECTED_EXECUTABLE_PATH" \
    || "$command_line" == "$EXPECTED_EXECUTABLE_PATH "* ]]; then
    return 0
  fi
  if /bin/kill -0 "$pid" 2>/dev/null \
    && { [[ "$command_name_status" -ne 0 || "$command_line_status" -ne 0 ]] \
      || [[ -z "$command_name" && -z "$command_line" ]]; }; then
    target_identity_readback_failed \
      "processPathReadbackError pid=${pid} commStatus=${command_name_status} commandStatus=${command_line_status}"
    return 2
  fi
  return 1
}

read_matching_identity_rows() {
  local executable_hash_status=0
  local matching_count=0
  local pid
  local pgrep_status=0
  local process_status=0
  local current_executable_sha256
  local matching_pids

  TARGET_MATCHING_IDENTITY_ROWS=()
  TARGET_LAUNCH_READBACK_ERROR=""

  current_executable_sha256="$(
    LC_ALL=C shasum -a 256 "$EXPECTED_EXECUTABLE_PATH" 2>/dev/null \
      | LC_ALL=C awk '{print $1}'
  )" || executable_hash_status=$?
  if [[ "$executable_hash_status" -ne 0 || -z "$current_executable_sha256" ]]; then
    target_identity_readback_failed \
      "executableHashReadbackError status=${executable_hash_status} path=${EXPECTED_EXECUTABLE_PATH}"
    return 2
  fi
  if [[ "$current_executable_sha256" != "$EXPECTED_EXECUTABLE_SHA256" ]]; then
    target_identity_readback_failed \
      "executableIdentityChanged expected=${EXPECTED_EXECUTABLE_SHA256} actual=${current_executable_sha256}"
    return 2
  fi

  matching_pids="$(pgrep -x "$EXPECTED_EXECUTABLE_NAME" 2>&1)" || pgrep_status=$?
  if [[ "$pgrep_status" -eq 1 ]]; then
    TARGET_LAUNCH_LAST_OBSERVATION="matchingIdentityCount=0"
    return 0
  fi
  if [[ "$pgrep_status" -ne 0 ]]; then
    target_identity_readback_failed \
      "processListReadbackError status=${pgrep_status} output=${matching_pids}"
    return 2
  fi

  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    if target_process_is_active "$pid"; then
      process_status=0
    else
      process_status=$?
      [[ "$process_status" -eq 1 ]] && continue
      return "$process_status"
    fi
    if process_path_matches_expected "$pid"; then
      process_status=0
    else
      process_status=$?
      [[ "$process_status" -eq 1 ]] && continue
      return "$process_status"
    fi
    if read_process_start_record "$pid"; then
      TARGET_MATCHING_IDENTITY_ROWS+=("${pid}:${TARGET_PROCESS_START_RECORD}")
    else
      process_status=$?
      [[ "$process_status" -eq 1 ]] && continue
      return "$process_status"
    fi
  done <<<"$matching_pids"
  if [[ "${TARGET_MATCHING_IDENTITY_ROWS[*]+set}" == set ]]; then
    matching_count="${#TARGET_MATCHING_IDENTITY_ROWS[@]}"
  fi
  TARGET_LAUNCH_LAST_OBSERVATION="matchingIdentityCount=${matching_count} identities=${TARGET_MATCHING_IDENTITY_ROWS[*]:-none}"
}

matching_identity_rows() {
  read_matching_identity_rows || return $?
  if [[ "${TARGET_MATCHING_IDENTITY_ROWS[*]+set}" == set ]]; then
    printf '%s\n' "${TARGET_MATCHING_IDENTITY_ROWS[@]}"
  fi
}

is_preexisting_target_identity() {
  local candidate="$1"
  local existing

  while IFS= read -r existing; do
    [[ -n "$existing" ]] || continue
    [[ "$candidate" == "$existing" ]] && return 0
  done <<<"$PREEXISTING_TARGET_IDENTITIES"
  return 1
}

post_request_identity_rows() {
  local row

  read_matching_identity_rows || return $?
  for row in "${TARGET_MATCHING_IDENTITY_ROWS[@]+"${TARGET_MATCHING_IDENTITY_ROWS[@]}"}"; do
    [[ -n "$row" ]] || continue
    is_preexisting_target_identity "$row" || printf '%s\n' "$row"
  done
}

capture_preexisting_target_identities() {
  local row

  PREEXISTING_TARGET_IDENTITIES=""
  if ! read_matching_identity_rows; then
    echo "Could not capture the pre-request target identity baseline." >&2
    echo "unmetCondition=preRequestTargetIdentitiesRead" >&2
    echo "lastObservation: ${TARGET_LAUNCH_LAST_OBSERVATION}" >&2
    return 2
  fi
  for row in "${TARGET_MATCHING_IDENTITY_ROWS[@]+"${TARGET_MATCHING_IDENTITY_ROWS[@]}"}"; do
    [[ -n "$PREEXISTING_TARGET_IDENTITIES" ]] \
      && PREEXISTING_TARGET_IDENTITIES+=$'\n'
    PREEXISTING_TARGET_IDENTITIES+="$row"
  done
}

read_post_request_target_identities() {
  local post_request_count=0
  local row

  TARGET_LAUNCH_ROWS=()
  if ! read_matching_identity_rows; then
    return 2
  fi
  for row in "${TARGET_MATCHING_IDENTITY_ROWS[@]+"${TARGET_MATCHING_IDENTITY_ROWS[@]}"}"; do
    is_preexisting_target_identity "$row" || TARGET_LAUNCH_ROWS+=("$row")
  done
  if [[ "${TARGET_LAUNCH_ROWS[*]+set}" == set ]]; then
    post_request_count="${#TARGET_LAUNCH_ROWS[@]}"
  fi
  TARGET_LAUNCH_LAST_OBSERVATION="postRequestIdentityCount=${post_request_count} identities=${TARGET_LAUNCH_ROWS[*]:-none} baseline=${PREEXISTING_TARGET_IDENTITIES:-none}"
}

publish_launch_receipt() {
  /usr/bin/python3 "$EVIDENCE_TOOL" write-launch-receipt \
    "$LAUNCH_RECEIPT_FILE" \
    "$UI_APP_IDENTITY_MANIFEST_SHA256" \
    "$EXPECTED_APP_PATH" \
    "$EXPECTED_BUNDLE_ID" \
    "$EXPECTED_EXECUTABLE_SHA256" \
    "$EXPECTED_DESIGNATED_REQUIREMENT_SHA256" \
    "$PID_BINDING_POLICY_VERSION" \
    "$TARGET_STABILITY_WINDOW_MILLISECONDS" \
    "$LAUNCH_REQUEST_MONOTONIC_NS" \
    "$LAUNCH_REQUEST_EPOCH_SECONDS" \
    "$TARGET_FIRST_OBSERVED_MONOTONIC_NS" \
    "$TARGET_QUALIFIED_MONOTONIC_NS" \
    "$TARGET_PID" \
    "$TARGET_START_IDENTITY" \
    "$TARGET_START_EPOCH_SECONDS" \
    "$TARGET_OBSERVATION_COUNT" \
    "$REJECTED_TRANSIENT_IDENTITY_COUNT"
}

target_launch_read_clock() {
  local clock_status=0
  local now_monotonic_ns

  TARGET_LAUNCH_CLOCK_ERROR=""
  now_monotonic_ns="$(monotonic_ns 2>&1)" || clock_status=$?
  if [[ "$clock_status" -ne 0 || ! "$now_monotonic_ns" =~ ^[0-9]+$ ]]; then
    TARGET_LAUNCH_CLOCK_ERROR="monotonicClockError status=${clock_status} output=${now_monotonic_ns}"
    TARGET_LAUNCH_LAST_OBSERVATION="$TARGET_LAUNCH_CLOCK_ERROR"
    return 2
  fi
  TARGET_LAUNCH_NOW_NS="$now_monotonic_ns"
}

target_launch_sleep() {
  /bin/sleep "$1"
}

report_target_launch_failure() {
  local candidate_row="$1"
  local candidate_first_observed_ns="$2"
  local candidate_observation_count="$3"
  local candidate_stability_ns="$4"

  echo "Runtime target launch did not reach one stable exact identity." >&2
  echo "unmetCondition=stableUniquePostRequestIdentity" >&2
  echo "identityVerdict=${IDENTITY_VERDICT}" >&2
  echo "watchdogMilliseconds=${TARGET_LAUNCH_WATCHDOG_MILLISECONDS}" >&2
  echo "stabilityWindowMilliseconds=${TARGET_STABILITY_WINDOW_MILLISECONDS}" >&2
  echo "pollIntervalSeconds=${TARGET_LAUNCH_POLL_INTERVAL_SECONDS}" >&2
  echo "baselineIdentities=${PREEXISTING_TARGET_IDENTITIES:-none}" >&2
  echo "candidateIdentity=${candidate_row:-none}" >&2
  echo "candidateFirstObservedMonotonicNS=${candidate_first_observed_ns:-none}" >&2
  echo "candidateObservationCount=${candidate_observation_count}" >&2
  echo "candidateStabilityNanoseconds=${candidate_stability_ns}" >&2
  echo "lastCandidateRows=${TARGET_LAUNCH_ROWS[*]:-none}" >&2
  echo "lastReadbackError=${TARGET_LAUNCH_READBACK_ERROR:-none}" >&2
  echo "lastClockError=${TARGET_LAUNCH_CLOCK_ERROR:-none}" >&2
  echo "lastObservation: ${TARGET_LAUNCH_LAST_OBSERVATION}" >&2
}

await_target_launch() {
  local candidate_row=""
  local candidate_first_observed_ns=""
  local candidate_observation_count=0
  local candidate_stability_ns=0
  local discovery_deadline_ns=0
  local ever_observed_candidate=false
  local launch_row_count=0
  local observation_started_ns=""
  local previous_observation_ns=""
  local readback_status=0
  local required_stability_ns=0
  local row
  local target_start_record
  local terminal_candidate_row=""

  if [[ ! "$TARGET_LAUNCH_WATCHDOG_MILLISECONDS" =~ ^[1-9][0-9]*$ ]] \
    || [[ ! "$TARGET_LAUNCH_POLL_INTERVAL_SECONDS" =~ ^[0-9]+([.][0-9]+)?$ ]] \
    || [[ "$TARGET_LAUNCH_POLL_INTERVAL_SECONDS" =~ ^0+([.]0+)?$ ]] \
    || [[ ! "$TARGET_STABILITY_WINDOW_MILLISECONDS" =~ ^[1-9][0-9]*$ ]] \
    || [[ ! "$LAUNCH_REQUEST_MONOTONIC_NS" =~ ^[0-9]+$ ]] \
    || [[ ! "$LAUNCH_REQUEST_EPOCH_SECONDS" =~ ^[0-9]+$ ]]; then
    IDENTITY_VERDICT="launch_observation_policy_invalid"
    report_target_launch_failure "" "" 0 0
    return 2
  fi
  required_stability_ns=$((TARGET_STABILITY_WINDOW_MILLISECONDS * 1000000))

  while true; do
    readback_status=0
    read_post_request_target_identities || readback_status=$?
    launch_row_count=0
    if [[ "${TARGET_LAUNCH_ROWS[*]+set}" == set ]]; then
      launch_row_count="${#TARGET_LAUNCH_ROWS[@]}"
      for row in "${TARGET_LAUNCH_ROWS[@]}"; do
        if [[ ! "$row" =~ ^[1-9][0-9]*:[0-9a-f]{64}:[0-9]+$ ]]; then
          TARGET_LAUNCH_READBACK_ERROR="malformedIdentityRow=${row}"
          TARGET_LAUNCH_LAST_OBSERVATION="$TARGET_LAUNCH_READBACK_ERROR"
          TARGET_LAUNCH_ROWS=()
          launch_row_count=0
          readback_status=2
          break
        fi
      done
    fi
    if ! target_launch_read_clock; then
      IDENTITY_VERDICT="launch_clock_error"
      report_target_launch_failure \
        "$candidate_row" \
        "$candidate_first_observed_ns" \
        "$candidate_observation_count" \
        "$candidate_stability_ns"
      return 2
    fi
    if [[ -z "$observation_started_ns" ]]; then
      observation_started_ns="$TARGET_LAUNCH_NOW_NS"
      discovery_deadline_ns=$((
        LAUNCH_REQUEST_MONOTONIC_NS + TARGET_LAUNCH_WATCHDOG_MILLISECONDS * 1000000
      ))
    fi
    if ((TARGET_LAUNCH_NOW_NS < LAUNCH_REQUEST_MONOTONIC_NS)) \
      || [[ -n "$previous_observation_ns" \
        && "$TARGET_LAUNCH_NOW_NS" -lt "$previous_observation_ns" ]]; then
      TARGET_LAUNCH_CLOCK_ERROR="monotonicClockRegressed now=${TARGET_LAUNCH_NOW_NS} previous=${previous_observation_ns:-none} observationStart=${observation_started_ns} launchRequest=${LAUNCH_REQUEST_MONOTONIC_NS}"
      TARGET_LAUNCH_LAST_OBSERVATION="$TARGET_LAUNCH_CLOCK_ERROR"
      IDENTITY_VERDICT="launch_clock_error"
      report_target_launch_failure \
        "$candidate_row" \
        "$candidate_first_observed_ns" \
        "$candidate_observation_count" \
        "$candidate_stability_ns"
      return 2
    fi
    previous_observation_ns="$TARGET_LAUNCH_NOW_NS"

    if [[ "$readback_status" -ne 0 ]]; then
      if [[ -n "$candidate_row" ]]; then
        REJECTED_TRANSIENT_IDENTITY_COUNT=$((REJECTED_TRANSIENT_IDENTITY_COUNT + 1))
      fi
      candidate_row=""
      candidate_first_observed_ns=""
      candidate_observation_count=0
      candidate_stability_ns=0
      if ((TARGET_LAUNCH_NOW_NS >= discovery_deadline_ns)); then
        IDENTITY_VERDICT="launch_identity_readback_error"
        report_target_launch_failure "" "" 0 0
        return 2
      fi
    elif [[ "$launch_row_count" -eq 1 ]]; then
      row="${TARGET_LAUNCH_ROWS[0]}"
      ever_observed_candidate=true
      target_start_record="${row#*:}"
      if [[ "${target_start_record##*:}" -lt "$LAUNCH_REQUEST_EPOCH_SECONDS" ]]; then
        IDENTITY_VERDICT="launch_started_before_request"
        report_target_launch_failure \
          "$row" \
          "$TARGET_LAUNCH_NOW_NS" \
          1 \
          0
        return 1
      fi

      if [[ "$row" != "$candidate_row" ]]; then
        if [[ -n "$candidate_row" ]]; then
          REJECTED_TRANSIENT_IDENTITY_COUNT=$((REJECTED_TRANSIENT_IDENTITY_COUNT + 1))
        fi
        candidate_row="$row"
        candidate_first_observed_ns="$TARGET_LAUNCH_NOW_NS"
        candidate_observation_count=1
      else
        candidate_observation_count=$((candidate_observation_count + 1))
      fi

      candidate_stability_ns=$((TARGET_LAUNCH_NOW_NS - candidate_first_observed_ns))
      if [[ "$candidate_stability_ns" -ge "$required_stability_ns" ]]; then
        TARGET_PID="${candidate_row%%:*}"
        target_start_record="${candidate_row#*:}"
        TARGET_START_IDENTITY="${target_start_record%%:*}"
        TARGET_START_EPOCH_SECONDS="${target_start_record##*:}"
        TARGET_FIRST_OBSERVED_MONOTONIC_NS="$candidate_first_observed_ns"
        TARGET_QUALIFIED_MONOTONIC_NS="$TARGET_LAUNCH_NOW_NS"
        TARGET_OBSERVATION_COUNT="$candidate_observation_count"
        IDENTITY_VERDICT="matched"
        if publish_launch_receipt; then
          return 0
        fi
        IDENTITY_VERDICT="launch_receipt_write_failed"
        report_target_launch_failure \
          "$candidate_row" \
          "$candidate_first_observed_ns" \
          "$candidate_observation_count" \
          "$candidate_stability_ns"
        return 2
      fi
    else
      [[ "$launch_row_count" -gt 0 ]] \
        && ever_observed_candidate=true
      if [[ -n "$candidate_row" ]]; then
        REJECTED_TRANSIENT_IDENTITY_COUNT=$((REJECTED_TRANSIENT_IDENTITY_COUNT + 1))
      fi
      candidate_row=""
      candidate_first_observed_ns=""
      candidate_observation_count=0
      candidate_stability_ns=0
    fi

    if ((TARGET_LAUNCH_NOW_NS >= discovery_deadline_ns)); then
      if [[ "$launch_row_count" -ne 1 ]]; then
        IDENTITY_VERDICT="$([[ "$ever_observed_candidate" == true ]] \
          && printf launch_identity_not_stable \
          || printf launch_identity_not_observed)"
        report_target_launch_failure \
          "$candidate_row" \
          "$candidate_first_observed_ns" \
          "$candidate_observation_count" \
          "$candidate_stability_ns"
        return 1
      fi
      if [[ -z "$terminal_candidate_row" ]]; then
        terminal_candidate_row="$candidate_row"
      elif [[ "$candidate_row" != "$terminal_candidate_row" ]]; then
        IDENTITY_VERDICT="launch_identity_not_stable"
        report_target_launch_failure \
          "$candidate_row" \
          "$candidate_first_observed_ns" \
          "$candidate_observation_count" \
          "$candidate_stability_ns"
        return 1
      fi
    fi
    if ! test_process_is_live; then
      IDENTITY_VERDICT="launch_runner_exited"
      report_target_launch_failure \
        "$candidate_row" \
        "$candidate_first_observed_ns" \
        "$candidate_observation_count" \
        "$candidate_stability_ns"
      return 1
    fi
    if ! target_launch_sleep "$TARGET_LAUNCH_POLL_INTERVAL_SECONDS"; then
      IDENTITY_VERDICT="launch_observation_cancelled"
      report_target_launch_failure \
        "$candidate_row" \
        "$candidate_first_observed_ns" \
        "$candidate_observation_count" \
        "$candidate_stability_ns"
      return 130
    fi
  done
}

record_identity_binding() {
  local verdict="$1"
  local pid="${TARGET_PID:-0}"
  local start_identity="${TARGET_START_IDENTITY:-unavailable}"
  local start_epoch_seconds="${TARGET_START_EPOCH_SECONDS:-0}"
  local path_sha256

  path_sha256="$(printf '%s' "$EXPECTED_EXECUTABLE_PATH" | LC_ALL=C shasum -a 256 | awk '{print $1}')"
  IDENTITY_CHECK_COUNT=$((IDENTITY_CHECK_COUNT + 1))
  printf '%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$IDENTITY_CHECK_COUNT" \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    "$pid" \
    "$start_epoch_seconds" \
    "$start_identity" \
    "$path_sha256" \
    "$EXPECTED_EXECUTABLE_SHA256" \
    "$verdict" >>"$PID_BINDINGS_FILE"
}

probe_target_identity() {
  local rows=()
  local row
  local current_start_record
  local current_start_identity
  local current_start_epoch_seconds

  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    rows+=("$row")
  done < <(post_request_identity_rows)

  if [[ "${#rows[@]}" -ne 1 ]]; then
    IDENTITY_VERDICT="$([[ "${#rows[@]}" -gt 1 ]] && printf multiple_identity_matches || printf identity_match_lost)"
    return 1
  fi
  if [[ "${rows[0]%%:*}" != "$TARGET_PID" ]]; then
    IDENTITY_VERDICT="identity_match_replaced"
    return 1
  fi

  current_start_record="${rows[0]#*:}"
  current_start_identity="${current_start_record%%:*}"
  current_start_epoch_seconds="${current_start_record##*:}"
  if [[ "$current_start_identity" != "$TARGET_START_IDENTITY" ]]; then
    IDENTITY_VERDICT="pid_reused"
    return 1
  fi
  if [[ "$current_start_epoch_seconds" != "$TARGET_START_EPOCH_SECONDS" ]]; then
    IDENTITY_VERDICT="process_start_time_changed"
    return 1
  fi

  IDENTITY_VERDICT="matched"
  return 0
}

sample_flowtab() {
  local line
  local cpu
  local cpu_time
  local cpu_centiseconds
  local sample_monotonic_ns
  local rss

  if ! probe_target_identity; then
    return 1
  fi
  line="$(LC_ALL=C ps -p "$TARGET_PID" -o cputime= -o rss= 2>/dev/null | LC_ALL=C awk '{$1=$1; print}' || true)"
  if [[ -z "$line" ]]; then
    IDENTITY_VERDICT="sample_unavailable"
    return 1
  fi
  cpu_time="$(LC_ALL=C awk '{print $1}' <<<"$line")"
  rss="$(LC_ALL=C awk '{print $2}' <<<"$line")"
  if ! cpu_centiseconds="$(
    flowtab_perf_cpu_time_centiseconds "$cpu_time"
  )"; then
    IDENTITY_VERDICT="cpu_time_parse_error"
    return 1
  fi
  if ! sample_monotonic_ns="$(monotonic_ns)"; then
    IDENTITY_VERDICT="cpu_sample_clock_error"
    return 1
  fi

  if [[ -z "$TARGET_PREVIOUS_CPU_CENTISECONDS" ]]; then
    TARGET_PREVIOUS_CPU_CENTISECONDS="$cpu_centiseconds"
    TARGET_PREVIOUS_CPU_SAMPLE_MONOTONIC_NS="$sample_monotonic_ns"
    return 0
  fi
  if ! cpu="$(
    flowtab_perf_interval_cpu_percent \
      "$cpu_centiseconds" \
      "$TARGET_PREVIOUS_CPU_CENTISECONDS" \
      "$((sample_monotonic_ns - TARGET_PREVIOUS_CPU_SAMPLE_MONOTONIC_NS))"
  )"; then
    IDENTITY_VERDICT="cpu_interval_error"
    return 1
  fi
  TARGET_PREVIOUS_CPU_CENTISECONDS="$cpu_centiseconds"
  TARGET_PREVIOUS_CPU_SAMPLE_MONOTONIC_NS="$sample_monotonic_ns"

  SAMPLE_COUNT=$((SAMPLE_COUNT + 1))
  record_identity_binding "$IDENTITY_VERDICT"
  printf '%s,%s,%s,%s,%s\n' \
    "$SAMPLE_COUNT" \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    "$TARGET_PID" \
    "$cpu" \
    "$rss" >>"$SAMPLES_FILE"
}
