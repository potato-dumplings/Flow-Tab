#!/usr/bin/env bash

FLOWTAB_TAB_SWITCH_EVIDENCE_CONDITION="not_read"
FLOWTAB_TAB_SWITCH_PLANNED_SWITCH_COUNT=""
FLOWTAB_TAB_SWITCH_COMPLETED_SWITCH_COUNT=""
FLOWTAB_TAB_SWITCH_HOME_SWITCH_COUNT=""
FLOWTAB_TAB_SWITCH_LOGS_SWITCH_COUNT=""
FLOWTAB_TAB_SWITCH_SETTINGS_SWITCH_COUNT=""
FLOWTAB_TAB_SWITCH_ELAPSED_NANOSECONDS=""
FLOWTAB_TAB_SWITCH_STARTED_UPTIME_NANOSECONDS=""
FLOWTAB_TAB_SWITCH_COMPLETED_UPTIME_NANOSECONDS=""
FLOWTAB_TAB_SWITCH_ACTUAL_ELAPSED_SECONDS=""
FLOWTAB_TAB_SWITCH_THROUGHPUT=""
FLOWTAB_TAB_SWITCH_RUNTIME_LOG_LEVEL=""

flowtab_tab_switch_evidence_field() {
  local evidence_line="$1"
  local field_name="$2"
  local token

  for token in $evidence_line; do
    if [[ "$token" == "${field_name}="* ]]; then
      printf '%s\n' "${token#*=}"
      return 0
    fi
  done
  return 1
}

