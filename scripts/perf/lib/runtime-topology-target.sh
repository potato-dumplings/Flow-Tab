#!/usr/bin/env bash

# The caller resolves path and identity intent before these functions inspect live processes.
monotonic_ns() {
  "$MONOTONIC_CLOCK"
}

process_start_record() {
  local pid="$1"
  local started_at
  local started_epoch_seconds
  local start_identity

  started_at="$(LC_ALL=C ps -p "$pid" -o lstart= 2>/dev/null | LC_ALL=C awk '{$1=$1; print}' || true)"
  [[ -n "$started_at" ]] || return 1
  started_epoch_seconds="$(LC_ALL=C /bin/date -j -f '%a %b %e %T %Y' "$started_at" '+%s' 2>/dev/null || true)"
  [[ "$started_epoch_seconds" =~ ^[0-9]+$ ]] || return 1
  start_identity="$(printf '%s' "$started_at" | LC_ALL=C shasum -a 256 | awk '{print $1}')"
  printf '%s:%s' "$start_identity" "$started_epoch_seconds"
}

process_path_matches_expected() {
  local pid="$1"
  local command_name
  local command_line

  command_name="$(LC_ALL=C ps -p "$pid" -o comm= 2>/dev/null | sed 's/^[[:space:]]*//' || true)"
  if [[ "$command_name" == "$EXPECTED_EXECUTABLE_PATH" ]]; then
    return 0
  fi

  command_line="$(LC_ALL=C ps -p "$pid" -o command= 2>/dev/null | sed 's/^[[:space:]]*//' || true)"
  [[ "$command_line" == "$EXPECTED_EXECUTABLE_PATH" || "$command_line" == "$EXPECTED_EXECUTABLE_PATH "* ]]
}

matching_identity_rows() {
  local pid
  local start_record
  local current_executable_sha256

  current_executable_sha256="$(LC_ALL=C shasum -a 256 "$EXPECTED_EXECUTABLE_PATH" 2>/dev/null | awk '{print $1}' || true)"
  [[ "$current_executable_sha256" == "$EXPECTED_EXECUTABLE_SHA256" ]] || return 0

  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    process_is_running "$pid" || continue
    process_path_matches_expected "$pid" || continue
    start_record="$(process_start_record "$pid" || true)"
    [[ -n "$start_record" ]] || continue
    printf '%s:%s\n' "$pid" "$start_record"
  done < <(pgrep -x "$EXPECTED_EXECUTABLE_NAME" 2>/dev/null || true)
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

  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    is_preexisting_target_identity "$row" || printf '%s\n' "$row"
  done < <(matching_identity_rows)
}

capture_preexisting_target_identities() {
  PREEXISTING_TARGET_IDENTITIES="$(matching_identity_rows)"
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

await_target_launch() {
  local attempt=0
  local row
  local now_monotonic_ns
  local target_start_record
  local candidate_row=""
  local candidate_first_observed_ns=""
  local candidate_observation_count=0
  local candidate_stability_ns=0
  local required_stability_ns=$((TARGET_STABILITY_WINDOW_MILLISECONDS * 1000000))
  local new_rows=()

  while test_process_is_live && [[ "$attempt" -lt 450 ]]; do
    new_rows=()
    while IFS= read -r row; do
      [[ -n "$row" ]] || continue
      new_rows+=("$row")
    done < <(post_request_identity_rows)
    now_monotonic_ns="$(monotonic_ns)"

    if [[ "${#new_rows[@]}" -eq 1 ]]; then
      row="${new_rows[0]}"
      target_start_record="${row#*:}"
      if [[ "${target_start_record##*:}" -lt "$LAUNCH_REQUEST_EPOCH_SECONDS" ]]; then
        IDENTITY_VERDICT="launch_started_before_request"
        return 1
      fi

      if [[ "$row" != "$candidate_row" ]]; then
        if [[ -n "$candidate_row" ]]; then
          REJECTED_TRANSIENT_IDENTITY_COUNT=$((REJECTED_TRANSIENT_IDENTITY_COUNT + 1))
        fi
        candidate_row="$row"
        candidate_first_observed_ns="$now_monotonic_ns"
        candidate_observation_count=1
      else
        candidate_observation_count=$((candidate_observation_count + 1))
      fi

      candidate_stability_ns=$((now_monotonic_ns - candidate_first_observed_ns))
      if [[ "$candidate_stability_ns" -ge "$required_stability_ns" ]]; then
        TARGET_PID="${candidate_row%%:*}"
        target_start_record="${candidate_row#*:}"
        TARGET_START_IDENTITY="${target_start_record%%:*}"
        TARGET_START_EPOCH_SECONDS="${target_start_record##*:}"
        TARGET_FIRST_OBSERVED_MONOTONIC_NS="$candidate_first_observed_ns"
        TARGET_QUALIFIED_MONOTONIC_NS="$now_monotonic_ns"
        TARGET_OBSERVATION_COUNT="$candidate_observation_count"
        IDENTITY_VERDICT="matched"
        publish_launch_receipt
        return 0
      fi
    else
      if [[ -n "$candidate_row" ]]; then
        REJECTED_TRANSIENT_IDENTITY_COUNT=$((REJECTED_TRANSIENT_IDENTITY_COUNT + 1))
      fi
      candidate_row=""
      candidate_first_observed_ns=""
      candidate_observation_count=0
    fi

    sleep 0.1
    attempt=$((attempt + 1))
  done

  if [[ -n "$candidate_row" ]]; then
    IDENTITY_VERDICT="launch_identity_not_stable"
  else
    IDENTITY_VERDICT="launch_identity_not_observed"
  fi
  return 1
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
  local rss

  if ! probe_target_identity; then
    return 1
  fi
  line="$(LC_ALL=C ps -p "$TARGET_PID" -o %cpu= -o rss= 2>/dev/null | LC_ALL=C awk '{$1=$1; print}' || true)"
  if [[ -z "$line" ]]; then
    IDENTITY_VERDICT="sample_unavailable"
    return 1
  fi
  cpu="$(LC_ALL=C awk '{print $1}' <<<"$line")"
  rss="$(LC_ALL=C awk '{print $2}' <<<"$line")"

  SAMPLE_COUNT=$((SAMPLE_COUNT + 1))
  record_identity_binding "$IDENTITY_VERDICT"
  printf '%s,%s,%s,%s,%s\n' \
    "$SAMPLE_COUNT" \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    "$TARGET_PID" \
    "$cpu" \
    "$rss" >>"$SAMPLES_FILE"
}