flowtab_tab_switch_parse_completion_evidence() {
  local app_log_path="$1"
  local expected_runtime_log_level="$2"
  local completed_line=""
  local completed_line_count=0
  local started_line=""
  local started_line_count=0
  local started_required_switch_count
  local started_runtime_log_level
  local started_started_uptime_nanoseconds
  local started_observed_uptime_nanoseconds
  local completed_started_uptime_nanoseconds
  local duration_satisfied
  local workload_satisfied

  FLOWTAB_TAB_SWITCH_EVIDENCE_CONDITION="missing"
  FLOWTAB_TAB_SWITCH_PLANNED_SWITCH_COUNT=""
  FLOWTAB_TAB_SWITCH_COMPLETED_SWITCH_COUNT=""
  FLOWTAB_TAB_SWITCH_HOME_SWITCH_COUNT=""
  FLOWTAB_TAB_SWITCH_LOGS_SWITCH_COUNT=""
  FLOWTAB_TAB_SWITCH_SETTINGS_SWITCH_COUNT=""
  FLOWTAB_TAB_SWITCH_ELAPSED_NANOSECONDS=""
  FLOWTAB_TAB_SWITCH_STARTED_UPTIME_NANOSECONDS=""
  FLOWTAB_TAB_SWITCH_COMPLETED_UPTIME_NANOSECONDS=""
  FLOWTAB_TAB_SWITCH_ACTUAL_ELAPSED_SECONDS=""
  FLOWTAB_TAB_SWITCH_THROUGHPUT=""
  FLOWTAB_TAB_SWITCH_RUNTIME_LOG_LEVEL=""

  [[ -f "$app_log_path" ]] || return 1

  while IFS= read -r evidence_line; do
    [[ "$evidence_line" == "FlowTabTabSwitchStressEvidence "* ]] || continue
    if [[ " $evidence_line " == *" phase=started "* ]]; then
      started_line="$evidence_line"
      started_line_count=$((started_line_count + 1))
    elif [[ " $evidence_line " == *" phase=completed "* ]]; then
      completed_line="$evidence_line"
      completed_line_count=$((completed_line_count + 1))
    fi
  done <"$app_log_path"

  if [[ "$started_line_count" -eq 0 || "$completed_line_count" -eq 0 ]]; then
    return 1
  fi
  if [[ "$started_line_count" -ne 1 || "$completed_line_count" -ne 1 ]]; then
    FLOWTAB_TAB_SWITCH_EVIDENCE_CONDITION="conflicting"
    return 2
  fi

  started_required_switch_count="$(
    flowtab_tab_switch_evidence_field "$started_line" requiredSwitches || true
  )"
  started_runtime_log_level="$(
    flowtab_tab_switch_evidence_field "$started_line" runtimeLogLevel || true
  )"
  started_started_uptime_nanoseconds="$(
    flowtab_tab_switch_evidence_field \
      "$started_line" startedAtUptimeNanoseconds || true
  )"
  started_observed_uptime_nanoseconds="$(
    flowtab_tab_switch_evidence_field \
      "$started_line" observedAtUptimeNanoseconds || true
  )"

  FLOWTAB_TAB_SWITCH_PLANNED_SWITCH_COUNT="$(
    flowtab_tab_switch_evidence_field "$completed_line" requiredSwitches || true
  )"
  FLOWTAB_TAB_SWITCH_COMPLETED_SWITCH_COUNT="$(
    flowtab_tab_switch_evidence_field "$completed_line" switches || true
  )"
  FLOWTAB_TAB_SWITCH_HOME_SWITCH_COUNT="$(
    flowtab_tab_switch_evidence_field "$completed_line" homeSwitches || true
  )"
  FLOWTAB_TAB_SWITCH_LOGS_SWITCH_COUNT="$(
    flowtab_tab_switch_evidence_field "$completed_line" logsSwitches || true
  )"
  FLOWTAB_TAB_SWITCH_SETTINGS_SWITCH_COUNT="$(
    flowtab_tab_switch_evidence_field "$completed_line" settingsSwitches || true
  )"
  FLOWTAB_TAB_SWITCH_ELAPSED_NANOSECONDS="$(
    flowtab_tab_switch_evidence_field "$completed_line" elapsedNanoseconds || true
  )"
  completed_started_uptime_nanoseconds="$(
    flowtab_tab_switch_evidence_field \
      "$completed_line" startedAtUptimeNanoseconds || true
  )"
  FLOWTAB_TAB_SWITCH_COMPLETED_UPTIME_NANOSECONDS="$(
    flowtab_tab_switch_evidence_field \
      "$completed_line" observedAtUptimeNanoseconds || true
  )"
  FLOWTAB_TAB_SWITCH_STARTED_UPTIME_NANOSECONDS="$started_started_uptime_nanoseconds"
  duration_satisfied="$(
    flowtab_tab_switch_evidence_field "$completed_line" durationSatisfied || true
  )"
  workload_satisfied="$(
    flowtab_tab_switch_evidence_field "$completed_line" workloadSatisfied || true
  )"
  FLOWTAB_TAB_SWITCH_RUNTIME_LOG_LEVEL="$(
    flowtab_tab_switch_evidence_field "$completed_line" runtimeLogLevel || true
  )"

  if [[ ! "$FLOWTAB_TAB_SWITCH_PLANNED_SWITCH_COUNT" =~ ^[0-9]+$ ]] \
    || [[ ! "$FLOWTAB_TAB_SWITCH_COMPLETED_SWITCH_COUNT" =~ ^[0-9]+$ ]] \
    || [[ ! "$FLOWTAB_TAB_SWITCH_ELAPSED_NANOSECONDS" =~ ^[0-9]+$ ]] \
    || [[ ! "$FLOWTAB_TAB_SWITCH_HOME_SWITCH_COUNT" =~ ^[0-9]+$ ]] \
    || [[ ! "$FLOWTAB_TAB_SWITCH_LOGS_SWITCH_COUNT" =~ ^[0-9]+$ ]] \
    || [[ ! "$FLOWTAB_TAB_SWITCH_SETTINGS_SWITCH_COUNT" =~ ^[0-9]+$ ]] \
    || [[ ! "$started_required_switch_count" =~ ^[0-9]+$ ]] \
    || [[ ! "$FLOWTAB_TAB_SWITCH_STARTED_UPTIME_NANOSECONDS" =~ ^[0-9]+$ ]] \
    || [[ ! "$started_observed_uptime_nanoseconds" =~ ^[0-9]+$ ]] \
    || [[ ! "$completed_started_uptime_nanoseconds" =~ ^[0-9]+$ ]] \
    || [[ ! "$FLOWTAB_TAB_SWITCH_COMPLETED_UPTIME_NANOSECONDS" =~ ^[0-9]+$ ]] \
    || [[ "$FLOWTAB_TAB_SWITCH_PLANNED_SWITCH_COUNT" -eq 0 ]] \
    || [[ "$FLOWTAB_TAB_SWITCH_ELAPSED_NANOSECONDS" -eq 0 ]] \
    || [[ "$FLOWTAB_TAB_SWITCH_STARTED_UPTIME_NANOSECONDS" -eq 0 ]] \
    || [[ "$started_required_switch_count" \
      -ne "$FLOWTAB_TAB_SWITCH_PLANNED_SWITCH_COUNT" ]] \
    || [[ "$started_observed_uptime_nanoseconds" \
      -ne "$FLOWTAB_TAB_SWITCH_STARTED_UPTIME_NANOSECONDS" ]] \
    || [[ "$completed_started_uptime_nanoseconds" \
      -ne "$FLOWTAB_TAB_SWITCH_STARTED_UPTIME_NANOSECONDS" ]] \
    || [[ "$FLOWTAB_TAB_SWITCH_COMPLETED_UPTIME_NANOSECONDS" \
      -le "$FLOWTAB_TAB_SWITCH_STARTED_UPTIME_NANOSECONDS" ]] \
    || [[ $((
      FLOWTAB_TAB_SWITCH_COMPLETED_UPTIME_NANOSECONDS
        - FLOWTAB_TAB_SWITCH_STARTED_UPTIME_NANOSECONDS
    )) -ne "$FLOWTAB_TAB_SWITCH_ELAPSED_NANOSECONDS" ]] \
    || [[ "$FLOWTAB_TAB_SWITCH_COMPLETED_SWITCH_COUNT" \
      -ne "$FLOWTAB_TAB_SWITCH_PLANNED_SWITCH_COUNT" ]] \
    || [[ "$FLOWTAB_TAB_SWITCH_HOME_SWITCH_COUNT" -eq 0 ]] \
    || [[ "$FLOWTAB_TAB_SWITCH_LOGS_SWITCH_COUNT" -eq 0 ]] \
    || [[ "$FLOWTAB_TAB_SWITCH_SETTINGS_SWITCH_COUNT" -eq 0 ]] \
    || [[ $((
      FLOWTAB_TAB_SWITCH_HOME_SWITCH_COUNT
        + FLOWTAB_TAB_SWITCH_LOGS_SWITCH_COUNT
        + FLOWTAB_TAB_SWITCH_SETTINGS_SWITCH_COUNT
    )) -ne "$FLOWTAB_TAB_SWITCH_COMPLETED_SWITCH_COUNT" ]] \
    || [[ "$duration_satisfied" != true ]] \
    || [[ "$workload_satisfied" != true ]] \
    || [[ ! "$FLOWTAB_TAB_SWITCH_RUNTIME_LOG_LEVEL" \
      =~ ^(DEBUG|INFO|WARN|ERROR)$ ]] \
    || [[ "$started_runtime_log_level" \
      != "$FLOWTAB_TAB_SWITCH_RUNTIME_LOG_LEVEL" ]] \
    || [[ "$FLOWTAB_TAB_SWITCH_RUNTIME_LOG_LEVEL" \
      != "$expected_runtime_log_level" ]]; then
    FLOWTAB_TAB_SWITCH_EVIDENCE_CONDITION="conflicting"
    return 2
  fi

  FLOWTAB_TAB_SWITCH_ACTUAL_ELAPSED_SECONDS="$(
    LC_ALL=C awk -v nanoseconds="$FLOWTAB_TAB_SWITCH_ELAPSED_NANOSECONDS" \
      'BEGIN { printf "%.6f", nanoseconds / 1000000000 }'
  )"
  FLOWTAB_TAB_SWITCH_THROUGHPUT="$(
    LC_ALL=C awk \
      -v switches="$FLOWTAB_TAB_SWITCH_COMPLETED_SWITCH_COUNT" \
      -v nanoseconds="$FLOWTAB_TAB_SWITCH_ELAPSED_NANOSECONDS" \
      'BEGIN { printf "%.6f", switches * 1000000000 / nanoseconds }'
  )"
  FLOWTAB_TAB_SWITCH_EVIDENCE_CONDITION="valid"
}
